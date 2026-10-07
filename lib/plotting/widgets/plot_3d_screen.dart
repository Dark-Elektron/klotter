import 'dart:async';
import 'dart:math';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/plot_view_state.dart';
import '../models/view_fit.dart';
import '../utils/level_extent.dart';
import 'package:flutter/scheduler.dart';
import '../models/complex_view.dart';
import '../models/enums.dart';
import '../../utils/app_colors.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/parametric.dart';
import '../parsers/plot_expression.dart';
import '../painters/plot_3d_painter.dart';
import '../utils/pinch_tracker.dart';
import '../utils/plot_cache.dart';
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

  /// How much of the panel's lower edge the expression rows cover.
  final double bottomInset;

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

  /// Draw the surface's own grid over it.
  final bool showMesh;

  /// Draw the axes — their lines, ticks and numbers.
  final bool showAxes;

  /// Where the controls float over the plot, in the plot's own coordinates,
  /// so no axis number is drawn underneath one.
  final List<Rect> labelKeepOut;
  final SurfaceMode surfaceMode;
  final ZoomAxis zoomAxis; // New
  final AppColors colors;

  /// Built once per panel rather than per paint, and carries the plot's
  /// colour mode and the theme's series palette.
  final PlotThemeData plotTheme;

  /// Where the plot was left, to open on rather than restore afterwards.
  ///
  /// It used to arrive a frame late, from the panel once this screen had been
  /// laid out. The surface was then drawn at a box of its own choosing and
  /// drawn again at the saved one, and for a level surface each of those is a
  /// march of its own — so every plot swiped to paid for two.
  final PlotViewState? initialView;

  const Plot3DScreen({
    super.key,
    required this.function,
    this.functions = const <PlotExpression>[],
    required this.is3DFunction,
    required this.toolMode,
    required this.plotMode,
    required this.fieldType,
    this.vectorParser,
    this.bottomInset = 0,
    this.vectorFields = const <VectorFieldParser>[],
    this.vectorSeriesBase = 0,
    this.complexView = ComplexView.initial,
    this.uRange = defaultParameterRange,
    this.vRange = defaultParameterRange,
    required this.showContour,
    this.showMesh = false,
    this.showAxes = true,
    this.labelKeepOut = const <Rect>[],
    required this.surfaceMode,
    required this.zoomAxis, // New
    required this.colors,
    required this.plotTheme,
    this.initialView,
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

  /// True while the plot is moving — turned, panned or zoomed under a finger,
  /// or spinning after a flick. The surface samples coarsely for the duration
  /// and sharpens when it settles.
  ///
  /// Set by the movement, not by a finger merely being down: a tap or a long
  /// press moves nothing, and dropping to the coarse grid under a still finger
  /// only showed the trace marker sitting on a blurred surface. Nor by the
  /// start of the gesture, which stops any spin and so clears this — that is
  /// how a drag came to be drawn on the fine grid, every frame, for the whole
  /// of it.
  bool _interacting = false;

  void _setInteracting(bool value) {
    if (_interacting == value) return;
    setState(() => _interacting = value);
  }

  void _trackPointerDown(PointerDownEvent event) {
    _velocityTracker = VelocityTracker.withKind(event.kind);
    _velocityTracker!.addPosition(event.timeStamp, event.position);
    _pinch.down(event.pointer, event.localPosition);
  }

  void _trackPointerMove(PointerMoveEvent event) {
    _velocityTracker?.addPosition(event.timeStamp, event.position);
    _pinch.move(event.pointer, event.localPosition);
  }

  void _trackPointerUp(PointerEvent event) {
    _pinch.up(event.pointer);
    // Still moving if a flick left it spinning.
    if (!isSpinning) _setInteracting(false);
  }

  Offset get _measuredVelocity =>
      _velocityTracker?.getVelocity().pixelsPerSecond ?? Offset.zero;

  void _stopSpin() {
    if (_spinTicker?.isActive ?? false) _spinTicker!.stop();
    _spinAzimuth = 0;
    _setInteracting(false);
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
    _setInteracting(true);
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
    _resizeSettleTimer?.cancel();
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
    // A restored view is a chosen view, so nothing may re-fit over it.
    //
    // Swiping away and back rebuilds the panel, which recompiles the cell and
    // hands over a *new* parser object for the same text. The screen compares
    // parsers by identity, so it read that as a changed sweep and framed the
    // figure again — throwing away the view that had just been restored. It
    // showed up on parametric plots because they are the ones with framing of
    // their own to fall back on.
    _manualZ = true;
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

  /// Set the box by hand.
  ///
  /// The box is centred on the origin, so it is held as half-extents; a
  /// min/max pair is applied as the larger of the two magnitudes. Nothing
  /// auto-fits a divergent surface, which is the case this exists for.
  void setBox({
    required double xMin,
    required double xMax,
    required double yMin,
    required double yMax,
    double? zMin,
    double? zMax,
  }) {
    double halfOf(double lo, double hi) =>
        math.max(lo.abs(), hi.abs()).clamp(_minRange, _maxRange);
    setState(() {
      _typedBox = true;
      xRange = halfOf(xMin, xMax);
      yRange = halfOf(yMin, yMax);
      if (zMin != null && zMax != null) {
        zRange = halfOf(zMin, zMax);
        _manualZ = true;
      }
    });
  }

  /// Once the window has been chosen — set by hand, or restored from a saved
  /// view — stop re-fitting it on every edit.
  bool _manualZ = false;

  /// Whether the box is exactly what was typed into the range fields. A typed
  /// box is held to the letter, through a resize as well; zooming it, or going
  /// home, makes it an ordinary view again.
  bool _typedBox = false;

  /// Whether the box has been zoomed since it was last framed automatically.
  ///
  /// A zoomed view has been chosen as much as a restored one, so a resize keeps
  /// it rather than framing the shape afresh — which threw the zoom away every
  /// time the keypad was folded.
  bool _zoomedSinceFit = false;

  /// Whether any level set is on show.
  bool get _showsLevelSets =>
      _curves.any((PlotExpression e) => e.isLevelSet && !e.hidden);

  /// Whether the box has to keep its proportions through a resize.
  ///
  /// A level set is a shape, and its proportions are what make it read as that
  /// shape: a box left to stretch with the panel turns a sphere into an egg.
  /// The exception is a box typed in by hand, which is held exactly.
  bool get _keepsAspect => !_typedBox && _showsLevelSets;

  /// Note a zoom: the box is now the user's, not the fit's.
  void _zoomed() {
    _zoomedSinceFit = true;
    _typedBox = false;
  }

  /// Re-fit the box height to the current surface and window.
  @visibleForTesting
  void autoScaleForTest() => _autoScaleIfNeeded();

  void resetView() {
    setState(() {
      _stopSpin();
      // Home is how you give up the window you chose, so the fit below is
      // allowed to run again — whether that window was set by hand or came
      // back with a restored view.
      _manualZ = false;
      _typedBox = false;
      _zoomedSinceFit = false;
      rotationX = 0.6;
      rotationZ = 0.8;
      xRange = 5.0;
      yRange = 5.0;
      zRange = 5.0;
      panX = 0.0;
      panY = 0.0;
    });
    // Home puts a parametric plot back around its figure, not back to ±5.
    _autoScaleIfNeeded();
  }

  /// The panel's size as last laid out, or null before the first layout.
  Size? _panelSize;

  /// Whether a change of panel shape should re-fit. Only the equal-aspect path
  /// depends on the shape, so nothing else pays for this.
  bool _refitOnResize = false;

  /// True from a change of panel size until the size has held still for
  /// [_resizeSettle].
  bool _resizing = false;
  Timer? _resizeSettleTimer;

  /// The panel size the box stays fitted to while the panel is still moving,
  /// or null when it is fitted to the panel as it is.
  Size? _fitSize;

  /// The panel's size before the current resize began, for a chosen view to
  /// be rescaled from once it settles.
  Size? _resizeFrom;

  /// How long the panel has to keep one size before the box is fitted to it.
  ///
  /// Folding the keypad away resizes the plot on every frame of the slide —
  /// fifteen sizes in a quarter of a second. Fitting a level surface to each
  /// one re-probed it for its extent and re-marched it at the new range: the
  /// probe alone measured 39 ms a frame on x⁴+y⁴+z⁴−2(x²+y²+z²)+8xyz+1, with a
  /// full march on top. Waiting for the size to stop moving does that once.
  static const Duration _resizeSettle = Duration(milliseconds: 160);

  /// The panel changed size after its first layout.
  void _panelResized(Size before) {
    // Held at the old fit, but only where the box is put back in proportion
    // once the panel settles — which is what keeps a sphere round — so letting
    // it stretch in the meantime would show a sphere swelling into an egg and
    // snapping back. Elsewhere the stretch is the box filling its new room,
    // and it is smoother to watch it happen.
    //
    // Holding the fit also keeps the scale still, and the level mesh is
    // cached against the scale: a box resized every frame rebuilt it every
    // frame, three times the cost of drawing it.
    if (_keepsAspect) {
      _fitSize ??= before;
      _resizeFrom ??= before;
    }
    _resizing = true;
    _resizeSettleTimer?.cancel();
    _resizeSettleTimer = Timer(_resizeSettle, _panelSettled);
  }

  void _panelSettled() {
    if (!mounted) return;
    final Size? from = _resizeFrom;
    _resizeFrom = null;
    // A view that was chosen — restored, or zoomed since it was framed — is
    // not framed afresh. It used to be left alone instead, and a level set in
    // it was stretched with the panel: the sphere restored in a cell came back
    // an egg once the keypad folded. Rescaled, it keeps its size and its
    // proportions, and the box gains or loses room around it.
    final bool chosen = _manualZ || _zoomedSinceFit;
    setState(() {
      _resizing = false;
      _fitSize = null;
      if (chosen && from != null && _keepsAspect) _keepScaleAcross(from);
    });
    if (!chosen && _refitOnResize) _autoScaleIfNeeded();
  }

  /// Rescale the box so every axis keeps its pixels per unit across the panel
  /// changing from [from] to the size it is now.
  ///
  /// The painter draws `planar / range` pixels to a unit of x and y and
  /// `vertical / range` to a unit of z, so scaling each range by how far its
  /// budget moved leaves every unit the size it was.
  void _keepScaleAcross(Size from) {
    final Size? to = _panelSize;
    if (to == null || to.isEmpty || from.isEmpty) return;
    final ViewFit before = Plot3DPainter.viewExtentsFor(from);
    final ViewFit after = Plot3DPainter.viewExtentsFor(to);
    if (before.planar <= 0 || before.vertical <= 0) return;
    final double planar = after.planar / before.planar;
    final double vertical = after.vertical / before.vertical;
    if (!planar.isFinite || !vertical.isFinite) return;
    if (planar <= 0 || vertical <= 0) return;
    xRange = (xRange * planar).clamp(_minRange, _maxRange);
    yRange = (yRange * planar).clamp(_minRange, _maxRange);
    zRange = (zRange * vertical).clamp(_minRange, _maxRange);
  }

  /// How to frame each level set (see [levelSetFraming]), kept with its
  /// compiled expression.
  ///
  /// The probe depends on nothing but the expression, and a cell compiles
  /// afresh on every edit, so an entry can never go stale. Without this a
  /// resize — which re-fits the box to the new panel — repeated the probe to
  /// arrive at the same answer.
  static final Expando<({bool volume, LevelExtent? at})> _extents =
      Expando<({bool volume, LevelExtent? at})>('levelSetExtent');

  LevelExtent? _extentOf(PlotExpression set, {required bool volume}) {
    final ({bool volume, LevelExtent? at})? known = _extents[set];
    if (known != null && known.volume == volume) return known.at;
    final LevelExtent? at = levelSetFraming(set, volume: volume);
    _extents[set] = (volume: volume, at: at);
    return at;
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
    // Hidden rows are excluded: a curve that is not drawn should not be
    // deciding how much of the box the drawn ones get. Home is meant to frame
    // what you can see.
    final List<PlotExpression> curves =
        _curves
            .where((PlotExpression e) => !e.isLevelSet && !e.hidden)
            .toList();
    if (curves.isEmpty) return null;
    try {
      // Measured on the same lattice the surface is drawn from, and taken
      // from the cache the painter fills, so this costs nothing.
      //
      // It used to be its own 7x7 grid, which is coarse enough to step over
      // whatever the surface actually does. For sin(r)/r² over ±24 the samples
      // land at multiples of 8, miss the spike at the origin entirely, and
      // return 0.02 — so the box was built a hundred times too short and the
      // spike came out clipped flat.
      final List<double> magnitudes = <double>[];
      for (final PlotExpression parser in curves) {
        final List<List<double>> grid = cachedHeightGrid(
          parser,
          xRange,
          yRange,
          50,
        );
        for (final List<double> row in grid) {
          for (final double z in row) {
            if (z.isFinite) magnitudes.add(z.abs());
          }
        }
      }
      if (magnitudes.isEmpty) return null;
      magnitudes.sort();

      // The tallest point, so a bounded surface gets its true height: sinc
      // peaks at 1 and the box comes out at 1.2, matching what it should be.
      //
      // A percentile cannot stand in for this. A peak occupies very few of the
      // samples — even the 99.5th of 2,601 sits far down the skirt of a sinc
      // and gave 0.26 for a surface that reaches 1.
      //
      // The percentile's job is only to notice a pole. sin(r)/r² climbs
      // without limit at the origin, and sizing the box to it would press
      // everything else flat onto the floor, so the height is capped at a
      // generous multiple of the bulk of the surface. Nothing can auto-fit a
      // divergent surface properly; set those bounds by hand.
      final double tallest = magnitudes.last;
      final double bulk = magnitudes[((magnitudes.length - 1) * 0.99).floor()];
      final double reference =
          (bulk > 0 && tallest > bulk * 20) ? bulk * 20 : tallest;
      if (reference <= 0) return null;
      return reference * 1.2;
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
    final PlotCamera camera = PlotCamera(
      size: size,
      rotationX: rotationX,
      rotationZ: rotationZ,
      panX: panX,
      panY: panY,
      rangeX: xRange,
      rangeY: yRange,
      rangeZ: zRange,
      bottomInset: widget.bottomInset,
    );

    // A sweep is picked from its own samples rather than by marching a ray:
    // it is not a height, so there is nothing for a ray to cross. Tried first
    // because a cell holding a sweep is showing the sweep — the scalar march
    // below would find nothing there anyway.
    final VectorFieldParser? field = widget.vectorParser;
    final SurfaceHit? hit =
        (field != null && field.isParametric)
            ? pickParametric(
              camera,
              field,
              local,
              uRange: widget.uRange,
              vRange: widget.vRange,
            )
            : pickSurface(
              camera,
              _curves,
              local,
              // A vector field's magnitude surface is a height like any other
              // and joins the same march, as do the components of a complex
              // line — which are only pickable while they are on show.
              field: field,
              surfaceMode: widget.surfaceMode,
              complexView: widget.complexView,
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
    final PlotViewState? saved = widget.initialView;
    if (saved != null && !saved.isInitial) {
      restoreView(
        rotX: saved.rotationX,
        rotZ: saved.rotationZ,
        pX: saved.panX,
        pY: saved.panY,
        rX: saved.rangeX,
        rY: saved.rangeY,
        rZ: saved.rangeZ,
      );
    }
    // Not fitted here: the fit depends on the panel's proportions, and there
    // is no panel yet. It used to fit at a guessed aspect of one and again
    // once the panel was laid out, and since the two boxes differ a level
    // surface was marched twice on every arrival, the first march thrown
    // away. The first layout fits it once (see build).
  }

  @override
  void didUpdateWidget(covariant Plot3DScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.function != widget.function ||
        oldWidget.functions != widget.functions ||
        oldWidget.fieldType != widget.fieldType ||
        // The sweep decides where a parametric figure goes, so changing it
        // changes what there is to frame.
        oldWidget.vectorParser != widget.vectorParser ||
        oldWidget.uRange != widget.uRange ||
        oldWidget.vRange != widget.vRange) {
      _autoScaleIfNeeded();
    }
  }

  /// Frame a parametric plot around the shape it actually traces.
  ///
  /// A sweep has no natural range: u and v decide where the points go, and
  /// nothing about the axes does. Left at the default ±5 a small figure sits
  /// in the middle of an empty box and a large one runs out of it, and either
  /// way the first thing anyone does is pinch to fix it.
  ///
  /// Returns false when there is nothing to frame, so the caller can fall
  /// through to whatever it would have done.
  bool _frameParametric() {
    final VectorFieldParser? field = widget.vectorParser;
    if (field == null || !field.isParametric) return false;

    final Iterable<ParametricPoint?> points =
        field.isParametricSurface
            ? cachedParametricSurface(
              field,
              u: widget.uRange,
              v: widget.vRange,
            ).expand((List<ParametricPoint?> row) => row)
            : cachedParametricCurve(field, u: widget.uRange);

    final ({double x, double y, double z})? extent = parametricExtent(points);
    if (extent == null) return false;

    // A tenth of margin so the figure does not touch the walls, and a floor
    // so a curve that lies flat in one axis — a circle in the plane, say —
    // still gets a box with some depth to it rather than a slot.
    // The sweep is not necessarily the whole cell. A circle of radius 1 beside
    // a sweep half a unit across belongs in the same box, and framing on the
    // sweep alone left the circle outside the walls.
    double reach = 0;
    for (final PlotExpression e in widget.functions) {
      if (!e.isValid || e.hidden) continue;
      // A level set says where it is satisfied, not how big it is, so its own
      // window is the only thing to go on. Height surfaces are handled by the
      // fit below and are not stretched to here.
      if (e.isLevelSet) reach = math.max(reach, 1.0);
    }

    double axis(double own) {
      final double padded = math.max(own, reach) * 1.1;
      return padded.isFinite && padded > 0.5 ? padded : 0.5;
    }

    _apply(() {
      xRange = axis(extent.x);
      yRange = axis(extent.y);
      zRange = axis(extent.z);
    });
    return true;
  }

  /// True while a fit is being made from inside this screen's own build.
  bool _fittingInBuild = false;

  /// Make [change], rebuilding for it unless this is the build already.
  void _apply(VoidCallback change) {
    if (_fittingInBuild) {
      change();
    } else {
      setState(change);
    }
  }

  /// Fit the box to what is drawn in it, unless the view was chosen.
  ///
  /// [inBuild] is for the first layout, which fits in place: the painter is
  /// made from these ranges a few lines later in the same build, so there is
  /// nothing to rebuild for — and asking would be an error there.
  void _autoScaleIfNeeded({bool inBuild = false}) {
    if (_manualZ) return;
    // Nothing to fit to before the first layout, which fits it.
    if (_panelSize == null) return;
    // Framed afresh, so whatever zoom there was is gone.
    _zoomedSinceFit = false;
    _fittingInBuild = inBuild;
    try {
      // A sweep is framed by its own extent; the height-surface fit below
      // has nothing to say about it.
      if (_frameParametric()) return;
      final newZ = _computeAutoZRange();
      // A level set is framed by where its surface is, which the height fit
      // cannot tell it. Run both: a cell may hold a sphere and a height
      // surface at once, and home is meant to show both.
      final bool framed = _frameLevelSets(floorZ: newZ);
      if (framed || newZ == null) return;
      _apply(() {
        zRange = newZ;
      });
    } finally {
      _fittingInBuild = false;
    }
  }

  /// Sizes the box around every level set in the cell.
  ///
  /// A level set is drawn where `F = 0`, and `F` itself says nothing about
  /// where that is — for the unit sphere over ±5, max|F| is 49, so a fit by
  /// value asks for a box fifty times too big. [levelSetExtent] instead looks
  /// for where `F` changes sign. Returns whether it framed anything.
  ///
  /// [floorZ] is what the height surfaces in the same cell asked for; the box
  /// takes whichever is larger so neither kind is clipped.
  bool _frameLevelSets({double? floorZ}) {
    final List<PlotExpression> sets =
        _curves.where((PlotExpression e) => e.isLevelSet && !e.hidden).toList();
    if (sets.isEmpty) return false;

    double x = 0, y = 0, z = 0;
    bool found = false;
    for (final PlotExpression set in sets) {
      final LevelExtent? at = _extentOf(set, volume: widget.is3DFunction);
      if (at == null) continue;
      found = true;
      x = max(x, at.x);
      y = max(y, at.y);
      z = max(z, at.z);
    }
    if (!found) return false;

    // A little room around the shape.
    //
    // An axis the surface does not extend along borrows the shape's overall
    // size rather than collapsing to nothing. A fixed floor was tried here
    // first and was wrong: clamping to 1 meant a small shape like x²+y²=0.1
    // asked for 0.56, got 1, and anything smaller stopped scaling at all.
    const double margin = 1.4;
    final double reach = <double>[x, y, z].reduce(max);
    if (reach <= 0) return false;
    double fit(double extent) => (extent > 0 ? extent : reach) * margin;

    // Equal aspect, so a sphere is round.
    //
    // The box gives the floor and the z axis separate screen budgets — the
    // plan is as wide as the panel allows, the axis as tall — so scaleX is
    // planar/xRange while scaleZ is vertical/zRange. Equal ranges therefore
    // still draw z stretched, and a sphere came out an egg.
    //
    // A unit of x and a unit of z cover the same pixels when the ranges hold
    // the same proportion as the budgets: zRange = plan * vertical / planar.
    // The plan is then whichever constraint binds, which is the smaller
    // budget: a tall panel has vertical room to spare, so the width decides
    // it, and a landscape one is the other way about.
    final double aspect = _boxAspect();
    _refitOnResize = true;
    final double planX = fit(x), planY = fit(y), needZ = fit(z);
    // z may widen the plan, but only so far. A surface unbounded in z — a
    // cylinder — reports a z reach of the whole probe, and letting that drive
    // the plan would frame a unit cylinder at a radius of forty. It cannot be
    // made to fit, so it is allowed to run off the top instead.
    final double planFromZ = min(needZ, 3 * max(planX, planY)) / aspect;
    final double plan = <double>[planX, planY, planFromZ].reduce(max);

    _apply(() {
      xRange = plan;
      yRange = plan;
      zRange = max(plan * aspect, floorZ ?? 0);
    });
    return true;
  }

  /// Screen pixels per unit of z against per unit of x, for the current panel.
  ///
  /// Above 1 the panel has vertical room to spare and the plan is the binding
  /// constraint; below 1 the height is. One when nothing has been laid out
  /// yet, though nothing fits before then.
  double _boxAspect() {
    final Size? size = _panelSize;
    if (size == null || size.isEmpty) return 1;
    final ViewFit fit = Plot3DPainter.viewExtentsFor(size);
    if (fit.planar <= 0 || fit.vertical <= 0) return 1;
    return fit.vertical / fit.planar;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight <= 0 || constraints.maxWidth <= 0) {
          return const SizedBox.shrink();
        }
        // The box's proportions depend on the panel, which is first known
        // here. Recorded so the fit can ask, and the box fitted now, before
        // the painter below is made from it — and fitted again if the panel
        // changes shape, which is what a rotation to landscape is.
        final Size now = Size(constraints.maxWidth, constraints.maxHeight);
        if (_panelSize != now) {
          final Size? before = _panelSize;
          _panelSize = now;
          if (before == null) {
            _autoScaleIfNeeded(inBuild: true);
          } else {
            _panelResized(before);
          }
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
                // Lifting the finger clears this (see _trackPointerUp), unless
                // a flick has left the plot spinning.
                _interacting = true;
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
                          _zoomed();
                        }
                        if ((vScaleDelta - 1.0).abs() > 0.001) {
                          yRange /= vScaleDelta;
                          yRange = yRange.clamp(_minRange, _maxRange);
                          _zoomed();
                        }
                        // Keep Z in sync with data when possible. A level set
                        // has no height to fit, so z follows the plan in the
                        // proportion that draws a unit of z the size of a unit
                        // of x — a sphere stays round under the pinch, where
                        // z at the plan's own range made it an egg.
                        final autoZ = _computeAutoZRange();
                        final double planZ = (xRange + yRange) / 2;
                        zRange =
                            autoZ ??
                            (_showsLevelSets ? planZ * _boxAspect() : planZ);
                        break;

                      case ZoomAxis.x:
                        // X-axis only zoom
                        final scaleDelta = _uniformDelta(details.scale);
                        if ((scaleDelta - 1.0).abs() > 0.001) {
                          xRange /= scaleDelta;
                          xRange = xRange.clamp(_minRange, _maxRange);
                          final autoZ = _computeAutoZRange();
                          if (autoZ != null) zRange = autoZ;
                          _zoomed();
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
                          _zoomed();
                        }
                        break;

                      case ZoomAxis.z:
                        // Z-axis only zoom
                        final scaleDelta = _uniformDelta(details.scale);
                        if ((scaleDelta - 1.0).abs() > 0.001) {
                          zRange /= scaleDelta;
                          zRange = zRange.clamp(_minRange, _maxRange);
                          _zoomed();
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
                  complexView: widget.complexView,
                  uRange: widget.uRange,
                  vRange: widget.vRange,
                  tracePoint: _tracePoint,
                  // A resize is motion too: the coarser grid keeps the frames
                  // of a sliding keypad cheap, and the fine one returns when
                  // the panel settles.
                  interacting: _interacting || _resizing,
                  fitSize: _fitSize,
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
                  bottomInset: widget.bottomInset,
                  vectorFields: widget.vectorFields,
                  vectorSeriesBase: widget.vectorSeriesBase,
                  showContour: widget.showContour,
                  showMesh: widget.showMesh,
                  showAxes: widget.showAxes,
                  labelKeepOut: widget.labelKeepOut,
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
