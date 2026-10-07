import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:klotter/help.dart';
import 'package:klotter/utils/utils.dart';
import 'buttons.dart';
import 'popup_menu_button.dart';
import '../settings/settings.dart';
import '../settings/settings_provider.dart';
import '../utils/app_colors.dart';
import '../utils/coordinate_system.dart';
import 'dart:async';
import '../walkthrough/walkthrough_service.dart';
import '../walkthrough/walkthrough_steps.dart';
import '../math_renderer/math_editor_controller.dart';
import '../math_renderer/selection_wrapper.dart';
import '../math_renderer/math_text_style.dart';

/// Custom ScrollPhysics that restricts swipe direction
class DirectionalScrollPhysics extends ScrollPhysics {
  final bool allowLeftSwipe;
  final bool allowRightSwipe;

  const DirectionalScrollPhysics({
    super.parent,
    this.allowLeftSwipe = true,
    this.allowRightSwipe = true,
  });

  @override
  DirectionalScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DirectionalScrollPhysics(
      parent: buildParent(ancestor),
      allowLeftSwipe: allowLeftSwipe,
      allowRightSwipe: allowRightSwipe,
    );
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // value > position.pixels means scrolling left (moving to higher index)
    // value < position.pixels means scrolling right (moving to lower index)

    if (!allowLeftSwipe && value > position.pixels) {
      // Trying to swipe left but not allowed - prevent it
      return value - position.pixels;
    }

    if (!allowRightSwipe && value < position.pixels) {
      // Trying to swipe right but not allowed - prevent it
      return value - position.pixels;
    }

    return super.applyBoundaryConditions(position, value);
  }
}

class CalculatorKeypad extends StatefulWidget {
  final double screenWidth;
  final bool isLandscape;
  final AppColors colors;
  final int activeIndex;

  /// The editor every key types into.
  ///
  /// Handed in already resolved, rather than the keypad reaching into a map by
  /// index. Which editor is current is the host's business and is about to stop
  /// being a single index at all — a plot will own several expression rows —
  /// and the keypad has no stake in that. It only ever wanted one controller.
  final MathEditorController? activeController;
  final SettingsProvider settingsProvider;
  final VoidCallback onUpdateMathEditor;
  final VoidCallback onAddDisplay;
  final void Function(int index) onRemoveDisplay;
  final VoidCallback onClearAllDisplays;
  final VoidCallback onSetState;

  // Walkthrough parameters
  final WalkthroughService walkthroughService;
  final GlobalKey scientificKeypadKey;
  final GlobalKey numberKeypadKey;
  final GlobalKey extrasKeypadKey;
  final GlobalKey commandButtonKey;
  final GlobalKey mainKeypadAreaKey;

  /// Where each block of the tablet keypad sits, for the walkthrough to point
  /// at. Null on a phone, where the blocks are separate pages instead.
  final GlobalKey? numberBlockKey;
  final GlobalKey? scientificBlockKey;
  final GlobalKey? extrasBlockKey;
  final GlobalKey settingsButtonKey;

  final VoidCallback? onClearSelectionOverlay;

  final bool canUndoAppState;
  final bool canRedoAppState;
  final VoidCallback? onUndoAppState;
  final VoidCallback? onRedoAppState;

  /// Save the plot of the cell being edited to a file.
  final VoidCallback? onExportPlot;

  /// Which system the three variable keys are showing.
  ///
  /// Held by the owner rather than the keypad because the plot has to know it
  /// too: an expression in ρ and θ is drawn by converting the sample point,
  /// so the renderer needs the same answer the keys are giving.
  final CoordinateSystem variableSystem;

  /// Which system the three unit-vector keys are showing. Independent of
  /// [variableSystem] — r̂ alongside x and y is a normal thing to write.
  final CoordinateSystem unitVectorSystem;

  final ValueChanged<CoordinateSystem>? onVariableSystemChanged;
  final ValueChanged<CoordinateSystem>? onUnitVectorSystemChanged;

  const CalculatorKeypad({
    super.key,
    required this.screenWidth,
    required this.isLandscape,
    required this.colors,
    required this.activeIndex,
    required this.activeController,
    required this.settingsProvider,
    required this.onUpdateMathEditor,
    required this.onAddDisplay,
    required this.onRemoveDisplay,
    required this.onClearAllDisplays,
    required this.onSetState,
    required this.walkthroughService,
    required this.scientificKeypadKey,
    required this.numberKeypadKey,
    required this.extrasKeypadKey,
    required this.commandButtonKey,
    required this.mainKeypadAreaKey,
    this.numberBlockKey,
    this.scientificBlockKey,
    this.extrasBlockKey,
    required this.settingsButtonKey,
    this.onClearSelectionOverlay,
    this.canUndoAppState = false,
    this.canRedoAppState = false,
    this.onUndoAppState,
    this.onRedoAppState,
    this.onExportPlot,
    this.variableSystem = CoordinateSystem.cartesian,
    this.unitVectorSystem = CoordinateSystem.cartesian,
    this.onVariableSystemChanged,
    this.onUnitVectorSystemChanged,
  });

  @override
  State<CalculatorKeypad> createState() => _CalculatorKeypadState();
}

class _CalculatorKeypadState extends State<CalculatorKeypad> {
  // ---- klotter phone keypad ---------------------------------------------
  // Two halves side by side, each a 5 x 4 grid: the number pad fixed on one
  // side, the function pages swiping on the other. Ten keys across and four
  // down, so the keys are the size they always were and the keypad takes the
  // same height — only what is where has changed.
  //
  // It was 10 x 2 halves stacked: two rows of functions over two rows of
  // numbers, the digits laid 5 6 7 8 9 over 0 1 2 3 4. That reads in neither
  // calculator order nor keyboard order, and the user found it unnatural. A
  // block of digits is the arrangement everyone already knows, so the numbers
  // went back to one, and the functions took the space beside it.
  //
  // At 10 columns a 360dp phone gives 36dp-wide keys, under the 48dp Material
  // minimum, so keys are made taller than wide (0.75) with a hard 48dp floor —
  // the same geometry a phone QWERTY uses. Unlike a keyboard a calculator has
  // no autocorrect, so a mis-tap is a wrong answer nobody notices.
  //
  // Tablets keep their own single grid; see below.
  static const int _phoneGridColumns = 5;

  /// The room either side of a label inside a phone key: half a dp, against
  /// the 2 dp a key leaves elsewhere (see [keyLabelPadding]). The glyphs keep
  /// their own side bearings, so even a label filling its key does not touch
  /// the edge — and the 3 dp it gives back is what lets cos and tan be drawn
  /// at full size.
  static const double _phoneLabelPadding = 0.5;
  static const int _phoneGridRows = 4;
  static const double _phonePortraitTileAspect = 0.75;
  static const double _minPhoneTileHeight = 48.0;

  /// The fixed number pad, as seen by a right-hander.
  ///
  /// A calculator's block: 7 8 9 on top, 0 beside the point. The operators are
  /// klator's two-by-two — + beside −, × beside ÷, each over its inverse's
  /// partner. Backspace takes the top corner and the action key the bottom
  /// one, where Enter belongs.
  ///
  /// Clear is kept away from backspace, beside the action key at the foot:
  /// the two are reached for in the same breath, and a thumb going for
  /// backspace that lands one key short should cost a character, not the
  /// whole expression. The user laid it out that way on purpose.
  static const List<List<String>> _phoneNumberGrid = <List<String>>[
    <String>['num.7', 'num.8', 'num.9', 'num.paren', 'num.back'],
    <String>['num.4', 'num.5', 'num.6', 'num.plus', 'num.minus'],
    <String>['num.1', 'num.2', 'num.3', 'num.times', 'num.div'],
    <String>['num.0', 'num.dot', 'num.exp', 'num.ce', 'num.cmd'],
  ];

  /// The scientific page, five keys across and four down.
  ///
  /// Every key sits over its relative, as it did when the page was two long
  /// rows: each variable over its unit vector, each trig function over its
  /// inverse, = over ≥, x² over √, π over e. What builds an expression is the
  /// top half; what is applied to it, the bottom.
  static const List<List<String>> _phoneScientificPage = <List<String>>[
    <String>['sci.x', 'sci.y', 'sci.z', 'sci.eq', 'sci.sq'],
    <String>['sci.xhat', 'sci.yhat', 'sci.zhat', 'sci.geq', 'sci.root'],
    <String>['sci.sin', 'sci.cos', 'sci.tan', 'sci.pi', 'sci.log'],
    <String>['sci.asin', 'sci.acos', 'sci.atan', 'sci.e', 'sci.deg'],
  ];

