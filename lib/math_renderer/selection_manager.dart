import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'math_editor_controller.dart';
import 'renderer.dart';
import 'expression_selection.dart';

/// Manages selection logic for the math editor
class SelectionManager {
  final MathEditorController controller;

  // Drag state
  bool _isDragging = false;
  bool _isDraggingStartHandle = false;
  SelectionAnchor? _fixedAnchor;

  // Context tracking
  String? _contextParentId;
  String? _contextPath;
  String? _selectedCompositeId;
  bool _isBlockMode = false;

  // The context a drag started in, and whether it started as a whole-composite
  // (block) selection. Used to stop an outward drag from a nested sub-context
  // (e.g. the argument of log_10(6)) from re-entering a *sibling* sub-context
  // and collapsing the selection. Drags that start in block mode keep full
  // re-entry so dragging a handle back into a composite still refines it.
  String? _originContextParentId;
  String? _originContextPath;
  bool _startedInBlockMode = false;

  // Bounds cache - separate content bounds from visual bounds
  final Map<String, Rect> _contentBoundsCache = {}; // Just the content
  final Map<String, Rect> _visualBoundsCache = {}; // Including visual elements

  // Handle offset compensation
  static const double _handleYOffset = 30.0; // Handles hang below selection

  // Config
  // static const double _exitPadding = 15.0;
  static const double _reentryPadding = 15.0;

  SelectionManager(this.controller);

  // ============== PUBLIC API ==============

  void startDrag(bool isStartHandle) {
    _isDragging = true;
    _isDraggingStartHandle = isStartHandle;

    final selection = controller.selection;
    if (selection == null) return;

    _fixedAnchor = isStartHandle ? selection.end : selection.start;
    _contextParentId = selection.start.parentId;
    _contextPath = selection.start.path;

    // Determine if we're in block mode (single composite selected)
    _selectedCompositeId = _getSingleSelectedCompositeId(selection);
    _isBlockMode = _selectedCompositeId != null;

    // Remember where this drag started so re-entry can be constrained.
    _originContextParentId = _contextParentId;
    _originContextPath = _contextPath;
    _startedInBlockMode = _isBlockMode;

    _rebuildBoundsCache();
  }

  void endDrag() {
    _isDragging = false;
    _isDraggingStartHandle = false;
    _fixedAnchor = null;
    _selectedCompositeId = null;
    _isBlockMode = false;
    _originContextParentId = null;
    _originContextPath = null;
    _startedInBlockMode = false;
  }

  /// Adjust position to compensate for handle being below the selection
  Offset _adjustForHandle(Offset position) {
    return Offset(position.dx, position.dy - _handleYOffset);
  }

  void updateDrag(Offset rawPosition) {
    if (!_isDragging) return;

    // Compensate for handle position
    final position = _adjustForHandle(rawPosition);

    // CASE 1: In block mode - check for re-entry
    if (_isBlockMode && _selectedCompositeId != null) {
      if (_tryReentry(position)) {
        return;
      }
      // Update selection while in block mode
      _updateBlockModeSelection(position);
      return;
    }

    // CASE 2: Inside a context - check for exit
    if (_contextParentId != null) {
      if (_shouldExit(position)) {
        _performExit();
        return;
      }

      // Check for sibling switch
      final siblingPath = _checkSiblingSwitch(position);
      if (siblingPath != null) {
        _performSiblingSwitch(siblingPath, position);
        return;
      }
    }

    // CASE 3: Normal selection update
    _updateSelectionInContext(position);
  }

  void selectAtPosition(Offset position) {
    _rebuildBoundsCache();

    // Find nearest literal
    NodeLayoutInfo? bestLiteral;
    double bestDist = double.infinity;

    for (final info in controller.layoutRegistry.values) {
      final dist = _distanceToRect(position, info.rect);
      if (dist < bestDist) {
        bestDist = dist;
        bestLiteral = info;
      }
    }

    if (bestLiteral == null) return;

    final text = bestLiteral.node.text;
    if (text.isEmpty) {
      if (bestLiteral.parentId != null) {
        _selectCompositeBlock(bestLiteral.parentId!);
      }
      return;
    }

    // Word selection
    final charIndex = _getCharIndex(bestLiteral, position);
    final (start, end) = _findWordBounds(text, charIndex);

    _contextParentId = bestLiteral.parentId;
    _contextPath = bestLiteral.path;
    _isBlockMode = false;
    _selectedCompositeId = null;

    controller.setSelection(
      SelectionRange(
        start: SelectionAnchor(
          parentId: bestLiteral.parentId,
          path: bestLiteral.path,
          nodeIndex: bestLiteral.index,
          charIndex: start,
        ),
        end: SelectionAnchor(
          parentId: bestLiteral.parentId,
          path: bestLiteral.path,
          nodeIndex: bestLiteral.index,
          charIndex: end,
        ),
      ),
    );
  }

