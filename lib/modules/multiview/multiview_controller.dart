import 'dart:async';
import 'dart:developer' as developer;

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';
import 'package:pure_live/modules/multiview/cells/multiview_cell_player.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';

/// 房间对象 → 可播放源解析器。
///
/// 复用站点适配器既有入口（getRoomDetail/getPlayQualites/getPlayUrls），
/// 禁止在 multiview 内复制解析逻辑；测试注入假实现。
/// v1 固定取首个清晰度（TODO: 每格清晰度选择）。
typedef MultiviewStreamResolver = Future<MultiviewStreamSource> Function(LiveRoom room);

/// 进入 multiview 时暂停全局播放器的钩子。
///
/// multiview 自建每格播放器实例，与全局单实例播放系统并存；
/// 两者同时出声不可接受，进入时必须先让全局侧静默。注入以便测试。
typedef MultiviewGlobalPauseHook = Future<void> Function();

/// 多画面同看控制器（无头核心层）。
///
/// 架构决策：
/// - 绕开 PlayerManager/GlobalPlayerService/PlayerPool 的全局单实例假设，
///   通过 [MultiviewCellPlayerFactory] 为每格创建独立 media_kit 实例；
/// - 仅活跃格出声（音频焦点模型），新起播成功的格自动成为焦点；
/// - 所有释放（removeCell/setLayout 缩容/disposeAll）走同一条
///   「pause → 销毁渲染控制器 → 销毁播放内核」路径。
///
/// TODO: 弹幕、每格清晰度选择、布局切换后重设渲染分辨率、会话持久化。
class MultiviewController extends GetxController {
  MultiviewController({
    MultiviewCellPlayerFactory? playerFactory,
    MultiviewStreamResolver? streamResolver,
    MultiviewGlobalPauseHook? pauseGlobalPlayback,
  }) : _playerFactory = playerFactory ?? _defaultPlayerFactory,
       _streamResolver = streamResolver ?? _defaultStreamResolver,
       _pauseGlobalPlayback = pauseGlobalPlayback ?? _defaultPauseGlobalPlayback;

  /// 生产环境每格播放器工厂。
  static MultiviewCellPlayerHandle _defaultPlayerFactory({required int renderWidth, required int renderHeight}) {
    return MultiviewCellPlayer(renderWidth: renderWidth, renderHeight: renderHeight);
  }

  /// 生产环境解析器：完整复用 LivePlayController 同一条站点解析链路。
  static Future<MultiviewStreamSource> _defaultStreamResolver(LiveRoom room) async {
    final platform = room.platform!;
    final site = Sites.of(platform);

    final detail = await site.liveSite.getRoomDetail(roomId: room.roomId!, platform: platform);
    final qualities = await site.liveSite.getPlayQualites(detail: detail);
    if (qualities.isEmpty) {
      throw StateError('multiview: no play qualities for $platform/${room.roomId}');
    }

    // ponytail: v1 固定取最高档（列表首项），每格清晰度选择留待后续。
    final urls = await site.liveSite.getPlayUrls(detail: detail, quality: qualities.first);
    if (urls.isEmpty) {
      throw StateError('multiview: no play urls for $platform/${room.roomId}');
    }

    final headers = await PlayerController.resolvePlaybackHeaders(site: site, room: detail);
    return MultiviewStreamSource(url: urls.first, headers: headers);
  }

  /// 生产环境全局播放静默钩子。
  ///
  /// 全局播放服务尚未初始化说明当前没有全局会话，无需处理。
  /// app 浮窗激活时仅 pause 会留下冻结画面悬浮在网格上方，用户点浮窗播放
  /// 即双出声；语义与 AppNavigator.toLiveRoomDetail 进入直播间前一致，
  /// 直接关闭浮窗。其余情况维持暂停行为。
  static Future<void> _defaultPauseGlobalPlayback() async {
    final service = GlobalPlayerService.instance;
    if (!service.initialized) return;
    final manager = service.player;
    if (manager.isAppFloatingActive) {
      await manager.closeAppFloating();
      return;
    }
    if (manager.isPlayingNow) {
      await manager.pause();
    }
  }

  /// 当前布局；初始为四画面（本功能的核心形态）。
  final Rx<MultiviewLayout> layout = MultiviewLayout.quad.obs;

  /// 单格状态列表，长度恒等于 [layout] 容量。
  final RxList<MultiviewCellState> cells = RxList<MultiviewCellState>(
    List.generate(MultiviewLayout.quad.capacity, MultiviewCellState.empty),
  );

  /// 每格播放器句柄，与 cells 一一对应；空格为 null。
  final List<MultiviewCellPlayerHandle?> _players = List<MultiviewCellPlayerHandle?>.generate(
    MultiviewLayout.quad.capacity,
    (_) => null,
    growable: true,
  );