  /// The extras page: the old two rows' left halves over their right halves,
  /// so every pair still shares a column.
  ///
  /// Values and the operators on them across the top. Below them, the
  /// whole-document keys — clear-all, undo, redo, export, help, settings — as
  /// one block on the outer edge, settings in the very corner: the far left
  /// for a right-hander, where a tablet has it too, and away from the thumb
  /// that is on the numbers. The discrete and calculus keys take the columns
  /// nearest the numbers, since they are reached far more often.
  static const List<List<String>> _phoneExtrasPage = <List<String>>[
    <String>['ext.sin', 'ext.i', 'ext.u', 'ext.sq', 'ext.fact'],
    <String>['ext.asin', 'ext.pi', 'ext.v', 'ext.root', 'ext.abs'],
    <String>['ext.clear', 'ext.undo', 'ext.redo', 'ext.npr', 'ext.deriv'],
    <String>['ext.settings', 'ext.export', 'ext.help', 'ext.sum', 'ext.int'],
  ];

  /// [grid], each row reflected for a left-hander.
  ///
  /// A left-hander's phone keypad is the right-hander's in a mirror, as a
  /// tablet's is: the halves trade sides and every row of every page is
  /// reflected. Reflected rather than moved, so whatever sat nearest the
  /// dominant thumb still does, and what was kept out of its way — settings
  /// and clear-all, backspace and the action key on the outer edge — still
  /// is, on the other side.
  List<List<String>> _handed(List<List<String>> grid) =>
      _leftHanded
          ? <List<String>>[
            for (final List<String> r in grid) r.reversed.toList(),
          ]
          : grid;
  // -----------------------------------------------------------------------

  bool get _isTabletLayout => widget.isLandscape || widget.screenWidth > 600;

  /// The width to lay the keys out in, given what the parent offered.
  ///
  /// The parent does not always offer a finite one. On the warm-up frame the
  /// keypad is laid out inside an offstage overlay with unbounded width, and
  /// dividing infinity by the column count gives an infinite cell; dividing
  /// that by an aspect ratio derived from the same infinity gives NaN. A NaN
  /// height reaches SizedBox as `NaN<=h<=NaN`, which is where the launch threw
  /// — and every "not laid out" and "!_debugDoingThisLayout" after it was
  /// fallout from that one box.
  ///
  /// The widget is told the screen width, so there is a real answer to fall
  /// back to rather than a guess.
  double _usableWidth(BoxConstraints constraints) {
    final double offered = constraints.maxWidth;
    if (offered.isFinite && offered > 0) return offered;
    return widget.screenWidth > 0 ? widget.screenWidth : 0;
  }

  /// How many keypad pages share the width. Derived from the configuration, so
  /// it is known before the first build and needs no frame to settle.
  int get _pagesPerView => _isTabletLayout ? 2 : 1;

  // ---- tablet keypad ----------------------------------------------------
  // A tablet has room for every key at once, so it drops the phone's
  // fixed/swipeable split: one grid, three 20-key blocks left to right —
  // extras (with settings), scientific, then numbers and basic operators
  // nearest the right hand.
  //
  // 4x15 gives each block 5 columns and fills exactly. The 3-row option is
  // 3x21, not 3x20: three 20-key blocks cannot tile 20 columns, since each
  // needs ceil(20 / 3) = 7, leaving one spare cell per block.
  /// Landscape gets 3 rows, portrait 4 — derived from the orientation rather
  /// than offered as a choice, since the shape that fits is not really a
  /// preference.
  int get _tabletRows => widget.isLandscape ? 3 : 4;

  /// Total columns: 3x20 landscape, 4x15 portrait.
  int get _tabletColumns => widget.isLandscape ? 20 : 15;

  bool get _leftHanded =>
      widget.settingsProvider.handedness == Handedness.leftHanded;

  // ---- tablet key map -----------------------------------------------------
  //
  // Each orientation is authored as the grid you actually see: one name per
  // cell, null for a deliberate gap. Keys are placed by name, so a key that is
  // never placed is a failing test rather than a key that quietly disappears --
  // which is what happened to export, whose index no table happened to mention.
  //
  // Names are prefixed because the three blocks genuinely share labels: there
  // is a scientific root and an extras root, a scientific x and an extras x.

  /// Names for `_scientificButtons()`, in the order it builds them.
  static const List<String> _sciNames = <String>[
    'sci.x',
    'sci.y',
    'sci.z',
    'sci.sin',
    'sci.cos',
    'sci.tan',
    'sci.eq',
    'sci.sq',
    'sci.pi',
    'sci.log',
    'sci.xhat',
    'sci.yhat',
    'sci.zhat',
    'sci.asin',
    'sci.acos',
    'sci.atan',
    'sci.geq',
    'sci.root',
    'sci.e',
    'sci.deg',
  ];

  /// Names for `_extrasButtons()`, in the order it builds them.
  ///
  /// Kept in step by hand, so the test that each name is the key it says is
  /// what holds it there. It had drifted: the builder put sin first and these
  /// still began with i, so on a tablet the slot authored for i showed sin,
  /// the one for x² showed u, and so on round four keys of each row.
  static const List<String> _extNames = <String>[
    'ext.sin',
    'ext.i',
    'ext.u',
    'ext.sq',
    'ext.fact',
    'ext.npr',
    'ext.deriv',
    'ext.undo',
    'ext.redo',
    'ext.clear',
    'ext.asin',
    'ext.pi',
    'ext.v',
    'ext.root',
    'ext.abs',
    'ext.sum',
    'ext.int',
    'ext.export',
    'ext.help',
    'ext.settings',
  ];

  /// Names for `_numberButtonAt(0..19)`.
  static const List<String> _numNames = <String>[
    'num.7',
    'num.8',
    'num.9',
    'num.paren',
    'num.back',
    'num.4',
    'num.5',
    'num.6',
    'num.plus',
    'num.minus',
    'num.1',
    'num.2',
    'num.3',
    'num.times',
    'num.div',
    'num.0',
    'num.dot',
    'num.exp',
    'num.ce',
    'num.cmd',
  ];

  /// Every key a tablet shows, by name. Exposed for the test that checks each
  /// one is placed exactly once in each orientation.
  static List<String> get tabletKeyNames => <String>[
    ..._extNames,
    ..._sciNames,
    ..._numNames,
  ];

  /// 3 rows x 20. Columns 0-6 are extras, the middle is scientific, and the
  /// numbers sit under the right hand.
  ///
  /// Variables and unit vectors run down columns 7 and 8, with each trig
  /// family in its own column beside them. Equals and its inequality take
  /// column 6, which only rows 1 and 2 reach. The four arithmetic operators
  /// form a 2x2 block at columns 17-18, which is what swapping the times key
  /// with E buys.
  static const List<List<String?>> _tabletLandscapeGrid = <List<String?>>[
    <String?>[
      'ext.clear',
      'ext.i',
      'ext.pi',
      'ext.root',
      'ext.sq',
      'ext.abs',
      'ext.sin',
      'sci.xhat',
      'sci.x',
      'sci.sin',
      'sci.asin',
      'sci.sq',
      'sci.e',
      'num.7',
      'num.8',
      'num.9',
      'num.paren',
      'num.plus',
      'num.minus',
      'num.back',
    ],
    <String?>[
      'ext.undo',
      'ext.redo',
      'ext.asin',
      'ext.fact',
      'ext.npr',
      'ext.u',
      'sci.eq',
      'sci.yhat',
      'sci.y',
      'sci.cos',
      'sci.acos',
      'sci.root',
      'sci.log',
      'num.4',
      'num.5',
      'num.6',
      'num.exp',
      'num.div',
      'num.times',
      'num.ce',
    ],
    <String?>[
      'ext.settings',
      'ext.help',
      'ext.deriv',
      'ext.sum',
      'ext.int',
      'ext.v',
      'sci.geq',
      'sci.zhat',
      'sci.z',
      'sci.tan',
      'sci.atan',
      'sci.pi',
      'sci.deg',
      'num.1',
      'num.2',
      'num.3',
      'num.0',
      'num.dot',
      'ext.export',
      'num.cmd',
    ],
  ];