  // ============== RE-ENTRY ==============

  bool _tryReentry(Offset position) {
    if (_selectedCompositeId == null) return false;

    // Don't re-enter if position is outside the composite's visual bounds.
    // This prevents oscillation where _tryReentry re-enters a child context
    // and _shouldExit immediately exits it, creating an infinite loop.
    final compositeBounds = _visualBoundsCache[_selectedCompositeId!];
    if (compositeBounds != null && !compositeBounds.contains(position)) {
      return false;
    }

    // We allow re-entry even during dragging to permit refining selections
    // by dragging handles back into composite nodes.

    // Use content bounds for re-entry (not visual bounds)
    final node = _findNodeById(_selectedCompositeId!);
    if (node == null) return false;

    // Get the content bounds of sub-contexts
    final contexts = _getChildContexts(node);
    for (final ctx in contexts) {
      // If this drag started inside a sub-context (not as a whole-composite
      // block selection), only allow re-entry back into that same origin
      // sub-context. Otherwise an outward drag toward a sibling sub-context
      // (e.g. from the argument toward the base of a log) would re-enter the
      // sibling and collapse/deselect the selection.
      if (!_startedInBlockMode &&
          !(_selectedCompositeId == _originContextParentId &&
              ctx.path == _originContextPath)) {
        continue;
      }

      final ctxBounds =
          _contentBoundsCache['$_selectedCompositeId:${ctx.path}'];
      if (ctxBounds == null) continue;

      // Check if position is within this context's bounds (with small padding)
      final expandedBounds = Rect.fromLTRB(
        ctxBounds.left - _reentryPadding,
        ctxBounds.top - _reentryPadding,
        ctxBounds.right + _reentryPadding,
        ctxBounds.bottom + _reentryPadding,
      );

      if (expandedBounds.contains(position)) {
        // Perform re-entry into this context
        _contextParentId = _selectedCompositeId;
        _contextPath = ctx.path;
        _isBlockMode = false;
        _selectedCompositeId = null;

        // Set fixed anchor at appropriate edge
        final siblings = ctx.nodes;
        if (siblings.isEmpty) return false;

        if (_isDraggingStartHandle) {
          final lastNode = siblings.last;
          _fixedAnchor = SelectionAnchor(
            parentId: _contextParentId,
            path: _contextPath,
            nodeIndex: siblings.length - 1,
            charIndex: lastNode is LiteralNode ? lastNode.text.length : 1,
          );
        } else {
          _fixedAnchor = SelectionAnchor(
            parentId: _contextParentId,
            path: _contextPath,
            nodeIndex: 0,
            charIndex: 0,
          );
        }

        // Create selection at position
        final literal = _findLiteralInContext(
          position,
          _contextParentId,
          _contextPath,
        );
        if (literal != null && _fixedAnchor != null) {
          final charIdx = _getCharIndex(literal, position);
          _createAndSetSelection(
            _fixedAnchor!,
            SelectionAnchor(
              parentId: literal.parentId,
              path: literal.path,
              nodeIndex: literal.index,
              charIndex: charIdx,
            ),
          );
        } else {
          _selectEntireContext(_contextParentId, _contextPath);
        }

        return true;
      }
    }

    return false;
  }

  // ============== EXIT ==============

