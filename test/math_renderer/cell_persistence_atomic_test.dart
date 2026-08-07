// Regression tests for Tier 3 fix 3.6: cells and the active index are now
// written as a single atomic blob, with backward-compatible reads of the old
// two-key format.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:klotter/math_renderer/cell_persistence_service.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saveAll round-trips cells and active index atomically', () async {
    final expressions = <List<MathNode>>[
      [LiteralNode(text: '1+2')],
      [LiteralNode(text: '3*4')],
      [LiteralNode(text: '5')],
    ];
    // The result display was removed, so a cell no longer stores an answer;
    // it stores where its plot was left instead.
    final views = <Map<String, dynamic>?>[
      const PlotViewState(xMin: 0, xMax: 10).toJson(),
      null,
      const PlotViewState(show3D: true, rotationX: 1.2).toJson(),
    ];

    await CellPersistence.saveAll(expressions, views, 2);

    final cells = await CellPersistence.loadCells();
    final activeIndex = await CellPersistence.loadActiveIndex();

    expect(cells, hasLength(3));
    expect(activeIndex, equals(2));

    final restored = PlotViewState.fromJson(cells[0].plotView!);
    expect(restored.xMin, equals(0));
    expect(restored.xMax, equals(10));

    // An untouched view is stored as nothing at all.
    expect(cells[1].plotView, isNull);

    expect(PlotViewState.fromJson(cells[2].plotView!).show3D, isTrue);
  });

  test('active index is stored inside the single blob (one key)', () async {
    await CellPersistence.saveAll([
      [LiteralNode(text: '9')],
    ], <Map<String, dynamic>?>[null], 0);

    final prefs = await SharedPreferences.getInstance();
    // The legacy separate key is not written by saveAll.
    expect(prefs.getInt('active_cell'), isNull);

    final raw = prefs.getString('calculator_cells');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!);
    expect(decoded, isA<Map>());
    expect((decoded as Map)['activeIndex'], equals(0));
  });

  test('reads the legacy bare-list format and separate active_cell key',
      () async {
    // Old format: a bare JSON list under calculator_cells + a separate int.
    final legacyCells = jsonEncode([
      {'expression': '', 'answer': '42'},
    ]);
    SharedPreferences.setMockInitialValues({
      'calculator_cells': legacyCells,
      'active_cell': 1,
    });

    final cells = await CellPersistence.loadCells();
    final activeIndex = await CellPersistence.loadActiveIndex();

    // A save written before plot views existed still loads: the old `answer`
    // field is ignored rather than treated as corruption, and the missing
    // view falls back to the default.
    expect(cells, hasLength(1));
    expect(cells.first.plotView, isNull);
    expect(activeIndex, equals(1)); // falls back to the legacy key
  });

  test('returns empty list and index 0 when nothing is stored', () async {
    expect(await CellPersistence.loadCells(), isEmpty);
    expect(await CellPersistence.loadActiveIndex(), equals(0));
  });
}
