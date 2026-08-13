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
  final Map<int, MathEditorController?> mathEditorControllers;
  final Map<int, TextEditingController?> textDisplayControllers;
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
    required this.mathEditorControllers,
    required this.textDisplayControllers,
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
  // ---- klotter keypad density -------------------------------------------
  // klotter shares the screen with a live plot, so the phone keypad runs at
  // 10 columns x 2 rows instead of klator's 5 x 4. That is 96dp instead of
  // 288dp, leaving ~190dp more for the plot while keeping the expression
  // editable — the whole point of plotting inline rather than modally.
  //
  // At 10 columns a 360dp phone gives 36dp-wide keys, under the 48dp Material
  // minimum, so keys are made taller than wide (0.75) with a hard 48dp floor —
  // the same geometry a phone QWERTY uses. Unlike a keyboard a calculator has
  // no autocorrect, so a mis-tap is a wrong answer nobody notices.
  //
  // Tablets keep klator's 5 x 4: two pages sit side by side there, so the
  // effective density is already 10 across.
  static const int _phoneGridColumns = 10;
  static const int _phoneGridRows = 2;
  static const double _phonePortraitTileAspect = 0.75;
  static const double _minPhoneTileHeight = 48.0;

  // ---- klotter phone key order ------------------------------------------
  // The button lists and their itemBuilders are written for klator's 5x4
  // grid, where index i lands at (row i~/5, col i%5). Reflowed to 10x2 that
  // same order reads as nonsense — the number pad becomes "7 8 9 ( <- 4 5 6
  // + -" across one row.
  //
  // Rather than reorder the lists (the itemBuilders branch on specific
  // indices, so that would rewire every button's behaviour), these tables map
  // a *visual position* to the original list index. Builders are untouched.
  //
  // Row 0 = digits ascending, like a phone keyboard's number row.
  // Row 1 = separators, operators and editing keys.
  // Mirrors the old pull-up pad: digits fill the left five columns, operators
  // and editing keys the right five.
  //   5 6 7 8 9 | ( ) + - CE ⌫
  //   0 1 2 3 4 | .  x /  E  ⌘
  // Destructive keys (clear, backspace) sit together on the top right; the
  // action button takes the bottom-right corner where Enter belongs.
  static const List<int> _numberPhoneOrder = <int>[
    6, 7, 0, 1, 2, 3, 8, 9, 18, 4, // 5 6 7 8 9 | () + - CE back
    15, 10, 11, 12, 5, 16, 13, 14, 17, 19, // 0 1 2 3 4 | . x / E cmd
  ];

  /// The phone number pad, mirrored for a left-hander so the digits move to
  /// the right half and the operators to the left.
  List<int> get _phoneNumberOrder =>
      _leftHanded
          ? _mirrorRows(_numberPhoneOrder, _phoneGridColumns)
          : _numberPhoneOrder;

  /// Maps a grid position to the index the itemBuilder expects. Tablets keep
  /// klator's 5x4 order untouched.
  int _phoneIndex(List<int> order, int position) {
    if (_isTabletLayout || position >= order.length) return position;
    return order[position];
  }
  // -----------------------------------------------------------------------

  bool get _isTabletLayout => widget.isLandscape || widget.screenWidth > 600;

  // One shape everywhere: each half of the keypad is a single 20-key grid, so
  // 10 columns x 2 rows. Splitting the keypad into a swipeable function half
  // and a fixed number half means a 5 x 4 tablet grid would stack to eight
  // rows; tablets keep their larger key aspect instead (see below).
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

  /// Columns each group takes on each row: extras | scientific | numbers.
  ///
  /// Landscape is a true 3x20. Three 20-key blocks cannot tile 20 columns as
  /// rectangles, but they do not have to be rectangles: numbers stays a clean
  /// 7-wide block and the extras/scientific boundary steps one column between
  /// the first row and the rest. 60 cells, 59 keys, one gap.
  static const List<List<int>> _landscapeRowWidths = <List<int>>[
    <int>[7, 6, 7],
    <int>[6, 7, 7],
    <int>[6, 7, 7],
  ];

  static const List<List<int>> _portraitRowWidths = <List<int>>[
    <int>[5, 5, 5],
    <int>[5, 5, 5],
    <int>[5, 5, 5],
    <int>[5, 5, 5],
  ];

  List<List<int>> get _rowWidths =>
      widget.isLandscape ? _landscapeRowWidths : _portraitRowWidths;

  /// Total columns: 3x20 landscape, 4x15 portrait.
  ///
  int get _tabletColumns => widget.isLandscape ? 20 : 15;

  bool get _leftHanded =>
      widget.settingsProvider.handedness == Handedness.leftHanded;

  // ---- tablet key orders -------------------------------------------------
  // Every block is authored per width, because a 20-key list reflows
  // differently at 5 and 7 columns and "just let it wrap" scatters the groups
  // that matter — the six trig keys especially.
  //
  // Both orientations show the SAME 58 keys and the same 2 blanks; only the
  // shape changes. Extras permanently drops its `x`, which duplicates the
  // scientific `x` (both give y and z on long-press), and its filler blank.
  //
  // -1 means an empty cell.

  /// Backspace tops the outer column, the action key ends it — the two are
  /// the extremes of the same column, which is the screen edge.
  static const List<int> _numberFiveWide = <int>[
    0, 1, 2, 3, 4, // 7 8 9 ()  | <-
    5, 6, 7, 8, 9, // 4 5 6 +   | -
    10, 11, 12, 13, 14, // 1 2 3 x   | /
    15, 16, 17, 18, 19, // 0 . E CE  | cmd
  ];

  /// The outer column is all editing keys — backspace, clear, action — with no
  /// hole between them; 21 cells for 20 keys leaves one gap, and it belongs at
  /// the end of the last row with the other blocks' gaps rather than in the
  /// middle of a column where it reads as a missing key.
  static const List<int> _numberSevenWide = <int>[
    0, 1, 2, 3, 8, 9, 4, // 7 8 9 ( ) + -  | <-
    5, 6, 7, 13, 14, 17, 18, // 4 5 6 x / E    | CE
    10, 11, 12, 15, 16, -1, 19, // 1 2 3 0 .      | cmd
  ];

  /// Variables and algebra up top, then the six trig keys as a 2x3 block.
  // Scientific source indices, in the order _scientificButtons builds them:
  //  0 x   1 y   2 z   3 sin   4 cos   5 tan   6 =  7 x²  8 π  9 log
  // 10 x̂  11 ŷ  12 ẑ  13 asin 14 acos 15 atan 16 ≥  17 √  18 e 19 °
  //
  // Reflowing to five columns keeps every pair in one column: a unit vector
  // under its variable, an inverse under its trig function, the root under
  // the square, the relational operators under equals.
  static const List<int> _scientificFiveWide = <int>[
    0, 1, 2, 6, 7, // x    y    z    =  x²
    10, 11, 12, 16, 17, // x̂    ŷ    ẑ    ≥  √
    3, 4, 5, 8, 9, // sin  cos  tan  π  log
    13, 14, 15, 18, 19, // asin acos atan e  °
  ];

  /// Rows of 6, 7, 7 — the scientific block is one column narrower in the top
  /// row so the whole keypad lands on exactly 20 columns. Rows 1 and 2 start
  /// at the same grid column, which is what keeps the trig keys aligned.
  static const List<int> _scientificLandscape = <int>[
    0, 1, 2, 10, 11, 12, // x  y  z  x̂  ŷ  ẑ
    3, 4, 5, 6, 7, 8, 9, // sin  cos  tan  =  x² π log
    13, 14, 15, 16, 17, 18, 19, // asin acos atan ≥ √  e  °
  ];

  // Extras source indices:
  //  0 i   1 x   2 √   3 sin  4 x!  5 nCr  6 d/dx 7 undo 8 redo 9 clear
  // 10 π  11 x² 12 |x| 13 asin 14 nPr 15 Σ  16 ∫  17 blank* 18 help 19 settings
  //  (* the filler blank is not placed; -1 supplies empties where needed)
  //
  // The first column is the screen edge, since extras is the outermost block.
  // It runs clear at the top, then undo and redo, with settings at the bottom.
  static const List<int> _extrasFiveWide = <int>[
    9, 0, 10, 2, 11, // clear    | i π √ x²
    7, 12, 3, 13, 4, // undo     | |x| sin asin x!
    8, 5, 14, 6, 15, // redo     | nCr nPr d/dx Σ
    19, 18, 16, 1, -1, // settings | help ∫ x
  ];

  /// Rows of 7, 6, 6 — 19 cells for 19 keys, no gaps.
  static const List<int> _extrasLandscape = <int>[
    9, 0, 10, 2, 11, 12, 3, // clear    | i π √ x² |x| sin
    7, 8, 13, 4, 5, 14, // undo redo | asin x! nCr nPr
    19, 18, 6, 15, 16, 1, // settings help | d/dx Σ ∫ x
  ];

  List<int> get _numberTabletOrder =>
      widget.isLandscape ? _numberSevenWide : _numberFiveWide;

  List<int> get _scientificTabletOrder =>
      widget.isLandscape ? _scientificLandscape : _scientificFiveWide;

  List<int> get _extrasTabletOrder =>
      widget.isLandscape ? _extrasLandscape : _extrasFiveWide;

  /// Place [source] into [order], where -1 leaves an empty cell.
  List<Widget> _arrange(List<Widget> source, List<int> order) => <Widget>[
    for (final int i in order) i < 0 ? _extrasBlank() : source[i],
  ];

  /// Mirror a row-major order across the vertical axis.
  ///
  /// Mirroring rather than merely moving the block keeps the reach the same:
  /// whatever fell under the dominant thumb still does, just on the other side.
  List<int> _mirrorRows(List<int> order, int columns) {
    final List<int> out = <int>[];
    for (int start = 0; start < order.length; start += columns) {
      final int stop = math.min(start + columns, order.length);
      out.addAll(order.sublist(start, stop).reversed);
    }
    return out;
  }

  List<Widget> _mirrorWidgetRows(List<Widget> items, int columns) {
    final List<Widget> out = <Widget>[];
    for (int start = 0; start < items.length; start += columns) {
      final int stop = math.min(start + columns, items.length);
      out.addAll(items.sublist(start, stop).reversed);
    }
    return out;
  }

  int get _gridColumns => _phoneGridColumns;

  int get _gridRows => _phoneGridRows;

  /// childAspectRatio for the main grids (width / height).
  ///
  /// Takes the width the grid will actually be laid out at, not
  /// `widget.screenWidth`. On phones the ratio depends on width (because of the
  /// 48dp floor), so deriving it from a different width than the grid receives
  /// would size the container and the tiles inconsistently and clip a row.
  double _gridAspectRatioFor(double availableWidth) {
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
    return tileWidth / tileHeight;
  }
  // -----------------------------------------------------------------------

  int? _lastPagesPerView;

  PageController? _keypadController;

  Timer? _deleteTimer;
  bool _isDeleting = false;
  int _deleteSpeed = 150;
  bool _deletedContentInCurrentBackspaceSession = false;

  int _currentKeypadIndex = 1;

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
    widget.walkthroughService.onResetKeypad = _resetToNumberKeypad;
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
    if (widget.walkthroughService != oldWidget.walkthroughService) {
      oldWidget.walkthroughService.onResetKeypad = null;
      oldWidget.walkthroughService.onNavigateToKeypadPage = null;
      widget.walkthroughService.onResetKeypad = _resetToNumberKeypad;
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
            page,
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

      _currentKeypadIndex = page;
    } else {
      debugPrint('Could not navigate - controller null or no clients');
    }
  }

  void _resetToNumberKeypad() {
    final int targetPage;
    if (_lastPagesPerView != null && _lastPagesPerView! >= 2) {
      targetPage = 0;
    } else {
      targetPage = 1;
    }

    if (_keypadController != null && _keypadController!.hasClients) {
      // Set flag to bypass directional physics during programmatic navigation
      setState(() {
        _isNavigatingProgrammatically = true;
      });

      _keypadController!
          .animateToPage(
            targetPage,
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

    _currentKeypadIndex = targetPage;
  }

  void _initializeKeypadController(int pagesPerView) {
    // Two pages now (scientific, extras) — the number pad is permanent.
    const int initialPage = 0;
    _currentKeypadIndex = initialPage;

    _keypadController?.dispose();
    _keypadController = PageController(
      initialPage: initialPage,
      viewportFraction: 1 / pagesPerView,
    );
  }

  MathEditorController? get _activeController =>
      widget.mathEditorControllers[widget.activeIndex];

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

  bool isOperator(String text) {
    const operators = [
      '+',
      '-',
      'x',
      '/',
      '=',
      '\u002B',
      '\u2212',
      '\u00B7',
      '\u00D7',
      '\u00F7',
    ];
    return operators.contains(text);
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
    // In klotter the action button always starts a new expression *within the
    // same cell*, because every line of a cell is drawn as its own curve on
    // that cell's plot. A whole new plot comes from the swipe strip instead.
    if (_activeController != null) {
      _activeController!.insertNewline();
      widget.onUpdateMathEditor();
      widget.onSetState();
    }
  }

  void _onKeypadPageChanged(int newIndex) {
    if (newIndex != _currentKeypadIndex) {
      // Don't trigger walkthrough action if navigating programmatically
      if (!_isNavigatingProgrammatically) {
        final WalkthroughAction direction;
        if (newIndex > _currentKeypadIndex) {
          direction = WalkthroughAction.swipeLeft;
        } else {
          direction = WalkthroughAction.swipeRight;
        }
        widget.walkthroughService.onUserAction(direction);
      } else {
        debugPrint('Keypad page changed programmatically: $newIndex');
      }

      _currentKeypadIndex = newIndex;
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
    bool isWideScreen = widget.screenWidth > 600;
    int pagesPerView;

    if (widget.isLandscape) {
      pagesPerView = 2;
    } else if (isWideScreen) {
      pagesPerView = 2;
    } else {
      pagesPerView = 1;
    }

    final isTablet = pagesPerView >= 2;
    if (widget.walkthroughService.isTabletMode != isTablet) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.walkthroughService.setDeviceMode(isTablet: isTablet);
      });
    }

    if (_lastPagesPerView != pagesPerView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _initializeKeypadController(pagesPerView);
          setState(() {});
        }
      });

      if (_keypadController == null) {
        _initializeKeypadController(pagesPerView);
      }

      _lastPagesPerView = pagesPerView;
    }

    // A tablet shows every key at once: one grid, no swiping, no fixed half.
    if (_isTabletLayout) {
      return _buildTabletKeypad();
    }

    int crossAxisCount = _gridColumns;
    int rowCount = _gridRows;
    // Page width, not screen width: with pagesPerView > 1 each page (and so
    // each grid) is only a fraction of the screen. The grids derive their own
    // aspect ratio from the same width, so container and tiles stay in step.

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Swipeable half: functions on top. Two pages now — scientific and
        // extras — because the number pad below is permanent.
        LayoutBuilder(
          builder: (context, keypadConstraints) {
            final double pageWidth = keypadConstraints.maxWidth / pagesPerView;
            final double cellW = pageWidth / crossAxisCount;
            final double cellH = cellW / _gridAspectRatioFor(pageWidth);
            return SizedBox(
              key: widget.mainKeypadAreaKey,
              height: cellH * rowCount,
              width: double.infinity,
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
                            children: [
                              SizedBox.expand(
                                key: widget.scientificKeypadKey,
                                child: _buildScientificGrid(widget.isLandscape),
                              ),
                              SizedBox.expand(
                                key: widget.extrasKeypadKey,
                                child: _buildExtrasGrid(widget.isLandscape),
                              ),
                            ],
                          );
                        },
                      )
                      : const SizedBox.shrink(),
            );
          },
        ),

        // Fixed half: the number pad never moves. Digits and operators are
        // the keys reached most often and sit closest to the thumb, and
        // keeping them put means swiping never costs you the numbers.
        LayoutBuilder(
          builder: (context, numberConstraints) {
            final double gridWidth = numberConstraints.maxWidth;
            final double cellW = gridWidth / crossAxisCount;
            final double cellH = cellW / _gridAspectRatioFor(gridWidth);
            return SizedBox(
              key: widget.numberKeypadKey,
              height: cellH * rowCount,
              width: double.infinity,
              child: _buildNumberGrid(widget.isLandscape),
            );
          },
        ),
      ],
    );
  }

  // ============================================================
  // SCIENTIFIC PAGE
  //
  // Authored in visual order rather than remapped from a 5x4 list, so the
  // arrangement is readable here and no index table has to be kept in sync.
  //
  //   row 1  x  y  z  x̂  ŷ  ẑ  =  x²  √  ⁿ√        build the expression
  //   row 2  sin cos tan asin acos atan log ° π e    apply a function
  //
  // Row 1 is what you write *with* — variables, unit vectors, equality and
  // the power/root forms. Row 2 is what you apply *to* them, with the six
  // trig keys in one block. Long-press collapses x² -> xⁿ and log -> ln/logᵣ,
  // which is what freed the three slots the unit vectors now occupy.
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
    // Two rows of ten, each key above or below its relative:
    //
    //   x  y  z  sin   cos   tan   =  x²  π  log
    //   x̂  ŷ  ẑ  asin  acos  atan  ≥  √   e  °
    //
    // Unit vectors under their variables, inverse trig under trig, the root
    // under the square, the relational operators under equals.
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final List<Widget> extras = _arrange(
          _extrasButtons(),
          _extrasTabletOrder,
        );
        final List<Widget> scientific = _arrange(
          _scientificButtons(),
          _scientificTabletOrder,
        );
        final List<Widget> numbers = _arrange(<Widget>[
          for (int i = 0; i < 20; i++) _numberButtonAt(i),
        ], _numberTabletOrder);

        // Walk each group with its own cursor: a group takes a different
        // number of columns on different rows.
        final List<List<Widget>> groups = <List<Widget>>[
          extras,
          scientific,
          numbers,
        ];
        final List<int> taken = <int>[0, 0, 0];
        final List<Widget> cells = <Widget>[];

        for (final List<int> widths in _rowWidths) {
          for (int g = 0; g < groups.length; g++) {
            for (int c = 0; c < widths[g]; c++) {
              final int i = taken[g]++;
              cells.add(i < groups[g].length ? groups[g][i] : _extrasBlank());
            }
          }
        }

        // Mirroring is a reflection of the finished grid: reverse every row.
        // That flips block order and each block's contents in one step.
        final List<Widget> laidOut =
            _leftHanded ? _mirrorWidgetRows(cells, _tabletColumns) : cells;

        final double cellW = constraints.maxWidth / _tabletColumns;
        final double cellH = cellW / _gridAspectRatioFor(constraints.maxWidth);

        return SizedBox(
          key: widget.mainKeypadAreaKey,
          height: cellH * _tabletRows,
          width: double.infinity,
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: laidOut.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _tabletColumns,
              childAspectRatio: cellW / cellH,
            ),
            itemBuilder: (context, position) => laidOut[position],
          ),
        );
      },
    );
  }

  Widget _buildScientificGrid(bool isLandscape) {
    final buttons = _scientificButtons();
    return LayoutBuilder(
      builder:
          (context, gridConstraints) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              childAspectRatio: _gridAspectRatioFor(gridConstraints.maxWidth),
            ),
            itemCount: buttons.length,
            itemBuilder: (context, position) => buttons[position],
          ),
    );
  }

  Widget _buildNumberGrid(bool isLandscape) {
    return LayoutBuilder(
      builder:
          (context, gridConstraints) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: _buttons.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              childAspectRatio: _gridAspectRatioFor(gridConstraints.maxWidth),
            ),
            itemBuilder:
                (context, position) =>
                    _numberButtonAt(_phoneIndex(_phoneNumberOrder, position)),
          ),
    );
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
  // Grouped **column-major**: each pair of keys that belong together shares a
  // column, read top-then-bottom. That is what puts sin over asin and d/dx
  // over ∫ — a related pair is one thumb-width apart rather than a row apart.
  //
  //   col   1    2    3     4     5     6    7     8   9   10
  //   row1  i    x    √    sin    !    ⁿCᵣ  d/dx   ⎌   ⎏   ⌧
  //   row2  π    x²  |x|  asin   ⁿPᵣ   ∑     ∫     ·   ⓘ   ☰
  //         └ values ┘└trig┘└ discrete ┘└calc┘ └ history / utils ┘
  //
  // Reading across: constants and variables, then the operators applied to
  // them, then trigonometry, discrete maths, and calculus.
  //
  // The last three columns are the exception to the pairing. Undo, redo and
  // clear-all act on the whole document rather than the expression, so they
  // take the top-right corner as a block; help and settings navigate away
  // from the calculator entirely and take the bottom-right. The single blank
  // at (row 2, col 8) is what separates the two.
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
  }) {
    final Widget button = MyButton(
      buttontapped: onTap,
      buttonText: label,
      color: _kpButton,
      textColor: _kpButtonText,
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
    final Widget kI = _extrasAction('i', () {
      _activeController?.insertCharacter('i');
      widget.onUpdateMathEditor();
    });
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
    final Widget kX = _sciMenu(
      'x',
      onTap: () => _activeController?.insertCharacter('x'),
      menuItems: [
        _sciItem('y', () => _activeController?.insertCharacter('y')),
        _sciItem('z', () => _activeController?.insertCharacter('z')),
      ],
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
      variants: const [],
    );
    final Widget kComb = _extrasVariants(
      'ⁿCᵣ',
      wrap: () => _wrapper.wrapInCombination(),
      normal: () => _activeController?.insertCombination(),
      variants: const [],
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
    );
    final Widget kRedo = _extrasAction(
      '⎌',
      () => widget.onRedoAppState?.call(),
      mirrored: true,
    );
    final Widget kClearAll = _extrasAction('⌧', widget.onClearAllDisplays);
    // U+21EA, an upward arrow out of a tray: the plot leaving the app. It sits
    // in the slot that was empty, beside the other whole-app actions rather
    // than among the maths keys.
    final Widget kExport = _extrasAction('⇪', () {
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

    // The grid fills row-major, so this list is the two rows back to back.
    return <Widget>[
      // row 1
      kI, kX, kRoot, kSin, kFactorial, kComb, kDeriv, kUndo, kRedo, kClearAll,
      // row 2
      kPi, kSquare, kAbs, kAsin, kPerm, kSum, kIntegral, kExport, kHelp,
      kSettings,
    ];
  }

  Widget _buildExtrasGrid(bool isLandscape) {
    final buttons = _extrasButtons();
    return LayoutBuilder(
      builder:
          (context, gridConstraints) => GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: buttons.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _gridColumns,
              childAspectRatio: _gridAspectRatioFor(gridConstraints.maxWidth),
            ),
            itemBuilder: (context, position) => buttons[position],
          ),
    );
  }
}

