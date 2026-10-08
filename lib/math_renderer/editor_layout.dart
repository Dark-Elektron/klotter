part of 'math_editor_controller.dart';

/// Where things are on screen: the registry of laid-out nodes, the caret's
/// rectangle, and turning a tap into a cursor position.
extension EditorLayout on MathEditorController {
  String _makeLayoutKey(String? parentId, String? path, int index) {
    return '${parentId ?? 'root'}:${path ?? 'root'}:$index';
  }

  void registerNodeLayout(NodeLayoutInfo info) {
    _layoutRegistry[info.node.id] = info;
    _layoutIndex[_makeLayoutKey(info.parentId, info.path, info.index)] = info;

    // The bounds are derived from this registry, so a new box makes the cached
    // ones wrong. They were only invalidated when the registry was cleared,
    // and the registry fills over several frames — the retry path in
    // `_LiteralWidgetState` spreads it out — so a read landing mid-fill cached
    // a rectangle covering only the nodes that had reported so far, and kept
    // it until the next structure change. `_processTap` decides "tapped past
    // the left/right edge" from these, so a tap in the middle of a long
    // expression could be read as a tap past its end.
    _contentBoundsValid = false;
    _cachedContentBounds = null;

    _tryUpdateCursorRectFor(info);
  }

  void registerComplexNodeLayout(ComplexNodeInfo info) {
    _complexNodeMap[info.node.id] = info;
  }

  /// A node's layout, as measured while it was painted (see
  /// [LayoutReporter]); registered once the frame is done.
  ///
  /// Painting is where a node's place is known, but registering can move the
  /// caret, and the caret's notifier may not be told anything during paint. So
  /// the measurement is taken there and applied straight after the frame:
  /// nothing is read back from a box that might have moved since.
  void reportNodeLayout(NodeLayoutInfo info) {
    _reportedNodeLayouts.add(info);
    _scheduleReportFlush();
  }

  /// [reportNodeLayout] for a composite node's whole box.
  void reportComplexNodeLayout(ComplexNodeInfo info) {
    _reportedComplexLayouts.add(info);
    _scheduleReportFlush();
  }

