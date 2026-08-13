import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../models/enums.dart';
import '../../utils/app_colors.dart';
import '../parsers/vector_field_parser.dart';
import '../parsers/plot_expression.dart';
import '../painters/plot_3d_painter.dart';
import '../utils/pinch_tracker.dart';
import '../utils/surface_pick.dart';
import '../utils/plot_theme.dart';

class Plot3DScreen extends StatefulWidget {
  final PlotExpression function;

  /// One surface per line of the cell, matching how 2D draws one curve per
  /// line. Empty means "just [function]".
  final List<PlotExpression> functions;

  final bool is3DFunction;
  final Tool3DMode toolMode;
  final PlotMode plotMode;
  final FieldType fieldType;
  final VectorFieldParser? vectorParser;
  final bool showContour;
  final SurfaceMode surfaceMode;
  final ZoomAxis zoomAxis; // New
  final AppColors colors;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  const Plot3DScreen({
    super.key,
    required this.function,
    this.functions = const <PlotExpression>[],
    required this.is3DFunction,
    required this.toolMode,
    required this.plotMode,
    required this.fieldType,
    this.vectorParser,
    required this.showContour,
    required this.surfaceMode,
    required this.zoomAxis, // New
    required this.colors,
    required this.plotTheme,
  });

  @override
  State<Plot3DScreen> createState() => Plot3DScreenState();
}