  bool _shouldExit(Offset position) {
    if (_contextParentId == null) return false;

    // Get the CONTENT bounds of current context (not visual bounds)
    final contextKey = '$_contextParentId:$_contextPath';
    final contentBounds = _contentBoundsCache[contextKey];
    if (contentBounds == null) {
      return false;
    }

    // CHECK: Visual Bounds Logic
    // If we have visual bounds for the parent container, we use them as the primary truth.
    final parentVisualBounds = _visualBoundsCache[_contextParentId];
    if (parentVisualBounds != null) {
      // 1. If we are OUTSIDE the parent's visual bounds, we definitely exit.
      // (This fixes the "stuck in padding" issue)
      if (!parentVisualBounds.contains(position)) {
        return true;
      }

      // 2. We are INSIDE the parent's visual bounds.
      // Check if we are in the "structure" (brackets, etc.) rather than the content.
      final innerContentBounds = Rect.fromLTRB(
        contentBounds.left - 2,
        contentBounds.top - 2,
        contentBounds.right + 2,
        contentBounds.bottom + 2,
      );

      if (!innerContentBounds.contains(position)) {
        // _checkSiblingSwitch handles moving to other contexts.
        // This check is: Am I hitting the container?

        // We should verify we aren't in a sibling's content bounds.
        // Check if we stumbled into a sibling first?
        // REMOVED Sibling Check: If we hit the frame, we prioritize EXIT to select the parent.
        // This allows dragging from Base -> Power to select the whole ExponentNode.
        // The user can click to select specific sibling components.

        return true; // Hit the frame -> Exit
      }
    }

    return false;
  }

  void _performExit() {
    if (_contextParentId == null) return;

    // Select the parent composite as a block
    _selectCompositeBlock(_contextParentId!);
  }

  // ============== SIBLING SWITCH ==============

  String? _checkSiblingSwitch(Offset position) {
    if (_contextParentId == null) return null;

    final parent = _findNodeById(_contextParentId!);
    if (parent == null) return null;

    final siblingPaths = _getSiblingPaths(parent);

    for (final path in siblingPaths) {
      if (path == _contextPath) continue;

      final bounds = _contentBoundsCache['$_contextParentId:$path'];
      if (bounds == null) continue;

      final targetBounds = Rect.fromLTRB(
        bounds.left - 5,
        bounds.top - 5,
        bounds.right + 5,
        bounds.bottom + 5,
      );

      if (targetBounds.contains(position)) {
        return path;
      }
    }

    return null;
  }

  void _performSiblingSwitch(String newPath, Offset position) {
    _contextPath = newPath;

    final siblings = _getSiblings(_contextParentId, _contextPath);
    if (siblings == null || siblings.isEmpty) return;

    // Set fixed anchor at start of new context
    _fixedAnchor = SelectionAnchor(
      parentId: _contextParentId,
      path: _contextPath,
      nodeIndex: 0,
      charIndex: 0,
    );

    final literal = _findLiteralInContext(
      position,
      _contextParentId,
      _contextPath,
    );
    if (literal != null && _fixedAnchor != null) {
      final charIdx = _getCharIndex(literal, position);
      _createAndSetSelection(
        _fixedAnchor!,
        SelectionAnchor(
          parentId: literal.parentId,
          path: literal.path,
          nodeIndex: literal.index,
          charIndex: charIdx,
        ),
      );
    } else {
      _selectEntireContext(_contextParentId, _contextPath);
    }
  }

  // ============== SELECTION UPDATE ==============

  void _updateBlockModeSelection(Offset position) {
    if (_fixedAnchor == null || _selectedCompositeId == null) return;

    // Check if we should exit THIS context (escalate further up)
    // The current context for block selection is the parent of the block.
    // e.g. Exponent > Parenthesis. Context is Exponent. Parenthesis is Block.
    // If we drag outside Exponent, we should select Exponent.
    if (_shouldExit(position)) {
      _performExit();
      return;
    }

    final info = controller.complexNodeMap[_selectedCompositeId!];
    if (info == null) return;

    final siblings = _getSiblings(info.parentId, info.path);
    if (siblings == null) return;

    // Find target node at position
    final targetInfo = _findTargetNodeAtPosition(
      position,
      info.parentId,
      info.path,
      siblings,
    );
    if (targetInfo == null) return;

    SelectionAnchor movingAnchor;

    if (targetInfo.index == info.index) {
      // Same composite - determine which edge
      final bounds = _visualBoundsCache[_selectedCompositeId!];
      int charIndex = 1;
      if (bounds != null && position.dx < bounds.center.dx) {
        charIndex = 0;
      }
      movingAnchor = SelectionAnchor(
        parentId: info.parentId,
        path: info.path,
        nodeIndex: info.index,
        charIndex: charIndex,
      );
    } else {
      // Different node
      if (targetInfo.isComposite) {
        final bounds = _visualBoundsCache[targetInfo.node.id];
        int charIndex = (targetInfo.index > info.index) ? 1 : 0;
        if (bounds != null) {
          charIndex = position.dx < bounds.center.dx ? 0 : 1;
        }
        movingAnchor = SelectionAnchor(
          parentId: info.parentId,
          path: info.path,
          nodeIndex: targetInfo.index,
          charIndex: charIndex,
        );
      } else {
        final literal = targetInfo.layoutInfo;
        if (literal == null) return;
        final charIdx = _getCharIndex(literal, position);
        movingAnchor = SelectionAnchor(
          parentId: literal.parentId,
          path: literal.path,
          nodeIndex: literal.index,
          charIndex: charIdx,
        );
      }
    }

    _createAndSetSelection(_fixedAnchor!, movingAnchor);
  }

