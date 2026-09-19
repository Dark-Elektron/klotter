import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/models/plane_slice.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/widgets/plane_slice_gutter.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';

/// The slice strip shares a corner with controls that come and go.
void main() {
  final AppColors colors = AppColors.fromType(ThemeType.dark);
  final PlotThemeData theme = PlotThemeData.fromColors(colors);
  const double buttonSize = 40;

  Widget wrap({
    double height = 400,
    double footInset = 0,
    PlaneSlice slice = const PlaneSlice(),
    bool chosen = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: height,
            child: PlaneSliceGutter(
              slice: slice,
              extent: 5,
              theme: theme,
              chosen: chosen,
              buttonSize: buttonSize,
              footInset: footInset,
              onChanged: (_) {},
              onSlideStart: () {},
              onSlideEnd: () {},
              onAxisTapped: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the button is square and the size of the plot\'s others', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    final Size size = tester.getSize(
      find.ancestor(of: find.text('z'), matching: find.byType(Container)).first,
    );
    expect(size.width, buttonSize);
    expect(size.height, buttonSize);
  });

  testWidgets('the knobs push the button up rather than sitting on it', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());
    final double bare = tester.getRect(find.text('z')).bottom;

    // One parameter chip showing: the strip stands off by the pile's height.
    await tester.pumpWidget(wrap(footInset: buttonSize + 14 + 26));
    final double cleared = tester.getRect(find.text('z')).bottom;

    expect(
      cleared,
      lessThan(bare),
      reason: 'the button did not move up for the knobs',
    );
    expect(bare - cleared, closeTo(buttonSize + 14 + 26, 0.5));
  });

  testWidgets('a short panel shrinks the slider instead of overflowing', (
    tester,
  ) async {
    // The strip is given the full height of the plot, which on a small cell is
    // not much. A fixed-length slider overflowed here; a capped one shrinks.
    for (final double height in <double>[150, 200, 400]) {
      await tester.pumpWidget(wrap(height: height));
      expect(
        tester.takeException(),
        isNull,
        reason: 'the strip overflowed at ${height}px tall',
      );
    }
  });

  testWidgets('it still fits when the knobs are there and the panel is short', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(height: 180, footInset: buttonSize + 14 + 52));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the button names the plane, and says when it was chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(slice: const PlaneSlice(axis: SliceAxis.x, offset: 1.5)),
    );
    expect(find.text('x'), findsOneWidget);
    // The offset is on show too: an unlabelled slice is the state the strip
    // exists to get rid of.
    expect(find.text('1.50'), findsOneWidget);
  });

  testWidgets('a round offset is not padded with decimals', (tester) async {
    await tester.pumpWidget(wrap(slice: const PlaneSlice(offset: 2)));
    expect(find.text('2'), findsOneWidget);
  });
}
