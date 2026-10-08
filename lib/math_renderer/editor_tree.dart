part of 'math_editor_controller.dart';

/// Finding things in the node tree: the node under the cursor, its siblings,
/// its parent, a chain of multiplied factors, and the ans references.
extension EditorTree on MathEditorController {
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
            !MathEditorController._isNonMultiplyWordBoundary(
              text[operandStart - 1],
            )) {
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

  /// Updates all AnsNode indices in the expression based on a cell insertion or removal.
  /// [atIndex] is the index where the change occurred.
  /// [delta] is typically +1 for insertion and -1 for removal.
  void updateAnsReferences(int atIndex, int delta) {
    _updateAnsIndicesRecursive(expression, atIndex, delta);
    // Serialize to update the 'expr' string used for computation trigger
    expr = MathExpressionSerializer.serialize(expression);
    _structureVersion++;
    _notifyListeners();
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
