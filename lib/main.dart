import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:klotter/utils/constants.dart';
import 'package:klotter/utils/texture_generator.dart';
import 'package:provider/provider.dart';
import 'settings/settings_provider.dart';
import 'math_renderer/renderer.dart';
import 'utils/app_colors.dart';
import 'math_renderer/cell_persistence_service.dart';
import 'math_engine/math_expression_serializer.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'keypad/keypad.dart';
import 'walkthrough/walkthrough_service.dart';
import 'walkthrough/walkthrough_overlay.dart';
import 'utils/app_state.dart';
import 'utils/coordinate_system.dart';
import 'math_renderer/expression_selection.dart';
import 'math_renderer/math_editor_controller.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'math_engine/math_engine_exact.dart';
import 'plotting/models/plot_view_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'plotting/export/plot_exporter.dart';
import 'plotting/widgets/inline_plot_panel.dart';
import 'widgets/textured_container.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Precache SVG backgrounds to avoid flash on load
  await Future.wait([
    _precacheSvg('assets/imgs/background_classic.svg'),
    _precacheSvg('assets/imgs/background_dark.svg'),
    _precacheSvg('assets/imgs/background_pink.svg'),
    _precacheSvg('assets/imgs/background_soft_pink.svg'),
    _precacheSvg('assets/imgs/background_sunset_ember.svg'),
    _precacheSvg('assets/imgs/background_desert_sand.svg'),
    _precacheSvg('assets/imgs/background_digital_amber.svg'),
    _precacheSvg('assets/imgs/background_rose_chic.svg'),
    _precacheSvg('assets/imgs/background_honey_mustard.svg'),
  ]);

  final settingsProvider = await SettingsProvider.create();

  runApp(
    ChangeNotifierProvider.value(value: settingsProvider, child: const MyApp()),
  );
}

