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
  ({double width, double height, double floor}) footprint(Size size) {
    final ViewFit f = Plot3DPainter.viewExtentsFor(size);
    final double focal = Plot3DPainter.focalLengthFor(size);
    const double tilt = 0.6;
    const double reach = Plot3DPainter.axisArrowOvershoot;
    final double ct = math.cos(tilt), st = math.sin(tilt);

    double left = double.infinity, right = double.negativeInfinity;
    double top = double.infinity, bottom = double.negativeInfinity;
    double floorLeft = double.infinity, floorRight = double.negativeInfinity;

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
        if (p[2] == -f.vertical) {
          floorLeft = math.min(floorLeft, sxp);
          floorRight = math.max(floorRight, sxp);
        }
      }
    }
    return (
      width: right - left,
      height: bottom - top,
      floor: floorRight - floorLeft,
    );
  }

  const List<Size> shapes = <Size>[
    Size(988, 1210), // the phone in portrait, where the waste showed
    Size(400, 400), // square
    Size(360, 320), // a short inline panel
    Size(800, 300), // wide and shallow
    Size(2000, 790), // a tablet in landscape
    Size(300, 900), // very tall
  ];

  group('the shape comes from the knobs, the size from the panel', () {
    // _planExtent and _zExtent set the proportions of the box. How big that
    // box may be cannot be written down in advance, because it depends on the
    // panel: the same proportions that fill a phone overrun a landscape
    // tablet by half again, since the floor is drawn tilted and a wide panel
    // gives it a depth the panel has no height for. So the pair is scaled
    // together until it fits.

    test('the proportions are constant within a form factor', () {
      // Not across all panels — the z extent is deliberately split three ways,
      // so a landscape tablet, a portrait tablet and a phone each have their
      // own. What must hold is that the shape depends only on which of those
      // a panel is, and not on its exact pixel size: two panels of the same
      // kind get the same box.
      final Map<String, Set<String>> byKind = <String, Set<String>>{};
      for (final Size s in <Size>[
        Size(2000, 790), Size(1400, 600), // landscape tablets
        Size(1600, 1100), Size(800, 900), // portrait tablets
        Size(411, 700), Size(360, 640), // phones
      ]) {
        final ViewFit f = Plot3DPainter.viewExtentsFor(s);
        final String kind =
            s.shortestSide < 600 && s.width < 600
                ? 'phone'
                : (s.width > s.height ? 'landscape' : 'portrait');
        byKind
            .putIfAbsent(kind, () => <String>{})
            .add(
              (f.vertical / f.planar * (s.width / s.height)).toStringAsFixed(2),
            );
      }
      for (final MapEntry<String, Set<String>> e in byKind.entries) {
        expect(e.value, hasLength(1), reason: '${e.key} varies: ${e.value}');
      }
    });

    test('and the width is used in full', () {
      // What the sizing is for. Scaling the box down until it fitted the
      // height was tried twice and rejected both times: on a wide screen it
      // gives up the one dimension that screen has plenty of.
      for (final Size s in shapes) {
        expect(
          footprint(s).width / s.width,
          greaterThan(0.9),
          reason: 'width on $s',
        );
      }
    });

    test('a panel too short for the box loses the bottom, not the top', () {
      // A landscape tablet cannot hold a full-width floor: it is deeper than
      // the panel is tall. Centring split the loss between top and bottom,
      // and the top is where the surface is — the bottom of the box is
      // mostly the empty half below the floor, which is the part to lose.
      const Size tablet = Size(2000, 790);
      final ViewFit f = Plot3DPainter.viewExtentsFor(tablet);
      final footprintOf = footprint(tablet);
      expect(
        footprintOf.height,
        greaterThan(tablet.height),
        reason: 'this panel is only interesting if the box overruns it',
      );
      // Hung from the top: the offset pushes the drawing down rather than
      // splitting the difference.
      expect(f.offsetY, isNot(0));
    });

    test('while still filling one dimension of it', () {
      // Scaled to fit, not scaled down: whichever way round the panel is, the
      // drawing reaches across it.
      for (final Size s in shapes) {
        final f = footprint(s);
        expect(
          math.max(f.width / s.width, f.height / s.height),
          greaterThan(0.9),
          reason: 'on $s',
        );
      }
    });

    test('and sits centred, not low', () {
      final ViewFit f = Plot3DPainter.viewExtentsFor(const Size(988, 1210));
      expect(f.offsetY, isNot(0));
    });
  });

  // NOT TESTED: that what is *drawn* ends up centred.
  //
  // The geometry above is centred, and measuring the rendered pixels shows
  // the ink is not — it sits high, and on a wide panel it sits right as well.
  // The two differ because the ink is the surface, the floor and the axes,
  // while the centring is computed from the box corners and the arrow tips.
  // No assertion here until that is understood, rather than one that locks in
  // a number nobody has explained.

  test('the fit is cached, so it is not re-searched every paint', () {
    // The search projects a few thousand points; it runs on every paint and
    // every pick, and the panel size rarely changes.
    const Size s = Size(988, 1210);
    final a = Plot3DPainter.viewExtentsFor(s);
    final b = Plot3DPainter.viewExtentsFor(s);
    expect(identical(a, b), isTrue);
  });
}