  void _updateSelectionInContext(Offset position) {
    if (_fixedAnchor == null) {
      return;
    }

    final siblings = _getSiblings(_contextParentId, _contextPath);
    if (siblings == null || siblings.isEmpty) {
      return;
    }

    // Find target node at position
    final targetInfo = _findTargetNodeAtPosition(
      position,
      _contextParentId,
      _contextPath,
      siblings,
    );
    if (targetInfo == null) {
      return;
    }

    SelectionAnchor movingAnchor;

    if (targetInfo.isComposite) {
      // Composite node - select as block
      final bounds = _visualBoundsCache[targetInfo.node.id];
      int charIndex = 1;
      if (bounds != null && position.dx < bounds.center.dx) {
        charIndex = 0;
      }
      movingAnchor = SelectionAnchor(
        parentId: _contextParentId,
        path: _contextPath,
        nodeIndex: targetInfo.index,
        charIndex: charIndex,
      );
    } else {
      // Literal node
      final literal = targetInfo.layoutInfo;
      if (literal == null) return;
      final charIdx = _getCharIndex(literal, position);
      movingAnchor = SelectionAnchor(
        parentId: literal.parentId,
        path: literal.path,
        nodeIndex: literal.index,
        charIndex: charIdx,
      );
    }

    _createAndSetSelection(_fixedAnchor!, movingAnchor);
  }

  _TargetNodeInfo? _findTargetNodeAtPosition(
    Offset position,
    String? parentId,
    String? path,
    List<MathNode> siblings,
  ) {
    double bestDist = double.infinity;
    _TargetNodeInfo? bestTarget;

    for (int i = 0; i < siblings.length; i++) {
      final node = siblings[i];
      Rect? bounds;
      NodeLayoutInfo? layoutInfo;

      if (node is LiteralNode) {
        for (final info in controller.layoutRegistry.values) {
          if (info.node.id == node.id) {
            bounds = info.rect;
            layoutInfo = info;
            break;
          }
        }
      } else {
        bounds = _visualBoundsCache[node.id];
      }

      if (bounds == null) continue;

      final dist = _distanceToRect(position, bounds);
      if (dist < bestDist) {
        bestDist = dist;
        bestTarget = _TargetNodeInfo(
          node: node,
          index: i,
          isComposite: node is! LiteralNode,
          layoutInfo: layoutInfo,
        );
      }
    }

    return bestTarget;
  }

