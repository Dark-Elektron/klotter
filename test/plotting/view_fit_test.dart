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

  /// How tall the z axis alone projects — the segment on the axis itself,
  /// arrowhead included, with nothing of the floor in it.
  double zAxisHeight(Size size) {
    final ViewFit f = Plot3DPainter.viewExtentsFor(size);
    final double focal = Plot3DPainter.focalLengthFor(size);
    const double tilt = 0.6;
    const double reach = Plot3DPainter.axisArrowOvershoot;
    final double ct = math.cos(tilt);
    double top = double.negativeInfinity, bottom = double.infinity;
    for (final double sz in <double>[-1, 1]) {
      // On the axis, so azimuth cannot move it.
      final double z = sz * f.vertical * reach;
      final double k = focal / (focal - z * math.sin(tilt));
      final double y = -z * ct * k;
      top = math.max(top, -y);
      bottom = math.min(bottom, -y);
    }
    return top - bottom;
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

    test('draws its floor across most of the panel', () {
      // The floor, not the whole drawing — budgeting everything drawn hid
      // the fact that the visible grid covered under two thirds while the
      // box's top corners, which nobody reads as the width, touched both
      // edges.
      //
      // Not all of it: the floor's width and the z axis's height are one
      // budget, and _zAspect is where the two are traded off. A floor filling
      // the panel would leave the z axis at little over half the height.
      expect(footprint(phone).floor / phone.width, greaterThan(0.7));
    });

    test('and gives the z axis a comparable share of the height', () {
      // The other side of that trade, so a change to _zAspect that starves
      // one of them fails here rather than passing quietly.
      final f = Plot3DPainter.viewExtentsFor(phone);
      final double zShare = zAxisHeight(phone) / phone.height;
      expect(zShare, greaterThan(0.6), reason: 'z axis is only $zShare');
      expect(f.vertical, greaterThan(f.planar));
    });

    test('is a cuboid, with z the long axis', () {
      // The shape asked for: a cube left the height empty above the box.
      final ViewFit f = Plot3DPainter.viewExtentsFor(phone);
      // Only modestly taller than wide. z takes what the height affords once
      // the floor has the width, and on this panel that is not much more.
      expect(f.vertical, greaterThan(f.planar * 1.1));
    });

    test('and sits centred, not low', () {
      // The centring is the other half of the fix. Without it the drawing
      // hangs below the middle however well it is sized.
      final ViewFit f = Plot3DPainter.viewExtentsFor(phone);
      expect(f.offsetY, isNot(0));
    });
  });

  group('the two extents are independent', () {
    // The point of the whole arrangement. Every earlier version tied them
    // together — the panel is one budget, so a joint fit meant that raising
    // one lowered the other, and whichever was fitted first left the other
    // knob doing nothing at all.

    test('each is a fixed share of the panel, whatever its shape', () {
      // If either were fitted against the other, its share would move as the
      // panel changed shape. Neither does.
      final Set<String> planShares = <String>{};
      final Set<String> zShares = <String>{};
      for (final Size s in shapes) {
        final ViewFit f = Plot3DPainter.viewExtentsFor(s);
        planShares.add((f.planar / s.width).toStringAsFixed(6));
        zShares.add((f.vertical / s.height).toStringAsFixed(6));
      }
      expect(planShares, hasLength(1), reason: 'plan varies: $planShares');
      expect(zShares, hasLength(1), reason: 'z varies: $zShares');
    });

    test('neither reads the other', () {
      // Doubling the panel's height must not touch the plan, and doubling its
      // width must not touch z. Anything shared between them would show here.
      const Size base = Size(600, 600);
      final ViewFit a = Plot3DPainter.viewExtentsFor(base);
      final ViewFit taller = Plot3DPainter.viewExtentsFor(
        const Size(600, 1200),
      );
      final ViewFit wider = Plot3DPainter.viewExtentsFor(const Size(1200, 600));

      expect(taller.planar, a.planar, reason: 'a taller panel moved the plan');
      expect(wider.vertical, a.vertical, reason: 'a wider panel moved z');
    });
  });

  group('what the panel affords', () {
    test('the plan covers most of the width', () {
      // Turned, so the floor spans about 2.8 times its half-width.
      for (final Size s in shapes) {
        expect(
          footprint(s).floor / s.width,
          greaterThan(0.75),
          reason: 'on $s',
        );
      }
    });

    test('a portrait panel holds both, near enough', () {
      // Independence means nothing shrinks to make room, so nothing stops the
      // extents overrunning either — that is the documented cost, and the
      // table beside _zExtent says where it starts. This guards against a
      // value that is badly wrong, not against the last few percent, which is
      // a matter of taste and meant to be tuned.
      const Size phone = Size(988, 1210);
      expect(footprint(phone).height, lessThan(phone.height * 1.05));
      // The floor stays inside. Only the box's topmost corners lean past the
      // edge, which is the cheapest part of the drawing to lose.
      expect(footprint(phone).floor, lessThan(phone.width));
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
