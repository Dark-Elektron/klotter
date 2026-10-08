part of 'math_editor_controller.dart';

/// Typing: inserting characters and every kind of node, and moving the
/// cursor into and out of what was inserted.
extension EditorInsertion on MathEditorController {
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

    // Everything above this line either wraps the selection or hands off to a
    // method that consumes it itself. From here the character is a plain
    // insertion, and a plain insertion replaces what is selected.
    _consumeSelectionForInsert();

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

    final displayChar = MathEditorController._mapToDisplayChar(char);
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

  bool _isOperator(String char) {
    return char == '+' ||
        char == '-' ||
        char == '*' ||
        MathTextStyle.relationalSigns.contains(char) ||
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
    _notifyListeners();
  }

  // ============= NODE INSERT FUNCTIONS ==============
  void insertSquare() {
    saveStateForUndo();
    _consumeSelectionForInsert();

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

    while (operandStart > 0 &&
        !MathEditorController._isWordBoundary(text[operandStart - 1])) {
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
    _consumeSelectionForInsert();

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

  /// Insert `z̲`, the complex variable.
  ///
  /// Goes in through the unit-vector path because it is one — the node
  /// extends UnitVectorNode so that every rule the editor already has for an
  /// indivisible glyph applies to it unchanged.
  void insertComplexVariable() => insertUnitVector('z', complexVariable: true);
  void insertUnitVector(String axis, {bool complexVariable = false}) {
    saveStateForUndo();
    _consumeSelectionForInsert();

    final siblings = _resolveSiblingList();
    final current = _resolveCursorNode();
    if (current is! LiteralNode) return;

    final String currentId = current.id;
    String text = current.text;
    int cursorPos = cursor.subIndex;
    int actualIndex = siblings.indexWhere((n) => n.id == currentId);

    String before = text.substring(0, cursorPos);
    String after = text.substring(cursorPos);

    final MathNode node =
        complexVariable ? ComplexVariableNode() : UnitVectorNode(axis);

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
    _consumeSelectionForInsert();

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
    _consumeSelectionForInsert();

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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();

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
    while (operandStart > 0 &&
        MathEditorController._isSerializedDigit(text[operandStart - 1])) {
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
    _consumeSelectionForInsert();

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
    while (operandStart > 0 &&
        MathEditorController._isSerializedDigit(text[operandStart - 1])) {
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
    _consumeSelectionForInsert();
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
        !MathEditorController._isNonMultiplyWordBoundary(
          text[operandStart - 1],
        )) {
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
    while (operandStart > 0 &&
        !MathEditorController._isWordBoundary(text[operandStart - 1])) {
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
        !MathEditorController._isNonMultiplyWordBoundaryForFraction(
          text,
          operandStart - 1,
        )) {
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

  // === OTHER HELPERS ===
  void _updateLiteralAtCursor(void Function(LiteralNode) edit) {
    final node = _resolveCursorNode();
    if (node is LiteralNode) edit(node);
  }

  /// Replace a live selection with whatever is about to be inserted.
  ///
  /// Typing over a selection replaces it, as in any text field. Only
  /// `deleteChar`, `pasteClipboard` and the parenthesis key used to check:
  /// every other key inserted at the caret and left the selection standing,
  /// still highlighted, so the next backspace deleted the old selection
  /// instead of the character just typed. After a select-all that is the whole
  /// expression.
  ///
  /// Callers snapshot for undo first, so the replacement is one undo step.
  /// This deliberately does not snapshot itself.
  void _consumeSelectionForInsert() {
    if (!hasSelection) return;
    deleteSelection();
  }

  /// Move the caret off a node it cannot edit.
  ///
  /// A cursor whose index lands on anything but a literal is inert: both
  /// `_updateLiteralAtCursor` and `deleteChar` resolve a non-literal and
  /// return without doing anything, so the keypad looks dead. Deleting a
  /// selection can land there — the literal the caret was going to sit in may
  /// be one of the nodes that just went — so it is checked in one place rather
  /// than trusted at each.
  void _ensureCursorInLiteral() {
    final List<MathNode> siblings = _resolveSiblingList();
    if (siblings.isEmpty) return;

    final int index = cursor.index;
    if (index >= 0 &&
        index < siblings.length &&
        siblings[index] is LiteralNode) {
      return;
    }

    if (index >= siblings.length) {
      // Past the end: anchor after the last node, making a literal when the
      // list ends on something else.
      _positionAfterAtomic(
        siblings,
        siblings.length - 1,
        cursor.parentId,
        cursor.path,
      );
      return;
    }

    _positionBeforeAtomic(
      siblings,
      index.clamp(0, siblings.length - 1),
      cursor.parentId,
      cursor.path,
    );
  }

  void _exitParenthesis() {
    String? currentParentId = cursor.parentId;
    while (currentParentId != null) {
      final parent = _findNode(expression, currentParentId);
      if (parent is ParenthesisNode) {
        _moveCursorAfterNode(parent.id);
        _notifyListeners();
        return;
      }
      final parentInfo = _findParentListOf(currentParentId);
      currentParentId = parentInfo?.parentId;
    }
  }
}