  void _createAndSetSelection(SelectionAnchor a1, SelectionAnchor a2) {
    if (a1.parentId != a2.parentId || a1.path != a2.path) {
      return;
    }

    final siblings = _getSiblings(a1.parentId, a1.path);
    if (siblings == null || siblings.isEmpty) return;

    // Determine order
    bool a1First =
        a1.nodeIndex < a2.nodeIndex ||
        (a1.nodeIndex == a2.nodeIndex && a1.charIndex <= a2.charIndex);

    int startNode, endNode, startChar, endChar;
    if (a1First) {
      startNode = a1.nodeIndex;
      endNode = a2.nodeIndex;
      startChar = a1.charIndex;
      endChar = a2.charIndex;
    } else {
      startNode = a2.nodeIndex;
      endNode = a1.nodeIndex;
      startChar = a2.charIndex;
      endChar = a1.charIndex;
    }

    // Clamp
    startNode = startNode.clamp(0, siblings.length - 1);
    endNode = endNode.clamp(0, siblings.length - 1);

    // Apply block rules
    for (int i = startNode; i <= endNode && i < siblings.length; i++) {
      final node = siblings[i];
      if (node is LiteralNode) {
        if (i == startNode) startChar = startChar.clamp(0, node.text.length);
        if (i == endNode) endChar = endChar.clamp(0, node.text.length);
      } else {
        if (i == startNode) startChar = 0;
        if (i == endNode) endChar = 1;
      }
    }

    // Same node
    if (startNode == endNode) {
      final node = siblings[startNode];
      if (node is LiteralNode) {
        final minC = math.min(startChar, endChar);
        final maxC = math.max(startChar, endChar);
        controller.setSelection(
          SelectionRange(
            start: SelectionAnchor(
              parentId: a1.parentId,
              path: a1.path,
              nodeIndex: startNode,
              charIndex: minC,
            ),
            end: SelectionAnchor(
              parentId: a1.parentId,
              path: a1.path,
              nodeIndex: endNode,
              charIndex: maxC,
            ),
          ),
        );
        return;
      } else {
        controller.setSelection(
          SelectionRange(
            start: SelectionAnchor(
              parentId: a1.parentId,
              path: a1.path,
              nodeIndex: startNode,
              charIndex: 0,
            ),
            end: SelectionAnchor(
              parentId: a1.parentId,
              path: a1.path,
              nodeIndex: endNode,
              charIndex: 1,
            ),
          ),
        );
        return;
      }
    }

    controller.setSelection(
      SelectionRange(
        start: SelectionAnchor(
          parentId: a1.parentId,
          path: a1.path,
          nodeIndex: startNode,
          charIndex: startChar,
        ),
        end: SelectionAnchor(
          parentId: a1.parentId,
          path: a1.path,
          nodeIndex: endNode,
          charIndex: endChar,
        ),
      ),
    );
  }

  // ============== COMPOSITE SELECTION ==============

  void _selectCompositeBlock(String compositeId) {
    final info = controller.complexNodeMap[compositeId];
    if (info == null) {
      return;
    }

    _selectedCompositeId = compositeId;
    _contextParentId = info.parentId;
    _contextPath = info.path;
    _isBlockMode = true;

    _fixedAnchor = SelectionAnchor(
      parentId: info.parentId,
      path: info.path,
      nodeIndex: info.index,
      charIndex: _isDraggingStartHandle ? 1 : 0,
    );

    controller.setSelection(
      SelectionRange(
        start: SelectionAnchor(
          parentId: info.parentId,
          path: info.path,
          nodeIndex: info.index,
          charIndex: 0,
        ),
        end: SelectionAnchor(
          parentId: info.parentId,
          path: info.path,
          nodeIndex: info.index,
          charIndex: 1,
        ),
      ),
    );
  }

  void _selectEntireContext(String? parentId, String? path) {
    final siblings = _getSiblings(parentId, path);
    if (siblings == null || siblings.isEmpty) return;

    final lastNode = siblings.last;
    final endChar = lastNode is LiteralNode ? lastNode.text.length : 1;

    controller.setSelection(
      SelectionRange(
        start: SelectionAnchor(
          parentId: parentId,
          path: path,
          nodeIndex: 0,
          charIndex: 0,
        ),
        end: SelectionAnchor(
          parentId: parentId,
          path: path,
          nodeIndex: siblings.length - 1,
          charIndex: endChar,
        ),
      ),
    );
  }

  // ============== BOUNDS CACHE ==============

  void _rebuildBoundsCache() {
    _contentBoundsCache.clear();
    _visualBoundsCache.clear();

    // Build root context
    final rootBounds = _computeContextBounds(null, null);
    if (rootBounds != null) {
      _contentBoundsCache['null:null'] = rootBounds;
    }

    // Build for all nodes
    for (final node in controller.expression) {
      _buildBoundsForNode(node);
    }
  }

