import 'dart:developer' as developer;

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:pure_live/common/global/platform_utils.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/player/adapters/media_kit_adapter.dart';

/// multiview 单格播放器契约。
///
/// 将操作拆分为 pause / disposeVideoController / disposePlayer 三个独立步骤，
/// 是为了把「pause → 销毁渲染控制器 → 销毁播放内核」的严格释放顺序
/// 收敛在控制器的一条释放路径中；真实实现包装 media_kit，测试注入假实现。
abstract interface class MultiviewCellPlayerHandle {
  /// 该格的渲染控制器，供 UI 的 Video widget 使用；尚未创建时为 null。
  VideoController? get videoController;

  /// 创建播放内核与渲染控制器并静音起播。
  ///
  /// 音频策略：所有格一律以音量 0 起播，只有获得音频焦点的格才会恢复音量。
  Future<void> start({required String url, required Map<String, String> headers});

  /// 静音/取消静音（音频焦点切换时由控制器调用）。
  Future<void> setMuted(bool muted);

  /// 释放步骤 1：暂停解码与输出。
  Future<void> pause();

  /// 释放步骤 2：销毁渲染控制器（Flutter 侧纹理引用）。
  Future<void> disposeVideoController();

  /// 释放步骤 3：销毁播放内核（native 纹理随 Player.dispose 摘除）。
  Future<void> disposePlayer();
}

/// 单格播放器工厂：按目标渲染分辨率创建一格播放器。
///
/// 生产环境绑定 [MultiviewCellPlayer]；测试注入记录调用序列的假实现。
typedef MultiviewCellPlayerFactory = MultiviewCellPlayerHandle Function({
  required int renderWidth,
  required int renderHeight,
});

/// 单格播放器持有者（非 widget）。
///
/// 自持独立的 media_kit Player + VideoController，绕开全局单实例的
/// PlayerManager/GlobalPlayerService/PlayerPool。每格渲染分辨率在构造时
/// 由控制器按当前布局计算并固定，避免 Windows 共享渲染线程下多实例
/// 相互争抢全分辨率输出。
class MultiviewCellPlayer implements MultiviewCellPlayerHandle {
  MultiviewCellPlayer({required this.renderWidth, required this.renderHeight});

  /// 固定的渲染输出宽度（物理像素），来自布局均分结果。
  final int renderWidth;

  /// 固定的渲染输出高度（物理像素），来自布局均分结果。
  final int renderHeight;

  Player? _player;

  VideoController? _controller;

  @override
  VideoController? get videoController => _controller;

  @override
  Future<void> start({required String url, required Map<String, String> headers}) async {
    MediaKit.ensureInitialized();

    final player = Player();
    _player = player;

    if (player.platform is NativePlayer) {
      final native = player.platform as dynamic;
      // 与主播放器共用同一套低延迟直播 mpv 属性。
      await MediaKitAdapter.applyNativeLiveProperties(native);
    }

    // 静音起播：先于 open 设置音量，避免首帧前出现声音毛刺；
    // 获得音频焦点后由 setMuted(false) 恢复。
    await player.setVolume(0.0);

    // 渲染配置与主播放器默认分支一致；multiview 不使用兼容模式与自定义输出
    // 分支（它们面向单画面调优），但必须固定 width/height。
    // Android/Web 平台忽略 width/height（media_kit 官方语义），无副作用。
    final controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: PlatformUtils.isMacOS ? false : SettingsService.to.player.enableCodec.v,
        hwdec: PlatformUtils.isMacOS ? 'no' : null,
        androidAttachSurfaceAfterVideoParameters: false,
        width: renderWidth,
        height: renderHeight,
      ),
    );
    _controller = controller;

    await player.open(Media(url, httpHeaders: headers), play: true);
  }

  @override
  Future<void> setMuted(bool muted) async {
    final player = _player;
    if (player == null) return;
    await player.setVolume(muted ? 0.0 : 1.0);
  }

  @override
  Future<void> pause() async {
    final player = _player;
    if (player == null) return;
    await player.pause();
  }

  @override
  Future<void> disposeVideoController() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      final platform = await controller.platform.future;
      platform.dispose();
    } catch (error, stackTrace) {
      // 渲染控制器可能因起播失败从未完成平台侧创建。此处必须继续走
      // Player.dispose（native 纹理在其 release 钩子中摘除），因此仅记录不中断。
      developer.log(
        'MultiviewCellPlayer: video controller dispose failed',
        name: 'MultiviewCellPlayer',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> disposePlayer() async {
    final player = _player;
    _player = null;
    if (player == null) return;
    await player.dispose();
  }
}
