import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/multiview/multiview_cell_controls_layout.dart';

MultiviewControlsLayout resolve({
  required double width,
  double height = 240,
  bool hasLineSwitch = true,
  bool qualityAvailable = true,
  bool pointerDevice = true,
}) => resolveMultiviewCellControlsLayout(
  cellWidth: width,
  cellHeight: height,
  hasLineSwitch: hasLineSwitch,
  qualityAvailable: qualityAvailable,
  pointerDevice: pointerDevice,
);

void main() {
  const allActions = MultiviewControlsAction.values;

  test('a wide cell keeps every available action inline', () {
    final layout = resolve(width: 900);
    expect(layout.tier, MultiviewControlsTier.full);
    expect(layout.inlineActions, containsAll(allActions));
    expect(layout.overflowActions, isEmpty);
    expect(layout.hasOverflow, isFalse);
  });

  test('inline actions are a prefix of the priority order; the tail falls into overflow', () {
    const priority = <MultiviewControlsAction>[
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

    for (final width in <double>[900, 460, 360, 250, 170]) {
      final layout = resolve(width: width);
      expect(
        layout.inlineActions,
        priority.take(layout.inlineActions.length),
        reason: 'width $width must keep the highest-priority actions inline',
      );
      expect(
        layout.overflowActions,
        priority.skip(layout.inlineActions.length).where(layout.overflowActions.contains),
        reason: 'width $width overflow must be the remaining tail',
      );
    }

    // A 250px cell fits seven of ten, so the low-priority tail is reachable only
    // through the `...` menu.
    final iconsOnly = resolve(width: 250);
    expect(iconsOnly.inlineActions.length, 7);
    expect(iconsOnly.overflowActions, contains(MultiviewControlsAction.danmakuSettings));
    expect(iconsOnly.overflowActions, contains(MultiviewControlsAction.closeCell));
    expect(iconsOnly.hasOverflow, isTrue);

    // A 900px cell fits everything, so there is no menu to open at all.
    final full = resolve(width: 900);
    expect(full.overflowActions, isEmpty);
    expect(full.hasOverflow, isFalse);
  });

  test('nothing becomes unreachable: inline plus overflow always covers the allowed set', () {
    final allowed = <MultiviewControlsAction>[
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
    for (final width in <double>[900, 460, 360, 250, 170, 120]) {
      final layout = resolve(width: width);
      expect(
        <MultiviewControlsAction>{...layout.inlineActions, ...layout.overflowActions},
        allowed.toSet(),
        reason: 'width $width must still expose every allowed action somewhere',
      );
    }
  });

  test('a cell too narrow for a bar falls back to the long-press sheet', () {
    final hidden = resolve(width: 120);
    expect(hidden.tier, MultiviewControlsTier.hidden);
    expect(hidden.isVisible, isFalse);
    expect(hidden.inlineActions, isEmpty);
    expect(hidden.overflowActions, isNotEmpty);
  });

  test('a cell too short for a bar also hides it', () {
    final layout = resolve(width: 900, height: 60);
    expect(layout.tier, MultiviewControlsTier.hidden);
    expect(layout.isVisible, isFalse);
  });

  test('actions the data cannot offer are absent from both lists', () {
    final noLine = resolve(width: 900, hasLineSwitch: false);
    expect(noLine.inlineActions, isNot(contains(MultiviewControlsAction.line)));
    expect(noLine.overflowActions, isNot(contains(MultiviewControlsAction.line)));

    final noQuality = resolve(width: 900, qualityAvailable: false);
    expect(noQuality.inlineActions, isNot(contains(MultiviewControlsAction.quality)));
    expect(noQuality.overflowActions, isNot(contains(MultiviewControlsAction.quality)));

    // Danmaku settings is a desktop-only affordance: touch users reach it from
    // the page toolbar, so it must not consume a small-cell slot.
    final touch = resolve(width: 900, pointerDevice: false);
    expect(touch.overflowActions, isNot(contains(MultiviewControlsAction.danmakuSettings)));
    expect(touch.inlineActions, isNot(contains(MultiviewControlsAction.danmakuSettings)));
  });

  test('band edges are inclusive on the larger side', () {
    expect(resolve(width: 460).tier, MultiviewControlsTier.full);
    expect(resolve(width: 459.9).tier, MultiviewControlsTier.compact);
    expect(resolve(width: 340).tier, MultiviewControlsTier.compact);
    expect(resolve(width: 339.9).tier, MultiviewControlsTier.iconsOnly);
    expect(resolve(width: 240).tier, MultiviewControlsTier.iconsOnly);
    expect(resolve(width: 239.9).tier, MultiviewControlsTier.minimal);
    expect(resolve(width: 160).tier, MultiviewControlsTier.minimal);
    expect(resolve(width: 159.9).tier, MultiviewControlsTier.hidden);
  });

  test('hit targets never shrink below a finger-friendly pitch', () {
    for (final width in <double>[900, 460, 340, 240, 170]) {
      final layout = resolve(width: width);
      expect(layout.hitTarget, greaterThanOrEqualTo(26));
      expect(layout.iconSize, greaterThanOrEqualTo(16));
      // Inline buttons plus the reserved `...` must fit the measured width.
      expect(
        layout.inlineActions.length * layout.hitTarget + MultiviewControlsLayout.moreButtonWidth,
        lessThanOrEqualTo(width + 0.5),
        reason: 'width $width cannot fit ${layout.inlineActions.length} buttons',
      );
    }
  });
}