/// Precache an SVG asset to avoid loading delay
Future<void> _precacheSvg(String assetPath) async {
  try {
    final loader = SvgAssetLoader(assetPath);
    await svg.cache.putIfAbsent(
      loader.cacheKey(null),
      () => loader.loadBytes(null),
    );
  } catch (e) {
    // Ignore errors - SVG will load normally if precaching fails
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: settings.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blueGrey,
            fontFamily: FONTFAMILY,
            scaffoldBackgroundColor: Colors.white,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.black,
            ),
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.black,
              selectionColor: Colors.red.withValues(alpha: 0.4),
              selectionHandleColor: Colors.red,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primarySwatch: Colors.blueGrey,
            fontFamily: FONTFAMILY,
            scaffoldBackgroundColor: const Color(0xFF121212),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
            ),
            cardColor: const Color(0xFF1E1E1E),
            dividerColor: Colors.grey[700],
            textSelectionTheme: TextSelectionThemeData(
              cursorColor: Colors.white,
              selectionColor: Colors.red.withValues(alpha: 0.4),
              selectionHandleColor: Colors.red,
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

/// Public so widget tests can reach the cell controllers and the undo
/// history, as Plot2DScreenState and InlinePlotPanelState already are.
class HomePageState extends State<HomePage> with WidgetsBindingObserver {
  /// Phones stay portrait: klotter is a plot above an expression above a
  /// keypad, and a phone in landscape fits maybe two of the three, which
  /// breaks the live edit loop the app is built around. Tablets keep both.
  ///
  /// Decided here rather than in `main()` because the view has no size before
  /// the first frame — reading it there returns zero, which reads as a phone
  /// and locked tablets to portrait too.
  bool _orientationApplied = false;

  void _applyOrientationLock(BuildContext context) {
    if (_orientationApplied) return;
    final Size size = MediaQuery.of(context).size;
    // Not laid out yet; try again next build.
    if (size.shortestSide <= 0) return;
    _orientationApplied = true;
    SystemChrome.setPreferredOrientations(
      size.shortestSide < 600
          ? const <DeviceOrientation>[
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]
          : DeviceOrientation.values,
    );
  }

  int count = 0;
  Map<int, GlobalKey<MathEditorInlineState>> mathEditorKeys = {}; // ADD THIS
  Map<int, TextEditingController> textDisplayControllers = {};
  Map<int, MathEditorController> mathEditorControllers = {};
  Map<int, FocusNode> focusNodes = {};
  Map<int, ScrollController> scrollControllers = {};

  Map<int, List<MathNode>?> exactResultNodes = {};
  Map<int, Expr?> exactResultExprs = {};
  Map<int, PageController> resultPageControllers = {};
  Map<int, int> currentResultPage = {};
  Map<int, ValueNotifier<int>> currentResultPageNotifiers = {};

  Map<int, ValueNotifier<int>> exactResultVersionNotifiers = {};

  Map<int, ValueNotifier<double>> resultPageProgressNotifiers = {};
  int activeIndex = 0;
  PageController pgViewController = PageController(
    initialPage: 1,
    viewportFraction: 1,
  );
  bool isVisible = true;
  bool isTypingExponent = false;
  double plotMaxHeight = 300;
  double plotMinHeight = 28;
  final bool _plotsEnabled = true;
  bool _isUpdating = false;
  bool _isLoading = true;
  List<String> answers = [];
  bool _isPlotInteracting = false;
  final Map<int, bool> _plotExpanded = {};

  /// Each cell's plot panel, so its view can be read back when saving.
  final Map<int, GlobalKey<InlinePlotPanelState>> _plotPanelKeys = {};

  /// Views restored from storage, held until the panel for that cell is built.
  final Map<int, PlotViewState> _restoredViews = {};

  /// Drives the plot-page transition. Physics are disabled — the strip below
  /// the expression animates this instead, so paging never competes with the
  /// plot's own pan and pinch.
  /// Created once the restored page is known.
  ///
  /// A post-hoc `jumpToPage` does not work here: the PageView is behind
  /// `_isLoading`, so the callback fires before it attaches, `hasClients` is
  /// false and the jump is silently dropped — which is why the app always
  /// opened on the first cell.
  PageController _pageViewController = PageController();

  SettingsProvider? _settingsProvider;
  bool _listenerAdded = false;
  Timer? _deleteTimer;

  // Walkthrough
  late WalkthroughService _walkthroughService;
  bool _walkthroughInitialized = false;

  // Walkthrough target keys
  final GlobalKey _expressionKey = GlobalKey();
  final GlobalKey _plotAreaKey = GlobalKey();
  final GlobalKey _commandButtonKey = GlobalKey();

  /// The strip between the expression and the keypad, which the walkthrough
  /// points at when it explains moving between plots.
  final GlobalKey _plotStripKey = GlobalKey();

  /// Which coordinate system the variable keys are offering, and so which
  /// symbols an expression is written in. The plot converts its Cartesian
  /// sample points into these before evaluating, which is how ρ = 1 draws a
  /// sphere without the renderers knowing anything about spherical geometry.
  CoordinateSystem _variableSystem = CoordinateSystem.cartesian;

  /// The unit-vector keys switch on their own. Writing r̂ while still using x
  /// and y is ordinary, so tying the two together would be wrong.
  CoordinateSystem _unitVectorSystem = CoordinateSystem.cartesian;
  final GlobalKey _scientificKeypadKey = GlobalKey();
  final GlobalKey _numberKeypadKey = GlobalKey();
  final GlobalKey _extrasKeypadKey = GlobalKey();
  final GlobalKey _mainKeypadAreaKey = GlobalKey();
  final GlobalKey _settingsButtonKey = GlobalKey(); // NEW

  // App-level undo/redo for operations like "Clear All"
  final List<AppState> _appUndoStack = [];
  final List<AppState> _appRedoStack = [];
  static const int _maxAppHistorySize = 10;

  // Update the _walkthroughTargets getter:

  Map<String, GlobalKey> get _walkthroughTargets => {
    'expression_area': _expressionKey,
    'plot_area': _plotAreaKey,
    'command_button': _commandButtonKey,
    'plot_pages': _plotStripKey,
    // Mobile keypad steps
    // The number pad has a box of its own. The scientific and extras pages do
    // not: they are children of the PageView, so the one that is off screen
    // reports an off-screen rect and the highlight lands somewhere random.
    // Both steps point at the swipeable half instead, which is the area that
    // actually holds them.
    'number_keypad': _numberKeypadKey,
    'scientific_keypad': _mainKeypadAreaKey,
    'extras_keypad': _mainKeypadAreaKey,
    'swipe_right_scientific': _mainKeypadAreaKey,
    'swipe_left_number': _mainKeypadAreaKey,
    // The swipe happens on the top rows, so only those are lit.
    'swipe_left_extras': _mainKeypadAreaKey,
    'swipe_right_back': _mainKeypadAreaKey,
    'settings_button': _settingsButtonKey, // NEW
    // Tablet keypad steps
    'tablet_keypads_visible': _mainKeypadAreaKey,
    'tablet_swipe_left_extras': _mainKeypadAreaKey,
    'tablet_extras_visible': _mainKeypadAreaKey,
    'tablet_swipe_right_back': _mainKeypadAreaKey,
    'tablet_settings_button': _settingsButtonKey, // NEW
    // Common
    'main_keypad_area': _mainKeypadAreaKey,

    // 'complete' deliberately has no target: the closing card is about the
    // app as a whole, and spotlighting the keypad implied it was about that.
  };

  Future<void> _initializeWalkthrough() async {
    if (_walkthroughInitialized) return;
    _walkthroughInitialized = true;

    // Delay to ensure everything is ready
    await Future.delayed(const Duration(milliseconds: 300));

    if (mounted) {
      // Determine if tablet mode based on screen size
      final mediaQuery = MediaQuery.of(context);
      final screenWidth = mediaQuery.size.width;
      final isLandscape = mediaQuery.orientation == Orientation.landscape;
      final isTablet = screenWidth > 600 || isLandscape;

      // Set device mode BEFORE initializing
      _walkthroughService.setDeviceMode(isTablet: isTablet);

      await _walkthroughService.initialize();
    }
  }

  @override
  void initState() {
    super.initState();

    // Initialize walkthrough service
    _walkthroughService = WalkthroughService();
    _walkthroughService.addListener(_onWalkthroughChanged);

    WidgetsBinding.instance.addObserver(this);
    _loadCells();

    if (mathEditorControllers.isEmpty) {
      _createControllers(0);
      count = 1;
      activeIndex = 0;
    }

    // Initialize walkthrough after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWalkthrough();
    });
  }

  void _onWalkthroughChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _createControllers(int index) {
    mathEditorControllers[index] = MathEditorController();

    mathEditorControllers[index]!.onResultChanged = () {
      _cascadeUpdates(index);
    };

    mathEditorControllers[index]!.addListener(() {
      _autoScrollToEnd(index);
    });

    textDisplayControllers[index] = TextEditingController();
    focusNodes[index] = FocusNode();
    mathEditorKeys[index] = GlobalKey<MathEditorInlineState>();
    scrollControllers[index] = ScrollController();

    // Initialize page tracking FIRST
    currentResultPage[index] = 0;
    currentResultPageNotifiers[index] = ValueNotifier<int>(0);
    resultPageProgressNotifiers[index] = ValueNotifier<double>(0.0);
    exactResultVersionNotifiers[index] = ValueNotifier<int>(0);
    exactResultNodes[index] = null;
    exactResultExprs[index] = null;
  }

  void _updateExactResult(int index) {
    final controller = mathEditorControllers[index];
    if (controller == null) return;

    try {
      // Collect valid previous exact results for substitution
      Map<int, Expr> ansExprs = {};
      List<int> sortedKeys = mathEditorControllers.keys.toList()..sort();
      for (int key in sortedKeys) {
        if (key < index) {
          Expr? prevExpr = exactResultExprs[key];
          if (prevExpr != null) {
            ansExprs[key] = prevExpr;
          }
        }
      }

      ExactResult result = ExactMathEngine.evaluate(
        controller.expression,
        ansExpressions: ansExprs,
      );

      if (result.isEmpty || result.hasError) {
        exactResultNodes[index] = null;
        exactResultExprs[index] = null;
      } else if (result.mathNodes != null && result.mathNodes!.isNotEmpty) {
        exactResultNodes[index] = result.mathNodes;
        exactResultExprs[index] = result.expr;
      } else {
        exactResultNodes[index] = null;
        exactResultExprs[index] = null;
      }
    } catch (e) {
      exactResultNodes[index] = null;
      exactResultExprs[index] = null;
    }

    // Notify that exact result changed
    final notifier = exactResultVersionNotifiers[index];
    if (notifier != null) {
      notifier.value = notifier.value + 1;
    }
  }

  String _getPlotExpression(int index) {
    final controller = mathEditorControllers[index];
    if (controller == null) return '';
    return MathExpressionSerializer.serialize(controller.expression);
  }

  /// The cell's expression as nodes. The plot compiles from these rather than
  /// from the serialized string, so it evaluates exactly what the calculator
  /// evaluates instead of re-parsing with a weaker grammar.
  List<MathNode> _getPlotNodes(int index) {
    return mathEditorControllers[index]?.expression ?? const <MathNode>[];
  }

  /// klotter always shows the plot. A cell with no free variable is not
  /// unplottable — a constant is a horizontal line, and an empty cell is an
  /// empty set of axes, which is the right thing to look at while you type
  /// the expression that will fill it.
  bool _canShowPlotButton(String expr) => _plotsEnabled;

  /// The cell currently filling the page. Cells are reached by swiping the
  /// strip below the expression, not by scrolling a list.
  int get _currentPageIndex {
    final keys = mathEditorControllers.keys.toList()..sort();
    if (keys.isEmpty) return 0;
    if (keys.contains(activeIndex)) return activeIndex;
    return keys.last;
  }

  List<int> get _pageKeys => mathEditorControllers.keys.toList()..sort();

  /// Whether a cell has anything on it.
  ///
  /// Measured from the serialized expression, not the node list. An empty cell
  /// still holds one placeholder node, so `expression.isNotEmpty` is true even
  /// for a blank cell — which let a flick forward keep stacking up empty
  /// plots. This is the same test backspace uses to decide a cell is empty
  /// enough to delete, so the two agree on what "empty" means.
  bool _pageHasContent(int index) =>
      (mathEditorControllers[index]?.getExpression().trim().isNotEmpty ??
          false);

  /// Move one page left or right.
  ///
  /// Swiping past the last page creates a new one, but only when the current
  /// page actually has something on it — the same rule the action button used
  /// to follow, so you cannot stack up empty plots by flicking.
  void _goToPage({required bool forward}) {
    final keys = _pageKeys;
    final current = keys.indexOf(_currentPageIndex);
    if (current == -1) return;

    if (forward) {
      if (current < keys.length - 1) {
        _animateToPage(current + 1);
      } else if (_canAddPage) {
        _addDisplay();
      }
      return;
    }
    if (current > 0) {
      _animateToPage(current - 1);
    }
  }

  /// A new page is only worth creating when the last one is actually used —
  /// otherwise flicking forward stacks up blank plots.
  bool get _canAddPage {
    final keys = _pageKeys;
    if (keys.isEmpty) return true;
    return _pageHasContent(keys.last);
  }

  /// Remember where a cell's plot was before leaving it.
  ///
  /// A swiped-away panel can be disposed before it is next read, so its view
  /// is captured on the way out — otherwise returning to a cell showed the 2D
  /// view again however it was left.
  void _captureView(int index) {
    final PlotViewState? live =
        _plotPanelKeys[index]?.currentState?.currentView();
    if (live != null) _restoredViews[index] = live;
  }

  void _animateToPage(int position) {
    final keys = _pageKeys;
    if (position < 0 || position >= keys.length) return;
    _captureView(_currentPageIndex);
    setState(() => activeIndex = keys[position]);
    focusNodes[keys[position]]?.requestFocus();
    if (_pageViewController.hasClients) {
      // Same feel as the keypad's page transition.
      _pageViewController.animateToPage(
        position,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Horizontal swipe target between the expression and the keypad.
  ///
  /// The plot itself owns pan and pinch, so page navigation needs its own
  /// surface rather than competing with those gestures.
  Widget _buildPageSwipeStrip(AppColors colors) {
    final keys = _pageKeys;
    final current = keys.indexOf(_currentPageIndex);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 100) return;
        _goToPage(forward: v < 0);
      },
      child: Container(
        height: 26,
        width: double.infinity,
        color: colors.containerBackground,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chevron_left,
              size: 16,
              color:
                  current > 0
                      ? colors.textSecondary
                      : colors.textSecondary.withValues(alpha: 0.2),
            ),
            const SizedBox(width: 10),
            for (int i = 0; i < keys.length; i++) ...[
              Container(
                width: i == current ? 7 : 5,
                height: i == current ? 7 : 5,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      i == current
                          ? colors.accent
                          : colors.textSecondary.withValues(alpha: 0.35),
                ),
              ),
            ],
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              size: 16,
              color:
                  (current < keys.length - 1 || _canAddPage)
                      ? colors.textSecondary
                      : colors.textSecondary.withValues(alpha: 0.2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlotArea(
    int index,
    AppColors colors, {
    bool shouldAddKeys = false,
  }) {
    final plotExpression = _getPlotExpression(index);
    final canPlot = _canShowPlotButton(plotExpression);

    if (!canPlot) {
      return const SizedBox.shrink();
    }

    // No fixed height: the plot fills whatever the page gives it. The caller
    // puts this in an Expanded so the graph takes all the room above the
    // expression rather than a third of the screen.
    return Container(
      key: shouldAddKeys ? _plotAreaKey : null,
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.transparent,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          if (!_isPlotInteracting) {
            setState(() => _isPlotInteracting = true);
          }
        },
        onPointerUp: (_) {
          if (_isPlotInteracting) {
            setState(() => _isPlotInteracting = false);
          }
        },
        onPointerCancel: (_) {
          if (_isPlotInteracting) {
            setState(() => _isPlotInteracting = false);
          }
        },
        child: InlinePlotPanel(
          key: _plotPanelKeys.putIfAbsent(
            index,
            () => GlobalKey<InlinePlotPanelState>(),
          ),
          expression: plotExpression,
          nodes: _getPlotNodes(index),
          initialView: _restoredViews[index] ?? PlotViewState.initial,
          coordinateSystem: _variableSystem,
          onViewChanged: (view) => _restoredViews[index] = view,
        ),
      ),
    );
  }

  Widget _buildExpressionDisplay(int index, AppColors colors) {
    final mathEditorController = mathEditorControllers[index];
    final mathEditorKey = mathEditorKeys[index];
    final scrollController = scrollControllers[index];
    final bool isFocused = (activeIndex == index);
    final bool shouldAddKeys = index == activeIndex;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: _buildPlotArea(index, colors, shouldAddKeys: shouldAddKeys),
        ),
        TexturedContainer(
          baseColor: colors.containerBackground,
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                spreadRadius: 2,
                blurRadius: 7,
                offset: const Offset(0, 0),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              // Expression input area - transparent background
              Container(
                key: shouldAddKeys ? _expressionKey : null,
                width: double.infinity,
                // No color - let texture show through
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: AnimatedOpacity(
                    curve: Curves.easeIn,
                    duration: const Duration(milliseconds: 500),
                    opacity: isVisible ? 1.0 : 0.0,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Center(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: MathEditorInline(
                              key: mathEditorKey,
                              controller: mathEditorController!,
                              showCursor: isFocused,
                              minWidth: constraints.maxWidth,
                              // Drag-to-tune edits the node tree directly,
                              // so the plot needs a rebuild to resample.
                              onExpressionChanged: () {
                                updateMathEditor();
                                setState(() {});
                              },
                              onFocus: () {
                                if (activeIndex != index) {
                                  setState(() {
                                    activeIndex = index;
                                  });
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  int _estimateNodesHeight(List<MathNode> nodes) {
    int maxDepth = 0;
    for (var node in nodes) {
      int depth = _estimateNodeDepth(node);
      if (depth > maxDepth) maxDepth = depth;
    }
    return maxDepth;
  }

  int _estimateNodeDepth(MathNode node) {
    if (node is FractionNode) {
      int numDepth = _estimateNodesHeight(node.numerator);
      int denDepth = _estimateNodesHeight(node.denominator);
      return 1 + (numDepth > denDepth ? numDepth : denDepth);
    } else if (node is RootNode) {
      return 1 + _estimateNodesHeight(node.radicand);
    } else if (node is TrigNode) {
      return _estimateNodesHeight(
        node.argument,
      ); // Sin(x) doesn't add much height unless arg is complex
    } else if (node is ParenthesisNode) {
      return _estimateNodesHeight(node.content);
    } else if (node is ExponentNode) {
      // Exponents add a bit of height but less than a full fraction level
      return 1 + _estimateNodesHeight(node.power);
    } else if (node is LogNode) {
      int argDepth = _estimateNodesHeight(node.argument);
      int baseDepth = _estimateNodesHeight(node.base);
      return 1 + (argDepth > baseDepth ? argDepth : baseDepth);
    }
    return 0;
  }

  @override
  void dispose() {
    _pageViewController.dispose();
    _deleteTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveCells();

    _walkthroughService.removeListener(_onWalkthroughChanged);
    _walkthroughService.dispose();

    for (MathEditorController controller in mathEditorControllers.values) {
      controller.dispose();
    }

    for (TextEditingController resController in textDisplayControllers.values) {
      resController.dispose();
    }

    for (FocusNode focusNode in focusNodes.values) {
      focusNode.dispose();
    }

    for (ScrollController scrollController in scrollControllers.values) {
      scrollController.dispose();
    }

    for (PageController pageController in resultPageControllers.values) {
      pageController.dispose();
    }

    for (ValueNotifier<double> notifier in resultPageProgressNotifiers.values) {
      notifier.dispose();
    }

    for (ValueNotifier<int> notifier in currentResultPageNotifiers.values) {
      notifier.dispose();
    }

    for (ValueNotifier<int> notifier in exactResultVersionNotifiers.values) {
      // ADD THIS
      notifier.dispose();
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveCells();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_listenerAdded) {
      _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
      _settingsProvider?.addListener(_onSettingsChanged);
      _listenerAdded = true;
    }
  }

  Future<void> _loadCells() async {
    List<CellData> savedCells = await CellPersistence.loadCells();
    int savedIndex = await CellPersistence.loadActiveIndex();

    if (savedCells.isEmpty) {
      _createControllers(0);
      count = 1;
      activeIndex = 0;
    } else {
      for (int i = 0; i < savedCells.length; i++) {
        _createControllers(i);

        List<MathNode> nodes = MathExpressionSerializer.deserializeFromJson(
          savedCells[i].expressionJson,
        );
        mathEditorControllers[i]?.setExpression(nodes);

        final Map<String, dynamic>? savedView = savedCells[i].plotView;
        if (savedView != null) {
          _restoredViews[i] = PlotViewState.fromJson(savedView);
        }
      }

      count = savedCells.length;
      activeIndex = savedIndex.clamp(0, count - 1);
    }

    // Build the controller before the PageView first appears, so it opens on
    // the restored cell rather than jumping there afterwards.
    final int restoredPosition = _pageKeys.indexOf(activeIndex);
    _pageViewController.dispose();
    _pageViewController = PageController(
      initialPage: restoredPosition < 0 ? 0 : restoredPosition,
    );

    setState(() => _isLoading = false);

    // Baseline the undo history at the state the app opened with. Without
    // this the first edit is what establishes the baseline, so the very first
    // thing a user types has nothing to undo back to.
    _syncHistoryMark();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (int i = 0; i < count; i++) {
        _updateExactResult(i);
      }
    });
  }

  Future<void> _saveCells() async {
    List<int> sortedKeys = mathEditorControllers.keys.toList()..sort();

    List<List<MathNode>> expressions = [];
    List<Map<String, dynamic>?> plotViews = [];

    for (int key in sortedKeys) {
      MathEditorController? mathController = mathEditorControllers[key];
      if (mathController == null) continue;
      expressions.add(mathController.expression);

      // Read the live view where the panel is on screen; fall back to what was
      // restored for cells that have not been built this session, so paging
      // away from a cell does not forget where it was left.
      final PlotViewState? live =
          _plotPanelKeys[key]?.currentState?.currentView();
      final PlotViewState view =
          live ?? _restoredViews[key] ?? PlotViewState.initial;
      _restoredViews[key] = view;
      plotViews.add(view.isInitial ? null : view.toJson());
    }

    await CellPersistence.saveCells(expressions, plotViews);
    await CellPersistence.saveActiveIndex(activeIndex);
  }

  // In HomePageState
  void _onSettingsChanged() {
    // Clear texture cache when theme changes
    TextureGenerator.clearCache();

    updateMathEditor();

    for (final controller in mathEditorControllers.values) {
      controller.refreshDisplay();
    }

    // Force rebuild to reload textures
    setState(() {});
  }

  void _cascadeUpdates(int changedIndex) {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      mathEditorControllers[changedIndex]?.updateAnswer(
        textDisplayControllers[changedIndex],
      );

      // NEW: Update exact result
      _updateExactResult(changedIndex);

      List<int> keys = mathEditorControllers.keys.toList()..sort();

      for (int key in keys) {
        if (key > changedIndex) {
          String expr = mathEditorControllers[key]?.expr ?? '';

          if (expr.contains('ans$changedIndex') || expr.contains('ans')) {
            Map<int, String> ansValues = _getAnsValues();
            mathEditorControllers[key]?.onCalculate(ansValues: ansValues);
            mathEditorControllers[key]?.updateAnswer(
              textDisplayControllers[key],
            );
            // NEW: Update exact result for cascaded cells
            _updateExactResult(key);
          }
        }
      }
    } finally {
      _isUpdating = false;
    }

    setState(() {});
  }

  void focusManager(int index) {
    focusNodes[index]?.requestFocus();
    activeIndex = index;
  }

  void _clearAllSelectionOverlays() {
    for (final key in mathEditorKeys.values) {
      key.currentState?.clearOverlay();
    }
  }

  /// Auto-scroll to the end when expression fills the screen
  /// Only scrolls when cursor is at the end of the expression (not when editing in middle)
  void _autoScrollToEnd(int index) {
    final scrollController = scrollControllers[index];
    final mathController = mathEditorControllers[index];
    if (scrollController == null || !scrollController.hasClients) return;
    if (mathController == null) return;

    // Only auto-scroll if cursor is at the end of the root expression
    final cursor = mathController.cursor;
    final expression = mathController.expression;

    // Check if cursor is at the end: at root level, at last node, at end of text
    bool isAtEnd =
        cursor.parentId == null && cursor.index == expression.length - 1;

    if (isAtEnd && expression.isNotEmpty) {
      final lastNode = expression.last;
      if (lastNode is LiteralNode) {
        isAtEnd = cursor.subIndex >= lastNode.text.length;
      }
    }

    if (!isAtEnd) return; // Don't scroll if not at end

    // Schedule scroll after layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        // With reverse: true, position 0 is the RIGHT end (where cursor is)
        if (scrollController.offset != 0) {
          scrollController.jumpTo(0);
        }
      }
    });
  }

  void _addDisplay({int? insertAt}) {
    // Default: insert after the active cell
    int insertIndex = insertAt ?? (activeIndex + 1);

    // Clamp to valid range
    insertIndex = insertIndex.clamp(0, count);

    if (insertIndex < count) {
      // Need to shift existing controllers to make room
      _shiftControllersUp(insertIndex);
    }

    _createControllers(insertIndex);

    setState(() {
      count += 1;
      activeIndex = insertIndex;
    });

    // Slide to the page that was just created rather than snapping to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final position = _pageKeys.indexOf(insertIndex);
      if (position != -1 && _pageViewController.hasClients) {
        _pageViewController.animateToPage(
          position,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      // Recalculate results for cells after the inserted one (ans references
      // may have shifted)
      for (int i = insertIndex + 1; i < count; i++) {
        _updateExactResult(i);
      }
    });
  }

  void _shiftControllersUp(int fromIndex) {
    // Work backwards from the end to avoid overwriting
    for (int i = count - 1; i >= fromIndex; i--) {
      int newIndex = i + 1;

      // Move all controller references
      mathEditorControllers[newIndex] = mathEditorControllers[i]!;
      textDisplayControllers[newIndex] = textDisplayControllers[i]!;
      focusNodes[newIndex] = focusNodes[i]!;
      scrollControllers[newIndex] = scrollControllers[i]!;
      mathEditorKeys[newIndex] = mathEditorKeys[i]!;
      exactResultNodes[newIndex] = exactResultNodes[i];
      exactResultExprs[newIndex] = exactResultExprs[i];
      currentResultPage[newIndex] = currentResultPage[i] ?? 0;
      currentResultPageNotifiers[newIndex] = currentResultPageNotifiers[i]!;
      resultPageProgressNotifiers[newIndex] = resultPageProgressNotifiers[i]!;
      exactResultVersionNotifiers[newIndex] = exactResultVersionNotifiers[i]!;

      // Move resultPageControllers if it exists
      if (resultPageControllers.containsKey(i)) {
        resultPageControllers[newIndex] = resultPageControllers[i]!;
      }

      // Move plot expanded state
      if (_plotExpanded.containsKey(i)) {
        _plotExpanded[newIndex] = _plotExpanded[i]!;
      }
    }

    // Clear the old references at fromIndex (will be replaced by _createControllers)
    mathEditorControllers.remove(fromIndex);
    textDisplayControllers.remove(fromIndex);
    focusNodes.remove(fromIndex);
    scrollControllers.remove(fromIndex);
    mathEditorKeys.remove(fromIndex);
    resultPageControllers.remove(fromIndex);
    exactResultNodes.remove(fromIndex);
    exactResultExprs.remove(fromIndex);
    currentResultPage.remove(fromIndex);
    currentResultPageNotifiers.remove(fromIndex);
    resultPageProgressNotifiers.remove(fromIndex);
    exactResultVersionNotifiers.remove(fromIndex);
    _plotExpanded.remove(fromIndex);
  }

  void _removeDisplay(int indexToRemove) {
    if (count <= 1) return;

    mathEditorControllers[indexToRemove]?.dispose();
    mathEditorControllers.remove(indexToRemove);
    textDisplayControllers[indexToRemove]?.dispose();
    textDisplayControllers.remove(indexToRemove);
    focusNodes[indexToRemove]?.dispose();
    focusNodes.remove(indexToRemove);
    scrollControllers[indexToRemove]?.dispose();
    scrollControllers.remove(indexToRemove);
    mathEditorKeys.remove(indexToRemove);

    resultPageControllers[indexToRemove]?.dispose();
    resultPageControllers.remove(indexToRemove);
    exactResultNodes.remove(indexToRemove);
    currentResultPage.remove(indexToRemove);
    currentResultPageNotifiers[indexToRemove]?.dispose();
    currentResultPageNotifiers.remove(indexToRemove);
    resultPageProgressNotifiers[indexToRemove]?.dispose();
    resultPageProgressNotifiers.remove(indexToRemove);
    exactResultVersionNotifiers[indexToRemove]?.dispose(); // ADD THIS
    exactResultVersionNotifiers.remove(indexToRemove); // ADD THIS

    // The cell's plot goes with it: its panel key, the view it was left at,
    // and whether it was expanded.
    _plotPanelKeys.remove(indexToRemove);
    _restoredViews.remove(indexToRemove);
    _plotExpanded.remove(indexToRemove);

    int newActiveIndex;
    if (activeIndex == indexToRemove) {
      newActiveIndex = indexToRemove > 0 ? indexToRemove - 1 : 0;
    } else if (activeIndex > indexToRemove) {
      newActiveIndex = activeIndex - 1;
    } else {
      newActiveIndex = activeIndex;
    }

    _reindexControllers();

    setState(() {
      count -= 1;
      activeIndex = newActiveIndex;
    });
  }

  /// Save the active cell's plot to a file and hand it to the share sheet.
  ///
  /// The plot is rasterised, so the formats offered are the ones a raster can
  /// honestly be: PNG, JPEG, and a PDF page holding the image. SVG is not
  /// offered — a Flutter Picture does not expose the operations that drew it,
  /// so an .svg could only wrap the same bitmap and would not scale, which is
  /// the one thing the format is chosen for.
  Future<void> _exportPlot() async {
    final InlinePlotPanelState? panel =
        _plotPanelKeys[activeIndex]?.currentState;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (panel == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Open a plot before exporting')),
      );
      return;
    }

    final PlotExportFormat? format = await _askExportFormat();
    if (format == null) return;

    try {
      final ui.Image? image = await panel.capturePlot();
      if (image == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('The plot is not on screen to export')),
        );
        return;
      }

      final Uint8List bytes = await PlotExporter.encode(image, format);
      image.dispose();

      final Directory dir = await getTemporaryDirectory();
      final File file = File('${dir.path}/${PlotExporter.fileName(format)}');
      await file.writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path, mimeType: format.mimeType)],
          fileNameOverrides: <String>[file.uri.pathSegments.last],
        ),
      );
    } catch (e) {
      // Cancelling the share sheet, no room on disk, a plot that cannot be
      // rasterised — none of these should take the app down mid-export.
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  /// Which file format, or null if the sheet was dismissed.
  Future<PlotExportFormat?> _askExportFormat() {
    final AppColors colors = AppColors.of(context, listen: false);
    return showModalBottomSheet<PlotExportFormat>(
      context: context,
      backgroundColor: colors.containerBackground,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Export plot',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final PlotExportFormat f in PlotExportFormat.values)
                  ListTile(
                    title: Text(
                      f.label,
                      style: TextStyle(color: colors.textPrimary),
                    ),
                    subtitle: Text(
                      '.${f.extension}',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                    onTap: () => Navigator.pop(context, f),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _clearAllDisplays() {
    _saveAppStateForUndo();

    for (var controller in mathEditorControllers.values) {
      controller.dispose();
    }
    for (var controller in textDisplayControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    for (var scrollController in scrollControllers.values) {
      scrollController.dispose();
    }
    // We don't dispose resultPageControllers here because they are owned by the widgets.
    // When the widgets are removed/replaced, they will dispose their own controllers.

    for (var notifier in resultPageProgressNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in currentResultPageNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in exactResultVersionNotifiers.values) {
      notifier.dispose();
    }

    mathEditorControllers.clear();
    textDisplayControllers.clear();
    focusNodes.clear();
    mathEditorKeys.clear();
    scrollControllers.clear();
    resultPageControllers.clear();
    exactResultNodes.clear();
    exactResultExprs.clear();
    currentResultPage.clear();
    currentResultPageNotifiers.clear();
    resultPageProgressNotifiers.clear();
    exactResultVersionNotifiers.clear();

    _createControllers(0);

    setState(() {
      count = 1;
      activeIndex = 0;
    });
  }

  void _reindexControllers() {
    List<int> oldKeys = mathEditorControllers.keys.toList()..sort();

    Map<int, MathEditorController> newMathControllers = {};
    Map<int, TextEditingController> newDisplayControllers = {};
    Map<int, FocusNode> newFocusNodes = {};
    Map<int, ScrollController> newScrollControllers = {};
    Map<int, GlobalKey<MathEditorInlineState>> newMathEditorKeys = {};
    Map<int, PageController> newResultPageControllers = {};
    Map<int, List<MathNode>?> newExactResultNodes = {};
    Map<int, Expr?> newExactResultExprs = {};
    Map<int, int> newCurrentResultPage = {};
    Map<int, ValueNotifier<int>> newCurrentResultPageNotifiers = {};
    Map<int, ValueNotifier<double>> newResultPageProgressNotifiers = {};
    Map<int, ValueNotifier<int>> newExactResultVersionNotifiers =
        {}; // ADD THIS

    // Not every map has an entry for every cell. resultPageControllers in
    // particular is filled in by the result widgets when a cell actually has
    // more than one result page, so for most cells it holds nothing at all.
    // Dereferencing it with `!` threw part-way through renumbering, which
    // aborted the removal and left the cell on screen — the reason backspace
    // on an empty cell appeared to do nothing.
    void carry<T>(Map<int, T> from, Map<int, T> to, int oldKey, int newIndex) {
      final T? value = from[oldKey];
      if (value != null) to[newIndex] = value;
    }

    final Map<int, GlobalKey<InlinePlotPanelState>> newPlotPanelKeys = {};
    final Map<int, PlotViewState> newRestoredViews = {};
    final Map<int, bool> newPlotExpanded = {};

    for (int newIndex = 0; newIndex < oldKeys.length; newIndex++) {
      int oldKey = oldKeys[newIndex];
      // Guaranteed: oldKeys is this map's own key list.
      newMathControllers[newIndex] = mathEditorControllers[oldKey]!;
      carry(textDisplayControllers, newDisplayControllers, oldKey, newIndex);
      carry(focusNodes, newFocusNodes, oldKey, newIndex);
      carry(scrollControllers, newScrollControllers, oldKey, newIndex);
      carry(mathEditorKeys, newMathEditorKeys, oldKey, newIndex);
      carry(resultPageControllers, newResultPageControllers, oldKey, newIndex);
      newExactResultNodes[newIndex] = exactResultNodes[oldKey];
      newExactResultExprs[newIndex] = exactResultExprs[oldKey];
      newCurrentResultPage[newIndex] = currentResultPage[oldKey] ?? 0;
      carry(
        currentResultPageNotifiers,
        newCurrentResultPageNotifiers,
        oldKey,
        newIndex,
      );
      carry(
        resultPageProgressNotifiers,
        newResultPageProgressNotifiers,
        oldKey,
        newIndex,
      );
      carry(
        exactResultVersionNotifiers,
        newExactResultVersionNotifiers,
        oldKey,
        newIndex,
      );

      // The plot side has to move with the cell too. Left behind, a surviving
      // cell inherits the panel key and saved view of a different one — and
      // for a GlobalKey that means two panels claiming the same key.
      carry(_plotPanelKeys, newPlotPanelKeys, oldKey, newIndex);
      carry(_restoredViews, newRestoredViews, oldKey, newIndex);
      carry(_plotExpanded, newPlotExpanded, oldKey, newIndex);
    }

    _plotPanelKeys
      ..clear()
      ..addAll(newPlotPanelKeys);
    _restoredViews
      ..clear()
      ..addAll(newRestoredViews);
    _plotExpanded
      ..clear()
      ..addAll(newPlotExpanded);

    mathEditorControllers = newMathControllers;
    textDisplayControllers = newDisplayControllers;
    focusNodes = newFocusNodes;
    scrollControllers = newScrollControllers;
    mathEditorKeys = newMathEditorKeys;
    resultPageControllers = newResultPageControllers;
    exactResultNodes = newExactResultNodes;
    exactResultExprs = newExactResultExprs;
    currentResultPage = newCurrentResultPage;
    currentResultPageNotifiers = newCurrentResultPageNotifiers;
    resultPageProgressNotifiers = newResultPageProgressNotifiers;
    exactResultVersionNotifiers = newExactResultVersionNotifiers; // ADD THIS
  }

  void _restoreAppState(AppState state) {
    // Rebuilding the cells runs updateMathEditor at the end, which would
    // otherwise see the restored state as a fresh edit — recording an undo
    // step for the undo itself and wiping the redo stack it had just filled.
    _restoringHistory = true;
    try {
      _applyAppState(state);
    } finally {
      _restoringHistory = false;
    }
  }

  void _applyAppState(AppState state) {
    for (var controller in mathEditorControllers.values) {
      controller.dispose();
    }
    for (var controller in textDisplayControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    for (var scrollController in scrollControllers.values) {
      scrollController.dispose();
    }
    // We don't dispose resultPageControllers here because they are owned by the widgets.

    for (var notifier in resultPageProgressNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in currentResultPageNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in exactResultVersionNotifiers.values) {
      notifier.dispose();
    }

    mathEditorControllers.clear();
    textDisplayControllers.clear();
    focusNodes.clear();
    mathEditorKeys.clear();
    scrollControllers.clear();
    resultPageControllers.clear();
    exactResultNodes.clear();
    exactResultExprs.clear();
    currentResultPage.clear();
    currentResultPageNotifiers.clear();
    resultPageProgressNotifiers.clear();
    exactResultVersionNotifiers.clear();

    for (int i = 0; i < state.expressions.length; i++) {
      _createControllers(i);
      mathEditorControllers[i]?.setExpression(
        MathClipboard.deepCopyNodes(state.expressions[i]),
      );
      textDisplayControllers[i]?.text = state.answers[i];
    }

    if (state.expressions.isEmpty) {
      _createControllers(0);
    }

    setState(() {
      count = state.expressions.isEmpty ? 1 : state.expressions.length;
      activeIndex = state.activeIndex.clamp(0, count - 1);
    });

    updateMathEditor();
  }

  /// The state as of the last recorded history point, and its signature.
  ///
  /// Undo has to restore the state *before* an edit, but the only hook every
  /// edit passes through — [updateMathEditor] — runs after the change has
  /// already been made. So the previous state is held here and pushed when the
  /// next change is noticed, rather than trying to intercept every mutation
  /// site: keypad buttons, selection wraps, paste, cell add and remove.
  AppState? _historyMark;
  String? _historySignature;

  /// True while an undo or redo is being applied, so restoring does not record
  /// itself as a fresh edit.
  bool _restoringHistory = false;

  /// Note the current state as the baseline, without recording an undo step.
  void _syncHistoryMark() {
    _historyMark = AppState.capture(
      mathEditorControllers,
      textDisplayControllers,
      activeIndex,
    );
    _historySignature = _historyMark!.signature;
  }

  /// Record an undo point if the expressions changed since the last one.
  ///
  /// Called at the end of [updateMathEditor], once answers have been
  /// recalculated, so a restored state carries its own results.
  void _recordHistoryPoint() {
    if (_restoringHistory) return;

    final AppState current = AppState.capture(
      mathEditorControllers,
      textDisplayControllers,
      activeIndex,
    );
    final String signature = current.signature;

    if (_historyMark == null) {
      _historyMark = current;
      _historySignature = signature;
      return;
    }
    if (signature == _historySignature) return;

    _appUndoStack.add(_historyMark!);
    if (_appUndoStack.length > _maxAppHistorySize) {
      _appUndoStack.removeAt(0);
    }
    _appRedoStack.clear();

    _historyMark = current;
    _historySignature = signature;
  }

  /// Save current app state before destructive operations
  void _saveAppStateForUndo() {
    _appUndoStack.add(
      AppState.capture(
        mathEditorControllers,
        textDisplayControllers,
        activeIndex,
      ),
    );

    // Limit stack size
    if (_appUndoStack.length > _maxAppHistorySize) {
      _appUndoStack.removeAt(0);
    }

    // Clear redo stack when new action is performed
    _appRedoStack.clear();

    // The step is already recorded, so drop the baseline: the next
    // [_recordHistoryPoint] re-establishes it rather than pushing the same
    // state a second time for one action.
    _historyMark = null;
    _historySignature = null;
  }

  /// Check if app-level undo is available
  bool get canUndoAppState => _appUndoStack.isNotEmpty;

  /// Check if app-level redo is available
  bool get canRedoAppState => _appRedoStack.isNotEmpty;

  /// Undo app-level action (like Clear All)
  void undoAppState() {
    if (!canUndoAppState) return;

    // Save current state to redo stack
    _appRedoStack.add(
      AppState.capture(
        mathEditorControllers,
        textDisplayControllers,
        activeIndex,
      ),
    );

    // Get previous state
    AppState previousState = _appUndoStack.removeLast();

    // Restore the state
    _restoreAppState(previousState);
    // The baseline is now the state we just moved to, so the next edit records
    // a step from here rather than from the one we undid.
    _syncHistoryMark();
  }

  /// Redo app-level action
  void redoAppState() {
    if (!canRedoAppState) return;

    // Save current state to undo stack
    _appUndoStack.add(
      AppState.capture(
        mathEditorControllers,
        textDisplayControllers,
        activeIndex,
      ),
    );

    // Get redo state
    AppState redoState = _appRedoStack.removeLast();

    // Restore the state
    _restoreAppState(redoState);
    _syncHistoryMark();
  }

  @override
  Widget build(BuildContext context) {
    _applyOrientationLock(context);

    if (_isLoading) {
      final colors = AppColors.of(context);
      return Scaffold(
        backgroundColor: colors.displayBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final colors = AppColors.of(context);

    return WalkthroughOverlay(
      walkthroughService: _walkthroughService,
      targetKeys: _walkthroughTargets,
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 5,
          backgroundColor: colors.displayBackground,
        ),
        backgroundColor: colors.displayBackground,
        body: Stack(
          children: [
            // SVG Background
            Positioned.fill(
              child: SvgPicture.asset(
                colors.backgroundImage,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            SafeArea(
              child: Column(
                children: <Widget>[
                  // One cell fills the page: its plot takes all the room
                  // above its expression. Other cells are reached by the swipe
                  // strip below rather than by scrolling.
                  Expanded(
                    child: PageView.builder(
                      controller: _pageViewController,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _pageKeys.length,
                      onPageChanged: (position) {
                        final keys = _pageKeys;
                        if (position >= 0 && position < keys.length) {
                          _captureView(_currentPageIndex);
                          setState(() => activeIndex = keys[position]);
                        }
                      },
                      itemBuilder: (context, position) {
                        final keys = _pageKeys;
                        if (position >= keys.length) {
                          return const SizedBox.shrink();
                        }
                        return _buildExpressionDisplay(keys[position], colors);
                      },
                    ),
                  ),
                  // A hairline between the expression and the strip below it,
                  // so the two read as separate surfaces rather than one.
                  Container(height: 1, color: colors.divider),
                  KeyedSubtree(
                    key: _plotStripKey,
                    child: _buildPageSwipeStrip(colors),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Builder(
                      builder: (context) {
                        final mediaQuery = MediaQuery.of(context);
                        double screenWidth = mediaQuery.size.width;
                        bool isLandscape =
                            mediaQuery.orientation == Orientation.landscape;

                        return CalculatorKeypad(
                          screenWidth: screenWidth,
                          isLandscape: isLandscape,
                          colors: colors,
                          activeIndex: activeIndex,
                          mathEditorControllers: mathEditorControllers,
                          textDisplayControllers: textDisplayControllers,
                          settingsProvider: _settingsProvider!,
                          onUpdateMathEditor: updateMathEditor,
                          onAddDisplay: _addDisplay,
                          onRemoveDisplay: _removeDisplay,
                          onExportPlot: _exportPlot,
                          variableSystem: _variableSystem,
                          unitVectorSystem: _unitVectorSystem,
                          onVariableSystemChanged: (system) {
                            // The two groups move together. A row of x, y, z
                            // beside r̂, θ̂, ẑ describes a point in one system
                            // and its directions in another, which is not a
                            // thing anyone means to write.
                            setState(() {
                              _variableSystem = system;
                              _unitVectorSystem = system;
                            });
                            // The symbols an expression is read in changed, so
                            // every cell has to be recompiled and redrawn.
                            updateMathEditor();
                          },
                          onUnitVectorSystemChanged: (system) {
                            setState(() {
                              _unitVectorSystem = system;
                              _variableSystem = system;
                            });
                          },
                          onClearAllDisplays: _clearAllDisplays,
                          onSetState: () => setState(() {}),
                          onClearSelectionOverlay: _clearAllSelectionOverlays,
                          canUndoAppState: canUndoAppState,
                          canRedoAppState: canRedoAppState,
                          onUndoAppState: undoAppState,
                          onRedoAppState: redoAppState,
                          // Walkthrough
                          walkthroughService: _walkthroughService,
                          scientificKeypadKey: _scientificKeypadKey,
                          numberKeypadKey: _numberKeypadKey,
                          extrasKeypadKey: _extrasKeypadKey,
                          commandButtonKey: _commandButtonKey,
                          mainKeypadAreaKey: _mainKeypadAreaKey,
                          settingsButtonKey: _settingsButtonKey,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<int, String> _getAnsValues() {
    Map<int, String> ansValues = {};

    List<int> keys = mathEditorControllers.keys.toList()..sort();
    for (int key in keys) {
      String? result = mathEditorControllers[key]?.result;

      if (result != null && result.isNotEmpty) {
        String parseableResult = result.replaceAll('\u1D07', 'E');

        if (double.tryParse(parseableResult) != null) {
          ansValues[key] = parseableResult;
        } else {
          List<String> lines = parseableResult.split('\n');
          if (lines.isNotEmpty) {
            RegExp numRegex = RegExp(r'=\s*(-?\d+\.?\d*(?:[eE][+-]?\d+)?)');
            Match? numMatch = numRegex.firstMatch(lines.first);
            if (numMatch != null) {
              ansValues[key] = numMatch.group(1)!;
            }
          }
        }
      }
    }

    return ansValues;
  }

  void updateMathEditor() {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      List<int> keys = mathEditorControllers.keys.toList()..sort();

      for (int key in keys) {
        Map<int, String> ansValues = _getAnsValues();
        mathEditorControllers[key]?.onCalculate(ansValues: ansValues);
        mathEditorControllers[key]?.updateAnswer(textDisplayControllers[key]);

        // NEW: Update exact result
        _updateExactResult(key);
      }
    } finally {
      _isUpdating = false;
    }

    // Every edit reaches here, so this is where an undo point is taken.
    _recordHistoryPoint();

    setState(() {});
    _saveCells();
  }

  bool isOperator(String x) {
    if (x == '/' || x == 'x' || x == '-' || x == '+' || x == '=') {
      return true;
    }
    return false;
  }
}

String _describeMathNodes(List<MathNode> nodes) {
  if (nodes.isEmpty) return '[]';
  final parts = nodes.map(_describeMathNode).toList();
  return '[${parts.join(', ')}]';
}

String _describeMathNode(MathNode node) {
  if (node is LiteralNode) return 'Literal("${node.text}")';
  if (node is FractionNode) {
    return 'Fraction(num:${_describeMathNodes(node.numerator)}, den:${_describeMathNodes(node.denominator)})';
  }
  if (node is ExponentNode) {
    return 'Exponent(base:${_describeMathNodes(node.base)}, pow:${_describeMathNodes(node.power)})';
  }
  if (node is ParenthesisNode) {
    return 'Paren(${_describeMathNodes(node.content)})';
  }
  if (node is RootNode) {
    return 'Root(idx:${_describeMathNodes(node.index)}, rad:${_describeMathNodes(node.radicand)})';
  }
  if (node is LogNode) {
    return 'Log(base:${_describeMathNodes(node.base)}, arg:${_describeMathNodes(node.argument)})';
  }
  if (node is TrigNode) {
    return 'Trig(${node.function}, arg:${_describeMathNodes(node.argument)})';
  }
  if (node is SummationNode) {
    return 'Sum(var:${_describeMathNodes(node.variable)}, low:${_describeMathNodes(node.lower)}, up:${_describeMathNodes(node.upper)}, body:${_describeMathNodes(node.body)})';
  }
  if (node is ProductNode) {
    return 'Prod(var:${_describeMathNodes(node.variable)}, low:${_describeMathNodes(node.lower)}, up:${_describeMathNodes(node.upper)}, body:${_describeMathNodes(node.body)})';
  }
  if (node is DerivativeNode) {
    return 'Diff(var:${_describeMathNodes(node.variable)}, at:${_describeMathNodes(node.at)}, body:${_describeMathNodes(node.body)})';
  }
  if (node is IntegralNode) {
    return 'Int(var:${_describeMathNodes(node.variable)}, low:${_describeMathNodes(node.lower)}, up:${_describeMathNodes(node.upper)}, body:${_describeMathNodes(node.body)})';
  }
  if (node is AnsNode) {
    return 'Ans(${_describeMathNodes(node.index)})';
  }
  if (node is ConstantNode) return 'Const(${node.constant})';
  if (node is UnitVectorNode) return 'Unit(${node.axis})';
  if (node is NewlineNode) return 'Newline';
  if (node is ComplexNode) {
    return 'Complex(${_describeMathNodes(node.content)})';
  }
  return node.runtimeType.toString();
}

/// Isolated widget for the result PageView to prevent unnecessary rebuilds
/// Isolated widget for the result PageView to prevent unnecessary rebuilds
class AnimatedResultContent extends StatelessWidget {
  final double animationValue;
  final bool isAnimating;
  final Widget child;

  const AnimatedResultContent({
    super.key,
    required this.animationValue,
    required this.isAnimating,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!isAnimating) {
      return child;
    }

    // Fade and subtle scale animation
    return Opacity(
      opacity: animationValue.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.95 + (0.05 * animationValue), // Scale from 0.95 to 1.0
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
