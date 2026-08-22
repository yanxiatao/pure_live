import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/modules/multiview/cells/multiview_cell_player.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';

/// 记录调用序列的假单格播放器。
///
/// 所有操作按「名称:动作」写入共享日志，用于断言释放顺序与静音互斥。
class _RecordingPlayer implements MultiviewCellPlayerHandle {
  _RecordingPlayer(this._log, this.name);

  final List<String> _log;
  final String name;

  double volume = 1.0;
  int startCalls = 0;
  Object? startError;

  @override
  VideoController? get videoController => null;

  @override
  Future<void> start({required String url, required Map<String, String> headers}) async {
    _log.add('$name:start');
    startCalls++;
    // 契约：一律静音起播。
    volume = 0.0;
    final error = startError;
    if (error != null) throw error;
  }

  @override
  Future<void> setMuted(bool muted) async {
    _log.add('$name:mute:${muted ? 'on' : 'off'}');
    volume = muted ? 0.0 : 1.0;
  }

  @override
  Future<void> pause() async {
    _log.add('$name:pause');
  }

  @override
  Future<void> disposeVideoController() async {
    _log.add('$name:vcDispose');
  }

  @override
  Future<void> disposePlayer() async {
    _log.add('$name:pDispose');
  }
}

/// 测试装配体：假工厂 + 假解析器 + 可控的解析门闩。
class _Harness {
  _Harness() {
    controller = MultiviewController(
      playerFactory: _factory,
      streamResolver: _resolver,
      pauseGlobalPlayback: () async => globalPauseCalls++,
    );
  }

  final List<String> log = <String>[];
  final List<_RecordingPlayer> players = <_RecordingPlayer>[];
  final List<(int, int)> requestedSizes = <(int, int)>[];
  final Map<String, Completer<void>> gates = <String, Completer<void>>{};
  final Set<String> resolveFailures = <String>{};
  int globalPauseCalls = 0;
  int playerSeq = 0;

  /// 下一个工厂产物的起播异常（消费一次）。
  Object? nextStartError;

  late final MultiviewController controller;

  MultiviewCellPlayerHandle _factory({required int renderWidth, required int renderHeight}) {
    requestedSizes.add((renderWidth, renderHeight));
    final player = _RecordingPlayer(log, 'p${playerSeq++}');
    final error = nextStartError;
    if (error != null) {
      player.startError = error;
      nextStartError = null;
    }
    players.add(player);
    return player;
  }

  Future<MultiviewStreamSource> _resolver(LiveRoom room) async {
    final id = room.roomId!;
    if (resolveFailures.contains(id)) {
      throw StateError('resolver boom for $id');
    }
    final gate = gates[id];
    if (gate != null) {
      await gate.future;
    }
    return MultiviewStreamSource(url: 'https://stream/$id', headers: const {'user-agent': 'test'});
  }

