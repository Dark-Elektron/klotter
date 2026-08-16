import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/complex_view.dart';
import '../models/enums.dart';
import '../models/plot_view_state.dart';
import 'package:provider/provider.dart';
import '../../settings/settings_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/coordinate_system.dart';
import '../utils/plot_theme.dart';
import '../parsers/plot_expression.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/parametric.dart';
import 'parameter_range_panel.dart';
import '../../math_renderer/math_nodes.dart';
import 'axis_range_sheet.dart';
import 'plot_2d_screen.dart';
import 'plot_3d_screen.dart';

class InlinePlotPanel extends StatefulWidget {
  /// Serialized form of [nodes]. Used for vector-field detection, which is
  /// still string-based.
  final String expression;

  /// The cell's expression as the calculator's own node tree. Scalar functions
  /// compile from this so the plot evaluates exactly what the calculator does.
  final List<MathNode> nodes;

  /// Where this cell's plot was last left. Restored on first build so a
  /// reopened cell shows the window the user framed, not the origin.
  final PlotViewState initialView;

  /// Which symbols the expression is written in. The plot samples Cartesian
  /// space and converts each point into these before evaluating, so a
  /// spherical cell needs no separate renderer.
  final CoordinateSystem coordinateSystem;

  /// Fired when the view changes in a discrete way — switching 2D/3D, typing a
  /// range, resetting. Not fired per drag frame: the owner reads the live view
  /// when it saves, and a rotation gesture would otherwise notify continuously.
  ///
  /// Needed because a panel swiped away can be disposed before its state is
  /// read, which lost the 2D/3D choice on every swipe.
  final ValueChanged<PlotViewState>? onViewChanged;

  const InlinePlotPanel({
    super.key,
    required this.expression,
    required this.nodes,
    this.initialView = PlotViewState.initial,
    this.coordinateSystem = CoordinateSystem.cartesian,
    this.onViewChanged,
  });

  @override
  State<InlinePlotPanel> createState() => InlinePlotPanelState();
}

class InlinePlotPanelState extends State<InlinePlotPanel> {
  PlotExpression _currentFunction = PlotExpression.invalid;
  List<PlotExpression> _functions = const <PlotExpression>[];
  String? _errorMessage;
  bool _is3DFunction = false;

  /// Whether the user has switched this plot to 3D.
  ///
  /// Re-parsing never clears this. It used to: any expression without a free
  /// `y` reset the plot to 2D, so choosing 3D for a curve like `sin(x)` was
  /// undone by the next keystroke — taking the pan and zoom controls with it.
  /// A 2D function is perfectly meaningful in 3D (it renders as a standing
  /// curve), and in any case the user's explicit choice outranks the guess.
  bool _show3D = false;
  Tool3DMode _tool3DMode = Tool3DMode.zoom;
  PlotMode _plotMode = PlotMode.function;
  FieldType _fieldType = FieldType.scalar;
  VectorFieldParser? _vectorParser;

  /// What u and v are swept over. Per panel rather than per app: two plots
  /// open at once are usually two different curves.
  ///
  /// Seeded from the saved view in [initState], so swiping to the next plot
  /// and back does not hand the sweep back to the default.
  late ParameterRange _uRange;
  late ParameterRange _vRange;
  bool _showContour = false;
  SurfaceMode _surfaceMode = SurfaceMode.none;

  /// Whether the colouring is the user's choice rather than a default.
  ///
  /// Once it is, re-parsing must leave it alone. Editing the expression and
  /// swiping away both rebuild the plot, and a default applied on every
  /// rebuild is not a default — it is an override that quietly undid turning
  /// the colours off.
  bool _surfaceModeChosen = false;

  /// Which complex readings are showing, and whether that was the user's
  /// choice rather than the default.
  ComplexView _complexView = ComplexView.initial;
  bool _complexViewChosen = false;
  ZoomAxis _zoomAxis = ZoomAxis.free;

  final GlobalKey<Plot2DScreenState> _plot2DKey = GlobalKey();
  final GlobalKey<Plot3DScreenState> _plot3DKey = GlobalKey();

