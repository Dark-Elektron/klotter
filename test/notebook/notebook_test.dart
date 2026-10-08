import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/cell_persistence_service.dart';
import 'package:klotter/math_renderer/expression_row.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/notebook/notebook.dart';
import 'package:klotter/plotting/models/plot_view_state.dart';

/// The plots, held apart from the screen.
///
/// What the home page kept for each plot used to live in a dozen maps keyed
/// by the plot's position, renumbered in step whenever a plot came or went;
/// each one missed was a plot opening with another's panel or error marks.
/// These pin down the model that replaced them, without a widget in sight.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Notebook book;
  setUp(() => book = Notebook());
  tearDown(() => book.dispose());

  void type(ExpressionRow row, String text) =>
      row.controller.setExpression(<MathNode>[LiteralNode(text: text)]);

  String textOf(int plot) => <String>[
    for (final ExpressionRow r in book.rowsOf(plot))
      r.controller.getExpression(),
  ].join('/');

  test('starts with one plot holding one empty row', () {
    expect(book.count, 1);
    expect(book.rowsOf(0), hasLength(1));
    expect(book.hasContent(0), isFalse);
  });

  group('plots', () {
    test('a new plot goes after the open one, and opens', () {
      book.insertPlot();
      book.insertPlot(at: 0);
      expect(book.count, 3);
      expect(book.activeIndex, 0);
    });

    test('a plot keeps its id when others come and go before it', () {
      // The property the position-keyed maps lacked.
      final Plot first = book.plots.first;
      final Plot added = book.insertPlot();
      book.insertPlot(at: 0);
      expect(book.plots[2], same(added));
      book.removePlotAt(0);
      expect(book.plots, <Plot>[first, added]);
      expect(<String>{for (final Plot p in book.plots) p.id}, hasLength(2));
    });

    test('removing a plot carries the open one with it', () {
      book
        ..insertPlot()
        ..insertPlot(); // plots 0, 1, 2; the last is open
      book.removePlotAt(0);
      expect(book.activeIndex, 1, reason: 'the open plot moved down one');
      book.removePlotAt(1);
      expect(book.activeIndex, 0, reason: 'its neighbour opens');
    });

    test('the last plot stays', () {
      expect(book.removePlotAt(0), isFalse);
      expect(book.count, 1);
    });
  });

  group('rows', () {
    test('nothing is added below an empty row', () {
      expect(book.addRowBelowActive(), isNull);
      type(book.rowsOf(0).first, 'x');
      final ExpressionRow? added = book.addRowBelowActive();
      expect(added, isNotNull);
      expect(book.activeRow, 1);
      expect(book.activeRowOf(0), same(added));
    });

    test('a plot keeps its last row', () {
      expect(book.removeActiveRow(), isFalse);
      type(book.rowsOf(0).first, 'x');
      book.addRowBelowActive();
      expect(book.removeActiveRow(), isTrue);
      expect(book.rowsOf(0), hasLength(1));
      expect(book.activeRow, 0);
    });

    test('each plot keeps the row its caret was in', () {
      // One number for the whole notebook pointed past the last row of a plot
      // with fewer rows, so no caret was drawn there.
      type(book.rowsOf(0).first, 'x');
      book.addRowBelowActive();
      type(book.rowsOf(0)[1], 'y');
      book.addRowBelowActive();
      expect(book.activeRow, 2);
      book.insertPlot();
      expect(book.activeRow, 0, reason: 'a new plot starts on its first row');
      book.activeIndex = 0;
      expect(book.activeRow, 2, reason: 'back where it was left');
      book.activeIndex = 1;
      expect(book.activeRow, 0);
    });

    test('every row made is handed over to be wired up', () {
      final List<ExpressionRow> made = <ExpressionRow>[];
      final Notebook watched = Notebook(onRowCreated: made.add);
      addTearDown(watched.dispose);
      type(watched.rowsOf(0).first, 'x');
      watched.addRowBelowActive();
      watched.insertPlot();
      expect(made, hasLength(3));
    });
  });

  test('clearing keeps the first plot, with its id and its view', () {
    const PlotViewState moved = PlotViewState(xMin: -2, xMax: 3);
    final Plot first = book.plots.first..view = moved;
    type(first.rows.first, 'x^2');
    book.insertPlot();
    book.clear();
    expect(book.plots, <Plot>[first]);
    expect(first.view, moved);
    expect(book.hasContent(0), isFalse);
  });

  group('saving', () {
    CellData cellOf(
      ({
        List<List<List<MathNode>>> rows,
        List<List<bool>> hidden,
        List<Map<String, dynamic>?> views,
        int activeIndex,
      })
      saved,
      int i,
    ) => CellData(
      rowsJson: <String>[
        for (final List<MathNode> row in saved.rows[i])
          MathExpressionSerializer.serializeToJson(row),
      ],
      hidden: saved.hidden[i],
      plotView: saved.views[i],
    );

    test(
      'what is saved comes back: rows, hidden rows, views, the open plot',
      () {
        type(book.rowsOf(0).first, 'sin(x)');
        book.addRowBelowActive();
        type(book.rowsOf(0)[1], 'cos(x)');
        book.rowsOf(0)[1].visible = false;
        book.insertPlot();
        type(book.rowsOf(1).first, 'x^2+y^2');
        book.plots[1].view = const PlotViewState(show3D: true, rotationX: 1.2);

        final saved = book.toSaved();
        final Notebook back = Notebook();
        addTearDown(back.dispose);
        back.restore(<CellData>[
          for (int i = 0; i < saved.rows.length; i++) cellOf(saved, i),
        ], saved.activeIndex);

        expect(back.count, 2);
        expect(back.activeIndex, 1);
        expect(back.rowsOf(0).map((r) => r.visible), <bool>[true, false]);
        expect(back.plots[1].view.show3D, isTrue);
        expect(
          back.rowsOf(1).first.controller.getExpression(),
          book.rowsOf(1).first.controller.getExpression(),
        );
      },
    );

    test(
      'an empty plot is left out, and the open plot counted among the rest',
      () {
        type(book.rowsOf(0).first, 'x');
        book.insertPlot();
        book.plots[1].rows.clear(); // a plot caught with no rows at all
        book.insertPlot();
        type(book.rowsOf(2).first, 'y');
        final saved = book.toSaved();
        expect(saved.rows, hasLength(2));
        expect(saved.activeIndex, 1, reason: 'third plot, second written');
      },
    );
  });

  group('history', () {
    test('an edit is one step; reading the same again is none', () {
      book.markHistory();
      type(book.rowsOf(0).first, 'x');
      book.recordHistoryPoint();
      book.recordHistoryPoint();
      expect(book.undoDepth, 1);
    });

    test('undo brings the rows back and keeps the plots', () {
      final Plot plot = book.plots.first;
      book.markHistory();
      type(plot.rows.first, 'x^2');
      book.recordHistoryPoint();
      int refreshed = 0;
      book.undo(refresh: () => refreshed++);
      expect(textOf(0), isNot(contains('x')));
      expect(book.plots.first, same(plot), reason: 'its panel survives');
      expect(refreshed, 1);
      book.redo(refresh: () {});
      expect(textOf(0), contains('x'));
    });

    test('undoing a clear brings the plots back where they were left', () {
      type(book.rowsOf(0).first, 'x');
      book.insertPlot();
      type(book.rowsOf(1).first, 'y');
      const PlotViewState left = PlotViewState(xMin: -9, xMax: 9);
      book.plots[1].view = left;

      book.saveForUndo();
      book.clear();
      expect(book.count, 1);
      book.undo(refresh: () {});
      expect(book.count, 2);
      expect(book.plots[1].view, left);
      expect(textOf(1), contains('y'));
    });

    test('nothing restored by undo is recorded as an edit', () {
      book.markHistory();
      type(book.rowsOf(0).first, 'x');
      book.recordHistoryPoint();
      // The refresh is where the page recalculates, which records a point;
      // inside an undo that must not count.
      book.undo(refresh: book.recordHistoryPoint);
      expect(book.canRedo, isTrue);
      expect(book.undoDepth, 0);
    });
  });
}