  /// 每格加载纪元，用于丢弃迟到的解析/起播结果（竞态防护）。
  final List<int> _cellEpochs = List<int>.generate(MultiviewLayout.quad.capacity, (_) => 0, growable: true);

  /// 音频焦点格下标，默认 0。
  int _audioFocusIndex = 0;

  final MultiviewCellPlayerFactory _playerFactory;
  final MultiviewStreamResolver _streamResolver;
  final MultiviewGlobalPauseHook _pauseGlobalPlayback;

  /// 当前持有音频焦点的格子下标。
  int get audioFocusIndex => _audioFocusIndex;

  @override
  void onInit() {
    super.onInit();
    // 进入 multiview 时先让全局播放器静默，避免双系统同时出声。
    unawaited(
      _pauseGlobalPlayback().catchError((Object error, StackTrace stackTrace) {
        developer.log(
          'MultiviewController: pause global playback failed',
          name: 'MultiviewController',
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  /// 切换布局。
  ///
  /// 缩容时按同一条释放路径销毁多余格；保留前 N 格的播放状态不重建。
  /// 扩容时追加空白格。已有格不重设渲染分辨率（TODO: 布局切换后重设，
  /// 当前接受暂时模糊）。
  Future<void> setLayout(MultiviewLayout newLayout) async {
    if (newLayout == layout.value) return;
    final capacity = newLayout.capacity;

    for (var i = capacity; i < _players.length; i++) {
      await _releaseSlot(i);
    }

    while (cells.length > capacity) {
      cells.removeLast();
      _players.removeLast();
      _cellEpochs.removeLast();
    }
    while (cells.length < capacity) {
      cells.add(MultiviewCellState.empty(cells.length));
      _players.add(null);
      _cellEpochs.add(0);
    }

    layout.value = newLayout;

    if (_audioFocusIndex >= capacity) {
      _refocusToFirstPlaying(fallback: 0);
    }
  }

  /// 向指定格分配房间并起播；成功后该格自动成为音频焦点。
  ///
  /// 若该格已被占用，先走统一释放路径再重新分配。
  /// 解析失败/起播失败置 status=error 并记录错误种类与原始详情，不吞异常。
  Future<void> assignRoom(int cellIndex, LiveRoom room) async {
    RangeError.checkValidIndex(cellIndex, cells, 'cellIndex');
    if (room.platform == null || !Sites.isSupported(room.platform!)) {
      throw ArgumentError.value(room.platform, 'room.platform', 'Unsupported live platform');
    }
    if (room.roomId == null || room.roomId!.isEmpty) {
      throw ArgumentError.value(room.roomId, 'room.roomId', 'Room id is required');
    }

    // 先推进纪元使该格任何在途解析/起播失效，再释放旧句柄。
    // 旧句柄的销毁不再推进纪元：本此分配已独占该格。
    final epoch = ++_cellEpochs[cellIndex];
    final previousHandle = _players[cellIndex];
    _players[cellIndex] = null;
    if (previousHandle != null) {
      await _teardown(previousHandle);
    }

    _updateCell(
      cellIndex,
      cells[cellIndex].copyWith(
        room: room,
        status: MultiviewCellStatus.resolving,
        clearError: true,
        clearVideoController: true,
      ),
    );

    final MultiviewStreamSource source;
    try {
      source = await _streamResolver(room);
    } catch (error, stackTrace) {
      developer.log(
        'MultiviewController: resolve stream failed for ${room.platform}/${room.roomId}',
        name: 'MultiviewController',
        error: error,
        stackTrace: stackTrace,
      );
      _failCell(cellIndex, epoch, MultiviewCellErrorKind.resolveFailure, error.toString());
      return;
    }
    if (_isStale(cellIndex, epoch)) return;

    final target = _resolveRenderTarget(layout.value);
    final handle = _playerFactory(renderWidth: target.width.toInt(), renderHeight: target.height.toInt());

    try {
      await handle.start(url: source.url, headers: source.headers);
    } catch (error, stackTrace) {
      developer.log(
        'MultiviewController: start playback failed for ${room.platform}/${room.roomId}',
        name: 'MultiviewController',
        error: error,
        stackTrace: stackTrace,
      );
      await _teardown(handle);
      _failCell(cellIndex, epoch, MultiviewCellErrorKind.startFailure, error.toString());
      return;
    }
    if (_isStale(cellIndex, epoch)) {
      await _teardown(handle);
      return;
    }

    _players[cellIndex] = handle;
    _updateCell(
      cellIndex,
      cells[cellIndex].copyWith(status: MultiviewCellStatus.playing, videoController: handle.videoController),
    );
    setAudioFocus(cellIndex);
  }

  /// 释放指定格并回到 empty。
  ///
  /// 契约为同步签名：状态立即回到 empty，原生释放按同一条路径在后台完成。
  void removeCell(int cellIndex) {
    RangeError.checkValidIndex(cellIndex, cells, 'cellIndex');
    final handle = _captureSlot(cellIndex);
    if (_audioFocusIndex == cellIndex) {
      _refocusToFirstPlaying(fallback: cellIndex);
    }
    if (handle != null) {
      unawaited(_teardown(handle));
    }
  }

  /// 切换音频焦点：仅目标格出声，其余全部静音。
  void setAudioFocus(int cellIndex) {
    RangeError.checkValidIndex(cellIndex, cells, 'cellIndex');
    final previous = _audioFocusIndex;
    _audioFocusIndex = cellIndex;
    // 缩容后旧焦点槽位可能已不存在，此时无需静音旧格。
    if (previous != cellIndex && previous >= 0 && previous < _players.length) {
      final old = _players[previous];
      if (old != null) {
        unawaited(old.setMuted(true));
      }
    }
    final next = _players[cellIndex];
    if (next != null) {
      unawaited(next.setMuted(false));
    }
  }

  /// 释放全部格子（页面 onClose 调用），cells 全部回到 empty。
  Future<void> disposeAll() async {
    for (var i = 0; i < _players.length; i++) {
      await _releaseSlot(i);
      _updateCell(i, MultiviewCellState.empty(i));
    }
    _audioFocusIndex = 0;
  }

  @override
  void onClose() {
    unawaited(disposeAll());
    super.onClose();
  }

  bool _isStale(int cellIndex, int epoch) => cellIndex >= _cellEpochs.length || _cellEpochs[cellIndex] != epoch;

  /// 记录失败种类与原始错误文本；展示文案由 UI 按语言映射，核心层不拼自然语言。
  void _failCell(int cellIndex, int epoch, MultiviewCellErrorKind kind, String detail) {
    if (_isStale(cellIndex, epoch)) return;
    _updateCell(
      cellIndex,
      cells[cellIndex].copyWith(status: MultiviewCellStatus.error, errorKind: kind, errorDetail: detail),
    );
  }

  /// 统一释放路径：捕获句柄置空 → pause → 销毁渲染控制器 → 销毁播放内核。
  Future<void> _releaseSlot(int cellIndex) async {
    final handle = _captureSlot(cellIndex);
    if (handle != null) {
      await _teardown(handle);
    }
  }

  /// 同步捕获并清空一格：句柄置空、纪元推进、状态回到 empty。
  MultiviewCellPlayerHandle? _captureSlot(int cellIndex) {
    final handle = _players[cellIndex];
    _players[cellIndex] = null;
    _cellEpochs[cellIndex]++;
    _updateCell(cellIndex, MultiviewCellState.empty(cellIndex));
    return handle;
  }

  Future<void> _teardown(MultiviewCellPlayerHandle handle) async {
    await handle.pause();
    await handle.disposeVideoController();
    await handle.disposePlayer();
  }

  /// 焦点格失效后转移到第一个播放中的格；没有则落到 [fallback]。
  void _refocusToFirstPlaying({required int fallback}) {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].status == MultiviewCellStatus.playing && _players[i] != null) {
        setAudioFocus(i);
        return;
      }
    }
    _audioFocusIndex = fallback;
  }

  void _updateCell(int cellIndex, MultiviewCellState state) {
    cells[cellIndex] = state;
  }

  /// 按当前布局把屏幕物理像素均分，得到每格固定渲染分辨率。
  Size _resolveRenderTarget(MultiviewLayout l) {
    final screen = _probeScreenMetrics();
    // ponytail: 无窗口树（纯 Dart 测试/极早期调用）退回 720p 基线，
    // 保证分辨率计算可确定性验证。
    final width = ((screen.logical.width * screen.dpr) / l.columns).round().clamp(320, 3840);
    final height = ((screen.logical.height * screen.dpr) / l.rows).round().clamp(180, 2160);
    return Size(width.toDouble(), height.toDouble());
  }

  /// 探测当前窗口的逻辑尺寸与像素密度。
  ///
  /// GetX 的 Get.context 在根路由未挂载时抛出而非返回 null（vendored 实现），
  /// 该场景只出现在无窗口树的纯 Dart 测试或极早期调用，属预期环境状态，
  /// 记录后退回 720p 基线，不视为错误。
  ({Size logical, double dpr}) _probeScreenMetrics() {
    try {
      final context = Get.context;
      if (context == null) {
        return (logical: const Size(1280, 720), dpr: 1.0);
      }
      return (logical: MediaQuery.sizeOf(context), dpr: MediaQuery.devicePixelRatioOf(context));
    } catch (error, stackTrace) {
      developer.log(
        'MultiviewController: window tree unavailable, using baseline render metrics',
        name: 'MultiviewController',
        error: error,
        stackTrace: stackTrace,
      );
      return (logical: const Size(1280, 720), dpr: 1.0);
    }
  }
}
