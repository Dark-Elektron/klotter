import '../math_engine/math_expression_serializer.dart';
import '../math_renderer/cell_persistence_service.dart';
import '../math_renderer/expression_row.dart';
import '../math_renderer/expression_selection.dart';
import '../math_renderer/math_editor_controller.dart';
import '../math_renderer/math_nodes.dart';
import '../plotting/models/plot_view_state.dart';
import '../plotting/parsers/plot_expression.dart';
import '../utils/app_state.dart';

/// One plot: the rows it draws, in order, and where its view was left.
class Plot {
  Plot._(this.id);

  /// Stable for the session, unlike the plot's position, which changes when a
  /// plot is added or removed before it.
  ///
  /// Whatever the screen keeps about a plot — its panel's key, the errors its
  /// rows reported, how tall its rows measured — is kept against this. It used
  /// to be kept against the position, in a dozen maps that all had to be
  /// renumbered in step whenever a plot came or went, and each one missed was a
  /// plot opening with another's panel or error marks.
  final String id;

  /// The expression rows, top to bottom.
  final List<ExpressionRow> rows = <ExpressionRow>[];

  /// Where the plot was last left: restored from storage, taken from its panel
  /// on leaving it, and kept up to date as the view moves.
  PlotViewState view = PlotViewState.initial;
}

/// Every plot, in order, which one is open, and which of its rows is being
/// typed into — with the history that undo and redo move through, and the
/// conversion to and from what is saved.
///
/// The document, held apart from the screen that shows it. It owns the rows;
/// the home page draws them, wires their editors up through [onRowCreated],
/// and keeps only what is about drawing (panel keys, measured heights) against
/// each plot's [Plot.id].
class Notebook {
  /// Starts with one empty plot, which is what a fresh install opens on.
  Notebook({this.onRowCreated}) {
    plots.add(_newPlot());
  }

  /// Called for every row the notebook makes, so the app can listen to it.
  final void Function(ExpressionRow row)? onRowCreated;

  /// The plots, in the order they are swiped through.
  final List<Plot> plots = <Plot>[];

  /// Which plot is open.
  int activeIndex = 0;

  /// Which row of the open plot is being typed into.
  int activeRow = 0;

  static int _nextPlotId = 0;

  Plot _newPlot() {
    final Plot plot = Plot._('p${_nextPlotId++}');
    plot.rows.add(_newRow());
    return plot;
  }

  ExpressionRow _newRow() {
    final ExpressionRow row = ExpressionRow(id: ExpressionRowIds.take());
    onRowCreated?.call(row);
    return row;
  }

  // ---- reading it --------------------------------------------------------

  int get count => plots.length;

  /// The open plot.
  Plot get activePlot => plots[activeIndex.clamp(0, plots.length - 1)];

  /// The rows of the plot at [index], or none for an index out of range.
  List<ExpressionRow> rowsOf(int index) =>
      index >= 0 && index < plots.length
          ? plots[index].rows
          : const <ExpressionRow>[];

  /// The row a plot is showing a caret in.
  ///
  /// Only the open plot has a live row cursor; every other plot answers with
  /// its first row, which is what callers that want "this plot's expression"
  /// mean.
  ExpressionRow? activeRowOf(int index) {
    final List<ExpressionRow> rows = rowsOf(index);
    if (rows.isEmpty) return null;
    if (index != activeIndex) return rows.first;
    return rows[activeRow.clamp(0, rows.length - 1)];
  }

  /// Every row of every plot.
  Iterable<ExpressionRow> get allRows => plots.expand((Plot plot) => plot.rows);

  /// Which plot [row] belongs to, or null once it has gone.
  ///
  /// Looked up, never remembered: a row's position changes whenever a plot is
  /// added or removed before it.
  int? indexOfRow(ExpressionRow row) {
    for (int i = 0; i < plots.length; i++) {
      if (plots[i].rows.contains(row)) return i;
    }
    return null;
  }

  /// Every row of a plot, joined as the one node list the panel draws from.
  ///
  /// Rows are separated by the `NewlineNode` the panel splits on.
  List<MathNode> plotNodes(int index) {
    final List<MathNode> out = <MathNode>[];
    for (final ExpressionRow row in rowsOf(index)) {
      if (out.isNotEmpty) out.add(NewlineNode());
      out.addAll(row.controller.expression);
    }
    return out;
  }

  /// Whether the plot at [index] has anything typed on it.
  ///
  /// Measured from the serialized expression rather than the node list: an
  /// empty row still holds one placeholder node. Backspace uses the same test
  /// to decide a row is empty enough to delete, so the two agree.
  bool hasContent(int index) =>
      activeRowOf(index)?.controller.getExpression().trim().isNotEmpty ?? false;

  // ---- changing it -------------------------------------------------------

