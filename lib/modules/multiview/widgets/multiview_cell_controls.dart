import 'package:remixicon/remixicon.dart';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/multiview/models/multiview_models.dart';
import 'package:pure_live/modules/multiview/multiview_cell_controls_layout.dart';
import 'package:pure_live/modules/multiview/multiview_controller.dart';

/// Callbacks the cell control bar needs from the page. The bar owns no navigation
/// and no sheet: quality/line/volume/danmaku-setting surfaces need the page's
/// `BuildContext` and display mode, so they stay in `MultiviewPageState`.
class MultiviewCellControlActions {
  const MultiviewCellControlActions({
    required this.onTogglePlay,
    required this.onRefresh,
    required this.onAudioFocus,
    required this.onDanmaku,
    required this.onQuality,
    required this.onLine,
    required this.onVolume,
    required this.onFullscreen,
    required this.onCloseCell,
    this.onDanmakuSettings,
  });

  final VoidCallback onTogglePlay;
  final VoidCallback onRefresh;
  final VoidCallback onAudioFocus;
  final VoidCallback onDanmaku;
  final VoidCallback onQuality;
  final VoidCallback onLine;
  final VoidCallback onVolume;
  final VoidCallback onFullscreen;
  final VoidCallback onCloseCell;
  final VoidCallback? onDanmakuSettings;
}

/// Bottom control bar for one multi-view cell.
///
/// Extracted from the old focus-only bar so that every layout (1×1, 1×2, 2×2 and
/// the one-big-plus-small grid, big cells *and* small cells) offers the same
/// actions; only how many fit inline depends on the measured cell.
class MultiviewCellControls extends StatelessWidget {
  const MultiviewCellControls({
    super.key,
    required this.controller,
    required this.state,
    required this.layout,
    required this.actions,
    required this.isFullscreen,
  });

