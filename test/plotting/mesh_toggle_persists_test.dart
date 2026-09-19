import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/models/plot_view_state.dart';

/// The mesh toggle survives being swiped away.
///
/// It was panel state and nothing else, so moving to the next plot and back
/// built a fresh panel with the mesh off — the button appeared to turn itself
/// off whenever you left the plot.
void main() {
  test('a saved view carries the mesh', () {
    const PlotViewState on = PlotViewState(showMesh: true);
    expect(on.showMesh, isTrue);
    expect(
      on.isInitial,
      isFalse,
      reason: 'a view with the mesh on reads as untouched, so it is discarded',
    );
  });

  test('it survives a round trip through storage', () {
    const PlotViewState on = PlotViewState(showMesh: true);
    expect(PlotViewState.fromJson(on.toJson()).showMesh, isTrue);

    const PlotViewState off = PlotViewState();
    expect(PlotViewState.fromJson(off.toJson()).showMesh, isFalse);
  });

  test('an older saved view, from before the mesh, restores as off', () {
    // Anything written before this existed has no key for it, and a missing
    // key must not read as on.
    expect(
      PlotViewState.fromJson(<String, dynamic>{'rangeX': 5}).showMesh,
      isFalse,
    );
  });

  test('copyWith carries it', () {
    expect(const PlotViewState().copyWith(showMesh: true).showMesh, isTrue);
  });
}
