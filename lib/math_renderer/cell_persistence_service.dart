// cell_persistence.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../math_engine/math_expression_serializer.dart';
import 'renderer.dart';

class CellData {
  /// Each expression row of the plot, serialized.
  ///
  /// A plot used to be one editor whose lines were `NewlineNode` sentinels, so
  /// one string held the lot. Rows own their editors now, and a row carries
  /// things a line never could — its own visibility, and an identity that
  /// survives another row being inserted above it. Saving the joined string
  /// would bring the curves back but not the rows.
  final List<String> rowsJson;

  /// Which rows are switched off, aligned with [rowsJson].
  final List<bool> hidden;

  final String expressionJson;

  /// Where the cell's plot was last left. Stored beside the expression
  /// because it is part of what the user built: the expression says what to
  /// draw, this says where they were looking.
  ///
  /// Null when the view was never moved, which keeps the stored payload to
  /// the expression alone for the common case.
  final Map<String, dynamic>? plotView;

  CellData({
    required this.expressionJson,
    this.rowsJson = const <String>[],
    this.hidden = const <bool>[],
    this.plotView,
  });

  Map<String, dynamic> toJson() => {
    // `expression` is still written so a downgrade keeps the maths, even
    // though it loses the row boundaries.
    'expression': expressionJson,
    if (rowsJson.isNotEmpty) 'rows': rowsJson,
    if (hidden.contains(true)) 'hidden': hidden,
    if (plotView != null) 'plotView': plotView,
  };

  /// Older saves carry an `answer` field and no `plotView`; both are tolerated
  /// so an upgrade does not wipe the user's cells.
  factory CellData.fromJson(Map<String, dynamic> json) => CellData(
    expressionJson: json['expression'] as String? ?? '',
    // Absent on anything saved before rows existed; the caller then splits the
    // single expression on its newlines, which is the same division the plot
    // was already making.
    rowsJson: switch (json['rows']) {
      final List<dynamic> r => r.whereType<String>().toList(),
      _ => const <String>[],
    },
    hidden: switch (json['hidden']) {
      final List<dynamic> h => h.map((dynamic v) => v == true).toList(),
      _ => const <bool>[],
    },
    plotView: switch (json['plotView']) {
      final Map<String, dynamic> m => m,
      _ => null,
    },
  );
}

class CellPersistence {
  static const String _key = 'calculator_cells';
  static const String _activeKey = 'active_cell';

  /// Save every plot's rows.
  static Future<void> saveRows(
    List<List<List<MathNode>>> rowsPerPlot,
    List<List<bool>> hiddenPerPlot,
    List<Map<String, dynamic>?> plotViews,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> cells = <Map<String, dynamic>>[];
    for (int i = 0; i < rowsPerPlot.length; i++) {
      final List<List<MathNode>> rows = rowsPerPlot[i];
      // The joined form too, so an older build still finds its curves.
      final List<MathNode> joined = <MathNode>[];
      for (final List<MathNode> row in rows) {
        if (joined.isNotEmpty) joined.add(NewlineNode());
        joined.addAll(row);
      }
      cells.add(
        CellData(
          expressionJson: MathExpressionSerializer.serializeToJson(joined),
          rowsJson: <String>[
            for (final List<MathNode> row in rows)
              MathExpressionSerializer.serializeToJson(row),
          ],
          hidden: i < hiddenPerPlot.length ? hiddenPerPlot[i] : const <bool>[],
          plotView: i < plotViews.length ? plotViews[i] : null,
        ).toJson(),
      );
    }
    await prefs.setString(_key, jsonEncode(cells));
  }

  static List<Map<String, dynamic>> _buildCellMaps(
    List<List<MathNode>> expressions,
    List<Map<String, dynamic>?> plotViews,
  ) {
    List<Map<String, dynamic>> cells = [];
    for (int i = 0; i < expressions.length; i++) {
      cells.add(
        CellData(
          expressionJson: MathExpressionSerializer.serializeToJson(
            expressions[i],
          ),
          plotView: i < plotViews.length ? plotViews[i] : null,
        ).toJson(),
      );
    }
    return cells;
  }

  /// Save all cells and the active index as a single atomic blob, so a crash
  /// or process kill can never leave the cells and the active index out of
  /// sync (they were previously two separate writes).
  static Future<void> saveAll(
    List<List<MathNode>> expressions,
    List<Map<String, dynamic>?> plotViews,
    int activeIndex,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final blob = {
      'cells': _buildCellMaps(expressions, plotViews),
      'activeIndex': activeIndex,
    };
    await prefs.setString(_key, jsonEncode(blob));
  }

  /// Save all cells (legacy list-only form, kept for callers that don't track
  /// the active index).
  static Future<void> saveCells(
    List<List<MathNode>> expressions,
    List<Map<String, dynamic>?> plotViews,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(_buildCellMaps(expressions, plotViews)),
    );
  }

  /// Decode the stored blob into a list of raw cell maps, handling both the
  /// new `{cells, activeIndex}` object form and the legacy bare-list form.
  static List<dynamic>? _decodeCellList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return null;
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        return decoded['cells'] as List<dynamic>?;
      }
      if (decoded is List) return decoded;
    } catch (_) {}
    return null;
  }

  /// Load all cells
  static Future<List<CellData>> loadCells({SharedPreferences? prefs}) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();
    final list = _decodeCellList(sharedPrefs.getString(_key));
    if (list == null) return [];
    try {
      return list
          .map((json) => CellData.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Save active cell index (legacy separate key; [saveAll] is preferred).
  static Future<void> saveActiveIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_activeKey, index);
  }

  /// Load active cell index. Prefers the value embedded in the cells blob and
  /// falls back to the legacy separate key.
  static Future<int> loadActiveIndex({SharedPreferences? prefs}) async {
    final sharedPrefs = prefs ?? await SharedPreferences.getInstance();
    try {
      final decoded = jsonDecode(sharedPrefs.getString(_key) ?? '');
      if (decoded is Map<String, dynamic> && decoded['activeIndex'] is int) {
        return decoded['activeIndex'] as int;
      }
    } catch (_) {}
    return sharedPrefs.getInt(_activeKey) ?? 0;
  }

  /// Clear all saved data
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_activeKey);
  }
}
