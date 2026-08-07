import 'renderer.dart';
import 'math_editor_controller.dart';
import 'cursor.dart';

/// Handles wrapping selected content in various node types
class SelectionWrapper {
  final MathEditorController controller;

  SelectionWrapper(this.controller);

  /// Check if selection exists and is valid
  bool get hasValidSelection {
    return controller.hasSelection &&
        controller.selection != null &&
        !controller.selection!.isEmpty;
  }

  /// Deep copy a single node
  MathNode _deepCopyNode(MathNode node) {
    if (node is LiteralNode) {
      return LiteralNode(text: node.text);
    } else if (node is FractionNode) {
      return FractionNode(
        num: _deepCopyNodes(node.numerator),
        den: _deepCopyNodes(node.denominator),
      );
    } else if (node is ExponentNode) {
      return ExponentNode(
        base: _deepCopyNodes(node.base),
        power: _deepCopyNodes(node.power),
      );
    } else if (node is TrigNode) {
      return TrigNode(
        function: node.function,
        argument: _deepCopyNodes(node.argument),
      );
    } else if (node is RootNode) {
      return RootNode(
        index: _deepCopyNodes(node.index),
        radicand: _deepCopyNodes(node.radicand),
        isSquareRoot: node.isSquareRoot,
      );
    } else if (node is LogNode) {
      return LogNode(
        base: _deepCopyNodes(node.base),
        argument: _deepCopyNodes(node.argument),
        isNaturalLog: node.isNaturalLog,
      );
    } else if (node is ParenthesisNode) {
      return ParenthesisNode(content: _deepCopyNodes(node.content));
    } else if (node is PermutationNode) {
      return PermutationNode(
        n: _deepCopyNodes(node.n),
        r: _deepCopyNodes(node.r),
      );
    } else if (node is CombinationNode) {
      return CombinationNode(
        n: _deepCopyNodes(node.n),
        r: _deepCopyNodes(node.r),
      );
    } else if (node is AnsNode) {
      return AnsNode(index: _deepCopyNodes(node.index));
    } else if (node is NewlineNode) {
      return NewlineNode();
    } else if (node is ConstantNode) {
      return ConstantNode(node.constant);
    } else if (node is UnitVectorNode) {
      return UnitVectorNode(node.axis);
    } else if (node is SummationNode) {
      return SummationNode(
        variable: _deepCopyNodes(node.variable),
        lower: _deepCopyNodes(node.lower),
        upper: _deepCopyNodes(node.upper),
        body: _deepCopyNodes(node.body),
      );
    } else if (node is ProductNode) {
      return ProductNode(
        variable: _deepCopyNodes(node.variable),
        lower: _deepCopyNodes(node.lower),
        upper: _deepCopyNodes(node.upper),
        body: _deepCopyNodes(node.body),
      );
    } else if (node is IntegralNode) {
      return IntegralNode(
        variable: _deepCopyNodes(node.variable),
        lower: _deepCopyNodes(node.lower),
        upper: _deepCopyNodes(node.upper),
        body: _deepCopyNodes(node.body),
        isDefinite: node.isDefinite,
      );
    } else if (node is DerivativeNode) {
      return DerivativeNode(
        variable: _deepCopyNodes(node.variable),
        at: _deepCopyNodes(node.at),
        body: _deepCopyNodes(node.body),
        isDefinite: node.isDefinite,
      );
    }
    return LiteralNode(text: '');
  }

  /// Deep copy a list of nodes
  List<MathNode> _deepCopyNodes(List<MathNode> nodes) {
    return nodes.map((node) => _deepCopyNode(node)).toList();
  }

