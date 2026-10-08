import 'selection_manager.dart';
import 'renderer.dart';
import 'selection_wrapper.dart';
import '../math_engine/math_expression_serializer.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'expression_selection.dart';
import 'cursor.dart';
part 'editor_history.dart';
part 'editor_layout.dart';
part 'editor_insertion.dart';
part 'editor_tree.dart';
part 'editor_deletion.dart';
part 'editor_selection.dart';

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

  String expr = '';
  int _structureVersion = 0;
  int get structureVersion => _structureVersion;
  VoidCallback? onResultChanged;

  Map<String, ComplexNodeInfo> get complexNodeMap => _complexNodeMap;

  // Add this field
  late final SelectionManager _selectionManager = SelectionManager(this);

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

  /// Layouts reported from paint, waiting for the frame to finish (see
  /// [EditorLayout.reportNodeLayout]).
  final List<NodeLayoutInfo> _reportedNodeLayouts = <NodeLayoutInfo>[];
  final List<ComplexNodeInfo> _reportedComplexLayouts = <ComplexNodeInfo>[];
  bool _reportFlushScheduled = false;
  bool _disposed = false;

  /// [notifyListeners] for the parts of this class kept in other files,
  /// whose extensions may not call a protected member directly.
  void _notifyListeners() => notifyListeners();

  MathEditorController() {
    selectionWrapper = SelectionWrapper(this);
  }

  @override
  void dispose() {
    _disposed = true;
    _cursorNotifier.dispose();
    cursorPaintNotifier.dispose(); // Add this line
    super.dispose();
  }

  // Method to refresh display when settings change
  void refreshDisplay() {
    _structureVersion++;
    notifyListeners();
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
        MathTextStyle.relationalSigns.contains(char) ||
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
        MathTextStyle.relationalSigns.contains(char) ||
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
        MathTextStyle.relationalSigns.contains(char) ||
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

  static bool _isSerializedDigit(String char) {
    return char.isNotEmpty && '0123456789.'.contains(char);
  }

  /// Caret anchors inserted by a cursor move that has not been published yet.
  ///
  /// Moving past an atomic symbol, or into a field whose edge is not a
  /// literal, has to insert an empty literal for the caret to sit in —
  /// [_positionAfterAtomic] and the four helpers around it all do it. That is
  /// a change to the tree, but the callers are cursor movements and they only
  /// ever called `notifyListeners`, which does not bump [structureVersion].
  ///
  /// Nothing downstream then noticed. The layout registry is only cleared on a
  /// version change, and each node re-reports its box only when the version
  /// changes, so every sibling after the insertion kept the index it had
  /// before — off by one for the rest of the session. Taps resolved to the
  /// node before the one touched, and the character went in the wrong place.
  ///
  /// Counted here rather than threaded back through the sixty-odd call sites
  /// of those helpers; [notifyListeners] drains it.
  int _pendingCaretAnchors = 0;

  /// Publishes a change, upgrading a plain notify to a structure change when
  /// the work that led here inserted a caret anchor.
  ///
  /// Overridden rather than added as a second method so that no caller can
  /// forget: every path out of the editor ends in a notify, and the ones that
  /// insert an anchor are spread across the delete handlers, the arrow keys
  /// and the structure-exit helpers.
  @override
  void notifyListeners() {
    if (_pendingCaretAnchors > 0) {
      _pendingCaretAnchors = 0;
      _structureVersion++;
      _rebuildComplexNodeMap();
    }
    super.notifyListeners();
  }

  void _notifyStructureChanged() {
    // Folded into this bump rather than counted twice.
    _pendingCaretAnchors = 0;
    _structureVersion++;
    _rebuildComplexNodeMap();
    notifyListeners();
    // Remove any postFrameCallback here - let registerNodeLayout handle cursor rect
  }

  void setCursor(EditorCursor c) {
    cursor = c;
    notifyListeners();
  }

  /// Set expression from loaded data
  void setExpression(List<MathNode> nodes) {
    expression = nodes.isNotEmpty ? nodes : [LiteralNode()];
    // Built from the list that is actually kept, not from the argument: an
    // empty argument is replaced above, and mapping the empty one left the
    // map describing a tree that was never displayed.
    _rebuildComplexNodeMap();

    // The old range refers to nodes that are no longer in the tree.
    clearSelection(notify: false);

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
    // An expression that ends in a fraction, a root or a constant leaves the
    // caret on a node nothing can type into — which on a restored row means
    // the keypad is dead from launch until the caret is moved some other way.
    _ensureCursorInLiteral();
    notifyListeners();
  }

  /// Note that the expression changed: serialize it, and tell the owner, which
  /// redraws the plot from it.
  ///
  /// Nothing is evaluated here. klotter plots its expressions and shows no
  /// result, so the answer this once worked out — and the background isolate
  /// meant to work it out off the UI thread, which was never connected — had
  /// nobody to show it to.
  void onCalculate() {
    expr = MathExpressionSerializer.serialize(expression);
    onResultChanged?.call();
  }

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

  /// Select word/element at position (for long-press)

  /// Notify listeners and recalculate (used by SelectionWrapper)

  // Add this field
  final Map<String, ComplexNodeInfo> _complexNodeMap = {};
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
