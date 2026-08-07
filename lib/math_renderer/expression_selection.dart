import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'math_editor_controller.dart';
import 'renderer.dart';

// ============== SELECTION DATA CLASSES ==============

class SelectionAnchor {
  final String? parentId;
  final String? path;
  final int nodeIndex;
  final int charIndex;

  const SelectionAnchor({
    this.parentId,
    this.path,
    required this.nodeIndex,
    required this.charIndex,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SelectionAnchor &&
        other.parentId == parentId &&
        other.path == path &&
        other.nodeIndex == nodeIndex &&
        other.charIndex == charIndex;
  }

  @override
  int get hashCode => Object.hash(parentId, path, nodeIndex, charIndex);

  SelectionAnchor copyWith({
    String? parentId,
    String? path,
    int? nodeIndex,
    int? charIndex,
  }) {
    return SelectionAnchor(
      parentId: parentId ?? this.parentId,
      path: path ?? this.path,
      nodeIndex: nodeIndex ?? this.nodeIndex,
      charIndex: charIndex ?? this.charIndex,
    );
  }

  @override
  String toString() =>
      'Anchor(parent: $parentId, path: $path, node: $nodeIndex, char: $charIndex)';
}

class SelectionRange {
  final SelectionAnchor start;
  final SelectionAnchor end;

  const SelectionRange({required this.start, required this.end});

  bool get isEmpty => start == end;

  SelectionRange get normalized {
    int cmp;
    if (start.nodeIndex != end.nodeIndex) {
      cmp = start.nodeIndex.compareTo(end.nodeIndex);
    } else {
      cmp = start.charIndex.compareTo(end.charIndex);
    }

    if (cmp <= 0) return this;
    return SelectionRange(start: end, end: start);
  }

  @override
  String toString() => 'SelectionRange(start: $start, end: $end)';
}

// ============== CLIPBOARD ==============

class MathClipboard {
  final List<MathNode> nodes;
  final String? leadingText;
  final String? trailingText;

  const MathClipboard({
    required this.nodes,
    this.leadingText,
    this.trailingText,
  });

  bool get isEmpty =>
      nodes.isEmpty &&
      (leadingText?.isEmpty ?? true) &&
      (trailingText?.isEmpty ?? true);

  static List<MathNode> deepCopyNodes(List<MathNode> nodes) {
    return nodes.map((node) => deepCopyNode(node)).toList();
  }

