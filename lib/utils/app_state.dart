import '../math_engine/math_expression_serializer.dart';
import '../math_renderer/renderer.dart';
import '../math_renderer/expression_selection.dart';
import '../plotting/models/plot_view_state.dart';

/// One row of one cell, as undo remembers it.
class RowState {
  const RowState({required this.nodes, required this.visible});

  final List<MathNode> nodes;
  final bool visible;
}

/// Represents the state of all cells for app-level undo/redo
class AppState {
  /// Every row of every cell, outer list by cell and inner by row.
  ///
  /// It used to be one expression per cell, taken from a map that holds each
  /// cell's *active* row — so a cell with three rows was remembered as one.
  /// Undoing then rebuilt each cell with a single row and the rest were gone,
  /// and redo brought back only the row the caret had been in.
  final List<List<RowState>> cells;
  final int activeIndex;
  final int activeRow;

  /// Where each cell's plot was left, aligned with [cells].
  ///
  /// For a plot that comes back from nothing — undoing a clear — so it opens
  /// where it was. Not part of the [signature]: moving a view is not an edit,
  /// and must not fill the history.
  final List<PlotViewState?> views;

  AppState({
    required this.cells,
    required this.activeIndex,
    required this.activeRow,
    this.views = const <PlotViewState?>[],
  });

  /// How many cells this state holds.
  int get cellCount => cells.length;

  /// Capture every row of every cell.
  static AppState capture(
    Map<int, List<RowState>> rowsByCell,
    int activeIndex,
    int activeRow, {
    List<PlotViewState?> views = const <PlotViewState?>[],
  }) {
    final List<int> sortedKeys = rowsByCell.keys.toList()..sort();

    final List<List<RowState>> cells = <List<RowState>>[];

    for (final int key in sortedKeys) {
      final List<RowState> rows = rowsByCell[key] ?? const <RowState>[];
      cells.add(<RowState>[
        for (final RowState r in rows)
          RowState(
            // Deep copied, or undo would hand back the live tree and every
            // later edit would rewrite the history it came from.
            nodes: MathClipboard.deepCopyNodes(r.nodes),
            visible: r.visible,
          ),
      ]);
    }

    return AppState(
      cells: cells,
      activeIndex: activeIndex,
      activeRow: activeRow,
      views: views,
    );
  }

  /// A value that changes exactly when the *expressions* do.
  ///
  /// The active cell is left out, so moving the caret between cells does not
  /// fill the undo history with entries that appear to do nothing when
  /// undone.
  String get signature {
    final StringBuffer out = StringBuffer();
    for (final List<RowState> rows in cells) {
      // A row boundary of its own, so moving a line between cells is a change
      // even when the text as a whole is the same.
      out.write('|');
      for (final RowState row in rows) {
        out.write(row.visible ? 'v' : 'h');
        _writeNodes(out, row.nodes);
      }
    }
    return out.toString();
  }

  static void _writeNodes(StringBuffer out, List<MathNode> nodes) {
    try {
      out.write(MathExpressionSerializer.serializeToJson(nodes));
    } catch (_) {
      // A tree the serializer cannot express still has to compare as
      // *something*; its length at least changes when the row does.
      out.write('?${nodes.length}');
    }
    out.write(' ');
  }
}
