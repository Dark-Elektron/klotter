import 'dart:math';

import 'package:flutter/material.dart';
import '../models/complex_view.dart';
import '../models/enums.dart';
import '../../utils/app_colors.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/parametric.dart';
import '../parsers/plot_expression.dart';
import '../painters/plot_2d_painter.dart';
import '../utils/curve_features.dart';
import '../utils/level_extent.dart';
import '../utils/pinch_tracker.dart';
import '../utils/plot_theme.dart';

class Plot2DScreen extends StatefulWidget {
  final PlotExpression function;

  /// One curve per line of the cell.
  final List<PlotExpression> functions;
  final bool is3DFunction;
  final PlotMode plotMode;
  final FieldType fieldType;
  final VectorFieldParser? vectorParser;

  /// Every vector or parametric line in the cell, in the order written.
  /// Empty falls back to [vectorParser] alone.
  final List<VectorFieldParser> vectorFields;

  /// The series index of the first vector line, so a sweep continues the
  /// cell's colour cycle instead of restarting it.
  final int vectorSeriesBase;

  /// The spans u and v are swept over, when the cell is parametric.
  /// Which readings of a complex function are on show.
  final ComplexView complexView;

  final ParameterRange uRange;
  final ParameterRange vRange;
  final bool showContour;
  final SurfaceMode surfaceMode;
  final AppColors colors;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  const Plot2DScreen({
    super.key,
    required this.function,
    this.functions = const <PlotExpression>[],
    required this.is3DFunction,
    required this.plotMode,
    required this.fieldType,
    this.vectorParser,
    this.vectorFields = const <VectorFieldParser>[],
    this.vectorSeriesBase = 0,
    this.complexView = ComplexView.initial,
    this.uRange = defaultParameterRange,
    this.vRange = defaultParameterRange,
    required this.showContour,
    required this.surfaceMode,
    required this.colors,
    required this.plotTheme,
  });

  @override
  State<Plot2DScreen> createState() => Plot2DScreenState();
}

class Plot2DScreenState extends State<Plot2DScreen> {
  double xMin = -5, xMax = 5;

  /// Apply a restored window without the validation [setRanges] does — the
  /// values have already been checked on the way out of storage.
  void restoreWindow(double x0, double x1, double y0, double y1) {
    if (x1 - x0 < 1e-9 || y1 - y0 < 1e-9) return;
    xMin = x0;
    xMax = x1;
    yMin = y0;
    yMax = y1;
    _features = null;
    _snappedFeature = null;
    _traceX = null;
  }

  double yMin = -5, yMax = 5;

  /// Pinch is decomposed per axis, so a vertical pinch stretches y and a
  /// horizontal one stretches x, measured from where the fingers actually are.
  /// The axis is not guessed from where on the plot they happened to land.
  final PinchTracker _pinch = PinchTracker();

  /// True from the moment a finger lands until it leaves. Implicit curves
  /// sample coarsely while it is set, then sharpen when the gesture ends: a
  /// moving window misses the geometry cache on every frame, so the fine grid
  /// is only affordable once the plot is still.
  bool _interacting = false;

  /// The window has to stay finite, ordered, and wide enough to derive a grid
  /// spacing from. A span reaching zero divides the axis bounds by zero in the
  /// painter, and the resulting NaN throws on every frame after that.
  static const double _minSpan = 1e-9;
  static const double _maxSpan = 1e12;

  static bool _isUsableSpan(double lo, double hi) {
    if (!lo.isFinite || !hi.isFinite) return false;
    final double span = hi - lo;
    return span >= _minSpan && span <= _maxSpan;
  }

  /// x of the trace crosshair in data space, or null when not tracing.
  ///
  /// Long-press starts it rather than tap, so it never competes with the
  /// single-finger pan that already owns dragging on this surface.
  double? _traceX;

  // For detecting axis-specific zoom based on gesture location

  @override
  void initState() {
    super.initState();
    _autoScaleIfNeeded();
  }

