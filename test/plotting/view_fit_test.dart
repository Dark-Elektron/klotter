import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/painters/plot_3d_painter.dart';

/// How much of the panel the 3D box is allowed to use.
///
/// It used to be fitted as a cube to `min(width, height)`, which threw away
/// everything past that on the longer side — on a phone, most of the height.
/// The box floated in the middle with the z axis stopping well short of the
/// top.
void main() {
  /// The projected half-extents of the *arrow tips*, at the tilt the fit is
  /// made for. Those are what leaves the canvas first, not the box corners.
  ({double width, double height}) footprint(Size size) {
    final e = Plot3DPainter.viewExtentsFor(size);
    const double tilt = 0.6;
    const double reach = Plot3DPainter.axisArrowOvershoot;
    return (
      // A rotated box shows its diagonal.
      width: math.sqrt2 * reach * e.planar,
      height:
          reach *
          (e.vertical * math.cos(tilt) +
              math.sqrt2 * e.planar * math.sin(tilt)),
    );
  }

  double heightUsed(Size s) => 2 * footprint(s).height / s.height;
  double widthUsed(Size s) => 2 * footprint(s).width / s.width;

  group('a tall panel', () {
    // The phone in portrait, which is where the waste was visible.
    const Size phone = Size(1005, 1310);

    test('fills its height', () {
      expect(heightUsed(phone), greaterThan(0.9));
    });

    test('fills its width', () {
      expect(widthUsed(phone), greaterThan(0.9));
    });

    test('is taller than it is wide, in world terms', () {
      // The whole point: the vertical axis gets its own extent, so the box
      // stops being a cube on a panel that is not square.
      final e = Plot3DPainter.viewExtentsFor(phone);
      expect(e.vertical, greaterThan(e.planar));
    });
  });

  group('whatever the panel shape', () {
    const List<Size> shapes = <Size>[
      Size(1005, 1310), // phone portrait
      Size(400, 400), // square
      Size(360, 320), // a short inline panel
      Size(800, 300), // wide and shallow
      Size(300, 900), // very tall
    ];

    test('nothing runs off the canvas', () {
      for (final Size s in shapes) {
        // A little over is tolerable — perspective moves the near corner, and
        // the ribbon guard can push a short panel slightly past. Well over
        // means the arrowheads are being cut off.
        expect(heightUsed(s), lessThan(1.05), reason: 'height on $s');
        expect(widthUsed(s), lessThan(1.02), reason: 'width on $s');
      }
    });

    test('and the box is never squashed into a ribbon', () {
      for (final Size s in shapes) {
        final e = Plot3DPainter.viewExtentsFor(s);
        expect(
          e.vertical,
          greaterThan(e.planar * 0.5),
          reason: 'flattened on $s',
        );
      }
    });
  });

  test('the old cube fit wasted the height it now uses', () {
    // Documents what changed, in the terms the complaint was made in.
    const Size phone = Size(1005, 1310);
    const double old = 1005 * 0.30; // min(w, h) * 0.30, uniform
    const double tilt = 0.6;
    const double reach = Plot3DPainter.axisArrowOvershoot;
    final double before =
        2 *
        reach *
        (old * math.cos(tilt) + math.sqrt2 * old * math.sin(tilt)) /
        1310;
    expect(before, lessThan(0.9));
    expect(heightUsed(phone), greaterThan(before + 0.08));
  });
}
