import 'dart:math' show exp, min;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:klotter/widgets/confirm_clear_dialog.dart';
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
import 'notebook/notebook.dart';
import 'walkthrough/walkthrough_service.dart';
import 'walkthrough/walkthrough_overlay.dart';
import 'utils/coordinate_system.dart';
import 'math_renderer/math_editor_controller.dart';
import 'plotting/models/plot_view_state.dart';
import 'plotting/parsers/plot_expression.dart' show PlotDefinitions;
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

  // The maths font is under the SIL Open Font License, which asks that the
  // licence travel with every copy. Registered beside the packages' licences
  // so it is listed wherever those are.
  LicenseRegistry.addLicense(_fontLicences);

  final settingsProvider = await SettingsProvider.create();

  runApp(
    ChangeNotifierProvider.value(value: settingsProvider, child: const MyApp()),
  );
}

Stream<LicenseEntry> _fontLicences() async* {
  yield LicenseEntryWithLineBreaks(
    const <String>['STIX Two Math'],
    await rootBundle.loadString('assets/fonts/STIXTwoMath-OFL.txt'),
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
class HomePageState extends State<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
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

  /// The plots and their rows: the document this page shows (see [Notebook]).
  ///
  /// It used to live here as a dozen maps keyed by each plot's position, all
  /// of which had to be renumbered in step whenever a plot came or went.
  late final Notebook notebook = Notebook(onRowCreated: _bindRow);

  /// How many plots there are.
  int get count => notebook.count;

  /// Which plot is open.
  int get activeIndex => notebook.activeIndex;
  set activeIndex(int value) => notebook.activeIndex = value;

  /// Which row of the open plot is being typed into.
  int get activeRow => notebook.activeRow;
  set activeRow(int value) => notebook.activeRow = value;

  /// The rows of [plot].
  List<ExpressionRow> rowsOf(int plot) => notebook.rowsOf(plot);

  /// The row a plot is showing a caret in; see [Notebook.activeRowOf].
  ExpressionRow? activeRowOf(int plot) => notebook.activeRowOf(plot);

  /// Every editor in the app, across all plots and rows.
  Iterable<MathEditorController> get allControllers =>
      notebook.allRows.map((ExpressionRow r) => r.controller);

  final bool _plotsEnabled = true;
  bool _isUpdating = false;
  bool _isLoading = true;

  /// Each plot's panel, by plot id, so its view can be read back when saving.
  final Map<String, GlobalKey<InlinePlotPanelState>> _plotPanelKeys =
      <String, GlobalKey<InlinePlotPanelState>>{};

  /// Forget what the screen kept about plots that have gone.
  ///
  /// Kept by plot id, so nothing has to move when a plot is added or removed
  /// before another; entries for a plot that no longer exists are dropped.
  void _forgetGonePlots() {
    final Set<String> live = <String>{
      for (final Plot plot in notebook.plots) plot.id,
    };
    bool gone(String id) => !live.contains(id);
    _plotPanelKeys.removeWhere((String id, _) => gone(id));
    _rowErrors.removeWhere((String id, _) => gone(id));
    _rowPanelHeight.removeWhere((String id, _) => gone(id));
    _rowPanelKeys.removeWhere((String id, _) => gone(id));
    _threeRowsHeight.removeWhere((String id, _) => gone(id));
    _revealedRow.removeWhere((String id, _) => gone(id));
  }

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

  /// Whether the keypad is folded away under its handle.
  ///
  /// Not saved. A fresh launch always opens with the keys showing, so nobody
  /// starts the app looking at a plot with no visible way to type into it.
  bool _keypadHidden = false;

  /// Slides the keypad away and back: 1 is showing, 0 is folded.
  late final AnimationController _keypadReveal = AnimationController(
    vsync: this,
    value: 1,
    // Entering decelerates and leaving accelerates, and leaving is the
    // quicker of the two — the usual pairing for something the user sends
    // away and calls back.
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 220),
  );

  late final Animation<double> _keypadRevealCurve = CurvedAnimation(
    parent: _keypadReveal,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Height of the strip the handle sits in, and so of everything left at the
  /// foot of the screen once the keypad is folded.
  ///
  /// klator's: a 5 dp pill with 8 dp above and below it. The two apps share
  /// the gesture, so they share its size.
  static const double _keypadHandleHeight = 21;

  /// How far a slow drag on the handle has travelled, for deciding which way
  /// it meant when there is no flick to go on.
  double _handleDrag = 0;

  @visibleForTesting
  bool get keypadHiddenForTest => _keypadHidden;

  /// Fold the keypad away, or bring it back.
  ///
  /// [animate] is false only where the keys have to be there this frame — the
  /// walkthrough measures them as soon as it starts.
  void _setKeypadHidden(bool hidden, {bool animate = true}) {
    if (hidden == _keypadHidden) return;
    // Never mid-tour: every step of the walkthrough points at a key.
    if (hidden && _walkthroughService.isActive) return;
    if (_settingsProvider?.hapticFeedback ?? false) {
      HapticFeedback.selectionClick();
    }
    setState(() => _keypadHidden = hidden);
    if (!animate) {
      _keypadReveal.value = hidden ? 0 : 1;
    } else if (hidden) {
      _keypadReveal.reverse();
    } else {
      _keypadReveal.forward();
    }
  }

  /// The grip between the plot strip and the keypad.
  ///
  /// Tapping it folds the keypad away and gives its height to the plot;
  /// tapping again brings it back. A flick works too — down to fold, up to
  /// open — since a handle invites dragging. Modelled on klator's handle,
  /// which opens its extra row of keys the same way: same pill, same strip,
  /// same soft shadow, so the gesture means one thing in both apps.
  ///
  /// Centred and full-width, so handedness does not move it.
  Widget _buildKeypadHandle(AppColors colors) {
    return Semantics(
      button: true,
      label: _keypadHidden ? 'Show keypad' : 'Hide keypad',
      child: GestureDetector(
        key: const ValueKey<String>('keypad-handle'),
        behavior: HitTestBehavior.opaque,
        // Measured from where the finger landed, so the slop the recogniser
        // waits through before calling it a drag still counts as pull.
        dragStartBehavior: DragStartBehavior.down,
        onTap: () => _setKeypadHidden(!_keypadHidden),
        onVerticalDragStart: (_) => _handleDrag = 0,
        onVerticalDragUpdate: (details) => _handleDrag += details.delta.dy,
        onVerticalDragEnd: (details) {
          // A flick decides on its own; a slow drag decides by how far it
          // went, so a deliberate pull still works without any speed in it.
          final double v = details.primaryVelocity ?? 0;
          if (v.abs() > 200) {
            _setKeypadHidden(v > 0);
          } else if (_handleDrag.abs() > 12) {
            _setKeypadHidden(_handleDrag > 0);
          }
        },
        child: SizedBox(
          height: _keypadHandleHeight,
          width: double.infinity,
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: colors.containerBackground,
                borderRadius: BorderRadius.circular(10),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    spreadRadius: 2,
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

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
    // The swipe happens on the function keys, so only those are lit.
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

    // Initialize walkthrough after build is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeWalkthrough();
    });
  }

  void _onWalkthroughChanged() {
    if (!mounted) return;
    // A tour points at the keys, so it always runs with them showing — at
    // once rather than sliding in, since it measures them straight away.
    if (_walkthroughService.isActive && _keypadHidden) {
      _setKeypadHidden(false, animate: false);
      return;
    }
    setState(() {});
  }

  /// Every row of a cell as plain text, for tests that describe what the user
  /// would see rather than a node tree.
  @visibleForTesting
  String textOfCellForTest(int plot) => <String>[
    for (final ExpressionRow r in rowsOf(plot))
      r.controller.expression
          .map((MathNode n) => n is LiteralNode ? n.text : '~')
          .join(),
  ].join('/');

  /// Wire a row's editor to the app.
  void _bindRow(ExpressionRow row) {
    row.controller.onResultChanged = () {
      final int? plot = notebook.indexOfRow(row);
      if (plot != null) _onRowResultChanged(plot);
    };
    row.controller.addListener(() {
      final int? plot = notebook.indexOfRow(row);
      if (plot != null) _autoScrollToEnd(plot);
      // Undo points are taken here, where the editing actually happens.
      //
      // They used to be taken at the end of `updateMathEditor`, on the belief
      // that every edit passed through it. Most do not: typing reached the
      // controller and changed the expression without that hook running at
      // all, so whole runs of keystrokes — and everything typed after a new
      // cell was added — left no history behind. Undo then jumped back to
      // whatever the last recorded state happened to be, which looked like it
      // deleted the cell rather than the last character.
      //
      // A controller notifies for caret moves too, but the signature is built
      // from expressions alone, so those compare equal and record nothing.
      notebook.recordHistoryPoint();
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
  void addRow() {
    // Nothing is added below an empty row; see [Notebook.addRowBelowActive].
    if (notebook.addRowBelowActive() == null) return;
    setState(() {});
    updateMathEditor();
    _flushSave();
  }

  /// Remove the row being edited, and report whether it could be.
  ///
  /// The last row of a plot is not removed: a plot with no expression has
  /// nothing to draw and nowhere to type, so the caller falls back to removing
  /// the whole plot, which is what backspace on an empty cell did before.
  bool removeActiveRow() {
    if (!notebook.removeActiveRow()) return false;
    setState(() {});
    updateMathEditor();
    _flushSave();
    return true;
  }

  String _getPlotExpression(int index) =>
      MathExpressionSerializer.serialize(_getPlotNodes(index));

  /// Every row of a plot as the one node list its panel draws from; see
  /// [Notebook.plotNodes].
  List<MathNode> _getPlotNodes(int index) => notebook.plotNodes(index);

  /// klotter always shows the plot. A cell with no free variable is not
  /// unplottable — a constant is a horizontal line, and an empty cell is an
  /// empty set of axes, which is the right thing to look at while you type
  /// the expression that will fill it.
  bool _canShowPlotButton(String expr) => _plotsEnabled;

  /// The cell currently filling the page. Cells are reached by swiping the
  /// strip below the expression, not by scrolling a list.
  int get _currentPageIndex =>
      activeIndex >= 0 && activeIndex < count ? activeIndex : count - 1;


  /// Whether a cell has anything on it.
  ///
  /// Measured from the serialized expression, not the node list. An empty cell
  /// still holds one placeholder node, so `expression.isNotEmpty` is true even
  /// for a blank cell — which let a flick forward keep stacking up empty
  /// plots. This is the same test backspace uses to decide a cell is empty
  /// enough to delete, so the two agree on what "empty" means.
  bool _pageHasContent(int index) => notebook.hasContent(index);

  /// Move one page left or right.
  ///
  /// Swiping past the last page creates a new one, but only when the current
  /// page actually has something on it — the same rule the action button used
  /// to follow, so you cannot stack up empty plots by flicking.
  void _goToPage({required bool forward}) {
    final int current = _currentPageIndex;
    if (current < 0) return;

    if (forward) {
      if (current < count - 1) {
        _animateToPage(current + 1);
      } else if (_canAddPage) {
        addPlot();
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
    if (count == 0) return true;
    return _pageHasContent(count - 1);
  }

  /// Remember where a cell's plot was before leaving it.
  ///
  /// A swiped-away panel can be disposed before it is next read, so its view
  /// is captured on the way out — otherwise returning to a cell showed the 2D
  /// view again however it was left.
  void _captureView(int index) {
    if (index < 0 || index >= count) return;
    final Plot plot = notebook.plots[index];
    final PlotViewState? live =
        _plotPanelKeys[plot.id]?.currentState?.currentView();
    if (live != null) plot.view = live;
  }

  /// Move to [position], carrying the focus and the saved view with it.
  ///
  /// [jump] skips the scroll, for when a genie is covering the swap: sliding
  /// the pages as well would show the change twice.
  void _animateToPage(int position, {bool jump = false}) {
    if (position < 0 || position >= count) return;
    _captureView(_currentPageIndex);
    setState(() => activeIndex = position);
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
  Widget _scrubReadout(AppColors colors, int total, int target) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '${target + 1} / $total',
        style: TextStyle(
          color: colors.accent,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPageSwipeStrip(AppColors colors) {
    final int current = _currentPageIndex;
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
            if (count < 2) return;
            _holdTimer = Timer(const Duration(milliseconds: 420), () {
              if (mounted) setState(() => _scrubTarget = current);
            });
          },
          onHorizontalDragUpdate: (details) {
            final double dx = details.localPosition.dx - _scrubOrigin;
            if (_scrubTarget != null) {
              _scrubTo(dx, current, stripWidth, count);
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
                    for (int i = 0; i < count; i++) ...[
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
                          (shown < count - 1 || _canAddPage)
                              ? colors.textSecondary
                              : colors.textSecondary.withValues(alpha: 0.2),
                    ),
                  ],
                ),
              ),
              if (_scrubTarget != null)
                Positioned(
                  bottom: 34,
                  child: _scrubReadout(colors, count, _scrubTarget!),
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
    final Plot plot = notebook.plots[index];
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
      child: InlinePlotPanel(
        key: _plotPanelKeys.putIfAbsent(
          plot.id,
          () => GlobalKey<InlinePlotPanelState>(),
        ),
        expression: plotExpression,
        nodes: _getPlotNodes(index),
        bottomInset: _visibleRowPanelHeight(index),
        hiddenRows: <bool>[
          for (final ExpressionRow r in rowsOf(index)) !r.visible,
        ],
        initialView: plot.view,
        coordinateSystem: _variableSystem,
        // The plot itself, not its position, which another plot being added
        // or removed before it would change under this callback.
        onViewChanged: (view) => plot.view = view,
        onRowErrors: (Map<int, String> byRow) {
          // No entry and an empty report both mean "nothing wrong". The
          // panel reports once whenever it is built, so treating them as
          // different would rebuild the page for every plot swiped to.
          if (mapEquals(_rowErrors[plot.id] ?? const <int, String>{}, byRow)) {
            return;
          }
          setState(() => _rowErrors[plot.id] = byRow);
        },
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
    final String plot = notebook.plots[index].id;
    if (index == activeIndex) _revealActiveRow(plot, rows);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      // A hairline of air between rows, so the stack reads as a list of
      // separate expressions rather than one run-on block.
      spacing: _rowGap,
      children: <Widget>[
        for (int r = 0; r < rows.length; r++)
          // The third row says where it ends, which is how tall the panel may
          // grow (see [_threeRowsHeight]). From three rows rather than four,
          // so the height is known when the fourth arrives and the panel
          // never grows past it on the way.
          if (r == _visibleRows - 1)
            LayoutReporter(
              rootKey: _rowPanelKeys.putIfAbsent(plot, () => GlobalKey()),
              version: (plot, rows[r].id),
              report:
                  (Rect rect, RenderObject? _) => _noteThreeRowsHeight(
                    plot,
                    rect.bottom,
                    capped: rows.length > _visibleRows,
                  ),
              child: _buildRow(index, rows, r),
            )
          else
            _buildRow(index, rows, r),
      ],
    );
  }

  /// One expression row: its swatch, its editor and its eye.
  ///
  /// Keyed by the row's own [ExpressionRow.rowKey], not its position, so
  /// Flutter reuses the right element when a row is inserted above or removed.
  Widget _buildRow(int index, List<ExpressionRow> rows, int r) {
    // A row giving a letter its value draws nothing, so it has no curve to
    // colour or hide.
    final String? defines = PlotDefinitions.nameDefinedBy(
      rows[r].controller.expression,
    );
    return KeyedSubtree(
      key: rows[r].rowKey,
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
          _rowSwatch(index, rows[r], r, defines: defines),
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
                        // Touching an expression means typing into it,
                        // so a folded keypad comes back — as a phone's
                        // keyboard rises when a field is tapped. Left
                        // folded, the caret would blink with no keys.
                        _setKeypadHidden(false);
                      },
                    ),
                  ),
            ),
          ),
          // Its space kept, so the expression does not shift sideways as a
          // row becomes a value or stops being one.
          Visibility(
            visible: defines == null,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _rowEye(rows[r]),
          ),
        ],
      ),
    );
  }

  /// How many rows the panel shows before it scrolls.
  ///
  /// Every row it shows is height taken from the plot above it, so past three
  /// the stack scrolls rather than growing.
  static const int _visibleRows = 3;

  /// How tall the first three rows of each plot stand, for plots with three
  /// or more.
  ///
  /// Measured, because rows are not one height — a fraction or an integral is
  /// several times a plain expression — so "three rows" is the third row's
  /// bottom edge, reported where it is painted.
  final Map<String, double> _threeRowsHeight = <String, double>{};

  void _noteThreeRowsHeight(
    String plot,
    double height, {
    required bool capped,
  }) {
    if (((_threeRowsHeight[plot] ?? -1) - height).abs() < 0.5) return;
    // With three rows nothing is held to it yet: it is kept for the fourth,
    // whose arrival rebuilds anyway.
    if (!capped) {
      _threeRowsHeight[plot] = height;
      return;
    }
    // Reported from paint, so the rebuild waits for the frame to finish.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _threeRowsHeight[plot] = height);
    });
  }

  /// The height the row panel may take: all of its rows up to three, the
  /// first three past that.
  double? _rowPanelCap(int index) {
    if (rowsOf(index).length <= _visibleRows) return null;
    return _threeRowsHeight[notebook.plots[index].id];
  }

  /// The row of each plot last brought into view.
  final Map<String, String> _revealedRow = <String, String>{};

  /// Scroll the panel to the row being typed into when that row changes.
  ///
  /// A row added past the third would otherwise arrive below the panel's
  /// edge, and the keys would type into something out of sight. Only the
  /// panel scrolls: the row is revealed by its own key, outside its
  /// expression's horizontal scroller.
  void _revealActiveRow(String plot, List<ExpressionRow> rows) {
    final ExpressionRow row = rows[activeRow.clamp(0, rows.length - 1)];
    if (_revealedRow[plot] == row.id) return;
    _revealedRow[plot] = row.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? target = row.rowKey.currentContext;
      if (!mounted || target == null) return;
      // One of the two moves, whichever side of the panel the row is past;
      // the other finds nothing to do.
      for (final ScrollPositionAlignmentPolicy policy in const <ScrollPositionAlignmentPolicy>[
        ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ]) {
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: policy,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// How tall each plot's row panel is, measured rather than guessed.
  ///
  /// The plot's controls have to clear the rows floating over them, and rows
  /// are not a fixed height — a fraction or an integral is several times a
  /// plain expression. So the panel is measured after it lays out and the plot
  /// is told, rather than the height being computed from a row count.
  final Map<String, double> _rowPanelHeight = <String, double>{};
  final Map<String, GlobalKey> _rowPanelKeys = <String, GlobalKey>{};

  /// Read the row panel's height back after layout, and rebuild if it moved.
  final Set<String> _measurePending = <String>{};

  void _measureRowPanel(int index) {
    final String plot = notebook.plots[index].id;
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

  /// How much of the plot the row panel covers: its measured height, or the
  /// three rows it shows when it holds more.
  double _visibleRowPanelHeight(int index) {
    final double measured = _rowPanelHeight[notebook.plots[index].id] ?? 0;
    final double? cap = _rowPanelCap(index);
    return cap == null ? measured : min(measured, cap + 2 * _rowInset);
  }

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
      palette: settings.plotPalette,
    );
  }

  /// Whether the interface is laid out for a left hand.
  ///
  /// The same setting that mirrors the keypad. Anything with a leading and a
  /// trailing side follows it — see the handedness note in memory.
  bool get _leftHanded =>
      Provider.of<SettingsProvider>(context).handedness ==
      Handedness.leftHanded;

  /// Which rows of which plot could not be drawn, and why.
  final Map<String, Map<int, String>> _rowErrors =
      <String, Map<int, String>>{};

  /// The colour a row's curve is drawn in.
  ///
  /// Reads the same palette entry the painters do, by row number, so the dot
  /// and the curve cannot disagree. Tapping it moves the caret to that row,
  /// which makes the whole left edge a way of choosing what to edit.
  ///
  /// [defines] is the letter the row gives a value to, when it gives one.
  Widget _rowSwatch(
    int plot,
    ExpressionRow row,
    int r, {
    required String? defines,
  }) {
    final Color colour = _rowTheme.seriesColor(r);
    final String? trouble = _rowErrors[notebook.plots[plot].id]?[r];
    void choose() {
      if (activeIndex != plot || activeRow != r) {
        setState(() {
          activeIndex = plot;
          activeRow = r;
        });
      }
    }

    // A row that cannot be drawn says so on its own dot. The banner over the
    // plot names the first problem but not the line it belongs to, which with
    // several rows stacked is the half you need.
    if (trouble != null) {
      return GestureDetector(
        onTap: choose,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tooltip(
            message: trouble,
            child: Icon(
              Icons.error_outline,
              size: 13,
              color: _rowTheme.errorMark,
            ),
          ),
        ),
      );
    }

    // A row giving a letter its value draws no curve, so it wears no colour:
    // a dot would promise a line that is not there. It wears the mark of
    // what it is for instead — a value to tune.
    if (defines != null) {
      return GestureDetector(
        onTap: choose,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tooltip(
            message:
                'Gives $defines its value. '
                'Long-press the number and drag to tune it.',
            child: Icon(Icons.tune, size: 13, color: _rowTheme.controlIdle),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: choose,
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
                      final double room =
                          constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : 260;
                      final double? cap = _rowPanelCap(index);
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                          // Three rows at most; the rest scroll.
                          maxHeight: cap == null ? room : min(room, cap),
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
                              notebook.plots[index].id,
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
      ],
    );
  }

  @override
  void dispose() {
    _pageViewController.dispose();
    _keypadReveal.dispose();
    _deleteTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveCells();

    _walkthroughService.removeListener(_onWalkthroughChanged);
    _walkthroughService.dispose();

    // Every row of every plot.
    notebook.dispose();

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

    notebook.restore(savedCells, savedIndex);

    // Build the controller before the PageView first appears, so it opens on
    // the restored cell rather than jumping there afterwards.
    _pageViewController.dispose();
    _pageViewController = PageController(initialPage: activeIndex);

    setState(() => _isLoading = false);

    // Baseline the undo history at the state the app opened with. Without
    // this the first edit is what establishes the baseline, so the very first
    // thing a user types has nothing to undo back to.
    notebook.markHistory();
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
    // The live view where a plot's panel is on screen; a plot not built this
    // session keeps the view it was restored with, so paging away from a plot
    // does not forget where it was left.
    for (final Plot plot in notebook.plots) {
      final PlotViewState? live =
          _plotPanelKeys[plot.id]?.currentState?.currentView();
      if (live != null) plot.view = live;
    }
    final saved = notebook.toSaved();
    await CellPersistence.saveRows(
      saved.rows,
      saved.hidden,
      saved.views,
      activeIndex: saved.activeIndex,
    );
  }

  void _onSettingsChanged() {
    // The built plot themes are keyed on the palette, the colour mode and the
    // theme type. That covers the settings they derive from, but clearing here
    // means a palette that changes in some other way cannot leave a stale
    // theme behind.
    PlotThemeData.clearCache();

    updateMathEditor();

    for (final controller in allControllers) {
      controller.refreshDisplay();
    }

    setState(() {});
  }

  /// A row's editor changed its expression outside [updateMathEditor] — a
  /// paste, an undo inside the editor, a drag-to-tune.
  ///
  /// This used to cascade: re-evaluate the cell exactly, then every later cell
  /// that might reference it through `ans`. Nothing has shown those results
  /// since the result display was removed, and the ANS key went with it, so
  /// all that is left is to bring the plot up to date.
  void _onRowResultChanged(int plot) {
    // [updateMathEditor] recalculates every row and rebuilds once at the end.
    if (_isUpdating) return;
    setState(() {});
  }

  void _clearAllSelectionOverlays() {
    for (final key in notebook.allRows.map((ExpressionRow r) => r.editorKey)) {
      key.currentState?.clearOverlay();
    }
  }

  /// Auto-scroll to the end when expression fills the screen
  /// Only scrolls when cursor is at the end of the expression (not when editing in middle)
  void _autoScrollToEnd(int index) {
    final scrollController = activeRowOf(index)?.scroll;
    final mathController = activeRowOf(index)?.controller;
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

  /// Add an empty plot, after the open one unless told where, and open it.
  void addPlot({int? at}) {
    notebook.insertPlot(at: at);
    final int index = activeIndex;
    setState(() {});

    // Slide to the page that was just created rather than snapping to it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageViewController.hasClients) {
        _pageViewController.animateToPage(
          index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// Remove the plot at [index]; the last one stays.
  void removePlot(int index) {
    if (!notebook.removePlotAt(index)) return;
    _forgetGonePlots();
    setState(() {});
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
        _plotPanelKeys[notebook.activePlot.id]?.currentState;
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
    notebook.saveForUndo();
    notebook.clear();
    _forgetGonePlots();
    setState(() {});
  }

  /// Check if app-level undo is available
  bool get canUndoAppState => notebook.canUndo;

  /// Check if app-level redo is available
  bool get canRedoAppState => notebook.canRedo;

  /// Undo the last change to the plots: an edit, a row or plot added or
  /// removed, a clear.
  void undoAppState() => notebook.undo(refresh: _afterHistoryApplied);

  /// Redo what undo took back.
  void redoAppState() => notebook.redo(refresh: _afterHistoryApplied);

  /// Bring the screen up to the plots an undo or redo restored.
  void _afterHistoryApplied() {
    _forgetGonePlots();
    setState(() {});
    updateMathEditor();
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
            // A plain colour, not a picture: the plot fills the page and
            // covers it anyway. The wallpaper SVGs this replaced cost
            // 250-300 ms to build the first time, and are gone.
            Positioned.fill(child: ColoredBox(color: colors.displayBackground)),
            // Light across the ground.
            //
            // One wash for every theme, one number to tune. Black at the rim
            // and white at the lit point, both at low alpha, so a dark theme
            // deepens and a light one is shaded rather than washed out.
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
                      itemCount: count,
                      onPageChanged: (position) {
                        if (position >= 0 && position < count) {
                          _captureView(_currentPageIndex);
                          setState(() => activeIndex = position);
                        }
                      },
                      itemBuilder: (context, position) {
                        if (position >= count) {
                          return const SizedBox.shrink();
                        }
                        return _buildExpressionDisplay(position, colors);
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
                  _buildKeypadHandle(colors),
                  // Folding, not removing: the keypad stays built while it is
                  // away, so it comes back on the page it was left on. Aligned
                  // to its top, so as the box shrinks from above the keys ride
                  // down with it and slide off rather than being cropped in
                  // place.
                  SizeTransition(
                    sizeFactor: _keypadRevealCurve,
                    axisAlignment: -1,
                    child: IgnorePointer(
                      ignoring: _keypadHidden,
                      child: ExcludeSemantics(
                        excluding: _keypadHidden,
                        child: _buildKeypad(colors),
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

  /// The keypad, below its handle.
  Widget _buildKeypad(AppColors colors) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      // Inside the AnimatedSize, so the guard sits directly above the keypad's
      // own Column — the box that was reported with no size. See
      // [LaidOutSubtree].
      child: LaidOutSubtree(
        child: Builder(
          builder: (context) {
            final mediaQuery = MediaQuery.of(context);
            double screenWidth = mediaQuery.size.width;
            bool isLandscape = mediaQuery.orientation == Orientation.landscape;

            return CalculatorKeypad(
              screenWidth: screenWidth,
              isLandscape: isLandscape,
              colors: colors,
              activeIndex: activeIndex,
              activeController: activeRowOf(activeIndex)?.controller,
              settingsProvider: _settingsProvider!,
              onUpdateMathEditor: updateMathEditor,
              // The action key adds a row to this plot; the
              // swipe strip still adds a whole plot.
              onAddDisplay: addRow,
              // Backspace on an empty row removes that row.
              // Only when it is the last one left does the
              // whole plot go, which is what it did before.
              onRemoveDisplay: (int plot) {
                if (!removeActiveRow()) removePlot(plot);
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
    );
  }

  void updateMathEditor() {
    if (_isUpdating) return;
    _isUpdating = true;

    try {
      for (int i = 0; i < count; i++) {
        final MathEditorController? controller = activeRowOf(i)?.controller;
        controller?.onCalculate();
      }
    } finally {
      _isUpdating = false;
    }

    // Every edit reaches here, so this is where an undo point is taken.
    notebook.recordHistoryPoint();

    setState(() {});
    _scheduleSave();
  }
}