  /// 4 rows x 15, five columns per block.
  static const List<List<String?>> _tabletPortraitGrid = <List<String?>>[
    <String?>[
      'ext.clear',
      'ext.i',
      'ext.pi',
      'ext.root',
      'ext.u',
      'sci.x',
      'sci.y',
      'sci.z',
      'sci.eq',
      'sci.sq',
      'num.7',
      'num.8',
      'num.9',
      'num.paren',
      'num.back',
    ],
    <String?>[
      'ext.undo',
      'ext.abs',
      'ext.sin',
      'ext.asin',
      'ext.v',
      'sci.xhat',
      'sci.yhat',
      'sci.zhat',
      'sci.geq',
      'sci.root',
      'num.4',
      'num.5',
      'num.6',
      'num.plus',
      'num.minus',
    ],
    <String?>[
      'ext.redo',
      'ext.export',
      'ext.npr',
      'ext.deriv',
      'ext.sq',
      'sci.sin',
      'sci.cos',
      'sci.tan',
      'sci.pi',
      'sci.log',
      'num.1',
      'num.2',
      'num.3',
      'num.times',
      'num.div',
    ],
    <String?>[
      'ext.settings',
      'ext.help',
      'ext.int',
      'ext.sum',
      'ext.fact',
      'sci.asin',
      'sci.acos',
      'sci.atan',
      'sci.e',
      'sci.deg',
      'num.0',
      'num.dot',
      'num.exp',
      'num.ce',
      'num.cmd',
    ],
  ];

  List<List<String?>> get _tabletGrid =>
      widget.isLandscape ? _tabletLandscapeGrid : _tabletPortraitGrid;

  /// The columns one block of the tablet keypad occupies, for the walkthrough
  /// to point at.
  ///
  /// Read off the grid rather than written down, so a rearranged keypad keeps
  /// its highlights — but by a majority vote per column, not by the outermost
  /// key carrying the prefix. The blocks are not clean rectangles: landscape
  /// puts `ext.export` at column 18, deep inside the number keys, so a
  /// min-to-max span would stretch the extras block across the whole keypad
  /// and overlap the other two. A column belongs to whichever block holds most
  /// of it, and the answer is contiguous in both grids.
  ///
  /// Columns are counted left to right as drawn, so a left-handed layout —
  /// which is the grid reflected — reports the mirrored span.
  ({int first, int last})? _tabletBlockColumns(
    List<List<String?>> grid,
    String prefix,
  ) {
    int lo = _tabletColumns, hi = -1;
    for (int c = 0; c < _tabletColumns; c++) {
      final Map<String, int> votes = <String, int>{};
      for (final List<String?> row in grid) {
        if (c >= row.length) continue;
        final String? name = row[c];
        if (name == null) continue;
        final int dot = name.indexOf('.');
        if (dot < 0) continue;
        final String block = name.substring(0, dot + 1);
        votes[block] = (votes[block] ?? 0) + 1;
      }
      if (votes.isEmpty) continue;
      final String winner =
          votes.entries.reduce((a, b) => b.value > a.value ? b : a).key;
      if (winner != prefix) continue;
      final int col = _leftHanded ? _tabletColumns - 1 - c : c;
      if (col < lo) lo = col;
      if (col > hi) hi = col;
    }
    return hi < 0 ? null : (first: lo, last: hi);
  }

  List<Widget> _mirrorWidgetRows(List<Widget> items, int columns) {
    final List<Widget> out = <Widget>[];
    for (int start = 0; start < items.length; start += columns) {
      final int stop = math.min(start + columns, items.length);
      out.addAll(items.sublist(start, stop).reversed);
    }
    return out;
  }

  /// childAspectRatio for the main grids (width / height).
  ///
  /// Takes the width the grid will actually be laid out at, not
  /// `widget.screenWidth`. On phones the ratio depends on width (because of the
  /// 48dp floor), so deriving it from a different width than the grid receives
  /// would size the container and the tiles inconsistently and clip a row.
  double _gridAspectRatioFor(double availableWidth) {
    // Nothing sane can be derived from a width of zero, and the answer must
    // never be zero itself: the callers divide by it, so a zero ratio turns a
    // zero cell into 0/0 — a NaN height, which reaches SizedBox as
    // `NaN<=h<=NaN` and brings the launch down. The window really is 0x0 on
    // the warm-up frame ("Width is zero" from the engine), so this is the
    // ordinary case at startup, not a defensive flourish. It is also passed
    // straight to GridView as childAspectRatio, where zero is just as invalid.
    if (!availableWidth.isFinite || availableWidth <= 0) return 1.0;
    // [availableWidth] is one half of the phone keypad, five keys across.
    // Tablets use the same grid in both orientations, so the keys keep the
    // same shape too — landscape simply makes them bigger, because each block
    // gets a third of a wider screen.
    if (_isTabletLayout) return 1.0;
    if (widget.isLandscape) return 1.5;
    final double tileWidth = availableWidth / _phoneGridColumns;
    final double tileHeight = math.max(
      _minPhoneTileHeight,
      tileWidth / _phonePortraitTileAspect,
    );
    final double ratio = tileWidth / tileHeight;
    return ratio.isFinite && ratio > 0 ? ratio : 1.0;
  }
  // -----------------------------------------------------------------------

  int? _lastPagesPerView;

  PageController? _keypadController;

  Timer? _deleteTimer;
  bool _isDeleting = false;
  int _deleteSpeed = 150;
  bool _deletedContentInCurrentBackspaceSession = false;

  /// How many pages the function keys swipe through: scientific (0) and
  /// extras (1).
  static const int _keypadPageCount = 2;

  /// The pages wrap: a swipe past either end comes round to the other (see
  /// [EasySnapPageView.wrap]). So the controller counts pages without end,
  /// and starts this many turns in to leave room both ways — a thousand
  /// turns of swiping in one direction before it would run out.
  static const int _wrapTurns = 1000;

  /// The controller's own page: the page showing, plus however many whole
  /// turns the swipes have made — so the page showing is this modulo
  /// [_keypadPageCount]. It keeps counting the way the swipes went, which is
  /// what says which way a swipe was; the page alone cannot, since the
  /// extras are both one to the left and one to the right of the scientific
  /// keys.
  ///
  /// Starts on the first page. It once started at 1 — the number pad's index
  /// back when the number pad was a page — which now names the extras.
  int _keypadVirtualPage = _keypadPageCount * _wrapTurns;

  bool _isNavigatingProgrammatically = false;

  // Button lists
  final List<String> _buttons = [
    '7',
    '8',
    '9',
    '()',
    '<-',
    '4',
    '5',
    '6',
    '+',
    '-',
    '1',
    '2',
    '3',
    'x',
    '/',
    '0',
    '.',
    '\u1D07',
    'CE',
    'EN',
  ];

  @override
  void initState() {
    super.initState();
    _initializeKeypadController(_pagesPerView);
    _lastPagesPerView = _pagesPerView;
    widget.walkthroughService.onResetKeypad = _resetToFirstKeypadPage;
    widget.walkthroughService.onNavigateToKeypadPage = _navigateToKeypadPage;
  }

  @override
  void dispose() {
    _deleteTimer?.cancel();
    _keypadController?.dispose();
    widget.walkthroughService.onResetKeypad = null;
    widget.walkthroughService.onNavigateToKeypadPage = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CalculatorKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rotation or a resize changes how many pages share the width. Done here
    // rather than in build: this runs before the subtree rebuilds, so the new
    // controller is in place by the time the PageView asks for it, and nothing
    // is marked dirty while something else is building.
    if (_pagesPerView != _lastPagesPerView) {
      _initializeKeypadController(_pagesPerView);
      _lastPagesPerView = _pagesPerView;
    }
    if (widget.walkthroughService != oldWidget.walkthroughService) {
      oldWidget.walkthroughService.onResetKeypad = null;
      oldWidget.walkthroughService.onNavigateToKeypadPage = null;
      widget.walkthroughService.onResetKeypad = _resetToFirstKeypadPage;
      widget.walkthroughService.onNavigateToKeypadPage = _navigateToKeypadPage;
    }
  }

  /// Navigate keypad to a specific page (used by walkthrough back button)
  void _navigateToKeypadPage(int page) {
    if (_keypadController != null && _keypadController!.hasClients) {
      // Set flag to bypass directional physics during programmatic navigation
      setState(() {
        _isNavigatingProgrammatically = true;
      });

      _keypadController!
          .animateToPage(
            _virtualPageFor(page),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          )
          .then((_) {
            // Reset flag after animation completes
            if (mounted) {
              setState(() {
                _isNavigatingProgrammatically = false;
              });
            }
          });
    } else {
      debugPrint('Could not navigate - controller null or no clients');
    }
  }

  /// Puts the swipeable rows back on their first page, which is scientific.
  ///
  /// This sent a phone to page 1 and was named for a layout that no longer
  /// exists: the number pad used to be a page of its own, and page 1 was how
  /// you reached it. The number pad is permanent now and the pages are
  /// [scientific, extras], so page 1 is extras — the tour opened there, and
  /// its "swipe the top rows LEFT" step had nothing to the left to reach. You
  /// had to swipe right to scientific first, then left again, to satisfy a
  /// step that was meant to be the first swipe you ever made.
  ///
  /// The first page is the right target for both arrangements, so there is no
  /// longer anything to decide.
  void _resetToFirstKeypadPage() {
    const int targetPage = 0;

    if (_keypadController != null && _keypadController!.hasClients) {
      // Set flag to bypass directional physics during programmatic navigation
      setState(() {
        _isNavigatingProgrammatically = true;
      });

      _keypadController!
          .animateToPage(
            _virtualPageFor(targetPage),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          )
          .then((_) {
            if (mounted) {
              setState(() {
                _isNavigatingProgrammatically = false;
              });
            }
          });
    }
  }

