import '../parsers/plot_expression.dart';

/// Something worth snapping the trace to.
enum FeatureKind { root, minimum, maximum }

class CurveFeature {
  final double x;
  final double y;
  final FeatureKind kind;
  const CurveFeature(this.x, this.y, this.kind);

  String get label => switch (kind) {
    FeatureKind.root => 'root',
    FeatureKind.minimum => 'min',
    FeatureKind.maximum => 'max',
  };
}

/// Find the roots and turning points of [curve] across the visible window.
///
/// This is what turns the crosshair from a readout into an answer: "where does
/// this cross zero" is a calculator question, and the plot can answer it
/// exactly rather than leaving you to eyeball the pixel.
///
/// Sampling is uniform and then refined, which is honest about its limits — a
/// feature narrower than the sample spacing is missed, and no amount of
/// refinement recovers it. [samples] therefore sets the resolution, not the
/// accuracy: found features are accurate to ~1e-9, but only features wider
/// than `(xMax - xMin) / samples` are found at all.
List<CurveFeature> findFeatures(
  PlotExpression curve,
  double xMin,
  double xMax, {
  int samples = 600,
}) {
  if (!curve.isValid || xMax <= xMin) return const <CurveFeature>[];

  // An equation is not a function of x, so sampling it as one finds the roots
  // and turning points of F(x, 0) rather than of the curve — for x²+y²=1 that
  // reports "root" at x = ±1 for the wrong reason and extrema that are not on
  // the circle at all. Snapping offers nothing here rather than something
  // untrue; the trace still solves for the y values.
  if (curve.isLevelSet) return const <CurveFeature>[];

  final List<CurveFeature> out = <CurveFeature>[];
  final double step = (xMax - xMin) / samples;

  double? previousX;
  double? previousY;
  double? beforePreviousY;

  for (int i = 0; i <= samples; i++) {
    final double x = xMin + i * step;
    final double y = curve.evaluate(x);

    if (y.isFinite && previousY != null && previousY.isFinite) {
      // Sign change brackets a root. A discontinuity also flips sign, so
      // reject brackets where the curve jumps instead of crossing.
      if ((previousY < 0) != (y < 0)) {
        final double jump = (y - previousY).abs();
        final double scale = previousY.abs() + y.abs();
        if (jump < scale * 4) {
          final double root = _bisectRoot(curve, previousX!, x);
          if (root.isFinite) out.add(CurveFeature(root, 0, FeatureKind.root));
        }
      }

      // A turning point shows as the middle sample being the local extreme.
      if (beforePreviousY != null && beforePreviousY.isFinite) {
        final bool isMax = previousY > beforePreviousY && previousY > y;
        final bool isMin = previousY < beforePreviousY && previousY < y;
        if (isMax || isMin) {
          final double xt = _refineExtremum(
            curve,
            previousX! - step,
            previousX + step,
            maximum: isMax,
          );
          final double yt = curve.evaluate(xt);
          if (xt.isFinite && yt.isFinite) {
            out.add(
              CurveFeature(
                xt,
                yt,
                isMax ? FeatureKind.maximum : FeatureKind.minimum,
              ),
            );
          }
        }
      }
    }

    beforePreviousY = previousY;
    previousY = y;
    previousX = x;
  }

  return _dedupe(out, step);
}

/// A feature straddling two sample intervals can be reported twice — once from
/// each bracket. Collapse neighbours of the same kind.
List<CurveFeature> _dedupe(List<CurveFeature> features, double step) {
  if (features.length < 2) return features;
  final List<CurveFeature> sorted = List<CurveFeature>.of(features)
    ..sort((a, b) => a.x.compareTo(b.x));
  final List<CurveFeature> out = <CurveFeature>[sorted.first];
  for (final CurveFeature f in sorted.skip(1)) {
    final CurveFeature last = out.last;
    if (f.kind == last.kind && (f.x - last.x).abs() <= step) continue;
    out.add(f);
  }
  return out;
}

/// The feature nearest [x], or null if none lies within [tolerance].
CurveFeature? nearestFeature(
  List<CurveFeature> features,
  double x,
  double tolerance,
) {
  CurveFeature? best;
  double bestDistance = double.infinity;
  for (final CurveFeature f in features) {
    final double d = (f.x - x).abs();
    if (d < bestDistance) {
      bestDistance = d;
      best = f;
    }
  }
  return bestDistance <= tolerance ? best : null;
}

double _bisectRoot(PlotExpression curve, double lo, double hi) {
  double a = lo;
  double b = hi;
  double fa = curve.evaluate(a);
  for (int i = 0; i < 60; i++) {
    final double mid = (a + b) / 2;
    final double fm = curve.evaluate(mid);
    if (!fm.isFinite) return mid;
    if (fm == 0) return mid;
    if ((fa < 0) != (fm < 0)) {
      b = mid;
    } else {
      a = mid;
      fa = fm;
    }
  }
  return (a + b) / 2;
}

/// Golden-section search: no derivative required, which matters because the
/// engine can differentiate symbolically but not for every expression it can
/// sample.
double _refineExtremum(
  PlotExpression curve,
  double lo,
  double hi, {
  required bool maximum,
}) {
  const double invPhi = 0.6180339887498949;
  double a = lo;
  double b = hi;
  double c = b - (b - a) * invPhi;
  double d = a + (b - a) * invPhi;

  double score(double x) {
    final double y = curve.evaluate(x);
    if (!y.isFinite) return maximum ? -double.infinity : double.infinity;
    return maximum ? y : -y;
  }

  for (int i = 0; i < 80 && (b - a).abs() > 1e-10; i++) {
    if (score(c) > score(d)) {
      b = d;
    } else {
      a = c;
    }
    c = b - (b - a) * invPhi;
    d = a + (b - a) * invPhi;
  }
  return (a + b) / 2;
}