class Plot3DScreenState extends State<Plot3DScreen>
    with SingleTickerProviderStateMixin {
  // ---- momentum ---------------------------------------------------------
  // A flick keeps the plot turning until it is touched again. Rotation is the
  // one gesture where the useful state is the *motion* rather than a final
  // position — you want to watch a surface turn while reading it, not hold a
  // finger down.
  Ticker? _spinTicker;

  /// Radians per second about the vertical axis.
  ///
  /// Azimuth only. Carrying the flick's vertical component too made the tilt
  /// creep at a constant rate until it hit the pole and stopped there — so a
  /// spin almost always ended looking straight down or straight up, whatever
  /// angle it started from. A turntable spins; it does not also tip over.
  double _spinAzimuth = 0;
  Duration _lastTick = Duration.zero;

  /// Fastest sustained spin, in radians per second — a little under a third
  /// of a turn. A hard flick should not leave the surface whipping round
  /// faster than it can be read.
  static const double _maxSpinRate = 1.8;

  /// A flick slower than this was a drag that happened to end while moving,
  /// not a request to keep spinning.
  static const double _spinStartThreshold = 0.35;

  bool get isSpinning => _spinTicker?.isActive ?? false;

  // Rotation speed measured from the drag itself.
  //
  // ScaleGestureRecognizer reports an end velocity, but it is the focal
  // point's and can come back as zero depending on how the gesture is
  // resolved — which is why a flick appeared to do nothing on a device while
  // every synthetic fling in a test worked. Timing the updates we already
  // handle is exact and under our control.
  /// Flutter's own velocity tracker, fed from raw pointer events.
  ///
  /// Three home-made attempts got this wrong: a wall clock measured real
  /// milliseconds against a test's pumped frames; `currentFrameTimeStamp` is
  /// only valid inside a frame while gestures arrive outside one; and movement
  /// per update cannot tell a slow drag from a flick, so stopping before
  /// lifting still span the plot.
  ///
  /// [VelocityTracker] uses each event's own timestamp — simulated under test,
  /// real on a device — and weights a short recent window, so pausing before
  /// the finger lifts correctly yields no velocity.
  VelocityTracker? _velocityTracker;
  bool _wasRotating = false;

  void _trackPointerDown(PointerDownEvent event) {
    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker!.addPosition(event.timeStamp, event.position);
    _pinch.down(event.pointer, event.localPosition);
  }

  void _trackPointerMove(PointerMoveEvent event) {
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    _pinch.move(event.pointer, event.localPosition);
  }

  void _trackPointerUp(PointerEvent event) => _pinch.up(event.pointer);

  Offset get _measuredVelocity =>
      _velocityTracker?.getVelocity().pixelsPerSecond ?? Offset.zero;

  void _stopSpin() {
    if (_spinTicker?.isActive ?? false) _spinTicker!.stop();
    _spinAzimuth = 0;
  }

  void _startSpin(Offset velocity) {
    // Horizontal movement only: the tilt the user dragged to is the angle they
    // chose to view from, and the spin turns the plot at that angle.
    double az = velocity.dx * 0.01;
    if (az.abs() < _spinStartThreshold) return;

    // Cap the rate, keeping the direction of the flick.
    if (az.abs() > _maxSpinRate) az = az.sign * _maxSpinRate;

    _spinAzimuth = az;
    _lastTick = Duration.zero;
    _spinTicker ??= createTicker(_onSpinTick);
    if (!_spinTicker!.isActive) _spinTicker!.start();
  }

  void _onSpinTick(Duration elapsed) {
    // Clamped: after the app is backgrounded the first tick can arrive with a
    // huge elapsed time, which would otherwise apply seconds of rotation in a
    // single jump.
    final double raw =
        _lastTick == Duration.zero
            ? 1 / 60
            : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (raw <= 0) return;
    final double dt = raw.clamp(0.0, 1 / 30);

    // Elevation is untouched, so the viewing angle at the end of the spin is
    // the one the user set — only the azimuth advances.
    setState(() => rotationZ += _spinAzimuth * dt);

    // No decay: the rotation continues until the plot is touched, so it can be
    // watched while reading the surface rather than re-flicked. Momentum that
    // dies after a second or two just reads as the drag having overshot.
    if (_spinAzimuth == 0) _stopSpin();
  }

  @override
  void dispose() {
    _spinTicker?.dispose();
    super.dispose();
  }
  // -----------------------------------------------------------------------

  double rotationX = 0.6;
  double rotationZ = 0.8;
  double xRange = 5.0;
  double yRange = 5.0;
  double zRange = 5.0; // New: separate Z range
  double panX = 0.0;
  double panY = 0.0;

  /// Apply a restored camera and box.
  void restoreView({
    required double rotX,
    required double rotZ,
    required double pX,
    required double pY,
    required double rX,
    required double rY,
    required double rZ,
  }) {
    rotationX = rotX;
    rotationZ = rotZ;
    panX = pX;
    panY = pY;
    if (rX > 0) xRange = rX;
    if (rY > 0) yRange = rY;
    if (rZ > 0) zRange = rZ;
  }

  /// How far the 3D box may be zoomed.
  ///
  /// The old ceiling of 50 was reached in a couple of pinches and then simply
  /// stopped, which reads as the plot being stuck rather than at a limit. The
  /// sampling grid is a fixed number of steps across whatever range is set, so
  /// a wide box costs no more to draw — it is only coarser.
  static const double _minRange = 0.001;
  static const double _maxRange = 100000.0;

  double _lastScale = 1.0;

  /// Uniform scale since the previous update, for the locked-axis zooms.
  ///
  /// Two fingers converging on the same point drive the reported scale to zero,
  /// and the update after that divides by it — so an axis range becomes
  /// Infinity or NaN, which `clamp` does not repair because NaN compares false
  /// against both limits. A range like that reaches the painter's grid spacing
  /// and throws `Unsupported operation: Infinity or NaN toInt` every frame.
  double _uniformDelta(double scale) {
    final bool usable = scale.isFinite && scale > 0;
    if (!usable || _lastScale <= 0) {
      _lastScale = usable ? scale : 1.0;
      return 1.0;
    }
    final double delta = scale / _lastScale;
    _lastScale = scale;
    if (!delta.isFinite || delta <= 0) return 1.0;
    return delta.clamp(0.25, 4.0);
  }

  /// Free zoom reads each axis from the finger separation along it. See
  /// [PinchTracker] for why the reported horizontal and vertical scales are not
  /// usable for that.
  final PinchTracker _pinch = PinchTracker();

  void resetView() {
    setState(() {
      _stopSpin();
      rotationX = 0.6;
      rotationZ = 0.8;
      xRange = 5.0;
      yRange = 5.0;
      zRange = 5.0;
      panX = 0.0;
      panY = 0.0;
    });
    _autoScaleIfNeeded();
  }

  double? _computeAutoZRange() {
    if (widget.fieldType != FieldType.scalar || !widget.is3DFunction) {
      return null;
    }
    // A level set has no height to fit. F is only a means of locating the
    // surface, so scaling z by max|F| blows the box far past the shape: for
    // x²+y²+z²=1 over x,y in [-5,5], max|F| is 49, which stretched z to ±59
    // and left the unit sphere falling between two z-samples — nothing drawn.
    //
    // Every height surface in the cell has to fit, not just the first: sizing
    // the box to one of them leaves the others clipped at the lid.
    final List<PlotExpression> curves =
        _curves.where((PlotExpression e) => !e.isLevelSet).toList();
    if (curves.isEmpty) return null;
    try {
      double maxAbs = 0;
      const int samples = 6;
      for (final PlotExpression parser in curves) {
        for (int i = 0; i <= samples; i++) {
          final tx = i / samples;
          final x = -xRange + (2 * xRange) * tx;
          for (int j = 0; j <= samples; j++) {
            final ty = j / samples;
            final y = -yRange + (2 * yRange) * ty;
            final z = parser.evaluate(x, y, 0);
            if (!z.isFinite) continue;
            final absZ = z.abs();
            if (absZ > maxAbs) maxAbs = absZ;
          }
        }
      }
      if (maxAbs <= 0) return null;
      return maxAbs * 1.2;
    } catch (_) {
      return null;
    }
  }

  /// The point a long-press picked off the surface, in data coordinates.
  ///
  /// Not persisted in the saved view: the 2D trace clears on restore too, and
  /// a marker reappearing on a plot you have since rotated would be pointing
  /// at nothing in particular.
  SurfaceHit? _tracePoint;

  /// Exposed for tests; the marker is otherwise private state.
  @visibleForTesting
  SurfaceHit? get tracePointForTest => _tracePoint;

  /// Put the marker where the touch meets the surface, or take it away when
  /// the touch is over empty space.
  void _pickTrace(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final SurfaceHit? hit = pickSurface(
      PlotCamera(
        size: size,
        rotationX: rotationX,
        rotationZ: rotationZ,
        panX: panX,
        panY: panY,
        rangeX: xRange,
        rangeY: yRange,
        rangeZ: zRange,
      ),
      _curves,
      local,
    );
    setState(() => _tracePoint = hit);
  }

  void _clearTrace() {
    if (_tracePoint == null) return;
    setState(() => _tracePoint = null);
  }

  /// Every function to draw, or just [Plot3DScreen.function] when the caller
  /// gave no list.
  List<PlotExpression> get _curves =>
      widget.functions.isEmpty
          ? <PlotExpression>[widget.function]
          : widget.functions;

  @override
  void initState() {
    super.initState();
    _autoScaleIfNeeded();
  }

  @override
  void didUpdateWidget(covariant Plot3DScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.function != widget.function ||
        oldWidget.functions != widget.functions ||
        oldWidget.fieldType != widget.fieldType) {
      _autoScaleIfNeeded();
    }
  }

  void _autoScaleIfNeeded() {
    final newZ = _computeAutoZRange();
    if (newZ == null) return;
    setState(() {
      zRange = newZ;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        return Listener(
          // Raw events carry their own timestamps, which the gesture callbacks
          // do not expose.
          onPointerDown: _trackPointerDown,
          onPointerMove: _trackPointerMove,
          onPointerUp: _trackPointerUp,
          onPointerCancel: _trackPointerUp,
          child: GestureDetector(
            onScaleStart: (details) {
              // Any touch stops the spin — including a plain tap, which reaches
              // here and then ends with no velocity, so it stops without
              // restarting.
              _stopSpin();
              _wasRotating = false;
              _lastScale = 1.0;
            },
            onScaleUpdate: (details) {
              setState(() {
                if (details.pointerCount == 2) {
                  if (widget.toolMode == Tool3DMode.pan) {
                    panX += details.focalPointDelta.dx;
                    panY += details.focalPointDelta.dy;
                  } else {
                    // Zoom mode
                    switch (widget.zoomAxis) {
                      case ZoomAxis.free:
                        // Free zoom — each axis follows the finger separation
                        // along it. horizontalScale and verticalScale are
                        // ratios against the separation at the start of the
                        // gesture, which for a near-level pinch is a pixel or
                        // two, or zero; dividing by that produced a NaN range
                        // that clamp() passes straight through, because NaN
                        // compares false against both limits.
                        final pinch = _pinch.read();
                        final hScaleDelta = pinch.x;
                        final vScaleDelta = pinch.y;

                        if ((hScaleDelta - 1.0).abs() > 0.001) {
                          xRange /= hScaleDelta;
                          xRange = xRange.clamp(_minRange, _maxRange);
                        }
                        if ((vScaleDelta - 1.0).abs() > 0.001) {
                          yRange /= vScaleDelta;
                          yRange = yRange.clamp(_minRange, _maxRange);
                        }
                        // Keep Z in sync with data when possible
                        final autoZ = _computeAutoZRange();
                        zRange = autoZ ?? ((xRange + yRange) / 2);
                        break;

                      case ZoomAxis.x:
                        // X-axis only zoom
                        final scaleDelta = _uniformDelta(details.scale);
                        if ((scaleDelta - 1.0).abs() > 0.001) {
                          xRange /= scaleDelta;
                          xRange = xRange.clamp(_minRange, _maxRange);
                          final autoZ = _computeAutoZRange();
                          if (autoZ != null) zRange = autoZ;
                        }
                        break;

                      case ZoomAxis.y:
                        // Y-axis only zoom
                        final scaleDelta = _uniformDelta(details.scale);
                        if ((scaleDelta - 1.0).abs() > 0.001) {
                          yRange /= scaleDelta;
                          yRange = yRange.clamp(_minRange, _maxRange);
                          final autoZ = _computeAutoZRange();
                          if (autoZ != null) zRange = autoZ;
                        }
                        break;

                      case ZoomAxis.z:
                        // Z-axis only zoom
                        final scaleDelta = _uniformDelta(details.scale);
                        if ((scaleDelta - 1.0).abs() > 0.001) {
                          zRange /= scaleDelta;
                          zRange = zRange.clamp(_minRange, _maxRange);
                        }
                        break;
                    }
                  }
                } else if (details.pointerCount == 1) {
                  // One finger follows the selected tool. Previously it always
                  // rotated, so choosing Pan appeared to do nothing unless you
                  // happened to use two fingers.
                  if (widget.toolMode == Tool3DMode.pan) {
                    panX += details.focalPointDelta.dx;
                    panY += details.focalPointDelta.dy;
                  } else {
                    rotationZ += details.focalPointDelta.dx * 0.01;
                    rotationX += details.focalPointDelta.dy * 0.01;
                    rotationX = rotationX.clamp(-pi / 2 + 0.1, pi / 2 - 0.1);
                    _wasRotating = true;
                  }
                }
              });
            },
            // Long-press reads a point off the surface, as it does in 2D.
            // There is no conflict with rotating: a plain drag is a scale
            // gesture, which wins the moment the finger moves.
            onLongPressStart:
                (details) => _pickTrace(
                  details.localPosition,
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
            onLongPressMoveUpdate:
                (details) => _pickTrace(
                  details.localPosition,
                  Size(constraints.maxWidth, constraints.maxHeight),
                ),
            // Stopping the spin used to fall out of onScaleStart, which a tap
            // reached as a degenerate scale gesture. Registering onTap gives
            // the tap recogniser the arena instead, so it has to do both jobs
            // or a tap no longer halts a spinning plot.
            onTap: () {
              _stopSpin();
              _clearTrace();
            },
            onScaleEnd: (details) {
              _lastScale = 1.0;
              // Only a one-finger rotate carries the spin: a pinch ends at a
              // chosen zoom, and panning ends where the plot was placed.
              //
              // The recognizer's own velocity is used only if it is larger than
              // what the drag measured; relying on it alone is what made this
              // fail on a device while passing every test.
              if (_wasRotating && widget.toolMode != Tool3DMode.pan) {
                final Offset reported = details.velocity.pixelsPerSecond;
                final Offset measured = _measuredVelocity;
                _startSpin(
                  reported.distanceSquared > measured.distanceSquared
                      ? reported
                      : measured,
                );
              }
              _wasRotating = false;
            },
            child: Container(
              decoration: BoxDecoration(
                gradient: widget.plotTheme.background3D,
              ),
              child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: Plot3DPainter(
                  tracePoint: _tracePoint,
                  plotTheme: widget.plotTheme,
                  function: widget.function,
                  functions: widget.functions,
                  is3DFunction: widget.is3DFunction,
                  rotationX: rotationX,
                  rotationZ: rotationZ,
                  rangeX: xRange,
                  rangeY: yRange,
                  rangeZ: zRange, // New: pass separate Z range
                  panX: panX,
                  panY: panY,
                  plotMode: widget.plotMode,
                  fieldType: widget.fieldType,
                  vectorParser: widget.vectorParser,
                  showContour: widget.showContour,
                  surfaceMode: widget.surfaceMode,
                  colors: widget.colors,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