  /// Get the selected nodes and partial text
  _SelectionContent? _getSelectionContent() {
    if (!hasValidSelection) return null;

    final selection = controller.selection!;
    final norm = selection.normalized;
    final siblings = _resolveNodeList(norm.start.parentId, norm.start.path);
    if (siblings == null) return null;

    List<MathNode> selectedNodes = [];
    String? leadingText;
    String? trailingText;
    String? beforeText;
    String? afterText;

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
          beforeText = node.text.substring(0, startIdx);
          afterText = node.text.substring(endIdx);
          final selectedText = node.text.substring(startIdx, endIdx);
          if (selectedText.isNotEmpty) {
            selectedNodes.add(LiteralNode(text: selectedText));
          }
        } else {
          selectedNodes.add(_deepCopyNode(node));
        }
      } else if (i == norm.start.nodeIndex) {
        // First node of multi-node selection
        if (node is LiteralNode) {
          final startIdx = norm.start.charIndex.clamp(0, node.text.length);
          beforeText = node.text.substring(0, startIdx);
          final selectedText = node.text.substring(startIdx);
          if (selectedText.isNotEmpty) {
            leadingText = selectedText;
          }
        } else {
          selectedNodes.add(_deepCopyNode(node));
        }
      } else if (i == norm.end.nodeIndex) {
        // Last node of multi-node selection
        if (node is LiteralNode) {
          final endIdx = norm.end.charIndex.clamp(0, node.text.length);
          afterText = node.text.substring(endIdx);
          final selectedText = node.text.substring(0, endIdx);
          if (selectedText.isNotEmpty) {
            trailingText = selectedText;
          }
        } else {
          selectedNodes.add(_deepCopyNode(node));
        }
      } else {
        // Middle nodes - fully selected
        selectedNodes.add(_deepCopyNode(node));
      }
    }

    return _SelectionContent(
      nodes: selectedNodes,
      leadingText: leadingText,
      trailingText: trailingText,
      beforeText: beforeText,
      afterText: afterText,
      parentId: norm.start.parentId,
      path: norm.start.path,
      startNodeIndex: norm.start.nodeIndex,
      endNodeIndex: norm.end.nodeIndex,
    );
  }

  /// Build the list of nodes to wrap from selection content
  List<MathNode> _buildNodesToWrap(_SelectionContent content) {
    List<MathNode> nodesToWrap = [];

    if (content.leadingText != null && content.leadingText!.isNotEmpty) {
      nodesToWrap.add(LiteralNode(text: content.leadingText!));
    }

    nodesToWrap.addAll(content.nodes);

    if (content.trailingText != null && content.trailingText!.isNotEmpty) {
      nodesToWrap.add(LiteralNode(text: content.trailingText!));
    }

    // If no nodes, add empty literal
    if (nodesToWrap.isEmpty) {
      nodesToWrap.add(LiteralNode(text: ''));
    }

    return nodesToWrap;
  }

  /// Check if selection is already wrapped in parenthesis
  bool _isAlreadyInParenthesis(_SelectionContent content) {
    if (content.nodes.length == 1 &&
        content.nodes.first is ParenthesisNode &&
        content.leadingText == null &&
        content.trailingText == null &&
        (content.beforeText?.isEmpty ?? true) &&
        (content.afterText?.isEmpty ?? true)) {
      return true;
    }
    return false;
  }

  /// Check if selection is a single simple element (doesn't need parenthesis for exponent)
  bool _isSingleSimpleElement(_SelectionContent content) {
    // Single literal with just numbers/letters (no operators)
    if (content.nodes.length == 1 &&
        content.nodes.first is LiteralNode &&
        content.leadingText == null &&
        content.trailingText == null) {
      final text = (content.nodes.first as LiteralNode).text;
      // Check if text contains only alphanumeric characters
      return RegExp(r'^[a-zA-Z0-9.]+$').hasMatch(text);
    }

    if (content.nodes.length == 1 &&
        (content.nodes.first is ConstantNode ||
            content.nodes.first is UnitVectorNode)) {
      return true;
    }

    // Already a parenthesis node
    if (_isAlreadyInParenthesis(content)) {
      return true;
    }

    return false;
  }

  /// Delete selection and return info about where to insert
  _InsertionPoint? _deleteSelectionAndGetInsertionPoint(
    _SelectionContent content,
  ) {
    if (!hasValidSelection) return null;

    final selection = controller.selection!;
    final norm = selection.normalized;
    final siblings = _resolveNodeList(norm.start.parentId, norm.start.path);
    if (siblings == null) return null;

    // Delete the selected content
    // We remove ALL nodes in the range, including the start node
    for (int i = norm.end.nodeIndex; i >= norm.start.nodeIndex; i--) {
      if (i < siblings.length) {
        siblings.removeAt(i);
      }
    }

    // Insert a single literal node containing the text before and after
    // This creates a stable target for _insertNodeAtPoint to split
    final combinedText = (content.beforeText ?? '') + (content.afterText ?? '');
    siblings.insert(norm.start.nodeIndex, LiteralNode(text: combinedText));

    return _InsertionPoint(
      siblings: siblings,
      nodeIndex: norm.start.nodeIndex,
      charIndex: (content.beforeText ?? '').length,
      parentId: norm.start.parentId,
      path: norm.start.path,
    );
  }

  /// Insert a node at the insertion point, splitting the literal if needed
  void _insertNodeAtPoint(_InsertionPoint point, MathNode newNode) {
    final currentNode = point.siblings[point.nodeIndex];

    if (currentNode is LiteralNode) {
      final text = currentNode.text;
      final before = text.substring(0, point.charIndex.clamp(0, text.length));
      final after = text.substring(point.charIndex.clamp(0, text.length));

      currentNode.text = before;

      // Insert new node after current
      point.siblings.insert(point.nodeIndex + 1, newNode);

      // Insert trailing text node
      point.siblings.insert(point.nodeIndex + 2, LiteralNode(text: after));
    }
  }

  List<MathNode>? _resolveNodeList(String? parentId, String? path) {
    if (parentId == null && path == null) {
      return controller.expression;
    }

    final parent = _findNodeById(controller.expression, parentId!);
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
    } else if (parent is AnsNode) {
      if (path == 'index') return parent.index;
    } else if (parent is SummationNode) {
      if (path == 'var' || path == 'variable') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is ProductNode) {
      if (path == 'var' || path == 'variable') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is IntegralNode) {
      if (path == 'var' || path == 'variable') return parent.variable;
      if (path == 'lower') return parent.lower;
      if (path == 'upper') return parent.upper;
      if (path == 'body') return parent.body;
    } else if (parent is DerivativeNode) {
      if (path == 'var' || path == 'variable') return parent.variable;
      if (path == 'at') return parent.at;
      if (path == 'body') return parent.body;
    }

    return null;
  }

  MathNode? _findNodeById(List<MathNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;

      MathNode? found;
      if (node is FractionNode) {
        found =
            _findNodeById(node.numerator, id) ??
            _findNodeById(node.denominator, id);
      } else if (node is ExponentNode) {
        found = _findNodeById(node.base, id) ?? _findNodeById(node.power, id);
      } else if (node is TrigNode) {
        found = _findNodeById(node.argument, id);
      } else if (node is RootNode) {
        found =
            _findNodeById(node.index, id) ?? _findNodeById(node.radicand, id);
      } else if (node is LogNode) {
        found =
            _findNodeById(node.base, id) ?? _findNodeById(node.argument, id);
      } else if (node is ParenthesisNode) {
        found = _findNodeById(node.content, id);
      } else if (node is PermutationNode) {
        found = _findNodeById(node.n, id) ?? _findNodeById(node.r, id);
      } else if (node is CombinationNode) {
        found = _findNodeById(node.n, id) ?? _findNodeById(node.r, id);
      } else if (node is AnsNode) {
        found = _findNodeById(node.index, id);
      } else if (node is SummationNode) {
        found =
            _findNodeById(node.variable, id) ??
            _findNodeById(node.lower, id) ??
            _findNodeById(node.upper, id) ??
            _findNodeById(node.body, id);
      } else if (node is ProductNode) {
        found =
            _findNodeById(node.variable, id) ??
            _findNodeById(node.lower, id) ??
            _findNodeById(node.upper, id) ??
            _findNodeById(node.body, id);
      } else if (node is IntegralNode) {
        found =
            _findNodeById(node.variable, id) ??
            _findNodeById(node.lower, id) ??
            _findNodeById(node.upper, id) ??
            _findNodeById(node.body, id);
      } else if (node is DerivativeNode) {
        found =
            _findNodeById(node.variable, id) ??
            _findNodeById(node.at, id) ??
            _findNodeById(node.body, id);
      }

      if (found != null) return found;
    }
    return null;
  }

  // ============== PUBLIC WRAPPING METHODS ==============

  /// Wrap selection in parenthesis
  bool wrapInParenthesis() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    if (_isAlreadyInParenthesis(content)) {
      controller.clearSelection();
      return false;
    }

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);

    // Ensure literals exist inside the parenthesis for cursor positioning
    if (nodesToWrap.isNotEmpty && nodesToWrap.first is! LiteralNode) {
      nodesToWrap.insert(0, LiteralNode(text: ''));
    }
    if (nodesToWrap.isNotEmpty && nodesToWrap.last is! LiteralNode) {
      nodesToWrap.add(LiteralNode(text: ''));
    }

    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final parenNode = ParenthesisNode(content: nodesToWrap);

    _insertNodeAtPoint(insertionPoint, parenNode);

    // Place cursor AFTER the right parenthesis (at start of the following literal)
    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in fraction (selection becomes numerator)
  bool wrapInFraction() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final fractionNode = FractionNode(
      num: nodesToWrap,
      den: [LiteralNode(text: '')],
    );

    _insertNodeAtPoint(insertionPoint, fractionNode);

    controller.cursor = EditorCursor(
      parentId: fractionNode.id,
      path: 'den',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in exponent (selection becomes base)
  bool wrapInExponent() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    List<MathNode> baseNodes = _buildNodesToWrap(content);

    // Wrap in parenthesis if not a single simple element
    if (!_isSingleSimpleElement(content)) {
      baseNodes = [ParenthesisNode(content: baseNodes)];
    }

    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final exponentNode = ExponentNode(
      base: baseNodes,
      power: [LiteralNode(text: '')],
    );

    _insertNodeAtPoint(insertionPoint, exponentNode);

    controller.cursor = EditorCursor(
      parentId: exponentNode.id,
      path: 'pow',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in square (exponent of 2)
  bool wrapInSquare() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    List<MathNode> baseNodes = _buildNodesToWrap(content);

    // Wrap in parenthesis if not a single simple element
    if (!_isSingleSimpleElement(content)) {
      baseNodes = [ParenthesisNode(content: baseNodes)];
    }

    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final exponentNode = ExponentNode(
      base: baseNodes,
      power: [LiteralNode(text: '2')],
    );

    _insertNodeAtPoint(insertionPoint, exponentNode);

    // Move cursor after the exponent node
    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in square root
  bool wrapInSquareRoot() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final rootNode = RootNode(
      isSquareRoot: true,
      index: [LiteralNode(text: '2')],
      radicand: nodesToWrap,
    );

    _insertNodeAtPoint(insertionPoint, rootNode);

    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in nth root (selection becomes radicand)
  bool wrapInNthRoot() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final rootNode = RootNode(
      isSquareRoot: false,
      index: [LiteralNode(text: '')],
      radicand: nodesToWrap,
    );

    _insertNodeAtPoint(insertionPoint, rootNode);

    controller.cursor = EditorCursor(
      parentId: rootNode.id,
      path: 'index',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in trig function
  bool wrapInTrig(String function) {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final trigNode = TrigNode(function: function, argument: nodesToWrap);

    _insertNodeAtPoint(insertionPoint, trigNode);

    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in log base 10
  bool wrapInLog10() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final logNode = LogNode(
      base: [LiteralNode(text: '10')],
      argument: nodesToWrap,
      isNaturalLog: false,
    );

    _insertNodeAtPoint(insertionPoint, logNode);

    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in log base n (selection becomes argument)
  bool wrapInLogN() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final logNode = LogNode(
      base: [LiteralNode(text: '')],
      argument: nodesToWrap,
      isNaturalLog: false,
    );

    _insertNodeAtPoint(insertionPoint, logNode);

    controller.cursor = EditorCursor(
      parentId: logNode.id,
      path: 'base',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in natural log
  bool wrapInNaturalLog() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final logNode = LogNode(argument: nodesToWrap, isNaturalLog: true);

    _insertNodeAtPoint(insertionPoint, logNode);

    controller.cursor = EditorCursor(
      parentId: insertionPoint.parentId,
      path: insertionPoint.path,
      index: insertionPoint.nodeIndex + 2,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in permutation (selection becomes n)
  bool wrapInPermutation() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final permNode = PermutationNode(
      n: nodesToWrap,
      r: [LiteralNode(text: '')],
    );

    _insertNodeAtPoint(insertionPoint, permNode);

    controller.cursor = EditorCursor(
      parentId: permNode.id,
      path: 'r',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in combination (selection becomes n)
  bool wrapInCombination() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final combNode = CombinationNode(
      n: nodesToWrap,
      r: [LiteralNode(text: '')],
    );

    _insertNodeAtPoint(insertionPoint, combNode);

    controller.cursor = EditorCursor(
      parentId: combNode.id,
      path: 'r',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in summation (selection becomes body)
  bool wrapInSummation() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final sumNode = SummationNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: nodesToWrap,
    );

    _insertNodeAtPoint(insertionPoint, sumNode);

    controller.cursor = EditorCursor(
      parentId: sumNode.id,
      path: 'body',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in product (selection becomes body)
  bool wrapInProduct() {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final prodNode = ProductNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: nodesToWrap,
    );

    _insertNodeAtPoint(insertionPoint, prodNode);

    controller.cursor = EditorCursor(
      parentId: prodNode.id,
      path: 'body',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in derivative (selection becomes body)
  bool wrapInDerivative({bool definite = false}) {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final diffNode = DerivativeNode(
      variable: [LiteralNode(text: 'x')],
      at: [LiteralNode(text: '')],
      body: nodesToWrap,
      isDefinite: definite,
    );

    _insertNodeAtPoint(insertionPoint, diffNode);

    controller.cursor = EditorCursor(
      parentId: diffNode.id,
      path: 'body',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }

  /// Wrap selection in integral (selection becomes body)
  bool wrapInIntegral({bool definite = false}) {
    if (!hasValidSelection) return false;

    final content = _getSelectionContent();
    if (content == null) return false;

    controller.saveStateForUndo();

    final nodesToWrap = _buildNodesToWrap(content);
    final insertionPoint = _deleteSelectionAndGetInsertionPoint(content);
    if (insertionPoint == null) return false;

    final intNode = IntegralNode(
      variable: [LiteralNode(text: 'x')],
      lower: [LiteralNode(text: '')],
      upper: [LiteralNode(text: '')],
      body: nodesToWrap,
      isDefinite: definite,
    );

    _insertNodeAtPoint(insertionPoint, intNode);

    controller.cursor = EditorCursor(
      parentId: intNode.id,
      path: 'body',
      index: 0,
      subIndex: 0,
    );

    controller.clearSelection();
    controller.notifyAndRecalculate();

    return true;
  }
}

/// Internal class to hold selection content
class _SelectionContent {
  final List<MathNode> nodes;
  final String? leadingText;
  final String? trailingText;
  final String? beforeText;
  final String? afterText;
  final String? parentId;
  final String? path;
  final int startNodeIndex;
  final int endNodeIndex;

  _SelectionContent({
    required this.nodes,
    this.leadingText,
    this.trailingText,
    this.beforeText,
    this.afterText,
    this.parentId,
    this.path,
    required this.startNodeIndex,
    required this.endNodeIndex,
  });
}

/// Internal class to hold insertion point info
class _InsertionPoint {
  final List<MathNode> siblings;
  final int nodeIndex;
  final int charIndex;
  final String? parentId;
  final String? path;

  _InsertionPoint({
    required this.siblings,
    required this.nodeIndex,
    required this.charIndex,
    this.parentId,
    this.path,
  });
}