  bool _viewRestored = false;

  /// The current view, for persistence.
  ///
  /// Pulled on demand rather than pushed on every drag frame: a rotation
  /// gesture fires continuously, and writing to storage at that rate would
  /// cost far more than the state is worth.
  PlotViewState currentView() {
    final p2 = _plot2DKey.currentState;
    final p3 = _plot3DKey.currentState;
    PlotViewState view = widget.initialView.copyWith(
      show3D: _show3D,
      uMin: _uRange.min,
      uMax: _uRange.max,
      vMin: _vRange.min,
      vMax: _vRange.max,
      surfaceMode: _surfaceModeChosen ? _surfaceMode.index : null,
      complexView: _complexViewChosen ? _complexView.bits : null,
    );
    if (p2 != null) {
      final (xMin, xMax, yMin, yMax) = p2.ranges;
      view = view.copyWith(xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax);
    }
    if (p3 != null) {
      view = view.copyWith(
        rotationX: p3.rotationX,
        rotationZ: p3.rotationZ,
        panX: p3.panX,
        panY: p3.panY,
        rangeX: p3.xRange,
        rangeY: p3.yRange,
        rangeZ: p3.zRange,
      );
    }
    return view;
  }

  /// Tell the owner where the plot is now, so it survives being swiped away.
  void _publishView() {
    final ValueChanged<PlotViewState>? notify = widget.onViewChanged;
    if (notify == null) return;
    // After the frame, so the screens have applied whatever just changed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notify(currentView());
    });
  }

  void _restoreView() {
    if (_viewRestored) return;
    final PlotViewState v = widget.initialView;
    if (v.isInitial) {
      _viewRestored = true;
      return;
    }
    final p2 = _plot2DKey.currentState;
    final p3 = _plot3DKey.currentState;
    // Both screens live in an IndexedStack, so both exist once laid out.
    if (p2 == null && p3 == null) return;
    p2?.restoreWindow(v.xMin, v.xMax, v.yMin, v.yMax);
    p3?.restoreView(
      rotX: v.rotationX,
      rotZ: v.rotationZ,
      pX: v.panX,
      pY: v.panY,
      rX: v.rangeX,
      rY: v.rangeY,
      rZ: v.rangeZ,
    );
    _viewRestored = true;
  }

  @override
  void initState() {
    super.initState();
    _show3D = widget.initialView.show3D;
    final int? savedMode = widget.initialView.surfaceMode;
    if (savedMode != null && savedMode < SurfaceMode.values.length) {
      _surfaceMode = SurfaceMode.values[savedMode];
      _surfaceModeChosen = true;
    }
    final int? savedComplex = widget.initialView.complexView;
    if (savedComplex != null) {
      _complexView = ComplexView.fromBits(savedComplex);
      _complexViewChosen = true;
    }
    _uRange = (min: widget.initialView.uMin, max: widget.initialView.uMax);
    _vRange = (min: widget.initialView.vMin, max: widget.initialView.vMax);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_restoreView);
    });
    _parseFunction(widget.expression);
  }

  @override
  void didUpdateWidget(covariant InlinePlotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A change of system re-reads the same text as different symbols, so it
    // has to recompile even when the expression itself has not moved.
    if (oldWidget.expression != widget.expression ||
        oldWidget.coordinateSystem != widget.coordinateSystem) {
      _parseFunction(widget.expression);
    }
  }

  void _parseFunction(String expr) {
    final trimmed = expr.trim();
    if (trimmed.isEmpty) {
      // An empty cell shows bare axes rather than an error — the plot is
      // always on screen, so "no expression yet" is a normal state, not a
      // fault worth a red banner.
      setState(() {
        _currentFunction = PlotExpression.invalid;
        _functions = const <PlotExpression>[];
        _vectorParser = null;
        _fieldType = FieldType.scalar;
        _errorMessage = null;
      });
      return;
    }

    // Vector fields split from the node tree, not the serialized string, so
    // their components compile through the same engine as everything else.
    final vector = VectorFieldParser.fromNodes(widget.nodes);
    if (vector != null) {
      setState(() {
        _currentFunction = PlotExpression.invalid;
        _functions = const <PlotExpression>[];
        _vectorParser = vector;
        _fieldType = FieldType.vector;
        _is3DFunction = vector.is3D;
        _errorMessage = vector.error;
        if (vector.isParametric) {
          // A sweep arrives coloured, but only on arrival. Its default
          // shading reads the shape and says nothing about the numbers, and
          // the magnitude is what a parametric plot is nearly always being
          // looked at for. Once the user has said otherwise, that stands.
          if (!_surfaceModeChosen) _surfaceMode = SurfaceMode.magnitude;
        } else if (_is3DFunction) {
          _surfaceMode = SurfaceMode.none;
        } else if (_surfaceMode == SurfaceMode.none) {
          _surfaceMode = SurfaceMode.magnitude;
        }
      });
      return;
    }

    // Compile through the calculator's own engine. Anything it cannot sample
    // reports a reason here rather than silently drawing a flat line at zero.
    //
    // Every line of the cell is its own curve on the shared plot, so one bad
    // line does not blank the others — the plot draws what it can and names
    // the first problem.
    final compiled = PlotExpression.compileAll(
      widget.nodes,
      system: widget.coordinateSystem,
    );
    final valid = compiled.where((e) => e.isValid).toList();
    if (valid.isEmpty) {
      setState(() {
        _functions = const <PlotExpression>[];
        _currentFunction = PlotExpression.invalid;
        _errorMessage = compiled.first.error ?? 'Invalid function';
      });
      return;
    }
    final firstError = compiled.firstWhere(
      (e) => !e.isValid,
      orElse: () => PlotExpression.invalid,
    );

    setState(() {
      _functions = valid;
      _errorMessage = valid.length == compiled.length ? null : firstError.error;
      _currentFunction = valid.first;
      _vectorParser = null;
      _fieldType = FieldType.scalar;
      // A level set in z is a surface even though it has no height to sample,
      // so 3D has to be offered for it explicitly rather than inferred from
      // "depends on y".
      //
      // Any line making the cell 3D is enough. Reading only the first meant
      // that adding a surface under a plain f(x) left the whole cell in 1D,
      // and the surface was drawn as a flat standing curve.
      _is3DFunction = valid.any(
        (PlotExpression e) => e.usesY || e.isImplicitSurface,
      );
      if (valid.first.isComplex) {
        // A complex surface arrives coloured by argument, which is what the
        // 2D view of the same function shows without being asked. Left solid,
        // it was a green shape with nothing on it but the lighting — the
        // height alone says almost nothing about a complex function.
        if (!_surfaceModeChosen) _surfaceMode = SurfaceMode.z;
      } else if (valid.first.isLevelSet) {
        // Never F itself: it only locates the curve or surface, so a heatmap
        // of it would colour the plot by distance from the answer. In 3D
        // there is height to shade instead, which is what the coloured
        // setting means for an implicit surface; in 2D there is nothing, so
        // it stays off. Left alone once the user has picked, either way, so
        // choosing a solid colour survives the next keystroke.
        // Keyed on whether the equation reaches into z, not on whether it
        // mentions y: `x² + y² = 1` is a circle drawn on the floor, and
        // shading it by height would be shading a line.
        if (!_surfaceModeChosen) {
          _surfaceMode =
              valid.first.isImplicitSurface
                  ? SurfaceMode.magnitude
                  : SurfaceMode.none;
        }
      } else if (!_is3DFunction) {
        if (!_surfaceModeChosen) _surfaceMode = SurfaceMode.none;
      } else if (_surfaceMode == SurfaceMode.x ||
          _surfaceMode == SurfaceMode.y ||
          _surfaceMode == SurfaceMode.z) {
        _surfaceMode = SurfaceMode.magnitude;
      }
    });
  }

  /// The 3D box, set by hand.
  ///
  /// Auto-fitting cannot help a surface that diverges — sin(r)/r² climbs
  /// without limit at the origin — so the height has to be settable.
  Future<void> _edit3DRanges() async {
    final state = _plot3DKey.currentState;
    if (state == null) return;
    final result = await AxisRangeSheet.show(
      context,
      initial: (
        xMin: -state.xRange,
        xMax: state.xRange,
        yMin: -state.yRange,
        yMax: state.yRange,
        zMin: -state.zRange,
        zMax: state.zRange,
      ),
      colors: _colorsNoListen(context),
    );
    if (result == null) return;
    state.setBox(
      xMin: result.xMin,
      xMax: result.xMax,
      yMin: result.yMin,
      yMax: result.yMax,
      zMin: result.zMin,
      zMax: result.zMax,
    );
    _publishView();
  }

  Future<void> _editRanges() async {
    final state = _plot2DKey.currentState;
    if (state == null) return;
    final (xMin, xMax, yMin, yMax) = state.ranges;
    final result = await AxisRangeSheet.show(
      context,
      initial: (
        xMin: xMin,
        xMax: xMax,
        yMin: yMin,
        yMax: yMax,
        zMin: null,
        zMax: null,
      ),
      colors: _colorsNoListen(context),
    );
    if (result == null) return;
    state.setRanges(
      newXMin: result.xMin,
      newXMax: result.xMax,
      newYMin: result.yMin,
      newYMax: result.yMax,
    );
    _publishView();
  }

  void _resetView() {
    if (_show3D) {
      _plot3DKey.currentState?.resetView();
    } else {
      _plot2DKey.currentState?.resetView();
    }
    _publishView();
  }

  /// Pan is a toggle: tapping it while active returns to rotate/zoom, so the
  /// mode is never a one-way trip.
  void _togglePan() {
    setState(() {
      _tool3DMode =
          _tool3DMode == Tool3DMode.pan ? Tool3DMode.zoom : Tool3DMode.pan;
    });
  }

  /// Switching dimension cross-fades rather than cutting. Both screens stay
  /// mounted so rotation, zoom and pan survive the switch; the hidden one
  /// stops painting once the fade finishes, so an expensive 3D surface is not
  /// redrawn behind a 2D plot.
  static const Duration _dimensionFade = Duration(milliseconds: 260);

  /// Overlay controls sit on top of the data, so they are kept small — big
  /// enough to hit, small enough not to cover the plot they control.
  static const double _overlayButtonSize = 40;
  static const double _overlayIconSize = 18;
  void _setShow3D(bool value) {
    if (value == _show3D) return;
    setState(() => _show3D = value);
    _publishView();
  }

  /// Switch dimension without hunting for the toolbar button.
  @visibleForTesting
  void setShow3DForTest(bool value) => _setShow3D(value);

  /// Wraps the plot layers only, so exports exclude the overlay controls.
  final GlobalKey _captureKey = GlobalKey();

  /// Rasterise the plot exactly as it is on screen.
  ///
  /// [pixelRatio] is a multiple of the logical size: 3 gives a file that still
  /// looks clean pasted into a document, where the on-screen size would look
  /// soft. Returns null when the panel is not laid out, which is the case for
  /// a cell that has never been shown.
  Future<ui.Image?> capturePlot({double pixelRatio = 3.0}) async {
    final BuildContext? ctx = _captureKey.currentContext;
    if (ctx == null) return null;
    final RenderObject? object = ctx.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    if (object.debugNeedsPaint) {
      // Capturing a boundary that has not painted yet yields the previous
      // frame, or nothing at all.
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return object.toImage(pixelRatio: pixelRatio);
  }

  /// The hidden plot stays in the tree, and stays laid out.
  ///
  /// Deliberately not `Visibility`/`Offstage`. An offstage subtree is kept
  /// alive but never laid out, and both plot screens have a `LayoutBuilder` at
  /// their root. A `LayoutBuilder` that is retained but not laid out is the
  /// exact situation `RenderObjectWithLayoutCallbackMixin
  /// .scheduleLayoutCallback` asserts against — "'debugNeedsLayout': is not
  /// true" — which crashed the app to a red screen, usually after minimising
  /// and restoring.
  ///
  /// Nothing is lost by dropping it. The reason the subtree was hidden was to
  /// stop an expensive 3D surface repainting behind a 2D plot, and opacity
  /// already does that: `RenderAnimatedOpacity` skips painting its child
  /// entirely at alpha 0. Only layout still runs, which for a `CustomPaint` is
  /// a size calculation and no sampling at all.
  /// True when [name] is one of the parameters the current cell sweeps.
  ///
  /// Read from the compiled components rather than the typed text, so a `u`
  /// inside a function call counts and one inside a variable name does not.
  bool _usesParameter(String name) {
    final VectorFieldParser? field = _vectorParser;
    if (field == null || !field.isParametric) return false;
    return <PlotExpression?>[
      field.xComponent,
      field.yComponent,
      field.zComponent,
    ].any((PlotExpression? c) => c?.variables.contains(name) ?? false);
  }

  Widget _plotLayer({required bool visible, required Widget child}) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: _dimensionFade,
        curve: Curves.easeInOut,
        child: child,
      ),
    );
  }

  void _setZoomAxis(ZoomAxis axis) {
    setState(() {
      _zoomAxis = axis;
      _tool3DMode = Tool3DMode.zoom;
    });
  }

  void _togglePlotMode() {
    setState(() {
      _plotMode =
          _plotMode == PlotMode.function ? PlotMode.field : PlotMode.function;
    });
  }

  void _toggleContour() {
    setState(() => _showContour = !_showContour);
  }

  void _toggleComplex({
    bool? colouring,
    bool? polya,
    bool? real,
    bool? imaginary,
    bool? modulus,
  }) {
    setState(() {
      _complexView = _complexView.copyWith(
        colouring: colouring,
        polya: polya,
        real: real,
        imaginary: imaginary,
        modulus: modulus,
      );
      _complexViewChosen = true;
    });
    _publishView();
  }

  /// One of the complex-view toggles.
  ///
  /// Deliberately the same shape as the pan and zoom controls beside it: these
  /// change what is drawn, not how you move around it, but they belong to the
  /// plot rather than to the expression and read best as part of the same row.
  Widget _buildComplexToggle(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: _overlayButtonSize,
        constraints: BoxConstraints(minWidth: _overlayButtonSize),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              on
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: on ? Colors.greenAccent : Colors.white24,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? Colors.greenAccent : Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _setSurfaceMode(SurfaceMode mode) {
    setState(() {
      _surfaceMode = mode;
      _surfaceModeChosen = true;
    });
    _publishView();
  }

  String _getModeDescription() {
    List<String> modes = [];

    if (_fieldType == FieldType.vector) {
      if (_surfaceMode != SurfaceMode.none) {
        modes.add(_surfaceModeLabel());
      }
      if (_plotMode == PlotMode.field) {
        modes.add('Magnitude dots');
      } else {
        modes.add('Vector arrows');
      }
      if (_showContour) {
        modes.add('Contour');
      }
    } else {
      if (_surfaceMode != SurfaceMode.none && _is3DFunction) {
        modes.add('Surface');
      }
      if (_plotMode == PlotMode.field) {
        modes.add('Scalar field');
      } else {
        modes.add(_is3DFunction ? 'Function' : 'Line');
      }
      if (_showContour) {
        modes.add('Contour');
      }
    }

    return modes.join(' + ');
  }

  bool _canShowSurface() {
    // A complex line always has something to colour by, in either view.
    if (_currentFunction.isComplex) return true;
    if (_fieldType == FieldType.vector) {
      // A parametric surface qualifies whether or not it has a z component:
      // the menu picks what its colours mean, and a flat patch in the plane
      // still has an x, a y and a magnitude worth colouring by.
      if (_vectorParser?.isParametricSurface ?? false) return true;
      return _vectorParser != null && !_vectorParser!.is3D;
    }
    return _is3DFunction;
  }

  String _surfaceModeLabel() {
    switch (_surfaceMode) {
      case SurfaceMode.magnitude:
        return '|F|';
      case SurfaceMode.x:
        return 'Fx';
      case SurfaceMode.y:
        return 'Fy';
      case SurfaceMode.z:
        return 'Fz';
      case SurfaceMode.none:
        return 'Surface';
    }
  }

  String _getZoomAxisShortLabel() {
    switch (_zoomAxis) {
      case ZoomAxis.free:
        return '';
      case ZoomAxis.x:
        return 'X';
      case ZoomAxis.y:
        return 'Y';
      case ZoomAxis.z:
        return 'Z';
    }
  }

  AppColors _colorsNoListen(BuildContext context) {
    return AppColors.fromType(
      Provider.of<SettingsProvider>(context, listen: false).themeType,
    );
  }

  /// Built once here and passed down, so the painters do not rebuild it on
  /// every paint. Watches settings so changing the plot colour mode or the app
  /// theme repaints the plot.
  PlotThemeData _plotTheme(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);
    return PlotThemeData.fromColors(
      AppColors.fromType(settings.themeType),
      mode: settings.plotColorMode,
      themeType: settings.themeType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool showOverlays = constraints.maxHeight > 140;
        return Stack(
          children: [
            // Only the plot layers are inside the capture boundary. The
            // overlay controls are siblings, so an exported file is the plot
            // and not a screenshot with buttons sitting on it.
            RepaintBoundary(
              key: _captureKey,
              child: Stack(
                children: [
                  _plotLayer(
                    visible: _show3D,
                    child: Plot3DScreen(
                      key: _plot3DKey,
                      plotTheme: _plotTheme(context),
                      functions: _functions,
                      function: _currentFunction,
                      is3DFunction: _is3DFunction,
                      toolMode: _tool3DMode,
                      plotMode: _plotMode,
                      fieldType: _fieldType,
                      vectorParser: _vectorParser,
                      uRange: _uRange,
                      vRange: _vRange,
                      complexView: _complexView,
                      showContour: _showContour,
                      surfaceMode: _surfaceMode,
                      zoomAxis: _zoomAxis,
                      colors: _colorsNoListen(context),
                    ),
                  ),
                  _plotLayer(
                    visible: !_show3D,
                    child: Plot2DScreen(
                      key: _plot2DKey,
                      plotTheme: _plotTheme(context),
                      functions: _functions,
                      function: _currentFunction,
                      is3DFunction: _is3DFunction,
                      plotMode: _plotMode,
                      fieldType: _fieldType,
                      vectorParser: _vectorParser,
                      uRange: _uRange,
                      vRange: _vRange,
                      complexView: _complexView,
                      showContour: _showContour,
                      surfaceMode: _surfaceMode,
                      colors: _colorsNoListen(context),
                    ),
                  ),
                ],
              ),
            ),

            if (showOverlays)
              Positioned(
                right: 0,
                bottom: 8,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_canShowSurface()) _buildSurfaceMenuButton(),
                    if (_fieldType == FieldType.scalar ||
                        (_fieldType == FieldType.vector &&
                            _surfaceMode != SurfaceMode.none))
                      _buildModeButton(
                        icon: Icons.show_chart,
                        isSelected: _showContour,
                        selectedColor: Colors.purpleAccent,
                        onTap: _toggleContour,
                        tooltip: 'Contour',
                      ),
                    _buildModeButton(
                      icon: Icons.grain,
                      isSelected: _plotMode == PlotMode.field,
                      selectedColor: Colors.orangeAccent,
                      onTap: _togglePlotMode,
                      tooltip: 'Field',
                    ),
                    _buildModeButton(
                      label: '3D',
                      isSelected: _show3D,
                      selectedColor: Colors.tealAccent,
                      onTap: () => _setShow3D(true),
                    ),
                    _buildModeButton(
                      label: '2D',
                      isSelected: !_show3D,
                      selectedColor: Colors.tealAccent,
                      onTap: () => _setShow3D(false),
                    ),
                  ],
                ),
              ),

            // Navigation floats over the plot, centred at the bottom: view
            // controls (reset, pan, zoom) are separated from the mode switches on
            // the right, which change *what* is drawn rather than how you move
            // around it.
            if (showOverlays)
              Positioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeButton(
                        icon: Icons.home,
                        isSelected: false,
                        selectedColor: Colors.tealAccent,
                        onTap: _resetView,
                        tooltip: 'Reset view',
                      ),
                      if (!_show3D)
                        _buildModeButton(
                          icon: Icons.crop_free,
                          isSelected: false,
                          selectedColor: Colors.tealAccent,
                          onTap: _editRanges,
                          tooltip: 'Set range',
                        ),
                      if (_show3D) ...[
                        _build3DZoomButton(),
                        _buildModeButton(
                          icon: Icons.pan_tool,
                          isSelected: _tool3DMode == Tool3DMode.pan,
                          selectedColor: Colors.tealAccent,
                          onTap: _togglePan,
                          tooltip: 'Pan',
                        ),
                        _buildModeButton(
                          icon: Icons.crop_free,
                          isSelected: false,
                          selectedColor: Colors.tealAccent,
                          onTap: _edit3DRanges,
                          tooltip: 'Set range',
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Top left, opposite the colorbar and above the parameter panels
            // that own the bottom left corner. Pushed down when an error
            // banner is showing, since that spans the full width of the top.
            if (showOverlays)
              Positioned(
                top: _errorMessage != null ? 32 : 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getModeDescription(),
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ),

            // Bottom left: which readings of a complex function are showing.
            // Two at once is the useful case — the colouring says what f is
            // and the arrows say where it is going — so these are toggles
            // rather than a menu.
            if (showOverlays && _currentFunction.isComplex)
              Positioned(
                left: 8,
                bottom: _overlayButtonSize + 14,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      (_show3D
                              ? <({String label, bool on, VoidCallback tap})>[
                                (
                                  label: 'Re',
                                  on: _complexView.real,
                                  tap:
                                      () => _toggleComplex(
                                        real: !_complexView.real,
                                      ),
                                ),
                                (
                                  label: 'Im',
                                  on: _complexView.imaginary,
                                  tap:
                                      () => _toggleComplex(
                                        imaginary: !_complexView.imaginary,
                                      ),
                                ),
                                (
                                  label: '|f|',
                                  on: _complexView.modulus,
                                  tap:
                                      () => _toggleComplex(
                                        modulus: !_complexView.modulus,
                                      ),
                                ),
                              ]
                              : <({String label, bool on, VoidCallback tap})>[
                                (
                                  label: 'arg',
                                  on: _complexView.colouring,
                                  tap:
                                      () => _toggleComplex(
                                        colouring: !_complexView.colouring,
                                      ),
                                ),
                                (
                                  label: '↗',
                                  on: _complexView.polya,
                                  tap:
                                      () => _toggleComplex(
                                        polya: !_complexView.polya,
                                      ),
                                ),
                              ])
                          .map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _buildComplexToggle(e.label, e.on, e.tap),
                            ),
                          )
                          .toList(),
                ),
              ),

            // Bottom left, where the description used to be: one chip per
            // parameter the expression actually uses, u above v. A curve in u
            // has nothing to say about v, so showing both would offer a
            // control that changes nothing.
            if (showOverlays && _usesParameter('u'))
              Positioned(
                left: 8,
                bottom:
                    _overlayButtonSize + 14 + (_usesParameter('v') ? 26 : 0),
                child: ParameterRangeChip(
                  name: 'u',
                  range: _uRange,
                  onChanged: (r) {
                    setState(() => _uRange = r);
                    _publishView();
                  },
                ),
              ),

            if (showOverlays && _usesParameter('v'))
              Positioned(
                left: 8,
                bottom: _overlayButtonSize + 14,
                child: ParameterRangeChip(
                  name: 'v',
                  range: _vRange,
                  onChanged: (r) {
                    setState(() => _vRange = r);
                    _publishView();
                  },
                ),
              ),

            if (_errorMessage != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: Colors.red.withValues(alpha: 0.8),
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Vector indicator removed per UI request
          ],
        );
      },
    );
  }

  Widget _buildModeButton({
    IconData? icon,
    String? label,
    required bool isSelected,
    required Color selectedColor,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: _overlayButtonSize,
        height: _overlayButtonSize,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? selectedColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: isSelected ? selectedColor : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child:
              icon != null
                  ? Icon(
                    icon,
                    color: isSelected ? selectedColor : Colors.white54,
                    size: _overlayIconSize,
                  )
                  : Text(
                    label!,
                    style: TextStyle(
                      color: isSelected ? selectedColor : Colors.white54,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  PopupMenuItem<ZoomAxis> _buildZoomMenuItem(
    ZoomAxis axis,
    String label,
    IconData icon,
  ) {
    final colors = _colorsNoListen(context);
    final bool isCurrent = _zoomAxis == axis;
    return PopupMenuItem<ZoomAxis>(
      value: axis,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isCurrent ? colors.accent : colors.textSecondary,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: isCurrent ? colors.accent : colors.textPrimary,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Zoom control for 3D, styled like the rest of the overlay column.
  ///
  /// Tapping selects the zoom axis from a menu; the chosen axis shows as a
  /// badge so the current constraint is visible without opening it.
  Widget _build3DZoomButton() {
    final colors = _colorsNoListen(context);
    final bool isSelected = _tool3DMode == Tool3DMode.zoom;
    final Color tint = isSelected ? Colors.tealAccent : Colors.white54;

    return Tooltip(
      message: 'Zoom axis',
      child: PopupMenuButton<ZoomAxis>(
        onSelected: _setZoomAxis,
        color: colors.containerBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: EdgeInsets.zero,
        itemBuilder:
            (BuildContext context) => <PopupMenuEntry<ZoomAxis>>[
              _buildZoomMenuItem(ZoomAxis.free, 'Free', Icons.zoom_out_map),
              _buildZoomMenuItem(ZoomAxis.x, 'X', Icons.swap_horiz),
              _buildZoomMenuItem(ZoomAxis.y, 'Y', Icons.swap_vert),
              _buildZoomMenuItem(ZoomAxis.z, 'Z', Icons.height),
            ],
        child: Container(
          width: _overlayButtonSize,
          height: _overlayButtonSize,
          decoration: BoxDecoration(
            color:
                isSelected
                    ? Colors.tealAccent.withValues(alpha: 0.3)
                    : Colors.black.withValues(alpha: 0.5),
            border: Border.all(
              color: isSelected ? Colors.tealAccent : Colors.white24,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.zoom_out_map, color: tint, size: _overlayIconSize),
              if (_zoomAxis != ZoomAxis.free)
                Positioned(
                  right: 3,
                  bottom: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.tealAccent,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      _getZoomAxisShortLabel(),
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurfaceMenuButton() {
    final bool isSelected = _surfaceMode != SurfaceMode.none;
    final menuItems = <PopupMenuEntry<SurfaceMode>>[];

    menuItems.add(
      const PopupMenuItem(value: SurfaceMode.none, child: Text('Off')),
    );

    if (_fieldType == FieldType.vector) {
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.magnitude, child: Text('|F|')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.x, child: Text('Fx')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.y, child: Text('Fy')),
      );
      if (_vectorParser?.zComponent != null) {
        menuItems.add(
          const PopupMenuItem(value: SurfaceMode.z, child: Text('Fz')),
        );
      }
    } else if (_currentFunction.isComplex) {
      // A complex function has no single height, so "on" is not one thing:
      // the surface can be coloured by any real reading of it, including the
      // argument, which goes on the hue wheel rather than a ramp.
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.x, child: Text('Re f')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.y, child: Text('Im f')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.magnitude, child: Text('|f|')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.z, child: Text('arg f')),
      );
    } else {
      menuItems.add(
        const PopupMenuItem(
          value: SurfaceMode.magnitude,
          child: Text('Surface'),
        ),
      );
    }

    return PopupMenuButton<SurfaceMode>(
      onSelected: _setSurfaceMode,
      itemBuilder: (context) => menuItems,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: isSelected ? Colors.greenAccent : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.landscape,
            color: isSelected ? Colors.greenAccent : Colors.white54,
            size: 20,
          ),
        ),
      ),
    );
  }
}
