import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:klotter/main.dart';
import 'package:klotter/math_engine/math_expression_serializer.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/math_speech.dart';
import 'package:klotter/settings/settings_provider.dart';

List<MathNode> lit(String t) => <MathNode>[LiteralNode(text: t)];

MathNode sq(String base) => ExponentNode(base: lit(base), power: lit('2'));

String say(List<MathNode> nodes) => MathSpeech.describe(nodes);

/// What a screen reader says for an expression: words, not glyphs.
void main() {
  group('an expression in words', () {
    test('an equation', () {
      expect(
        say(<MathNode>[
          LiteralNode(),
          sq('x'),
          LiteralNode(text: '+'),
          sq('y'),
          LiteralNode(text: '=1'),
        ]),
        'x squared plus y squared equals 1',
      );
    });

    test('letters typed together are said one at a time', () {
      expect(say(lit('2kx')), '2 k x');
      expect(say(lit('k=2.5')), 'k equals 2.5');
      expect(say(lit('−y')), 'minus y');
    });

    test('nothing typed', () {
      expect(say(<MathNode>[LiteralNode()]), 'empty');
    });

    test('a function, with its brackets when it holds more than a word', () {
      expect(
        say(<MathNode>[TrigNode(function: 'sin', argument: lit('x'))]),
        'sine of x',
      );
      expect(
        say(<MathNode>[TrigNode(function: 'sin', argument: lit('x+1'))]),
        'sine of open bracket x plus 1 close bracket',
      );
      expect(
        say(<MathNode>[TrigNode(function: 'atanh', argument: lit('x'))]),
        'inverse hyperbolic tangent of x',
      );
    });

    test('a fraction is closed when its parts are more than a word', () {
      expect(
        say(<MathNode>[FractionNode(num: lit('1'), den: lit('x'))]),
        '1 over x',
      );
      expect(
        say(<MathNode>[FractionNode(num: lit('x+1'), den: lit('x−1'))]),
        'fraction x plus 1, over x minus 1, end fraction',
      );
    });

    test('powers', () {
      expect(say(<MathNode>[sq('x')]), 'x squared');
      expect(
        say(<MathNode>[ExponentNode(base: lit('x'), power: lit('3'))]),
        'x cubed',
      );
      expect(
        say(<MathNode>[ExponentNode(base: lit('e'), power: lit('kx'))]),
        'e to the power k x, end power',
      );
    });

    test('roots and logs', () {
      expect(
        say(<MathNode>[RootNode(radicand: lit('x'), isSquareRoot: true)]),
        'square root of x',
      );
      expect(
        say(<MathNode>[RootNode(index: lit('3'), radicand: lit('x+1'))]),
        'cube root of x plus 1, end root',
      );
      expect(
        say(<MathNode>[LogNode(argument: lit('x'), isNaturalLog: true)]),
        'natural log of x',
      );
      expect(
        say(<MathNode>[LogNode(base: lit('2'), argument: lit('x'))]),
        'log base 2 of x',
      );
    });

    test('polar symbols by name', () {
      expect(
        say(<MathNode>[
          LiteralNode(text: 'r=1+'),
          TrigNode(function: 'cos', argument: lit('θ')),
          LiteralNode(),
        ]),
        'r equals 1 plus cosine of theta',
      );
    });

    test('unit vectors and the complex variable', () {
      expect(
        say(<MathNode>[
          LiteralNode(text: '−y'),
          UnitVectorNode('x'),
          LiteralNode(text: '+x'),
          UnitVectorNode('y'),
          LiteralNode(),
        ]),
        'minus y x hat plus x y hat',
      );
      expect(
        say(<MathNode>[
          ExponentNode(
            base: <MathNode>[
              LiteralNode(),
              ComplexVariableNode(),
              LiteralNode(),
            ],
            power: lit('2'),
          ),
        ]),
        'complex z squared',
      );
    });

    test('sums and integrals say where they end', () {
      expect(
        say(<MathNode>[
          SummationNode(
            variable: lit('n'),
            lower: lit('1'),
            upper: lit('3'),
            body: lit('nx'),
          ),
        ]),
        'sum from n equals 1 to 3 of n x, end sum',
      );
      expect(
        say(<MathNode>[
          IntegralNode(
            lower: lit('0'),
            upper: lit('1'),
            body: <MathNode>[LiteralNode(), sq('x'), LiteralNode()],
          ),
        ]),
        'integral from 0 to 1 of x squared, d x',
      );
      expect(
        say(<MathNode>[
          DerivativeNode(
            at: <MathNode>[LiteralNode()],
            body: lit('kx'),
            isDefinite: false,
          ),
        ]),
        'derivative with respect to x of k x, end derivative',
      );
    });
  });

  testWidgets('each row is one node a screen reader reads and can choose', (
    tester,
  ) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    String row(String t) => MathExpressionSerializer.serializeToJson(<MathNode>[
      LiteralNode(text: t),
    ]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'walkthrough_completed_v2': true,
      'calculator_cells': jsonEncode(<String, dynamic>{
        'version': 2,
        'cells': <Map<String, dynamic>>[
          <String, dynamic>{
            'rows': <String>[row('k=2'), row('kx')],
          },
        ],
        'activeIndex': 0,
      }),
    });
    final SettingsProvider settings = await SettingsProvider.create();
    addTearDown(settings.dispose);
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final GlobalKey<HomePageState> key = GlobalKey<HomePageState>();
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(home: HomePage(key: key)),
      ),
    );
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final HomePageState state = key.currentState!;

    final Finder second = find.byWidgetPredicate(
      (Widget w) =>
          w is MathEditorInline &&
          w.controller == state.rowsOf(0)[1].controller,
    );
    final SemanticsNode node = tester.getSemantics(second);
    expect(node.label, 'k x');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    expect(state.activeRow, 0);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pump();
    expect(state.activeRow, 1, reason: 'a double tap chooses the row');
    semantics.dispose();
  });
}
