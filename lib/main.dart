import 'dart:math' show exp;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:klotter/widgets/confirm_clear_dialog.dart';
import 'package:klotter/utils/texture_generator.dart';
import 'package:provider/provider.dart';
import 'settings/settings_provider.dart';
import 'math_renderer/renderer.dart';
import 'utils/app_colors.dart';
import 'math_renderer/cell_persistence_service.dart';
import 'math_renderer/expression_row.dart';
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
import 'math_engine/math_engine_exact.dart';
import 'plotting/models/plot_view_state.dart';
import 'plotting/parsers/plot_expression.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'plotting/export/plot_exporter.dart';
import 'plotting/utils/plot_theme.dart';
import 'plotting/widgets/inline_plot_panel.dart';
import 'utils/crash_log.dart';
import 'utils/render_box.dart';
import 'utils/laid_out_subtree.dart';
import 'utils/memory_release.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before anything else that can fail, so a failure during startup is
  // recorded too.
  CrashLog.install();

  final settingsProvider = await SettingsProvider.create();

  runApp(
    ChangeNotifierProvider.value(value: settingsProvider, child: const MyApp()),
  );
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
            // The chosen font, not the built-in default. Hardcoding the
            // constant here meant the setting changed the expression (which
            // asks MathTextStyle) while every button, label and result stayed
            // on OpenSans.
            fontFamily: settings.fontFamily,
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
            // The chosen font, not the built-in default. Hardcoding the
            // constant here meant the setting changed the expression (which
            // asks MathTextStyle) while every button, label and result stayed
            // on OpenSans.
            fontFamily: settings.fontFamily,
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

  /// Every plot's expression rows, in the order they are shown.
  ///
  /// The store. A plot used to own one editor whose lines were `NewlineNode`
  /// sentinels; it now owns a list of rows, each with its own editor, identity
  /// and visibility. Today every plot holds exactly one row, so behaviour is
  /// unchanged — the shape is what has moved.
  ///
  /// The three maps below are derived from it, so the many places that ask a
  /// plot for "its editor" keep working while the rows grow plural.
  final Map<int, List<ExpressionRow>> _rows = <int, List<ExpressionRow>>{};

  /// Which row of the active plot is being typed into.
  int activeRow = 0;

  /// The rows of [plot], or empty while one is being built.
  List<ExpressionRow> rowsOf(int plot) =>
      _rows[plot] ?? const <ExpressionRow>[];

  /// The row a plot is currently showing a caret in.
  ///
  /// Only the active plot has a live row cursor; every other plot answers with
  /// its first row, which is what the callers that just want "this plot's
  /// expression" mean.
  ExpressionRow? activeRowOf(int plot) {
    final List<ExpressionRow> rows = rowsOf(plot);
    if (rows.isEmpty) return null;
    if (plot != activeIndex) return rows.first;
    return rows[activeRow.clamp(0, rows.length - 1)];
  }

  // These three are a transition scaffold, kept so the many call sites that ask
  // a plot for "its editor" keep working while rows grow plural. Each one
  // *builds a map* on access, so nothing on a hot path should use them — read
  // `rowsOf` or `activeRowOf` directly instead.
  Map<int, GlobalKey<MathEditorInlineState>> get mathEditorKeys =>
      <int, GlobalKey<MathEditorInlineState>>{
        for (final MapEntry<int, List<ExpressionRow>> e in _rows.entries)
          if (activeRowOf(e.key) case final ExpressionRow r) e.key: r.editorKey,
      };
  Map<int, MathEditorController> get mathEditorControllers =>
      <int, MathEditorController>{
        for (final MapEntry<int, List<ExpressionRow>> e in _rows.entries)
          if (activeRowOf(e.key) case final ExpressionRow r)
            e.key: r.controller,
      };
  Map<int, ScrollController> get scrollControllers => <int, ScrollController>{
    for (final MapEntry<int, List<ExpressionRow>> e in _rows.entries)
      if (activeRowOf(e.key) case final ExpressionRow r) e.key: r.scroll,
  };

  /// Every row in the app, across all plots.
  Iterable<ExpressionRow> get _allRows =>
      _rows.values.expand((List<ExpressionRow> r) => r);

  /// Every editor in the app, across all plots and rows.
  ///
  /// The iterate-everything cases — recompute, save, dispose — want this rather
  /// than one controller per plot, or a row that is not currently focused would
  /// be skipped.
  Iterable<MathEditorController> get allControllers => _rows.values
      .expand((List<ExpressionRow> r) => r)
      .map((r) => r.controller);

  Map<int, TextEditingController> textDisplayControllers = {};
  Map<int, FocusNode> focusNodes = {};

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

  /// Which plot a hold-and-drag on the strip is currently pointing at, or
  /// null when nobody is scrubbing.
  ///
  /// The page itself does not move while this is set. Rendering each plot as
  /// the finger passes over it is not affordable: a plot's geometry is cached
  /// against its own expression, so every plot scrubbed past is a cold cache
  /// — measured at 67 ms for a level surface against 5 ms once warm. Half a
  /// dozen of those in a second is a locked-up screen, and none of those
  /// frames is on screen long enough to read anyway. So the scrub moves a
  /// cheap readout and the plot is drawn once, on release.
  int? _scrubTarget;

  /// Where the finger went down on the strip, and the timer that decides
  /// whether staying there means "scrub".
  double _scrubOrigin = 0;
  Timer? _holdTimer;

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
  // The three blocks of the tablet keypad. Separate from the page keys above:
  // those belong to the phone's swipeable pages, and although the two layouts
  // never coexist, a key that means one thing in one layout and something else
  // in the other is a trap for whoever changes either.
  final GlobalKey _tabletNumberBlockKey = GlobalKey();
  final GlobalKey _tabletScientificBlockKey = GlobalKey();
  final GlobalKey _tabletExtrasBlockKey = GlobalKey();
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
    'tablet_number_block': _tabletNumberBlockKey,
    'tablet_scientific_block': _tabletScientificBlockKey,
    'tablet_extras_block': _tabletExtrasBlockKey,
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

    if (_rows.isEmpty) {
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

  /// Test hooks for the row model.
  @visibleForTesting
  List<MathNode> plotNodesForTest(int plot) => _getPlotNodes(plot);

  @visibleForTesting
  bool removeActiveRowForTest() => _removeActiveRow();

  @visibleForTesting
  void addDisplayForTest({int? insertAt}) => _addDisplay(insertAt: insertAt);

  /// Rebuild a plot's rows from what was saved.
  ///
  /// Anything written before rows existed has one expression and no row list,
  /// so it is split on its newlines — the same division the plot was already
  /// making to draw one curve per line. Each line becomes a row, which is what
  /// gives it a swatch and a toggle.
  void _restoreRows(int plot, CellData saved) {
    final List<List<MathNode>> lines =
        saved.rowsJson.isNotEmpty
            ? <List<MathNode>>[
              for (final String json in saved.rowsJson)
                MathExpressionSerializer.deserializeFromJson(json),
            ]
            : PlotExpression.splitLines(
              MathExpressionSerializer.deserializeFromJson(
                saved.expressionJson,
              ),
            );
    if (lines.isEmpty) return;

    // The first row already exists from _createControllers; the rest are made
    // here, so ids stay unique against anything else in this session.
    final List<ExpressionRow> rows = _rows[plot]!;
    while (rows.length < lines.length) {
      final ExpressionRow row = ExpressionRow(id: ExpressionRowIds.take());
      _bindRow(row);
      rows.add(row);
    }
    for (int i = 0; i < lines.length; i++) {
      rows[i].controller.setExpression(lines[i]);
      rows[i].visible = i >= saved.hidden.length || !saved.hidden[i];
    }
  }

  /// Which plot owns [row], or null once it has been removed.
  ///
  /// Looked up rather than captured. A row's plot index changes when a plot is
  /// inserted or deleted before it, so a callback that closed over the index it
  /// was created with would fire against the wrong plot from then on — the same
  /// reason klator resolves its index at call time.
  int? _plotOfRow(ExpressionRow row) {
    for (final MapEntry<int, List<ExpressionRow>> e in _rows.entries) {
      if (e.value.contains(row)) return e.key;
    }
    return null;
  }

  /// Wire a row's editor to the app.
  void _bindRow(ExpressionRow row) {
    row.controller.onResultChanged = () {
      final int? plot = _plotOfRow(row);
      if (plot != null) _cascadeUpdates(plot);
    };
    row.controller.addListener(() {
      final int? plot = _plotOfRow(row);
      if (plot != null) _autoScrollToEnd(plot);
    });
  }

  /// Add an expression row to the current plot, below the one being edited.
  ///
  /// This is what the action key does now. It used to insert a `NewlineNode`
  /// into the plot's single editor; a row can carry its own colour, its own
  /// visibility and its own identity, which a line inside a shared node list
  /// never could.
  ///
  /// Focus is the assignment to [activeRow] and nothing else — there is no
  /// system keyboard and no `FocusNode` in play, exactly as in klator.
  void _addRow() {
    final List<ExpressionRow>? rows = _rows[activeIndex];
    if (rows == null) return;
    // Nothing to add below an empty row. klator does the same: pressing the
    // action key twice would otherwise leave a trail of blank rows, each
    // taking height from the plot and offering a swatch and a toggle for a
    // curve that does not exist.
    final ExpressionRow? current = activeRowOf(activeIndex);
    if (current != null && current.controller.getExpression().isEmpty) return;
    final int at = (activeRow + 1).clamp(0, rows.length);
    final ExpressionRow row = ExpressionRow(id: ExpressionRowIds.take());
    _bindRow(row);
    setState(() {
      rows.insert(at, row);
      activeRow = at;
    });
    updateMathEditor();
    _flushSave();
  }

  /// Remove the row being edited, and report whether it could be.
  ///
  /// The last row of a plot is not removed: a plot with no expression has
  /// nothing to draw and nowhere to type, so the caller falls back to removing
  /// the whole plot, which is what backspace on an empty cell did before.
  bool _removeActiveRow() {
    final List<ExpressionRow>? rows = _rows[activeIndex];
    if (rows == null || rows.length <= 1) return false;
    final int at = activeRow.clamp(0, rows.length - 1);
    final ExpressionRow row = rows[at];
    setState(() {
      rows.removeAt(at);
      activeRow = (at - 1).clamp(0, rows.length - 1);
    });
    row.dispose();
    updateMathEditor();
    _flushSave();
    return true;
  }

  void _createControllers(int index) {
    final ExpressionRow row = ExpressionRow(id: ExpressionRowIds.take());
    _rows[index] = <ExpressionRow>[row];
    _bindRow(row);

    textDisplayControllers[index] = TextEditingController();
    focusNodes[index] = FocusNode();

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
      final List<int> sortedKeys = _rows.keys.toList()..sort();
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

  String _getPlotExpression(int index) =>
      MathExpressionSerializer.serialize(_getPlotNodes(index));

  /// The cell's expression as nodes. The plot compiles from these rather than
  /// from the serialized string, so it evaluates exactly what the calculator
  /// evaluates instead of re-parsing with a weaker grammar.
  /// Every row of a plot, joined as the one node list the panel still expects.
  ///
  /// Rows are separated by the same `NewlineNode` the panel already splits on,
  /// so the plot pipeline is unchanged by rows existing. Passing the lines
  /// through directly is the tidier end state and is the next step; going via
  /// the sentinel keeps this change behaviour-neutral, which is what makes it
  /// safe to land on its own.
  List<MathNode> _getPlotNodes(int index) {
    final List<ExpressionRow> rows = rowsOf(index);
    if (rows.isEmpty) return const <MathNode>[];
    final List<MathNode> out = <MathNode>[];
    for (final ExpressionRow row in rows) {
      if (out.isNotEmpty) out.add(NewlineNode());
      out.addAll(row.controller.expression);
    }
    return out;
  }

  /// klotter always shows the plot. A cell with no free variable is not
  /// unplottable — a constant is a horizontal line, and an empty cell is an
  /// empty set of axes, which is the right thing to look at while you type
  /// the expression that will fill it.
  bool _canShowPlotButton(String expr) => _plotsEnabled;

  /// The cell currently filling the page. Cells are reached by swiping the
  /// strip below the expression, not by scrolling a list.
  int get _currentPageIndex {
    final keys = _rows.keys.toList()..sort();
    if (keys.isEmpty) return 0;
    if (keys.contains(activeIndex)) return activeIndex;
    return keys.last;
  }

  /// The plots, in order.
  ///
  /// Straight off the row store. Going via `mathEditorControllers` built a
  /// whole map — walking every plot and resolving its active row — only to read
  /// the keys back off it, and this is called several times per frame from the
  /// page view and the swipe strip.
  List<int> get _pageKeys => _rows.keys.toList()..sort();

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

  /// Move to [position], carrying the focus and the saved view with it.
  ///
  /// [jump] skips the scroll, for when a genie is covering the swap: sliding
  /// the pages as well would show the change twice.
  void _animateToPage(int position, {bool jump = false}) {
    final keys = _pageKeys;
    if (position < 0 || position >= keys.length) return;
    _captureView(_currentPageIndex);
    setState(() => activeIndex = keys[position]);
    focusNodes[keys[position]]?.requestFocus();
    if (!_pageViewController.hasClients) return;
    if (jump) {
      _pageViewController.jumpToPage(position);
      return;
    }
    // Same feel as the keypad's page transition.
    _pageViewController.animateToPage(
      position,
      // Brisk. This is a step between two plots, not a journey, and at
      // 300 ms it read as the app thinking rather than as a page moving.
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  /// Horizontal swipe target between the expression and the keypad.
  ///
  /// The plot itself owns pan and pinch, so page navigation needs its own
  /// surface rather than competing with those gestures.
  /// How far the finger travels for one plot while scrubbing.
  /// How big the dot for plot [i] is, given the finger is over [focus].
  ///
  /// The dock's magnification: not one dot picked out and the rest left flat,
  /// but a bump that falls away over its neighbours, so the row swells under
  /// the finger and settles either side of it. Only while scrubbing — at rest
  /// the strip is a row of dots and should look like one.
  double _dotSize(int i, int focus) {
    const double resting = 5, current = 7, peak = 14;
    if (_scrubTarget == null) return i == focus ? current : resting;
    // Gaussian falloff over about two dots each way, which is close to the
    // dock's own reach and wide enough to read as a swell rather than a blip.
    final double d = (i - focus).toDouble();
    final double bump = exp(-(d * d) / 2.0);
    return resting + (peak - resting) * bump;
  }

  double _scrubPitch(double stripWidth, int count) {
    if (count <= 1) return stripWidth;
    // Capped rather than floored, which is the opposite of what it was. With
    // only a few plots, dividing the strip between them meant fifty pixels of
    // travel each — slower than just swiping, which is not what a hold-and-run
    // is for. The lower bound only stops a very long list becoming twitchy.
    final double even = stripWidth / count;
    return even < 9.0 ? 9.0 : (even > 18.0 ? 18.0 : even);
  }

  void _scrubTo(double dx, int from, double stripWidth, int count) {
    final int target = (from + dx / _scrubPitch(stripWidth, count)).round();
    final int clamped = target.clamp(0, count - 1);
    if (clamped != _scrubTarget) setState(() => _scrubTarget = clamped);
  }

  /// The readout that floats over the plot while scrubbing.
  ///
  /// The number only. The expression was here too, but it was the serialized
  /// form rather than the typeset one, so it read as something the user had
  /// not written.
  Widget _scrubReadout(AppColors colors, List<int> keys, int target) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${target + 1} / ${keys.length}',
        style: TextStyle(
          color: colors.accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPageSwipeStrip(AppColors colors) {
    final keys = _pageKeys;
    final current = keys.indexOf(_currentPageIndex);
    // The dots follow the finger during a scrub even though the page does not,
    // so the strip is still the thing being operated.
    final int shown = _scrubTarget ?? current;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double stripWidth = constraints.maxWidth;
        return GestureDetector(
          key: const ValueKey<String>('plot-swipe-strip'),
          behavior: HitTestBehavior.opaque,
          // Both behaviours come out of one recogniser rather than two. A
          // long press and a horizontal drag on the same detector compete in
          // the gesture arena, and a swipe that begins with even a moment of
          // stillness loses it: the press timer fires first, the drag is
          // rejected, and the flick does nothing. Which is exactly what a
          // real thumb does on a strip this thin — and why flinging it in a
          // test, where the pointer moves at once, looked fine.
          //
          // So the drag owns the gesture throughout, and holding still is
          // detected here rather than by a rival recogniser.
          onHorizontalDragStart: (details) {
            _scrubOrigin = details.localPosition.dx;
            _holdTimer?.cancel();
            if (keys.length < 2) return;
            _holdTimer = Timer(const Duration(milliseconds: 420), () {
              if (mounted) setState(() => _scrubTarget = current);
            });
          },
          onHorizontalDragUpdate: (details) {
            final double dx = details.localPosition.dx - _scrubOrigin;
            if (_scrubTarget != null) {
              _scrubTo(dx, current, stripWidth, keys.length);
              return;
            }
            // Moved before the hold landed, so this is a swipe after all.
            // Generous on both counts: a thumb rarely holds perfectly still,
            // and a slow swipe turning into a scrub is the more annoying of
            // the two mistakes — the page then waits for the finger to lift.
            if (dx.abs() > 8) _holdTimer?.cancel();
          },
          onHorizontalDragEnd: (details) {
            _holdTimer?.cancel();
            if (_scrubTarget != null) {
              _commitScrub();
              return;
            }
            final v = details.primaryVelocity ?? 0;
            if (v.abs() < 100) return;
            _goToPage(forward: v < 0);
          },
          onHorizontalDragCancel: () {
            _holdTimer?.cancel();
            if (_scrubTarget != null) setState(() => _scrubTarget = null);
          },
          child: Stack(
            // The readout sits above the strip, over the plot it is choosing.
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: <Widget>[
              Container(
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
                          shown > 0
                              ? colors.textSecondary
                              : colors.textSecondary.withValues(alpha: 0.2),
                    ),
                    const SizedBox(width: 10),
                    for (int i = 0; i < keys.length; i++) ...[
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 90),
                        curve: Curves.easeOut,
                        width: _dotSize(i, shown),
                        height: _dotSize(i, shown),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              i == shown
                                  ? colors.accent
                                  : colors.textSecondary.withValues(
                                    alpha: 0.35,
                                  ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color:
                          (shown < keys.length - 1 || _canAddPage)
                              ? colors.textSecondary
                              : colors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ],
                ),
              ),
              if (_scrubTarget != null)
                Positioned(
                  bottom: 34,
                  child: _scrubReadout(colors, keys, _scrubTarget!),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Land on whatever the scrub was pointing at.
  void _commitScrub() {
    final int? target = _scrubTarget;
    setState(() => _scrubTarget = null);
    if (target == null) return;
    _animateToPage(target, jump: true);
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
          bottomInset: _rowPanelHeight[index] ?? 0,
          hiddenRows: <bool>[
            for (final ExpressionRow r in rowsOf(index)) !r.visible,
          ],
          initialView: _restoredViews[index] ?? PlotViewState.initial,
          coordinateSystem: _variableSystem,
          onViewChanged: (view) => _restoredViews[index] = view,
        ),
      ),
    );
  }

  /// Every expression row of a plot, stacked.
  ///
  /// One row is the common case and looks exactly as the single editor did.
  /// Several read as a continuous list, which is the point: each row is its own
  /// expression, drawn as its own curve, and about to carry its own colour
  /// swatch and eye toggle.
  Widget _buildRowStack(int index, BoxConstraints constraints) {
    final List<ExpressionRow> rows = rowsOf(index);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // A hairline of air between rows, so the stack reads as a list of
      // separate expressions rather than one run-on block.
      spacing: _rowGap,
      children: <Widget>[
        for (int r = 0; r < rows.length; r++)
          // Keyed by the row's own identity, not its position, so Flutter
          // reuses the right element when a row is inserted above or removed.
          KeyedSubtree(
            key: ValueKey<int>(rows[r].token),
            child: Row(
              // Centred, because a row can be tall — a fraction or an integral
              // is several times the height of a plain expression — and chrome
              // pinned to the top would drift away from it.
              crossAxisAlignment: CrossAxisAlignment.center,
              // Mirrored for a left-handed layout, like the keypad: the
              // colour swatch and the eye swap sides so both stay under the
              // thumb the setting says is doing the reaching.
              textDirection: _leftHanded ? TextDirection.rtl : null,
              children: <Widget>[
                _rowSwatch(index, rows[r], r),
                Expanded(
                  // Measured here, not from the panel: the editor shares its
                  // row with the swatch and the eye, so the panel's width is
                  // wider than the slot it actually gets. Handing it the panel
                  // width made every expression too wide for its box, which
                  // pushed the glyphs and the caret off centre.
                  child: LayoutBuilder(
                    builder:
                        (context, slot) => SingleChildScrollView(
                          controller: rows[r].scroll,
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: MathEditorInline(
                            key: rows[r].editorKey,
                            controller: rows[r].controller,
                            showCursor: activeIndex == index && activeRow == r,
                            minWidth: slot.maxWidth,
                            // Drag-to-tune edits the node tree directly, so the plot needs
                            // a rebuild to resample.
                            onExpressionChanged: () {
                              updateMathEditor();
                              setState(() {});
                            },
                            onFocus: () {
                              if (activeIndex != index || activeRow != r) {
                                setState(() {
                                  activeIndex = index;
                                  activeRow = r;
                                });
                              }
                            },
                          ),
                        ),
                  ),
                ),
                _rowEye(rows[r]),
              ],
            ),
          ),
      ],
    );
  }

  /// How tall each plot's row panel is, measured rather than guessed.
  ///
  /// The plot's controls have to clear the rows floating over them, and rows
  /// are not a fixed height — a fraction or an integral is several times a
  /// plain expression. So the panel is measured after it lays out and the plot
  /// is told, rather than the height being computed from a row count.
  final Map<int, double> _rowPanelHeight = <int, double>{};
  final Map<int, GlobalKey> _rowPanelKeys = <int, GlobalKey>{};

  /// Read the row panel's height back after layout, and rebuild if it moved.
  final Set<int> _measurePending = <int>{};

  void _measureRowPanel(int plot) {
    // One callback in flight per plot. This is called from build, so without
    // the guard every frame queued another measurement — and any frame that
    // found a different height called setState, which built again, which
    // queued again. That is a rebuild running against every frame of the
    // panel's own size animation, and it made the whole plot feel sluggish and
    // its controls slow to answer.
    if (!_measurePending.add(plot)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurePending.remove(plot);
      if (!mounted) return;
      final RenderBox? box = laidOutBox(_rowPanelKeys[plot]?.currentContext);
      if (box == null) return;
      // Plus the padding the content sits in, which is not part of it.
      final double h = box.size.height + 2 * _rowInset;
      // Sub-pixel jitter is not worth a frame: without a tolerance a height
      // that settles at 43.0000001 rebuilds forever.
      if (((_rowPanelHeight[plot] ?? -1) - h).abs() < 0.5) return;
      setState(() => _rowPanelHeight[plot] = h);
    });
  }

  /// How much air the expression rows get.
  ///
  /// Paid once per row rather than once per plot, so what reads as comfortable
  /// around a single editor reads as loose gaps down a list — and every pixel
  /// spent here is taken from the plot above. These are the two numbers to
  /// nudge if the stack feels cramped or airy.
  static const double _rowInset = 1;
  static const double _rowGap = 1;

  /// The palette the plot draws with.
  ///
  /// Built the same way the panel builds its own, so a row's swatch and its
  /// curve are looking up the same entry rather than two that merely tend to
  /// agree.
  /// The palette for the frame being built.
  ///
  /// Built once and shared by every row: `PlotThemeData.fromColors` is not
  /// cheap, and a swatch and an eye each asked for their own, so a plot with
  /// several rows paid for it twice per row per frame.
  PlotThemeData? _frameRowTheme;

  PlotThemeData get _rowTheme => _frameRowTheme ??= _plotThemeFor(context);

  PlotThemeData _plotThemeFor(BuildContext context) {
    final SettingsProvider settings = Provider.of<SettingsProvider>(context);
    return PlotThemeData.fromColors(
      AppColors.fromType(settings.themeType),
      mode: settings.plotColorMode,
      themeType: settings.themeType,
    );
  }

  /// Whether the interface is laid out for a left hand.
  ///
  /// The same setting that mirrors the keypad. Anything with a leading and a
  /// trailing side follows it — see the handedness note in memory.
  bool get _leftHanded =>
      Provider.of<SettingsProvider>(context).handedness ==
      Handedness.leftHanded;

  /// The colour a row's curve is drawn in.
  ///
  /// Reads the same palette entry the painters do, by row number, so the dot
  /// and the curve cannot disagree. Tapping it moves the caret to that row,
  /// which makes the whole left edge a way of choosing what to edit.
  Widget _rowSwatch(int plot, ExpressionRow row, int r) {
    final Color colour = _rowTheme.seriesColor(r);
    return GestureDetector(
      onTap: () {
        if (activeIndex != plot || activeRow != r) {
          setState(() {
            activeIndex = plot;
            activeRow = r;
          });
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Hollow when hidden: the row keeps its colour — hiding one curve
            // never recolours the others — so the ring says which row this is
            // while the empty middle says it is not being drawn.
            color: row.visible ? colour : Colors.transparent,
            border: Border.all(color: colour, width: 1.5),
          ),
        ),
      ),
    );
  }

  /// Show or hide this row's curve.
  Widget _rowEye(ExpressionRow row) {
    final PlotThemeData theme = _rowTheme;
    return GestureDetector(
      onTap: () {
        setState(() => row.visible = !row.visible);
        updateMathEditor();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Icon(
          row.visible ? Icons.visibility : Icons.visibility_off,
          size: 16,
          color: row.visible ? theme.controlIdle : theme.controlOutline,
        ),
      ),
    );
  }

  Widget _buildExpressionDisplay(int index, AppColors colors) {
    final bool shouldAddKeys = index == activeIndex;
    _frameRowTheme = _plotThemeFor(context);
    _measureRowPanel(index);

    // The plot fills the page and the expression rows float over its lower
    // edge. They used to sit in an opaque band beneath it, so every row cost
    // the plot that much height — with rows now plural, that is height the plot
    // cannot spare. Translucent and on top, the axes run on behind the
    // expressions instead of stopping above them.
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: _buildPlotArea(index, colors, shouldAddKeys: shouldAddKeys),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              // Enough to read an expression against a busy plot, little
              // enough to see the curves through it.
              color: colors.containerBackground.withValues(alpha: 0.82),
              border: Border(
                top: BorderSide(color: colors.divider.withValues(alpha: 0.6)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                key: shouldAddKeys ? _expressionKey : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: _rowInset,
                  vertical: _rowInset,
                ),
                child: AnimatedOpacity(
                  curve: Curves.easeIn,
                  duration: const Duration(milliseconds: 500),
                  opacity: isVisible ? 1.0 : 0.0,
                  // The panel grows into its new height rather than snapping,
                  // so a row arriving reads as the stack making room. The
                  // plot's controls slide on the same curve, and the two
                  // movements are what make adding a row feel like one action
                  // instead of three things jumping at once.
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Rows can outgrow their share of the page, so the stack
                        // scrolls rather than pushing the plot off the top.
                        return ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight:
                                constraints.maxHeight.isFinite
                                    ? constraints.maxHeight
                                    : 260,
                          ),
                          child: SingleChildScrollView(
                            // No outer horizontal scroller: each row owns its
                            // own, so a long expression scrolls independently of
                            // its neighbours.
                            // Keyed here rather than on the panel above:
                            // that box is mid-animation whenever it is
                            // asked, and nothing rebuilds once the
                            // animation ends, so its height would be read
                            // on the way and never corrected. The content
                            // is already at its target.
                            child: KeyedSubtree(
                              key: _rowPanelKeys.putIfAbsent(
                                index,
                                () => GlobalKey(),
                              ),
                              child: _buildRowStack(index, constraints),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
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
    _saveTimer?.cancel();
    _saveCells();

    _walkthroughService.removeListener(_onWalkthroughChanged);
    _walkthroughService.dispose();

    // Every row of every plot, not one controller per plot: the derived maps
    // answer with the focused row only, so iterating them would leak the rest.
    for (final ExpressionRow row in _rows.values.expand(
      (List<ExpressionRow> r) => r,
    )) {
      row.dispose();
    }

    for (TextEditingController resController in textDisplayControllers.values) {
      resController.dispose();
    }

    for (FocusNode focusNode in focusNodes.values) {
      focusNode.dispose();
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
    CrashLog.context = 'the app was ${state.name}';

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // Flushed, not scheduled: the process may not survive long enough for a
      // timer to fire, and this is the last chance to write.
      _flushSave();
    }

    // Only once actually backgrounded. `inactive` also arrives for a dialog or
    // a pull-down of the notification shade, and throwing away every decoded
    // image for those would show as a flash of reloading on the way back.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      releaseMemoryForBackground();
    }
  }

  /// Android asking every process to give memory back.
  ///
  /// This is the warning that precedes being killed, and it is the one chance
  /// to stop being the largest thing on the device.
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    releaseMemoryForBackground();
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
        _restoreRows(i, savedCells[i]);

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

  Timer? _saveTimer;

  /// Save shortly, coalescing a burst of keystrokes into one write.
  ///
  /// Every edit used to write immediately, which is a platform-channel round
  /// trip per character and part of why the app felt heavy. What it must not
  /// become is a way to lose work, so it is paired with [_flushSave] on every
  /// path out of the app — and structural changes do not wait at all.
  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () {
      _saveTimer = null;
      _saveCells();
    });
  }

  /// Write now, cancelling any pending debounce.
  ///
  /// Used where the app may be about to stop existing. Adding or removing a
  /// row or a plot goes through here too: those are the changes worth never
  /// losing, and they are rare enough that writing immediately costs nothing.
  Future<void> _flushSave() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveCells();
  }

  Future<void> _saveCells() async {
    List<int> sortedKeys = _rows.keys.toList()..sort();

    final List<List<List<MathNode>>> rowsPerPlot = <List<List<MathNode>>>[];
    final List<List<bool>> hiddenPerPlot = <List<bool>>[];
    List<Map<String, dynamic>?> plotViews = [];

    for (int key in sortedKeys) {
      final List<ExpressionRow> rows = rowsOf(key);
      if (rows.isEmpty) continue;
      rowsPerPlot.add(<List<MathNode>>[
        for (final ExpressionRow row in rows) row.controller.expression,
      ]);
      hiddenPerPlot.add(<bool>[
        for (final ExpressionRow row in rows) !row.visible,
      ]);

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

    await CellPersistence.saveRows(rowsPerPlot, hiddenPerPlot, plotViews);
    await CellPersistence.saveActiveIndex(activeIndex);
  }

  // In HomePageState
  void _onSettingsChanged() {
    // Clear texture cache when theme changes
    TextureGenerator.clearCache();
    // The built plot themes are keyed on the palette, the colour mode and the
    // theme type. That covers the settings they derive from, but clearing here
    // means a palette that changes in some other way cannot leave a stale
    // theme behind.
    PlotThemeData.clearCache();

    updateMathEditor();

    for (final controller in allControllers) {
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

      List<int> keys = _rows.keys.toList()..sort();

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
    for (final key in _allRows.map((ExpressionRow r) => r.editorKey)) {
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

      // Move all controller references.
      //
      // The rows move as one list. The three editor maps are derived from it
      // now, and assigning into a derived map writes into the temporary it
      // just built — legal Dart, and silently nothing at all. That is what
      // these three lines were doing.
      if (_rows[i] case final List<ExpressionRow> rows) _rows[newIndex] = rows;
      textDisplayControllers[newIndex] = textDisplayControllers[i]!;
      focusNodes[newIndex] = focusNodes[i]!;
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
    _rows.remove(fromIndex);
    textDisplayControllers.remove(fromIndex);
    focusNodes.remove(fromIndex);
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
    _rows.remove(indexToRemove);
    textDisplayControllers[indexToRemove]?.dispose();
    textDisplayControllers.remove(indexToRemove);
    focusNodes[indexToRemove]?.dispose();
    focusNodes.remove(indexToRemove);
    scrollControllers[indexToRemove]?.dispose();

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

  /// Ask first, unless the user has said not to.
  ///
  /// The gate is kept separate from [_clearAllDisplays] so the clearing itself
  /// is untouched — including the `_saveAppStateForUndo()` on its first line,
  /// which is what makes the dialog's promise true.
  Future<void> _confirmClearAllDisplays() async {
    final SettingsProvider settings = context.read<SettingsProvider>();
    if (!settings.confirmClearAll) {
      _clearAllDisplays();
      return;
    }
    final ClearAllChoice? choice = await showConfirmClearDialog(context);
    if (choice == null || !choice.confirmed) return;
    // Only once they have gone through with it: ticking the box and then
    // cancelling is not an instruction to stop warning them.
    if (choice.dontAskAgain) await settings.toggleConfirmClearAll(false);
    if (!mounted) return;
    _clearAllDisplays();
  }

  void _clearAllDisplays() {
    _saveAppStateForUndo();

    for (var controller in allControllers) {
      controller.dispose();
    }
    for (var controller in textDisplayControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    for (var scrollController in _allRows.map((ExpressionRow r) => r.scroll)) {
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

    _rows.clear();
    textDisplayControllers.clear();
    focusNodes.clear();
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
    List<int> oldKeys = _rows.keys.toList()..sort();

    final Map<int, List<ExpressionRow>> newRows = <int, List<ExpressionRow>>{};
    Map<int, TextEditingController> newDisplayControllers = {};
    Map<int, FocusNode> newFocusNodes = {};
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
      if (_rows[oldKey] case final List<ExpressionRow> r) newRows[newIndex] = r;
      carry(textDisplayControllers, newDisplayControllers, oldKey, newIndex);
      carry(focusNodes, newFocusNodes, oldKey, newIndex);
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

    _rows
      ..clear()
      ..addAll(newRows);
    textDisplayControllers = newDisplayControllers;
    focusNodes = newFocusNodes;
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
    for (var controller in allControllers) {
      controller.dispose();
    }
    for (var controller in textDisplayControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    for (var scrollController in _allRows.map((ExpressionRow r) => r.scroll)) {
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

    _rows.clear();
    textDisplayControllers.clear();
    focusNodes.clear();
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
    // Which way the wallpaper leans, for the lighting below. The same test
    // PlotThemeData uses, so the plot ground and the wallpaper never disagree
    // about whether this is a light theme.
    final bool lightGround = colors.displayBackground.computeLuminance() > 0.5;

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
            // The wallpaper SVG is not drawn.
            //
            // Measured, it cost 0.09 ms a frame to replay but 250-300 ms to
            // build the first time, and the plot fills the page and covers it
            // anyway. The plain colour and the lighting below give the same
            // ground without either cost.
            Positioned.fill(child: ColoredBox(color: colors.displayBackground)),
            // Light across the wallpaper.
            //
            // Over the artwork rather than baked into it: the same wash then
            // covers all eleven themes, stays one number to tune, and leaves
            // the SVGs as drawn. Black at the rim and white at the lit point,
            // both at low alpha, so a dark theme deepens and a light one is
            // shaded rather than washed out.
            //
            // IgnorePointer because it spans the whole screen and must not sit
            // between the user and the keypad.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      // Tight to the visible strip. The plot occupies the top
                      // half of the screen and the keypad the bottom, so a
                      // circle sized to the whole window puts its dark rim
                      // behind opaque UI and only the flat middle shows.
                      center: const Alignment(-0.25, -0.75),
                      radius: 0.85,
                      colors: <Color>[
                        Colors.white.withValues(
                          alpha: 0.18 * PlotThemeData.backgroundDepth,
                        ),
                        Colors.transparent,
                        // Harder on a light theme. The eye reads lightness
                        // relatively, so the same wash that swung 76% of the
                        // local value on a dark ground swung only 22% on a
                        // light one and vanished. 1.8x brings a light theme to
                        // about 45%, which is the same order without being
                        // heavy-handed.
                        Colors.black.withValues(
                          alpha:
                              (lightGround ? 1.8 : 0.85) *
                              PlotThemeData.backgroundDepth,
                        ),
                      ],
                      stops: const <double>[0.0, 0.5, 1.0],
                    ),
                  ),
                ),
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
                    // Inside the AnimatedSize, so the guard sits directly above
                    // the keypad's own Column — the box that was reported with
                    // no size. See [LaidOutSubtree].
                    child: LaidOutSubtree(
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
                            activeController:
                                activeRowOf(activeIndex)?.controller,
                            settingsProvider: _settingsProvider!,
                            onUpdateMathEditor: updateMathEditor,
                            // The action key adds a row to this plot; the
                            // swipe strip still adds a whole plot.
                            onAddDisplay: _addRow,
                            // Backspace on an empty row removes that row.
                            // Only when it is the last one left does the
                            // whole plot go, which is what it did before.
                            onRemoveDisplay: (int plot) {
                              if (!_removeActiveRow()) _removeDisplay(plot);
                            },
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
                            onClearAllDisplays: _confirmClearAllDisplays,
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
                            numberBlockKey: _tabletNumberBlockKey,
                            scientificBlockKey: _tabletScientificBlockKey,
                            extrasBlockKey: _tabletExtrasBlockKey,
                            settingsButtonKey: _settingsButtonKey,
                          );
                        },
                      ),
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

    List<int> keys = _rows.keys.toList()..sort();
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
      List<int> keys = _rows.keys.toList()..sort();

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
    _scheduleSave();
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
