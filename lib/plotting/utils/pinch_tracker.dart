import 'dart:ui' show Offset;

/// Measures a pinch separately along each axis, from raw pointer positions.
///
/// [ScaleUpdateDetails.horizontalScale] and `verticalScale` look like they
/// already do this, but both are ratios against the finger separation at the
/// moment the gesture started, and that separation is the problem. Fingers
/// pinching top-to-bottom start a pixel or two out of level; the horizontal
/// ratio is then measured against a baseline of about 2px, so drifting to 5px
/// reports a 2.5x horizontal zoom that the hand never asked for. When the
/// fingers do line up exactly the baseline is zero, and the ratio is a division
/// by zero: the window becomes Infinity or NaN, and every later frame throws
/// `Unsupported operation: Infinity or NaN toInt` out of the painter's grid
/// spacing.
///
/// Measuring the raw separation instead means an axis can simply be ignored
/// while the fingers are level along it, which is also the behaviour a pinch
/// should have: pinch up and down and only the vertical axis moves.
class PinchTracker {
  /// Finger separation along an axis below which that axis is not being
  /// pinched at all.
  ///
  /// Two fingers this close together on an axis are level, and their
  /// separation says nothing about how that axis should scale — the ratio
  /// between two spans this small is jitter. About 5mm on a phone, which a
  /// deliberate diagonal pinch clears easily on both axes.
  static const double minSpan = 32.0;

  /// Largest per-update change accepted on one axis.
  ///
  /// A finger lifting and landing elsewhere can move a span across the screen
  /// between two frames. Real pinching moves it a few percent per frame.
  static const double _maxStep = 4.0;

  final Map<int, Offset> _pointers = <int, Offset>{};
  double _lastSpanX = 0;
  double _lastSpanY = 0;

  void down(int pointer, Offset position) {
    _pointers[pointer] = position;
    _rebase();
  }

  void move(int pointer, Offset position) {
    if (_pointers.containsKey(pointer)) _pointers[pointer] = position;
  }

  void up(int pointer) {
    _pointers.remove(pointer);
    _rebase();
  }

  /// Forget the baseline without forgetting where the fingers are, so the next
  /// read establishes a fresh one instead of comparing across a change in
  /// which fingers are down.
  void _rebase() {
    _lastSpanX = 0;
    _lastSpanY = 0;
  }

  /// Scale along each axis since the previous read.
  ///
  /// Returns 1.0 for an axis the fingers are level along, for the first read of
  /// a gesture, and whenever fewer than two fingers are down — so a caller can
  /// apply both factors unconditionally.
  ({double x, double y}) read() {
    final double spanX = _span(horizontal: true);
    final double spanY = _span(horizontal: false);
    final factors = (
      x: _factor(spanX, _lastSpanX),
      y: _factor(spanY, _lastSpanY),
    );
    _lastSpanX = spanX;
    _lastSpanY = spanY;
    return factors;
  }

  static double _factor(double now, double before) {
    if (before < minSpan || now < minSpan) return 1.0;
    final double f = now / before;
    if (!f.isFinite || f <= 0) return 1.0;
    return f.clamp(1 / _maxStep, _maxStep);
  }

  double _span({required bool horizontal}) {
    if (_pointers.length < 2) return 0;
    double lo = double.infinity;
    double hi = double.negativeInfinity;
    for (final Offset p in _pointers.values) {
      final double v = horizontal ? p.dx : p.dy;
      if (!v.isFinite) return 0;
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    return hi - lo;
  }
}