  void _initializeKeypadController(int pagesPerView) {
    // Two pages now (scientific, extras) — the number pad is permanent.
    const int initialPage = 0;
    _keypadVirtualPage = _keypadPageCount * _wrapTurns + initialPage;

    _keypadController?.dispose();
    _keypadController = PageController(
      initialPage: _keypadVirtualPage,
      viewportFraction: 1 / pagesPerView,
    );
  }

  /// The controller page nearest the one showing that holds [page] — the
  /// shortest way round, so going back to a page never spins the keys
  /// through a turn they did not need.
  int _virtualPageFor(int page) {
    final int here = _keypadController?.page?.round() ?? _keypadVirtualPage;
    int step = (page - here) % _keypadPageCount;
    if (step > _keypadPageCount ~/ 2) step -= _keypadPageCount;
    return here + step;
  }

  /// Whether a swipe may turn the page now.
  ///
  /// Any swipe may, except during the tour's swipe steps, which ask for one
  /// direction: there the other does nothing, as it always did. Before the
  /// pages wrapped, the end of the row was what stopped it — the tour asks
  /// for a swipe left on the first page and a swipe right on the last, so
  /// the wrong way had nowhere to go. Now it would come round to the other
  /// page while the tour still waited for its swipe.
  bool _allowKeypadSwipe(bool towardNext) {
    final WalkthroughService tour = widget.walkthroughService;
    if (!tour.isActive) return true;
    final WalkthroughStep step = tour.currentStepData;
    if (!step.requiresAction) return true;
    return switch (step.requiredAction) {
      WalkthroughAction.swipeLeft => towardNext,
      WalkthroughAction.swipeRight => !towardNext,
      _ => true,
    };
  }

  MathEditorController? get _activeController => widget.activeController;

  // Effective keypad button colors, honoring the KeypadColorMode setting
  // (always light, always dark, or follow the current theme).
  static const Color _darkKeypadButton = Color(0xFF2C2C2C);

  Color get _kpButton {
    switch (widget.settingsProvider.keypadColorMode) {
      case KeypadColorMode.light:
        return Colors.white;
      case KeypadColorMode.dark:
        return _darkKeypadButton;
      case KeypadColorMode.themeBased:
        return widget.colors.keypadButton;
    }
  }

  Color get _kpButtonText {
    switch (widget.settingsProvider.keypadColorMode) {
      case KeypadColorMode.light:
        return Colors.black;
      case KeypadColorMode.dark:
        return Colors.white;
      case KeypadColorMode.themeBased:
        return widget.colors.keypadButtonText;
    }
  }

  void _startContinuousDelete() {
    _deletedContentInCurrentBackspaceSession = false;
    _isDeleting = true;
    _deleteSpeed = 150;
    _performDelete();
    if (_isDeleting) {
      _scheduleNextDelete();
    }
  }

  void _scheduleNextDelete() {
    _deleteTimer = Timer(Duration(milliseconds: _deleteSpeed), () {
      if (_isDeleting) {
        _performDelete();
        _deleteSpeed = (_deleteSpeed * 0.85).clamp(30, 150).toInt();
        _scheduleNextDelete();
      }
    });
  }

  void _stopContinuousDelete() {
    _isDeleting = false;
    _deleteTimer?.cancel();
    _deleteTimer = null;
  }

  void _handleSingleBackspace() {
    _deletedContentInCurrentBackspaceSession = false;
    _performDelete();
  }

  void _performDelete() {
    final controller = _activeController;
    if (controller == null) {
      _stopContinuousDelete();
      return;
    }

    if (controller.getExpression().isEmpty) {
      if (!_deletedContentInCurrentBackspaceSession) {
        widget.onRemoveDisplay(widget.activeIndex);
      }
      _stopContinuousDelete();
      return;
    }

    controller.deleteChar();
    _deletedContentInCurrentBackspaceSession = true;
    widget.onUpdateMathEditor();
    widget.onSetState();
  }

  void _handleEnter() {
    // Adds an expression row to the current plot. Every row of a plot is drawn
    // as its own curve on that plot's axes, and a whole new plot still comes
    // from the swipe strip.
    //
    // This used to insert a NewlineNode into the plot's one editor. A line
    // inside a shared node list can carry nothing of its own — no colour, no
    // visibility, no identity — which is what stopped it having a swatch and an
    // eye toggle beside it.
    widget.onAddDisplay();
    widget.onUpdateMathEditor();
    widget.onSetState();
  }

  /// [virtualPage] is the controller's page, which counts on through the
  /// wrap (see [_keypadVirtualPage]); which way it moved is which way the
  /// keys were swiped.
  void _onKeypadPageChanged(int virtualPage) {
    if (virtualPage != _keypadVirtualPage) {
      // Don't trigger walkthrough action if navigating programmatically
      if (!_isNavigatingProgrammatically) {
        final WalkthroughAction direction;
        if (virtualPage > _keypadVirtualPage) {
          direction = WalkthroughAction.swipeLeft;
        } else {
          direction = WalkthroughAction.swipeRight;
        }
        widget.walkthroughService.onUserAction(direction);
      } else {
        debugPrint('Keypad page changed programmatically: $virtualPage');
      }

      _keypadVirtualPage = virtualPage;
    }
  }

  void _handleButtonWithSelection({
    required bool Function() wrapAction,
    required VoidCallback normalAction,
  }) {
    final hadSelection = _activeController?.hasSelection ?? false;

    if (hadSelection) {
      if (wrapAction()) {
        widget.onClearSelectionOverlay?.call();
        widget.onUpdateMathEditor();
        widget.onSetState();
      }
    } else {
      normalAction();
      widget.onUpdateMathEditor();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int pagesPerView = _pagesPerView;
    final isTablet = pagesPerView >= 2;
    if (widget.walkthroughService.isTabletMode != isTablet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.walkthroughService.setDeviceMode(isTablet: isTablet);
      });
    }

    // The controller is made in initState and remade in didUpdateWidget,
    // never here.
    //
    // Making it during build attached a PageController while the PageView
    // under it was building, which marks that subtree dirty mid-build. On its
    // own that is the "setState() called during build" error; when this build
    // runs inside a layout pass — anything with a LayoutBuilder above it —
    // the same marking re-enters layout instead:
    //
    //     '!_debugDoingThisLayout': is not true
    //
    // Nothing here needed a frame to settle. The page count comes from the
    // width and the orientation, both known when the widget is configured.

    // A tablet shows every key at once: one grid, no swiping, no fixed half.
    if (_isTabletLayout) {
      return _buildTabletKeypad();
    }

    // The keys, made once for both halves. Each appears in exactly one of
    // them, so the keys that carry a GlobalKey — ⌘ and settings — are in the
    // tree once.
    final Map<String, Widget> keys = _keyWidgets();

