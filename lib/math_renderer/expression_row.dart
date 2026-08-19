import 'package:flutter/widgets.dart';

import 'math_editor_controller.dart';
import 'math_editor_widgets.dart';

/// One expression inside a plot.
///
/// A plot used to hold a single editor whose lines were separated by
/// `NewlineNode` sentinels, and every consumer re-derived those lines by
/// scanning for them. A line could therefore carry nothing of its own — no
/// colour, no visibility, no identity — which is what stopped it having a
/// swatch or an eye toggle beside it.
///
/// A row owns its editor instead. The plot owns an ordered list of rows, and
/// the swipe strip still moves between plots: this is the level *below* the
/// page, not a replacement for it.
class ExpressionRow {
  ExpressionRow({required this.id})
    : controller = MathEditorController(),
      editorKey = GlobalKey<MathEditorInlineState>(),
      scroll = ScrollController();

  /// Stable across edits, reorders and reloads.
  ///
  /// Position cannot do this job: inserting a row above shifts every index
  /// below it, so anything remembered by position — which row is hidden, which
  /// colour it wears — would silently move to a different expression. The id is
  /// what gets persisted.
  final String id;

  final MathEditorController controller;
  final GlobalKey<MathEditorInlineState> editorKey;

  /// Horizontal scroll, so a long expression can run past the panel edge.
  final ScrollController scroll;

  /// Whether this row's curve is drawn.
  ///
  /// A hidden row still compiles and still holds its place in the colour
  /// order — hiding one must not recolour the others.
  bool visible = true;

  /// Identity for widget keys, so Flutter reuses element state when rows are
  /// renumbered by an insert or a delete.
  int get token => identityHashCode(controller);

  void dispose() {
    controller.dispose();
    scroll.dispose();
  }
}

/// Ids that do not collide across a session.
///
/// Monotonic rather than random: a row's id shows up in saved data, and a
/// readable sequence is easier to reason about when reading a stored blob.
class ExpressionRowIds {
  static int _next = 0;
  static String take() => 'r${_next++}';

  /// Ensure freshly minted ids cannot collide with ones just loaded.
  static void reserveAbove(Iterable<String> existing) {
    for (final String id in existing) {
      if (!id.startsWith('r')) continue;
      final int? n = int.tryParse(id.substring(1));
      if (n != null && n >= _next) _next = n + 1;
    }
  }
}
