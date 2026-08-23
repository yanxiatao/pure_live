import 'dart:async';

import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';
import 'package:pure_live/modules/multiview/widgets/multiview_room_picker.dart';

/// 多画面同看页面。
///
/// 视觉与交互层：按 [MultiviewController] 的布局与格子状态渲染网格，
/// 提供布局切换（1x1/1x2/2x2/一大多小）、选台面板（窄屏底部弹窗、宽屏
/// 右侧常驻侧板）、音频焦点标识与单格操作菜单。播放资源的创建与释放
/// 全部由控制器统一管理，本页面不持有任何播放器对象。
class MultiviewPage extends StatefulWidget {
  const MultiviewPage({super.key});

  @override
  State<MultiviewPage> createState() => _MultiviewPageState();
}

class _MultiviewPageState extends State<MultiviewPage> {
  /// 与首页一致的宽窄屏分界：超过该宽度时选台面板以右侧常驻侧板呈现。
  static const double _wideBreakpoint = 680;

  /// 宽屏侧板宽度，与桌面端设置类页面的侧栏习惯一致。
  static const double _sidePanelWidth = 320;

  /// 一大多小布局的大格与右侧小列的弹性比。
  static const int _focusBigFlex = 3;

  static const int _focusSmallFlex = 1;

  /// 选台面板当前的目标格下标。
  int _targetCell = 0;

  /// 布局监听：缩容时把选台目标钳制回有效范围，避免向已不存在的格子提交。
  Worker? _layoutWorker;

  /// 每格 GlobalKey：一大多小晋升时格子跨父级移动（大格槽 ⇄ 小格列），
  /// 普通 ValueKey 无法跨父级复用元素；GlobalKey 让格子子树整体搬移，
  /// Video 状态与纹理附着保持不变，切换不闪黑。
  final Map<int, GlobalKey> _cellKeys = {};

  MultiviewController get controller => Get.find<MultiviewController>();

  GlobalKey _cellKey(int index) => _cellKeys.putIfAbsent(index, () => GlobalKey(debugLabel: 'multiview_cell_$index'));

  @override
  void initState() {
    super.initState();
    _targetCell = _firstEmptyCell();
    _layoutWorker = ever<MultiviewLayout>(controller.layout, (_) => _clampTargetCell());
  }

  @override
  void dispose() {
    _layoutWorker?.dispose();
    super.dispose();
  }

  int _firstEmptyCell() {
    for (final cell in controller.cells) {
      if (cell.status == MultiviewCellStatus.empty) return cell.index;
    }
    return 0;
  }

  /// 布局缩容后旧目标格（如 quad 的第 4 格）已不存在，钳制到新容量内。
  void _clampTargetCell() {
    final maxIndex = controller.cells.length - 1;
    if (_targetCell > maxIndex && mounted) {
      setState(() => _targetCell = maxIndex);
    }
  }

  /// 分配成功后把目标推进到下一个空位，连续选台无需反复点击格子。
  void _advanceTarget(int justAssigned) {
    final count = controller.cells.length;
    for (var step = 1; step < count; step++) {
      final index = (justAssigned + step) % count;
      if (controller.cells[index].status == MultiviewCellStatus.empty) {
        setState(() => _targetCell = index);
        return;
      }
    }
  }

  void _pickRoom(LiveRoom room) {
    // 防御性钳制：布局切换与选台回调竞态时，提交下标必须仍在当前容量内。
    final target = _targetCell.clamp(0, controller.cells.length - 1);
    unawaited(controller.assignRoom(target, room));
    _advanceTarget(target);
  }

