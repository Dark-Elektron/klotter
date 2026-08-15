import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/models/view_fit.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';

/// How much of the panel the 3D box uses.
///
/// It used to be fitted as a cube to `min(width, height)`, centred on the
/// world origin. Both were wrong on a portrait panel: the cube threw away the
/// height, and centring on the origin hung the drawing low, because
/// perspective throws the near-bottom corner much further from the origin
/// than the far-top one. The box stopped well short of the top.
void main() {
  /// Where the drawing actually lands, measured the way the painter draws it:
  /// the box corners and arrow tips, projected over a full turn of azimuth at
  /// the tilt the fit is made for, with the fit's own centring applied.
  ({double width, double height}) footprint(Size size) {
    final ViewFit f = Plot3DPainter.viewExtentsFor(size);
    final double focal = Plot3DPainter.focalLengthFor(size);
    const double tilt = 0.6;
    const double reach = Plot3DPainter.axisArrowOvershoot;
    final double ct = math.cos(tilt), st = math.sin(tilt);

    double left = double.infinity, right = double.negativeInfinity;
    double top = double.infinity, bottom = double.negativeInfinity;

    for (int a = 0; a < 24; a++) {
      final double az = a * math.pi / 12;
      final double ca = math.cos(az), sa = math.sin(az);
      for (final List<double> p in <List<double>>[
        <double>[f.planar * reach, 0, 0],
        <double>[-f.planar * reach, 0, 0],
        <double>[0, f.planar * reach, 0],
        <double>[0, 0, f.vertical * reach],
        <double>[0, 0, -f.vertical * reach],
        for (final double sx in <double>[-1, 1])
          for (final double sy in <double>[-1, 1])
            for (final double sz in <double>[-1, 1])
              <double>[sx * f.planar, sy * f.planar, sz * f.vertical],
      ]) {
        final double vx = p[0] * ca - p[1] * sa;
        final double planeY = p[0] * sa + p[1] * ca;
        final double depth = planeY * ct - p[2] * st;
        final double vz = planeY * st + p[2] * ct;
        final double k = focal / (focal + depth);
        // The painter's own placement, offsets included.
        final double sxp = size.width / 2 + vx * k + f.offsetX;
        final double syp = size.height / 2 - vz * k + f.offsetY;
        left = math.min(left, sxp);
        right = math.max(right, sxp);
        top = math.min(top, syp);
        bottom = math.max(bottom, syp);
      }
    }
    return (width: right - left, height: bottom - top);
  }

  const List<Size> shapes = <Size>[
    Size(988, 1210), // the phone in portrait, where the waste showed
    Size(400, 400), // square
    Size(360, 320), // a short inline panel
    Size(800, 300), // wide and shallow
    Size(300, 900), // very tall
  ];

  group('a portrait panel', () {
    const Size phone = Size(988, 1210);

    test('fills its height', () {
      expect(footprint(phone).height / phone.height, greaterThan(0.9));
    });

    test('fills its width', () {
      expect(footprint(phone).width / phone.width, greaterThan(0.9));
    });

    test('is a cuboid, with z the long axis', () {
      // The shape asked for: a cube left the height empty above the box.
      final ViewFit f = Plot3DPainter.viewExtentsFor(phone);
      expect(f.vertical, greaterThan(f.planar * 1.2));
    });

    test('and sits centred, not low', () {
      // The centring is the other half of the fix. Without it the drawing
      // hangs below the middle however well it is sized.
      final ViewFit f = Plot3DPainter.viewExtentsFor(phone);
      expect(f.offsetY, isNot(0));
    });
  });

  group('whatever the panel shape', () {
    test('nothing runs off the canvas', () {
      for (final Size s in shapes) {
        expect(footprint(s).height, lessThan(s.height), reason: 'height on $s');
        expect(footprint(s).width, lessThan(s.width), reason: 'width on $s');
      }
    });

    test('one dimension or the other is filled', () {
      for (final Size s in shapes) {
        // The box is as big as it can be, so whichever constraint binds is
        // met almost exactly. Only one of them can be: on a panel much wider
        // than it is tall the height binds and the width is left largely
        // empty, which is correct — filling it would push the box off the
        // top and bottom.
        final f = footprint(s);
        final double filled = math.max(f.width / s.width, f.height / s.height);
        // 0.88 rather than the 0.96 margin because the aspect is searched
        // over a fixed set of steps, so the best cuboid for a given panel is
        // not always exactly on one of them.
        expect(filled, greaterThan(0.88), reason: 'on $s');
      }
    });

    test('z is never the short axis', () {
      for (final Size s in shapes) {
        final ViewFit f = Plot3DPainter.viewExtentsFor(s);
        expect(f.vertical, greaterThanOrEqualTo(f.planar), reason: 'on $s');
      }
    });
  });

  test('the fit is cached, so it is not re-searched every paint', () {
    // The search projects a few thousand points; it runs on every paint and
    // every pick, and the panel size rarely changes.
    const Size s = Size(988, 1210);
    final a = Plot3DPainter.viewExtentsFor(s);
    final b = Plot3DPainter.viewExtentsFor(s);
    expect(identical(a, b), isTrue);
  });
}
