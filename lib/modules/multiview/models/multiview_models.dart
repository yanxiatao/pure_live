import 'package:media_kit_video/media_kit_video.dart';

import 'package:pure_live/common/index.dart';

/// 多画面布局枚举。
///
/// 每个布局隐含固定的行列划分，用于把屏幕物理像素均分给每个格子，
/// 作为该格 media_kit 渲染输出（VideoControllerConfiguration.width/height）
/// 的固定分辨率依据。
enum MultiviewLayout {
  /// 单画面（1 行 x 1 列）。
  single,

  /// 双画面（1 行 x 2 列，左右并排）。
  dual,

  /// 四画面（2 行 x 2 列）。
  quad;

  /// 当前布局可容纳的格子数量。
  int get capacity => switch (this) {
    MultiviewLayout.single => 1,
    MultiviewLayout.dual => 2,
    MultiviewLayout.quad => 4,
  };

  /// 当前列数（渲染分辨率按列均分宽度）。
  int get columns => switch (this) {
    MultiviewLayout.single => 1,
    MultiviewLayout.dual => 2,
    MultiviewLayout.quad => 2,
  };

  /// 当前行数（渲染分辨率按行均分高度）。
  int get rows => switch (this) {
    MultiviewLayout.single => 1,
    MultiviewLayout.dual => 1,
    MultiviewLayout.quad => 2,
  };
}

/// 单格生命周期状态。
enum MultiviewCellStatus {
  /// 未分配房间。
  empty,

  /// 正在解析播放地址或正在起播。
  resolving,

  /// 已成功起播。
  playing,

  /// 解析或起播失败，[MultiviewCellState.errorKind]/[MultiviewCellState.errorDetail] 携带原因。
  error,
}

/// 单格失败种类。
///
/// 核心层只记录种类与原始错误文本，不硬编码任何自然语言；
/// 展示文案由 UI 按当前语言映射对应的 i18n 键。
enum MultiviewCellErrorKind {
  /// 解析播放地址失败（站点接口/网络原因）。
  resolveFailure,

  /// 已取得地址但起播失败（播放内核打开媒体失败）。
  startFailure,
}

/// 单格播放源解析结果。
///
/// 直播流普遍需要平台鉴权头（Cookie/UA/Referer），因此除 URL 外
/// 一并携带请求头，交给每格播放器在 open 时使用。
class MultiviewStreamSource {
  const MultiviewStreamSource({required this.url, required this.headers});

  /// 可直接交给播放内核的媒体地址。
  final String url;

  /// 打开该地址所需的 HTTP 头。
  final Map<String, String> headers;
}

/// multiview 单格的不可变状态快照。
///
/// 控制器以 `RxList<MultiviewCellState>` 持有，长度恒等于当前布局容量；
/// UI 按 [videoController] 渲染画面、按 [status]/[errorKind] 呈现占位与错误。
class MultiviewCellState {
  const MultiviewCellState({
    required this.index,
    this.room,
    this.status = MultiviewCellStatus.empty,
    this.errorKind,
    this.errorDetail,
    this.videoController,
  });

  /// 该格在当前布局中的固定下标（0 起）。
  final int index;

  /// 分配到该格的直播间模型；未分配时为 null。
  final LiveRoom? room;

  /// 当前生命周期状态。
  final MultiviewCellStatus status;

  /// 失败种类；仅 [MultiviewCellStatus.error] 时非空，UI 据此映射本地化文案。
  final MultiviewCellErrorKind? errorKind;

  /// 原始错误文本（未本地化）；仅 [MultiviewCellStatus.error] 时非空，
  /// 作为 i18n 文案的 {detail} 参数展示。
  final String? errorDetail;

  /// 该格 media_kit 的 VideoController，供 UI 的 Video widget 渲染；
  /// 尚未创建或已释放时为 null。
  final VideoController? videoController;

  /// 构造一个空白格状态。
  factory MultiviewCellState.empty(int index) => MultiviewCellState(index: index);

  MultiviewCellState copyWith({
    LiveRoom? room,
    bool clearRoom = false,
    MultiviewCellStatus? status,
    MultiviewCellErrorKind? errorKind,
    String? errorDetail,
    bool clearError = false,
    VideoController? videoController,
    bool clearVideoController = false,
  }) {
    return MultiviewCellState(
      index: index,
      room: clearRoom ? null : (room ?? this.room),
      status: status ?? this.status,
      errorKind: clearError ? null : (errorKind ?? this.errorKind),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
      videoController: clearVideoController ? null : (videoController ?? this.videoController),
    );
  }
}