  void _openPickerFor(int cellIndex, {required bool isWide}) {
    setState(() => _targetCell = cellIndex);
    // 宽屏侧板常驻，点击空格只切换目标高亮；窄屏弹出底部选台弹窗。
    if (isWide) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.72),
      builder: (sheetContext) => SafeArea(
        child: MultiviewRoomPicker(
          cellIndex: cellIndex,
          onPicked: (room) {
            Navigator.of(sheetContext).pop();
            _pickRoom(room);
          },
        ),
      ),
    );
  }

  void _showCellActions(MultiviewCellState state) {
    final isWide = MediaQuery.sizeOf(context).width > _wideBreakpoint;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Remix.tv_2_line),
              title: Text(i18n('multiview_change_room')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openPickerFor(state.index, isWide: isWide);
              },
            ),
            ListTile(
              leading: Icon(Remix.close_circle_line, color: Theme.of(context).colorScheme.error),
              title: Text(i18n('multiview_close_cell')),
              onTap: () {
                Navigator.of(sheetContext).pop();
                controller.removeCell(state.index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _retryCell(MultiviewCellState state) {
    final room = state.room;
    if (room == null) {
      _openPickerFor(state.index, isWide: MediaQuery.sizeOf(context).width > _wideBreakpoint);
      return;
    }
    unawaited(controller.assignRoom(state.index, room));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(i18n('multiview_title'))),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > _wideBreakpoint;
          return Column(
            children: [
              _buildToolbar(),
              Expanded(
                child: isWide
                    ? Row(
                        children: [
                          Expanded(child: _buildGrid(isWide: isWide)),
                          const VerticalDivider(width: 1),
                          SizedBox(width: _sidePanelWidth, child: _buildSidePanel()),
                        ],
                      )
                    : _buildGrid(isWide: isWide),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Obx(() {
        final layout = controller.layout.value;
        return Center(
          child: SegmentedButton<MultiviewLayout>(
            showSelectedIcon: false,
            selected: {layout},
            onSelectionChanged: (selection) => controller.setLayout(selection.first),
            segments: [
              ButtonSegment(
                value: MultiviewLayout.single,
                icon: const Icon(Remix.aspect_ratio_line),
                label: const Text('1×1'),
              ),
              ButtonSegment(
                value: MultiviewLayout.dual,
                icon: const Icon(Remix.layout_column_line),
                label: const Text('1×2'),
              ),
              ButtonSegment(
                value: MultiviewLayout.quad,
                icon: const Icon(Remix.layout_grid_line),
                label: const Text('2×2'),
              ),
              ButtonSegment(
                value: MultiviewLayout.focus,
                icon: const Icon(Remix.focus_3_line),
                label: const Text('1+3'),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSidePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            i18n('multiview_pick_for_cell', args: {'index': '${_targetCell + 1}'}),
            style: AppTextStyles.t15Bold,
          ),
        ),
        Expanded(
          child: MultiviewRoomPicker(cellIndex: _targetCell, onPicked: _pickRoom),
        ),
      ],
    );
  }

  Widget _buildGrid({required bool isWide}) {
    return Obx(() {
      final layout = controller.layout.value;
      final cells = controller.cells;
      final content = layout == MultiviewLayout.focus
          ? _buildFocusLayout(cells, isWide: isWide)
          : Column(
              children: [
                for (var row = 0; row < layout.rows; row++)
                  Expanded(
                    child: Row(
                      children: [
                        for (var col = 0; col < layout.columns; col++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: _buildCellAt(cells, row * layout.columns + col, isWide: isWide),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
      return Padding(padding: const EdgeInsets.all(6), child: content);
    });
  }

  /// 一大多小布局：左侧大格（当前聚焦格）+ 右侧其余三格等分小列。
  ///
  /// 窄屏保持同一形态，不做上下变体。格子子树经 GlobalKey 搬移，
  /// 晋升切换只改变位置，不重建播放画面。
  Widget _buildFocusLayout(List<MultiviewCellState> cells, {required bool isWide}) {
    // 核心层已在缩容/释放时钳制 focusedCellIndex，此处再钳一次防竞态越界。
    final focused = controller.focusedCellIndex.value.clamp(0, cells.length - 1);
    final others = [
      for (var i = 0; i < cells.length; i++)
        if (i != focused) i,
    ];
    return Row(
      children: [
        Expanded(
          flex: _focusBigFlex,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: _buildCellAt(cells, focused, isWide: isWide),
          ),
        ),
        Expanded(
          flex: _focusSmallFlex,
          child: Column(
            children: [
              for (final i in others)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: _buildCellAt(cells, i, isWide: isWide),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCellAt(List<MultiviewCellState> cells, int index, {required bool isWide}) {
    final state = cells[index];
    final status = state.status;
    return _MultiviewCellView(
      key: _cellKey(index),
      state: state,
      isAudioFocus: controller.audioFocusIndex == index && status == MultiviewCellStatus.playing,
      isPickTarget:
          _targetCell == index && (status == MultiviewCellStatus.empty || status == MultiviewCellStatus.error),
      onTap: () {
        switch (status) {
          case MultiviewCellStatus.playing:
            // 一大多小下点击小格 = 晋升为大画面（声源跟随大画面）；
            // 其余布局与 focus 大格维持原音频焦点行为。
            if (controller.layout.value == MultiviewLayout.focus && controller.focusedCellIndex.value != index) {
              controller.promoteCell(index); // focusedCellIndex 为 Rx，Obx 自行重绘
              return;
            }
            controller.setAudioFocus(index);
            // audioFocusIndex 非 Rx，焦点标识需要手动触发一次重绘。
            setState(() {});
          case MultiviewCellStatus.empty || MultiviewCellStatus.error:
            _openPickerFor(index, isWide: isWide);
          case MultiviewCellStatus.resolving:
            break;
        }
      },
      onLongPress: status == MultiviewCellStatus.playing ? () => _showCellActions(state) : null,
      onRetry: () => _retryCell(state),
    );
  }
}

/// 单格视图：按生命周期状态渲染播放画面、空态、加载与错误占位。
///
/// 音频焦点格以主色描边 + 「声音来源」角标突出；目标空格以待选描边提示。
class _MultiviewCellView extends StatelessWidget {
  const _MultiviewCellView({
    super.key,
    required this.state,
    required this.isAudioFocus,
    required this.isPickTarget,
    required this.onTap,
    required this.onLongPress,
    required this.onRetry,
  });

  final MultiviewCellState state;
  final bool isAudioFocus;
  final bool isPickTarget;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final videoController = state.videoController;
    final showVideo = state.status == MultiviewCellStatus.playing && videoController != null;
    final isDark = theme.brightness == Brightness.dark;

    final (borderColor, borderWidth) = switch ((isAudioFocus, isPickTarget)) {
      (true, _) => (theme.colorScheme.primary, 2.0),
      (_, true) => (theme.colorScheme.primary.withValues(alpha: 0.55), 1.5),
      _ => (theme.dividerColor.withValues(alpha: isDark ? 0.25 : 0.15), 1.0),
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: showVideo || isDark ? Colors.black : theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final videoController = state.videoController;
    if (state.status == MultiviewCellStatus.playing && videoController != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Video(
            controller: videoController,
            controls: NoVideoControls,
            // multiview 页面自持每格生命周期，禁用 Video 内置的后台暂停策略，
            // 与主播放器 LivePlay 的单一生命周期权威原则保持一致。
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RoomNameChip(state: state),
                if (isAudioFocus) ...[const SizedBox(width: 6), const _AudioFocusBadge()],
              ],
            ),
          ),
        ],
      );
    }
    return switch (state.status) {
      MultiviewCellStatus.empty => _buildEmptyContent(theme),
      MultiviewCellStatus.resolving => _buildResolvingContent(),
      MultiviewCellStatus.error => _buildErrorContent(theme),
      // playing 但渲染控制器尚未就绪的瞬间：黑场等待即可。
      MultiviewCellStatus.playing => const SizedBox.shrink(),
    };
  }

  Widget _buildEmptyContent(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            ),
            child: Icon(Remix.add_circle_line, size: 26, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(i18n('multiview_empty_cell_hint'), style: AppTextStyles.t14Medium),
        ],
      ),
    );
  }

  Widget _buildResolvingContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(strokeWidth: 2.5),
          if ((state.room?.nick ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(state.room!.nick!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.t12Muted),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorContent(ThemeData theme) {
    final kind = state.errorKind;
    final detailMessage = kind == null
        ? ''
        : i18n(
            switch (kind) {
              MultiviewCellErrorKind.resolveFailure => 'multiview_error_resolve',
              MultiviewCellErrorKind.startFailure => 'multiview_error_start',
            },
            args: {'detail': state.errorDetail ?? ''},
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Remix.error_warning_line, size: 30, color: theme.colorScheme.error),
          const SizedBox(height: 10),
          Text(i18n('multiview_play_failed'), style: AppTextStyles.t14Bold, textAlign: TextAlign.center),
          if (detailMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              detailMessage,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTextStyles.t12Muted,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Remix.refresh_line, size: 16),
            label: Text(i18n('retry')),
          ),
        ],
      ),
    );
  }
}

/// 播放中格子左上角的房间名条：平台徽标 + 主播昵称。
class _RoomNameChip extends StatelessWidget {
  const _RoomNameChip({required this.state});

  final MultiviewCellState state;

  @override
  Widget build(BuildContext context) {
    final nick = state.room?.nick ?? '';
    final platform = state.room?.platform?.trim().toLowerCase() ?? '';
    final hasLogo = Sites.isSupported(platform);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasLogo) ...[Image.asset(Sites.of(platform).logo, width: 13, height: 13), const SizedBox(width: 5)],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              nick,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 音频焦点角标：主色底 + 音量图标，标记当前出声的格子。
class _AudioFocusBadge extends StatelessWidget {
  const _AudioFocusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Remix.volume_up_line, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            i18n('multiview_audio_focus_badge'),
            style: AppTextStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
