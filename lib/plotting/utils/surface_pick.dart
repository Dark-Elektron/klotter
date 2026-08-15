import 'dart:math';
import 'dart:ui';

import '../painters/plot_3d_painter.dart';
import '../models/view_fit.dart';
import '../parsers/plot_expression.dart';

/// A point on a surface, in data coordinates, with the line it came from.
typedef SurfaceHit = ({double x, double y, double z, int curveIndex});

/// The camera a 3D plot is drawn through.
///
/// Holds exactly what [Plot3DPainter] uses to project, so picking can invert
/// the same transform. The constants come from the painter rather than being
/// repeated here — a second copy would drift and put the marker where the
/// surface is not.
class PlotCamera {
  PlotCamera({
    required this.size,
    required this.rotationX,
    required this.rotationZ,
    required this.panX,
    required this.panY,
    required this.rangeX,
    required this.rangeY,
    required this.rangeZ,
  }) : _extents = Plot3DPainter.viewExtentsFor(size);

  final Size size;
  final double rotationX, rotationZ;
  final double panX, panY;
  final double rangeX, rangeY, rangeZ;
  final ViewFit _extents;

  double get scaleX => _extents.planar / rangeX;
  double get scaleY => _extents.planar / rangeY;
  double get scaleZ => _extents.vertical / rangeZ;

  /// Data point to screen, matching `Point3D.rotateZ().rotateX().project()`.
  Offset project(double x, double y, double z) {
    final (double vx, double vy, double vz) = _toView(
      x * scaleX,
      y * scaleY,
      z * scaleZ,
    );
    final double f = Plot3DPainter.focalLengthFor(size);
    final double scale = f / (f + vy);
    return Offset(
      size.width / 2 + vx * scale + panX + _extents.offsetX,
      size.height / 2 - vz * scale + panY + _extents.offsetY,
    );
  }

  /// World to view: azimuth first, then elevation — the turntable order the
  /// painter uses everywhere.
  (double, double, double) _toView(double x, double y, double z) {
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double x1 = x * cz - y * sz;
    final double y1 = x * sz + y * cz;
    return (x1, y1 * cx - z * sx, y1 * sx + z * cx);
  }

  /// View back to world, undoing [_toView] in reverse.
  (double, double, double) _toWorld(double x, double y, double z) {
    final double cx = cos(rotationX), sx = sin(rotationX);
    final double y1 = y * cx + z * sx;
    final double z0 = -y * sx + z * cx;
    final double cz = cos(rotationZ), sz = sin(rotationZ);
    return (x * cz + y1 * sz, -x * sz + y1 * cz, z0);
  }

  /// The data point under [screen] at view-space depth [depth].
  ///
  /// A screen point does not name a point in the scene, only a ray through it;
  /// [depth] chooses how far along that ray to look. This is the projection
  /// solved for the world point instead of the screen one.
  (double, double, double) unproject(Offset screen, double depth) {
    final double f = Plot3DPainter.focalLengthFor(size);
    final double inv = (f + depth) / f;
    final double vx =
        (screen.dx - size.width / 2 - panX - _extents.offsetX) * inv;
    final double vz =
        (size.height / 2 + panY + _extents.offsetY - screen.dy) * inv;
    final (double wx, double wy, double wz) = _toWorld(vx, depth, vz);
    return (wx / scaleX, wy / scaleY, wz / scaleZ);
  }

  /// Depth range of the drawn box, so a ray is only marched where there is
  /// something to hit.
  (double, double) get depthSpan {
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final double sx in <double>[-1, 1]) {
      for (final double sy in <double>[-1, 1]) {
        for (final double sz in <double>[-1, 1]) {
          final (_, double vy, _) = _toView(
            sx * rangeX * scaleX,
            sy * rangeY * scaleY,
            sz * rangeZ * scaleZ,
          );
          lo = min(lo, vy);
          hi = max(hi, vy);
        }
      }
    }
    return (lo, hi);
  }
}

/// Where a touch first meets a surface.
///
/// A touch in 3D picks out a ray, not a point, so this marches the ray from
/// near to far and returns the first crossing — the point that was visually
/// touched, not one hidden behind it. Null when the ray misses everything,
/// which is a real answer: there is nothing under that part of the plot.
///
/// The root function differs by what the line means. A height `z = f(x, y)` is
/// hit where the ray's own z meets the surface's; an equation `F = 0` is hit
/// where F vanishes. Both are found the same way — walk for a sign change,
/// then bisect — as [levelSetYAt] does for the 2D trace.
///
/// Single-variable lines (`sin(x)`, `sin(z)`) are curves, not surfaces, and a
/// ray does not meaningfully meet one; they are skipped.
SurfaceHit? pickSurface(
  PlotCamera camera,
  List<PlotExpression> curves,
  Offset screen, {
  int samples = 320,
}) {
  final (double near, double far) = camera.depthSpan;
  if (!near.isFinite || !far.isFinite || far <= near) return null;

  SurfaceHit? best;
  double bestDepth = double.infinity;

  for (int i = 0; i < curves.length; i++) {
    final PlotExpression curve = curves[i];
    if (!curve.isValid) continue;
    if (!curve.isLevelSet && !curve.isSurface) continue;

    // Signed distance to the surface along the ray, or NaN where there is
    // nothing to compare against.
    double at(double depth) {
      final (double x, double y, double z) = camera.unproject(screen, depth);
      if (x.abs() > camera.rangeX || y.abs() > camera.rangeY) return double.nan;
      if (curve.isLevelSet) {
        if (z.abs() > camera.rangeZ) return double.nan;
        return curve.evaluate(x, y, z);
      }
      final double surface = curve.evaluate(x, y);
      // Outside the z window the surface is not drawn, so it is not pickable.
      if (!surface.isFinite || surface.abs() > camera.rangeZ) return double.nan;
      return z - surface;
    }

    double previousDepth = near;
    double previous = at(near);

    for (int s = 1; s <= samples; s++) {
      final double depth = near + (far - near) * s / samples;
      final double value = at(depth);

      final bool crossed =
          previous.isFinite &&
          value.isFinite &&
          previous != 0 &&
          previous.isNegative != value.isNegative;

      if (value == 0 || crossed) {
        double hit = depth;
        if (crossed) {
          double lo = previousDepth, hi = depth, atLo = previous;
          for (int step = 0; step < 50; step++) {
            final double mid = (lo + hi) / 2;
            final double atMid = at(mid);
            if (!atMid.isFinite) break;
            if (atMid.isNegative == atLo.isNegative) {
              lo = mid;
              atLo = atMid;
            } else {
              hi = mid;
            }
          }
          hit = (lo + hi) / 2;
        }
        if (hit < bestDepth) {
          final (double x, double y, double z) = camera.unproject(screen, hit);
          bestDepth = hit;
          best = (x: x, y: y, z: z, curveIndex: i);
        }
        // Nearest crossing on this curve is enough; anything behind it is
        // hidden by the surface just found.
        break;
      }

      previousDepth = depth;
      previous = value;
    }
  }

  return best;
}