  static MathNode deepCopyNode(MathNode node) {
    if (node is LiteralNode) {
      return LiteralNode(text: node.text);
    } else if (node is FractionNode) {
      return FractionNode(
        num: deepCopyNodes(node.numerator),
        den: deepCopyNodes(node.denominator),
      );
    } else if (node is ExponentNode) {
      return ExponentNode(
        base: deepCopyNodes(node.base),
        power: deepCopyNodes(node.power),
      );
    } else if (node is LogNode) {
      return LogNode(
        base: deepCopyNodes(node.base),
        argument: deepCopyNodes(node.argument),
        isNaturalLog: node.isNaturalLog,
      );
    } else if (node is TrigNode) {
      return TrigNode(
        function: node.function,
        argument: deepCopyNodes(node.argument),
      );
    } else if (node is RootNode) {
      return RootNode(
        index: deepCopyNodes(node.index),
        radicand: deepCopyNodes(node.radicand),
        isSquareRoot: node.isSquareRoot,
      );
    } else if (node is PermutationNode) {
      return PermutationNode(
        n: deepCopyNodes(node.n),
        r: deepCopyNodes(node.r),
      );
    } else if (node is CombinationNode) {
      return CombinationNode(
        n: deepCopyNodes(node.n),
        r: deepCopyNodes(node.r),
      );
    } else if (node is SummationNode) {
      return SummationNode(
        variable: deepCopyNodes(node.variable),
        lower: deepCopyNodes(node.lower),
        upper: deepCopyNodes(node.upper),
        body: deepCopyNodes(node.body),
      );
    } else if (node is ProductNode) {
      return ProductNode(
        variable: deepCopyNodes(node.variable),
        lower: deepCopyNodes(node.lower),
        upper: deepCopyNodes(node.upper),
        body: deepCopyNodes(node.body),
      );
    } else if (node is DerivativeNode) {
      return DerivativeNode(
        variable: deepCopyNodes(node.variable),
        at: deepCopyNodes(node.at),
        body: deepCopyNodes(node.body),
        isDefinite: node.isDefinite,
      );
    } else if (node is IntegralNode) {
      return IntegralNode(
        variable: deepCopyNodes(node.variable),
        lower: deepCopyNodes(node.lower),
        upper: deepCopyNodes(node.upper),
        body: deepCopyNodes(node.body),
        isDefinite: node.isDefinite,
      );
    } else if (node is NewlineNode) {
      return NewlineNode();
    } else if (node is ParenthesisNode) {
      return ParenthesisNode(content: deepCopyNodes(node.content));
    } else if (node is AnsNode) {
      return AnsNode(index: deepCopyNodes(node.index));
    } else if (node is ConstantNode) {
      return ConstantNode(node.constant);
    } else if (node is UnitVectorNode) {
      return UnitVectorNode(node.axis);
    } else if (node is ComplexNode) {
      return ComplexNode(content: deepCopyNodes(node.content));
    }
    return LiteralNode(text: '');
  }
}

// ============== SELECTION OVERLAY WIDGET ==============

class SelectionOverlayWidget extends StatefulWidget {
  final MathEditorController controller;
  final GlobalKey containerKey;
  final Offset? cursorLocalPosition; // Keep this for compatibility
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;
  final VoidCallback onDismiss;

  const SelectionOverlayWidget({
    super.key,
    required this.controller,
    required this.containerKey,
    this.cursorLocalPosition, // Keep this parameter
    this.onCopy,
    this.onCut,
    this.onPaste,
    required this.onDismiss,
  });

  bool get isPasteOnlyMode =>
      onCopy == null && onCut == null && onPaste != null;

  @override
  State<SelectionOverlayWidget> createState() => _SelectionOverlayWidgetState();
}

class _SelectionOverlayWidgetState extends State<SelectionOverlayWidget> {
  static const double _menuOffset = 12.0;
  static const double _handleSize = 18.0;

  // ============== BOUNDING BOX HELPERS ==============

  Set<String> _collectAllNodeIds(MathNode node) {
    final ids = <String>{node.id};

    final childLists = _getChildLists(node);
    for (final list in childLists) {
      for (final child in list) {
        ids.addAll(_collectAllNodeIds(child));
      }
    }

    return ids;
  }

  List<List<MathNode>> _getChildLists(MathNode node) {
    if (node is FractionNode) return [node.numerator, node.denominator];
    if (node is ExponentNode) return [node.base, node.power];
    if (node is TrigNode) return [node.argument];
    if (node is RootNode) return [node.index, node.radicand];
    if (node is LogNode) return [node.base, node.argument];
    if (node is ParenthesisNode) return [node.content];
    if (node is PermutationNode) return [node.n, node.r];
    if (node is CombinationNode) return [node.n, node.r];
    if (node is AnsNode) return [node.index];
    if (node is SummationNode) {
      return [node.variable, node.lower, node.upper, node.body];
    }
    if (node is ProductNode) {
      return [node.variable, node.lower, node.upper, node.body];
    }
    if (node is IntegralNode) {
      return [node.variable, node.lower, node.upper, node.body];
    }
    if (node is DerivativeNode) return [node.variable, node.at, node.body];
    return [];
  }

