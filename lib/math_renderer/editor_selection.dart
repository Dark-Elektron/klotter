part of 'math_editor_controller.dart';

/// Selecting, dragging the selection handles, and the clipboard.
extension EditorSelection on MathEditorController {
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

    _notifyListeners();
  }

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

    MathEditorController._clipboard = MathClipboard(
      nodes: copiedNodes,
      leadingText: leadingText,
      trailingText: trailingText,
    );

    return MathEditorController._clipboard;
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

    // Several branches above can leave the caret on a composite — the literal
    // it was going to sit in may be one of the nodes just removed — and that
    // is a position nothing can type into.
    _ensureCursorInLiteral();

    // Clear selection FIRST, then notify
    _selection = null;
    onSelectionCleared?.call();

    _structureVersion++;
    _notifyListeners();
    onResultChanged?.call();

    onCalculate();
  }

  /// Paste clipboard content at cursor
  void pasteClipboard() {
    if (MathEditorController._clipboard == null ||
        MathEditorController._clipboard!.isEmpty) {
      return;
    }

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
      if (MathEditorController._clipboard!.leadingText != null) {
        pastedText += MathEditorController._clipboard!.leadingText!;
      }
      if (MathEditorController._clipboard!.trailingText != null) {
        pastedText += MathEditorController._clipboard!.trailingText!;
      }

      if (MathEditorController._clipboard!.nodes.isEmpty) {
        // Just text - simple insert
        target.text = before + pastedText + after;
        cursor = cursor.copyWith(subIndex: before.length + pastedText.length);
      } else {
        // Has complex nodes
        target.text =
            before + (MathEditorController._clipboard!.leadingText ?? '');

        int insertIndex = cursor.index + 1;

        // Insert copied nodes
        for (final node in MathEditorController._clipboard!.nodes) {
          siblings.insert(insertIndex, MathClipboard.deepCopyNode(node));
          insertIndex++;
        }

        // Insert trailing text node
        final trailingNode = LiteralNode(
          text: (MathEditorController._clipboard!.trailingText ?? '') + after,
        );
        siblings.insert(insertIndex, trailingNode);

        cursor = EditorCursor(
          parentId: cursor.parentId,
          path: cursor.path,
          index: insertIndex,
          subIndex:
              (MathEditorController._clipboard!.trailingText ?? '').length,
        );
      }
    }

    _structureVersion++;
    _notifyListeners();
    onResultChanged?.call();

    onCalculate();
  }

  void clearSelection({bool notify = true}) {
    if (_selection == null) return;

    _selection = null;
    onSelectionCleared?.call();

    if (notify) {
      _notifyListeners();
    }
  }

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
    _notifyListeners();
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
}