  /// Add a row below the one being typed into, and move to it. Null when that
  /// row is empty: pressing the key twice would otherwise leave a trail of
  /// blank rows, each with a swatch and a toggle for a curve that is not there.
  ExpressionRow? addRowBelowActive() {
    if (plots.isEmpty) return null;
    final List<ExpressionRow> rows = activePlot.rows;
    final ExpressionRow? current = activeRowOf(activeIndex);
    if (current != null && current.controller.getExpression().isEmpty) {
      return null;
    }
    final int at = (activeRow + 1).clamp(0, rows.length);
    final ExpressionRow row = _newRow();
    rows.insert(at, row);
    activeRow = at;
    return row;
  }

  /// Remove the row being typed into, and say whether it could be.
  ///
  /// A plot keeps its last row: with no expression it has nothing to draw and
  /// nowhere to type, so the caller removes the whole plot instead.
  bool removeActiveRow() {
    if (plots.isEmpty) return false;
    final List<ExpressionRow> rows = activePlot.rows;
    if (rows.length <= 1) return false;
    final int at = activeRow.clamp(0, rows.length - 1);
    final ExpressionRow row = rows.removeAt(at);
    activeRow = (at - 1).clamp(0, rows.length - 1);
    row.dispose();
    return true;
  }

  /// Insert a new, empty plot at [at] — after the open one unless told — and
  /// open it.
  Plot insertPlot({int? at}) {
    final int index = (at ?? activeIndex + 1).clamp(0, plots.length);
    final Plot plot = _newPlot();
    plots.insert(index, plot);
    activeIndex = index;
    return plot;
  }

  /// Remove the plot at [index], and say whether it could be: the last plot
  /// stays.
  bool removePlotAt(int index) {
    if (plots.length <= 1 || index < 0 || index >= plots.length) return false;
    for (final ExpressionRow row in plots.removeAt(index).rows) {
      row.dispose();
    }
    if (activeIndex == index) {
      activeIndex = index > 0 ? index - 1 : 0;
    } else if (activeIndex > index) {
      activeIndex -= 1;
    }
    return true;
  }

  /// Down to one empty plot.
  ///
  /// The first plot is emptied rather than replaced, so its panel and the view
  /// it was left at survive, as they did when the plots were numbered.
  void clear() {
    final Plot first = plots.first;
    for (final Plot plot in plots) {
      _disposeRowsOf(plot);
    }
    plots
      ..clear()
      ..add(first);
    first.rows.add(_newRow());
    activeIndex = 0;
  }

  void _disposeRowsOf(Plot plot) {
    for (final ExpressionRow row in plot.rows) {
      row.dispose();
    }
    plot.rows.clear();
  }

  /// Release every row's editor.
  void dispose() {
    for (final Plot plot in plots) {
      _disposeRowsOf(plot);
    }
  }

  // ---- saving it ---------------------------------------------------------

  /// Replace everything with what was saved, opening plot [savedIndex].
  ///
  /// A save from before rows existed holds each plot as one expression, so it
  /// is split on its newlines — the same division the plot was already making
  /// to draw one curve per line.
  void restore(List<CellData> saved, int savedIndex) {
    dispose();
    plots.clear();
    for (final CellData cell in saved) {
      final Plot plot = _newPlot();
      final List<List<MathNode>> lines =
          cell.rowsJson.isNotEmpty
              ? <List<MathNode>>[
                for (final String json in cell.rowsJson)
                  MathExpressionSerializer.deserializeFromJson(json),
              ]
              : PlotExpression.splitLines(
                MathExpressionSerializer.deserializeFromJson(
                  cell.expressionJson,
                ),
              );
      while (plot.rows.length < lines.length) {
        plot.rows.add(_newRow());
      }
      for (int i = 0; i < lines.length; i++) {
        plot.rows[i].controller.setExpression(lines[i]);
        plot.rows[i].visible = i >= cell.hidden.length || !cell.hidden[i];
      }
      final Map<String, dynamic>? view = cell.plotView;
      if (view != null) plot.view = PlotViewState.fromJson(view);
      plots.add(plot);
    }
    if (plots.isEmpty) plots.add(_newPlot());
    activeIndex = savedIndex.clamp(0, plots.length - 1);
  }

  /// What [CellPersistence.saveRows] writes: each plot's rows, which of them
  /// are hidden, and its view, with the open plot's place among them. A plot
  /// with no rows is left out, so the open plot's place is counted among what
  /// is written rather than among all the plots.
  ({
    List<List<List<MathNode>>> rows,
    List<List<bool>> hidden,
    List<Map<String, dynamic>?> views,
    int activeIndex,
  })
  toSaved() {
    final List<List<List<MathNode>>> rows = <List<List<MathNode>>>[];
    final List<List<bool>> hidden = <List<bool>>[];
    final List<Map<String, dynamic>?> views = <Map<String, dynamic>?>[];
    int active = 0;
    for (int i = 0; i < plots.length; i++) {
      final Plot plot = plots[i];
      if (plot.rows.isEmpty) continue;
      if (i == activeIndex) active = rows.length;
      rows.add(<List<MathNode>>[
        for (final ExpressionRow row in plot.rows) row.controller.expression,
      ]);
      hidden.add(<bool>[
        for (final ExpressionRow row in plot.rows) !row.visible,
      ]);
      views.add(plot.view.isInitial ? null : plot.view.toJson());
    }
    return (rows: rows, hidden: hidden, views: views, activeIndex: active);
  }