class CustomPageScrollPhysics extends PageScrollPhysics {
  final double threshold; // 0.0 - 1.0

  const CustomPageScrollPhysics({
    this.threshold = 0.1, // 10% drag required
    super.parent,
  });

  @override
  CustomPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return CustomPageScrollPhysics(
      threshold: threshold,
      parent: buildParent(ancestor),
    );
  }
}

class CustomSnapPageView extends StatefulWidget {
  final PageController controller;
  final List<Widget> children;
  final ValueChanged<int>? onPageChanged;
  final double threshold; // fraction of page width to trigger snap

  const CustomSnapPageView({
    super.key,
    required this.controller,
    required this.children,
    this.onPageChanged,
    this.threshold = 0.05, // 5% of page width
  });

  @override
  State<CustomSnapPageView> createState() => _CustomSnapPageViewState();
}

class _CustomSnapPageViewState extends State<CustomSnapPageView> {
  double? _dragStartPage;
  bool _isAnimating = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_isAnimating) return false;

        if (notification is ScrollStartNotification &&
            notification.dragDetails != null) {
          // User started dragging — record starting page
          _dragStartPage = widget.controller.page;
        }

        if (notification is ScrollUpdateNotification &&
            notification.dragDetails != null &&
            _dragStartPage != null) {
          final currentPage = widget.controller.page!;
          final delta = currentPage - _dragStartPage!;

          if (delta.abs() > widget.threshold) {
            // Determine target page
            int targetPage;
            if (delta > 0) {
              targetPage = _dragStartPage!.ceil(); // swiped forward
            } else {
              targetPage = _dragStartPage!.floor(); // swiped backward
            }

            // Clamp to valid range
            targetPage = targetPage.clamp(0, widget.children.length - 1);

            _dragStartPage = null;
            _isAnimating = true;

            widget.controller
                .animateToPage(
                  targetPage,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                )
                .then((_) {
                  _isAnimating = false;
                });
          }
        }

        if (notification is ScrollEndNotification) {
          _dragStartPage = null;
        }

        return false;
      },
      child: PageView(
        controller: widget.controller,
        physics: const PageScrollPhysics(), // Keep default physics
        onPageChanged: widget.onPageChanged,
        padEnds: false,
        children: widget.children,
      ),
    );
  }
}