  final MultiviewController controller;
  final MultiviewCellState state;
  final MultiviewControlsLayout layout;
  final MultiviewCellControlActions actions;
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = Colors.white.withValues(alpha: 0.92);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in layout.inlineActions) _buildButton(context, action, iconColor, theme),
          if (layout.hasOverflow)
            PopupMenuButton<MultiviewControlsAction>(
              tooltip: i18n('multiview_more'),
              color: theme.colorScheme.surfaceContainerHighest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              position: PopupMenuPosition.over,
              onSelected: (action) => _invoke(context, action),
              itemBuilder: (context) => [
                for (final action in layout.overflowActions)
                  PopupMenuItem<MultiviewControlsAction>(
                    value: action,
                    child: Row(
                      children: [
                        Icon(_icon(action), size: 18, color: theme.colorScheme.onSurface),
                        const SizedBox(width: 8),
                        Text(_tooltip(context, action), style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
              ],
              child: SizedBox(
                height: layout.hitTarget,
                width: MultiviewControlsLayout.moreButtonWidth,
                child: Icon(Icons.more_horiz_rounded, size: layout.iconSize, color: iconColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, MultiviewControlsAction action, Color iconColor, ThemeData theme) {
    switch (action) {
      case MultiviewControlsAction.playPause:
        return Obx(() {
          final playing = controller.playingFlags[state.index];
          return _button(
            icon: playing ? Remix.pause_line : Remix.play_line,
            tooltip: i18n(playing ? 'multiview_pause' : 'multiview_play'),
            iconColor: iconColor,
            onTap: actions.onTogglePlay,
          );
        });
      case MultiviewControlsAction.danmaku:
        return Obx(
          () => _button(
            icon: CustomIcons.danmaku_open,
            tooltip: _tooltip(context, action),
            iconColor: controller.danmakuEnabled.value ? theme.colorScheme.primary : iconColor,
            onTap: actions.onDanmaku,
          ),
        );
      case MultiviewControlsAction.audioFocus:
        // Tap-to-focus is also how a cell reveals this bar, so the sound source
        // needs an explicit control of its own.
        return _button(
          icon: controller.audioFocusIndex == state.index ? Remix.volume_up_line : Remix.volume_mute_line,
          tooltip: _tooltip(context, action),
          iconColor: controller.audioFocusIndex == state.index ? theme.colorScheme.primary : iconColor,
          onTap: actions.onAudioFocus,
        );
      case MultiviewControlsAction.fullscreen:
        return _button(
          icon: isFullscreen ? Remix.fullscreen_exit_line : Remix.fullscreen_line,
          tooltip: _tooltip(context, action),
          iconColor: iconColor,
          onTap: actions.onFullscreen,
        );
      case MultiviewControlsAction.closeCell:
        return _button(
          icon: Remix.close_line,
          tooltip: _tooltip(context, action),
          iconColor: iconColor,
          onTap: actions.onCloseCell,
        );
      case MultiviewControlsAction.refresh:
      case MultiviewControlsAction.quality:
      case MultiviewControlsAction.line:
      case MultiviewControlsAction.volume:
      case MultiviewControlsAction.danmakuSettings:
        return _button(
          icon: _icon(action),
          tooltip: _tooltip(context, action),
          iconColor: iconColor,
          onTap: () => _invoke(context, action),
        );
    }
  }

  void _invoke(BuildContext context, MultiviewControlsAction action) {
    switch (action) {
      case MultiviewControlsAction.playPause:
        actions.onTogglePlay();
      case MultiviewControlsAction.refresh:
        actions.onRefresh();
      case MultiviewControlsAction.audioFocus:
        actions.onAudioFocus();
      case MultiviewControlsAction.danmaku:
        actions.onDanmaku();
      case MultiviewControlsAction.quality:
        actions.onQuality();
      case MultiviewControlsAction.line:
        actions.onLine();
      case MultiviewControlsAction.volume:
        actions.onVolume();
      case MultiviewControlsAction.danmakuSettings:
        actions.onDanmakuSettings?.call();
      case MultiviewControlsAction.fullscreen:
        actions.onFullscreen();
      case MultiviewControlsAction.closeCell:
        actions.onCloseCell();
    }
  }

  IconData _icon(MultiviewControlsAction action) => switch (action) {
    MultiviewControlsAction.playPause => Remix.play_line,
    MultiviewControlsAction.refresh => Remix.refresh_line,
    MultiviewControlsAction.audioFocus => Remix.volume_up_line,
    MultiviewControlsAction.danmaku => CustomIcons.danmaku_open,
    MultiviewControlsAction.quality => Remix.hd_line,
    MultiviewControlsAction.line => Remix.route_line,
    MultiviewControlsAction.volume => Remix.volume_down_line,
    MultiviewControlsAction.danmakuSettings => Remix.settings_3_line,
    MultiviewControlsAction.fullscreen => Remix.fullscreen_line,
    MultiviewControlsAction.closeCell => Remix.close_line,
  };

  String _tooltip(BuildContext context, MultiviewControlsAction action) => switch (action) {
    MultiviewControlsAction.playPause => i18n('multiview_play'),
    MultiviewControlsAction.refresh => i18n('multiview_refresh'),
    MultiviewControlsAction.audioFocus => i18n('multiview_audio_focus'),
    MultiviewControlsAction.danmaku => i18n('danmaku'),
    MultiviewControlsAction.quality => i18n('select_quality'),
    MultiviewControlsAction.line => i18n('multiview_line_selector'),
    MultiviewControlsAction.volume => i18n('multiview_volume'),
    MultiviewControlsAction.danmakuSettings => i18n('multiview_danmaku_settings'),
    MultiviewControlsAction.fullscreen => i18n('multiview_fullscreen'),
    MultiviewControlsAction.closeCell => i18n('multiview_close_cell'),
  };

  Widget _button({
    required IconData icon,
    required String tooltip,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: layout.hitTarget,
          width: layout.hitTarget,
          child: Icon(icon, size: layout.iconSize, color: iconColor),
        ),
      ),
    );
  }
}
