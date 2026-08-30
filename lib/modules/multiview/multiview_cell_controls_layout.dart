/// Per-cell control-bar sizing rules for multi-view.
///
/// Kept free of widget imports so the width bands, hit targets and which actions
/// are inline versus hidden behind `⋯` can be unit-tested directly instead of by
/// pumping a nine-cell grid. Both inputs matter: a 460px-wide cell with one CDN
/// line must not reserve room for a line button, and a 200px cell cannot show ten
/// hit targets regardless of what the data offers.
enum MultiviewControlsAction {
  playPause,
  refresh,
  audioFocus,
  danmaku,
  quality,
  line,
  volume,
  danmakuSettings,
  fullscreen,
  closeCell,
}

enum MultiviewControlsTier {
  /// Every available action fits inline.
  full,

  /// Low-priority actions move into `⋯`.
  compact,

  /// Transport controls only inline.
  iconsOnly,

  /// Play/pause plus `⋯`.
  minimal,

  /// No bar; the long-press sheet is the only entry point.
  hidden,
}

class MultiviewControlsLayout {
  const MultiviewControlsLayout({
    required this.tier,
    required this.barHeight,
    required this.iconSize,
    required this.hitTarget,
    required this.inlineActions,
    required this.overflowActions,
  });

  final MultiviewControlsTier tier;
  final double barHeight;
  final double iconSize;

  /// Minimum tappable side for one button; also the horizontal pitch.
  final double hitTarget;
  final List<MultiviewControlsAction> inlineActions;
  final List<MultiviewControlsAction> overflowActions;

  /// Space reserved at the right edge for the `⋯` button.
  static const double moreButtonWidth = 32;

  static const double _edgePadding = 8;

  bool get hasOverflow => overflowActions.isNotEmpty;

  bool get isVisible => tier != MultiviewControlsTier.hidden;
}

/// Left-to-right priority: anything past the budget falls into `⋯`.
const List<MultiviewControlsAction> _priority = <MultiviewControlsAction>[
  MultiviewControlsAction.playPause,
  MultiviewControlsAction.refresh,
  MultiviewControlsAction.audioFocus,
  MultiviewControlsAction.danmaku,
  MultiviewControlsAction.quality,
  MultiviewControlsAction.line,
  MultiviewControlsAction.volume,
  MultiviewControlsAction.fullscreen,
  MultiviewControlsAction.closeCell,
  MultiviewControlsAction.danmakuSettings,
];

MultiviewControlsLayout resolveMultiviewCellControlsLayout({
  required double cellWidth,
  required double cellHeight,
  required bool hasLineSwitch,
  required bool qualityAvailable,
  required bool pointerDevice,
}) {
  final (tier, barHeight, iconSize, hitTarget) = switch (cellWidth) {
    >= 460 => (MultiviewControlsTier.full, 34.0, 20.0, 34.0),
    >= 340 => (MultiviewControlsTier.compact, 30.0, 18.0, 30.0),
    >= 240 => (MultiviewControlsTier.iconsOnly, 28.0, 17.0, 28.0),
    >= 160 => (MultiviewControlsTier.minimal, 26.0, 16.0, 26.0),
    _ => (MultiviewControlsTier.hidden, 0.0, 16.0, 26.0),
  };

  // A bar taller than a quarter of the cell would eat the picture; drop to the
  // long-press sheet instead.
  if (cellHeight > 0 && cellHeight < barHeight * 4 && tier != MultiviewControlsTier.hidden) {
    return MultiviewControlsLayout(
      tier: MultiviewControlsTier.hidden,
      barHeight: 0,
      iconSize: iconSize,
      hitTarget: hitTarget,
      inlineActions: const <MultiviewControlsAction>[],
      overflowActions: const <MultiviewControlsAction>[],
    );
  }

  final available = <MultiviewControlsAction>[
    for (final action in _priority)
      if (action != MultiviewControlsAction.quality || qualityAvailable)
        if (action != MultiviewControlsAction.line || hasLineSwitch)
          // Touch devices already reach danmaku settings from the page toolbar;
          // spending a small-cell slot on it there is not worth it.
          if (action != MultiviewControlsAction.danmakuSettings || pointerDevice) action,
  ];

  if (tier == MultiviewControlsTier.hidden) {
    return MultiviewControlsLayout(
      tier: tier,
      barHeight: 0,
      iconSize: iconSize,
      hitTarget: hitTarget,
      inlineActions: const <MultiviewControlsAction>[],
      // The overflow menu still lists everything the data allows, so nothing
      // becomes unreachable on a narrow cell.
      overflowActions: available,
    );
  }

  final budget =
      ((cellWidth - MultiviewControlsLayout._edgePadding - MultiviewControlsLayout.moreButtonWidth) / hitTarget)
          .floor();
  final inlineCount = budget.clamp(1, available.length);
  return MultiviewControlsLayout(
    tier: tier,
    barHeight: barHeight,
    iconSize: iconSize,
    hitTarget: hitTarget,
    inlineActions: available.take(inlineCount).toList(growable: false),
    overflowActions: available.skip(inlineCount).toList(growable: false),
  );
}
