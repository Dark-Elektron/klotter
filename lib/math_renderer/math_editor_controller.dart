import 'selection_manager.dart';
import 'renderer.dart';
import 'selection_wrapper.dart';
import '../math_engine/math_expression_serializer.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'expression_selection.dart';
import 'cursor.dart';

class MathEditorController extends ChangeNotifier {
  List<MathNode> expression = [LiteralNode()];
  EditorCursor get cursor => _cursorNotifier.value;

  // Cache for faster repeated taps
  NodeLayoutInfo? _lastTappedNode;

  set cursor(EditorCursor value) {
    if (_cursorNotifier.value != value) {
      _cursorNotifier.value = value;
    }
  }

  VoidCallback? onSelectionCleared;
  final Map<String, NodeLayoutInfo> _layoutRegistry = {};
  Map<String, NodeLayoutInfo> get layoutRegistry => _layoutRegistry;

  String? result = '';
  String expr = '';
  int _structureVersion = 0;
  int get structureVersion => _structureVersion;
  VoidCallback? onResultChanged;

  Map<String, ComplexNodeInfo> get complexNodeMap => _complexNodeMap;

  // Add this field
  late final SelectionManager _selectionManager = SelectionManager(this);

  // ============== UNDO/REDO ==============
  final List<EditorState> _undoStack = [];
  final List<EditorState> _redoStack = [];
  static const int _maxHistorySize = 50;
  bool _isUndoRedoOperation = false;

  /// Check if undo is available
  bool get canUndo => _undoStack.isNotEmpty;

  /// Check if redo is available
  bool get canRedo => _redoStack.isNotEmpty;

  late final SelectionWrapper selectionWrapper;
  final ValueNotifier<EditorCursor> _cursorNotifier = ValueNotifier(
    const EditorCursor(),
  );

  ValueNotifier<EditorCursor> get cursorListenable => _cursorNotifier;

  // Add this field
  final Map<String, NodeLayoutInfo> _layoutIndex = {};
  final CursorPaintNotifier cursorPaintNotifier = CursorPaintNotifier();

  Rect? _cachedContentBounds;
  bool _contentBoundsValid = false;

  MathEditorController() {
    selectionWrapper = SelectionWrapper(this);
  }

  @override
  void dispose() {
    _cursorNotifier.dispose();
    cursorPaintNotifier.dispose(); // Add this line
    super.dispose();
  }

  // Method to refresh display when settings change
  void refreshDisplay() {
    _structureVersion++;
    notifyListeners();
  }

  /// Save current state before making changes
  void saveStateForUndo() {
    if (_isUndoRedoOperation) return;

    // Skip a redundant snapshot when the expression is unchanged since the last
    // one. This collapses the double snapshots produced when insertCharacter and
    // a delegating handler (insertAns, _wrapSelectionInParenthesis, ...) both
    // save before any mutation, so one keystroke maps to one undo entry.
    if (_undoStack.isNotEmpty) {
      final lastExpr = MathExpressionSerializer.serialize(
        _undoStack.last.expression,
      );
      final currentExpr = MathExpressionSerializer.serialize(expression);
      if (lastExpr == currentExpr) return;
    }

    _undoStack.add(EditorState.capture(expression, cursor));

    // Limit stack size
    if (_undoStack.length > _maxHistorySize) {
      _undoStack.removeAt(0);
    }

    // Clear redo stack when new action is performed
    _redoStack.clear();
  }

  /// Undo the last action
  void undo() {
    if (!canUndo) return;

    _isUndoRedoOperation = true;

    // Save current state to redo stack
    _redoStack.add(EditorState.capture(expression, cursor));

    // Restore previous state
    EditorState previousState = _undoStack.removeLast();
    expression = previousState.expression;
    cursor = previousState.cursor;
    _rebuildComplexNodeMap();
    _structureVersion++;

    _isUndoRedoOperation = false;

    _scheduleCursorRecalc();
    notifyListeners();
    onResultChanged?.call();
  }

  /// Redo the last undone action
  void redo() {
    if (!canRedo) return;

    _isUndoRedoOperation = true;

    // Save current state to undo stack
    _undoStack.add(EditorState.capture(expression, cursor));

    // Restore redo state
    EditorState redoState = _redoStack.removeLast();
    expression = redoState.expression;
    cursor = redoState.cursor;
    _rebuildComplexNodeMap();
    _structureVersion++;

    _isUndoRedoOperation = false;

    _scheduleCursorRecalc();
    notifyListeners();
    onResultChanged?.call();
  }

  /// Clear undo/redo history
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  static String _mapToDisplayChar(String char) {
    switch (char) {
      case '+':
        return MathTextStyle.plusSign;
      case '-':
        return MathTextStyle.minusSign;
      case '*':
        return MathTextStyle.multiplySign; // Uses current setting
      default:
        return char;
    }
  }

  static bool _isWordBoundary(String char) {
    return char == '+' ||
        char == '-' ||
        char == '*' ||
        char == '/' ||
        char == '=' ||
        char == ' ' ||
        char == MathTextStyle.plusSign ||
        char == MathTextStyle.minusSign ||
        char == MathTextStyle.multiplyDot || // Check both
        char == MathTextStyle.multiplyTimes; // Check both
  }

  static bool _isNonMultiplyWordBoundary(String char) {
    return char == '+' ||
        char == '-' ||
        char == '/' ||
        char == '=' ||
        char == ' ' ||
        char == MathTextStyle.plusSign ||
        char == MathTextStyle.minusSign;
  }

  /// Checks if a character at the given position is a word boundary for fraction extraction.
  /// Unlike _isNonMultiplyWordBoundary, this treats minus sign as part of the
  /// number when it's part of scientific notation (e.g., 1ᴇ-17).
  static bool _isNonMultiplyWordBoundaryForFraction(String text, int index) {
    final char = text[index];

    // Standard word boundaries (excluding minus for special handling)
    if (char == '+' ||
        char == '/' ||
        char == '=' ||
        char == ' ' ||
        char == MathTextStyle.plusSign) {
      return true;
    }

    // Minus sign is NOT a boundary if it follows scientific E
    if (char == '-' || char == MathTextStyle.minusSign) {
      // Check if preceded by scientific E
      if (index > 0) {
        final prevChar = text[index - 1];
        if (prevChar == MathTextStyle.scientificE ||
            prevChar == 'E' ||
            prevChar == 'e') {
          return false; // Part of scientific notation, not a boundary
        }
      }
      return true; // Regular minus sign is a boundary
    }

    return false;
  }

  String _makeLayoutKey(String? parentId, String? path, int index) {
    return '${parentId ?? 'root'}:${path ?? 'root'}:$index';
  }

  void registerNodeLayout(NodeLayoutInfo info) {
    _layoutRegistry[info.node.id] = info;
    _layoutIndex[_makeLayoutKey(info.parentId, info.path, info.index)] = info;

    _tryUpdateCursorRectFor(info);
  }

  void registerComplexNodeLayout(ComplexNodeInfo info) {
    _complexNodeMap[info.node.id] = info;
  }

  void clearLayoutRegistry() {
    _layoutRegistry.clear();
    _layoutIndex.clear();
    _complexNodeMap.clear();
    _lastTappedNode = null;
    _contentBoundsValid = false;
    _cachedContentBounds = null;
  }

  void _tryUpdateCursorRectFor(NodeLayoutInfo info) {
    final cursor = _cursorNotifier.value;

    if (info.parentId != cursor.parentId ||
        info.path != cursor.path ||
        info.index != cursor.index) {
      return;
    }

    final text = info.node.text;
    final charIndex = cursor.subIndex.clamp(0, text.length);
    double cursorX;

    if (text.isEmpty) {
      cursorX = info.rect.left;
    } else {
      if (info.renderParagraph != null && info.renderParagraph!.attached) {
        final displayIndex = MathTextStyle.logicalToDisplayIndex(
          text,
          charIndex,
          forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
        );
        final displayText = info.displayText; // Use cached display text
        final offset = info.renderParagraph!.getOffsetForCaret(
          TextPosition(offset: displayIndex.clamp(0, displayText.length)),
          Rect.zero,
        );
        cursorX = info.rect.left + offset.dx;
      } else {
        cursorX =
            info.rect.left +
            MathTextStyle.getCursorOffset(
              text,
              charIndex,
              info.fontSize,
              info.textScaler,
              forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
            );
      }
    }

    cursorPaintNotifier.updateRectDirect(
      Rect.fromLTWH(cursorX, info.rect.top, 2, info.rect.height),
    );
  }

  double getContentWidth() {
    if (_layoutRegistry.isEmpty) return 0;

    double minX = double.infinity;
    double maxX = double.negativeInfinity;

    for (final info in _layoutRegistry.values) {
      minX = math.min(minX, info.rect.left);
      maxX = math.max(maxX, info.rect.right);
    }

    if (minX == double.infinity) return 0;
    return maxX - minX;
  }

  static bool _isSerializedDigit(String char) {
    return char.isNotEmpty && '0123456789.'.contains(char);
  }

  void _notifyStructureChanged() {
    _structureVersion++;
    _rebuildComplexNodeMap();
    notifyListeners();
    // Remove any postFrameCallback here - let registerNodeLayout handle cursor rect
  }