  List<MathNode>? _getSiblingList(String? parentId, String? path) {
    if (parentId == null) {
      return widget.controller.expression;
    }

    final parent = _findNodeById(widget.controller.expression, parentId);
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

      final childLists = _getChildLists(node);
      for (final list in childLists) {
        final found = _findNodeById(list, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  Rect? _getNodeBounds(MathNode node) {
    // Check if this is a complex node with registered bounds
    final complexInfo = widget.controller.complexNodeMap[node.id];
    if (complexInfo != null) {
      return complexInfo.rect;
    }

    final nodeIds = _collectAllNodeIds(node);

    double minX = double.infinity;
    double maxX = double.negativeInfinity;
    double minY = double.infinity;
    double maxY = double.negativeInfinity;

    for (final info in widget.controller.layoutRegistry.values) {
      if (nodeIds.contains(info.node.id)) {
        minX = math.min(minX, info.rect.left);
        maxX = math.max(maxX, info.rect.right);
        minY = math.min(minY, info.rect.top);
        maxY = math.max(maxY, info.rect.bottom);
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  NodeLayoutInfo? _findLayoutInfo(MathNode node) {
    for (final info in widget.controller.layoutRegistry.values) {
      if (info.node.id == node.id) return info;
    }
    return null;
  }

  double _getCursorOffset(NodeLayoutInfo info, int charIndex) {
    final text = info.node.text;
    if (text.isEmpty || charIndex <= 0) return 0.0;

    final displayText = info.displayText;
    final displayIndex = MathTextStyle.logicalToDisplayIndex(
      text,
      charIndex,
      forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
    ).clamp(0, displayText.length);

    if (info.renderParagraph != null) {
      final offset = info.renderParagraph!.getOffsetForCaret(
        TextPosition(offset: displayIndex),
        Rect.zero,
      );
      return offset.dx;
    }

    // Fallback
    final textSpan = TextSpan(
      text: displayText,
      style: MathTextStyle.getStyle(info.fontSize),
    );
    final renderParagraph = RenderParagraph(
      textSpan,
      textDirection: TextDirection.ltr,
      textScaler: info.textScaler,
    );
    renderParagraph.layout(const BoxConstraints());
    final offset = renderParagraph.getOffsetForCaret(
      TextPosition(offset: displayIndex),
      Rect.zero,
    );
    renderParagraph.dispose();
    return offset.dx;
  }

  // ============== SELECTION BOUNDS CALCULATION ==============

  _SelectionBounds? _calculateSelectionBounds() {
    final selection = widget.controller.selection;
    if (selection == null || selection.isEmpty) return null;

    final containerBox =
        widget.containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerBox == null) return null;

    final norm = selection.normalized;
    final siblings = _getSiblingList(norm.start.parentId, norm.start.path);
    if (siblings == null || siblings.isEmpty) return null;

    final startNodeIdx = norm.start.nodeIndex.clamp(0, siblings.length - 1);
    final endNodeIdx = norm.end.nodeIndex.clamp(0, siblings.length - 1);

    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    double startX = double.infinity;
    double endX = double.negativeInfinity;

    bool foundAny = false;

    for (int i = startNodeIdx; i <= endNodeIdx; i++) {
      if (i >= siblings.length) break;

      final node = siblings[i];
      final nodeBounds = _getNodeBounds(node);
      if (nodeBounds == null) continue;

      foundAny = true;
      minY = math.min(minY, nodeBounds.top);
      maxY = math.max(maxY, nodeBounds.bottom);

      if (i == startNodeIdx && i == endNodeIdx) {
        // Single node selection
        if (node is LiteralNode) {
          final info = _findLayoutInfo(node);
          if (info != null) {
            final startOffset = _getCursorOffset(info, norm.start.charIndex);
            final endOffset = _getCursorOffset(info, norm.end.charIndex);
            startX = info.rect.left + startOffset;
            endX = info.rect.left + endOffset;
          } else {
            startX = nodeBounds.left;
            endX = nodeBounds.right;
          }
        } else {
          // Composite node - full bounds
          startX = nodeBounds.left;
          endX = nodeBounds.right;
        }
      } else if (i == startNodeIdx) {
        // First node in multi-node selection
        if (node is LiteralNode && norm.start.charIndex > 0) {
          final info = _findLayoutInfo(node);
          if (info != null) {
            startX =
                info.rect.left + _getCursorOffset(info, norm.start.charIndex);
          } else {
            startX = nodeBounds.left;
          }
        } else {
          startX = nodeBounds.left;
        }
        endX = math.max(endX, nodeBounds.right);
      } else if (i == endNodeIdx) {
        // Last node
        startX = math.min(startX, nodeBounds.left);
        if (node is LiteralNode) {
          final info = _findLayoutInfo(node);
          if (info != null) {
            final effectiveEndChar = norm.end.charIndex.clamp(
              0,
              node.text.length,
            );
            endX = math.max(
              endX,
              info.rect.left + _getCursorOffset(info, effectiveEndChar),
            );
          } else {
            endX = math.max(endX, nodeBounds.right);
          }
        } else {
          endX = math.max(endX, nodeBounds.right);
        }
      } else {
        // Middle nodes - full width
        startX = math.min(startX, nodeBounds.left);
        endX = math.max(endX, nodeBounds.right);
      }
    }

    if (!foundAny || minY == double.infinity || startX == double.infinity) {
      return null;
    }

    // Ensure minimum width
    if (endX <= startX) {
      endX = startX + 4;
    }

    // Convert to global coordinates
    final globalTopLeft = containerBox.localToGlobal(Offset(startX, minY));
    final globalBottomRight = containerBox.localToGlobal(Offset(endX, maxY));

    return _SelectionBounds(
      rect: Rect.fromLTRB(
        globalTopLeft.dx,
        globalTopLeft.dy,
        globalBottomRight.dx,
        globalBottomRight.dy,
      ),
    );
  }

  Rect? _getCursorGlobalBounds() {
    final containerBox =
        widget.containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerBox == null) return null;

    final cursor = widget.controller.cursor;

    for (final info in widget.controller.layoutRegistry.values) {
      if (info.parentId == cursor.parentId &&
          info.path == cursor.path &&
          info.index == cursor.index) {
        double cursorX;
        if (info.node.text.isEmpty) {
          cursorX = info.rect.left;
        } else {
          cursorX = info.rect.left + _getCursorOffset(info, cursor.subIndex);
        }

        final globalTopLeft = containerBox.localToGlobal(
          Offset(cursorX, info.rect.top),
        );
        final globalBottomRight = containerBox.localToGlobal(
          Offset(cursorX + 2, info.rect.bottom),
        );

        return Rect.fromLTRB(
          globalTopLeft.dx,
          globalTopLeft.dy,
          globalBottomRight.dx,
          globalBottomRight.dy,
        );
      }
    }

    return null;
  }

  // ============== HANDLE DRAG ==============

  void _onHandleDragStart(bool isStart) {
    widget.controller.startHandleDrag(isStart);
  }

  void _onHandleDragUpdate(bool isStart, Offset globalPosition) {
    final containerBox =
        widget.containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerBox == null) return;

    final localPos = containerBox.globalToLocal(globalPosition);
    widget.controller.updateSelectionHandle(isStart, localPos);

    setState(() {});
  }

  void _onHandleDragEnd() {
    widget.controller.endHandleDrag();
  }

  // ============== BUILD ==============

  @override
  Widget build(BuildContext context) {
    final selectionBounds = _calculateSelectionBounds();
    final hasSelection = widget.controller.hasSelection;
    final screenSize = MediaQuery.of(context).size;
    final hasClipboard =
        MathEditorController.clipboard != null &&
        !MathEditorController.clipboard!.isEmpty;

    final isPasteOnlyMode = widget.onCopy == null && widget.onCut == null;

    // Calculate menu position - use expression top, not selection top
    double menuCenterX;
    double menuTopY;

    if (hasSelection && selectionBounds != null) {
      menuCenterX = selectionBounds.rect.center.dx;

      // Get the top of the entire expression/context, not just the selection
      final expressionTop = _getExpressionTop();
      menuTopY = (expressionTop ?? selectionBounds.rect.top) - 55 - _menuOffset;
    } else {
      final cursorBounds = _getCursorGlobalBounds();
      if (cursorBounds != null) {
        menuCenterX = cursorBounds.center.dx;
        final expressionTop = _getExpressionTop();
        menuTopY = (expressionTop ?? cursorBounds.top) - 55 - _menuOffset;
      } else if (widget.cursorLocalPosition != null) {
        // Fallback to tap position if cursor bounds unavailable
        final containerBox =
            widget.containerKey.currentContext?.findRenderObject()
                as RenderBox?;
        if (containerBox != null) {
          final globalPos = containerBox.localToGlobal(
            widget.cursorLocalPosition!,
          );
          menuCenterX = globalPos.dx;
          menuTopY = globalPos.dy - 55 - _menuOffset;
        } else {
          menuCenterX = screenSize.width / 2;
          menuTopY = 100;
        }
      } else {
        menuCenterX = screenSize.width / 2;
        menuTopY = 100;
      }
    }

    // Clamp menu position to screen
    menuTopY = menuTopY.clamp(8.0, screenSize.height - 100);
    menuCenterX = menuCenterX.clamp(80.0, screenSize.width - 80.0);

    return Stack(
      children: [
        // Tap to dismiss (paste-only mode)
        if (isPasteOnlyMode)
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onDismiss,
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
          ),

        // Selection highlight
        if (hasSelection && selectionBounds != null)
          Positioned(
            left: selectionBounds.rect.left,
            top: selectionBounds.rect.top,
            width: selectionBounds.rect.width,
            height: selectionBounds.rect.height,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.yellow.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),

        // Selection handles
        if (hasSelection && selectionBounds != null) ...[
          // Left (start) handle
          Positioned(
            left: selectionBounds.rect.left - _handleSize,
            top: selectionBounds.rect.bottom,
            child: _SelectionHandle(
              isStart: true,
              size: _handleSize,
              onDragStart: () => _onHandleDragStart(true),
              onDragUpdate: (pos) => _onHandleDragUpdate(true, pos),
              onDragEnd: _onHandleDragEnd,
            ),
          ),
          // Right (end) handle
          Positioned(
            left: selectionBounds.rect.right,
            top: selectionBounds.rect.bottom,
            child: _SelectionHandle(
              isStart: false,
              size: _handleSize,
              onDragStart: () => _onHandleDragStart(false),
              onDragUpdate: (pos) => _onHandleDragUpdate(false, pos),
              onDragEnd: _onHandleDragEnd,
            ),
          ),
        ],

        // Menu
        Positioned(
          top: menuTopY,
          left: menuCenterX,
          child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: _SelectionMenu(
              onCopy: widget.onCopy,
              onCut: widget.onCut,
              onPaste: hasClipboard ? widget.onPaste : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Get the top Y coordinate of the entire expression or current composite node
  double? _getExpressionTop() {
    final containerBox =
        widget.containerKey.currentContext?.findRenderObject() as RenderBox?;
    if (containerBox == null) return null;

    final selection = widget.controller.selection;

    // Find the minimum Y across all relevant nodes
    double minY = double.infinity;

    if (selection != null) {
      final norm = selection.normalized;

      // If we're inside a composite node, use that node's top
      if (norm.start.parentId != null) {
        // Find the root composite that contains this selection
        String? rootCompositeId = _findRootComposite(norm.start.parentId);
        if (rootCompositeId != null) {
          final bounds = _getCompositeBounds(rootCompositeId);
          if (bounds != null) {
            final globalTop = containerBox.localToGlobal(Offset(0, bounds.top));
            return globalTop.dy;
          }
        }
      }
    }

    // Fallback: use the top of all layout items
    for (final info in widget.controller.layoutRegistry.values) {
      minY = math.min(minY, info.rect.top);
    }

    if (minY == double.infinity) return null;

    final globalTop = containerBox.localToGlobal(Offset(0, minY));
    return globalTop.dy;
  }

  /// Find the root-level composite node that contains the given node
  String? _findRootComposite(String? nodeId) {
    if (nodeId == null) return null;

    String? current = nodeId;
    String? rootComposite;

    while (current != null) {
      final info = widget.controller.complexNodeMap[current];
      if (info == null) break;

      if (info.parentId == null) {
        // This is at root level
        rootComposite = current;
        break;
      }

      rootComposite = current;
      current = info.parentId;
    }

    return rootComposite;
  }

  /// Get bounds of a composite node
  Rect? _getCompositeBounds(String nodeId) {
    final node = _findNodeById(widget.controller.expression, nodeId);
    if (node == null) return null;
    return _getNodeBounds(node);
  }
}

// ============== HELPER CLASSES ==============

class _SelectionBounds {
  final Rect rect;

  _SelectionBounds({required this.rect});
}

class _SelectionHandle extends StatelessWidget {
  final bool isStart;
  final double size;
  final VoidCallback onDragStart;
  final Function(Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnd;

  const _SelectionHandle({
    required this.isStart,
    required this.size,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    const double touchPadding = 16.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        onDragStart();
        onDragUpdate(details.globalPosition);
      },
      onPanUpdate: (details) {
        onDragUpdate(details.globalPosition);
      },
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: Container(
        width: size + touchPadding,
        height: size + touchPadding,
        color: Colors.transparent,
        child: CustomPaint(
          size: Size(size + touchPadding, size + touchPadding),
          painter: _HandlePainter(isStart: isStart, size: size),
        ),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  final bool isStart;
  final double size;

  _HandlePainter({required this.isStart, required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final paint =
        Paint()
          ..color = Colors.yellowAccent
          ..style = PaintingStyle.fill;

    final double r = size / 2;

    if (isStart) {
      // Left handle - teardrop pointing up-right
      final path = Path();
      path.moveTo(size, 0);
      path.lineTo(size, r);
      path.arcToPoint(
        Offset(r, 0),
        radius: Radius.circular(r),
        clockwise: true,
        largeArc: true,
      );
      path.close();
      canvas.drawPath(path, paint);
    } else {
      // Right handle - teardrop pointing up-left
      final path = Path();
      path.moveTo(0, 0);
      path.lineTo(0, r);
      path.arcToPoint(
        Offset(r, 0),
        radius: Radius.circular(r),
        clockwise: false,
        largeArc: true,
      );
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) {
    return isStart != oldDelegate.isStart || size != oldDelegate.size;
  }
}

class _SelectionMenu extends StatelessWidget {
  final VoidCallback? onCopy;
  final VoidCallback? onCut;
  final VoidCallback? onPaste;

  const _SelectionMenu({this.onCopy, this.onCut, this.onPaste});

  @override
  Widget build(BuildContext context) {
    final hasAnyAction = onCopy != null || onCut != null || onPaste != null;
    if (!hasAnyAction) return const SizedBox.shrink();

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(8),
      color: const Color(0xFF2D2D2D),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onCut != null)
              _MenuButton(icon: Icons.cut, label: 'Cut', onTap: onCut!),
            if (onCopy != null) ...[
              if (onCut != null) const _MenuDivider(),
              _MenuButton(icon: Icons.copy, label: 'Copy', onTap: onCopy!),
            ],
            if (onPaste != null) ...[
              if (onCopy != null || onCut != null) const _MenuDivider(),
              _MenuButton(icon: Icons.paste, label: 'Paste', onTap: onPaste!),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MenuButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: Colors.grey[600]);
  }
}