  // ---- its history -------------------------------------------------------

  static const int _maxHistory = 10;
  final List<AppState> _undo = <AppState>[];
  final List<AppState> _redo = <AppState>[];

  /// The state as of the last recorded history point, and its signature.
  ///
  /// Undo has to restore the state *before* an edit, but the hooks every edit
  /// passes through run after the change has been made. So the previous state
  /// is held here and pushed when the next change is noticed, rather than
  /// intercepting every place that edits: keys, selection wraps, paste, plots
  /// added and removed.
  AppState? _mark;
  String? _markSignature;

  /// True while an undo or redo is being applied, so restoring does not record
  /// itself as a fresh edit.
  bool _restoring = false;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// How many steps undo can take.
  int get undoDepth => _undo.length;

  /// Every row of every plot, and every plot's view, as undo remembers them.
  AppState capture() => AppState.capture(
    <int, List<RowState>>{
      for (int i = 0; i < plots.length; i++)
        i: <RowState>[
          for (final ExpressionRow r in plots[i].rows)
            RowState(nodes: r.controller.expression, visible: r.visible),
        ],
    },
    activeIndex,
    activeRow,
    views: <PlotViewState>[for (final Plot plot in plots) plot.view],
  );

  /// Note the current state as the baseline, without recording an undo step.
  void markHistory() {
    _mark = capture();
    _markSignature = _mark!.signature;
  }

  /// Record an undo point if the expressions changed since the last one.
  void recordHistoryPoint() {
    if (_restoring) return;
    final AppState current = capture();
    final String signature = current.signature;
    if (_mark == null) {
      _mark = current;
      _markSignature = signature;
      return;
    }
    if (signature == _markSignature) return;
    _push(_undo, _mark!);
    _redo.clear();
    _mark = current;
    _markSignature = signature;
  }

  /// Record the current state before something destructive, such as clearing
  /// every plot, so it can be undone.
  void saveForUndo() {
    _push(_undo, capture());
    _redo.clear();
    // The step is recorded, so the baseline goes: the next recorded point
    // re-establishes it rather than pushing the same state twice for one
    // action.
    _mark = null;
    _markSignature = null;
  }

  void _push(List<AppState> stack, AppState state) {
    stack.add(state);
    if (stack.length > _maxHistory) stack.removeAt(0);
  }

  /// Step back. [refresh] runs once the plots are restored and before the
  /// baseline is retaken, so whatever it recalculates is not taken for an
  /// edit.
  void undo({required void Function() refresh}) {
    if (!canUndo) return;
    _redo.add(capture());
    _restore(_undo.removeLast(), refresh);
  }

  /// Step forward again; see [undo].
  void redo({required void Function() refresh}) {
    if (!canRedo) return;
    _undo.add(capture());
    _restore(_redo.removeLast(), refresh);
  }

  void _restore(AppState state, void Function() refresh) {
    _restoring = true;
    try {
      apply(state);
      refresh();
    } finally {
      _restoring = false;
    }
    // The baseline is the state just moved to, so the next edit records a step
    // from here rather than from the one undone.
    markHistory();
  }

  /// Make the plots what [state] says.
  ///
  /// Plots are kept by position, with their ids and views, and only their rows
  /// are rebuilt: a plot's panel survives an undo, as it did when the plots
  /// were numbered. A plot that comes back from nothing — undoing a clear —
  /// takes the view it was left at from [state].
  void apply(AppState state) {
    final int n = state.cells.isEmpty ? 1 : state.cells.length;
    for (final Plot plot in plots) {
      _disposeRowsOf(plot);
    }
    while (plots.length > n) {
      plots.removeLast();
    }
    while (plots.length < n) {
      final int i = plots.length;
      final Plot plot = Plot._('p${_nextPlotId++}');
      final PlotViewState? view =
          i < state.views.length ? state.views[i] : null;
      if (view != null) plot.view = view;
      plots.add(plot);
    }
    for (int i = 0; i < n; i++) {
      final List<RowState> saved =
          state.cells.isEmpty ? const <RowState>[] : state.cells[i];
      final List<ExpressionRow> rows = plots[i].rows;
      // At least one row, as a plot always has somewhere to type.
      while (rows.length < (saved.isEmpty ? 1 : saved.length)) {
        rows.add(_newRow());
      }
      for (int r = 0; r < saved.length; r++) {
        rows[r].controller.setExpression(
          MathClipboard.deepCopyNodes(saved[r].nodes),
        );
        rows[r].visible = saved[r].visible;
      }
    }
    activeIndex = state.activeIndex.clamp(0, n - 1);
    // Clamped against the plot it lands in, which may hold fewer rows than
    // the one the caret was in when the state was recorded.
    activeRow = state.activeRow.clamp(0, plots[activeIndex].rows.length - 1);
  }
}