  void _scheduleCursorRecalc() {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        recalculateCursorRect();
      });
    } catch (_) {
      // If binding isn't available (unit tests), skip scheduling.
    }
  }

  void setCursor(EditorCursor c) {
    cursor = c;
    notifyListeners();
  }

  void tapAt(Offset position) {
    if (_layoutRegistry.isEmpty) return;

    // Fast check: is it the same as last time?
    if (_lastTappedNode != null && _lastTappedNode!.rect.contains(position)) {
      _processTapAtNode(_lastTappedNode!, position);
      return;
    }

    NodeLayoutInfo? bestContain;
    NodeLayoutInfo? bestNearest;
    double minDistanceSq = double.infinity;

    // Single pass for both containment and distance
    for (final info in _layoutRegistry.values) {
      if (info.rect.contains(position)) {
        bestContain = info;
        break; // Found it!
      }

      // Proximity fallback
      final dx = position.dx - info.rect.center.dx;
      final dy = position.dy - info.rect.center.dy;
      final distSq = dx * dx + dy * dy;
      if (distSq < minDistanceSq) {
        minDistanceSq = distSq;
        bestNearest = info;
      }
    }

    final targetNode = bestContain ?? bestNearest;
    if (targetNode != null) {
      _processTapAtNode(targetNode, position);
    }
  }

  void _processTapAtNode(NodeLayoutInfo info, Offset position) {
    _lastTappedNode = info;
    final text = info.node.text;
    int charIndex;
    double cursorX;

    if (text.isEmpty) {
      charIndex = 0;
      cursorX = info.rect.left;
    } else {
      final relativeX = position.dx - info.rect.left;

      if (info.renderParagraph != null && info.renderParagraph!.attached) {
        final pos = info.renderParagraph!.getPositionForOffset(
          Offset(relativeX, info.fontSize / 2),
        );

        final displayText = info.displayText;
        final displayOffset = pos.offset.clamp(0, displayText.length);
        charIndex = MathTextStyle.displayToLogicalIndex(
          text,
          displayOffset,
          forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
        );

        final cursorDisplayIndex = MathTextStyle.logicalToDisplayIndex(
          text,
          charIndex,
          forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
        );
        final offset = info.renderParagraph!.getOffsetForCaret(
          TextPosition(offset: cursorDisplayIndex.clamp(0, displayText.length)),
          Rect.zero,
        );
        cursorX = info.rect.left + offset.dx;
      } else {
        charIndex = MathTextStyle.getCharIndexForOffset(
          text,
          relativeX,
          info.fontSize,
          info.textScaler,
          forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
        );
        cursorX =
            info.rect.left +
            MathTextStyle.getCursorOffset(
              text,
              charIndex,
              info.fontSize,
              info.textScaler,
              forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
            );
      }
    }

    final currentCursor = _cursorNotifier.value;
    if (currentCursor.parentId == info.parentId &&
        currentCursor.path == info.path &&
        currentCursor.index == info.index &&
        currentCursor.subIndex == charIndex) {
      return;
    }

    _cursorNotifier.value = EditorCursor(
      parentId: info.parentId,
      path: info.path,
      index: info.index,
      subIndex: charIndex,
    );

    cursorPaintNotifier.updateRectDirect(
      Rect.fromLTWH(cursorX, info.rect.top, 2, info.rect.height),
    );
  }

  void moveCursorToStartWithRect() {
    if (_layoutRegistry.isEmpty) {
      return;
    }

    // Find the leftmost literal node
    NodeLayoutInfo? leftmostInfo;
    double minLeft = double.infinity;

    for (final info in _layoutRegistry.values) {
      if (info.rect.left < minLeft) {
        minLeft = info.rect.left;
        leftmostInfo = info;
      }
    }

    if (leftmostInfo == null) {
      return;
    }

    final newCursor = EditorCursor(
      parentId: leftmostInfo.parentId,
      path: leftmostInfo.path,
      index: leftmostInfo.index,
      subIndex: 0,
    );

    _cursorNotifier.value = newCursor;

    final newRect = Rect.fromLTWH(
      leftmostInfo.rect.left,
      leftmostInfo.rect.top,
      2,
      leftmostInfo.rect.height,
    );

    cursorPaintNotifier.updateRectDirect(newRect);
  }

  void moveCursorToEndWithRect() {
    if (_layoutRegistry.isEmpty) return;

    // Find the rightmost literal node
    NodeLayoutInfo? rightmostInfo;
    double maxRight = double.negativeInfinity;

    for (final info in _layoutRegistry.values) {
      if (info.rect.right > maxRight) {
        maxRight = info.rect.right;
        rightmostInfo = info;
      }
    }

    if (rightmostInfo == null) return;

    final text = rightmostInfo.node.text;
    final charIndex = text.length;

    double cursorX;
    if (text.isEmpty) {
      cursorX = rightmostInfo.rect.left;
    } else {
      if (rightmostInfo.renderParagraph != null &&
          rightmostInfo.renderParagraph!.attached) {
        final displayIndex = MathTextStyle.logicalToDisplayIndex(
          text,
          charIndex,
          forceLeadingOperatorPadding:
              rightmostInfo.forceLeadingOperatorPadding,
        );
        final displayText = rightmostInfo.displayText;
        final offset = rightmostInfo.renderParagraph!.getOffsetForCaret(
          TextPosition(offset: displayIndex.clamp(0, displayText.length)),
          Rect.zero,
        );
        cursorX = rightmostInfo.rect.left + offset.dx;
      } else {
        cursorX =
            rightmostInfo.rect.left +
            MathTextStyle.getCursorOffset(
              text,
              charIndex,
              rightmostInfo.fontSize,
              rightmostInfo.textScaler,
              forceLeadingOperatorPadding:
                  rightmostInfo.forceLeadingOperatorPadding,
            );
      }
    }

    _cursorNotifier.value = EditorCursor(
      parentId: rightmostInfo.parentId,
      path: rightmostInfo.path,
      index: rightmostInfo.index,
      subIndex: charIndex,
    );

    cursorPaintNotifier.updateRectDirect(
      Rect.fromLTWH(
        cursorX,
        rightmostInfo.rect.top,
        2,
        rightmostInfo.rect.height,
      ),
    );
  }

  void insertCharacter(String char) {
    // ')' only moves the cursor out of a parenthesis; it makes no structural
    // change, so it must not create an undo entry. Handle it before snapshotting.
    if (char == ')') {
      _exitParenthesis();
      return;
    }

    saveStateForUndo();
    if (char == '/') {
      _wrapIntoFraction();
      return;
    }

    if (char == '^') {
      _wrapIntoExponent();
      return;
    }

    if (char == '(' || char == '()') {
      _insertParenthesis();
      return;
    }

    if (char == 'ans') {
      insertAns();
      return;
    }

    // === NEW: Exit container nodes when typing operators ===
    if (_isOperator(char)) {
      _exitContainerIfNeeded();

      // Check for double multiply -> power conversion
      if (_isMultiplyChar(char)) {
        final node = _resolveCursorNode();
        if (node is LiteralNode && cursor.subIndex > 0) {
          final text = node.text;
          final prevChar = text[cursor.subIndex - 1];
          if (_isMultiplyChar(prevChar)) {
            // Delete the previous multiply sign and insert exponent instead
            node.text =
                text.substring(0, cursor.subIndex - 1) +
                text.substring(cursor.subIndex);
            cursor = cursor.copyWith(subIndex: cursor.subIndex - 1);
            _notifyStructureChanged();
            _wrapIntoExponent();
            return;
          }
        }
      }
    }
    // === END NEW ===

    final displayChar = _mapToDisplayChar(char);
    _updateLiteralAtCursor((node) {
      node.text =
          node.text.substring(0, cursor.subIndex) +
          displayChar +
          node.text.substring(cursor.subIndex);
      cursor = cursor.copyWith(subIndex: cursor.subIndex + 1);
    });
    _notifyStructureChanged();

    onCalculate();

    // DEBUG: Print structure after each character
    // debugPrintExpression();
  }

  /// Set expression from loaded data
  void setExpression(List<MathNode> nodes) {
    expression = nodes;
    _rebuildComplexNodeMap(); // Add this line

    expression = nodes.isNotEmpty ? nodes : [LiteralNode()];
    expr = MathExpressionSerializer.serialize(expression);
    _structureVersion++;
    // Position cursor at end of root expression
    int lastIndex = expression.length - 1;
    MathNode lastNode = expression[lastIndex];

    int subIndex = 0;
    if (lastNode is LiteralNode) {
      subIndex = lastNode.text.length;
    }

    cursor = EditorCursor(
      parentId: null,
      path: null,
      index: lastIndex,
      subIndex: subIndex,
    );
    notifyListeners();
  }

  // === HELPER METHODS ===

  bool _isOperator(String char) {
    return char == '+' ||
        char == '-' ||
        char == '*' ||
        char == '=' ||
        char == MathTextStyle.plusSign ||
        char == MathTextStyle.minusSign ||
        char == MathTextStyle.multiplySign;
  }

  bool _isMultiplyChar(String char) {
    return char == '*' ||
        char == MathTextStyle.multiplyDot ||
        char == MathTextStyle.multiplyTimes;
  }

  void _exitContainerIfNeeded() {
    // Keep exiting until we're at root or in a "content" container like ParenthesisNode
    while (cursor.parentId != null) {
      final parent = _findNode(expression, cursor.parentId!);

      // Stay inside parentheses - operators are valid there
      if (parent is ParenthesisNode) {
        break;
      }

      // If parent not found, break
      if (parent == null) break;

      // Stay inside fraction numerator/denominator - operators are valid there
      if (parent is FractionNode) {
        break;
      }
      if (parent is SummationNode ||
          parent is DerivativeNode ||
          parent is IntegralNode ||
          parent is ProductNode) {
        break;
      }

      // Exit AnsNode, TrigNode, RootNode, LogNode, etc.
      if (parent
          is AnsNode //||
      // parent is TrigNode ||
      // parent is RootNode ||
      // parent is LogNode ||
      // parent is PermutationNode ||
      // parent is CombinationNode ||
      // parent is ExponentNode
      ) {
        final EditorCursor before = cursor;
        _moveCursorAfterNode(parent.id);
        // Safety: if the cursor could not be repositioned (e.g. no valid
        // position after the node), stop instead of looping forever.
        if (cursor.parentId == before.parentId &&
            cursor.path == before.path &&
            cursor.index == before.index &&
            cursor.subIndex == before.subIndex) {
          break;
        }
        continue;
      }

      break;
    }
  }

  void _moveCursorAfterNode(String nodeId) {
    _findAndPositionAfter(expression, nodeId, null, null);
    notifyListeners();
  }

  // ============= NODE INSERT FUNCTIONS ==============
  void insertSquare() {
    saveStateForUndo();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorClick = cursor.subIndex;

    // Find the operand before cursor (number or variable to square)
    int operandStart = cursorClick;
    bool isDigit(String char) {
      final int code = char.codeUnitAt(0);
      return code >= 48 && code <= 57;
    }

    bool isLetter(String char) {
      final int code = char.codeUnitAt(0);
      return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }

    while (operandStart > 0 && !_isWordBoundary(text[operandStart - 1])) {
      if (operandStart < text.length) {
        final String prevChar = text[operandStart - 1];
        final String nextChar = text[operandStart];
        if (isDigit(prevChar) && isLetter(nextChar)) {
          break;
        }
        if (isLetter(prevChar) && isLetter(nextChar)) {
          break;
        }
      }
      operandStart--;
    }

    String baseText = text.substring(operandStart, cursorClick);
    String prefixText = text.substring(0, operandStart);
    bool isAllLetters(String value) {
      for (int i = 0; i < value.length; i++) {
        if (!isLetter(value[i])) return false;
      }
      return value.isNotEmpty;
    }

    if (baseText.length > 1 && isAllLetters(baseText)) {
      prefixText += baseText.substring(0, baseText.length - 1);
      baseText = baseText.substring(baseText.length - 1);
    }
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    // Handle case where base is a previous node (like a fraction or parenthesis)
    if (baseText.isEmpty && operandStart == 0 && actualIndex > 0) {
      final chainResult = _collectMultiplicationChain(
        siblings,
        actualIndex - 1,
      );
      if (chainResult.nodes.isNotEmpty) {
        if (chainResult.prefixToKeep != null &&
            chainResult.prefixNodeIndex != null) {
          (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
              chainResult.prefixToKeep!;
        }
        int removeStart =
            chainResult.prefixNodeIndex != null
                ? chainResult.prefixNodeIndex! + 1
                : chainResult.removeFromIndex;
        int removeEnd = actualIndex - 1;
        for (int j = removeEnd; j >= removeStart; j--) {
          siblings.removeAt(j);
        }
        int newCurrentIndex = removeStart;
        current.text = text.substring(cursorClick);

        // Create exponent with power = 2
        final exp = ExponentNode(
          base: chainResult.nodes,
          power: [LiteralNode(text: "2")],
        );
        siblings.insert(newCurrentIndex, exp);

        // Move cursor after the exponent
        cursor = EditorCursor(
          parentId: cursor.parentId,
          path: cursor.path,
          index: newCurrentIndex + 1,
          subIndex: 0,
        );
        _notifyStructureChanged();
        onCalculate();
        return;
      }
    }

    current.text = prefixText;

    // Create exponent with power = 2
    final exp = ExponentNode(
      base: [LiteralNode(text: baseText)],
      power: [LiteralNode(text: "2")],
    );
    final tail = LiteralNode(text: text.substring(cursorClick));

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, exp);
      siblings.insert(actualIndex + 2, tail);

      // Move cursor after the exponent (not inside power)
      cursor = EditorCursor(
        parentId: cursor.parentId,
        path: cursor.path,
        index: actualIndex + 2,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
    onCalculate();
  }

  void insertConstant(String constant) {
    saveStateForUndo();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    final node = ConstantNode(constant);

    if (actualIndex >= 0) {
      if (after.isNotEmpty) {
        // We are in the middle or at the start. Update current and insert constant + new tail.
        current.text = before;
        final tail = LiteralNode(text: after);
        siblings.insert(actualIndex + 1, node);
        siblings.insert(actualIndex + 2, tail);
        cursor = EditorCursor(
          parentId: cursor.parentId,
          path: cursor.path,
          index: actualIndex + 2,
          subIndex: 0,
        );
      } else {
        // We are at the very end of the literal (or it was empty).
        // If 'before' is not empty, we keep it and just apppend the constant.
        // If 'before' IS empty, we replace the LiteralNode with the ConstantNode.
        if (before.isNotEmpty) {
          current.text = before;
          siblings.insert(actualIndex + 1, node);
          // Insert a NEW empty LiteralNode after the constant so the user has somewhere to type
          final tail = LiteralNode(text: "");
          siblings.insert(actualIndex + 2, tail);
          cursor = EditorCursor(
            parentId: cursor.parentId,
            path: cursor.path,
            index: actualIndex + 2,
            subIndex: 0,
          );
        } else {
          // Both before and after are empty. Replace current Literal with Constant.
          final prevNode = actualIndex > 0 ? siblings[actualIndex - 1] : null;
          if (prevNode is ConstantNode || prevNode is UnitVectorNode) {
            // Keep the empty literal as a spacer so the cursor can sit between constants.
            siblings.insert(actualIndex + 1, node);
            // Still need an empty literal after it to allow further typing
            final tail = LiteralNode(text: "");
            siblings.insert(actualIndex + 2, tail);
            cursor = EditorCursor(
              parentId: cursor.parentId,
              path: cursor.path,
              index: actualIndex + 2,
              subIndex: 0,
            );
          } else {
            siblings[actualIndex] = node;
            // Still need an empty literal after it to allow further typing
            final tail = LiteralNode(text: "");
            siblings.insert(actualIndex + 1, tail);
            cursor = EditorCursor(
              parentId: cursor.parentId,
              path: cursor.path,
              index: actualIndex + 1,
              subIndex: 0,
            );
          }
        }
      }
    }
    _notifyStructureChanged();
    onCalculate();
  }

  void insertUnitVector(String axis) {
    saveStateForUndo();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    final node = UnitVectorNode(axis);

    if (actualIndex >= 0) {
      if (after.isNotEmpty) {
        current.text = before;
        final tail = LiteralNode(text: after);
        siblings.insert(actualIndex + 1, node);
        siblings.insert(actualIndex + 2, tail);
        cursor = EditorCursor(
          parentId: cursor.parentId,
          path: cursor.path,
          index: actualIndex + 2,
          subIndex: 0,
        );
      } else {
        if (before.isNotEmpty) {
          current.text = before;
          siblings.insert(actualIndex + 1, node);
          final tail = LiteralNode(text: "");
          siblings.insert(actualIndex + 2, tail);
          cursor = EditorCursor(
            parentId: cursor.parentId,
            path: cursor.path,
            index: actualIndex + 2,
            subIndex: 0,
          );
        } else {
          final prevNode = actualIndex > 0 ? siblings[actualIndex - 1] : null;
          if (prevNode is ConstantNode || prevNode is UnitVectorNode) {
            siblings.insert(actualIndex + 1, node);
            final tail = LiteralNode(text: "");
            siblings.insert(actualIndex + 2, tail);
            cursor = EditorCursor(
              parentId: cursor.parentId,
              path: cursor.path,
              index: actualIndex + 2,
              subIndex: 0,
            );
          } else {
            siblings[actualIndex] = node;
            final tail = LiteralNode(text: "");
            siblings.insert(actualIndex + 1, tail);
            cursor = EditorCursor(
              parentId: cursor.parentId,
              path: cursor.path,
              index: actualIndex + 1,
              subIndex: 0,
            );
          }
        }
      }
    }
    _notifyStructureChanged();
    onCalculate();
  }

  void insertTrig(String function) {
    saveStateForUndo();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final trig = TrigNode(
      function: function,
      argument: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, trig);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: trig.id,
        path: 'arg',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertSquareRoot() {
    saveStateForUndo();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final root = RootNode(
      isSquareRoot: true,
      index: [LiteralNode(text: "2")],
      radicand: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, root);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: root.id,
        path: 'radicand',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertNthRoot() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final root = RootNode(
      isSquareRoot: false,
      index: [LiteralNode(text: "")],
      radicand: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, root);
      siblings.insert(actualIndex + 2, tail);
      // Start in the index field so user can type the root degree
      cursor = EditorCursor(
        parentId: root.id,
        path: 'index',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertLog10() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final log = LogNode(
      base: [LiteralNode(text: "10")], // Fixed base 10
      argument: [LiteralNode(text: "")],
      isNaturalLog: false,
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, log);
      siblings.insert(actualIndex + 2, tail);
      // Cursor goes to argument, not base
      cursor = EditorCursor(
        parentId: log.id,
        path: 'arg', // <-- Start in argument
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertLogN() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final log = LogNode(
      base: [LiteralNode(text: "")], // Empty base for user to fill
      argument: [LiteralNode(text: "")],
      isNaturalLog: false,
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, log);
      siblings.insert(actualIndex + 2, tail);
      // Cursor goes to base first
      cursor = EditorCursor(
        parentId: log.id,
        path: 'base', // <-- Start in base
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertNaturalLog() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final log = LogNode(argument: [LiteralNode(text: "")], isNaturalLog: true);
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, log);
      siblings.insert(actualIndex + 2, tail);
      // Go directly to argument
      cursor = EditorCursor(
        parentId: log.id,
        path: 'arg',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertAns() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final ans = AnsNode(index: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, ans);
      siblings.insert(actualIndex + 2, tail);
      // Move cursor to index field so user can type the reference number
      cursor = EditorCursor(
        parentId: ans.id,
        path: 'index',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void _insertParenthesis() {
    // If there's a selection, wrap it in parentheses
    if (hasSelection) {
      _wrapSelectionInParenthesis();
      return;
    }

    // Original cursor-based insertion
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    current.text = text.substring(0, cursorPos);
    final paren = ParenthesisNode(content: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: text.substring(cursorPos));

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, paren);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: paren.id,
        path: 'content',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void _wrapSelectionInParenthesis() {
    if (!hasSelection) return;
    saveStateForUndo();

    final norm = _selection!.normalized;
    final siblings = _resolveNodeListForSelection(
      norm.start.parentId,
      norm.start.path,
    );
    if (siblings == null) return;

    // Collect the selected nodes
    List<MathNode> selectedNodes = [];

    for (
      int i = norm.start.nodeIndex;
      i <= norm.end.nodeIndex && i < siblings.length;
      i++
    ) {
      final node = siblings[i];

      if (i == norm.start.nodeIndex && i == norm.end.nodeIndex) {
        // Single node selection
        if (node is LiteralNode) {
          final startIdx = norm.start.charIndex.clamp(0, node.text.length);
          final endIdx = norm.end.charIndex.clamp(0, node.text.length);
          final selectedText = node.text.substring(startIdx, endIdx);
          if (selectedText.isNotEmpty) {
            selectedNodes.add(LiteralNode(text: selectedText));
          }
        } else {
          // Composite node - add the whole thing
          selectedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else if (i == norm.start.nodeIndex) {
        // First node in multi-node selection
        if (node is LiteralNode) {
          final startIdx = norm.start.charIndex.clamp(0, node.text.length);
          final selectedText = node.text.substring(startIdx);
          if (selectedText.isNotEmpty) {
            selectedNodes.add(LiteralNode(text: selectedText));
          }
        } else {
          selectedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else if (i == norm.end.nodeIndex) {
        // Last node in multi-node selection
        if (node is LiteralNode) {
          final endIdx = norm.end.charIndex.clamp(0, node.text.length);
          final selectedText = node.text.substring(0, endIdx);
          if (selectedText.isNotEmpty) {
            selectedNodes.add(LiteralNode(text: selectedText));
          }
        } else {
          selectedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else {
        // Middle node - take the whole thing
        selectedNodes.add(MathClipboard.deepCopyNode(node));
      }
    }

    // If nothing was selected, just insert empty parenthesis
    if (selectedNodes.isEmpty) {
      selectedNodes.add(LiteralNode(text: ""));
    }

    // Get text before and after selection BEFORE removing nodes
    String textBefore = '';
    String textAfter = '';

    final firstNode = siblings[norm.start.nodeIndex];
    if (firstNode is LiteralNode) {
      textBefore = firstNode.text.substring(
        0,
        norm.start.charIndex.clamp(0, firstNode.text.length),
      );
    }

    // Check bounds before accessing lastNode
    if (norm.end.nodeIndex < siblings.length) {
      final lastNode = siblings[norm.end.nodeIndex];
      if (lastNode is LiteralNode) {
        textAfter = lastNode.text.substring(
          norm.end.charIndex.clamp(0, lastNode.text.length),
        );
      }
    }

    // Remove selected nodes (from end to start)
    for (int i = norm.end.nodeIndex; i >= norm.start.nodeIndex; i--) {
      if (i < siblings.length) {
        siblings.removeAt(i);
      }
    }

    // Create the parenthesis node with selected content
    _ensureLiteralEdges(selectedNodes);

    final paren = ParenthesisNode(content: selectedNodes);

    // Insert: textBefore literal, parenthesis, textAfter literal
    // We unconditionally insert literals to ensure stable structure (Literal-Node-Literal pattern)
    int insertIndex = norm.start.nodeIndex;

    // 1. Insert textBefore
    siblings.insert(insertIndex, LiteralNode(text: textBefore));
    insertIndex++;

    // 2. Insert the parenthesis
    siblings.insert(insertIndex, paren);
    int parenIndex = insertIndex;
    insertIndex++;

    // 3. Insert textAfter
    siblings.insert(insertIndex, LiteralNode(text: textAfter));

    // Position cursor after the parenthesis (at start of next literal)
    cursor = EditorCursor(
      parentId: norm.start.parentId,
      path: norm.start.path,
      index: parenIndex + 1,
      subIndex: 0,
    );

    // Clear selection
    _selection = null;
    onSelectionCleared?.call();

    _notifyStructureChanged();
  }

  void insertPermutation() {
    saveStateForUndo();

    // Check if we're inside a container that should be wrapped entirely
    if (cursor.parentId != null) {
      final parent = _findNode(expression, cursor.parentId!);

      // If inside a parenthesis, wrap the entire parenthesis as n
      if (parent is ParenthesisNode) {
        _wrapParenthesisNodeIntoPermutation(parent);
        return;
      }
    }

    // Check if previous node is a parenthesis or complex node
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    // If cursor is at start of literal and previous node exists
    if (cursorPos == 0 && actualIndex > 0) {
      final prevNode = siblings[actualIndex - 1];

      // If previous node is a ParenthesisNode, wrap it
      if (prevNode is ParenthesisNode) {
        _wrapPreviousNodeIntoPermutation(
          prevNode,
          actualIndex,
          siblings,
          current,
        );
        return;
      }

      // If previous node is another complex node (fraction, trig, etc.)
      if (prevNode is FractionNode ||
          prevNode is TrigNode ||
          prevNode is RootNode ||
          prevNode is LogNode ||
          prevNode is ExponentNode ||
          prevNode is AnsNode) {
        _wrapPreviousNodeIntoPermutation(
          prevNode,
          actualIndex,
          siblings,
          current,
        );
        return;
      }
    }

    // Check if there's a number before cursor to use as n
    int operandStart = cursorPos;
    while (operandStart > 0 && _isSerializedDigit(text[operandStart - 1])) {
      operandStart--;
    }

    String nText = text.substring(operandStart, cursorPos);
    String before = text.substring(0, operandStart);
    String after = text.substring(cursorPos);

    // If no number but there's a previous complex node
    if (nText.isEmpty && operandStart == 0 && actualIndex > 0) {
      final chainResult = _collectMultiplicationChain(
        siblings,
        actualIndex - 1,
      );
      if (chainResult.nodes.isNotEmpty) {
        if (chainResult.prefixToKeep != null &&
            chainResult.prefixNodeIndex != null) {
          (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
              chainResult.prefixToKeep!;
        }

        int removeStart =
            chainResult.prefixNodeIndex != null
                ? chainResult.prefixNodeIndex! + 1
                : chainResult.removeFromIndex;
        int removeEnd = actualIndex - 1;

        for (int j = removeEnd; j >= removeStart; j--) {
          siblings.removeAt(j);
        }

        int newCurrentIndex = removeStart;
        current.text = after;

        final perm = PermutationNode(
          n: chainResult.nodes,
          r: [LiteralNode(text: "")],
        );
        siblings.insert(newCurrentIndex, perm);

        cursor = EditorCursor(
          parentId: perm.id,
          path: 'r',
          index: 0,
          subIndex: 0,
        );
        _notifyStructureChanged();
        return;
      }
    }

    current.text = before;

    final perm = PermutationNode(
      n: [LiteralNode(text: nText)],
      r: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, perm);
      siblings.insert(actualIndex + 2, tail);

      cursor = EditorCursor(
        parentId: perm.id,
        path: nText.isEmpty ? 'n' : 'r',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertCombination() {
    saveStateForUndo();

    // Check if we're inside a container that should be wrapped entirely
    if (cursor.parentId != null) {
      final parent = _findNode(expression, cursor.parentId!);

      if (parent is ParenthesisNode) {
        _wrapParenthesisNodeIntoCombination(parent);
        return;
      }
    }

    // Check if previous node is a parenthesis or complex node
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    // If cursor is at start of literal and previous node exists
    if (cursorPos == 0 && actualIndex > 0) {
      final prevNode = siblings[actualIndex - 1];

      if (prevNode is ParenthesisNode ||
          prevNode is FractionNode ||
          prevNode is TrigNode ||
          prevNode is RootNode ||
          prevNode is LogNode ||
          prevNode is ExponentNode ||
          prevNode is AnsNode) {
        _wrapPreviousNodeIntoCombination(
          prevNode,
          actualIndex,
          siblings,
          current,
        );
        return;
      }
    }

    // Check if there's a number before cursor to use as n
    int operandStart = cursorPos;
    while (operandStart > 0 && _isSerializedDigit(text[operandStart - 1])) {
      operandStart--;
    }

    String nText = text.substring(operandStart, cursorPos);
    String before = text.substring(0, operandStart);
    String after = text.substring(cursorPos);

    if (nText.isEmpty && operandStart == 0 && actualIndex > 0) {
      final chainResult = _collectMultiplicationChain(
        siblings,
        actualIndex - 1,
      );
      if (chainResult.nodes.isNotEmpty) {
        if (chainResult.prefixToKeep != null &&
            chainResult.prefixNodeIndex != null) {
          (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
              chainResult.prefixToKeep!;
        }

        int removeStart =
            chainResult.prefixNodeIndex != null
                ? chainResult.prefixNodeIndex! + 1
                : chainResult.removeFromIndex;
        int removeEnd = actualIndex - 1;

        for (int j = removeEnd; j >= removeStart; j--) {
          siblings.removeAt(j);
        }

        int newCurrentIndex = removeStart;
        current.text = after;

        final comb = CombinationNode(
          n: chainResult.nodes,
          r: [LiteralNode(text: "")],
        );
        siblings.insert(newCurrentIndex, comb);

        cursor = EditorCursor(
          parentId: comb.id,
          path: 'r',
          index: 0,
          subIndex: 0,
        );
        _notifyStructureChanged();
        return;
      }
    }

    current.text = before;

    final comb = CombinationNode(
      n: [LiteralNode(text: nText)],
      r: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, comb);
      siblings.insert(actualIndex + 2, tail);

      cursor = EditorCursor(
        parentId: comb.id,
        path: nText.isEmpty ? 'n' : 'r',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
  }

  void insertSummation() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final sumNode = SummationNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: [LiteralNode(text: '')],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, sumNode);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: sumNode.id,
        path: 'body',
        index: 0,
        subIndex: 0,
      );
    }

    _notifyStructureChanged();
    onCalculate();
  }

  void insertProduct() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final prodNode = ProductNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: [LiteralNode(text: '')],
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, prodNode);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: prodNode.id,
        path: 'body',
        index: 0,
        subIndex: 0,
      );
    }

    _notifyStructureChanged();
    onCalculate();
  }

  void insertDerivative({bool definite = false}) {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final diffNode = DerivativeNode(
      variable: [LiteralNode(text: 'x')],
      at: [LiteralNode(text: '')],
      body: [LiteralNode(text: '')],
      isDefinite: definite,
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, diffNode);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: diffNode.id,
        path: 'body',
        index: 0,
        subIndex: 0,
      );
    }

    _notifyStructureChanged();
    onCalculate();
  }

  void insertIntegral({bool definite = false}) {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final intNode = IntegralNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: [LiteralNode(text: '')],
      isDefinite: definite,
    );
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, intNode);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: intNode.id,
        path: 'body',
        index: 0,
        subIndex: 0,
      );
    }

    _notifyStructureChanged();
    onCalculate();
  }

  void insertNewline() {
    saveStateForUndo();
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    current.text = before;

    final newline = NewlineNode();
    final tail = LiteralNode(text: after);

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, newline);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: cursor.parentId,
        path: cursor.path,
        index: actualIndex + 2,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
    onCalculate();
  }

  /// Checks if there's content at cursor position that could become a numerator
  bool _hasContentForNumerator() {
    // final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();

    // If there are previous nodes in the sibling list, there's content
    if (cursor.index > 0) return true;

    // If current node is not a literal, there might be content
    if (current is! LiteralNode) return true;

    String text = current.text;
    int cursorClick = cursor.subIndex;

    // Find operand start
    int operandStart = cursorClick;
    while (operandStart > 0 &&
        !_isNonMultiplyWordBoundary(text[operandStart - 1])) {
      operandStart--;
    }

    String numeratorText = text.substring(operandStart, cursorClick);

    // If there's text that could be numerator, we have content
    if (numeratorText.isNotEmpty) return true;

    return false;
  }

  /// Wraps Into Node Funcions
  /// Wraps an entire ParenthesisNode into a fraction's numerator
  void _wrapParenthesisNodeIntoFraction(ParenthesisNode paren) {
    final parentInfo = _findParentListOf(paren.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final parenIndex = parentInfo.index;

    String afterText = '';
    if (parenIndex + 1 < parentList.length &&
        parentList[parenIndex + 1] is LiteralNode) {
      afterText = (parentList[parenIndex + 1] as LiteralNode).text;
      parentList.removeAt(parenIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = parenIndex;

    if (parenIndex > 0) {
      final prevNode = parentList[parenIndex - 1];
      if (prevNode is LiteralNode &&
          (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
              (prevNode.text.isNotEmpty &&
                  _isDigitOrLetter(prevNode.text[prevNode.text.length - 1])))) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          parenIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(paren);

    for (int j = parenIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire PermutationNode into a fraction's numerator
  void _wrapPermutationNodeIntoFraction(PermutationNode perm) {
    final parentInfo = _findParentListOf(perm.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final permIndex = parentInfo.index;

    String afterText = '';
    if (permIndex + 1 < parentList.length &&
        parentList[permIndex + 1] is LiteralNode) {
      afterText = (parentList[permIndex + 1] as LiteralNode).text;
      parentList.removeAt(permIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = permIndex;

    if (permIndex > 0) {
      final prevNode = parentList[permIndex - 1];
      if (prevNode is LiteralNode &&
          (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
              (prevNode.text.isNotEmpty &&
                  _isDigitOrLetter(prevNode.text[prevNode.text.length - 1])))) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          permIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(perm);

    for (int j = permIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire CombinationNode into a fraction's numerator
  void _wrapCombinationNodeIntoFraction(CombinationNode comb) {
    final parentInfo = _findParentListOf(comb.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final combIndex = parentInfo.index;

    String afterText = '';
    if (combIndex + 1 < parentList.length &&
        parentList[combIndex + 1] is LiteralNode) {
      afterText = (parentList[combIndex + 1] as LiteralNode).text;
      parentList.removeAt(combIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = combIndex;

    if (combIndex > 0) {
      final prevNode = parentList[combIndex - 1];
      if (prevNode is LiteralNode &&
          (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
              (prevNode.text.isNotEmpty &&
                  _isDigitOrLetter(prevNode.text[prevNode.text.length - 1])))) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          combIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(comb);

    for (int j = combIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  void _wrapIntoExponent() {
    // Check if we're inside an AnsNode - if so, wrap the whole AnsNode
    if (cursor.parentId != null) {
      final parent = _findNode(expression, cursor.parentId!);
      if (parent is AnsNode) {
        _wrapAnsNodeIntoExponent(parent);
        return;
      }
    }
    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorClick = cursor.subIndex;

    int operandStart = cursorClick;
    // Helper functions to identify character types
    bool isDigit(String char) {
      final int code = char.codeUnitAt(0);
      return code >= 48 && code <= 57;
    }

    bool isLetter(String char) {
      final int code = char.codeUnitAt(0);
      return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
    }

    // Scan backwards to find operand start, but stop at digit-letter boundary
    // This ensures "3x" splits at the boundary: "3" stays as coefficient, "x" becomes base
    while (operandStart > 0 && !_isWordBoundary(text[operandStart - 1])) {
      if (operandStart < text.length) {
        final String prevChar = text[operandStart - 1];
        final String nextChar = text[operandStart];
        if (isDigit(prevChar) && isLetter(nextChar)) {
          break;
        }
        if (isLetter(prevChar) && isLetter(nextChar)) {
          break;
        }
      }
      operandStart--;
    }

    String baseText = text.substring(operandStart, cursorClick);
    String prefixText = text.substring(0, operandStart);
    bool isAllLetters(String value) {
      for (int i = 0; i < value.length; i++) {
        if (!isLetter(value[i])) return false;
      }
      return value.isNotEmpty;
    }

    if (baseText.length > 1 && isAllLetters(baseText)) {
      prefixText += baseText.substring(0, baseText.length - 1);
      baseText = baseText.substring(baseText.length - 1);
    }
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    // A trailing postfix (factorial/degree/percent) belongs to the operand it
    // follows, so `(19+2)!` raised to a power wraps the whole `(19+2)!` as the
    // base rather than just the "!".
    final bool isPostfixBase =
        baseText.startsWith('!') ||
        baseText.startsWith('°') ||
        baseText.startsWith('%');

    if ((baseText.isEmpty || isPostfixBase) &&
        operandStart == 0 &&
        actualIndex > 0) {
      final chainResult = _collectMultiplicationChain(
        siblings,
        actualIndex - 1,
      );
      if (chainResult.nodes.isNotEmpty) {
        if (chainResult.prefixToKeep != null &&
            chainResult.prefixNodeIndex != null) {
          (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
              chainResult.prefixToKeep!;
        }
        int removeStart =
            chainResult.prefixNodeIndex != null
                ? chainResult.prefixNodeIndex! + 1
                : chainResult.removeFromIndex;
        int removeEnd = actualIndex - 1;
        for (int j = removeEnd; j >= removeStart; j--) {
          siblings.removeAt(j);
        }
        int newCurrentIndex = removeStart;
        current.text = text.substring(cursorClick);
        final List<MathNode> baseNodes = List<MathNode>.from(chainResult.nodes);
        if (isPostfixBase) {
          baseNodes.add(LiteralNode(text: baseText));
        }
        _ensureLiteralEdges(baseNodes);
        final exp = ExponentNode(
          base: baseNodes,
          power: [LiteralNode(text: "")],
        );
        siblings.insert(newCurrentIndex, exp);
        cursor = EditorCursor(
          parentId: exp.id,
          path: 'pow',
          index: 0,
          subIndex: 0,
        );
        _notifyStructureChanged();
        _scheduleCursorRecalc();
        return;
      }
    }

    current.text = prefixText;
    final exp = ExponentNode(
      base: [LiteralNode(text: baseText)],
      power: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: text.substring(cursorClick));

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, exp);
      siblings.insert(actualIndex + 2, tail);
      cursor = EditorCursor(
        parentId: exp.id,
        path: 'pow',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
    _scheduleCursorRecalc();
  }

  /// Wraps an entire AnsNode into a fraction's numerator
  void _wrapAnsNodeIntoFraction(AnsNode ans) {
    final parentInfo = _findParentListOf(ans.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final ansIndex = parentInfo.index;

    // Get the node after AnsNode (if exists) to preserve text after
    String afterText = '';
    if (ansIndex + 1 < parentList.length &&
        parentList[ansIndex + 1] is LiteralNode) {
      afterText = (parentList[ansIndex + 1] as LiteralNode).text;
      parentList.removeAt(ansIndex + 1);
    }

    // ========== NEW: Collect multiplication chain before this AnsNode ==========
    List<MathNode> numeratorNodes = [];
    int removeStartIndex = ansIndex;

    if (ansIndex > 0) {
      // Check if there's a multiply sign before this AnsNode
      final prevNode = parentList[ansIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        // Collect the chain
        final chainResult = _collectMultiplicationChain(
          parentList,
          ansIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          // Handle prefix
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }

          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;

          // Add chain nodes to numerator
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    // Add the current AnsNode to numerator
    numeratorNodes.add(ans);

    // Remove all collected nodes (from chain start to ansIndex)
    for (int j = ansIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    // ========== END NEW ==========

    // Create fraction with collected nodes as numerator
    final frac = FractionNode(
      num: numeratorNodes, // ← Now includes the whole chain!
      den: [LiteralNode(text: "")],
    );

    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire LogNode into a fraction's numerator
  void _wrapLogNodeIntoFraction(LogNode log) {
    final parentInfo = _findParentListOf(log.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final logIndex = parentInfo.index;

    String afterText = '';
    if (logIndex + 1 < parentList.length &&
        parentList[logIndex + 1] is LiteralNode) {
      afterText = (parentList[logIndex + 1] as LiteralNode).text;
      parentList.removeAt(logIndex + 1);
    }

    // Collect multiplication chain before this LogNode
    List<MathNode> numeratorNodes = [];
    int removeStartIndex = logIndex;

    if (logIndex > 0) {
      final prevNode = parentList[logIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          logIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(log);

    for (int j = logIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire ExponentNode into a fraction's numerator
  void _wrapExponentNodeIntoFraction(ExponentNode exp) {
    final parentInfo = _findParentListOf(exp.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final expIndex = parentInfo.index;

    String afterText = '';
    if (expIndex + 1 < parentList.length &&
        parentList[expIndex + 1] is LiteralNode) {
      afterText = (parentList[expIndex + 1] as LiteralNode).text;
      parentList.removeAt(expIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = expIndex;

    if (expIndex > 0) {
      final prevNode = parentList[expIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          expIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(exp);

    for (int j = expIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire TrigNode into a fraction's numerator
  void _wrapTrigNodeIntoFraction(TrigNode trig) {
    final parentInfo = _findParentListOf(trig.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final trigIndex = parentInfo.index;

    String afterText = '';
    if (trigIndex + 1 < parentList.length &&
        parentList[trigIndex + 1] is LiteralNode) {
      afterText = (parentList[trigIndex + 1] as LiteralNode).text;
      parentList.removeAt(trigIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = trigIndex;

    if (trigIndex > 0) {
      final prevNode = parentList[trigIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          trigIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(trig);

    for (int j = trigIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire RootNode into a fraction's numerator
  void _wrapRootNodeIntoFraction(RootNode root) {
    final parentInfo = _findParentListOf(root.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final rootIndex = parentInfo.index;

    String afterText = '';
    if (rootIndex + 1 < parentList.length &&
        parentList[rootIndex + 1] is LiteralNode) {
      afterText = (parentList[rootIndex + 1] as LiteralNode).text;
      parentList.removeAt(rootIndex + 1);
    }

    List<MathNode> numeratorNodes = [];
    int removeStartIndex = rootIndex;

    if (rootIndex > 0) {
      final prevNode = parentList[rootIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          rootIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          numeratorNodes.addAll(chainResult.nodes);
        }
      }
    }

    numeratorNodes.add(root);

    for (int j = rootIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(numeratorNodes);

    final frac = FractionNode(
      num: numeratorNodes,
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, frac);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(
      parentId: frac.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );
    _notifyStructureChanged();
  }

  /// Wraps an entire AnsNode into an exponent's base
  void _wrapAnsNodeIntoExponent(AnsNode ans) {
    final parentInfo = _findParentListOf(ans.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final ansIndex = parentInfo.index;

    String afterText = '';
    if (ansIndex + 1 < parentList.length &&
        parentList[ansIndex + 1] is LiteralNode) {
      afterText = (parentList[ansIndex + 1] as LiteralNode).text;
      parentList.removeAt(ansIndex + 1);
    }

    // ========== NEW: Collect multiplication chain ==========
    List<MathNode> baseNodes = [];
    int removeStartIndex = ansIndex;

    if (ansIndex > 0) {
      final prevNode = parentList[ansIndex - 1];
      if (prevNode is LiteralNode &&
          prevNode.text.endsWith(MathTextStyle.multiplySign)) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          ansIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }

          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;

          baseNodes.addAll(chainResult.nodes);
        }
      }
    }

    baseNodes.add(ans);

    for (int j = ansIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    _ensureLiteralEdges(baseNodes);

    // ========== END NEW ==========

    final exp = ExponentNode(
      base: baseNodes, // ← Now includes the whole chain!
      power: [LiteralNode(text: "")],
    );

    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, exp);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(parentId: exp.id, path: 'pow', index: 0, subIndex: 0);
    _notifyStructureChanged();
  }

  void _wrapIntoFraction() {
    if (cursor.parentId != null) {
      final parent = _findNode(expression, cursor.parentId!);

      // === NODES THAT SHOULD ALWAYS WRAP ENTIRELY ===
      // (their fields are just numbers, not expressions)

      if (parent is AnsNode) {
        _wrapAnsNodeIntoFraction(parent);
        return;
      }

      if (parent is PermutationNode) {
        // <-- MOVE HERE
        _wrapPermutationNodeIntoFraction(parent);
        return;
      }

      if (parent is CombinationNode) {
        // <-- MOVE HERE
        _wrapCombinationNodeIntoFraction(parent);
        return;
      }

      // === NODES THAT CAN CONTAIN FRACTIONS INSIDE ===
      // (only wrap entire node if cursor is at start with no content)

      if (!_hasContentForNumerator()) {
        if (parent is LogNode) {
          _wrapLogNodeIntoFraction(parent);
          return;
        }
        if (parent is ExponentNode) {
          _wrapExponentNodeIntoFraction(parent);
          return;
        }
        if (parent is TrigNode) {
          _wrapTrigNodeIntoFraction(parent);
          return;
        }
        if (parent is RootNode) {
          _wrapRootNodeIntoFraction(parent);
          return;
        }
        if (parent is ParenthesisNode) {
          _wrapParenthesisNodeIntoFraction(parent);
          return;
        }
      }
      // If there's content for numerator, fall through to create fraction inside
    }

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorClick = cursor.subIndex;

    int operandStart = cursorClick;
    while (operandStart > 0 &&
        !_isNonMultiplyWordBoundaryForFraction(text, operandStart - 1)) {
      operandStart--;
    }

    String numeratorText = text.substring(operandStart, cursorClick);
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    // If the cursor sits immediately after a multiplication sign, the user is
    // multiplying by a fraction (e.g. "18·" then "/"). Insert an empty fraction
    // after the sign instead of absorbing the sign and the preceding operand
    // into the numerator.
    if (cursorClick > 0 && _isMultiplyChar(text[cursorClick - 1])) {
      current.text = text.substring(0, cursorClick);
      final frac = FractionNode(
        num: [LiteralNode(text: "")],
        den: [LiteralNode(text: "")],
      );
      final tail = LiteralNode(text: text.substring(cursorClick));
      if (actualIndex >= 0) {
        siblings.insert(actualIndex + 1, frac);
        siblings.insert(actualIndex + 2, tail);
        cursor = EditorCursor(
          parentId: frac.id,
          path: 'num',
          index: 0,
          subIndex: 0,
        );
      }
      _notifyStructureChanged();
      _scheduleCursorRecalc();
      return;
    }

    // === DETERMINE IF WE NEED TO COLLECT A CHAIN ===
    bool shouldCollectChain = false;
    String actualOperand = numeratorText;

    // Case 1: Empty operand at start of node with previous nodes
    if (numeratorText.isEmpty && operandStart == 0 && actualIndex > 0) {
      shouldCollectChain = true;
    }
    // Case 2: Operand preceded by multiply sign in same node
    else if (operandStart > 0 &&
        text[operandStart - 1] == MathTextStyle.multiplySign) {
      shouldCollectChain = true;
    }
    // Case 3: Operand STARTS with multiply sign
    else if (numeratorText.startsWith(MathTextStyle.multiplySign) &&
        actualIndex > 0) {
      shouldCollectChain = true;
      actualOperand = numeratorText.substring(1);
    }
    // Case 4: Implicit multiplication across nodes (e.g., 52 x^2)
    else if (operandStart == 0 && actualIndex > 0) {
      final prevNode = siblings[actualIndex - 1];
      if (prevNode is LiteralNode) {
        if (prevNode.text.isNotEmpty) {
          final lastChar = prevNode.text[prevNode.text.length - 1];
          if (_isDigitOrLetter(lastChar) ||
              prevNode.text.endsWith(MathTextStyle.multiplySign)) {
            shouldCollectChain = true;
          }
        }
      } else if (prevNode is ExponentNode ||
          prevNode is FractionNode ||
          prevNode is ParenthesisNode ||
          prevNode is TrigNode ||
          prevNode is RootNode ||
          prevNode is AnsNode ||
          prevNode is LogNode ||
          prevNode is ConstantNode ||
          prevNode is UnitVectorNode ||
          prevNode is PermutationNode ||
          prevNode is CombinationNode ||
          prevNode is SummationNode ||
          prevNode is DerivativeNode ||
          prevNode is IntegralNode ||
          prevNode is ProductNode) {
        shouldCollectChain = true;
      }
    }

    if (shouldCollectChain && actualIndex > 0) {
      final chainResult = _collectMultiplicationChain(
        siblings,
        actualIndex - 1,
      );

      if (chainResult.nodes.isNotEmpty) {
        if (chainResult.prefixToKeep != null &&
            chainResult.prefixNodeIndex != null) {
          (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
              chainResult.prefixToKeep!;
        }

        int removeStart =
            chainResult.prefixNodeIndex != null
                ? chainResult.prefixNodeIndex! + 1
                : chainResult.removeFromIndex;
        int removeEnd = actualIndex - 1;

        for (int j = removeEnd; j >= removeStart; j--) {
          siblings.removeAt(j);
        }

        int newCurrentIndex = removeStart;
        current.text = text.substring(cursorClick);

        List<MathNode> allNumeratorNodes = List.from(chainResult.nodes);
        if (actualOperand.isNotEmpty) {
          // A trailing postfix (factorial/degree/percent) glues to the operand
          // it follows, e.g. "(19+2)!"; other operands are separate factors and
          // get an explicit multiplication sign.
          final bool isPostfix =
              actualOperand.startsWith('!') ||
              actualOperand.startsWith('°') ||
              actualOperand.startsWith('%');
          allNumeratorNodes.add(
            LiteralNode(
              text:
                  isPostfix
                      ? actualOperand
                      : MathTextStyle.multiplySign + actualOperand,
            ),
          );
        }

        _ensureLiteralEdges(allNumeratorNodes);

        final frac = FractionNode(
          num: allNumeratorNodes,
          den: [LiteralNode(text: "")],
        );
        siblings.insert(newCurrentIndex, frac);

        final bool numeratorIsEmpty = _isListEffectivelyEmpty(frac.numerator);
        cursor = EditorCursor(
          parentId: frac.id,
          path: numeratorIsEmpty ? 'num' : 'den',
          index: 0,
          subIndex: 0,
        );
        _notifyStructureChanged();
        _scheduleCursorRecalc();
        return;
      }
    }

    // === DEFAULT BEHAVIOR ===
    if (numeratorText.startsWith(MathTextStyle.multiplySign)) {
      actualOperand = numeratorText.substring(1);
    }

    current.text = text.substring(0, operandStart);
    final frac = FractionNode(
      num: [LiteralNode(text: actualOperand)],
      den: [LiteralNode(text: "")],
    );
    final tail = LiteralNode(text: text.substring(cursorClick));

    if (actualIndex >= 0) {
      siblings.insert(actualIndex + 1, frac);
      siblings.insert(actualIndex + 2, tail);
      final bool numeratorIsEmpty = _isListEffectivelyEmpty(frac.numerator);
      cursor = EditorCursor(
        parentId: frac.id,
        path: numeratorIsEmpty ? 'num' : 'den',
        index: 0,
        subIndex: 0,
      );
    }
    _notifyStructureChanged();
    _scheduleCursorRecalc();
  }

  void _wrapPreviousNodeIntoPermutation(
    MathNode prevNode,
    int currentIndex,
    List<MathNode> siblings,
    LiteralNode currentLiteral,
  ) {
    String afterText = currentLiteral.text;

    // Remove the current literal and previous node
    siblings.removeAt(currentIndex); // Remove current literal
    siblings.removeAt(currentIndex - 1); // Remove previous node

    // Collect any chain before the previous node
    List<MathNode> nNodes = [];
    int insertIndex = currentIndex - 1;

    if (currentIndex - 2 >= 0) {
      final beforePrev = siblings[currentIndex - 2];
      if (beforePrev is LiteralNode &&
          (beforePrev.text.endsWith(MathTextStyle.multiplySign) ||
              (beforePrev.text.isNotEmpty &&
                  _isDigitOrLetter(
                    beforePrev.text[beforePrev.text.length - 1],
                  )))) {
        final chainResult = _collectMultiplicationChain(
          siblings,
          currentIndex - 2,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          insertIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;

          // Remove chain nodes
          for (int j = currentIndex - 2; j >= insertIndex; j--) {
            siblings.removeAt(j);
          }

          nNodes.addAll(chainResult.nodes);
        }
      }
    }

    nNodes.add(prevNode);

    final perm = PermutationNode(n: nNodes, r: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: afterText);

    siblings.insert(insertIndex, perm);
    siblings.insert(insertIndex + 1, tail);

    cursor = EditorCursor(parentId: perm.id, path: 'r', index: 0, subIndex: 0);
    _notifyStructureChanged();
  }

  void _wrapParenthesisNodeIntoPermutation(ParenthesisNode paren) {
    final parentInfo = _findParentListOf(paren.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final parenIndex = parentInfo.index;

    // Get text after parenthesis
    String afterText = '';
    if (parenIndex + 1 < parentList.length &&
        parentList[parenIndex + 1] is LiteralNode) {
      afterText = (parentList[parenIndex + 1] as LiteralNode).text;
      parentList.removeAt(parenIndex + 1);
    }

    // Collect multiplication chain before parenthesis
    List<MathNode> nNodes = [];
    int removeStartIndex = parenIndex;

    if (parenIndex > 0) {
      final prevNode = parentList[parenIndex - 1];
      if (prevNode is LiteralNode &&
          (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
              (prevNode.text.isNotEmpty &&
                  _isDigitOrLetter(prevNode.text[prevNode.text.length - 1])))) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          parenIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          nNodes.addAll(chainResult.nodes);
        }
      }
    }

    nNodes.add(paren);

    // Remove collected nodes
    for (int j = parenIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    final perm = PermutationNode(n: nNodes, r: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, perm);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(parentId: perm.id, path: 'r', index: 0, subIndex: 0);
    _notifyStructureChanged();
  }

  void _wrapPreviousNodeIntoCombination(
    MathNode prevNode,
    int currentIndex,
    List<MathNode> siblings,
    LiteralNode currentLiteral,
  ) {
    String afterText = currentLiteral.text;

    siblings.removeAt(currentIndex);
    siblings.removeAt(currentIndex - 1);

    List<MathNode> nNodes = [];
    int insertIndex = currentIndex - 1;

    if (currentIndex - 2 >= 0) {
      final beforePrev = siblings[currentIndex - 2];
      if (beforePrev is LiteralNode &&
          (beforePrev.text.endsWith(MathTextStyle.multiplySign) ||
              (beforePrev.text.isNotEmpty &&
                  _isDigitOrLetter(
                    beforePrev.text[beforePrev.text.length - 1],
                  )))) {
        final chainResult = _collectMultiplicationChain(
          siblings,
          currentIndex - 2,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (siblings[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          insertIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;

          for (int j = currentIndex - 2; j >= insertIndex; j--) {
            siblings.removeAt(j);
          }

          nNodes.addAll(chainResult.nodes);
        }
      }
    }

    nNodes.add(prevNode);

    final comb = CombinationNode(n: nNodes, r: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: afterText);

    siblings.insert(insertIndex, comb);
    siblings.insert(insertIndex + 1, tail);

    cursor = EditorCursor(parentId: comb.id, path: 'r', index: 0, subIndex: 0);
    _notifyStructureChanged();
  }

  void _wrapParenthesisNodeIntoCombination(ParenthesisNode paren) {
    final parentInfo = _findParentListOf(paren.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final parenIndex = parentInfo.index;

    String afterText = '';
    if (parenIndex + 1 < parentList.length &&
        parentList[parenIndex + 1] is LiteralNode) {
      afterText = (parentList[parenIndex + 1] as LiteralNode).text;
      parentList.removeAt(parenIndex + 1);
    }

    List<MathNode> nNodes = [];
    int removeStartIndex = parenIndex;

    if (parenIndex > 0) {
      final prevNode = parentList[parenIndex - 1];
      if (prevNode is LiteralNode &&
          (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
              (prevNode.text.isNotEmpty &&
                  _isDigitOrLetter(prevNode.text[prevNode.text.length - 1])))) {
        final chainResult = _collectMultiplicationChain(
          parentList,
          parenIndex - 1,
        );
        if (chainResult.nodes.isNotEmpty) {
          if (chainResult.prefixToKeep != null &&
              chainResult.prefixNodeIndex != null) {
            (parentList[chainResult.prefixNodeIndex!] as LiteralNode).text =
                chainResult.prefixToKeep!;
          }
          removeStartIndex =
              chainResult.prefixNodeIndex != null
                  ? chainResult.prefixNodeIndex! + 1
                  : chainResult.removeFromIndex;
          nNodes.addAll(chainResult.nodes);
        }
      }
    }

    nNodes.add(paren);

    for (int j = parenIndex; j >= removeStartIndex; j--) {
      parentList.removeAt(j);
    }

    final comb = CombinationNode(n: nNodes, r: [LiteralNode(text: "")]);
    final tail = LiteralNode(text: afterText);

    parentList.insert(removeStartIndex, comb);
    parentList.insert(removeStartIndex + 1, tail);

    cursor = EditorCursor(parentId: comb.id, path: 'r', index: 0, subIndex: 0);
    _notifyStructureChanged();
  }

  // function to calculate the input operation
  void onCalculate({Map<int, String>? ansValues}) {
    // Get expression from the math editor (lightweight serialization only)
    expr = MathExpressionSerializer.serialize(expression);

    // NOTE: Heavy computation (ExactMathEngine.evaluate + MathSolverNew.solve)
    // has been moved to ComputeService which runs in a background isolate.
    // This method now only serializes and notifies, keeping the UI responsive.

    // Notify that expression changed (triggers async compute pipeline)
    onResultChanged?.call();
  }

  void updateAnswer(TextEditingController? textDisplayController) {
    if (textDisplayController != null) {
      textDisplayController.text = result ?? '';
    }
  }

  void recalculateCursorRect() {
    final c = cursor;

    final key = _makeLayoutKey(c.parentId, c.path, c.index);

    final info = _layoutIndex[key];

    if (info == null) {
      return;
    }

    // Calculate cursor position
    final text = info.node.text;
    final charIndex = c.subIndex.clamp(0, text.length);
    double cursorX;

    if (text.isEmpty) {
      cursorX = info.rect.left;
    } else {
      if (info.renderParagraph != null && info.renderParagraph!.attached) {
        final displayIndex = MathTextStyle.logicalToDisplayIndex(
          text,
          charIndex,
          forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
        );
        final displayText = info.displayText; // Use cached display text
        final offset = info.renderParagraph!.getOffsetForCaret(
          TextPosition(offset: displayIndex.clamp(0, displayText.length)),
          Rect.zero,
        );
        cursorX = info.rect.left + offset.dx;
      } else {
        cursorX =
            info.rect.left +
            MathTextStyle.getCursorOffset(
              text,
              charIndex,
              info.fontSize,
              info.textScaler,
              forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
            );
      }
    }

    final newRect = Rect.fromLTWH(cursorX, info.rect.top, 2, info.rect.height);

    cursorPaintNotifier.updateRectDirect(newRect);
  }

  // === OTHER HELPERS ===
  void _updateLiteralAtCursor(void Function(LiteralNode) edit) {
    final node = _resolveCursorNode();
    if (node is LiteralNode) edit(node);
  }

  MathNode? _resolveCursorNode() {
    final list = _resolveSiblingList();
    return cursor.index < list.length ? list[cursor.index] : null;
  }

  List<MathNode> _resolveSiblingList() {
    if (cursor.parentId == null) return expression;
    final parent = _findNode(expression, cursor.parentId!);
    if (parent is FractionNode) {
      return cursor.path == 'num' ? parent.numerator : parent.denominator;
    }
    if (parent is ExponentNode) {
      return cursor.path == 'pow' ? parent.power : parent.base;
    }
    if (parent is ParenthesisNode) {
      return parent.content;
    }
    if (parent is TrigNode) {
      return parent.argument;
    }
    if (parent is RootNode) {
      return cursor.path == 'index' ? parent.index : parent.radicand;
    }
    if (parent is LogNode) {
      return cursor.path == 'base' ? parent.base : parent.argument;
    }
    if (parent is PermutationNode) {
      return cursor.path == 'n' ? parent.n : parent.r;
    }
    if (parent is CombinationNode) {
      return cursor.path == 'n' ? parent.n : parent.r;
    }
    if (parent is SummationNode) {
      if (cursor.path == 'var') return parent.variable;
      if (cursor.path == 'lower') return parent.lower;
      if (cursor.path == 'upper') return parent.upper;
      return parent.body;
    }
    if (parent is DerivativeNode) {
      if (cursor.path == 'var') return parent.variable;
      if (cursor.path == 'at') return parent.at;
      return parent.body;
    }
    if (parent is IntegralNode) {
      if (cursor.path == 'var') return parent.variable;
      if (cursor.path == 'lower') return parent.lower;
      if (cursor.path == 'upper') return parent.upper;
      return parent.body;
    }
    if (parent is ProductNode) {
      if (cursor.path == 'var') return parent.variable;
      if (cursor.path == 'lower') return parent.lower;
      if (cursor.path == 'upper') return parent.upper;
      return parent.body;
    }
    if (parent is AnsNode) {
      return parent.index;
    }
    return expression;
  }

  MathNode? _findNode(List<MathNode> nodes, String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
      if (n is FractionNode) {
        final found =
            _findNode(n.numerator, id) ?? _findNode(n.denominator, id);
        if (found != null) return found;
      }
      if (n is ExponentNode) {
        final found = _findNode(n.base, id) ?? _findNode(n.power, id);
        if (found != null) return found;
      }
      if (n is ParenthesisNode) {
        final found = _findNode(n.content, id);
        if (found != null) return found;
      }
      if (n is TrigNode) {
        final found = _findNode(n.argument, id);
        if (found != null) return found;
      }
      if (n is RootNode) {
        final found = _findNode(n.index, id) ?? _findNode(n.radicand, id);
        if (found != null) return found;
      }
      if (n is LogNode) {
        final found = _findNode(n.base, id) ?? _findNode(n.argument, id);
        if (found != null) return found;
      }
      if (n is PermutationNode) {
        final found = _findNode(n.n, id) ?? _findNode(n.r, id);
        if (found != null) return found;
      }
      if (n is CombinationNode) {
        final found = _findNode(n.n, id) ?? _findNode(n.r, id);
        if (found != null) return found;
      }
      if (n is SummationNode) {
        final found =
            _findNode(n.variable, id) ??
            _findNode(n.lower, id) ??
            _findNode(n.upper, id) ??
            _findNode(n.body, id);
        if (found != null) return found;
      }
      if (n is DerivativeNode) {
        final found =
            _findNode(n.variable, id) ??
            _findNode(n.at, id) ??
            _findNode(n.body, id);
        if (found != null) return found;
      }
      if (n is IntegralNode) {
        final found =
            _findNode(n.variable, id) ??
            _findNode(n.lower, id) ??
            _findNode(n.upper, id) ??
            _findNode(n.body, id);
        if (found != null) return found;
      }
      if (n is ProductNode) {
        final found =
            _findNode(n.variable, id) ??
            _findNode(n.lower, id) ??
            _findNode(n.upper, id) ??
            _findNode(n.body, id);
        if (found != null) return found;
      }
      if (n is AnsNode) {
        final found = _findNode(n.index, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  _ParentListInfo? _findParentListOf(String nodeId) =>
      _searchForParent(expression, nodeId, null, null);

  _ParentListInfo? _searchForParent(
    List<MathNode> nodes,
    String targetId,
    String? parentId,
    String? path,
  ) {
    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i].id == targetId) {
        return _ParentListInfo(nodes, i, parentId, path);
      }
      final node = nodes[i];
      if (node is FractionNode) {
        var result = _searchForParent(node.numerator, targetId, node.id, 'num');
        if (result != null) return result;
        result = _searchForParent(node.denominator, targetId, node.id, 'den');
        if (result != null) return result;
      } else if (node is ExponentNode) {
        var result = _searchForParent(node.base, targetId, node.id, 'base');
        if (result != null) return result;
        result = _searchForParent(node.power, targetId, node.id, 'pow');
        if (result != null) return result;
      } else if (node is ParenthesisNode) {
        var result = _searchForParent(
          node.content,
          targetId,
          node.id,
          'content',
        );
        if (result != null) return result;
      } else if (node is TrigNode) {
        // <-- ADD THIS
        var result = _searchForParent(node.argument, targetId, node.id, 'arg');
        if (result != null) return result;
      } else if (node is RootNode) {
        // <-- ADD THIS
        var result = _searchForParent(node.index, targetId, node.id, 'index');
        if (result != null) return result;
        result = _searchForParent(node.radicand, targetId, node.id, 'radicand');
        if (result != null) return result;
      } else if (node is PermutationNode) {
        // <-- ADD THIS
        var result = _searchForParent(node.n, targetId, node.id, 'n');
        if (result != null) return result;
        result = _searchForParent(node.r, targetId, node.id, 'r');
        if (result != null) return result;
      } else if (node is CombinationNode) {
        // <-- ADD THIS
        var result = _searchForParent(node.n, targetId, node.id, 'n');
        if (result != null) return result;
        result = _searchForParent(node.r, targetId, node.id, 'r');
        if (result != null) return result;
      } else if (node is SummationNode) {
        var result = _searchForParent(node.variable, targetId, node.id, 'var');
        if (result != null) return result;
        result = _searchForParent(node.lower, targetId, node.id, 'lower');
        if (result != null) return result;
        result = _searchForParent(node.upper, targetId, node.id, 'upper');
        if (result != null) return result;
        result = _searchForParent(node.body, targetId, node.id, 'body');
        if (result != null) return result;
      } else if (node is DerivativeNode) {
        var result = _searchForParent(node.variable, targetId, node.id, 'var');
        if (result != null) return result;
        if (node.isDefinite) {
          result = _searchForParent(node.at, targetId, node.id, 'at');
          if (result != null) return result;
        }
        result = _searchForParent(node.body, targetId, node.id, 'body');
        if (result != null) return result;
      } else if (node is IntegralNode) {
        var result = _searchForParent(node.variable, targetId, node.id, 'var');
        if (result != null) return result;
        if (node.isDefinite) {
          result = _searchForParent(node.lower, targetId, node.id, 'lower');
          if (result != null) return result;
          result = _searchForParent(node.upper, targetId, node.id, 'upper');
          if (result != null) return result;
        }
        result = _searchForParent(node.body, targetId, node.id, 'body');
        if (result != null) return result;
      } else if (node is ProductNode) {
        var result = _searchForParent(node.variable, targetId, node.id, 'var');
        if (result != null) return result;
        result = _searchForParent(node.lower, targetId, node.id, 'lower');
        if (result != null) return result;
        result = _searchForParent(node.upper, targetId, node.id, 'upper');
        if (result != null) return result;
        result = _searchForParent(node.body, targetId, node.id, 'body');
        if (result != null) return result;
      }
      if (node is LogNode) {
        var result = _searchForParent(node.base, targetId, node.id, 'base');
        if (result != null) return result;
        result = _searchForParent(node.argument, targetId, node.id, 'arg');
        if (result != null) return result;
      }
      if (node is AnsNode) {
        var result = _searchForParent(node.index, targetId, node.id, 'index');
        if (result != null) return result;
      }
    }
    return null;
  }

  _MultiplicationChainResult _collectMultiplicationChain(
    List<MathNode> siblings,
    int startIndex,
  ) {
    List<MathNode> collectedNodes = [];
    int removeFromIndex = startIndex;
    String? prefixToKeep;
    int? prefixNodeIndex;

    int i = startIndex;
    while (i >= 0) {
      final node = siblings[i];

      if (node is LiteralNode && node.text.isEmpty) {
        i--;
        continue;
      }

      if (node is ExponentNode ||
          node is FractionNode ||
          node is ParenthesisNode ||
          node is TrigNode ||
          node is RootNode ||
          node is AnsNode ||
          node is LogNode ||
          node is ConstantNode || // <-- ADD THIS
          node is UnitVectorNode || // <-- ADD THIS
          node is PermutationNode || // <-- ADD THIS
          node is CombinationNode ||
          node is SummationNode ||
          node is DerivativeNode ||
          node is IntegralNode ||
          node is ProductNode) {
        // <-- ADD THIS
        collectedNodes.insert(0, node);
        removeFromIndex = i;

        // Check if we should continue collecting
        if (i > 0) {
          final prevNode = siblings[i - 1];

          // Continue if previous node ends with multiply sign
          if (prevNode is LiteralNode &&
              prevNode.text.endsWith(MathTextStyle.multiplySign)) {
            i--;
            continue;
          }

          // Continue if previous node ends with digit/letter (implicit multiplication)
          if (prevNode is LiteralNode && prevNode.text.isNotEmpty) {
            String lastChar = prevNode.text[prevNode.text.length - 1];
            if (_isDigitOrLetter(lastChar)) {
              i--;
              continue;
            }
          }

          // Continue if previous is a structural node
          if (prevNode is ExponentNode ||
              prevNode is FractionNode ||
              prevNode is ParenthesisNode ||
              prevNode is TrigNode ||
              prevNode is RootNode ||
              prevNode is AnsNode ||
              prevNode is LogNode ||
              prevNode is ConstantNode || // <-- ADD THIS
              prevNode is UnitVectorNode || // <-- ADD THIS
              prevNode is PermutationNode || // <-- ADD THIS
              prevNode is CombinationNode ||
              prevNode is SummationNode ||
              prevNode is DerivativeNode ||
              prevNode is IntegralNode ||
              prevNode is ProductNode) {
            // <-- ADD THIS
            if (i > 1) {
              final prevPrevNode = siblings[i - 2];
              if (prevPrevNode is LiteralNode &&
                  (prevPrevNode.text.endsWith(MathTextStyle.multiplySign) ||
                      (prevPrevNode.text.isNotEmpty &&
                          _isDigitOrLetter(
                            prevPrevNode.text[prevPrevNode.text.length - 1],
                          )))) {
                i--;
                continue;
              }
            }
            i--;
            continue;
          }
        }
        break;
      } else if (node is LiteralNode) {
        String text = node.text;
        int operandEnd = text.length;
        int operandStart = operandEnd;

        while (operandStart > 0 &&
            !_isNonMultiplyWordBoundary(text[operandStart - 1])) {
          operandStart--;
        }

        if (operandStart < operandEnd) {
          String operandPart = text.substring(operandStart);

          if (operandPart == MathTextStyle.multiplySign) {
            collectedNodes.insert(0, LiteralNode(text: operandPart));
            removeFromIndex = i;

            if (operandStart > 0) {
              prefixToKeep = text.substring(0, operandStart);
              prefixNodeIndex = i;
              break;
            }

            if (i > 0) {
              i--;
              continue;
            }
            break;
          }

          collectedNodes.insert(0, LiteralNode(text: operandPart));
          removeFromIndex = i;

          if (operandStart > 0) {
            prefixToKeep = text.substring(0, operandStart);
            prefixNodeIndex = i;
            break;
          } else {
            if (i > 0) {
              final prevNode = siblings[i - 1];
              if (prevNode is ExponentNode ||
                  prevNode is FractionNode ||
                  prevNode is ParenthesisNode ||
                  prevNode is TrigNode ||
                  prevNode is RootNode ||
                  prevNode is AnsNode ||
                  prevNode is LogNode ||
                  prevNode is PermutationNode || // <-- ADD THIS
                  prevNode is CombinationNode) {
                // <-- ADD THIS
                i--;
                continue;
              } else if (prevNode is LiteralNode &&
                  (prevNode.text.endsWith(MathTextStyle.multiplySign) ||
                      (prevNode.text.isNotEmpty &&
                          _isDigitOrLetter(
                            prevNode.text[prevNode.text.length - 1],
                          )))) {
                i--;
                continue;
              }
            }
            break;
          }
        } else {
          break;
        }
      } else {
        break;
      }
    }

    return _MultiplicationChainResult(
      nodes: collectedNodes,
      removeFromIndex: removeFromIndex,
      prefixToKeep: prefixToKeep,
      prefixNodeIndex: prefixNodeIndex,
    );
  }

  // Add this helper method
  bool _isDigitOrLetter(String char) {
    if (char.isEmpty) return false;
    int code = char.codeUnitAt(0);
    return (code >= 48 && code <= 57) || // 0-9
        (code >= 65 && code <= 90) || // A-Z
        (code >= 97 && code <= 122); // a-z
  }

  void _exitParenthesis() {
    String? currentParentId = cursor.parentId;
    while (currentParentId != null) {
      final parent = _findNode(expression, currentParentId);
      if (parent is ParenthesisNode) {
        _moveCursorAfterNode(parent.id);
        notifyListeners();
        return;
      }
      final parentInfo = _findParentListOf(currentParentId);
      currentParentId = parentInfo?.parentId;
    }
  }

  void deleteChar() {
    if (hasSelection) {
      saveStateForUndo();
      deleteSelection();
      return;
    }

    saveStateForUndo();
    final node = _resolveCursorNode();

    if (node is! LiteralNode) {
      return;
    }

    if (cursor.subIndex > 0) {
      node.text =
          node.text.substring(0, cursor.subIndex - 1) +
          node.text.substring(cursor.subIndex);
      cursor = cursor.copyWith(subIndex: cursor.subIndex - 1);
      _notifyStructureChanged();
      return;
    }
    if (cursor.index > 0) {
      _deleteIntoPreviousNode();
      return;
    }
    if (cursor.parentId == null) {
      return;
    }

    _handleDeleteAtStructureStart();
  }

  void clear() {
    saveStateForUndo();
    expression = [LiteralNode()];
    result = '';
    cursor = const EditorCursor(); // Reset cursor to initial state
    _notifyStructureChanged();
  }

  // ============== DELETE HANDLERS FOR NEW NODES ==============

  void _handleDeleteInExponent(ExponentNode exp) {
    if (cursor.path == 'pow') {
      if (_isListEffectivelyEmpty(exp.power)) {
        _unwrapExponent(exp);
      } else {
        _moveCursorToEndOfList(exp.base, exp.id, 'base');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'base') {
      if (_isListEffectivelyEmpty(exp.base) &&
          _isListEffectivelyEmpty(exp.power)) {
        _removeExponent(exp);
      } else {
        _moveCursorBeforeNode(exp.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInFraction(FractionNode frac) {
    if (cursor.path == 'den') {
      if (_isListEffectivelyEmpty(frac.denominator)) {
        _unwrapFraction(frac);
      } else {
        _moveCursorToEndOfList(frac.numerator, frac.id, 'num');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'num') {
      if (_isListEffectivelyEmpty(frac.numerator) &&
          _isListEffectivelyEmpty(frac.denominator)) {
        _removeFraction(frac);
      } else {
        _moveCursorBeforeNode(frac.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInParenthesis(ParenthesisNode paren) {
    if (_isListEffectivelyEmpty(paren.content)) {
      _removeParenthesis(paren);
    } else {
      _moveCursorBeforeNode(paren.id);
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInTrig(TrigNode trig) {
    if (_isListEffectivelyEmpty(trig.argument)) {
      _removeTrig(trig);
    } else {
      _moveCursorBeforeNode(trig.id);
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInRoot(RootNode root) {
    if (cursor.path == 'radicand') {
      if (_isListEffectivelyEmpty(root.radicand)) {
        _removeRoot(root);
      } else if (!root.isSquareRoot) {
        _moveCursorToEndOfList(root.index, root.id, 'index');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(root.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'index') {
      if (_isListEffectivelyEmpty(root.index) &&
          _isListEffectivelyEmpty(root.radicand)) {
        _removeRoot(root);
      } else {
        _moveCursorBeforeNode(root.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInLog(LogNode log) {
    if (cursor.path == 'arg') {
      if (_isListEffectivelyEmpty(log.argument)) {
        _removeLog(log);
      } else if (!log.isNaturalLog) {
        _moveCursorToEndOfList(log.base, log.id, 'base');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(log.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'base') {
      if (_isListEffectivelyEmpty(log.base) &&
          _isListEffectivelyEmpty(log.argument)) {
        _removeLog(log);
      } else {
        _moveCursorBeforeNode(log.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInPermutation(PermutationNode perm) {
    if (cursor.path == 'r') {
      if (_isListEffectivelyEmpty(perm.r)) {
        _moveCursorToEndOfList(perm.n, perm.id, 'n');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorToEndOfList(perm.n, perm.id, 'n');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'n') {
      if (_isListEffectivelyEmpty(perm.n) && _isListEffectivelyEmpty(perm.r)) {
        _removePermutation(perm);
      } else {
        _moveCursorBeforeNode(perm.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInCombination(CombinationNode comb) {
    if (cursor.path == 'r') {
      if (_isListEffectivelyEmpty(comb.r)) {
        _moveCursorToEndOfList(comb.n, comb.id, 'n');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorToEndOfList(comb.n, comb.id, 'n');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'n') {
      if (_isListEffectivelyEmpty(comb.n) && _isListEffectivelyEmpty(comb.r)) {
        _removeCombination(comb);
      } else {
        _moveCursorBeforeNode(comb.id);
        recalculateCursorRect();
        notifyListeners();
      }
    }
  }

  void _handleDeleteInSummation(SummationNode sum) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(sum.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(sum.upper, sum.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(sum.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(sum.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(sum.lower, sum.id, 'lower');
        recalculateCursorRect();
        notifyListeners();
      } else {
        // Move to body if user pressed left or something, but usually backspace
        // from start of upper should go to... somewhere.
        // If we are at the start of upper, backspace should trigger this handler.
        _moveCursorToEndOfList(sum.body, sum.id, 'body');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(sum.lower)) {
        // Finally remove the node
        _removeSummation(sum);
      } else {
        _moveCursorToEndOfList(sum.upper, sum.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(sum.body, sum.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInProduct(ProductNode prod) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(prod.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(prod.upper, prod.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(prod.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(prod.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(prod.lower, prod.id, 'lower');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorToEndOfList(prod.body, prod.id, 'body');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(prod.lower)) {
        // Finally remove the node
        _removeProduct(prod);
      } else {
        _moveCursorToEndOfList(prod.upper, prod.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(prod.body, prod.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInDerivative(DerivativeNode diff) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(diff.body)) {
        // Move to 'at' field (value to be evaluated at)
        _moveCursorToEndOfList(diff.at, diff.id, 'at');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(diff.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'at') {
      if (_isListEffectivelyEmpty(diff.at)) {
        // Finally remove the node
        _removeDerivative(diff);
      } else {
        _moveCursorToEndOfList(diff.body, diff.id, 'body');
        recalculateCursorRect();
        notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(diff.body, diff.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInIntegral(IntegralNode integ) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(integ.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(integ.upper, integ.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorBeforeNode(integ.id);
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(integ.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(integ.lower, integ.id, 'lower');
        recalculateCursorRect();
        notifyListeners();
      } else {
        _moveCursorToEndOfList(integ.body, integ.id, 'body');
        recalculateCursorRect();
        notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(integ.lower)) {
        // Finally remove the node
        _removeIntegral(integ);
      } else {
        _moveCursorToEndOfList(integ.upper, integ.id, 'upper');
        recalculateCursorRect();
        notifyListeners();
      }
    } else {
      // From 'var' field
      if (!_isListEffectivelyEmpty(integ.variable)) {
        final int lastIndex = integ.variable.length - 1;
        final MathNode lastNode = integ.variable[lastIndex];

        if (lastNode is LiteralNode && lastNode.text.isNotEmpty) {
          lastNode.text = lastNode.text.substring(0, lastNode.text.length - 1);
          cursor = cursor.copyWith(
            path: 'var',
            index: lastIndex,
            subIndex: lastNode.text.length,
          );
          _notifyStructureChanged();
          return;
        }

        integ.variable.removeLast();
        if (integ.variable.isEmpty || integ.variable.last is! LiteralNode) {
          integ.variable.add(LiteralNode(text: ''));
        }

        final int newLastIndex = integ.variable.length - 1;
        final MathNode newLastNode = integ.variable[newLastIndex];
        final int newSubIndex =
            newLastNode is LiteralNode ? newLastNode.text.length : 0;

        cursor = cursor.copyWith(
          path: 'var',
          index: newLastIndex,
          subIndex: newSubIndex,
        );
        _notifyStructureChanged();
        return;
      }

      _moveCursorToEndOfList(integ.body, integ.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _handleDeleteInAns(AnsNode ans) {
    if (_isListEffectivelyEmpty(ans.index)) {
      _removeAns(ans);
    } else {
      _moveCursorBeforeNode(ans.id);
      recalculateCursorRect();
      notifyListeners();
    }
  }

  void _deleteIntoPreviousNode() {
    final siblings = _resolveSiblingList();
    final prevNode = siblings[cursor.index - 1];

    if (prevNode is LiteralNode) {
      if (prevNode.text.isNotEmpty) {
        prevNode.text = prevNode.text.substring(0, prevNode.text.length - 1);
        cursor = cursor.copyWith(
          index: cursor.index - 1,
          subIndex: prevNode.text.length,
        );
        _notifyStructureChanged();
      } else {
        cursor = cursor.copyWith(index: cursor.index - 1, subIndex: 0);
        recalculateCursorRect(); // ← ADD THIS
        notifyListeners();
      }
    } else if (prevNode is ConstantNode || prevNode is UnitVectorNode) {
      siblings.removeAt(cursor.index - 1);
      final newIndex = cursor.index - 1;
      cursor = cursor.copyWith(index: newIndex);

      // After removing a constant, clean up adjacent empty LiteralNode spacers.
      // When constants are adjacent (e.g. π e), empty literals sit between them.
      // Deleting the constant can leave consecutive empty literals — merge them.
      if (newIndex > 0 &&
          newIndex < siblings.length &&
          siblings[newIndex] is LiteralNode &&
          (siblings[newIndex] as LiteralNode).text.isEmpty &&
          siblings[newIndex - 1] is LiteralNode &&
          (siblings[newIndex - 1] as LiteralNode).text.isEmpty) {
        siblings.removeAt(newIndex - 1);
        cursor = cursor.copyWith(index: newIndex - 1);
      }

      _notifyStructureChanged();
    } else if (prevNode is NewlineNode) {
      _removeNewline(prevNode);
    } else if (prevNode is FractionNode) {
      _moveCursorToEndOfList(prevNode.denominator, prevNode.id, 'den');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is ExponentNode) {
      _moveCursorToEndOfList(prevNode.power, prevNode.id, 'pow');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is ParenthesisNode) {
      _moveCursorToEndOfList(prevNode.content, prevNode.id, 'content');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is TrigNode) {
      _moveCursorToEndOfList(prevNode.argument, prevNode.id, 'arg');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is RootNode) {
      _moveCursorToEndOfList(prevNode.radicand, prevNode.id, 'radicand');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is LogNode) {
      _moveCursorToEndOfList(prevNode.argument, prevNode.id, 'arg');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is PermutationNode) {
      _moveCursorToEndOfList(prevNode.r, prevNode.id, 'r');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    } else if (prevNode is CombinationNode) {
      _moveCursorToEndOfList(prevNode.r, prevNode.id, 'r');
      recalculateCursorRect();
      notifyListeners();
    } else if (prevNode is SummationNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    } else if (prevNode is DerivativeNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    } else if (prevNode is IntegralNode) {
      _moveCursorToEndOfList(prevNode.variable, prevNode.id, 'var');
      recalculateCursorRect();
      notifyListeners();
    } else if (prevNode is ProductNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      notifyListeners();
    } else if (prevNode is AnsNode) {
      _moveCursorToEndOfList(prevNode.index, prevNode.id, 'index');
      recalculateCursorRect(); // ← ADD THIS
      notifyListeners();
    }
  }

  void _handleDeleteAtStructureStart() {
    final parent = _findNode(expression, cursor.parentId!);
    if (parent is FractionNode) {
      _handleDeleteInFraction(parent);
    } else if (parent is ExponentNode) {
      _handleDeleteInExponent(parent);
    } else if (parent is ParenthesisNode) {
      _handleDeleteInParenthesis(parent);
    } else if (parent is TrigNode) {
      _handleDeleteInTrig(parent);
    } else if (parent is RootNode) {
      _handleDeleteInRoot(parent);
    } else if (parent is LogNode) {
      _handleDeleteInLog(parent);
    } else if (parent is PermutationNode) {
      _handleDeleteInPermutation(parent);
    } else if (parent is CombinationNode) {
      _handleDeleteInCombination(parent);
    } else if (parent is SummationNode) {
      _handleDeleteInSummation(parent);
    } else if (parent is DerivativeNode) {
      _handleDeleteInDerivative(parent);
    } else if (parent is IntegralNode) {
      _handleDeleteInIntegral(parent);
    } else if (parent is ProductNode) {
      _handleDeleteInProduct(parent);
    } else if (parent is AnsNode) {
      _handleDeleteInAns(parent);
    }
  }

  bool _isListEffectivelyEmpty(List<MathNode> nodes) {
    for (final node in nodes) {
      if (node is LiteralNode && node.text.isNotEmpty) return false;
      if (node is! LiteralNode) return false;
    }
    return true;
  }

  void _ensureLiteralEdges(List<MathNode> nodes) {
    if (nodes.isEmpty) {
      nodes.add(LiteralNode(text: ""));
      return;
    }
    if (nodes.first is! LiteralNode) {
      nodes.insert(0, LiteralNode(text: ""));
    }
    if (nodes.last is! LiteralNode) {
      nodes.add(LiteralNode(text: ""));
    }
  }

  void _moveCursorToEndOfList(
    List<MathNode> nodes,
    String parentId,
    String path,
  ) {
    if (nodes.isEmpty) return;
    final lastIndex = nodes.length - 1;
    final lastNode = nodes[lastIndex];

    if (lastNode is LiteralNode) {
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: lastIndex,
        subIndex: lastNode.text.length,
      );
    } else if (lastNode is FractionNode) {
      _moveCursorToEndOfList(lastNode.denominator, lastNode.id, 'den');
    } else if (lastNode is ExponentNode) {
      _moveCursorToEndOfList(lastNode.power, lastNode.id, 'pow');
    } else if (lastNode is ParenthesisNode) {
      _moveCursorToEndOfList(lastNode.content, lastNode.id, 'content');
    } else if (lastNode is TrigNode) {
      _moveCursorToEndOfList(lastNode.argument, lastNode.id, 'arg');
    } else if (lastNode is RootNode) {
      _moveCursorToEndOfList(lastNode.radicand, lastNode.id, 'radicand');
    } else if (lastNode is LogNode) {
      _moveCursorToEndOfList(lastNode.argument, lastNode.id, 'arg');
    } else if (lastNode is PermutationNode) {
      _moveCursorToEndOfList(lastNode.r, lastNode.id, 'r');
    } else if (lastNode is CombinationNode) {
      _moveCursorToEndOfList(lastNode.r, lastNode.id, 'r');
    } else if (lastNode is SummationNode) {
      _moveCursorToEndOfList(lastNode.body, lastNode.id, 'body');
    } else if (lastNode is DerivativeNode) {
      _moveCursorToEndOfList(lastNode.body, lastNode.id, 'body');
    } else if (lastNode is IntegralNode) {
      _moveCursorToEndOfList(lastNode.body, lastNode.id, 'body');
    } else if (lastNode is ProductNode) {
      _moveCursorToEndOfList(lastNode.body, lastNode.id, 'body');
    } else if (lastNode is AnsNode) {
      _moveCursorToEndOfList(lastNode.index, lastNode.id, 'index');
    } else if (lastNode is ConstantNode || lastNode is UnitVectorNode) {
      final insertIndex = lastIndex + 1;
      nodes.insert(insertIndex, LiteralNode(text: ""));
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: insertIndex,
        subIndex: 0,
      );
    }
  }

  void _moveCursorToStartOfList(
    List<MathNode> nodes,
    String parentId,
    String path,
  ) {
    if (nodes.isEmpty) return;
    final firstNode = nodes[0];

    if (firstNode is LiteralNode) {
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: 0,
        subIndex: 0,
      );
    } else if (firstNode is FractionNode) {
      _moveCursorToStartOfList(firstNode.numerator, firstNode.id, 'num');
    } else if (firstNode is ExponentNode) {
      _moveCursorToStartOfList(firstNode.base, firstNode.id, 'base');
    } else if (firstNode is ParenthesisNode) {
      _moveCursorToStartOfList(firstNode.content, firstNode.id, 'content');
    } else if (firstNode is TrigNode) {
      _moveCursorToStartOfList(firstNode.argument, firstNode.id, 'arg');
    } else if (firstNode is RootNode) {
      if (firstNode.isSquareRoot) {
        _moveCursorToStartOfList(firstNode.radicand, firstNode.id, 'radicand');
      } else {
        _moveCursorToStartOfList(firstNode.index, firstNode.id, 'index');
      }
    } else if (firstNode is LogNode) {
      if (firstNode.isNaturalLog) {
        _moveCursorToStartOfList(firstNode.argument, firstNode.id, 'arg');
      } else {
        _moveCursorToStartOfList(firstNode.base, firstNode.id, 'base');
      }
    } else if (firstNode is PermutationNode) {
      _moveCursorToStartOfList(firstNode.n, firstNode.id, 'n');
    } else if (firstNode is CombinationNode) {
      _moveCursorToStartOfList(firstNode.n, firstNode.id, 'n');
    } else if (firstNode is SummationNode) {
      _moveCursorToStartOfList(firstNode.body, firstNode.id, 'body');
    } else if (firstNode is DerivativeNode) {
      _moveCursorToStartOfList(firstNode.body, firstNode.id, 'body');
    } else if (firstNode is IntegralNode) {
      _moveCursorToStartOfList(firstNode.body, firstNode.id, 'body');
    } else if (firstNode is ProductNode) {
      _moveCursorToStartOfList(firstNode.body, firstNode.id, 'body');
    } else if (firstNode is AnsNode) {
      _moveCursorToStartOfList(firstNode.index, firstNode.id, 'index');
    } else if (firstNode is ConstantNode || firstNode is UnitVectorNode) {
      nodes.insert(0, LiteralNode(text: ""));
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: 0,
        subIndex: 0,
      );
    }
  }

  void _moveCursorBeforeNode(String nodeId) =>
      _findAndPositionBefore(expression, nodeId, null, null);

  void moveCursorToStart() {
    cursor = const EditorCursor(
      parentId: null,
      path: null,
      index: 0,
      subIndex: 0,
    );
    notifyListeners();
  }

  void moveCursorToEnd() {
    if (expression.isEmpty) {
      cursor = const EditorCursor(index: 0, subIndex: 0);
    } else {
      int lastIndex = expression.length - 1;
      MathNode lastNode = expression[lastIndex];

      cursor = EditorCursor(
        parentId: null,
        path: null,
        index: lastIndex,
        subIndex: lastNode is LiteralNode ? lastNode.text.length : 0,
      );
    }
    notifyListeners();
  }

  /// All editable child lists of a composite node, each paired with the path
  /// key the cursor system uses to identify it (see [_resolveSiblingList]).
  /// Order is the caret traversal order. Returns an empty list for atomic
  /// nodes (literals, constants, unit vectors, newlines). This is the single
  /// source of truth used to recurse through the whole node tree.
  List<MapEntry<String, List<MathNode>>> _childListsOf(MathNode node) {
    if (node is FractionNode) {
      return [
        MapEntry('num', node.numerator),
        MapEntry('den', node.denominator),
      ];
    } else if (node is ExponentNode) {
      return [MapEntry('base', node.base), MapEntry('pow', node.power)];
    } else if (node is ParenthesisNode) {
      return [MapEntry('content', node.content)];
    } else if (node is TrigNode) {
      return [MapEntry('arg', node.argument)];
    } else if (node is RootNode) {
      return [MapEntry('index', node.index), MapEntry('radicand', node.radicand)];
    } else if (node is LogNode) {
      return [MapEntry('base', node.base), MapEntry('arg', node.argument)];
    } else if (node is PermutationNode) {
      return [MapEntry('n', node.n), MapEntry('r', node.r)];
    } else if (node is CombinationNode) {
      return [MapEntry('n', node.n), MapEntry('r', node.r)];
    } else if (node is SummationNode) {
      return [
        MapEntry('var', node.variable),
        MapEntry('lower', node.lower),
        MapEntry('upper', node.upper),
        MapEntry('body', node.body),
      ];
    } else if (node is ProductNode) {
      return [
        MapEntry('var', node.variable),
        MapEntry('lower', node.lower),
        MapEntry('upper', node.upper),
        MapEntry('body', node.body),
      ];
    } else if (node is IntegralNode) {
      // Indefinite integrals have no editable bounds.
      return [
        MapEntry('var', node.variable),
        if (node.isDefinite) MapEntry('lower', node.lower),
        if (node.isDefinite) MapEntry('upper', node.upper),
        MapEntry('body', node.body),
      ];
    } else if (node is DerivativeNode) {
      // Indefinite derivatives have no editable evaluation point.
      return [
        MapEntry('var', node.variable),
        if (node.isDefinite) MapEntry('at', node.at),
        MapEntry('body', node.body),
      ];
    } else if (node is AnsNode) {
      return [MapEntry('index', node.index)];
    }
    return const [];
  }

  /// Move the cursor into [node] at its logical entry field (respecting the
  /// hidden index of a square root and the hidden base of a natural log).
  /// Mirrors the composite handling in [_moveCursorToStartOfList].
  void _moveCursorIntoNodeStart(MathNode node) {
    if (node is RootNode && node.isSquareRoot) {
      _moveCursorToStartOfList(node.radicand, node.id, 'radicand');
      return;
    }
    if (node is LogNode && node.isNaturalLog) {
      _moveCursorToStartOfList(node.argument, node.id, 'arg');
      return;
    }
    if (node is SummationNode ||
        node is ProductNode ||
        node is IntegralNode ||
        node is DerivativeNode) {
      // Match _moveCursorToStartOfList: enter these at the body.
      final body = _childListsOf(node).last;
      _moveCursorToStartOfList(body.value, node.id, body.key);
      return;
    }
    final lists = _childListsOf(node);
    if (lists.isNotEmpty) {
      _moveCursorToStartOfList(lists.first.value, node.id, lists.first.key);
    }
  }

  /// Move the cursor to the end of [node]'s logical last field. Mirrors the
  /// composite handling in [_moveCursorToEndOfList].
  void _moveCursorIntoNodeEnd(MathNode node) {
    final lists = _childListsOf(node);
    if (lists.isNotEmpty) {
      _moveCursorToEndOfList(lists.last.value, node.id, lists.last.key);
    }
  }

  /// Place the cursor immediately after the atomic node (constant/unit vector)
  /// at [atomicIndex] in [siblings], reusing the following literal as a caret
  /// anchor or inserting an empty one if there is none.
  void _positionAfterAtomic(
    List<MathNode> siblings,
    int atomicIndex,
    String? parentId,
    String? path,
  ) {
    final nextIndex = atomicIndex + 1;
    if (nextIndex >= siblings.length || siblings[nextIndex] is! LiteralNode) {
      siblings.insert(nextIndex, LiteralNode(text: ""));
    }
    cursor = EditorCursor(
      parentId: parentId,
      path: path,
      index: nextIndex,
      subIndex: 0,
    );
  }

  /// Place the cursor immediately before the atomic node (constant/unit vector)
  /// at [atomicIndex] in [siblings], reusing the preceding literal as a caret
  /// anchor or inserting an empty one if there is none.
  void _positionBeforeAtomic(
    List<MathNode> siblings,
    int atomicIndex,
    String? parentId,
    String? path,
  ) {
    final prevIndex = atomicIndex - 1;
    if (prevIndex >= 0 && siblings[prevIndex] is LiteralNode) {
      final lit = siblings[prevIndex] as LiteralNode;
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: prevIndex,
        subIndex: lit.text.length,
      );
    } else {
      siblings.insert(atomicIndex, LiteralNode(text: ""));
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: atomicIndex,
        subIndex: 0,
      );
    }
  }

  bool _findAndPositionBefore(
    List<MathNode> nodes,
    String targetId,
    String? grandParentId,
    String? path,
  ) {
    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i].id == targetId) {
        if (i > 0) {
          final prevNode = nodes[i - 1];
          if (prevNode is LiteralNode) {
            cursor = EditorCursor(
              parentId: grandParentId,
              path: path,
              index: i - 1,
              subIndex: prevNode.text.length,
            );
          } else if (_childListsOf(prevNode).isNotEmpty) {
            // Composite previous sibling: step into the end of its last field.
            _moveCursorIntoNodeEnd(prevNode);
          } else {
            // Atomic previous sibling (constant/unit vector/newline): the caret
            // sits between it and the target.
            cursor = EditorCursor(
              parentId: grandParentId,
              path: path,
              index: i,
              subIndex: 0,
            );
          }
        } else {
          cursor = EditorCursor(
            parentId: grandParentId,
            path: path,
            index: 0,
            subIndex: 0,
          );
        }
        return true;
      }
      // Recurse into every editable child list of composite nodes.
      for (final child in _childListsOf(nodes[i])) {
        if (_findAndPositionBefore(
          child.value,
          targetId,
          nodes[i].id,
          child.key,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  bool _findAndPositionAfter(
    List<MathNode> nodes,
    String targetId,
    String? grandParentId,
    String? path,
  ) {
    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i].id == targetId) {
        if (i < nodes.length - 1) {
          final nextNode = nodes[i + 1];
          if (_childListsOf(nextNode).isEmpty) {
            // Literal or atomic (constant/unit vector/newline): caret sits
            // just before the next sibling.
            cursor = EditorCursor(
              parentId: grandParentId,
              path: path,
              index: i + 1,
              subIndex: 0,
            );
          } else {
            _moveCursorIntoNodeStart(nextNode);
          }
        } else if (grandParentId != null) {
          // Target is the last node in its field: move to the start of the
          // grandparent's next editable field, or after the grandparent node.
          final grandParent = _findNode(expression, grandParentId);
          if (grandParent != null) {
            final gLists = _childListsOf(grandParent);
            final idx = gLists.indexWhere((e) => e.key == path);
            if (idx != -1 && idx + 1 < gLists.length) {
              final next = gLists[idx + 1];
              _moveCursorToStartOfList(next.value, grandParent.id, next.key);
            } else {
              _moveCursorAfterNode(grandParent.id);
            }
          }
        }
        return true;
      }
      // Recurse into every editable child list of composite nodes.
      for (final child in _childListsOf(nodes[i])) {
        if (_findAndPositionAfter(
          child.value,
          targetId,
          nodes[i].id,
          child.key,
        )) {
          return true;
        }
      }
    }
    return false;
  }

  void _mergeAdjacentLiteralsFrom(List<MathNode> list, int startIndex) {
    if (startIndex < 0) startIndex = 0;
    int i = startIndex;
    while (i < list.length - 1) {
      final current = list[i];
      final next = list[i + 1];
      if (current is LiteralNode && next is LiteralNode) {
        current.text += next.text;
        list.removeAt(i + 1);
      } else {
        i++;
      }
    }
  }

  void _unwrapFraction(FractionNode frac) {
    final parentInfo = _findParentListOf(frac.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final fracIndex = parentInfo.index;

    List<MathNode> replacement =
        _isListEffectivelyEmpty(frac.numerator)
            ? []
            : List<MathNode>.from(frac.numerator);

    parentList.removeAt(fracIndex);
    if (replacement.isNotEmpty) {
      parentList.insertAll(fracIndex, replacement);
    }

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    NewlineNode? boundaryMarker;
    if (replacement.isNotEmpty) {
      boundaryMarker = NewlineNode();
      parentList.insert(fracIndex + replacement.length, boundaryMarker);
    }

    int mergeStartIndex = (fracIndex > 0) ? fracIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);

    // Position cursor at end of numerator content
    if (replacement.isEmpty) {
      // No content was inserted
      if (mergeStartIndex < parentList.length) {
        final node = parentList[mergeStartIndex];
        if (node is LiteralNode) {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: node.text.length,
          );
        } else {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: 0,
          );
        }
      } else {
        cursor = EditorCursor(
          parentId: parentInfo.parentId,
          path: parentInfo.path,
          index: 0,
          subIndex: 0,
        );
      }
    } else {
      final String? markerId = boundaryMarker?.id;
      final int markerIndex =
          markerId == null
              ? -1
              : parentList.indexWhere((n) => n.id == markerId);
      final int targetIndex = markerIndex > 0 ? markerIndex - 1 : -1;

      if (targetIndex >= 0) {
        final node = parentList[targetIndex];
        if (node is LiteralNode) {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: targetIndex,
            subIndex: node.text.length,
          );
        } else if (node is ParenthesisNode) {
          _moveCursorToEndOfList(node.content, node.id, 'content');
        } else if (node is FractionNode) {
          _moveCursorToEndOfList(node.denominator, node.id, 'den');
        } else if (node is ExponentNode) {
          _moveCursorToEndOfList(node.power, node.id, 'pow');
        } else if (node is AnsNode) {
          _moveCursorToEndOfList(node.index, node.id, 'index');
        } else if (node is TrigNode) {
          _moveCursorToEndOfList(node.argument, node.id, 'arg');
        } else if (node is RootNode) {
          _moveCursorToEndOfList(node.radicand, node.id, 'radicand');
        } else if (node is LogNode) {
          _moveCursorToEndOfList(node.argument, node.id, 'arg');
        } else if (node is PermutationNode) {
          _moveCursorToEndOfList(node.r, node.id, 'r');
        } else if (node is CombinationNode) {
          _moveCursorToEndOfList(node.r, node.id, 'r');
        } else if (node is DerivativeNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is IntegralNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is SummationNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is ProductNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is ConstantNode || node is UnitVectorNode) {
          if (targetIndex + 1 < parentList.length &&
              parentList[targetIndex + 1] is LiteralNode) {
            cursor = EditorCursor(
              parentId: parentInfo.parentId,
              path: parentInfo.path,
              index: targetIndex + 1,
              subIndex: 0,
            );
          } else {
            final insertIndex = targetIndex + 1;
            parentList.insert(insertIndex, LiteralNode(text: ""));
            cursor = EditorCursor(
              parentId: parentInfo.parentId,
              path: parentInfo.path,
              index: insertIndex,
              subIndex: 0,
            );
          }
        } else {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: targetIndex,
            subIndex: 0,
          );
        }
      } else {
        cursor = EditorCursor(
          parentId: parentInfo.parentId,
          path: parentInfo.path,
          index: 0,
          subIndex: 0,
        );
      }
    }

    final String? markerId = boundaryMarker?.id;
    if (markerId != null) {
      parentList.removeWhere((n) => n.id == markerId);
    }

    _notifyStructureChanged();
  }

  void _removeFraction(FractionNode frac) {
    final parentInfo = _findParentListOf(frac.id);
    if (parentInfo == null) return;
    final parentList = parentInfo.list;
    final fracIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (fracIndex > 0 && parentList[fracIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[fracIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(fracIndex);
    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (fracIndex > 0) ? fracIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _unwrapExponent(ExponentNode exp) {
    final parentInfo = _findParentListOf(exp.id);
    if (parentInfo == null) return;
    final parentList = parentInfo.list;
    final expIndex = parentInfo.index;

    List<MathNode> replacement =
        _isListEffectivelyEmpty(exp.base) ? [] : List<MathNode>.from(exp.base);

    parentList.removeAt(expIndex);
    if (replacement.isNotEmpty) {
      parentList.insertAll(expIndex, replacement);
    }

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (expIndex > 0) ? expIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);

    // Position cursor at end of base content
    if (replacement.isEmpty) {
      // No content was inserted
      if (mergeStartIndex < parentList.length) {
        final node = parentList[mergeStartIndex];
        if (node is LiteralNode) {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: node.text.length,
          );
        } else {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: 0,
          );
        }
      } else {
        cursor = EditorCursor(
          parentId: parentInfo.parentId,
          path: parentInfo.path,
          index: 0,
          subIndex: 0,
        );
      }
    } else {
      // Find the last node of the base by its ID
      MathNode lastBaseNode = replacement.last;

      int foundIndex = -1;
      for (int i = 0; i < parentList.length; i++) {
        if (parentList[i].id == lastBaseNode.id) {
          foundIndex = i;
          break;
        }
      }

      if (foundIndex != -1) {
        // Found the node, position at its end
        final node = parentList[foundIndex];
        if (node is LiteralNode) {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: foundIndex,
            subIndex: node.text.length,
          );
        } else if (node is ParenthesisNode) {
          _moveCursorToEndOfList(node.content, node.id, 'content');
        } else if (node is FractionNode) {
          _moveCursorToEndOfList(node.denominator, node.id, 'den');
        } else if (node is ExponentNode) {
          _moveCursorToEndOfList(node.power, node.id, 'pow');
        } else if (node is AnsNode) {
          _moveCursorToEndOfList(node.index, node.id, 'index');
        } else if (node is TrigNode) {
          _moveCursorToEndOfList(node.argument, node.id, 'arg');
        } else if (node is RootNode) {
          _moveCursorToEndOfList(node.radicand, node.id, 'radicand');
        } else if (node is LogNode) {
          _moveCursorToEndOfList(node.argument, node.id, 'arg');
        } else if (node is PermutationNode) {
          // <-- ADD THIS
          _moveCursorToEndOfList(node.r, node.id, 'r');
        } else if (node is CombinationNode) {
          // <-- ADD THIS
          _moveCursorToEndOfList(node.r, node.id, 'r');
        } else if (node is DerivativeNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is IntegralNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is SummationNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is ProductNode) {
          _moveCursorToEndOfList(node.body, node.id, 'body');
        } else if (node is ConstantNode || node is UnitVectorNode) {
          if (foundIndex + 1 < parentList.length &&
              parentList[foundIndex + 1] is LiteralNode) {
            cursor = EditorCursor(
              parentId: parentInfo.parentId,
              path: parentInfo.path,
              index: foundIndex + 1,
              subIndex: 0,
            );
          } else {
            final insertIndex = foundIndex + 1;
            parentList.insert(insertIndex, LiteralNode(text: ""));
            cursor = EditorCursor(
              parentId: parentInfo.parentId,
              path: parentInfo.path,
              index: insertIndex,
              subIndex: 0,
            );
          }
        }
      } else {
        // The last node was a LiteralNode that got merged
        final mergedNode = parentList[mergeStartIndex];
        if (mergedNode is LiteralNode) {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: mergedNode.text.length,
          );
        } else {
          cursor = EditorCursor(
            parentId: parentInfo.parentId,
            path: parentInfo.path,
            index: mergeStartIndex,
            subIndex: 0,
          );
        }
      }
    }

    _notifyStructureChanged();
  }

  // ============== REMOVE METHODS ==============
  void _removeExponent(ExponentNode exp) {
    final parentInfo = _findParentListOf(exp.id);
    if (parentInfo == null) return;
    final parentList = parentInfo.list;
    final expIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (expIndex > 0 && parentList[expIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[expIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(expIndex);
    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (expIndex > 0) ? expIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeParenthesis(ParenthesisNode paren) {
    final parentInfo = _findParentListOf(paren.id);
    if (parentInfo == null) return;
    final parentList = parentInfo.list;
    final parenIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (parenIndex > 0 && parentList[parenIndex - 1] is LiteralNode) {
      textLengthBefore =
          (parentList[parenIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(parenIndex);
    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (parenIndex > 0) ? parenIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeNewline(NewlineNode newline) {
    final parentInfo = _findParentListOf(newline.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final newlineIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (newlineIndex > 0 && parentList[newlineIndex - 1] is LiteralNode) {
      textLengthBefore =
          (parentList[newlineIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(newlineIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (newlineIndex > 0) ? newlineIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeTrig(TrigNode trig) {
    final parentInfo = _findParentListOf(trig.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final trigIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (trigIndex > 0 && parentList[trigIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[trigIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(trigIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (trigIndex > 0) ? trigIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeRoot(RootNode root) {
    final parentInfo = _findParentListOf(root.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final rootIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (rootIndex > 0 && parentList[rootIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[rootIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(rootIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (rootIndex > 0) ? rootIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removePermutation(PermutationNode perm) {
    final parentInfo = _findParentListOf(perm.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final permIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (permIndex > 0 && parentList[permIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[permIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(permIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (permIndex > 0) ? permIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeCombination(CombinationNode comb) {
    final parentInfo = _findParentListOf(comb.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final combIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (combIndex > 0 && parentList[combIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[combIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(combIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (combIndex > 0) ? combIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeSummation(SummationNode sum) {
    final parentInfo = _findParentListOf(sum.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final sumIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (sumIndex > 0 && parentList[sumIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[sumIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(sumIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (sumIndex > 0) ? sumIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeProduct(ProductNode prod) {
    final parentInfo = _findParentListOf(prod.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final prodIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (prodIndex > 0 && parentList[prodIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[prodIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(prodIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (prodIndex > 0) ? prodIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeDerivative(DerivativeNode diff) {
    final parentInfo = _findParentListOf(diff.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final diffIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (diffIndex > 0 && parentList[diffIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[diffIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(diffIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (diffIndex > 0) ? diffIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeIntegral(IntegralNode integ) {
    final parentInfo = _findParentListOf(integ.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final integIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (integIndex > 0 && parentList[integIndex - 1] is LiteralNode) {
      textLengthBefore =
          (parentList[integIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(integIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (integIndex > 0) ? integIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeAns(AnsNode ans) {
    final parentInfo = _findParentListOf(ans.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final ansIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (ansIndex > 0 && parentList[ansIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[ansIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(ansIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (ansIndex > 0) ? ansIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _removeLog(LogNode log) {
    final parentInfo = _findParentListOf(log.id);
    if (parentInfo == null) return;

    final parentList = parentInfo.list;
    final logIndex = parentInfo.index;

    int textLengthBefore = 0;
    if (logIndex > 0 && parentList[logIndex - 1] is LiteralNode) {
      textLengthBefore = (parentList[logIndex - 1] as LiteralNode).text.length;
    }

    parentList.removeAt(logIndex);

    if (parentList.isEmpty) {
      parentList.add(LiteralNode());
      cursor = EditorCursor(
        parentId: parentInfo.parentId,
        path: parentInfo.path,
        index: 0,
        subIndex: 0,
      );
      _notifyStructureChanged();
      return;
    }

    int mergeStartIndex = (logIndex > 0) ? logIndex - 1 : 0;
    _mergeAdjacentLiteralsFrom(parentList, mergeStartIndex);
    _positionCursorAtOffset(
      parentList,
      mergeStartIndex,
      textLengthBefore,
      parentInfo.parentId,
      parentInfo.path,
    );
    _notifyStructureChanged();
  }

  void _positionCursorAtOffset(
    List<MathNode> list,
    int nodeIndex,
    int targetOffset,
    String? parentId,
    String? path,
  ) {
    if (nodeIndex >= list.length) nodeIndex = list.length - 1;
    if (nodeIndex < 0) nodeIndex = 0;
    final node = list[nodeIndex];
    if (node is LiteralNode) {
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: nodeIndex,
        subIndex: targetOffset.clamp(0, node.text.length),
      );
    } else {
      cursor = EditorCursor(
        parentId: parentId,
        path: path,
        index: nodeIndex,
        subIndex: 0,
      );
    }
  }

  void moveRight() {
    final siblings = _resolveSiblingList();
    final node = _resolveCursorNode();

    if (node is LiteralNode) {
      if (cursor.subIndex < node.text.length) {
        cursor = cursor.copyWith(subIndex: cursor.subIndex + 1);
      } else if (cursor.index < siblings.length - 1) {
        final nextNode = siblings[cursor.index + 1];
        if (nextNode is LiteralNode) {
          cursor = cursor.copyWith(index: cursor.index + 1, subIndex: 0);
        } else if (nextNode is NewlineNode) {
          if (cursor.index + 2 < siblings.length) {
            cursor = cursor.copyWith(index: cursor.index + 2, subIndex: 0);
          }
        } else if (nextNode is ConstantNode || nextNode is UnitVectorNode) {
          _positionAfterAtomic(
            siblings,
            cursor.index + 1,
            cursor.parentId,
            cursor.path,
          );
        } else {
          // Enter any composite node (fraction, exponent, parenthesis, ans,
          // trig, root, log, permutation, combination, sum, product,
          // integral, derivative).
          _moveCursorIntoNodeStart(nextNode);
        }
      } else if (cursor.parentId != null) {
        _exitNestedStructureRight();
      }
      notifyListeners();
    }
  }

  void moveLeft() {
    if (cursor.subIndex > 0) {
      cursor = cursor.copyWith(subIndex: cursor.subIndex - 1);
      notifyListeners();
      return;
    }

    final siblings = _resolveSiblingList();
    if (cursor.index > 0) {
      final prevNode = siblings[cursor.index - 1];
      if (prevNode is LiteralNode) {
        cursor = cursor.copyWith(
          index: cursor.index - 1,
          subIndex: prevNode.text.length,
        );
      } else if (prevNode is NewlineNode) {
        if (cursor.index - 2 >= 0) {
          final beforeNewline = siblings[cursor.index - 2];
          if (beforeNewline is LiteralNode) {
            cursor = cursor.copyWith(
              index: cursor.index - 2,
              subIndex: beforeNewline.text.length,
            );
          }
        }
      } else if (prevNode is ConstantNode || prevNode is UnitVectorNode) {
        _positionBeforeAtomic(
          siblings,
          cursor.index - 1,
          cursor.parentId,
          cursor.path,
        );
      } else {
        // Enter any composite node from its end (fraction, exponent,
        // parenthesis, ans, trig, root, log, permutation, combination, sum,
        // product, integral, derivative).
        _moveCursorIntoNodeEnd(prevNode);
      }
      notifyListeners();
      return;
    }

    if (cursor.parentId != null) {
      _exitNestedStructureLeft();
      notifyListeners();
    }
  }

  void _exitNestedStructureRight() {
    final parent = _findNode(expression, cursor.parentId!);

    if (parent is FractionNode) {
      if (cursor.path == 'num') {
        _moveCursorToStartOfList(parent.denominator, parent.id, 'den');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is ExponentNode) {
      if (cursor.path == 'base') {
        _moveCursorToStartOfList(parent.power, parent.id, 'pow');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is ParenthesisNode) {
      _moveCursorAfterNode(parent.id);
    } else if (parent is TrigNode) {
      _moveCursorAfterNode(parent.id);
    } else if (parent is RootNode) {
      if (cursor.path == 'index') {
        _moveCursorToStartOfList(parent.radicand, parent.id, 'radicand');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is LogNode) {
      if (cursor.path == 'base') {
        _moveCursorToStartOfList(parent.argument, parent.id, 'arg');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is PermutationNode) {
      if (cursor.path == 'n') {
        _moveCursorToStartOfList(parent.r, parent.id, 'r');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is CombinationNode) {
      if (cursor.path == 'n') {
        _moveCursorToStartOfList(parent.r, parent.id, 'r');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is SummationNode) {
      if (cursor.path == 'var' ||
          cursor.path == 'lower' ||
          cursor.path == 'upper') {
        _moveCursorToStartOfList(parent.body, parent.id, 'body');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is DerivativeNode) {
      if (cursor.path == 'var' || cursor.path == 'at') {
        _moveCursorToStartOfList(parent.body, parent.id, 'body');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is IntegralNode) {
      if (cursor.path == 'var' ||
          cursor.path == 'lower' ||
          cursor.path == 'upper') {
        _moveCursorToStartOfList(parent.body, parent.id, 'body');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is ProductNode) {
      if (cursor.path == 'var' ||
          cursor.path == 'lower' ||
          cursor.path == 'upper') {
        _moveCursorToStartOfList(parent.body, parent.id, 'body');
      } else {
        _moveCursorAfterNode(parent.id);
      }
    } else if (parent is AnsNode) {
      _moveCursorAfterNode(parent.id);
    }
  }

  void _exitNestedStructureLeft() {
    final parent = _findNode(expression, cursor.parentId!);

    if (parent is FractionNode) {
      if (cursor.path == 'den') {
        _moveCursorToEndOfList(parent.numerator, parent.id, 'num');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is ExponentNode) {
      if (cursor.path == 'pow') {
        _moveCursorToEndOfList(parent.base, parent.id, 'base');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is ParenthesisNode) {
      _moveCursorBeforeNode(parent.id);
    } else if (parent is TrigNode) {
      _moveCursorBeforeNode(parent.id);
    } else if (parent is RootNode) {
      if (cursor.path == 'radicand') {
        if (!parent.isSquareRoot) {
          _moveCursorToEndOfList(parent.index, parent.id, 'index');
        } else {
          _moveCursorBeforeNode(parent.id);
        }
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is LogNode) {
      if (cursor.path == 'arg') {
        if (!parent.isNaturalLog) {
          _moveCursorToEndOfList(parent.base, parent.id, 'base');
        } else {
          _moveCursorBeforeNode(parent.id);
        }
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is PermutationNode) {
      if (cursor.path == 'r') {
        _moveCursorToEndOfList(parent.n, parent.id, 'n');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is CombinationNode) {
      if (cursor.path == 'r') {
        _moveCursorToEndOfList(parent.n, parent.id, 'n');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is SummationNode) {
      if (cursor.path == 'body') {
        _moveCursorToEndOfList(parent.lower, parent.id, 'lower');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is DerivativeNode) {
      if (cursor.path == 'body') {
        _moveCursorToEndOfList(parent.at, parent.id, 'at');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is IntegralNode) {
      if (cursor.path == 'body') {
        _moveCursorToEndOfList(parent.lower, parent.id, 'lower');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is ProductNode) {
      if (cursor.path == 'body') {
        _moveCursorToEndOfList(parent.lower, parent.id, 'lower');
      } else {
        _moveCursorBeforeNode(parent.id);
      }
    } else if (parent is AnsNode) {
      _moveCursorBeforeNode(parent.id);
    }
  }

  /// Gets the serialized expression string for solving
  String getExpression() {
    return MathExpressionSerializer.serialize(expression);
  }

  /// Gets variables used in the expression
  Set<String> getVariables() {
    return MathExpressionSerializer.extractVariables(expression);
  }

  /// Checks if current expression is an equation
  bool isEquation() {
    return MathExpressionSerializer.isEquation(expression);
  }

  void navigateTo({
    required String? parentId,
    required String? path,
    required int index,
    required int subIndex,
  }) {
    cursor = EditorCursor(
      parentId: parentId,
      path: path,
      index: index,
      subIndex: subIndex,
    );
    notifyListeners();
  }

  // ============== SELECTION STATE ==============
  SelectionRange? _selection;
  SelectionRange? get selection => _selection;
  bool get hasSelection => _selection != null && !_selection!.isEmpty;

  // Static clipboard shared across all instances
  static MathClipboard? _clipboard;
  static MathClipboard? get clipboard => _clipboard;
  static void setClipboard(MathClipboard? value) => _clipboard = value;

  // Container key for coordinate conversion
  GlobalKey? _containerKey;
  void setContainerKey(GlobalKey key) => _containerKey = key;
  GlobalKey? get containerKey => _containerKey;

  // ============== SELECTION OPERATIONS ==============

  /// Select word/element at position (for long-press)

  /// Select all content at root level
  void selectAll() {
    if (expression.isEmpty) return;

    final lastNode = expression.last;
    int lastCharIndex = lastNode is LiteralNode ? lastNode.text.length : 1;

    _selection = SelectionRange(
      start: const SelectionAnchor(
        parentId: null,
        path: null,
        nodeIndex: 0,
        charIndex: 0,
      ),
      end: SelectionAnchor(
        parentId: null,
        path: null,
        nodeIndex: expression.length - 1,
        charIndex: lastCharIndex,
      ),
    );

    notifyListeners();
  }

  // ============== CLIPBOARD OPERATIONS ==============

  /// Copy selected content to clipboard
  MathClipboard? copySelection() {
    if (!hasSelection) return null;

    final norm = _selection!.normalized;
    final siblings = _resolveNodeListForSelection(
      norm.start.parentId,
      norm.start.path,
    );
    if (siblings == null) return null;

    List<MathNode> copiedNodes = [];
    String? leadingText;
    String? trailingText;

    for (
      int i = norm.start.nodeIndex;
      i <= norm.end.nodeIndex && i < siblings.length;
      i++
    ) {
      final node = siblings[i];

      if (i == norm.start.nodeIndex && i == norm.end.nodeIndex) {
        // Single node - partial selection
        if (node is LiteralNode) {
          final startIdx = norm.start.charIndex.clamp(0, node.text.length);
          final endIdx = norm.end.charIndex.clamp(0, node.text.length);
          final text = node.text.substring(startIdx, endIdx);
          if (text.isNotEmpty) {
            leadingText = text;
          }
        } else {
          copiedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else if (i == norm.start.nodeIndex) {
        // First node
        if (node is LiteralNode) {
          final startIdx = norm.start.charIndex.clamp(0, node.text.length);
          final text = node.text.substring(startIdx);
          if (text.isNotEmpty) {
            leadingText = text;
          }
        } else {
          copiedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else if (i == norm.end.nodeIndex) {
        // Last node
        if (node is LiteralNode) {
          final endIdx = norm.end.charIndex.clamp(0, node.text.length);
          final text = node.text.substring(0, endIdx);
          if (text.isNotEmpty) {
            trailingText = text;
          }
        } else {
          copiedNodes.add(MathClipboard.deepCopyNode(node));
        }
      } else {
        // Middle nodes - full copy
        copiedNodes.add(MathClipboard.deepCopyNode(node));
      }
    }

    _clipboard = MathClipboard(
      nodes: copiedNodes,
      leadingText: leadingText,
      trailingText: trailingText,
    );

    return _clipboard;
  }

  /// Cut selected content
  void cutSelection() {
    if (!hasSelection) return;

    saveStateForUndo();
    copySelection();
    deleteSelection();
  }

  /// Delete selected content
  void deleteSelection() {
    if (!hasSelection) return;

    final norm = _selection!.normalized;
    final siblings = _resolveNodeListForSelection(
      norm.start.parentId,
      norm.start.path,
    );
    if (siblings == null) return;

    if (norm.start.nodeIndex == norm.end.nodeIndex) {
      // Same node
      final node = siblings[norm.start.nodeIndex];
      if (node is LiteralNode) {
        // Character deletion within literal
        final startIdx = norm.start.charIndex.clamp(0, node.text.length);
        final endIdx = norm.end.charIndex.clamp(0, node.text.length);
        node.text =
            node.text.substring(0, startIdx) + node.text.substring(endIdx);

        cursor = EditorCursor(
          parentId: norm.start.parentId,
          path: norm.start.path,
          index: norm.start.nodeIndex,
          subIndex: startIdx,
        );
      } else {
        // Composite node (FractionNode, ExponentNode, etc.) - delete the whole
        // node, then merge the literals that surrounded it and place the caret
        // at the join point (matching the behaviour of the _remove* helpers).
        final int removeIndex = norm.start.nodeIndex;
        siblings.removeAt(removeIndex);

        if (siblings.isNotEmpty) {
          final int beforeIndex = removeIndex - 1;
          if (beforeIndex >= 0 && siblings[beforeIndex] is LiteralNode) {
            final int joinOffset =
                (siblings[beforeIndex] as LiteralNode).text.length;
            _mergeAdjacentLiteralsFrom(siblings, beforeIndex);
            cursor = EditorCursor(
              parentId: norm.start.parentId,
              path: norm.start.path,
              index: beforeIndex,
              subIndex: joinOffset,
            );
          } else {
            cursor = EditorCursor(
              parentId: norm.start.parentId,
              path: norm.start.path,
              index: removeIndex.clamp(0, siblings.length - 1),
              subIndex: 0,
            );
          }
        }
      }
    } else {
      // Multiple nodes selected
      final firstNode = siblings[norm.start.nodeIndex];
      String remainingFromFirst = '';
      if (firstNode is LiteralNode) {
        final startIdx = norm.start.charIndex.clamp(0, firstNode.text.length);
        remainingFromFirst = firstNode.text.substring(0, startIdx);
      }

      final lastNode = siblings[norm.end.nodeIndex];
      String remainingFromLast = '';
      if (lastNode is LiteralNode) {
        final endIdx = norm.end.charIndex.clamp(0, lastNode.text.length);
        remainingFromLast = lastNode.text.substring(endIdx);
      }

      // Remove nodes from end to start (including composite nodes)
      for (int i = norm.end.nodeIndex; i > norm.start.nodeIndex; i--) {
        if (i < siblings.length) {
          siblings.removeAt(i);
        }
      }

      // Handle first node
      if (firstNode is LiteralNode) {
        firstNode.text = remainingFromFirst + remainingFromLast;
        cursor = EditorCursor(
          parentId: norm.start.parentId,
          path: norm.start.path,
          index: norm.start.nodeIndex,
          subIndex: remainingFromFirst.length,
        );
      } else if (norm.start.charIndex == 0) {
        // First node is composite and fully selected - remove it too.
        siblings.removeAt(norm.start.nodeIndex);
        // Add remaining text if any
        if (remainingFromLast.isNotEmpty) {
          if (norm.start.nodeIndex < siblings.length &&
              siblings[norm.start.nodeIndex] is LiteralNode) {
            (siblings[norm.start.nodeIndex] as LiteralNode).text =
                remainingFromLast +
                (siblings[norm.start.nodeIndex] as LiteralNode).text;
          } else {
            siblings.insert(
              norm.start.nodeIndex,
              LiteralNode(text: remainingFromLast),
            );
          }
        }
        cursor = EditorCursor(
          parentId: norm.start.parentId,
          path: norm.start.path,
          index: norm.start.nodeIndex.clamp(0, siblings.length - 1),
          subIndex: 0,
        );
      } else {
        // Selection starts at the right edge of a composite first node
        // (charIndex == 1): keep the composite and re-attach the surviving
        // tail of the last node just after it. Without this the tail text was
        // silently dropped.
        final int insertAt = norm.start.nodeIndex + 1;
        if (insertAt < siblings.length && siblings[insertAt] is LiteralNode) {
          (siblings[insertAt] as LiteralNode).text =
              remainingFromLast + (siblings[insertAt] as LiteralNode).text;
        } else {
          siblings.insert(insertAt, LiteralNode(text: remainingFromLast));
        }
        cursor = EditorCursor(
          parentId: norm.start.parentId,
          path: norm.start.path,
          index: insertAt.clamp(0, siblings.length - 1),
          subIndex: 0,
        );
      }
    }

    // Ensure there's always at least one node
    if (siblings.isEmpty) {
      siblings.add(LiteralNode());
      cursor = EditorCursor(
        parentId: norm.start.parentId,
        path: norm.start.path,
        index: 0,
        subIndex: 0,
      );
    }

    // Clear selection FIRST, then notify
    _selection = null;
    onSelectionCleared?.call();

    _structureVersion++;
    notifyListeners();
    onResultChanged?.call();

    onCalculate();
  }

  /// Paste clipboard content at cursor
  void pasteClipboard() {
    if (_clipboard == null || _clipboard!.isEmpty) return;

    saveStateForUndo();

    // Delete selection first if any
    if (hasSelection) {
      deleteSelection();
    }

    final siblings = _resolveSiblingList();
    final existing =
        cursor.index < siblings.length ? siblings[cursor.index] : null;

    // If the cursor is on a composite/atomic node (or past the end), there is
    // no literal to split, so create an empty literal anchor at the cursor
    // position. Without this, paste silently did nothing on such nodes.
    late final LiteralNode target;
    if (existing is LiteralNode) {
      target = existing;
    } else {
      final int insertPos = cursor.index.clamp(0, siblings.length);
      target = LiteralNode(text: '');
      siblings.insert(insertPos, target);
      cursor = EditorCursor(
        parentId: cursor.parentId,
        path: cursor.path,
        index: insertPos,
        subIndex: 0,
      );
    }

    {
      final text = target.text;
      final cursorPos = cursor.subIndex.clamp(0, text.length);
      final before = text.substring(0, cursorPos);
      final after = text.substring(cursorPos);

      // Build pasted content
      String pastedText = '';
      if (_clipboard!.leadingText != null) {
        pastedText += _clipboard!.leadingText!;
      }
      if (_clipboard!.trailingText != null) {
        pastedText += _clipboard!.trailingText!;
      }

      if (_clipboard!.nodes.isEmpty) {
        // Just text - simple insert
        target.text = before + pastedText + after;
        cursor = cursor.copyWith(subIndex: before.length + pastedText.length);
      } else {
        // Has complex nodes
        target.text = before + (_clipboard!.leadingText ?? '');

        int insertIndex = cursor.index + 1;

        // Insert copied nodes
        for (final node in _clipboard!.nodes) {
          siblings.insert(insertIndex, MathClipboard.deepCopyNode(node));
          insertIndex++;
        }

        // Insert trailing text node
        final trailingNode = LiteralNode(
          text: (_clipboard!.trailingText ?? '') + after,
        );
        siblings.insert(insertIndex, trailingNode);

        cursor = EditorCursor(
          parentId: cursor.parentId,
          path: cursor.path,
          index: insertIndex,
          subIndex: (_clipboard!.trailingText ?? '').length,
        );
      }
    }

    _structureVersion++;
    notifyListeners();
    onResultChanged?.call();

    onCalculate();
  }

  /// Notify listeners and recalculate (used by SelectionWrapper)

  void notifyAndRecalculate() {
    _rebuildComplexNodeMap(); // Add this line
    _structureVersion++;
    notifyListeners();
    onCalculate();
    onResultChanged?.call();
  }
  // ============== SELECTION HELPERS ==============

  // Add this field
  final Map<String, ComplexNodeInfo> _complexNodeMap = {};

  /// Rebuild the complex node map from the expression tree
  void _rebuildComplexNodeMap() {
    _complexNodeMap.clear();
    _buildComplexNodeMapRecursive(expression, null, null);
  }

  void _buildComplexNodeMapRecursive(
    List<MathNode> nodes,
    String? parentId,
    String? path,
  ) {
    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];

      // Register all non-literal nodes
      if (node is! LiteralNode) {
        _complexNodeMap[node.id] = ComplexNodeInfo(
          node: node,
          parentId: parentId,
          path: path,
          index: i,
          rect: Rect.zero,
        );
      }

      // Recurse into children
      if (node is FractionNode) {
        _buildComplexNodeMapRecursive(node.numerator, node.id, 'num');
        _buildComplexNodeMapRecursive(node.denominator, node.id, 'den');
      } else if (node is ExponentNode) {
        _buildComplexNodeMapRecursive(node.base, node.id, 'base');
        _buildComplexNodeMapRecursive(node.power, node.id, 'pow');
      } else if (node is TrigNode) {
        _buildComplexNodeMapRecursive(node.argument, node.id, 'arg');
      } else if (node is RootNode) {
        _buildComplexNodeMapRecursive(node.index, node.id, 'index');
        _buildComplexNodeMapRecursive(node.radicand, node.id, 'radicand');
      } else if (node is LogNode) {
        _buildComplexNodeMapRecursive(node.base, node.id, 'base');
        _buildComplexNodeMapRecursive(node.argument, node.id, 'arg');
      } else if (node is ParenthesisNode) {
        _buildComplexNodeMapRecursive(node.content, node.id, 'content');
      } else if (node is PermutationNode) {
        _buildComplexNodeMapRecursive(node.n, node.id, 'n');
        _buildComplexNodeMapRecursive(node.r, node.id, 'r');
      } else if (node is CombinationNode) {
        _buildComplexNodeMapRecursive(node.n, node.id, 'n');
        _buildComplexNodeMapRecursive(node.r, node.id, 'r');
      } else if (node is SummationNode) {
        _buildComplexNodeMapRecursive(node.variable, node.id, 'var');
        _buildComplexNodeMapRecursive(node.lower, node.id, 'lower');
        _buildComplexNodeMapRecursive(node.upper, node.id, 'upper');
        _buildComplexNodeMapRecursive(node.body, node.id, 'body');
      } else if (node is DerivativeNode) {
        _buildComplexNodeMapRecursive(node.variable, node.id, 'var');
        if (node.isDefinite) {
          _buildComplexNodeMapRecursive(node.at, node.id, 'at');
        }
        _buildComplexNodeMapRecursive(node.body, node.id, 'body');
      } else if (node is IntegralNode) {
        _buildComplexNodeMapRecursive(node.variable, node.id, 'var');
        if (node.isDefinite) {
          _buildComplexNodeMapRecursive(node.lower, node.id, 'lower');
          _buildComplexNodeMapRecursive(node.upper, node.id, 'upper');
        }
        _buildComplexNodeMapRecursive(node.body, node.id, 'body');
      } else if (node is ProductNode) {
        _buildComplexNodeMapRecursive(node.variable, node.id, 'var');
        _buildComplexNodeMapRecursive(node.lower, node.id, 'lower');
        _buildComplexNodeMapRecursive(node.upper, node.id, 'upper');
        _buildComplexNodeMapRecursive(node.body, node.id, 'body');
      } else if (node is AnsNode) {
        _buildComplexNodeMapRecursive(node.index, node.id, 'index');
      }
    }
  }

  /// Get the complex node info for a given parent ID
  ComplexNodeInfo? getComplexNodeInfo(String nodeId) {
    return _complexNodeMap[nodeId];
  }

  // ============== CORE SELECTION UPDATE ==============

  void clearSelection({bool notify = true}) {
    if (_selection == null) return;

    _selection = null;
    onSelectionCleared?.call();

    if (notify) {
      notifyListeners();
    }
  }

  // ============== HELPER METHODS ==============

  List<MathNode>? _resolveNodeListForSelection(String? parentId, String? path) {
    if (parentId == null && path == null) {
      return expression;
    }

    final parent = _findNode(expression, parentId!);
    if (parent == null) return null;

    if (parent is FractionNode) {
      if (path == 'num' || path == 'numerator') return parent.numerator;
      if (path == 'den' || path == 'denominator') return parent.denominator;
    } else if (parent is ExponentNode) {
      if (path == 'base') return parent.base;
      if (path == 'pow' || path == 'power') return parent.power;
    } else if (parent is TrigNode) {
      if (path == 'arg' || path == 'argument') return parent.argument;
    } else if (parent is RootNode) {
      if (path == 'index') return parent.index;
      if (path == 'radicand') return parent.radicand;
    } else if (parent is LogNode) {
      if (path == 'base') return parent.base;
      if (path == 'arg' || path == 'argument') return parent.argument;
    } else if (parent is ParenthesisNode) {
      if (path == 'content') return parent.content;
    } else if (parent is PermutationNode) {
      if (path == 'n') return parent.n;
      if (path == 'r') return parent.r;
    } else if (parent is CombinationNode) {
      if (path == 'n') return parent.n;
      if (path == 'r') return parent.r;
    } else if (parent is SummationNode) {
      if (path == 'var') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is DerivativeNode) {
      if (path == 'var') return parent.variable;
      if (path == 'at') return parent.at;
      if (path == 'body') return parent.body;
    } else if (parent is IntegralNode) {
      if (path == 'var') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is ProductNode) {
      if (path == 'var') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is AnsNode) {
      if (path == 'index') return parent.index;
    }

    return null;
  }

  // Add this setter method
  void setSelection(SelectionRange? range) {
    _selection = range;
    notifyListeners();
  }

  // Replace startHandleDrag
  void startHandleDrag(bool isStartHandle) {
    _selectionManager.startDrag(isStartHandle);
  }

  // Replace endHandleDrag
  void endHandleDrag() {
    _selectionManager.endDrag();
  }

  // Replace updateSelectionHandle
  void updateSelectionHandle(bool isStartHandle, Offset localPosition) {
    _selectionManager.updateDrag(localPosition);
  }

  // Replace selectAtPosition
  void selectAtPosition(Offset position) {
    _selectionManager.selectAtPosition(position);
  }

  Rect? getContentBounds() {
    if (_contentBoundsValid) return _cachedContentBounds;
    if (_layoutRegistry.isEmpty) return null;

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final info in _layoutRegistry.values) {
      minX = math.min(minX, info.rect.left);
      maxX = math.max(maxX, info.rect.right);
      minY = math.min(minY, info.rect.top);
      maxY = math.max(maxY, info.rect.bottom);
    }

    if (minX == double.infinity) return null;

    _cachedContentBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
    _contentBoundsValid = true;
    return _cachedContentBounds;
  }

  /// Updates all AnsNode indices in the expression based on a cell insertion or removal.
  /// [atIndex] is the index where the change occurred.
  /// [delta] is typically +1 for insertion and -1 for removal.
  void updateAnsReferences(int atIndex, int delta) {
    _updateAnsIndicesRecursive(expression, atIndex, delta);
    // Serialize to update the 'expr' string used for computation trigger
    expr = MathExpressionSerializer.serialize(expression);
    _structureVersion++;
    notifyListeners();
  }

  void _updateAnsIndicesRecursive(
    List<MathNode> nodes,
    int atIndex,
    int delta,
  ) {
    for (final node in nodes) {
      if (node is AnsNode) {
        String idxStr = MathExpressionSerializer.serialize(node.index);
        int? idx = int.tryParse(idxStr);
        if (idx != null && idx >= atIndex) {
          int newIdx = idx + delta;
          if (newIdx < 0) newIdx = 0;
          node.index = [LiteralNode(text: newIdx.toString())];
        }
      }

      if (node is FractionNode) {
        _updateAnsIndicesRecursive(node.numerator, atIndex, delta);
        _updateAnsIndicesRecursive(node.denominator, atIndex, delta);
      } else if (node is ExponentNode) {
        _updateAnsIndicesRecursive(node.base, atIndex, delta);
        _updateAnsIndicesRecursive(node.power, atIndex, delta);
      } else if (node is ParenthesisNode) {
        _updateAnsIndicesRecursive(node.content, atIndex, delta);
      } else if (node is TrigNode) {
        _updateAnsIndicesRecursive(node.argument, atIndex, delta);
      } else if (node is RootNode) {
        _updateAnsIndicesRecursive(node.index, atIndex, delta);
        _updateAnsIndicesRecursive(node.radicand, atIndex, delta);
      } else if (node is LogNode) {
        _updateAnsIndicesRecursive(node.base, atIndex, delta);
        _updateAnsIndicesRecursive(node.argument, atIndex, delta);
      } else if (node is PermutationNode) {
        _updateAnsIndicesRecursive(node.n, atIndex, delta);
        _updateAnsIndicesRecursive(node.r, atIndex, delta);
      } else if (node is CombinationNode) {
        _updateAnsIndicesRecursive(node.n, atIndex, delta);
        _updateAnsIndicesRecursive(node.r, atIndex, delta);
      } else if (node is SummationNode) {
        _updateAnsIndicesRecursive(node.lower, atIndex, delta);
        _updateAnsIndicesRecursive(node.upper, atIndex, delta);
        _updateAnsIndicesRecursive(node.body, atIndex, delta);
      } else if (node is ProductNode) {
        _updateAnsIndicesRecursive(node.lower, atIndex, delta);
        _updateAnsIndicesRecursive(node.upper, atIndex, delta);
        _updateAnsIndicesRecursive(node.body, atIndex, delta);
      } else if (node is IntegralNode) {
        _updateAnsIndicesRecursive(node.lower, atIndex, delta);
        _updateAnsIndicesRecursive(node.upper, atIndex, delta);
        _updateAnsIndicesRecursive(node.body, atIndex, delta);
      } else if (node is DerivativeNode) {
        _updateAnsIndicesRecursive(node.at, atIndex, delta);
        _updateAnsIndicesRecursive(node.body, atIndex, delta);
      } else if (node is ComplexNode) {
        _updateAnsIndicesRecursive(node.content, atIndex, delta);
      }
    }
  }
}

class _ParentListInfo {
  final List<MathNode> list;
  final int index;
  final String? parentId;
  final String? path;
  _ParentListInfo(this.list, this.index, this.parentId, this.path);
}

class _MultiplicationChainResult {
  final List<MathNode> nodes;
  final int removeFromIndex;
  final String? prefixToKeep;
  final int? prefixNodeIndex;

  _MultiplicationChainResult({
    required this.nodes,
    required this.removeFromIndex,
    this.prefixToKeep,
    this.prefixNodeIndex,
  });
}

class SelectionPathStep {
  final String? parentId;
  final String? path;
  final int nodeIndex;

  SelectionPathStep({this.parentId, this.path, required this.nodeIndex});
}

extension NodeLayoutInfoExt on NodeLayoutInfo {
  SelectionAnchor toAnchor(int charIdx) {
    return SelectionAnchor(
      parentId: parentId,
      path: path,
      nodeIndex: index,
      charIndex: charIdx,
    );
  }
}

class CursorPaintNotifier extends ChangeNotifier {
  Rect _rect = Rect.zero;

  Rect get rect => _rect;

  void updateRect(Rect newRect) {
    if (_rect != newRect) {
      _rect = newRect;
      notifyListeners();
    }
  }

  // Direct paint callback - bypasses notification system
  VoidCallback? onNeedsPaint;

  void updateRectDirect(Rect newRect) {
    _rect = newRect;
    onNeedsPaint?.call();
  }
}
