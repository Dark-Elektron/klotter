import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/models/plot_view_state.dart';

/// The sweep is part of the view, not part of the expression.
///
/// It is something you dialled in, like a window or a camera angle, and
/// swiping to the next plot and back used to hand it silently back to the
/// default.
void main() {
  test('a dialled-in sweep survives being saved and restored', () {
    const PlotViewState set = PlotViewState(
      uMin: -1,
      uMax: 2 * math.pi,
      vMin: 0.5,
      vMax: 3,
    );
    final PlotViewState back = PlotViewState.fromJson(set.toJson());
    expect(back.uMin, set.uMin);
    expect(back.uMax, set.uMax);
    expect(back.vMin, set.vMin);
    expect(back.vMax, set.vMax);
  });

  test('the default is the unit interval', () {
    expect(PlotViewState.initial.uMin, 0);
    expect(PlotViewState.initial.uMax, 1);
    expect(PlotViewState.initial.vMin, 0);
    expect(PlotViewState.initial.vMax, 1);
  });

  test('a view with only the sweep changed is not the initial one', () {
    // Otherwise it is treated as untouched and never written, which is
    // exactly how it went missing.
    const PlotViewState swept = PlotViewState(uMax: 2 * math.pi);
    expect(swept.isInitial, isFalse);
    expect(PlotViewState.initial.isInitial, isTrue);
  });

  test('copyWith carries the sweep through', () {
    // The path the panel actually uses when it publishes its view.
    final PlotViewState v = PlotViewState.initial.copyWith(
      uMin: 1,
      uMax: 4,
      vMin: -2,
      vMax: 2,
    );
    expect(v.uMin, 1);
    expect(v.uMax, 4);
    expect(v.vMin, -2);
    expect(v.vMax, 2);
    // And leaves the rest alone.
    expect(v.rangeZ, PlotViewState.initial.rangeZ);
  });

  test('a zero-width sweep is rejected, like a zero-width window', () {
    // It draws nothing, and silently restoring an empty plot is worse than
    // restoring the default one.
    final PlotViewState back = PlotViewState.fromJson(<String, dynamic>{
      'uMin': 2.0,
      'uMax': 2.0,
      'vMin': 0.0,
      'vMax': 5.0,
    });
    expect(back.uMin, PlotViewState.initial.uMin);
    expect(back.uMax, PlotViewState.initial.uMax);
    // The good one is untouched.
    expect(back.vMax, 5.0);
  });

  test('a saved view from before the sweep existed still loads', () {
    // Old stored views have no u or v keys at all.
    final PlotViewState back = PlotViewState.fromJson(<String, dynamic>{
      'show3D': true,
      'xMin': -2.0,
      'xMax': 2.0,
    });
    expect(back.show3D, isTrue);
    expect(back.xMin, -2.0);
    expect(back.uMax, PlotViewState.initial.uMax);
    expect(back.vMax, PlotViewState.initial.vMax);
  });
}
