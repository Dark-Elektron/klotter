import 'renderer.dart';

class EditorCursor {
  final String? parentId;
  final String? path;
  final int index;
  final int subIndex;

  const EditorCursor({
    this.parentId,
    this.path,
    this.index = 0,
    this.subIndex = 0,
  });

  EditorCursor copyWith({
    String? parentId,
    String? path,
    int? index,
    int? subIndex,
  }) {
    return EditorCursor(
      parentId: parentId ?? this.parentId,
      path: path ?? this.path,
      index: index ?? this.index,
      subIndex: subIndex ?? this.subIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EditorCursor &&
        other.parentId == parentId &&
        other.path == path &&
        other.index == index &&
        other.subIndex == subIndex;
  }

  @override
  int get hashCode =>
      parentId.hashCode ^ path.hashCode ^ index.hashCode ^ subIndex.hashCode;
}

/// Snapshot of editor state for undo/redo
class EditorState {
  final List<MathNode> expression;
  final EditorCursor cursor;

  EditorState({required this.expression, required this.cursor});

  /// Deep copy the expression tree
  static List<MathNode> _deepCopyNodes(
    List<MathNode> nodes,
    Map<String, String> idMap,
  ) {
    return nodes.map((node) => _deepCopyNode(node, idMap)).toList();
  }

  static MathNode _deepCopyNode(MathNode node, Map<String, String> idMap) {
    late final MathNode copy;
    if (node is LiteralNode) {
      copy = LiteralNode(text: node.text);
    } else if (node is FractionNode) {
      copy = FractionNode(
        num: _deepCopyNodes(node.numerator, idMap),
        den: _deepCopyNodes(node.denominator, idMap),
      );
    } else if (node is ExponentNode) {
      copy = ExponentNode(
        base: _deepCopyNodes(node.base, idMap),
        power: _deepCopyNodes(node.power, idMap),
      );
    } else if (node is ParenthesisNode) {
      copy = ParenthesisNode(content: _deepCopyNodes(node.content, idMap));
    } else if (node is TrigNode) {
      copy = TrigNode(
        function: node.function,
        argument: _deepCopyNodes(node.argument, idMap),
      );
    } else if (node is RootNode) {
      copy = RootNode(
        isSquareRoot: node.isSquareRoot,
        index: _deepCopyNodes(node.index, idMap),
        radicand: _deepCopyNodes(node.radicand, idMap),
      );
    } else if (node is LogNode) {
      copy = LogNode(
        isNaturalLog: node.isNaturalLog,
        base: _deepCopyNodes(node.base, idMap),
        argument: _deepCopyNodes(node.argument, idMap),
      );
    } else if (node is PermutationNode) {
      copy = PermutationNode(
        n: _deepCopyNodes(node.n, idMap),
        r: _deepCopyNodes(node.r, idMap),
      );
    } else if (node is CombinationNode) {
      copy = CombinationNode(
        n: _deepCopyNodes(node.n, idMap),
        r: _deepCopyNodes(node.r, idMap),
      );
    } else if (node is SummationNode) {
      copy = SummationNode(
        variable: _deepCopyNodes(node.variable, idMap),
        lower: _deepCopyNodes(node.lower, idMap),
        upper: _deepCopyNodes(node.upper, idMap),
        body: _deepCopyNodes(node.body, idMap),
      );
    } else if (node is ProductNode) {
      copy = ProductNode(
        variable: _deepCopyNodes(node.variable, idMap),
        lower: _deepCopyNodes(node.lower, idMap),
        upper: _deepCopyNodes(node.upper, idMap),
        body: _deepCopyNodes(node.body, idMap),
      );
    } else if (node is DerivativeNode) {
      copy = DerivativeNode(
        variable: _deepCopyNodes(node.variable, idMap),
        at: _deepCopyNodes(node.at, idMap),
        body: _deepCopyNodes(node.body, idMap),
        isDefinite: node.isDefinite,
      );
    } else if (node is IntegralNode) {
      copy = IntegralNode(
        variable: _deepCopyNodes(node.variable, idMap),
        lower: _deepCopyNodes(node.lower, idMap),
        upper: _deepCopyNodes(node.upper, idMap),
        body: _deepCopyNodes(node.body, idMap),
        isDefinite: node.isDefinite,
      );
    } else if (node is AnsNode) {
      copy = AnsNode(index: _deepCopyNodes(node.index, idMap));
    } else if (node is ConstantNode) {
      copy = ConstantNode(node.constant);
    } else if (node is UnitVectorNode) {
      copy = UnitVectorNode(node.axis);
    } else if (node is ComplexNode) {
      copy = ComplexNode(content: _deepCopyNodes(node.content, idMap));
    } else if (node is NewlineNode) {
      copy = NewlineNode();
    } else {
      copy = LiteralNode();
    }

    idMap[node.id] = copy.id;
    return copy;
  }

  /// Create a snapshot from current state
  factory EditorState.capture(List<MathNode> expression, EditorCursor cursor) {
    final Map<String, String> idMap = {};
    final List<MathNode> copiedExpression = _deepCopyNodes(expression, idMap);

    // Every node in the tree is registered in idMap, so a null mapping means
    // the cursor's parent is no longer in the tree (a stale reference). In that
    // case clamp to a safe root position instead of keeping a dangling id that
    // would silently mislocate the caret to root after undo/redo.
    final EditorCursor mappedCursor;
    if (cursor.parentId == null) {
      mappedCursor = cursor;
    } else {
      final String? mapped = idMap[cursor.parentId];
      mappedCursor =
          mapped != null
              ? cursor.copyWith(parentId: mapped)
              : const EditorCursor(index: 0, subIndex: 0);
    }

    return EditorState(expression: copiedExpression, cursor: mappedCursor);
  }
}