  /// 让事件循环排空微任务，使后台释放/静音序列完成。
  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

LiveRoom _room(String id) => LiveRoom(roomId: id, platform: 'bilibili');

void main() {
  group('MultiviewController', () {
    test('assignRoom 走 empty→resolving→playing 并自动成为音频焦点', () async {
      final harness = _Harness();
      final controller = harness.controller;
      final gate = Completer<void>();
      harness.gates['r1'] = gate;

      final assigning = controller.assignRoom(0, _room('r1'));
      await harness.pump();
      expect(controller.cells[0].status, MultiviewCellStatus.resolving);

      gate.complete();
      await assigning;

      expect(controller.cells[0].status, MultiviewCellStatus.playing);
      expect(controller.cells[0].errorKind, isNull);
      expect(controller.cells[0].errorDetail, isNull);
      expect(controller.cells[0].room?.roomId, 'r1');
      expect(controller.audioFocusIndex, 0);
      // 静音起播后因获得焦点而恢复音量。
      expect(harness.players[0].volume, 1.0);

      // 第二格成功后抢占焦点，第一格被静音。
      await controller.assignRoom(1, _room('r2'));
      expect(controller.audioFocusIndex, 1);
      expect(harness.players[0].volume, 0.0);
      expect(harness.players[1].volume, 1.0);
    });

    test('assignRoom 按布局均分结果固定每格渲染分辨率', () async {
      final harness = _Harness();
      final controller = harness.controller;

      // 初始布局 quad：无窗口上下文时基线 1280x720 → 每格 640x360。
      await controller.assignRoom(0, _room('r1'));
      expect(harness.requestedSizes.last, (640, 360));

      await controller.setLayout(MultiviewLayout.dual);
      await controller.assignRoom(1, _room('r2'));
      // dual（1 行 x 2 列）：640x720。
      expect(harness.requestedSizes.last, (640, 720));
    });

    test('setAudioFocus 切换后新旧格静音状态互斥', () async {
      final harness = _Harness();
      final controller = harness.controller;
      await controller.assignRoom(0, _room('r1'));
      await controller.assignRoom(1, _room('r2'));
      expect(controller.audioFocusIndex, 1);

      controller.setAudioFocus(0);
      await harness.pump();

      expect(controller.audioFocusIndex, 0);
      expect(harness.players[0].volume, 1.0);
      expect(harness.players[1].volume, 0.0);
      expect(harness.log.where((e) => e == 'p0:mute:off'), isNotEmpty);
      expect(harness.log.where((e) => e == 'p1:mute:on'), isNotEmpty);
    });

    test('removeCell 按严格顺序释放并回到 empty', () async {
      final harness = _Harness();
      final controller = harness.controller;
      await controller.assignRoom(0, _room('r1'));
      await controller.assignRoom(1, _room('r2'));
      harness.log.clear();

      controller.removeCell(0);
      await harness.pump();

      final releaseOrder = harness.log.where((e) => e.startsWith('p0:')).toList();
      expect(releaseOrder, ['p0:pause', 'p0:vcDispose', 'p0:pDispose']);
      expect(controller.cells[0].status, MultiviewCellStatus.empty);
      expect(controller.cells[0].videoController, isNull);
      // 焦点从被移除的格转移到仍在播放的格。
      expect(controller.audioFocusIndex, 1);
    });

    test('setLayout quad→dual 保留前两格播放状态并释放第三/四格', () async {
      final harness = _Harness();
      final controller = harness.controller;
      for (var i = 0; i < 4; i++) {
        await controller.assignRoom(i, _room('r$i'));
      }
      harness.log.clear();

      await controller.setLayout(MultiviewLayout.dual);

      expect(controller.layout.value, MultiviewLayout.dual);
      expect(controller.cells.length, MultiviewLayout.dual.capacity);
      expect(controller.cells[0].status, MultiviewCellStatus.playing);
      expect(controller.cells[0].room?.roomId, 'r0');
      expect(controller.cells[1].status, MultiviewCellStatus.playing);
      expect(controller.cells[1].room?.roomId, 'r1');
      for (final name in ['p2', 'p3']) {
        final order = harness.log.where((e) => e.startsWith('$name:')).toList();
        expect(order, ['$name:pause', '$name:vcDispose', '$name:pDispose']);
      }
      expect(controller.audioFocusIndex, lessThan(2));
    });

    test('disposeAll 释放全部格且 cells 回到 empty', () async {
      final harness = _Harness();
      final controller = harness.controller;
      await controller.assignRoom(0, _room('r1'));
      await controller.assignRoom(2, _room('r2'));

      await controller.disposeAll();

      expect(controller.cells.length, MultiviewLayout.quad.capacity);
      for (final cell in controller.cells) {
        expect(cell.status, MultiviewCellStatus.empty);
        expect(cell.room, isNull);
      }
      for (final player in harness.players) {
        final order = harness.log.where((e) => e.startsWith('${player.name}:')).toList();
        final releaseStart = order.indexOf('${player.name}:pause');
        expect(releaseStart, greaterThan(0), reason: '${player.name} 应先起播再释放');
        expect(order.sublist(releaseStart), [
          '${player.name}:pause',
          '${player.name}:vcDispose',
          '${player.name}:pDispose',
        ]);
      }
      expect(controller.audioFocusIndex, 0);
    });

    test('assignRoom 解析失败置 error 且不创建播放器', () async {
      final harness = _Harness();
      final controller = harness.controller;
      harness.resolveFailures.add('bad');

      await controller.assignRoom(0, _room('bad'));

      expect(controller.cells[0].status, MultiviewCellStatus.error);
      expect(controller.cells[0].errorKind, MultiviewCellErrorKind.resolveFailure);
      expect(controller.cells[0].errorDetail, contains('resolver boom for bad'));
      expect(harness.players, isEmpty);
    });

    test('assignRoom 起播失败置 error 并按序释放已创建的播放器', () async {
      final harness = _Harness();
      final controller = harness.controller;
      harness.nextStartError = StateError('open boom');

      await controller.assignRoom(0, _room('r1'));

      expect(controller.cells[0].status, MultiviewCellStatus.error);
      expect(controller.cells[0].errorKind, MultiviewCellErrorKind.startFailure);
      expect(controller.cells[0].errorDetail, contains('open boom'));
      final order = harness.log.where((e) => e.startsWith('p0:')).toList();
      expect(order, ['p0:start', 'p0:pause', 'p0:vcDispose', 'p0:pDispose']);
      // 失败后该格不持有播放器句柄，可重新分配。
      await controller.assignRoom(0, _room('r2'));
      expect(controller.cells[0].status, MultiviewCellStatus.playing);
      expect(controller.cells[0].errorKind, isNull);
    });

    test('向已占用格重复 assignRoom 先按序释放旧播放器', () async {
      final harness = _Harness();
      final controller = harness.controller;
      await controller.assignRoom(0, _room('r1'));
      harness.log.clear();

      await controller.assignRoom(0, _room('r2'));

      final order = harness.log.where((e) => e.startsWith('p0:')).toList();
      expect(order, ['p0:pause', 'p0:vcDispose', 'p0:pDispose']);
      expect(controller.cells[0].status, MultiviewCellStatus.playing);
      expect(controller.cells[0].room?.roomId, 'r2');
      expect(harness.players.length, 2);
    });

    test('onInit 暂停全局播放器恰好一次', () async {
      final harness = _Harness();
      final controller = harness.controller;

      controller.onInit();

      await harness.pump();
      expect(harness.globalPauseCalls, 1);
    });
  });
}