    // One LayoutBuilder for both halves, since they share a height. The boxes
    // the walkthrough measures are keyed inside it, as they always were:
    // `laidOutBox` refuses a LayoutBuilder's own render object, which is what
    // a key hoisted outside one resolves to.
    return LayoutBuilder(
      builder: (context, keypadConstraints) {
        final double available = _usableWidth(keypadConstraints);
        // No width to lay keys out in — the warm-up frame, before the window
        // has a size. An empty box now, the real keypad on the frame after.
        if (available <= 0) return const SizedBox.shrink();
        final double half = available / 2;
        final double cellW = half / _phoneGridColumns;
        final double cellH = cellW / _gridAspectRatioFor(half);
        final double height = cellH * _phoneGridRows;

        // The number pad never moves. Digits and operators are the keys
        // reached most often, and keeping them put means swiping never costs
        // you the numbers.
        final Widget numbers = SizedBox(
          key: widget.numberKeypadKey,
          width: half,
          height: height,
          child: _phoneGrid(_handed(_phoneNumberGrid), keys),
        );

        // The function pages swipe: scientific, then extras.
        final Widget functions = SizedBox(
          key: widget.mainKeypadAreaKey,
          width: half,
          height: height,
          child:
              _keypadController != null
                  ? ListenableBuilder(
                    listenable: widget.walkthroughService,
                    builder: (context, _) {
                      return EasySnapPageView(
                        controller: _keypadController!,
                        onPageChanged: _onKeypadPageChanged,
                        padEnds: false,
                        enableTransitions: !isTablet,
                        // Past either end comes round to the other.
                        wrap: true,
                        allowSwipe: _allowKeypadSwipe,
                        children: [
                          SizedBox.expand(
                            key: widget.scientificKeypadKey,
                            child: _phoneGrid(
                              _handed(_phoneScientificPage),
                              keys,
                            ),
                          ),
                          SizedBox.expand(
                            key: widget.extrasKeypadKey,
                            child: _phoneGrid(_handed(_phoneExtrasPage), keys),
                          ),
                        ],
                      );
                    },
                  )
                  : const SizedBox.shrink(),
        );

        // Numbers under the dominant thumb — on the right for a right-hander,
        // with backspace and the action key on the outer edge — and the
        // function pages on the other side, settings at its far edge. A
        // left-hander gets the mirror image: numbers on the left, functions
        // on the right, every row reflected (see [_handed]).
        //
        // Labels sit close to the edge of their keys, and the inverse
        // functions are stacked, so the long labels can be drawn as large as
        // the keys allow (see [_labelShares]).
        return KeyLabelScale(
          byLength: _labelShares(
            context,
            <Widget?>[
              for (final List<List<String>> page in const <List<List<String>>>[
                _phoneScientificPage,
                _phoneExtrasPage,
                _phoneNumberGrid,
              ])
                for (final List<String> row in page)
                  for (final String name in row) keys[name],
            ],
            cellW -
                widget.settingsProvider.buttonSpacing -
                2 * _phoneLabelPadding,
            stackArc: true,
          ),
          labelPadding: _phoneLabelPadding,
          stackArc: true,
          child: SizedBox(
            width: available,
            height: height,
            child: Row(
              children:
                  _leftHanded
                      ? <Widget>[numbers, functions]
                      : <Widget>[functions, numbers],
            ),
          ),
        );
      },
    );
  }

  /// One half of the phone keypad: [grid] laid out five across.
  Widget _phoneGrid(List<List<String>> grid, Map<String, Widget> keys) {
    final List<String> names = <String>[
      for (final List<String> row in grid) ...row,
    ];
    return LayoutBuilder(
      builder:
          (context, gridConstraints) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: names.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _phoneGridColumns,
              childAspectRatio: _gridAspectRatioFor(gridConstraints.maxWidth),
            ),
            itemBuilder:
                (context, position) => keys[names[position]] ?? _extrasBlank(),
          ),
    );
  }

  // ============================================================
  // SCIENTIFIC PAGE
  //
  // The keys are built here and placed by name: on a phone by
  // [_phoneScientificPage], on a tablet by the tablet grids.
  //
  //   x     y     z     =    x²
  //   x̂     ŷ     ẑ     ≥    √
  //   sin   cos   tan   π    log
  //   asin  acos  atan  e    °
  //
  // Long-press collapses x² -> xⁿ and log -> ln/logᵣ, which is what freed
  // the three slots the unit vectors occupy.
  // ============================================================

  Widget _sciPlain(String label, VoidCallback onTap) {
    return MyButton(
      buttontapped: () {
        onTap();
        widget.onUpdateMathEditor();
      },
      buttonText: label,
      color: _kpButton,
      textColor: _kpButtonText,
    );
  }

  Widget _sciMenu(
    String label, {
    required VoidCallback onTap,
    required List<CalcMenuItem> menuItems,
    Color? menuBackground,
  }) {
    return PopupMenuCalcButton(
      buttonText: label,
      color: _kpButton,
      textColor: _kpButtonText,
      menuBackgroundColor: menuBackground,
      separatorColor: menuBackground == null ? null : Colors.black12,
      onTap: onTap,
      menuItems: menuItems,
      indicatorColor: widget.colors.textSecondary,
    );
  }

  CalcMenuItem _sciItem(String label, VoidCallback action) {
    return CalcMenuItem(
      label: label,
      onTap: () {
        action();
        widget.onUpdateMathEditor();
      },
    );
  }

  Widget _sciTrig(String name, String hyperbolic) {
    return _sciMenu(
      name,
      onTap:
          () => _handleButtonWithSelection(
            wrapAction:
                () => _activeController!.selectionWrapper.wrapInTrig(name),
            normalAction: () => _activeController?.insertTrig(name),
          ),
      menuItems: [
        _sciItem(hyperbolic, () => _activeController?.insertTrig(hyperbolic)),
      ],
    );
  }

  /// A coordinate variable key, with the other systems behind a long press.
  ///
  /// The whole group changes together: choosing spherical from any of the
  /// three turns them all into ρ, θ, ϕ. A row showing two systems at once would
  /// mean nothing, because the symbols only have meaning relative to one.
  /// A coordinate variable key.
  ///
  /// A long press offers the symbol this key becomes in each other system —
  /// hold x and you are offered r and ρ, not the names of the systems they
  /// belong to. Choosing one moves the whole group, so y and z follow to
  /// match: a row reading x, θ, z would mean nothing, because each symbol
  /// only has meaning relative to one system.
  Widget _sciVariable(int axis) {
    final CoordinateSystem system = widget.variableSystem;
    return _sciMenu(
      system.variables[axis],
      onTap: () => _activeController?.insertCharacter(system.variables[axis]),
      menuItems: _systemChoices(
        system,
        (CoordinateSystem s) => s.variables,
        axis,
        (CoordinateSystem s) {
          // Switch the keys and type the symbol, as every other long-press
          // menu does: choosing ln from the log key writes ln. Picking r
          // without writing r would leave you to press the key again.
          widget.onVariableSystemChanged?.call(s);
          _activeController?.insertCharacter(s.variables[axis]);
        },
      ),
    );
  }

  /// The unit vector on the same axis, switched independently of the
  /// variables — writing r̂ while still using x and y is legitimate.
  Widget _sciUnitVector(int axis) {
    final CoordinateSystem system = widget.unitVectorSystem;
    return _sciMenu(
      system.unitVectorLabels[axis],
      onTap:
          () =>
              _activeController?.insertUnitVector(system.unitVectorAxes[axis]),
      menuItems: _systemChoices(
        system,
        (CoordinateSystem s) => s.unitVectorLabels,
        axis,
        (CoordinateSystem s) {
          widget.onUnitVectorSystemChanged?.call(s);
          _activeController?.insertUnitVector(s.unitVectorAxes[axis]);
        },
      ),
    );
  }

  /// The other systems, each shown as the symbol this key would become.
  ///
  /// Where two systems give the same symbol on this axis the whole triple is
  /// shown instead — θ is the second variable of both cylindrical and
  /// spherical, so two menu rows reading "θ" would be a coin toss.
  List<CalcMenuItem> _systemChoices(
    CoordinateSystem current,
    List<String> Function(CoordinateSystem) symbols,
    int axis,
    void Function(CoordinateSystem) choose,
  ) {
    final List<CoordinateSystem> others =
        CoordinateSystem.values.where((s) => s != current).toList();
    final List<String> onThisAxis = <String>[
      for (final CoordinateSystem s in others) symbols(s)[axis],
    ];
    final bool ambiguous = onThisAxis.toSet().length != onThisAxis.length;

    return <CalcMenuItem>[
      for (int i = 0; i < others.length; i++)
        _sciItem(
          ambiguous
              ? '${onThisAxis[i]}      ${symbols(others[i]).join('  ')}'
              : onThisAxis[i],
          () => choose(others[i]),
        ),
    ];
  }

  /// Relational operators. The key carries the one a tap gives you; the rest
  /// are a long press away, as with the trig and log keys.
  Widget _sciInequality() {
    return _sciMenu(
      '≥',
      onTap: () => _activeController?.insertCharacter('≥'),
      menuItems: <CalcMenuItem>[
        for (final String op in const <String>['>', '≤', '<', '≠'])
          _sciItem(op, () => _activeController?.insertCharacter(op)),
      ],
    );
  }

  List<Widget> _scientificButtons() {
    // Built in the order of [_sciNames]; where each goes is decided by name.
    return <Widget>[
      // ---- row 1 ----
      _sciVariable(0),
      _sciVariable(1),
      _sciVariable(2),
      _sciTrig('sin', 'sinh'),
      _sciTrig('cos', 'cosh'),
      _sciTrig('tan', 'tanh'),
      _sciPlain('=', () => _activeController?.insertCharacter('=')),
      // Taps to square, long-press for an arbitrary exponent.
      _sciMenu(
        'x²',
        onTap:
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInSquare(),
              normalAction: () => _activeController?.insertSquare(),
            ),
        menuItems: [
          _sciItem(
            'xⁿ',
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInExponent(),
              normalAction: () => _activeController?.insertCharacter('^'),
            ),
          ),
        ],
      ),
      _sciMenu(
        'π',
        menuBackground: Colors.white,
        onTap: () => _activeController?.insertCharacter('π'),
        menuItems: [
          _sciItem(
            'ε₀ (permittivity)',
            () => _activeController?.insertConstant('ε₀'),
          ),
          _sciItem(
            'μ₀ (permeability)',
            () => _activeController?.insertConstant('μ₀'),
          ),
          _sciItem(
            'c₀ (speed of light)',
            () => _activeController?.insertConstant('c₀'),
          ),
          _sciItem(
            'e⁻ (elementary charge)',
            () => _activeController?.insertConstant('e⁻'),
          ),
        ],
      ),
      // Taps to log base 10; ln and an arbitrary base are a long press away.
      _sciMenu(
        'log',
        onTap:
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInLog10(),
              normalAction: () => _activeController?.insertLog10(),
            ),
        menuItems: [
          _sciItem(
            'ln',
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInNaturalLog(),
              normalAction: () => _activeController?.insertNaturalLog(),
            ),
          ),
          _sciItem(
            'logᵣ',
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInLogN(),
              normalAction: () => _activeController?.insertLogN(),
            ),
          ),
        ],
      ),

      // ---- row 2 ----
      _sciUnitVector(0),
      _sciUnitVector(1),
      _sciUnitVector(2),
      _sciTrig('asin', 'asinh'),
      _sciTrig('acos', 'acosh'),
      _sciTrig('atan', 'atanh'),
      _sciInequality(),
      // The nth root moved in here: same operation with the index supplied,
      // so it belongs behind the square root rather than beside it.
      _sciMenu(
        '√',
        onTap:
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInSquareRoot(),
              normalAction: () => _activeController?.insertSquareRoot(),
            ),
        menuItems: [
          _sciItem(
            'ⁿ√',
            () => _handleButtonWithSelection(
              wrapAction:
                  () => _activeController!.selectionWrapper.wrapInNthRoot(),
              normalAction: () => _activeController?.insertNthRoot(),
            ),
          ),
        ],
      ),
      _sciPlain('e', () => _activeController?.insertCharacter('e')),
      _sciPlain('°', () => _activeController?.insertCharacter('°')),
    ];
  }

  /// The whole tablet keypad: one grid, every key on screen, no swiping.
  ///
  /// A single [GridView] rather than three side-by-side blocks, because the
  /// groups are not all rectangles — see [_landscapeRowWidths]. Composing the
  /// cells row by row is what lets landscape be a true 3x20.
  Widget _buildTabletKeypad() {
    // Keyed out here rather than inside the builder, for the reason given on
    // the phone arrangement above: a GlobalKey created inside a LayoutBuilder
    // is created, and moved, during layout.
    return LayoutBuilder(
      builder: (context, constraints) {
        final Map<String, Widget> byName = _keyWidgets();
        final List<List<String?>> grid = _tabletGrid;

        final List<Widget> cells = <Widget>[
          for (final List<String?> row in grid)
            for (final String? name in row)
              name == null ? _extrasBlank() : byName[name] ?? _extrasBlank(),
        ];

        // Mirroring is a reflection of the finished grid: reverse every row.
        // That flips block order and each block's contents in one step.
        final List<Widget> laidOut =
            _leftHanded ? _mirrorWidgetRows(cells, _tabletColumns) : cells;

        final double tabletWidth = _usableWidth(constraints);
        if (tabletWidth <= 0) return const SizedBox.shrink();
        final double cellW = tabletWidth / _tabletColumns;
        final double cellH = cellW / _gridAspectRatioFor(tabletWidth);

        /// An invisible box over one block, so the walkthrough has something
        /// with a real rect to highlight.
        ///
        /// Laid over the grid rather than wrapped around part of it: the grid
        /// is one GridView of uniform cells, so a block is a span of columns
        /// rather than a widget, and there is nothing to attach a key to.
        Widget blockMarker(GlobalKey? key, String prefix) {
          if (key == null) return const SizedBox.shrink();
          final ({int first, int last})? at = _tabletBlockColumns(grid, prefix);
          if (at == null) return const SizedBox.shrink();
          return Positioned(
            key: key,
            left: at.first * cellW,
            width: (at.last - at.first + 1) * cellW,
            top: 0,
            height: cellH * _tabletRows,
            child: const IgnorePointer(child: SizedBox.expand()),
          );
        }

        return SizedBox(
          key: widget.mainKeypadAreaKey,
          height: cellH * _tabletRows,
          width: tabletWidth,
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: KeyLabelScale(
                  byLength: _labelShares(
                    context,
                    <Widget?>[
                      for (final List<String?> row in grid)
                        for (final String? name in row)
                          if (name != null) byName[name],
                    ],
                    cellW -
                        widget.settingsProvider.buttonSpacing -
                        2 * keyLabelPadding,
                  ),
                  child: _tabletGridView(laidOut, cellW, cellH),
                ),
              ),
              blockMarker(widget.numberBlockKey, 'num.'),
              blockMarker(widget.scientificBlockKey, 'sci.'),
              blockMarker(widget.extrasBlockKey, 'ext.'),
            ],
          ),
        );
      },
    );
  }

  /// How large each length of label is drawn (see [KeyLabelScale]): for each
  /// length of three characters or more, the largest share of the full size
  /// at which every label of that length among [keys] fits in [room], the
  /// width a key leaves for its label.
  ///
  /// Measured rather than guessed from the length. On a tablet nearly every
  /// label fits whole: measured on a Xiaomi Pad 5, all of them in landscape,
  /// and in portrait all but "acos", "d/dx" and "atan", which need about nine
  /// tenths — where shrinking by length drew "sin" at two thirds and "asin"
  /// at half on keys with room to spare. On a phone, with the label nearer
  /// the edge of its key and the inverse functions stacked ([stackArc]), sin,
  /// cos and tan come out at full size, where by length they were two thirds.
  /// Labels of one length share their size, so those that have to come out a
  /// little smaller still match each other.
  ///
  /// Shorter labels are always drawn whole: no single short label should
  /// shrink all the others of its length, and the key's FittedBox still
  /// catches any that would not fit. A stacked inverse function is measured
  /// by the function under its "arc", which is all that has to fit across,
  /// and a fraction is not measured at all.
  Map<int, double> _labelShares(
    BuildContext context,
    Iterable<Widget?> keys,
    double room, {
    bool stackArc = false,
  }) {
    if (room <= 0) return const <int, double>{};
    // The style the label is drawn in: the key's Material sets bodyMedium,
    // and the key sets the size and the line height.
    final TextStyle drawn = (Theme.of(context).textTheme.bodyMedium ??
            const TextStyle())
        .copyWith(height: 1.0);
    final TextScaler scaler = MediaQuery.textScalerOf(context);

    final Map<int, double> shares = <int, double>{};
    for (final Widget? key in keys) {
      final ({String text, double size})? label = switch (key) {
        MyButton(:final String buttonText, :final double fontSize) => (
          text: buttonText,
          size: fontSize,
        ),
        PopupMenuCalcButton(:final String buttonText, :final double fontSize) =>
          (text: buttonText, size: fontSize),
        _ => null,
      };
      if (label == null) continue;
      // Drawn as a fraction, narrower than any long label (see
      // [fractionLabels]); measured as written out, "d/dx" would hold every
      // other four-letter label down to its size.
      if (fractionLabels.containsKey(label.text)) continue;
      final String across =
          stackArc && arcLabels.contains(label.text)
              ? label.text.substring(1)
              : label.text;
      final int length = across.characters.length;
      if (length < 3) continue;
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: across,
          style: drawn.copyWith(fontSize: label.size),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final double fits = room / painter.width;
      painter.dispose();
      shares[length] = math.min(shares[length] ?? 1.0, fits);
    }
    // A hair under the measured fit, so rounding never leaves a label a
    // fraction too wide and its FittedBox shrinking it alone.
    return <int, double>{
      for (final MapEntry<int, double> e in shares.entries)
        e.key: math.min(1.0, e.value * 0.99),
    };
  }

  /// The tablet grid itself.
  Widget _tabletGridView(List<Widget> laidOut, double cellW, double cellH) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: laidOut.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _tabletColumns,
        childAspectRatio: cellW / cellH,
      ),
      itemBuilder: (context, position) => laidOut[position],
    );
  }

  /// Every key, looked up by name — for the phone's halves and the tablet's
  /// grid alike.
  ///
  /// The three builders keep producing their keys in their own order; this
  /// pairs each list with its names. If a builder gains a key and its name
  /// list is not updated the lengths stop matching, which is the check that
  /// the old index tables could not make.
  Map<String, Widget> _keyWidgets() {
    final List<Widget> sci = _scientificButtons();
    final List<Widget> ext = _extrasButtons();
    final List<Widget> num = <Widget>[
      for (int i = 0; i < _numNames.length; i++) _numberButtonAt(i),
    ];
    assert(sci.length == _sciNames.length, 'scientific keys lost their names');
    assert(ext.length == _extNames.length, 'extras keys lost their names');

    return <String, Widget>{
      for (int i = 0; i < _sciNames.length; i++) _sciNames[i]: sci[i],
      for (int i = 0; i < _extNames.length; i++) _extNames[i]: ext[i],
      for (int i = 0; i < _numNames.length; i++) _numNames[i]: num[i],
    };
  }

  /// One key of the number pad, addressed by its index in [_buttons] so both
  /// the phone grid and the tablet block can place it wherever they like.
  Widget _numberButtonAt(int index) {
    if (index == 3) {
      return MyButton(
        buttontapped: () {
          _handleButtonWithSelection(
            wrapAction:
                () => _activeController!.selectionWrapper.wrapInParenthesis(),
            normalAction:
                () => _activeController?.insertCharacter(_buttons[index]),
          );
        },
        buttonText: '\u0028\u0029',
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 4) {
      return GestureDetector(
        onLongPressStart: (_) => _startContinuousDelete(),
        onLongPressEnd: (_) => _stopContinuousDelete(),
        onLongPressCancel: _stopContinuousDelete,
        child: MyButton(
          buttontapped: _handleSingleBackspace,
          buttonText: '\u232B',
          color: const Color.fromARGB(255, 226, 104, 104),
          textColor: _kpButtonText,
        ),
      );
    } else if (index == 8) {
      return MyButton(
        buttontapped: () {
          _activeController?.insertCharacter('\u002B');
          widget.onUpdateMathEditor();
        },
        buttonText: '\u002B',
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 9) {
      return MyButton(
        buttontapped: () {
          _activeController?.insertCharacter('\u2212');
          widget.onUpdateMathEditor();
        },
        buttonText: '\u2212',
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 13) {
      return MyButton(
        buttontapped: () {
          _activeController?.insertCharacter(
            widget.settingsProvider.multiplicationSign,
          );
          widget.onUpdateMathEditor();
        },
        buttonText: '\u00D7',
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } // Division button (index 14)
    else if (index == 14) {
      return MyButton(
        buttontapped: () {
          _handleButtonWithSelection(
            wrapAction:
                () => _activeController!.selectionWrapper.wrapInFraction(),
            normalAction:
                () => _activeController?.insertCharacter(_buttons[index]),
          );
        },
        buttonText: '\u00F7',
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 17) {
      // Scientific notation is the only behaviour for this key. klotter is
      // an advanced calculator: 1E6 earns the slot, percentage does not.
      return MyButton(
        buttontapped: () {
          _activeController?.insertCharacter(MathTextStyle.scientificE);
          widget.onUpdateMathEditor();
        },
        buttonText: MathTextStyle.scientificE,
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 18) {
      return MyButton(
        buttontapped: () {
          _activeController?.clear();
          widget.onUpdateMathEditor();
          widget.onSetState();
        },
        buttonText: _buttons[index],
        color: _kpButton,
        textColor: _kpButtonText,
      );
    } else if (index == 19) {
      return Container(
        key: widget.commandButtonKey,
        child: MyButton(
          buttontapped: _handleEnter,
          buttonText: '\u2318',
          color: Colors.blueGrey,
          textColor: _kpButtonText,
        ),
      );
    } else {
      return MyButton(
        buttontapped: () {
          _activeController?.insertCharacter(_buttons[index]);
          widget.onUpdateMathEditor();
        },
        buttonText: _buttons[index],
        color: _kpButton,
        textColor: _kpButtonText,
      );
    }
  }

  // ============================================================
  // EXTRAS PAGE
  //
  // Grouped in pairs: each two keys that belong together share a column,
  // read top-then-bottom — sin over asin, d/dx over ∫. On a phone, for a
  // right-hander:
  //
  //   sin   i     u     x²    !
  //   asin  π     v     √     |x|
  //   ⌧     ⎌     ⎏     ⁿPᵣ   d/dx
  //   ☰     ⇪     ⓘ     ∑     ∫
  //
  // The keys that act on the whole document rather than the expression —
  // clear-all, undo, redo, export, help, settings — take the outer bottom
  // corner as one block, settings in the corner itself. A left-hander sees
  // the page reflected, settings in the far right corner.
  //
  // ANS is gone: removing the result display took the cell index with it, so
  // the key referenced something the user could no longer see.
  // ============================================================

  Widget _extrasBlank() => const SizedBox.shrink();

  SelectionWrapper get _wrapper => _activeController!.selectionWrapper;

  Widget _extrasAction(
    String label,
    VoidCallback? onTap, {
    bool mirrored = false,
    double? fontSize,
    bool enabled = true,
  }) {
    // A key with nothing to do says so rather than looking live and doing
    // nothing when pressed: dimmed, and not tappable.
    final Widget button = MyButton(
      buttontapped: enabled ? onTap : null,
      buttonText: label,
      color: _kpButton,
      textColor: enabled ? _kpButtonText : _kpButtonText.withValues(alpha: 0.3),
      fontSize: fontSize ?? 22,
    );
    // Redo is undo's mirror image. Unicode has no flipped twin of U+238C, so
    // the glyph is drawn reversed rather than substituted with a different
    // symbol that would only approximate the pair.
    if (!mirrored) return button;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: button,
    );
  }

  /// A key whose long-press menu offers related variants of the same idea.
  Widget _extrasVariants(
    String label, {
    required bool Function() wrap,
    required VoidCallback normal,
    required List<CalcMenuItem> variants,
  }) {
    return _sciMenu(
      label,
      onTap:
          () => _handleButtonWithSelection(
            wrapAction: wrap,
            normalAction: normal,
          ),
      menuItems: variants,
    );
  }

  /// Menu entry that wraps a selection when there is one.
  CalcMenuItem _extrasWrapItem(
    String label, {
    required bool Function() wrap,
    required VoidCallback normal,
  }) {
    return CalcMenuItem(
      label: label,
      onTap: () {
        _handleButtonWithSelection(wrapAction: wrap, normalAction: normal);
        widget.onUpdateMathEditor();
      },
    );
  }

  CalcMenuItem _extrasTrigItem(String name) =>
      _sciItem(name, () => _activeController?.insertTrig(name));

  List<Widget> _extrasButtons() {
    // ---- pieces, defined once and placed below ----
    // Long-pressing the imaginary unit reveals z̲ — z with a low line — the
    // complex variable written as one symbol instead of as x + iy. It belongs
    // on this key because it is the same idea: i is what makes a line complex,
    // and z̲ is what such a line is a function of.
    final Widget kI = _sciMenu(
      'i',
      onTap: () {
        _activeController?.insertCharacter('i');
        widget.onUpdateMathEditor();
      },
      menuItems: [
        _sciItem('z̲', () {
          _activeController?.insertComplexVariable();
          widget.onUpdateMathEditor();
        }),
      ],
    );

    final Widget kPi = _sciMenu(
      'π',
      menuBackground: Colors.white,
      onTap: () => _activeController?.insertCharacter('π'),
      menuItems: [
        _sciItem('e', () => _activeController?.insertConstant('e')),
        _sciItem('μ₀', () => _activeController?.insertConstant('μ₀')),
        _sciItem('ε₀', () => _activeController?.insertConstant('ε₀')),
        _sciItem('c₀', () => _activeController?.insertConstant('c₀')),
      ],
    );
    // u and v are the parameters a parametric plot runs over: one traces a
    // curve, both together sweep a surface. They are their own quantities
    // rather than another name for a coordinate, so neither offers the x/y/z
    // menu the scientific variable keys carry.
    final Widget kU = _extrasAction(
      'u',
      () => _activeController?.insertCharacter('u'),
    );
    final Widget kV = _extrasAction(
      'v',
      () => _activeController?.insertCharacter('v'),
    );
    final Widget kSquare = _extrasVariants(
      'x²',
      wrap: () => _wrapper.wrapInSquare(),
      normal: () => _activeController?.insertSquare(),
      variants: [
        _extrasWrapItem(
          'xⁿ',
          wrap: () => _wrapper.wrapInExponent(),
          normal: () => _activeController?.insertCharacter('^'),
        ),
      ],
    );
    final Widget kRoot = _extrasVariants(
      '√',
      wrap: () => _wrapper.wrapInSquareRoot(),
      normal: () => _activeController?.insertSquareRoot(),
      variants: [
        _extrasWrapItem(
          'ⁿ√',
          wrap: () => _wrapper.wrapInNthRoot(),
          normal: () => _activeController?.insertNthRoot(),
        ),
      ],
    );
    final Widget kAbs = _extrasVariants(
      '|x|',
      wrap: () => _wrapper.wrapInTrig('abs'),
      normal: () => _activeController?.insertTrig('abs'),
      variants: [
        for (final f in const ['arg', 'Re', 'Im', 'sgn'])
          _extrasWrapItem(
            f,
            wrap: () => _wrapper.wrapInTrig(f),
            normal: () => _activeController?.insertTrig(f),
          ),
      ],
    );
    final Widget kSin = _extrasVariants(
      'sin',
      wrap: () => _wrapper.wrapInTrig('sin'),
      normal: () => _activeController?.insertTrig('sin'),
      variants: [
        for (final f in const ['cos', 'tan', 'sinh', 'cosh', 'tanh'])
          _extrasTrigItem(f),
      ],
    );
    final Widget kAsin = _extrasVariants(
      'asin',
      wrap: () => _wrapper.wrapInTrig('asin'),
      normal: () => _activeController?.insertTrig('asin'),
      variants: [
        for (final f in const ['acos', 'atan', 'asinh', 'acosh', 'atanh'])
          _extrasTrigItem(f),
      ],
    );
    final Widget kFactorial = _extrasAction('!', () {
      _activeController?.insertCharacter('!');
      widget.onUpdateMathEditor();
    });
    final Widget kPerm = _extrasVariants(
      'ⁿPᵣ',
      wrap: () => _wrapper.wrapInPermutation(),
      normal: () => _activeController?.insertPermutation(),
      // One key for both: the same idea with and without order, and
      // splitting them cost a cell that u and v now use.
      variants: [
        _extrasWrapItem(
          'ⁿCᵣ',
          wrap: () => _wrapper.wrapInCombination(),
          normal: () => _activeController?.insertCombination(),
        ),
      ],
    );
    final Widget kSum = _extrasVariants(
      '∑',
      wrap: () => _wrapper.wrapInSummation(),
      normal: () => _activeController?.insertSummation(),
      variants: [
        _extrasWrapItem(
          '∏',
          wrap: () => _wrapper.wrapInProduct(),
          normal: () => _activeController?.insertProduct(),
        ),
      ],
    );
    final Widget kDeriv = _extrasVariants(
      'd/dx',
      wrap: () => _wrapper.wrapInDerivative(),
      normal: () => _activeController?.insertDerivative(),
      variants: [
        _extrasWrapItem(
          'd/dx|ₐ',
          wrap: () => _wrapper.wrapInDerivative(definite: true),
          normal: () => _activeController?.insertDerivative(definite: true),
        ),
      ],
    );
    final Widget kIntegral = _extrasVariants(
      '∫',
      wrap: () => _wrapper.wrapInIntegral(),
      normal: () => _activeController?.insertIntegral(),
      variants: [
        _extrasWrapItem(
          '∫ₐᵇ',
          wrap: () => _wrapper.wrapInIntegral(definite: true),
          normal: () => _activeController?.insertIntegral(definite: true),
        ),
      ],
    );
    final Widget kUndo = _extrasAction(
      '⎌',
      () => widget.onUndoAppState?.call(),
      enabled: widget.canUndoAppState,
    );
    final Widget kRedo = _extrasAction(
      '⎌',
      () => widget.onRedoAppState?.call(),
      mirrored: true,
      enabled: widget.canRedoAppState,
    );
    final Widget kClearAll = _extrasAction('⌧', widget.onClearAllDisplays);
    // U+21EA, an upward arrow out of a tray: the plot leaving the app. It sits
    // in the slot that was empty, beside the other whole-app actions rather
    // than among the maths keys.
    final Widget kExport = _extrasAction('⇪', fontSize: 30, () {
      widget.onExportPlot?.call();
    });
    final Widget kHelp = _extrasAction(
      'ⓘ',
      () => Navigator.push(context, SlidePageRoute(page: HelpPage())),
    );
    final Widget kSettings = Container(
      key: widget.settingsButtonKey,
      child: _extrasAction('☰', () {
        Navigator.push(
          context,
          SlidePageRoute(
            page: SettingsScreen(
              onShowTutorial: () {
                Navigator.pop(context);
                widget.walkthroughService.resetWalkthrough();
              },
            ),
          ),
        );
      }),
    );

    // Built in the order of [_extNames]; where each goes is decided by name.
    return <Widget>[
      // row 1
      kSin, kI, kU, kSquare, kFactorial, kPerm, kDeriv, kUndo, kRedo,
      kClearAll,
      // row 2
      kAsin, kPi, kV, kRoot, kAbs, kSum, kIntegral, kExport, kHelp,
      kSettings,
    ];
  }
}

class EasySnapPageView extends StatefulWidget {
  final PageController controller;
  final List<Widget> children;
  final ValueChanged<int>? onPageChanged;
  final bool padEnds;
  final bool enableTransitions; // Add this

  /// Whether the pages come round again past either end, so a swipe off the
  /// last page brings in the first and a swipe back off the first brings in
  /// the last, each sliding in from the side it was swiped from.
  ///
  /// The pages then repeat without end in both directions: page n of the
  /// controller shows `children[n % children.length]`, and [onPageChanged]
  /// reports n itself, which keeps counting the way the swipes went. Start
  /// the controller well away from zero, so there are turns to spare in both
  /// directions.
  final bool wrap;

  /// Asked before a swipe moves the pages, with whether it heads for the next
  /// page — a swipe to the left. Null lets every swipe through.
  final bool Function(bool towardNext)? allowSwipe;

  const EasySnapPageView({
    super.key,
    required this.controller,
    required this.children,
    this.onPageChanged,
    this.padEnds = false,
    this.enableTransitions = true, // Default true for phone
    this.wrap = false,
    this.allowSwipe,
  });

  @override
  State<EasySnapPageView> createState() => _EasySnapPageViewState();
}

class _EasySnapPageViewState extends State<EasySnapPageView> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) {
        _handled = false;
      },
      onHorizontalDragUpdate: (details) {
        if (_handled) return;

        final delta = details.primaryDelta ?? 0;
        if (delta == 0) return;

        _handled = true;

        final bool towardNext = delta < 0;
        if (widget.allowSwipe?.call(towardNext) == false) return;

        final currentPage = widget.controller.page?.round() ?? 0;
        final int step = towardNext ? 1 : -1;
        final targetPage =
            widget.wrap
                ? currentPage + step
                : (currentPage + step).clamp(0, widget.children.length - 1);

        widget.controller.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      },
      child:
          widget.enableTransitions
              ? _buildWithTransitions()
              : _buildWithoutTransitions(),
    );
  }

  Widget _buildWithTransitions() {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return PageView.builder(
          controller: widget.controller,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: widget.onPageChanged,
          padEnds: widget.padEnds,
          itemCount: widget.wrap ? null : widget.children.length,
          itemBuilder: (context, index) {
            // Before the first layout there is no page to read, so it is the
            // page the controller opens on. Taken as 0 instead, a wrapping
            // controller — which opens a thousand turns in — drew its first
            // page as though it were that far away, shrunk and half faded,
            // until something scrolled it.
            double page = widget.controller.initialPage.toDouble();
            if (widget.controller.position.hasContentDimensions) {
              page = widget.controller.page ?? page;
            }

            final double offset = (page - index).abs();
            final double scale = (1 - (offset * 0.15)).clamp(0.85, 1.0);
            final double opacity = (1 - (offset * 0.5)).clamp(0.5, 1.0);

            return Transform.scale(
              scale: scale,
              child: Opacity(opacity: opacity, child: _pageAt(index)),
            );
          },
        );
      },
    );
  }

  Widget _buildWithoutTransitions() {
    return PageView.builder(
      controller: widget.controller,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: widget.onPageChanged,
      padEnds: widget.padEnds,
      itemCount: widget.wrap ? null : widget.children.length,
      itemBuilder: (context, index) => _pageAt(index),
    );
  }

  /// The page shown at [index] of the controller, which keeps counting past
  /// the last child when the pages wrap.
  ///
  /// Only neighbouring pages are ever on screen together, and with two or more
  /// children they are always different ones — which matters, because the
  /// pages carry global keys and a key may only be in the tree once.
  Widget _pageAt(int index) => widget.children[index % widget.children.length];
}

// ---- exposed for tests ------------------------------------------------------
// Dart privacy is per library, so these reach the state class from the same
// file. They exist so a test can assert every key is placed exactly once in
// each orientation — the check the old index tables could not support.

/// Every key a tablet shows, by name.
List<String> get tabletKeyNames => _CalculatorKeypadState.tabletKeyNames;

/// The authored grid for an orientation; null is a deliberate empty cell.
List<List<String?>> tabletGridFor({required bool landscape}) =>
    landscape
        ? _CalculatorKeypadState._tabletLandscapeGrid
        : _CalculatorKeypadState._tabletPortraitGrid;