  @override
  void didUpdateWidget(covariant Plot2DScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.function != widget.function ||
        oldWidget.functions != widget.functions ||
        oldWidget.fieldType != widget.fieldType ||
        oldWidget.is3DFunction != widget.is3DFunction) {
      // The curve changed, so any cached roots and turning points are stale.
      _features = null;
      _snappedFeature = null;
      _autoScaleIfNeeded();
    }
  }

  /// Exposed for tests; the crosshair is otherwise private state.
  @visibleForTesting
  double? get traceXForTest => _traceX;

  /// Feature snapping. The trace answers "what is f(2.3)?"; snapping lets it
  /// also answer "where does this cross zero?" without hunting for the pixel.
  CurveFeature? _snappedFeature;
  List<CurveFeature>? _features;

  List<PlotExpression> get _curves =>
      widget.functions.isEmpty
          ? <PlotExpression>[widget.function]
          : widget.functions;

  /// Features of the primary curve across the visible window, recomputed only
  /// when the curve or the window changes — not on every drag frame.
  List<CurveFeature> _featuresForWindow() {
    return _features ??= findFeatures(_curves.first, xMin, xMax);
  }

  void _setTrace(double localX, double width) {
    if (width <= 0) return;
    final double raw = xMin + (localX / width) * (xMax - xMin);

    // Snap within a few pixels' worth of x, so it assists without fighting a
    // deliberate placement elsewhere.
    final double tolerance = (xMax - xMin) * (12 / width);
    final CurveFeature? hit = nearestFeature(
      _featuresForWindow(),
      raw,
      tolerance,
    );

    setState(() {
      _snappedFeature = hit;
      _traceX = (hit?.x ?? raw).clamp(xMin, xMax);
    });
  }

  /// Current window, for the axis-range editor.
  (double, double, double, double) get ranges => (xMin, xMax, yMin, yMax);

  /// Set the window numerically.
  ///
  /// Gestures cannot reliably land on an exact window — getting to
  /// x ∈ [0, 2π] by pinching is guesswork — so the ranges are typeable.
  /// Inverted or degenerate input is rejected rather than silently swapped,
  /// because a zero-width axis renders as a blank plot with no explanation.
  bool setRanges({
    required double newXMin,
    required double newXMax,
    required double newYMin,
    required double newYMax,
  }) {
    if (!newXMin.isFinite ||
        !newXMax.isFinite ||
        !newYMin.isFinite ||
        !newYMax.isFinite) {
      return false;
    }
    if (newXMax - newXMin < 1e-9 || newYMax - newYMin < 1e-9) return false;
    setState(() {
      xMin = newXMin;
      xMax = newXMax;
      yMin = newYMin;
      yMax = newYMax;
      _traceX = null;
      _snappedFeature = null;
      _features = null;
    });
    return true;
  }

  void resetView() {
    setState(() {
      xMin = -5;
      xMax = 5;
      yMin = -5;
      yMax = 5;
      _traceX = null;
      _snappedFeature = null;
      _features = null;
    });
    _autoScaleIfNeeded();
  }

  /// How far the implicit curves in this cell reach, or null if there are none.
  ///
  /// An implicit curve is drawn where `F = 0`, and `F` says nothing about where
  /// that is, so it cannot be framed by sampling. [levelSetExtent] looks for
  /// where `F` changes sign instead.
  LevelExtent? _levelSetSpan(List<PlotExpression> curves) {
    double x = 0, y = 0;
    bool found = false;
    for (final PlotExpression curve in curves) {
      if (!curve.isValid || curve.hidden || !curve.isLevelSet) continue;
      // A flat plot, so z plays no part: `volume: false` keeps the search in
      // the plane instead of hunting a surface that is not being drawn.
      final LevelExtent? at = levelSetExtent(curve, volume: false);
      if (at == null) continue;
      found = true;
      x = max(x, at.x);
      y = max(y, at.y);
    }
    return found ? (x: x, y: y, z: 0.0) : null;
  }

  void _autoScaleIfNeeded() {
    if (widget.fieldType != FieldType.scalar) return;
    // A complex function has no curve to frame. Its domain is the plane, and
    // the window should stay centred on the origin — the Argand diagram is
    // the picture, not a graph of something against x.
    //
    // Fitting it anyway read a real-valued sample of it: `evaluate(x, 0, 0)`
    // of (x + yi)² is x², so the window came out as -2.5 to 27.5 and the
    // origin sat near the bottom of the plot.
    if (widget.function.isComplex) return;
    try {
      final curves =
          widget.functions.isEmpty
              ? <PlotExpression>[widget.function]
              : widget.functions;
      double? minY;
      double? maxY;
      const int samples = 80;
      // Fit every curve, not just the first, or added lines land off-screen.
      for (final parser in curves) {
        if (!parser.isValid || parser.hidden) continue;
        // An implicit curve is handled below. Sampling it here fits the window
        // to F's values rather than to the curve: for x²+y²=1, evaluate(x,0,0)
        // is x²-1, which over ±5 asks for y from -1 to 24 and pushes the unit
        // circle into the bottom corner.
        if (parser.isLevelSet) continue;
        // A surface has no curve to frame in the flat view either — it is
        // drawn as a field, and evaluate(x, 0, 0) is one slice through the
        // middle of it. This was a check on the whole cell, which is why an
        // implicit curve never reached the fit at all: it is flagged 3D
        // merely for mentioning y. Per curve, so a plain f(x) sharing the
        // cell with one is still framed.
        if (parser.usesY) continue;
        for (int i = 0; i <= samples; i++) {
          final t = i / samples;
          final x = xMin + (xMax - xMin) * t;
          final y = parser.evaluate(x, 0, 0);
          if (y.isNaN || y.isInfinite) continue;
          minY = minY == null ? y : (y < minY ? y : minY);
          maxY = maxY == null ? y : (y > maxY ? y : maxY);
        }
      }
      final LevelExtent? level = _levelSetSpan(curves);
      if (level == null) {
        if (minY == null || maxY == null) return;
        if ((maxY - minY).abs() < 1e-6) {
          maxY = maxY + 1;
          minY = minY - 1;
        }
        final padding = (maxY - minY) * 0.1;
        setState(() {
          yMin = minY! - padding;
          yMax = maxY! + padding;
        });
        return;
      }

      // A little room around the shape.
      //
      // An axis the curve does not extend along at all — a single point, or a
      // curve flat in y — would collapse the window to nothing, so it borrows
      // the shape's overall size instead. A fixed floor was tried here first
      // and was wrong: clamping to 1 meant x²+y²=0.1 asked for 0.56 and got
      // 1, and anything smaller stopped scaling altogether.
      const double margin = 1.4;
      final double reach = max(level.x, level.y);
      if (reach <= 0) return;
      double fit(double extent) => (extent > 0 ? extent : reach) * margin;
      final double halfX = fit(level.x);
      final double halfY = fit(level.y);

      // The union of both kinds, so a cell holding a circle and a parabola
      // shows both. A plain curve has no natural x extent, so it keeps the
      // default width unless the implicit curve needs more.
      final double? fitLow = minY;
      final double? fitHigh = maxY;
      final bool onlyLevelSets = fitLow == null || fitHigh == null;
      final double left = onlyLevelSets ? -halfX : min(xMin, -halfX);
      final double right = onlyLevelSets ? halfX : max(xMax, halfX);
      final double low = onlyLevelSets ? -halfY : min(fitLow, -halfY);
      final double high = onlyLevelSets ? halfY : max(fitHigh, halfY);
      final double padding = (high - low) * 0.1;

      setState(() {
        xMin = left;
        xMax = right;
        yMin = low - padding;
        yMax = high + padding;
      });
    } catch (_) {
      // Keep defaults on parse/eval failure
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }

        return Listener(
          // The scale callbacks report ratios against the separation at the
          // start of the gesture, which is useless when that separation is a
          // couple of pixels. Raw positions give the separation itself.
          onPointerDown: (e) {
            _pinch.down(e.pointer, e.localPosition);
            if (!_interacting) setState(() => _interacting = true);
          },
          onPointerMove: (e) => _pinch.move(e.pointer, e.localPosition),
          onPointerUp: (e) {
            _pinch.up(e.pointer);
            if (_interacting) setState(() => _interacting = false);
          },
          onPointerCancel: (e) {
            _pinch.up(e.pointer);
            if (_interacting) setState(() => _interacting = false);
          },
          child: GestureDetector(
            onScaleUpdate: (details) {
              setState(() {
                if (details.pointerCount > 1) {
                  _features = null;

                  final focalX =
                      xMin +
                      (details.localFocalPoint.dx / constraints.maxWidth) *
                          (xMax - xMin);
                  final focalY =
                      yMax -
                      (details.localFocalPoint.dy / constraints.maxHeight) *
                          (yMax - yMin);

                  // A zoom that would leave the window unpaintable is dropped
                  // rather than applied and repaired, so the gesture simply stops
                  // having an effect at the limit.
                  void zoomX(double factor) {
                    final double lo = focalX - (focalX - xMin) / factor;
                    final double hi = focalX + (xMax - focalX) / factor;
                    if (!_isUsableSpan(lo, hi)) return;
                    xMin = lo;
                    xMax = hi;
                  }

                  void zoomY(double factor) {
                    final double lo = focalY - (focalY - yMin) / factor;
                    final double hi = focalY + (yMax - focalY) / factor;
                    if (!_isUsableSpan(lo, hi)) return;
                    yMin = lo;
                    yMax = hi;
                  }

                  // The gesture's shape is the control. Pinching top and bottom
                  // toward the centre scales y; left and right scales x; a
                  // diagonal pinch scales both, which is what it looks like it
                  // should do. An axis the fingers are level along reads back as
                  // exactly 1.0, so it cannot creep.
                  //
                  // There is deliberately no axis lock here. The 3D view has one,
                  // and sharing that setting meant locking 3D to the y axis
                  // silently locked the 2D plot too.
                  final pinch = _pinch.read();
                  if (pinch.x != 1.0) zoomX(pinch.x);
                  if (pinch.y != 1.0) zoomY(pinch.y);
                } else if (details.pointerCount == 1) {
                  // Pan — the visible window moved, so features must be refound.
                  _features = null;
                  final xShift =
                      -details.focalPointDelta.dx *
                      (xMax - xMin) /
                      constraints.maxWidth;
                  final yShift =
                      details.focalPointDelta.dy *
                      (yMax - yMin) /
                      constraints.maxHeight;
                  xMin += xShift;
                  xMax += xShift;
                  yMin += yShift;
                  yMax += yShift;
                }
              });
            },
            onLongPressStart:
                (details) =>
                    _setTrace(details.localPosition.dx, constraints.maxWidth),
            onLongPressMoveUpdate:
                (details) =>
                    _setTrace(details.localPosition.dx, constraints.maxWidth),
            onTap: () {
              if (_traceX != null) {
                setState(() {
                  _traceX = null;
                  _snappedFeature = null;
                });
              }
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: widget.plotTheme.background2D,
              ),
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: Plot2DPainter(
                  complexView: widget.complexView,
                  uRange: widget.uRange,
                  vRange: widget.vRange,
                  functions: widget.functions,
                  traceX: _traceX,
                  traceFeature: _snappedFeature,
                  plotTheme: widget.plotTheme,
                  function: widget.function,
                  xMin: xMin,
                  xMax: xMax,
                  yMin: yMin,
                  yMax: yMax,
                  plotMode: widget.plotMode,
                  fieldType: widget.fieldType,
                  vectorParser: widget.vectorParser,
                  vectorFields: widget.vectorFields,
                  vectorSeriesBase: widget.vectorSeriesBase,
                  showContour: widget.showContour,
                  surfaceMode: widget.surfaceMode,
                  colors: widget.colors,
                  interacting: _interacting,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
