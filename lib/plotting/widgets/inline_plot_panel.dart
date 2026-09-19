import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../models/complex_view.dart';
import '../models/enums.dart';
import '../models/plot_view_state.dart';
import 'package:provider/provider.dart';
import '../../settings/settings_provider.dart';
import '../../utils/app_colors.dart';
import '../../utils/render_box.dart';
import '../../utils/coordinate_system.dart';
import '../utils/plot_theme.dart';
import '../parsers/plot_expression.dart';
import '../parsers/vector_field_parser.dart';
import '../utils/parametric.dart';
import 'parameter_range_panel.dart';
import 'plane_slice_gutter.dart';
import '../models/plane_slice.dart';
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

  /// How much of the panel's bottom edge is covered by something else.
  ///
  /// The expression rows float over the plot now, so the plot's own controls —
  /// the reset/fit/pan row and the 2D/3D column — would sit underneath them.
  /// The canvas still fills the whole page, which is the point of the overlay;
  /// only the controls are lifted clear.
  final double bottomInset;

  /// Which rows are switched off, by row number.
  ///
  /// Carried beside the nodes rather than inside them: a hidden row is still
  /// compiled and still holds its place in the colour order, so it cannot be
  /// left out of the node list without recolouring everything after it.
  final List<bool> hiddenRows;

  /// Which rows could not be plotted, by row number, with the reason.
  ///
  /// The panel already names the first problem in a banner over the plot. With
  /// several rows stacked, that says what is wrong without saying which line
  /// it is about, so the rows themselves are marked too.
  final void Function(Map<int, String> byRow)? onRowErrors;

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
    this.hiddenRows = const <bool>[],
    this.onRowErrors,
    this.bottomInset = 0,
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

  /// Which plane the 2D view cuts, or null while the reader has not said.
  ///
  /// Null is meaningful, as it is for the colouring: the two plot types have
  /// always cut different planes by default, so there is no single answer to
  /// store for a plot nobody has touched.
  PlaneSlice? _slice;

  /// Whether the slice strip is taking width off the plot this frame.
  ///
  /// Worked out once at the top of build and read by both the padding and the
  /// strip itself, so the two cannot disagree about whether the space is
  /// reserved — which would either overlap the curve or leave a blank band.
  bool _sliceStripShowing = false;

  /// True while the slice slider is under a finger.
  bool _slidingSlice = false;

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

  /// Every vector or parametric line in the cell. [_vectorParser] is the
  /// first; the controls that describe "the field" still mean that one.
  List<VectorFieldParser> _vectorFields = const <VectorFieldParser>[];

  /// Whether the row at [row] has its eye closed.
  bool _rowHidden(int row) =>
      row < widget.hiddenRows.length && widget.hiddenRows[row];

  /// What u and v are swept over. Per panel rather than per app: two plots
  /// open at once are usually two different curves.
  ///
  /// Seeded from the saved view in [initState], so swiping to the next plot
  /// and back does not hand the sweep back to the default.
  late ParameterRange _uRange;
  late ParameterRange _vRange;
  bool _showContour = false;

  /// Whether surfaces are drawn with their own grid over them.
  bool _showMesh = false;
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
      showMesh: _showMesh,
      uMin: _uRange.min,
      uMax: _uRange.max,
      vMin: _vRange.min,
      vMax: _vRange.max,
      surfaceMode: _surfaceModeChosen ? _surfaceMode.index : null,
      complexView: _complexViewChosen ? _complexView.bits : null,
      sliceAxis: _slice?.axis.index,
      sliceOffset: _slice?.offset,
      clearSlice: _slice == null,
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
    _showMesh = widget.initialView.showMesh;
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
    final int? savedSlice = widget.initialView.sliceAxis;
    if (savedSlice != null && savedSlice < SliceAxis.values.length) {
      _slice = PlaneSlice(
        axis: SliceAxis.values[savedSlice],
        offset: widget.initialView.sliceOffset,
      );
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
        !listEquals(oldWidget.hiddenRows, widget.hiddenRows) ||
        oldWidget.coordinateSystem != widget.coordinateSystem) {
      _parseFunction(widget.expression);
    }
  }

  /// The last set reported, so an unchanged set is not sent every rebuild.
  Map<int, String> _lastRowErrors = const <int, String>{};

  void _reportRowErrors(Map<int, String> byRow) {
    if (mapEquals(byRow, _lastRowErrors)) return;
    _lastRowErrors = byRow;
    // After the frame: this runs from a parse that is itself inside a build,
    // and the owner rebuilds when it hears.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRowErrors?.call(byRow);
    });
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
        _vectorFields = const <VectorFieldParser>[];
        _fieldType = FieldType.scalar;
        _errorMessage = null;
      });
      _reportRowErrors(const <int, String>{});
      return;
    }

    // Line by line, because every line of a cell is its own plot on shared
    // axes and they need not be the same kind of plot.
    //
    // This used to hand the whole cell to the vector parser at once. A cell
    // holding `x²+y²=1`, `x²−y²=0.1` and `u x̂ + u² ŷ` was then read as one
    // vector field: the two circles were discarded for having no unit vector,
    // and what was left was the sweep with the other lines' terms folded into
    // its components. The cell drew nothing and called itself vector arrows.
    final List<List<MathNode>> lines = PlotExpression.splitLines(widget.nodes);
    // All of them. Two fields on one set of axes get two sets of arrows and a
    // colour ramp each, the same way two surfaces do — sharing the full
    // rainbow would put every magnitude in both and neither could be followed.
    //
    // Walked by row rather than filtered, because a hidden row has to be left
    // out and the row number is the only thing that says which is which. It
    // was filtered before, which threw the numbering away: a field or a sweep
    // could not be hidden at all, since nothing downstream knew which row it
    // came from. Unlike a surface, a field is not a PlotExpression and carries
    // no `hidden` of its own — leaving it out here is what hiding means.
    final List<VectorFieldParser> fields = <VectorFieldParser>[
      for (int row = 0; row < lines.length; row++)
        if (VectorFieldParser.isVectorFieldNodes(lines[row]) &&
            !_rowHidden(row))
          if (VectorFieldParser.fromNodes(lines[row])
              case final VectorFieldParser f)
            f,
    ];
    final VectorFieldParser? vector = fields.isEmpty ? null : fields.first;

    if (vector != null) {
      // The rest of the cell is still made of plots, and they are drawn
      // alongside rather than thrown away. Compiled one line at a time, since
      // each is its own curve.
      // By row here too, so these keep their colour slot and their eye. They
      // were compiled without either, so a curve sharing a cell with a field
      // could not be hidden and took whatever colour its position happened to
      // give it.
      final List<PlotExpression> alongside =
          <PlotExpression>[
            for (int row = 0; row < lines.length; row++)
              if (!VectorFieldParser.isVectorFieldNodes(lines[row]))
                PlotExpression.compile(
                    lines[row],
                    system: widget.coordinateSystem,
                  )
                  ..seriesIndex = row
                  ..hidden = _rowHidden(row),
          ].where((PlotExpression e) => e.isValid).toList();

      setState(() {
        _currentFunction =
            alongside.isEmpty ? PlotExpression.invalid : alongside.first;
        _functions = alongside;
        _vectorParser = vector;
        _vectorFields = fields;
        _fieldType = FieldType.vector;
        // Either half can want the third dimension: a 3D field, or a level
        // set in z sitting on the same axes.
        _is3DFunction =
            vector.is3D ||
            alongside.any((PlotExpression e) => e.usesY || e.isImplicitSurface);
        _errorMessage = vector.error;
        if (vector.isParametric) {
          if (!_surfaceModeChosen) {
            _surfaceMode = _defaultParametricSurfaceMode;
          }
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
    //
    // A line written with unit vectors is never an ordinary expression, so it
    // is left out rather than compiled and failed. Reaching here means no
    // field is being drawn — every one of them is hidden — and putting the
    // hidden line through this parser reported "unknown variable e_x, e_y"
    // for a row whose eye was closed. A hidden row draws nothing and complains
    // about nothing.
    final List<PlotExpression> compiled = <PlotExpression>[
      for (int row = 0; row < lines.length; row++)
        if (!VectorFieldParser.isVectorFieldNodes(lines[row]))
          PlotExpression.compile(lines[row], system: widget.coordinateSystem)
            ..seriesIndex = row
            ..hidden = _rowHidden(row),
    ];

    if (compiled.isEmpty) {
      // Nothing but hidden fields. Bare axes, and no error: closing an eye is
      // not a mistake to report.
      setState(() {
        _functions = const <PlotExpression>[];
        _currentFunction = PlotExpression.invalid;
        _vectorParser = null;
        _vectorFields = const <VectorFieldParser>[];
        _fieldType = FieldType.scalar;
        _errorMessage = null;
      });
      _reportRowErrors(const <int, String>{});
      return;
    }

    // By row, so the rows themselves can say which line the trouble is on.
    final Map<int, String> rowErrors = <int, String>{
      for (final PlotExpression e in compiled)
        if (!e.isValid) e.seriesIndex: e.error ?? 'Cannot plot this line',
    };
    _reportRowErrors(rowErrors);

    final valid = compiled.where((e) => e.isValid).toList();
    if (valid.isEmpty) {
      setState(() {
        _functions = const <PlotExpression>[];
        _currentFunction = PlotExpression.invalid;
        // The fields go too. Hiding the one field in a cell lands exactly
        // here: with the field left out, the only line left compiles as an
        // ordinary expression and fails, and this returned without touching
        // the field list — so the arrows stayed on the plot after the eye had
        // been closed on them.
        _vectorParser = null;
        _vectorFields = const <VectorFieldParser>[];
        _fieldType = FieldType.scalar;
        _errorMessage = compiled.first.error ?? 'Invalid function';
      });
      return;
    }
    final firstError = compiled.firstWhere(
      (e) => !e.isValid,
      orElse: () => PlotExpression.invalid,
    );

    setState(() {
      for (final PlotExpression e in valid) {
        e.hidden =
            e.seriesIndex < widget.hiddenRows.length &&
            widget.hiddenRows[e.seriesIndex];
      }
      _functions = valid;
      _errorMessage = valid.length == compiled.length ? null : firstError.error;
      _currentFunction = valid.first;
      _vectorParser = null;
      // And the list with it. Clearing only the parser left the previous
      // fields standing, so closing the eye on the one field in a cell left
      // its arrows on the plot: the cell became scalar while the painter was
      // still handed the field it had before.
      _vectorFields = const <VectorFieldParser>[];
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

  /// Whether the plot's side chrome is laid out for a left hand.
  ///
  /// The same setting that mirrors the keypad and the expression rows. The
  /// control column and the parameter chips are the parts of the plot with a
  /// leading and a trailing side, so they follow it; the toolbar and the mode
  /// label are centred or full-width and do not.
  bool get _mirrored =>
      Provider.of<SettingsProvider>(context).handedness ==
      Handedness.leftHanded;

  /// How long the overlay controls take to settle when the rows below them
  /// change height.
  ///
  /// They are anchored to the bottom of the plot and the rows float over that
  /// edge, so adding or removing a row moves every one of them. Jumping read
  /// as a glitch; sliding reads as the panel making room.
  static const Duration _insetSlide = Duration(milliseconds: 220);

  /// How a parametric sweep arrives, before the user has said otherwise.
  ///
  /// In 3D, coloured by magnitude: a surface swept in u and v is nearly always
  /// being read for its numbers, and left solid it is a shape with nothing on
  /// it but the lighting.
  ///
  /// In 2D there is no surface to shade. A sweep there is a curve — one
  /// parameter traced across the plane — and shading it filled the plot with a
  /// surface nobody asked for. So it starts off, and the button is there for
  /// anyone who wants it.
  SurfaceMode get _defaultParametricSurfaceMode =>
      _show3D ? SurfaceMode.magnitude : SurfaceMode.none;

  void _setShow3D(bool value) {
    if (value == _show3D) return;
    setState(() {
      _show3D = value;
      // The default differs per dimension, so switching re-reads it. Only
      // while it is still a default: a choice the user has made survives the
      // switch, which is the whole point of tracking that they made one.
      if (!_surfaceModeChosen && (_vectorParser?.isParametric ?? false)) {
        _surfaceMode = _defaultParametricSurfaceMode;
      }
    });
    _publishView();
  }

  /// Switch dimension without hunting for the toolbar button.
  @visibleForTesting
  void setShow3DForTest(bool value) => _setShow3D(value);

  /// Which 3D tool is active.
  @visibleForTesting
  Tool3DMode get toolModeForTest => _tool3DMode;

  /// Whether the colouring menu is on offer — for a field cut to a plane, that
  /// is what turns the cut surface on.
  @visibleForTesting
  bool get canShowSurfaceForTest => _canShowSurface();

  /// Which plane the flat view is cutting.
  @visibleForTesting
  PlaneSlice get sliceForTest => _resolvedSlice;

  @visibleForTesting
  void cycleSliceAxisForTest() => _cycleSliceAxis();

  @visibleForTesting
  ZoomAxis get zoomAxisForTest => _zoomAxis;

  /// What the plot is coloured by, and whether that was asked for.
  @visibleForTesting
  (SurfaceMode, bool) get surfaceModeForTest => (
    _surfaceMode,
    _surfaceModeChosen,
  );

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

  /// Whether this plot has a third dimension to slide along.
  ///
  /// A curve in the plane has no plane to choose, so the strip stays away
  /// rather than offering a control that changes nothing — the same reasoning
  /// as the u and v chips appearing only for the parameters actually used.
  bool get _canSlice =>
      _is3DFunction ||
      (_vectorParser?.is3D ?? false) ||
      _vectorFields.any((VectorFieldParser f) => f.is3D) ||
      _functions.any((PlotExpression f) => f.variables.contains('z'));

  /// The plane on show, falling back to whichever one this plot's own kind has
  /// always used when the reader has not chosen.
  PlaneSlice get _resolvedSlice {
    final PlaneSlice? chosen = _slice;
    if (chosen != null) return chosen;
    // A field has always been sampled with its third argument left at zero, so
    // it opens where an equation does. Only a surface z = f(x, y) is different,
    // because it was drawn by evaluating f(x, 0).
    if (_fieldType == FieldType.vector) return const PlaneSlice();
    return _currentFunction.isLevelSet
        ? const PlaneSlice()
        : const PlaneSlice(axis: SliceAxis.y);
  }

  /// How far the held variable runs either side of zero.
  ///
  /// Taken from the 3D box rather than from the 2D window, because the plane
  /// being sled is the third axis — the one the flat view has no room for.
  double get _sliceExtent {
    final p3 = _plot3DKey.currentState;
    return switch (_resolvedSlice.axis) {
      SliceAxis.x => p3?.xRange ?? widget.initialView.rangeX,
      SliceAxis.y => p3?.yRange ?? widget.initialView.rangeY,
      SliceAxis.z => p3?.zRange ?? widget.initialView.rangeZ,
    };
  }

  /// How much of the leading strip's foot the parameter knobs and the complex
  /// toggles have already taken.
  ///
  /// They are positioned against the panel, not against the plot, so they come
  /// down over the slice strip — which had them sitting on its button and
  /// covering its track. Rather than move them into the pile's hand-computed
  /// offsets, the strip stands off by however much they use, so its button
  /// rides up when they appear and drops back when they go.
  double get _leadingFootHeight {
    double stack = 0;
    // Two readings in the flat view, each a square button, stacked.
    if (_currentFunction.isComplex) stack = 2 * _overlayButtonSize;

    int chips = 0;
    if (_usesParameter('u')) chips++;
    if (_usesParameter('v')) chips++;
    // 26 apart, which is what the chips offset themselves by.
    final double chipStack = chips * 26.0;
    if (chipStack > stack) stack = chipStack;

    // Nothing down there: the button can sit at the foot of the plot, since
    // the navigation toolbar is centred and never reaches this edge.
    if (stack == 0) return 0;
    return _overlayButtonSize + 14 + stack;
  }

  void _cycleSliceAxis() {
    final PlaneSlice now = _resolvedSlice;
    final SliceAxis next =
        SliceAxis.values[(now.axis.index + 1) % SliceAxis.values.length];
    setState(() => _slice = now.withAxis(next));
    _publishView();
  }

  void _setSliceOffset(double value) {
    // Not published here. A slide fires continuously, and the view is written
    // to storage, so the plane is saved when the finger lifts instead.
    setState(() => _slice = _resolvedSlice.withOffset(value));
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

  void _toggleMesh() {
    setState(() => _showMesh = !_showMesh);
    // Saved with the rest of the view, or swiping to the next plot and back
    // handed it silently back to off.
    _publishView();
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
  /// Square, unrounded and butted against its neighbours, exactly like the
  /// pan and zoom controls: these were the only overlay buttons with rounded
  /// corners and gaps between them, which made them read as belonging to
  /// something else.
  Widget _buildComplexToggle(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _overlayButtonSize,
        height: _overlayButtonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? _theme.controlFill : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: on ? _theme.controlActive : _theme.controlOutline,
            width: on ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: on ? _theme.controlActive : _theme.controlIdle,
            fontSize: 12,
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
      final bool spatial =
          (_vectorParser?.is3D ?? false) ||
          _vectorFields.any((VectorFieldParser f) => f.is3D);
      // A field filling space has no one surface to colour while it is drawn
      // in space, which is why this used to turn it away. Cut to a plane it
      // has one: the plane itself, coloured by what runs through it. That is
      // the cut surface, and without it slicing a field showed arrows and
      // nothing else.
      if (spatial) return !_show3D;
      return _vectorParser != null;
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
        // The collapsed button, which names the control rather than the
        // current value when nothing is chosen.
        return 'f(x, y)';
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
  /// The theme for the frame being built.
  ///
  /// [_plotTheme] builds a whole `PlotThemeData` — palettes, gradients, a
  /// couple of dozen derived colours — and it was being called twenty-eight
  /// times per build, once for every control that wanted a colour off it. That
  /// is twenty-eight identical objects per frame, and the plot repaints on
  /// every drag frame.
  PlotThemeData? _frameTheme;

  PlotThemeData get _theme => _frameTheme ??= _plotTheme(context);

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
    // Rebuilt once per frame; every control below reads this one.
    _frameTheme = _plotTheme(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool showOverlays = constraints.maxHeight > 140;
        _sliceStripShowing = showOverlays && !_show3D && _canSlice;
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
                      plotTheme: _theme,
                      functions: _functions,
                      function: _currentFunction,
                      is3DFunction: _is3DFunction,
                      toolMode: _tool3DMode,
                      plotMode: _plotMode,
                      fieldType: _fieldType,
                      vectorParser: _vectorParser,
                      bottomInset: widget.bottomInset,
                      vectorFields: _vectorFields,
                      vectorSeriesBase: _functions.length,
                      uRange: _uRange,
                      vRange: _vRange,
                      complexView: _complexView,
                      showMesh: _showMesh,
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
                      bottomInset: widget.bottomInset,
                      plotTheme: _theme,
                      functions: _functions,
                      function: _currentFunction,
                      is3DFunction: _is3DFunction,
                      plotMode: _plotMode,
                      fieldType: _fieldType,
                      vectorParser: _vectorParser,
                      vectorFields: _vectorFields,
                      vectorSeriesBase: _functions.length,
                      uRange: _uRange,
                      vRange: _vRange,
                      complexView: _complexView,
                      showContour: _showContour,
                      surfaceMode: _surfaceMode,
                      slice: _slice,
                      externallyInteracting: _slidingSlice,
                      colors: _colorsNoListen(context),
                    ),
                  ),
                ],
              ),
            ),

            // The slice strip, on the same side as the parameter chips and
            // mirrored with them: the control column sits opposite, so a
            // left-handed layout swaps the two rather than stacking them.
            if (_sliceStripShowing)
              Positioned(
                top: 0,
                bottom: 0,
                left: _mirrored ? null : 0,
                right: _mirrored ? 0 : null,
                child: PlaneSliceGutter(
                  slice: _resolvedSlice,
                  extent: _sliceExtent,
                  theme: _theme,
                  chosen: _slice != null,
                  buttonSize: _overlayButtonSize,
                  bottomInset: widget.bottomInset,
                  footInset: _leadingFootHeight,
                  onChanged: _setSliceOffset,
                  onSlideStart: () => setState(() => _slidingSlice = true),
                  onSlideEnd: () {
                    setState(() => _slidingSlice = false);
                    _publishView();
                  },
                  onAxisTapped: _cycleSliceAxis,
                ),
              ),

            if (showOverlays)
              AnimatedPositioned(
                duration: _insetSlide,
                curve: Curves.easeOutCubic,
                left: _mirrored ? 0 : null,
                right: _mirrored ? null : 0,
                bottom: 8 + widget.bottomInset,
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
                    // Only in 3D, and only where there is a surface to lay it
                    // over: a flat plot has no mesh to show.
                    if (_show3D && _canShowSurface())
                      _buildModeButton(
                        icon: Icons.grid_4x4,
                        isSelected: _showMesh,
                        selectedColor: Colors.tealAccent,
                        onTap: _toggleMesh,
                        tooltip: 'Mesh',
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
                      selectedColor: _theme.controlActive,
                      onTap: () => _setShow3D(true),
                    ),
                    _buildModeButton(
                      label: '2D',
                      isSelected: !_show3D,
                      selectedColor: _theme.controlActive,
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
              AnimatedPositioned(
                duration: _insetSlide,
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: 8 + widget.bottomInset,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildModeButton(
                        icon: Icons.home,
                        isSelected: false,
                        selectedColor: _theme.controlActive,
                        onTap: _resetView,
                        tooltip: 'Reset view',
                      ),
                      if (!_show3D)
                        _buildModeButton(
                          icon: Icons.crop_free,
                          isSelected: false,
                          selectedColor: _theme.controlActive,
                          onTap: _editRanges,
                          tooltip: 'Set range',
                        ),
                      if (_show3D) ...[
                        _build3DZoomButton(),
                        _buildModeButton(
                          icon: Icons.pan_tool,
                          isSelected: _tool3DMode == Tool3DMode.pan,
                          selectedColor: _theme.controlActive,
                          onTap: _togglePan,
                          tooltip: 'Pan',
                        ),
                        _buildModeButton(
                          icon: Icons.crop_free,
                          isSelected: false,
                          selectedColor: _theme.controlActive,
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
                left: _mirrored ? null : 8,
                right: _mirrored ? 8 : null,
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
                    style: TextStyle(color: _theme.controlIdle, fontSize: 11),
                  ),
                ),
              ),

            // Bottom left: which readings of a complex function are showing.
            // Two at once is the useful case — the colouring says what f is
            // and the arrows say where it is going — so these are toggles
            // rather than a menu.
            if (showOverlays && _currentFunction.isComplex)
              AnimatedPositioned(
                duration: _insetSlide,
                curve: Curves.easeOutCubic,
                left: _mirrored ? null : 8,
                right: _mirrored ? 8 : null,
                bottom: _overlayButtonSize + 14 + widget.bottomInset,
                // Stacked, like the mode buttons on the right. Three of them
                // side by side reached most of the way across the plot.
                child: Column(
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
                          .map((e) => _buildComplexToggle(e.label, e.on, e.tap))
                          .toList(),
                ),
              ),

            // Bottom left, where the description used to be: one chip per
            // parameter the expression actually uses, u above v. A curve in u
            // has nothing to say about v, so showing both would offer a
            // control that changes nothing.
            if (showOverlays && _usesParameter('u'))
              AnimatedPositioned(
                duration: _insetSlide,
                curve: Curves.easeOutCubic,
                left: _mirrored ? null : 8,
                right: _mirrored ? 8 : null,
                bottom:
                    _overlayButtonSize +
                    14 +
                    (_usesParameter('v') ? 26 : 0) +
                    widget.bottomInset,
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
              AnimatedPositioned(
                duration: _insetSlide,
                curve: Curves.easeOutCubic,
                left: _mirrored ? null : 8,
                right: _mirrored ? 8 : null,
                bottom: _overlayButtonSize + 14 + widget.bottomInset,
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
            color: isSelected ? selectedColor : _theme.controlOutline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child:
              icon != null
                  ? Icon(
                    icon,
                    color: isSelected ? selectedColor : _theme.controlIdle,
                    size: _overlayIconSize,
                  )
                  : Text(
                    label!,
                    style: TextStyle(
                      color: isSelected ? selectedColor : _theme.controlIdle,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
        ),
      ),
    );

    if (tooltip != null) {
      // Manual trigger, so the tooltip stops competing for the gesture.
      //
      // A Tooltip claims long press on touch, and these controls sit in a
      // stack that already has the plot's own long-press-to-trace recogniser
      // in it. A tap held even slightly is then won by the tooltip: the label
      // appears and the button never fires — which is exactly the reported
      // symptom, a control that "only shows a tooltip text".
      //
      // The label is still available to screen readers through the button's
      // semantics; what is given up is the press-and-hold hint, which these
      // controls do not need — they are icons with a visible selected state.
      return Tooltip(
        message: tooltip,
        triggerMode: TooltipTriggerMode.manual,
        child: button,
      );
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
  final GlobalKey _zoomButtonKey = GlobalKey();

  Widget _build3DZoomButton() {
    final colors = _colorsNoListen(context);
    final bool isSelected = _tool3DMode == Tool3DMode.zoom;
    final Color tint = isSelected ? _theme.controlActive : _theme.controlIdle;

    // Tap switches back to zoom, or opens the axis menu when zoom is already
    // the mode. Long press opens it either way.
    //
    // Tap used to only ever switch mode, which left the menu reachable solely
    // by long press: once in zoom mode the button appeared to do nothing at
    // all, and there was no way to find Free/X/Y/Z without guessing at a
    // gesture. Selecting a mode and configuring it are the same control here,
    // so the second tap is the one that configures.
    //
    // This was a PopupMenuButton, so the *only* way back from pan was through
    // a menu — and when that menu did not open there was no way back at all.
    // Leaning the mode switch on a route being pushed made the one control you
    // need to escape pan the one control that could fail. Tapping now does the
    // job on its own, and the axis menu is a separate, optional gesture.
    //
    // It also makes zoom and pan symmetric: both are taps, both toggle.
    Future<void> chooseAxis() async {
      // The button's own box, not the panel's. `context` here is the panel, so
      // the menu was placed at the panel's top-left corner — the top of the
      // screen — rather than beside the control that opened it.
      final RenderBox? box = laidOutBox(_zoomButtonKey.currentContext);
      if (box == null) return;
      final Offset origin = box.localToGlobal(Offset.zero);
      final ZoomAxis? picked = await showMenu<ZoomAxis>(
        context: context,
        color: colors.containerBackground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        position: RelativeRect.fromRect(
          origin & box.size,
          Offset.zero & MediaQuery.of(context).size,
        ),
        items: <PopupMenuEntry<ZoomAxis>>[
          _buildZoomMenuItem(ZoomAxis.free, 'Free', Icons.zoom_out_map),
          _buildZoomMenuItem(ZoomAxis.x, 'X', Icons.swap_horiz),
          _buildZoomMenuItem(ZoomAxis.y, 'Y', Icons.swap_vert),
          _buildZoomMenuItem(ZoomAxis.z, 'Z', Icons.height),
        ],
      );
      if (picked != null) _setZoomAxis(picked);
    }

    return GestureDetector(
      key: _zoomButtonKey,
      onTap: () {
        if (_tool3DMode != Tool3DMode.zoom) {
          setState(() => _tool3DMode = Tool3DMode.zoom);
          return;
        }
        chooseAxis();
      },
      onLongPress: chooseAxis,
      child: Container(
        width: _overlayButtonSize,
        height: _overlayButtonSize,
        decoration: BoxDecoration(
          color:
              isSelected
                  ? _theme.controlFill
                  : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: isSelected ? _theme.controlActive : _theme.controlOutline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
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
                    color: _theme.controlActive,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _getZoomAxisShortLabel(),
                    style: TextStyle(
                      color: colors.containerBackground,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
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
      // arg first, straight after Off: it is the reading a complex plot
      // arrives with and the one the 2D view shows, so it belongs where the
      // eye lands rather than at the bottom of the list.
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.z, child: Text('arg f')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.x, child: Text('Re f')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.y, child: Text('Im f')),
      );
      menuItems.add(
        const PopupMenuItem(value: SurfaceMode.magnitude, child: Text('|f|')),
      );
    } else {
      menuItems.add(
        const PopupMenuItem(
          value: SurfaceMode.magnitude,
          // Named for what the colour is read from, not for what is drawn.
          // A scalar plot is already a surface, so "Surface" said nothing
          // about the choice being made; the height is f(x, y), and that is
          // what the ramp maps.
          child: Text('f(x, y)'),
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
                  ? _theme.controlFill
                  : Colors.black.withValues(alpha: 0.5),
          border: Border.all(
            color: isSelected ? _theme.controlActive : _theme.controlOutline,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.landscape,
            color: isSelected ? _theme.controlActive : _theme.controlIdle,
            size: 20,
          ),
        ),
      ),
    );
  }
}