  void _buildBoundsForNode(MathNode node) {
    if (node is LiteralNode) return;

    // Compute content bounds (just the literals inside)
    final contentBounds = _computeCompositeBounds(
      node,
      includeVisualPadding: false,
    );
    if (contentBounds != null) {
      // Use registered visual bounds if available, otherwise fallback to padded content
      final registered = controller.complexNodeMap[node.id];
      if (registered != null && registered.rect != Rect.zero) {
        _visualBoundsCache[node.id] = registered.rect;
      } else {
        final visualBounds = _computeCompositeBounds(
          node,
          includeVisualPadding: true,
        );
        _visualBoundsCache[node.id] = visualBounds ?? contentBounds;
      }
    }

    // Compute context bounds for children
    final contexts = _getChildContexts(node);
    for (final ctx in contexts) {
      final ctxBounds = _computeContextBounds(node.id, ctx.path);
      if (ctxBounds != null) {
        _contentBoundsCache['${node.id}:${ctx.path}'] = ctxBounds;
      }
      // Recurse
      for (final child in ctx.nodes) {
        _buildBoundsForNode(child);
      }
    }
  }

  Rect? _computeContextBounds(String? parentId, String? path) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final info in controller.layoutRegistry.values) {
      if (info.parentId == parentId && info.path == path) {
        minX = math.min(minX, info.rect.left);
        maxX = math.max(maxX, info.rect.right);
        minY = math.min(minY, info.rect.top);
        maxY = math.max(maxY, info.rect.bottom);
      }
    }

    // Also include complex nodes in this context
    for (final info in controller.complexNodeMap.values) {
      if (info.parentId == parentId &&
          info.path == path &&
          info.rect != Rect.zero) {
        minX = math.min(minX, info.rect.left);
        maxX = math.max(maxX, info.rect.right);
        minY = math.min(minY, info.rect.top);
        maxY = math.max(maxY, info.rect.bottom);
      }
    }

    if (minX == double.infinity) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _computeCompositeBounds(
    MathNode node, {
    required bool includeVisualPadding,
  }) {
    final ids = <String>{};
    _collectDescendantIds(node, ids);

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final info in controller.layoutRegistry.values) {
      if (ids.contains(info.node.id)) {
        minX = math.min(minX, info.rect.left);
        maxX = math.max(maxX, info.rect.right);
        minY = math.min(minY, info.rect.top);
        maxY = math.max(maxY, info.rect.bottom);
      }
    }

    // Also check complex node map for descendants
    // (A composite node's ID is in the descendant set)
    for (final info in controller.complexNodeMap.values) {
      if (ids.contains(info.node.id) && info.rect != Rect.zero) {
        minX = math.min(minX, info.rect.left);
        maxX = math.max(maxX, info.rect.right);
        minY = math.min(minY, info.rect.top);
        maxY = math.max(maxY, info.rect.bottom);
      }
    }

    if (minX == double.infinity) return null;

    if (includeVisualPadding) {
      final pad = _getVisualPadding(node);
      return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  double _getVisualPadding(MathNode node) {
    if (node is ParenthesisNode) return 12.0;
    if (node is TrigNode) return 12.0;
    if (node is LogNode) return 10.0;
    if (node is FractionNode) return 4.0;
    if (node is RootNode) return 10.0;
    return 4.0;
  }

  void _collectDescendantIds(MathNode node, Set<String> ids) {
    ids.add(node.id);
    for (final list in _getAllChildLists(node)) {
      for (final child in list) {
        _collectDescendantIds(child, ids);
      }
    }
  }

  // ============== HELPERS ==============

  String? _getSingleSelectedCompositeId(SelectionRange selection) {
    final norm = selection.normalized;
    if (norm.start.nodeIndex != norm.end.nodeIndex) return null;

    final siblings = _getSiblings(norm.start.parentId, norm.start.path);
    if (siblings == null) return null;

    final idx = norm.start.nodeIndex;
    if (idx >= siblings.length) return null;

    final node = siblings[idx];
    if (node is LiteralNode) return null;

    if (norm.start.charIndex == 0 && norm.end.charIndex == 1) {
      return node.id;
    }
    return null;
  }

  NodeLayoutInfo? _findLiteralInContext(
    Offset position,
    String? parentId,
    String? path,
  ) {
    NodeLayoutInfo? best;
    double bestDist = double.infinity;

    for (final info in controller.layoutRegistry.values) {
      if (info.parentId == parentId && info.path == path) {
        final dist = _distanceToRect(position, info.rect);
        if (dist < bestDist) {
          bestDist = dist;
          best = info;
        }
      }
    }

    return best;
  }

  int _getCharIndex(NodeLayoutInfo info, Offset position) {
    final text = info.node.text;
    if (text.isEmpty) return 0;

    final relX = position.dx - info.rect.left;

    if (info.renderParagraph != null) {
      final displayText = info.displayText;
      final pos = info.renderParagraph!.getPositionForOffset(
        Offset(relX, info.fontSize / 2),
      );
      return MathTextStyle.displayToLogicalIndex(
        text,
        pos.offset.clamp(0, displayText.length),
        forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
      );
    }

    return MathTextStyle.getCharIndexForOffset(
      text,
      relX,
      info.fontSize,
      info.textScaler,
      forceLeadingOperatorPadding: info.forceLeadingOperatorPadding,
    );
  }

  (int, int) _findWordBounds(String text, int charIndex) {
    if (text.isEmpty) return (0, 0);

    int start = charIndex.clamp(0, text.length);
    int end = charIndex.clamp(0, text.length);

    while (start > 0 && !_isWordBoundary(text[start - 1])) {
      start--;
    }
    while (end < text.length && !_isWordBoundary(text[end])) {
      end++;
    }

    if (charIndex < text.length && _isWordBoundary(text[charIndex])) {
      start = charIndex;
      end = charIndex + 1;
    }

    if (start == end && text.isNotEmpty) {
      if (charIndex < text.length) {
        end = charIndex + 1;
      } else if (charIndex > 0) {
        start = charIndex - 1;
      }
    }

    return (start, end);
  }

  MathNode? _findNodeById(String id) {
    return _findNode(controller.expression, id);
  }

  MathNode? _findNode(List<MathNode> nodes, String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
      for (final list in _getAllChildLists(node)) {
        final found = _findNode(list, id);
        if (found != null) return found;
      }
    }
    return null;
  }

  List<MathNode>? _getSiblings(String? parentId, String? path) {
    if (parentId == null) return controller.expression;
    final parent = _findNodeById(parentId);
    if (parent == null) return null;
    return _getChildList(parent, path);
  }

  List<MathNode>? _getChildList(MathNode node, String? path) {
    if (node is FractionNode) {
      if (path == 'num') return node.numerator;
      if (path == 'den') return node.denominator;
    } else if (node is ExponentNode) {
      if (path == 'base') return node.base;
      if (path == 'pow') return node.power;
    } else if (node is TrigNode) {
      if (path == 'arg') return node.argument;
    } else if (node is RootNode) {
      if (path == 'index') return node.index;
      if (path == 'radicand') return node.radicand;
    } else if (node is LogNode) {
      if (path == 'base') return node.base;
      if (path == 'arg') return node.argument;
    } else if (node is ParenthesisNode) {
      if (path == 'content') return node.content;
    } else if (node is PermutationNode) {
      if (path == 'n') return node.n;
      if (path == 'r') return node.r;
    } else if (node is CombinationNode) {
      if (path == 'n') return node.n;
      if (path == 'r') return node.r;
    } else if (node is AnsNode) {
      if (path == 'index') return node.index;
    } else if (node is SummationNode) {
      if (path == 'var') return node.variable;
      if (path == 'lower') return node.lower;
      if (path == 'upper') return node.upper;
      if (path == 'body') return node.body;
    } else if (node is ProductNode) {
      if (path == 'var') return node.variable;
      if (path == 'lower') return node.lower;
      if (path == 'upper') return node.upper;
      if (path == 'body') return node.body;
    } else if (node is IntegralNode) {
      if (path == 'var') return node.variable;
      if (path == 'lower') return node.lower;
      if (path == 'upper') return node.upper;
      if (path == 'body') return node.body;
    } else if (node is DerivativeNode) {
      if (path == 'var') return node.variable;
      if (path == 'at') return node.at;
      if (path == 'body') return node.body;
    }
    return null;
  }

  List<List<MathNode>> _getAllChildLists(MathNode node) {
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

  List<_ChildContext> _getChildContexts(MathNode node) {
    final list = <_ChildContext>[];
    if (node is FractionNode) {
      list.add(_ChildContext(path: 'num', nodes: node.numerator));
      list.add(_ChildContext(path: 'den', nodes: node.denominator));
    } else if (node is ExponentNode) {
      list.add(_ChildContext(path: 'base', nodes: node.base));
      list.add(_ChildContext(path: 'pow', nodes: node.power));
    } else if (node is TrigNode) {
      list.add(_ChildContext(path: 'arg', nodes: node.argument));
    } else if (node is RootNode) {
      list.add(_ChildContext(path: 'index', nodes: node.index));
      list.add(_ChildContext(path: 'radicand', nodes: node.radicand));
    } else if (node is LogNode) {
      list.add(_ChildContext(path: 'base', nodes: node.base));
      list.add(_ChildContext(path: 'arg', nodes: node.argument));
    } else if (node is ParenthesisNode) {
      list.add(_ChildContext(path: 'content', nodes: node.content));
    } else if (node is PermutationNode) {
      list.add(_ChildContext(path: 'n', nodes: node.n));
      list.add(_ChildContext(path: 'r', nodes: node.r));
    } else if (node is CombinationNode) {
      list.add(_ChildContext(path: 'n', nodes: node.n));
      list.add(_ChildContext(path: 'r', nodes: node.r));
    } else if (node is AnsNode) {
      list.add(_ChildContext(path: 'index', nodes: node.index));
    } else if (node is SummationNode) {
      list.add(_ChildContext(path: 'var', nodes: node.variable));
      list.add(_ChildContext(path: 'lower', nodes: node.lower));
      list.add(_ChildContext(path: 'upper', nodes: node.upper));
      list.add(_ChildContext(path: 'body', nodes: node.body));
    } else if (node is ProductNode) {
      list.add(_ChildContext(path: 'var', nodes: node.variable));
      list.add(_ChildContext(path: 'lower', nodes: node.lower));
      list.add(_ChildContext(path: 'upper', nodes: node.upper));
      list.add(_ChildContext(path: 'body', nodes: node.body));
    } else if (node is IntegralNode) {
      list.add(_ChildContext(path: 'var', nodes: node.variable));
      if (node.isDefinite) {
        list.add(_ChildContext(path: 'lower', nodes: node.lower));
        list.add(_ChildContext(path: 'upper', nodes: node.upper));
      }
      list.add(_ChildContext(path: 'body', nodes: node.body));
    } else if (node is DerivativeNode) {
      list.add(_ChildContext(path: 'var', nodes: node.variable));
      if (node.isDefinite) {
        list.add(_ChildContext(path: 'at', nodes: node.at));
      }
      list.add(_ChildContext(path: 'body', nodes: node.body));
    }
    return list;
  }

  List<String> _getSiblingPaths(MathNode node) {
    if (node is FractionNode) return ['num', 'den'];
    if (node is ExponentNode) return ['base', 'pow'];
    if (node is RootNode) return ['index', 'radicand'];
    if (node is LogNode) return ['base', 'arg'];
    if (node is PermutationNode) return ['n', 'r'];
    if (node is CombinationNode) return ['n', 'r'];
    if (node is SummationNode) return ['var', 'lower', 'upper', 'body'];
    if (node is ProductNode) return ['var', 'lower', 'upper', 'body'];
    if (node is IntegralNode) {
      return node.isDefinite
          ? ['var', 'lower', 'upper', 'body']
          : ['var', 'body'];
    }
    if (node is DerivativeNode) {
      return node.isDefinite ? ['var', 'at', 'body'] : ['var', 'body'];
    }
    return [];
  }

  double _distanceToRect(Offset p, Rect r) {
    double dx = 0, dy = 0;
    if (p.dx < r.left) {
      dx = r.left - p.dx;
    } else if (p.dx > r.right) {
      dx = p.dx - r.right;
    }
    if (p.dy < r.top) {
      dy = r.top - p.dy;
    } else if (p.dy > r.bottom) {
      dy = p.dy - r.bottom;
    }
    return math.sqrt(dx * dx + dy * dy);
  }

  bool _isWordBoundary(String c) {
    return {
      '+',
      '-',
      '×',
      '·',
      '÷',
      '/',
      '=',
      '(',
      ')',
      ' ',
      '\u2212',
    }.contains(c);
  }
}

class _ChildContext {
  final String path;
  final List<MathNode> nodes;
  _ChildContext({required this.path, required this.nodes});
}

class _TargetNodeInfo {
  final MathNode node;
  final int index;
  final bool isComposite;
  final NodeLayoutInfo? layoutInfo;

  _TargetNodeInfo({
    required this.node,
    required this.index,
    required this.isComposite,
    this.layoutInfo,
  });
}