  void _scheduleReportFlush() {
    if (_reportFlushScheduled) return;
    _reportFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportFlushScheduled = false;
      final List<NodeLayoutInfo> nodes = List<NodeLayoutInfo>.of(
        _reportedNodeLayouts,
      );
      final List<ComplexNodeInfo> complexes = List<ComplexNodeInfo>.of(
        _reportedComplexLayouts,
      );
      _reportedNodeLayouts.clear();
      _reportedComplexLayouts.clear();
      if (_disposed) return;
      for (final ComplexNodeInfo info in complexes) {
        registerComplexNodeLayout(info);
      }
      for (final NodeLayoutInfo info in nodes) {
        registerNodeLayout(info);
      }
    });
  }

  /// Puts the caret where the current cursor position actually is.
  ///
  /// The rect is otherwise only refreshed opportunistically, as each node
  /// reports its layout: [_tryUpdateCursorRectFor] updates it when the node
  /// registering happens to be the one the cursor sits in. That covers typing,
  /// where the cursor moves to a node that is about to lay out anyway, but not
  /// a fresh build — reopening the app rebuilds every row from storage with a
  /// cursor already set, and if no registering node matches it, the caret
  /// keeps whatever rect it had and is drawn away from the expression.
  ///
  /// Safe to call at any time: with nothing registered yet it leaves the rect
  /// alone rather than guessing.
  void recalculateCursorPosition() {
    if (_layoutRegistry.isEmpty) return;
    final EditorCursor at = _cursorNotifier.value;
    final NodeLayoutInfo? info =
        _layoutIndex[_makeLayoutKey(at.parentId, at.path, at.index)];
    if (info == null) return;
    _tryUpdateCursorRectFor(info);
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

    final text = info.literalText;
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
    // The nearest node on the line that was tapped, which is preferred over
    // anything nearer on another line.
    //
    // Straight-line distance is the right answer only while an expression is
    // one line, which is how it was in the app this came from — its action key
    // starts a new cell. Here it inserts a newline in the same cell, so one
    // editor holds several lines, and the nearest node to a tap past the end of
    // a short line is often on the long line above it. The caret then landed on
    // a line the user was not pointing at, and the next backspace deleted from
    // there.
    NodeLayoutInfo? bestOnLine;
    double minLineDistance = double.infinity;

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

      // On the tapped line, only the horizontal gap matters: the node at the
      // end of that line is the one being reached for.
      if (position.dy >= info.rect.top && position.dy <= info.rect.bottom) {
        final double gap = dx.abs();
        if (gap < minLineDistance) {
          minLineDistance = gap;
          bestOnLine = info;
        }
      }
    }

    final targetNode = bestContain ?? bestOnLine ?? bestNearest;
    if (targetNode != null) {
      _processTapAtNode(targetNode, position);
    }
  }

  void _processTapAtNode(NodeLayoutInfo info, Offset position) {
    _lastTappedNode = info;

    // A symbol that is one object — π, x̂, z̲, ε₀ — has a box but no interior,
    // so the caret goes to one side of it and never inside it.
    //
    // Falling through to the code below put the cursor on the atom's own
    // index, which is a position nothing can edit: `_updateLiteralAtCursor`
    // resolves a non-literal and does nothing, `deleteChar` returns, and
    // `moveRight` is wrapped in a literal test and cannot escape. Tapping a
    // constant left the keypad apparently dead until the caret was moved some
    // other way, which is what made it look intermittent.
    if (info.isAtomic) {
      _placeCaretBesideAtom(info, position);
      return;
    }

    final text = info.literalText;
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

  /// Put the caret on the side of an atomic symbol the tap fell on.
  ///
  /// The symbol's live index is looked up rather than taken from [info],
  /// because a registered box carries the index it had when it was measured
  /// and the caret helpers insert into the list they are handed — using a
  /// stale index here would anchor the caret to the wrong sibling.
  void _placeCaretBesideAtom(NodeLayoutInfo info, Offset position) {
    final _ParentListInfo? place = _findParentListOf(info.node.id);
    if (place == null) return;

    final bool after = position.dx >= info.rect.center.dx;
    if (after) {
      _positionAfterAtomic(place.list, place.index, place.parentId, place.path);
    } else {
      _positionBeforeAtomic(
        place.list,
        place.index,
        place.parentId,
        place.path,
      );
    }

    // Close enough to avoid a visible jump; the exact rect arrives when the
    // anchor literal reports its box.
    cursorPaintNotifier.updateRectDirect(
      Rect.fromLTWH(
        after ? info.rect.right : info.rect.left,
        info.rect.top,
        2,
        info.rect.height,
      ),
    );

    // Upgrades itself to a structure change when an anchor had to be made.
    _notifyListeners();
  }

  /// Put the caret at the start of the line, for a tap off the left edge.
  ///
  /// [atY] is where that tap was. Without it this takes the leftmost node of
  /// the whole expression, which is the start of the first line rather than of
  /// the line pointed at — right while an expression is a single line, wrong
  /// here, where one cell holds several. Null keeps the old whole-expression
  /// behaviour, for callers that have no position to offer.
  void moveCursorToStartWithRect({double? atY}) {
    if (_layoutRegistry.isEmpty) {
      return;
    }

    // Find the leftmost literal node
    NodeLayoutInfo? leftmostInfo;
    double minLeft = double.infinity;

    for (final info in _layoutRegistry.values) {
      if (!_isOnLine(info, atY)) continue;
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

  /// True when [info] is on the line at [atY], or when no line was named.
  ///
  /// A node whose vertical span contains the point is on that line. Falling
  /// back to true for a null [atY] keeps every existing caller working on the
  /// whole expression.
  bool _isOnLine(NodeLayoutInfo info, double? atY) {
    if (atY == null) return true;
    return atY >= info.rect.top && atY <= info.rect.bottom;
  }

  /// Put the caret at the end of the line, for a tap off the right edge.
  ///
  /// See [moveCursorToStartWithRect]: without [atY] this finds the rightmost
  /// node anywhere, which on a multi-line expression is the end of the *widest*
  /// line rather than the one being pointed at.
  void moveCursorToEndWithRect({double? atY}) {
    if (_layoutRegistry.isEmpty) return;

    // Find the rightmost literal node
    NodeLayoutInfo? rightmostInfo;
    double maxRight = double.negativeInfinity;

    for (final info in _layoutRegistry.values) {
      if (!_isOnLine(info, atY)) continue;
      if (info.rect.right > maxRight) {
        maxRight = info.rect.right;
        rightmostInfo = info;
      }
    }

    if (rightmostInfo == null) return;

    final text = rightmostInfo.literalText;
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

  void recalculateCursorRect() {
    final c = cursor;

    final key = _makeLayoutKey(c.parentId, c.path, c.index);

    final info = _layoutIndex[key];

    if (info == null) {
      return;
    }

    // Calculate cursor position
    final text = info.literalText;
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

  void notifyAndRecalculate() {
    _rebuildComplexNodeMap(); // Add this line
    _structureVersion++;
    _notifyListeners();
    onCalculate();
    onResultChanged?.call();
  }

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
}
