import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/widgets/inline_plot_panel.dart';
import 'package:klotter/settings/settings_provider.dart';

List<MathNode> lit(String t) => <MathNode>[LiteralNode(text: t)];

/// A plot's rows read the way the panel reads them: the values first, then
/// every other row compiled with them. A row giving a value comes back null,
/// since it is not drawn.
({PlotDefinitions definitions, List<PlotExpression?> rows}) plot(
  List<List<MathNode>> lines,
) {
  final PlotDefinitions definitions = PlotDefinitions.read(lines);
  return (
    definitions: definitions,
    rows: <PlotExpression?>[
      for (int r = 0; r < lines.length; r++)
        definitions.rows.containsKey(r)
            ? null
            : PlotExpression.compile(lines[r], definitions: definitions),
    ],
  );
}

/// A row `k = 2` gives k the value 2 in every other row of its plot.
void main() {
  group('which rows give a value', () {
    test('a letter from the key, =, and a value', () {
      expect(PlotDefinitions.nameDefinedBy(lit('k=2')), 'k');
      expect(PlotDefinitions.nameDefinedBy(lit('a = 2x')), 'a');
      // Waiting for its value, which is not a relation missing a side.
      expect(PlotDefinitions.nameDefinedBy(lit('n=')), 'n');
    });

    test('anything else is a curve', () {
      // A coordinate, not a value.
      expect(PlotDefinitions.nameDefinedBy(lit('y=2')), isNull);
      expect(PlotDefinitions.nameDefinedBy(lit('k≥2')), isNull);
      expect(PlotDefinitions.nameDefinedBy(lit('2=k')), isNull);
      expect(PlotDefinitions.nameDefinedBy(lit('kk=2')), isNull);
      expect(PlotDefinitions.nameDefinedBy(lit('k=1=2')), isNull);
      expect(PlotDefinitions.nameDefinedBy(lit('kx')), isNull);
    });
  });

  group('a row gives a letter its value', () {
    test('k = 2 makes kx the line 2x', () {
      final r = plot(<List<MathNode>>[lit('k=2'), lit('kx')]);
      expect(r.definitions.rows, <int, String>{0: 'k'});
      expect(r.definitions.errors, isEmpty);
      expect(r.rows[1]!.error, isNull);
      expect(r.rows[1]!.evaluate(3), 6);
    });

    test('a value can use another, whichever row comes first', () {
      final r = plot(<List<MathNode>>[lit('b=2a'), lit('a=3'), lit('bx')]);
      expect(r.definitions.errors, isEmpty);
      expect(r.rows[2]!.evaluate(1), 6);
    });

    test('a constant is a value', () {
      final r = plot(<List<MathNode>>[lit('a=π'), lit('ax')]);
      expect(r.rows[1]!.evaluate(1), closeTo(math.pi, 1e-12));
    });

    test('every letter of the key can be given one', () {
      for (final String name in PlotDefinitions.names) {
        final r = plot(<List<MathNode>>[lit('$name=5'), lit('${name}x')]);
        expect(r.rows[1]!.evaluate(2), 10, reason: name);
      }
    });

    test('a field reads the values too', () {
      final PlotDefinitions d = PlotDefinitions.read(<List<MathNode>>[
        lit('k=2'),
      ]);
      final VectorFieldParser? f = VectorFieldParser.fromNodes(<MathNode>[
        LiteralNode(text: 'k'),
        UnitVectorNode('x'),
      ], definitions: d);
      expect(f, isNotNull);
      expect(f!.error, isNull);
      expect(f.xComponent!.evaluate(0), 2);
    });
  });

  group('a value that cannot be read says why, on its own row', () {
    Map<int, String> errors(List<String> rows) =>
        PlotDefinitions.read(<List<MathNode>>[
          for (final r in rows) lit(r),
        ]).errors;

    test('one that depends on itself', () {
      expect(errors(<String>['k=k+1'])[0], contains('depends on itself'));
      final Map<int, String> both = errors(<String>['a=b', 'b=a']);
      expect(both.keys, unorderedEquals(<int>[0, 1]));
    });

    test('a letter given two values keeps the first', () {
      final r = plot(<List<MathNode>>[lit('k=1'), lit('k=2'), lit('kx')]);
      expect(r.definitions.errors.keys, <int>[1]);
      expect(r.definitions.errors[1], contains('row 1'));
      expect(r.rows[2]!.evaluate(5), 5);
    });

    test('one that depends on where it is', () {
      expect(errors(<String>['k=2x'])[0], contains('cannot depend on x'));
    });

    test('one that uses a letter with no value', () {
      expect(errors(<String>['k=2a'])[0], contains('a, which has no value'));
    });

    test('one that is not a real number', () {
      expect(errors(<String>['k=2i'])[0], contains('real number'));
      expect(errors(<String>['k=1/0'])[0], isNotNull);
    });

    test('one with nothing after the =', () {
      expect(errors(<String>['k='])[0], contains('k = 1'));
    });
  });

  group('a letter with no value', () {
    test('says where the value goes', () {
      final r = plot(<List<MathNode>>[lit('kx')]);
      expect(r.rows[0]!.isValid, isFalse);
      expect(r.rows[0]!.error, contains('k has no value'));
      expect(r.rows[0]!.error, contains('k = 1'));
    });

    test('names the row that is meant to give it one, when there is one', () {
      final r = plot(<List<MathNode>>[lit('k=x'), lit('kx')]);
      expect(r.rows[1]!.error, contains('until the row giving it is fixed'));
    });

    test('a letter that is not from the key is still unknown', () {
      final r = plot(<List<MathNode>>[lit('kq')]);
      expect(r.rows[0]!.error, contains('unknown variable k, q'));
    });
  });

  group('letters are read as letters', () {
    test('with the letters bound, a word they spell is their product', () {
      // m·a·x, not a function called max; e·x·p, not exp.
      final r = plot(<List<MathNode>>[
        lit('m=2'),
        lit('a=3'),
        lit('p=5'),
        lit('max'),
        lit('exp'),
      ]);
      expect(r.rows[3]!.evaluate(1), 6);
      expect(r.rows[4]!.evaluate(1), closeTo(5 * math.e, 1e-12));
    });

    test('p and then i is p times i, not π', () {
      final Expr two = MathNodeToExpr.convert(lit('2'));
      final Expr pi = MathNodeToExpr.convert(
        lit('pi'),
        varBindings: <String, Expr>{'p': two},
      );
      expect(pi, isNot(isA<ConstExpr>()));
      // 2 times i, where i inside a word is the name a complex line binds to
      // the unit (see PlotExpression.compile).
      expect(pi.freeVariables, <String>{'i'});
      // And a plot reads it as complex, which it is.
      expect(PlotExpression.usesImaginaryUnit(lit('pi')), isTrue);
    });

    test('without bindings the engine still reads pi as π', () {
      expect(MathNodeToExpr.convert(lit('pi')), isA<ConstExpr>());
    });

    test('e inside a word is Euler\'s number', () {
      final PlotExpression xe = PlotExpression.compile(lit('xe'));
      expect(xe.error, isNull);
      expect(xe.evaluate(2), closeTo(2 * math.e, 1e-12));
    });
  });

  group('an operator\'s own letter is its own', () {
    test('a sum over n is not changed by n having a value', () {
      final r = plot(<List<MathNode>>[
        lit('n=10'),
        <MathNode>[
          SummationNode(
            variable: lit('n'),
            lower: lit('1'),
            upper: lit('3'),
            body: lit('nx'),
          ),
        ],
      ]);
      expect(r.rows[1]!.evaluate(1), 6, reason: '1x + 2x + 3x, not 3 × 10x');
    });

    test('d/dk differentiates by k even when k has a value', () {
      final r = plot(<List<MathNode>>[
        lit('k=2'),
        <MathNode>[
          DerivativeNode(
            variable: lit('k'),
            at: <MathNode>[LiteralNode()],
            body: lit('kx'),
          ),
        ],
      ]);
      expect(r.rows[1]!.error, isNull);
      expect(r.rows[1]!.evaluate(3), 3, reason: 'd/dk of kx is x');
    });
  });

  group('a compiled row is keyed by the values it reads', () {
    final PlotDefinitions d = PlotDefinitions.read(<List<MathNode>>[
      lit('k=2'),
      lit('a=x'),
    ]);
    String key(List<MathNode> row) =>
        d.valuesReadBy(MathExpressionSerializer.serializeToJson(row));

    test('the values it uses, and only those', () {
      expect(key(lit('kx')), 'k=2.0');
      expect(key(lit('x')), isEmpty);
    });

    test('however deep in the row the letter is', () {
      expect(
        key(<MathNode>[
          SummationNode(
            variable: lit('n'),
            lower: lit('1'),
            upper: lit('3'),
            body: <MathNode>[FractionNode(num: lit('k'), den: lit('n'))],
          ),
        ]),
        'k=2.0',
      );
    });

    test('a letter whose row cannot be read yet is marked as such', () {
      expect(key(lit('ax')), 'a=?');
    });

    test('nothing at all when no row gives a value', () {
      expect(
        PlotDefinitions.none.valuesReadBy(
          MathExpressionSerializer.serializeToJson(lit('kx')),
        ),
        isEmpty,
      );
    });
  });

  group('in the plot', () {
    late SettingsProvider settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'walkthrough_completed_v2': true,
      });
      settings = await SettingsProvider.create();
    });
    tearDown(() => settings.dispose());

    Future<Map<int, String>> errorsFor(
      WidgetTester tester,
      List<String> rows,
    ) async {
      Map<int, String> seen = const <int, String>{};
      await tester.pumpWidget(
        ChangeNotifierProvider<SettingsProvider>.value(
          value: settings,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 300,
                width: 360,
                child: InlinePlotPanel(
                  expression: rows.join('\n'),
                  nodes: <MathNode>[
                    for (int i = 0; i < rows.length; i++) ...<MathNode>[
                      if (i > 0) NewlineNode(),
                      LiteralNode(text: rows[i]),
                    ],
                  ],
                  onRowErrors: (Map<int, String> byRow) => seen = byRow,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return seen;
    }

    testWidgets('a value and a curve using it mark nothing', (tester) async {
      expect(await errorsFor(tester, <String>['k=2', 'kx']), isEmpty);
    });

    testWidgets('a curve with no value for its letter is marked', (
      tester,
    ) async {
      final Map<int, String> errors = await errorsFor(tester, <String>['kx']);
      expect(errors.keys, <int>[0]);
      expect(errors[0], contains('Add a row such as k = 1'));
    });

    testWidgets('a value that cannot be read marks its own row', (
      tester,
    ) async {
      final Map<int, String> errors = await errorsFor(tester, <String>[
        'k=x',
        'kx',
      ]);
      expect(errors.keys, unorderedEquals(<int>[0, 1]));
      expect(errors[0], contains('cannot depend on x'));
    });

    testWidgets('a plot of nothing but values is bare axes', (tester) async {
      expect(await errorsFor(tester, <String>['k=2', 'a=3']), isEmpty);
    });
  });
}