class EasySnapPageView extends StatefulWidget {
  final PageController controller;
  final List<Widget> children;
  final ValueChanged<int>? onPageChanged;
  final bool padEnds;
  final bool enableTransitions; // Add this

  const EasySnapPageView({
    super.key,
    required this.controller,
    required this.children,
    this.onPageChanged,
    this.padEnds = false,
    this.enableTransitions = true, // Default true for phone
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

        final currentPage = widget.controller.page?.round() ?? 0;
        final targetPage =
            delta > 0
                ? (currentPage - 1).clamp(0, widget.children.length - 1)
                : (currentPage + 1).clamp(0, widget.children.length - 1);

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
          itemCount: widget.children.length,
          itemBuilder: (context, index) {
            double page = 0;
            if (widget.controller.position.hasContentDimensions) {
              page = widget.controller.page ?? 0;
            }

            final double offset = (page - index).abs();
            final double scale = (1 - (offset * 0.15)).clamp(0.85, 1.0);
            final double opacity = (1 - (offset * 0.5)).clamp(0.5, 1.0);

            return Transform.scale(
              scale: scale,
              child: Opacity(opacity: opacity, child: widget.children[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildWithoutTransitions() {
    return PageView(
      controller: widget.controller,
      physics: const NeverScrollableScrollPhysics(),
      onPageChanged: widget.onPageChanged,
      padEnds: widget.padEnds,
      children: widget.children,
    );
  }
}
