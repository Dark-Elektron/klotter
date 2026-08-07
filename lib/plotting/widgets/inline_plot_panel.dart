import 'package:flutter/material.dart';
import '../models/enums.dart';
import '../models/plot_view_state.dart';
import 'package:provider/provider.dart';
import '../../settings/settings_provider.dart';
import '../../utils/app_colors.dart';
import '../utils/plot_theme.dart';
import '../parsers/plot_expression.dart';
import '../parsers/vector_field_parser.dart';
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
  bool _showContour = false;
  SurfaceMode _surfaceMode = SurfaceMode.none;
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
    PlotViewState view = widget.initialView.copyWith(show3D: _show3D);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(_restoreView);
    });
    _parseFunction(widget.expression);
  }

  @override
  void didUpdateWidget(covariant InlinePlotPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expression != widget.expression) {
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
        if (_is3DFunction) {
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
    final compiled = PlotExpression.compileAll(widget.nodes);
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
      _is3DFunction = valid.first.usesY || valid.first.isImplicitSurface;
      if (valid.first.isLevelSet) {
        // Nothing to shade: F only locates the curve or surface, so a heatmap
        // of it would colour the plot by distance from the answer.
        _surfaceMode = SurfaceMode.none;
      } else if (!_is3DFunction) {
        _surfaceMode = SurfaceMode.none;
      } else if (_surfaceMode == SurfaceMode.x ||
          _surfaceMode == SurfaceMode.y ||
          _surfaceMode == SurfaceMode.z) {
        _surfaceMode = SurfaceMode.magnitude;
      }
    });
  }

  Future<void> _editRanges() async {
    final state = _plot2DKey.currentState;
    if (state == null) return;
    final (xMin, xMax, yMin, yMax) = state.ranges;
    final result = await AxisRangeSheet.show(
      context,
      initial: (xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax),
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
  bool _switchingDimension = false;

  void _setShow3D(bool value) {
    if (value == _show3D) return;
    setState(() {
      _show3D = value;
      _switchingDimension = true;
    });
    _publishView();
    Future.delayed(_dimensionFade, () {
      if (mounted) setState(() => _switchingDimension = false);
    });
  }

  Widget _plotLayer({required bool visible, required Widget child}) {
    return Visibility(
      visible: visible || _switchingDimension,
      maintainState: true,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: _dimensionFade,
        curve: Curves.easeInOut,
        child: IgnorePointer(ignoring: !visible, child: child),
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

  void _setSurfaceMode(SurfaceMode mode) {
    setState(() => _surfaceMode = mode);
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
    if (_fieldType == FieldType.vector) {
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
        _plotLayer(
          visible: _show3D,
          child: Plot3DScreen(
                key: _plot3DKey,
                plotTheme: _plotTheme(context),
                function: _currentFunction,
                is3DFunction: _is3DFunction,
                toolMode: _tool3DMode,
                plotMode: _plotMode,
                fieldType: _fieldType,
                vectorParser: _vectorParser,
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
                  showContour: _showContour,
                  surfaceMode: _surfaceMode,
                  colors: _colorsNoListen(context),
                ),
              ),

        if (showOverlays)
          Positioned(
            right: 0,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                  if (_canShowSurface())
                    _buildSurfaceMenuButton(),
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
                  ],
                ],
              ),
            ),
          ),

        if (showOverlays)
          Positioned(
            bottom: _overlayButtonSize + 14,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      const PopupMenuItem(
        value: SurfaceMode.none,
        child: Text('Off'),
      ),
    );

    if (_fieldType == FieldType.vector) {
      menuItems.add(
        const PopupMenuItem(
          value: SurfaceMode.magnitude,
          child: Text('|F|'),
        ),
      );
      menuItems.add(
        const PopupMenuItem(
          value: SurfaceMode.x,
          child: Text('Fx'),
        ),
      );
      menuItems.add(
        const PopupMenuItem(
          value: SurfaceMode.y,
          child: Text('Fy'),
        ),
      );
      if (_vectorParser?.zComponent != null) {
        menuItems.add(
          const PopupMenuItem(
            value: SurfaceMode.z,
            child: Text('Fz'),
          ),
        );
      }
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
