part of 'math_editor_controller.dart';

/// Undo and redo inside one expression: the editor's own history, as
/// distinct from the app's, which restores whole plots.
extension EditorHistory on MathEditorController {
  /// Save current state before making changes
  void saveStateForUndo() {
    if (_isUndoRedoOperation) return;

    // Skip a redundant snapshot when the expression is unchanged since the last
    // one. This collapses the double snapshots produced when insertCharacter and
    // a delegating handler (insertAns, _wrapSelectionInParenthesis, ...) both
    // save before any mutation, so one keystroke maps to one undo entry.
    if (_undoStack.isNotEmpty) {
      final lastExpr = MathExpressionSerializer.serialize(
        _undoStack.last.expression,
      );
      final currentExpr = MathExpressionSerializer.serialize(expression);
      if (lastExpr == currentExpr) return;
    }

    _undoStack.add(EditorState.capture(expression, cursor));

    // Limit stack size
    if (_undoStack.length > MathEditorController._maxHistorySize) {
      _undoStack.removeAt(0);
    }

    // Clear redo stack when new action is performed
    _redoStack.clear();
  }

  /// Undo the last action
  void undo() {
    if (!canUndo) return;

    _isUndoRedoOperation = true;

    // Save current state to redo stack
    _redoStack.add(EditorState.capture(expression, cursor));

    // Restore previous state
    EditorState previousState = _undoStack.removeLast();
    expression = previousState.expression;
    cursor = previousState.cursor;
    _rebuildComplexNodeMap();
    _structureVersion++;

    _isUndoRedoOperation = false;

    _scheduleCursorRecalc();
    _notifyListeners();
    onResultChanged?.call();
  }

  /// Redo the last undone action
  void redo() {
    if (!canRedo) return;

    _isUndoRedoOperation = true;

    // Save current state to undo stack
    _undoStack.add(EditorState.capture(expression, cursor));

    // Restore redo state
    EditorState redoState = _redoStack.removeLast();
    expression = redoState.expression;
    cursor = redoState.cursor;
    _rebuildComplexNodeMap();
    _structureVersion++;

    _isUndoRedoOperation = false;

    _scheduleCursorRecalc();
    _notifyListeners();
    onResultChanged?.call();
  }

  /// Clear undo/redo history
  void clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
