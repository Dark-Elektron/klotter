import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';

/// The view is where you got to by dragging, stored beside what you typed.
/// Losing it meant framing x over [0, 2π], closing the app, and finding
/// [-5, 5] again.
void main() {
  group('round-trips', () {
    test('a moved 2D window survives', () {
      const v = PlotViewState(xMin: 0, xMax: 6.28, yMin: -2, yMax: 2);
      final back = PlotViewState.fromJson(v.toJson());
      expect(back.xMin, equals(0));
      expect(back.xMax, closeTo(6.28, 1e-9));
      expect(back.yMin, equals(-2));
      expect(back.yMax, equals(2));
    });

    test('a 3D camera survives', () {
      const v = PlotViewState(
        show3D: true,
        rotationX: 1.1,
        rotationZ: -0.4,
        panX: 12,
        panY: -8,
        rangeX: 3,
        rangeY: 4,
        rangeZ: 9,
      );
      final back = PlotViewState.fromJson(v.toJson());
      expect(back.show3D, isTrue);
      expect(back.rotationX, closeTo(1.1, 1e-9));
      expect(back.rotationZ, closeTo(-0.4, 1e-9));
      expect(back.panX, equals(12));
      expect(back.rangeZ, equals(9));
    });
  });

  group('an untouched view is not stored', () {
    test('the default reports itself as initial', () {
      expect(const PlotViewState().isInitial, isTrue);
    });

    test('any change makes it worth storing', () {
      expect(const PlotViewState(xMin: -4).isInitial, isFalse);
      expect(const PlotViewState(show3D: true).isInitial, isFalse);
      expect(const PlotViewState(rotationX: 0.61).isInitial, isFalse);
    });
  });

  group('corrupt storage falls back rather than failing', () {
    test('missing fields take the default', () {
      final v = PlotViewState.fromJson(<String, dynamic>{'xMin': 1.0});
      expect(v.xMin, equals(1));
      expect(v.yMin, equals(const PlotViewState().yMin));
      expect(v.rotationX, equals(const PlotViewState().rotationX));
    });

    test('wrong types are ignored per field, not wholesale', () {
      // Half a saved view is better than dropping the user back to the origin.
      final v = PlotViewState.fromJson(<String, dynamic>{
        'xMin': 'nonsense',
        'xMax': 9.0,
        'rotationX': 1.5,
      });
      expect(v.rotationX, equals(1.5), reason: 'the good field survived');
      expect(v.xMin, equals(const PlotViewState().xMin));
    });

    test('a zero-width window is rejected, not restored', () {
      // It would render as a blank plot with nothing to explain it.
      final v = PlotViewState.fromJson(<String, dynamic>{
        'xMin': 3.0,
        'xMax': 3.0,
      });
      expect(v.xMin, equals(const PlotViewState().xMin));
      expect(v.xMax, equals(const PlotViewState().xMax));
    });

    test('an inverted window is rejected', () {
      final v = PlotViewState.fromJson(<String, dynamic>{
        'yMin': 5.0,
        'yMax': -5.0,
      });
      expect(v.yMin, equals(const PlotViewState().yMin));
    });

    test('non-finite values are refused', () {
      final v = PlotViewState.fromJson(<String, dynamic>{
        'panX': double.infinity,
        'rotationZ': double.nan,
      });
      expect(v.panX, equals(0));
      expect(v.rotationZ, equals(const PlotViewState().rotationZ));
    });

    test('a non-positive 3D range is refused', () {
      // Zero range divides by zero when scaling the world.
      final v = PlotViewState.fromJson(<String, dynamic>{
        'rangeX': 0.0,
        'rangeZ': -4.0,
      });
      expect(v.rangeX, equals(5));
      expect(v.rangeZ, equals(5));
    });
  });
}
