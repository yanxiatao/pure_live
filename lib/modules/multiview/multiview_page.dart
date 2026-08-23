import 'dart:async';

import 'package:flame_barrage/flame_barrage.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:remixicon/remixicon.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';
import 'package:pure_live/modules/multiview/widgets/multiview_room_picker.dart';

/// 页面显示状态机：normal（完整界面）→ immersive（隐藏工具条与侧板，
/// 留悬浮恢复钮）→ fullscreen（无任何 chrome）。
///
/// 只影响 chrome 显隐，不触碰布局/格子状态；返回手势与 Esc 均沿
/// fullscreen/immersive → normal → 退出页面 的单一路径回退。
enum _DisplayMode { normal, immersive, fullscreen }

/// 多画面同看页面。
///
/// 视觉与交互层：按 [MultiviewController] 的布局与格子状态渲染网格，
/// 提供布局切换（1x1/1x2/2x2/一大多小）、每格清晰度选择、大画面弹幕、
/// 选台面板（窄屏底部弹窗、宽屏右侧常驻侧板）、音频焦点标识、单格操作
/// 菜单与沉浸/全屏显示模式。播放资源的创建与释放全部由控制器统一管理，
/// 本页面不持有任何播放器对象。
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

  /// 一大多小小列首屏可见格数：前三格恰好铺满视口（与固定三格时代的
  /// 视觉节奏一致），追加格滚动呈现。
  static const int _focusSmallViewportCells = 3;

  /// 当前显示模式；仅 chrome 显隐差异，见 [_DisplayMode]。
  _DisplayMode _displayMode = _DisplayMode.normal;

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
    // 桌面端 Esc 退沉浸/全屏。用全局键盘钩子而非 Focus 节点：
    // 选台面板搜索框等输入焦点不应抢占 Esc 处理权；
    // 本路由非栈顶（弹层/上层页面打开）时让位，不干扰其按键语义。
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _layoutWorker?.dispose();
    super.dispose();
  }

  /// 返回意图统一入口：非 normal 先回 normal，normal 才真正退出页面。
  void _handleBackIntent({required bool didPop}) {
    if (didPop) return;
    if (_displayMode != _DisplayMode.normal) {
      setState(() => _displayMode = _DisplayMode.normal);
      return;
    }
    Navigator.of(context).pop();
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return false;
    if (!mounted || _displayMode == _DisplayMode.normal) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    setState(() => _displayMode = _DisplayMode.normal);
    return true;
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
    final isWide = MediaQuery.sizeOf(context).width > _wideBreakpoint && _displayMode == _DisplayMode.normal;
    final hasQuality =
        state.status == MultiviewCellStatus.playing && state.qualities.isNotEmpty && state.qualityLoader != null;
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
              leading: const Icon(Remix.equalizer_line),
              title: Text(i18n('select_quality')),
              enabled: hasQuality,
              onTap: hasQuality
                  ? () {
                      Navigator.of(sheetContext).pop();
                      _showQualitySheet(state);
                    }
                  : null,
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

  /// 清晰度列表底部弹窗（长按菜单路径）；点选后换档，当前档打勾。
  void _showQualitySheet(MultiviewCellState state) {
    final qualities = state.qualities;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < qualities.length; i++)
              ListTile(
                title: Text(qualities[i].quality),
                trailing: i == state.qualityIndex ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(controller.setCellQuality(state.index, i));
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBackIntent(didPop: didPop),
      child: switch (_displayMode) {
        _DisplayMode.normal => Scaffold(
          appBar: AppBar(
            title: Text(i18n('multiview_title')),
            actions: [
              IconButton(
                tooltip: i18n('multiview_immersive'),
                icon: const Icon(Remix.expand_diagonal_line),
                onPressed: () => setState(() => _displayMode = _DisplayMode.immersive),
              ),
              IconButton(
                tooltip: i18n('multiview_fullscreen'),
                icon: const Icon(Remix.fullscreen_line),
                onPressed: () => setState(() => _displayMode = _DisplayMode.fullscreen),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > _wideBreakpoint;
              return Column(
                children: [
                  _buildToolbar(),
                  Expanded(child: _buildContentArea(isWide: isWide)),
                ],
              );
            },
          ),
        ),
        // 沉浸：无工具条/侧板/AppBar，仅右下角一个小恢复钮。
        _DisplayMode.immersive => Scaffold(
          body: Stack(
            children: [
              // 沉浸/全屏下没有可见侧板：空格点击一律走底部选台弹窗。
              _buildContentArea(isWide: false),
              Positioned(
                right: 16,
                bottom: 16,
                child: _ImmersiveRestoreButton(onTap: () => setState(() => _displayMode = _DisplayMode.normal)),
              ),
            ],
          ),
        ),
        // 全屏：只保留多路画面，连沉浸恢复钮也不显示。
        _DisplayMode.fullscreen => Scaffold(body: _buildContentArea(isWide: false)),
      },
    );
  }

  /// 内容区：宽屏且 normal 时为「网格 + 分隔线 + 选台侧板」，否则仅网格。
  ///
  /// [isWide] 由调用方按显示模式折算——沉浸/全屏下传 false，
  /// 保证空格点击仍能唤起选台弹窗而非指向不可见的侧板。
  Widget _buildContentArea({required bool isWide}) {
    if (!isWide) return _buildGrid(isWide: isWide);
    return Row(
      children: [
        Expanded(child: _buildGrid(isWide: isWide)),
        const VerticalDivider(width: 1),
        SizedBox(width: _sidePanelWidth, child: _buildSidePanel()),
      ],
    );
  }

  Widget _buildToolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Obx(() {
                final layout = controller.layout.value;
                return SegmentedButton<MultiviewLayout>(
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
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          // 页级弹幕开关（连接管理在核心层，UI 只切显隐开关）。
          Obx(() {
            final enabled = controller.danmakuEnabled.value;
            final theme = Theme.of(context);
            return IconButton(
              tooltip: i18n('danmaku'),
              icon: Icon(
                CustomIcons.danmaku_open,
                size: 22,
                color: enabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () => controller.danmakuEnabled.toggle(),
            );
          }),
          // 小格自动降质联动：仅 focus 布局生效，非 focus 下置灰防误触。
          Obx(() {
            final isFocusLayout = controller.layout.value == MultiviewLayout.focus;
            final enabled = controller.smallCellsLowQuality.value;
            final theme = Theme.of(context);
            return IconButton(
              tooltip: i18n('multiview_small_low_quality'),
              icon: Icon(
                Remix.speed_mini_line,
                size: 22,
                color: enabled ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: isFocusLayout ? () => controller.smallCellsLowQuality.toggle() : null,
            );
          }),
        ],
      ),
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
      // 在 Obx 内读取以建立订阅：晋升与弹幕开关变化即时驱动重绘。
      final focused = controller.focusedCellIndex.value;
      final danmakuEnabled = controller.danmakuEnabled.value;
      final content = layout == MultiviewLayout.focus
          ? _buildFocusLayout(cells, focused: focused, isWide: isWide, danmakuEnabled: danmakuEnabled)
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

  /// 一大多小布局：左侧大格（当前聚焦格）+ 右侧可滚动小列。
  ///
  /// 窄屏保持同一形态，不做上下变体。格子子树经 GlobalKey 搬移，
  /// 晋升切换只改变位置，不重建播放画面。小列首屏恰容纳
  /// [_focusSmallViewportCells] 格，追加格滚动呈现，列尾附「添加画面」槽。
  Widget _buildFocusLayout(
    List<MultiviewCellState> cells, {
    required int focused,
    required bool isWide,
    required bool danmakuEnabled,
  }) {
    // 核心层已在缩容/释放时钳制 focusedCellIndex，此处再钳一次防竞态越界。
    final bigIndex = focused.clamp(0, cells.length - 1);
    final others = [
      for (var i = 0; i < cells.length; i++)
        if (i != bigIndex) i,
    ];
    return Row(
      children: [
        Expanded(
          flex: _focusBigFlex,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: _buildCellAt(cells, bigIndex, isWide: isWide, showDanmaku: danmakuEnabled, showQualityEntry: true),
          ),
        ),
        Expanded(
          flex: _focusSmallFlex,
          child: LayoutBuilder(
            builder: (context, boxConstraints) {
              // 固定行高 = 视口高 / 首屏格数：前三格铺满视口，超出滚动。
              final extent = boxConstraints.maxHeight / _focusSmallViewportCells;
              final canAdd = controller.canAddCell;
              // 常驻全部子项（SingleChildScrollView + Column），不做虚拟化：
              // maxCells=9、首屏 3 格的规模下虚拟化是纯负收益——滚动会反复
              // 销毁/重建 Video（Windows 共享渲染线程纹理重附开销大），且把
              // GlobalKey 零重建降级为仅视口内成立。滚动行为不变。
              return SingleChildScrollView(
                child: Column(
                  children: [
                    for (final index in others)
                      SizedBox(
                        height: extent,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: _buildCellAt(cells, index, isWide: isWide),
                        ),
                      ),
                    if (canAdd)
                      SizedBox(
                        height: extent,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: _AddCellSlot(onTap: () => unawaited(controller.addCell())),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCellAt(
    List<MultiviewCellState> cells,
    int index, {
    required bool isWide,
    bool showDanmaku = false,
    bool showQualityEntry = false,
  }) {
    final state = cells[index];
    final status = state.status;
    return _MultiviewCellView(
      key: _cellKey(index),
      state: state,
      isAudioFocus: controller.audioFocusIndex == index && status == MultiviewCellStatus.playing,
      isPickTarget:
          _targetCell == index && (status == MultiviewCellStatus.empty || status == MultiviewCellStatus.error),
      showDanmaku: showDanmaku && status == MultiviewCellStatus.playing && state.videoController != null,
      barrageController: controller.barrageController,
      showQualityEntry: showQualityEntry,
      onSelectQuality: (qualityIndex) => unawaited(controller.setCellQuality(index, qualityIndex)),
      onTap: () {
        switch (status) {
          case MultiviewCellStatus.playing:
            // 一大多小下点击小格 = 晋升为大画面（声源跟随大画面）；
            // 其余布局与 focus 大格维持原音频焦点行为。
            if (controller.layout.value == MultiviewLayout.focus && controller.focusedCellIndex.value != index) {
              unawaited(controller.promoteCell(index)); // focusedCellIndex 为 Rx，Obx 自行重绘
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
/// 大画面格（focus 布局）额外承载弹幕层与清晰度入口。
class _MultiviewCellView extends StatelessWidget {
  const _MultiviewCellView({
    super.key,
    required this.state,
    required this.isAudioFocus,
    required this.isPickTarget,
    required this.onTap,
    required this.onLongPress,
    required this.onRetry,
    required this.barrageController,
    required this.onSelectQuality,
    this.showDanmaku = false,
    this.showQualityEntry = false,
  });

  final MultiviewCellState state;
  final bool isAudioFocus;
  final bool isPickTarget;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRetry;

  /// 在大画面上层叠弹幕；由页面按 danmakuEnabled 折算后传入。
  final bool showDanmaku;
  final BarrageController barrageController;

  /// 是否显示清晰度入口（仅 focus 布局大画面为 true）。
  final bool showQualityEntry;
  final ValueChanged<int> onSelectQuality;

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
          // 弹幕层：仅大画面渲染；IgnorePointer 保证不遮挡格子手势。
          if (showDanmaku)
            Positioned.fill(
              child: IgnorePointer(
                // 独立 Obx：_buildBarrageConfig 在订阅作用域内读取全部弹幕
                // 设置 Rx（字号/速度/透明度/区域/描边/字体/FPS），全局设置
                // 变化即时重绘弹幕层（对照 live_play DanmakuViewer 整段
                // Obx 包裹的做法）。格子子树的 build 不在父级 Obx 作用域内，
                // 不包裹则设置变化永远不会触达这里。
                child: Obx(() {
                  // refreshRateMode 是由该 Rx 派生的普通 getter，
                  // 显式订阅其响应源以覆盖自动帧率模式切换。
                  SettingsService.to.app.refreshRateModeName.v;
                  return FlameBarrageWidget(
                    controller: barrageController,
                    enablePointerEvents: false,
                    config: _buildBarrageConfig(),
                    emojiAtlas: EmojiAtlas.instance,
                  );
                }),
              ),
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
          if (showQualityEntry) Positioned(left: 8, bottom: 8, child: _buildQualityEntry(theme)),
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

  /// 清晰度是否可选：qualities 为空（解析中/失败/不支持换档）时置灰。
  bool get _qualityAvailable =>
      state.status == MultiviewCellStatus.playing && state.qualities.isNotEmpty && state.qualityLoader != null;

  /// 大画面左下角清晰度入口：形态对齐 live_play 的 ResolutionSelector，
  /// 底色改为视频上的半透明黑以保证可读性。
  Widget _buildQualityEntry(ThemeData theme) {
    if (!_qualityAvailable) return const SizedBox.shrink();
    final currentName = state.qualities[state.qualityIndex.clamp(0, state.qualities.length - 1)].quality;
    return PopupMenuButton<int>(
      tooltip: i18n('select_quality'),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(0, 5),
      position: PopupMenuPosition.under,
      onSelected: onSelectQuality,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Remix.equalizer_line, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              currentName,
              style: AppTextStyles.t11.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      itemBuilder: (context) => [
        for (var i = 0; i < state.qualities.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              state.qualities[i].quality,
              style: AppTextStyles.t13.copyWith(
                color: i == state.qualityIndex ? theme.colorScheme.primary : null,
                fontWeight: i == state.qualityIndex ? FontWeight.w700 : null,
              ),
            ),
          ),
      ],
    );
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

/// 大画面弹幕配置。
///
/// 结构照抄 live_play 的 DanmakuViewer（video_controller_panel.dart）既有
/// 配置；字号/速度/区域等取全局弹幕设置默认值，池容量沿用同组常量。
BarrageConfig _buildBarrageConfig() {
  final settings = SettingsService.to.danmaku;
  return BarrageConfig(
    emitInterval: 0.05,
    fontSize: settings.danmakuFontSize.v,
    topAreaDistance: settings.danmakuTopArea.v,
    area: settings.danmakuArea.v,
    bottomAreaDistance: settings.danmakuBottomArea.v,
    baseSpeed: settings.danmakuSpeed.v,
    opacity: settings.danmakuOpacity.v,
    fontWeight: FontWeight(settings.danmakuFontWeight.v),
    strokeWidth: settings.danmakuFontBorder.v,
    showStroke: settings.enableDanmakuStroke.v,
    noEmojiMode: settings.noEmojiMode.v,
    fps: settings.danmakuAutoFps.v
        ? settings.resolvedDanmakuFps(refreshRateMode: SettingsService.to.app.refreshRateMode)
        : settings.danmakuFps.v.clamp(30, 240).toInt(),
    maxVisibleCount: 48,
    maxPendingCount: 120,
    maxPendingAge: const Duration(seconds: 5),
    fontFamily: settings.danmakuFontFamilyName.v,
    trackHeight: (settings.danmakuFontSize.v * 1.55).clamp(24.0, 64.0).toDouble(),
    emojiSize: (settings.danmakuFontSize.v * 1.3).clamp(16.0, 48.0).toDouble(),
    pictureCacheMaxSize: 96,
    barragePoolMaxSize: 72,
    textCacheMaxSize: 320,
  );
}

/// 一大多小小列尾部的「添加画面」占位槽。
class _AddCellSlot extends StatelessWidget {
  const _AddCellSlot({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.35), width: 1.5),
            color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Remix.add_circle_line, size: 22, color: theme.colorScheme.primary),
                const SizedBox(height: 6),
                Text(
                  i18n('multiview_add_cell'),
                  style: AppTextStyles.t12.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 沉浸模式右下角的悬浮恢复钮。
class _ImmersiveRestoreButton extends StatelessWidget {
  const _ImmersiveRestoreButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: i18n('multiview_immersive_exit'),
      child: Material(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Remix.collapse_diagonal_line, size: 20, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
