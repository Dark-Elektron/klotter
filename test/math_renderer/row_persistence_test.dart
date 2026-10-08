import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/cell_persistence_service.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// Rows have to survive a restart, not just their curves.
///
/// A plot used to be one editor whose lines were `NewlineNode` sentinels, so
/// one string held the lot. Saving that joined string brings the curves back
/// but not the rows — and a row carries what a line never could: its own
/// visibility, and an identity that outlives another row being inserted above.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  List<MathNode> line(String text) => <MathNode>[LiteralNode(text: text)];

  test('rows come back as rows', () async {
    await CellPersistence.saveRows(
      <List<List<MathNode>>>[
        <List<MathNode>>[line('2x'), line('x^2'), line('x+1')],
      ],
      <List<bool>>[
        <bool>[false, true, false],
      ],
      <Map<String, dynamic>?>[null],
    );

    final List<CellData> cells = await CellPersistence.loadCells();
    expect(cells, hasLength(1));
    expect(cells.single.rowsJson, hasLength(3));
    expect(cells.single.hidden, <bool>[
      false,
      true,
      false,
    ], reason: 'which row was switched off was not saved');
  });

  test('the middle row keeps its own text', () async {
    await CellPersistence.saveRows(
      <List<List<MathNode>>>[
        <List<MathNode>>[line('2x'), line('x^2')],
      ],
      <List<bool>>[const <bool>[]],
      <Map<String, dynamic>?>[null],
    );
    final CellData cell = (await CellPersistence.loadCells()).single;
    final List<MathNode> second = MathExpressionSerializer.deserializeFromJson(
      cell.rowsJson[1],
    );
    expect((second.single as LiteralNode).text, 'x^2');
  });

  test('a save from before rows existed still loads', () async {
    // One expression with newlines in it, which is every save made until now.
    // The rows are absent, so the caller splits it — and each line becomes a
    // row rather than the whole thing staying one.
    final List<MathNode> joined = <MathNode>[
      LiteralNode(text: '2x'),
      NewlineNode(),
      LiteralNode(text: 'x^2'),
    ];
    SharedPreferences.setMockInitialValues(<String, Object>{
      'calculator_cells': jsonEncode(<Map<String, dynamic>>[
        {'expression': MathExpressionSerializer.serializeToJson(joined)},
      ]),
    });

    final CellData cell = (await CellPersistence.loadCells()).single;
    expect(cell.rowsJson, isEmpty, reason: 'an old save has no row list');
    expect(
      MathExpressionSerializer.deserializeFromJson(
        cell.expressionJson,
      ).whereType<NewlineNode>(),
      hasLength(1),
      reason: 'the joined expression is what an old save carries',
    );
  });

  test('a save holds its version and the rows, and no joined copy', () async {
    // The rows used to be written joined as well, so an older build could
    // still find the maths after a downgrade. Android does not install an
    // older build over a newer one without uninstalling, which takes the data
    // with it, so the copy protected nothing and doubled every write.
    await CellPersistence.saveRows(
      <List<List<MathNode>>>[
        <List<MathNode>>[line('2x'), line('x^2')],
      ],
      <List<bool>>[const <bool>[]],
      <Map<String, dynamic>?>[null],
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> blob =
        jsonDecode(prefs.getString('calculator_cells')!)
            as Map<String, dynamic>;
    expect(blob['version'], CellPersistence.version);
    final Map<String, dynamic> cell =
        (blob['cells'] as List<dynamic>).single as Map<String, dynamic>;
    expect(cell.containsKey('expression'), isFalse);
    expect(cell['rows'], hasLength(2));

    final CellData loaded = (await CellPersistence.loadCells()).single;
    expect(
      MathExpressionSerializer.deserializeFromJson(
        loaded.rowsJson.last,
      ).whereType<LiteralNode>().single.text,
      'x^2',
    );
  });

  test('nothing hidden writes no hidden list', () async {
    // The common case should not grow the saved blob.
    await CellPersistence.saveRows(
      <List<List<MathNode>>>[
        <List<MathNode>>[line('2x')],
      ],
      <List<bool>>[
        <bool>[false],
      ],
      <Map<String, dynamic>?>[null],
    );
    final CellData cell = (await CellPersistence.loadCells()).single;
    expect(cell.hidden, isEmpty);
  });
}
