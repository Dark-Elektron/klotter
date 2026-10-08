part of 'math_editor_controller.dart';

/// Backspace and its consequences: deleting characters, taking structures
/// apart node kind by node kind, and clearing.
extension EditorDeletion on MathEditorController {
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
    cursor = const EditorCursor(); // Reset cursor to initial state
    // The range pointed at nodes that no longer exist; left standing, the next
    // backspace deleted "the selection" out of the fresh literal.
    clearSelection(notify: false);
    _notifyStructureChanged();
  }

  void _handleDeleteInExponent(ExponentNode exp) {
    if (cursor.path == 'pow') {
      if (_isListEffectivelyEmpty(exp.power)) {
        _unwrapExponent(exp);
      } else {
        _moveCursorToEndOfList(exp.base, exp.id, 'base');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'base') {
      if (_isListEffectivelyEmpty(exp.base) &&
          _isListEffectivelyEmpty(exp.power)) {
        _removeExponent(exp);
      } else {
        _moveCursorBeforeNode(exp.id);
        recalculateCursorRect();
        _notifyListeners();
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
        _notifyListeners();
      }
    } else if (cursor.path == 'num') {
      if (_isListEffectivelyEmpty(frac.numerator) &&
          _isListEffectivelyEmpty(frac.denominator)) {
        _removeFraction(frac);
      } else {
        _moveCursorBeforeNode(frac.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    }
  }

  void _handleDeleteInParenthesis(ParenthesisNode paren) {
    if (_isListEffectivelyEmpty(paren.content)) {
      _removeParenthesis(paren);
    } else {
      _moveCursorBeforeNode(paren.id);
      recalculateCursorRect();
      _notifyListeners();
    }
  }

  void _handleDeleteInTrig(TrigNode trig) {
    if (_isListEffectivelyEmpty(trig.argument)) {
      _removeTrig(trig);
    } else {
      _moveCursorBeforeNode(trig.id);
      recalculateCursorRect();
      _notifyListeners();
    }
  }

  void _handleDeleteInRoot(RootNode root) {
    if (cursor.path == 'radicand') {
      if (_isListEffectivelyEmpty(root.radicand)) {
        _removeRoot(root);
      } else if (!root.isSquareRoot) {
        _moveCursorToEndOfList(root.index, root.id, 'index');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(root.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'index') {
      if (_isListEffectivelyEmpty(root.index) &&
          _isListEffectivelyEmpty(root.radicand)) {
        _removeRoot(root);
      } else {
        _moveCursorBeforeNode(root.id);
        recalculateCursorRect();
        _notifyListeners();
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
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(log.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'base') {
      if (_isListEffectivelyEmpty(log.base) &&
          _isListEffectivelyEmpty(log.argument)) {
        _removeLog(log);
      } else {
        _moveCursorBeforeNode(log.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    }
  }

  void _handleDeleteInPermutation(PermutationNode perm) {
    if (cursor.path == 'r') {
      if (_isListEffectivelyEmpty(perm.r)) {
        _moveCursorToEndOfList(perm.n, perm.id, 'n');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorToEndOfList(perm.n, perm.id, 'n');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'n') {
      if (_isListEffectivelyEmpty(perm.n) && _isListEffectivelyEmpty(perm.r)) {
        _removePermutation(perm);
      } else {
        _moveCursorBeforeNode(perm.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    }
  }

  void _handleDeleteInCombination(CombinationNode comb) {
    if (cursor.path == 'r') {
      if (_isListEffectivelyEmpty(comb.r)) {
        _moveCursorToEndOfList(comb.n, comb.id, 'n');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorToEndOfList(comb.n, comb.id, 'n');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'n') {
      if (_isListEffectivelyEmpty(comb.n) && _isListEffectivelyEmpty(comb.r)) {
        _removeCombination(comb);
      } else {
        _moveCursorBeforeNode(comb.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    }
  }

  void _handleDeleteInSummation(SummationNode sum) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(sum.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(sum.upper, sum.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(sum.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(sum.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(sum.lower, sum.id, 'lower');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        // Move to body if user pressed left or something, but usually backspace
        // from start of upper should go to... somewhere.
        // If we are at the start of upper, backspace should trigger this handler.
        _moveCursorToEndOfList(sum.body, sum.id, 'body');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(sum.lower)) {
        // Finally remove the node
        _removeSummation(sum);
      } else {
        _moveCursorToEndOfList(sum.upper, sum.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(sum.body, sum.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    }
  }

  void _handleDeleteInProduct(ProductNode prod) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(prod.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(prod.upper, prod.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(prod.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(prod.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(prod.lower, prod.id, 'lower');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorToEndOfList(prod.body, prod.id, 'body');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(prod.lower)) {
        // Finally remove the node
        _removeProduct(prod);
      } else {
        _moveCursorToEndOfList(prod.upper, prod.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(prod.body, prod.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    }
  }

  void _handleDeleteInDerivative(DerivativeNode diff) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(diff.body)) {
        // Move to 'at' field (value to be evaluated at)
        _moveCursorToEndOfList(diff.at, diff.id, 'at');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(diff.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'at') {
      if (_isListEffectivelyEmpty(diff.at)) {
        // Finally remove the node
        _removeDerivative(diff);
      } else {
        _moveCursorToEndOfList(diff.body, diff.id, 'body');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else {
      // From 'var' field
      _moveCursorToEndOfList(diff.body, diff.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    }
  }

  void _handleDeleteInIntegral(IntegralNode integ) {
    if (cursor.path == 'body') {
      if (_isListEffectivelyEmpty(integ.body)) {
        // Move to 'upper' limit
        _moveCursorToEndOfList(integ.upper, integ.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorBeforeNode(integ.id);
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'upper') {
      if (_isListEffectivelyEmpty(integ.upper)) {
        // Move to 'lower' limit
        _moveCursorToEndOfList(integ.lower, integ.id, 'lower');
        recalculateCursorRect();
        _notifyListeners();
      } else {
        _moveCursorToEndOfList(integ.body, integ.id, 'body');
        recalculateCursorRect();
        _notifyListeners();
      }
    } else if (cursor.path == 'lower') {
      if (_isListEffectivelyEmpty(integ.lower)) {
        // Finally remove the node
        _removeIntegral(integ);
      } else {
        _moveCursorToEndOfList(integ.upper, integ.id, 'upper');
        recalculateCursorRect();
        _notifyListeners();
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
      _notifyListeners();
    }
  }

  void _handleDeleteInAns(AnsNode ans) {
    if (_isListEffectivelyEmpty(ans.index)) {
      _removeAns(ans);
    } else {
      _moveCursorBeforeNode(ans.id);
      recalculateCursorRect();
      _notifyListeners();
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
        _notifyListeners();
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
      _notifyListeners();
    } else if (prevNode is ExponentNode) {
      _moveCursorToEndOfList(prevNode.power, prevNode.id, 'pow');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is ParenthesisNode) {
      _moveCursorToEndOfList(prevNode.content, prevNode.id, 'content');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is TrigNode) {
      _moveCursorToEndOfList(prevNode.argument, prevNode.id, 'arg');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is RootNode) {
      _moveCursorToEndOfList(prevNode.radicand, prevNode.id, 'radicand');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is LogNode) {
      _moveCursorToEndOfList(prevNode.argument, prevNode.id, 'arg');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is PermutationNode) {
      _moveCursorToEndOfList(prevNode.r, prevNode.id, 'r');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
    } else if (prevNode is CombinationNode) {
      _moveCursorToEndOfList(prevNode.r, prevNode.id, 'r');
      recalculateCursorRect();
      _notifyListeners();
    } else if (prevNode is SummationNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    } else if (prevNode is DerivativeNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    } else if (prevNode is IntegralNode) {
      _moveCursorToEndOfList(prevNode.variable, prevNode.id, 'var');
      recalculateCursorRect();
      _notifyListeners();
    } else if (prevNode is ProductNode) {
      _moveCursorToEndOfList(prevNode.body, prevNode.id, 'body');
      recalculateCursorRect();
      _notifyListeners();
    } else if (prevNode is AnsNode) {
      _moveCursorToEndOfList(prevNode.index, prevNode.id, 'index');
      recalculateCursorRect(); // ← ADD THIS
      _notifyListeners();
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
      _pendingCaretAnchors++;
      return;
    }
    if (nodes.first is! LiteralNode) {
      nodes.insert(0, LiteralNode(text: ""));
      _pendingCaretAnchors++;
    }
    if (nodes.last is! LiteralNode) {
      nodes.add(LiteralNode(text: ""));
      _pendingCaretAnchors++;
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
      _pendingCaretAnchors++;
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
      _pendingCaretAnchors++;
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
    _notifyListeners();
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
    _notifyListeners();
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
      return [
        MapEntry('index', node.index),
        MapEntry('radicand', node.radicand),
      ];
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
      _pendingCaretAnchors++;
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
      _pendingCaretAnchors++;
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
            // Atomic previous sibling (constant/unit vector/newline): the
            // caret sits between it and the target.
            //
            // Not on index i, which is the target itself: when the target is
            // anything but a literal that is a position nothing can type into
            // or delete from. This reuses the target when it is a literal and
            // makes an anchor between the two when it is not.
            _positionAfterAtomic(nodes, i - 1, grandParentId, path);
          }
        } else {
          // Before the first sibling. The caret needs a literal to sit in, so
          // make one when the target itself is not one.
          if (nodes[i] is! LiteralNode) {
            nodes.insert(0, LiteralNode(text: ""));
            _pendingCaretAnchors++;
          }
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
          if (nextNode is LiteralNode) {
            // The caret goes at the head of the literal that follows.
            cursor = EditorCursor(
              parentId: grandParentId,
              path: path,
              index: i + 1,
              subIndex: 0,
            );
          } else if (_childListsOf(nextNode).isEmpty) {
            // Atomic (constant/unit vector/newline): there is nothing to step
            // into and nothing to type into, and the old code parked the
            // caret on the symbol's own index — a position `insertCharacter`
            // and `deleteChar` both silently ignore. Anchor on the literal
            // before it, which is the node this call is positioning after.
            _positionBeforeAtomic(nodes, i + 1, grandParentId, path);
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

    // A cursor that is not in a literal should no longer be reachable, but if
    // one ever is again this is the only key that can get out of it: the whole
    // body below is a literal branch, so without this the caret simply stops
    // responding to the right arrow. Left is already recoverable because it
    // steps by index rather than by character.
    if (node != null && node is! LiteralNode) {
      _positionAfterAtomic(
        siblings,
        cursor.index,
        cursor.parentId,
        cursor.path,
      );
      _notifyListeners();
      return;
    }

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
      _notifyListeners();
    }
  }

  void moveLeft() {
    if (cursor.subIndex > 0) {
      cursor = cursor.copyWith(subIndex: cursor.subIndex - 1);
      _notifyListeners();
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
      _notifyListeners();
      return;
    }

    if (cursor.parentId != null) {
      _exitNestedStructureLeft();
      _notifyListeners();
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
    _notifyListeners();
  }
}
