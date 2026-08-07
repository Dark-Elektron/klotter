// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_result_display.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/utils/constants.dart';

void main() {
  Finder _fractionBarFinder() {
    return find.byWidgetPredicate((widget) {
      if (widget is! Container) return false;
      final margin = widget.margin;
      final constraints = widget.constraints;
      final bool isThinBar =
          constraints != null &&
          constraints.minHeight == constraints.maxHeight &&
          constraints.maxHeight <= 3.0;
      return widget.color == Colors.white &&
          isThinBar &&
          margin is EdgeInsets &&
          margin.vertical > 0;
    });
  }

  Offset _widestFractionBarCenter(WidgetTester tester) {
    final barFinder = _fractionBarFinder();
    final int count = barFinder.evaluate().length;
    expect(count, greaterThan(0));

    double maxWidth = -1;
    Offset? center;

    for (int i = 0; i < count; i++) {
      final currentFinder = barFinder.at(i);
      final width = tester.getSize(currentFinder).width;
      if (width > maxWidth) {
        maxWidth = width;
        center = tester.getCenter(currentFinder);
      }
    }

    return center!;
  }

  group('Vertical Alignment Tests', () {
    testWidgets('PermutationNode is centered in MathResultDisplay', (
      tester,
    ) async {
      final node = PermutationNode(
        n: [LiteralNode(text: 'n')],
        r: [LiteralNode(text: 'r')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathResultDisplay(
                nodes: [LiteralNode(text: '1'), LiteralNode(text: '+'), node],
              ),
            ),
          ),
        ),
      );

      final pFinder = find.text('P');
      expect(pFinder, findsOneWidget);

      final oneFinder = find.text('1');
      expect(oneFinder, findsOneWidget);

      final pCenter = tester.getCenter(pFinder);
      final oneCenter = tester.getCenter(oneFinder);

      expect(pCenter.dy, moreOrLessEquals(oneCenter.dy, epsilon: 1.0));
    });

    testWidgets('CombinationNode is centered in MathResultDisplay', (
      tester,
    ) async {
      final node = CombinationNode(
        n: [LiteralNode(text: 'n')],
        r: [LiteralNode(text: 'r')],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathResultDisplay(
                nodes: [LiteralNode(text: '1'), LiteralNode(text: '+'), node],
              ),
            ),
          ),
        ),
      );

      final cFinder = find.text('C');
      expect(cFinder, findsOneWidget);

      final oneFinder = find.text('1');
      expect(oneFinder, findsOneWidget);

      final cCenter = tester.getCenter(cFinder);
      final oneCenter = tester.getCenter(oneFinder);

      expect(cCenter.dy, moreOrLessEquals(oneCenter.dy, epsilon: 1.0));
    });

    testWidgets('AnsNode is centered in MathResultDisplay', (tester) async {
      final node = AnsNode(index: [LiteralNode(text: '0')]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathResultDisplay(
                nodes: [LiteralNode(text: '1'), LiteralNode(text: '+'), node],
              ),
            ),
          ),
        ),
      );

      final ansFinder = find.text('ans');
      expect(ansFinder, findsOneWidget);

      final oneFinder = find.text('1');
      expect(oneFinder, findsOneWidget);

      final ansCenter = tester.getCenter(ansFinder);
      final oneCenter = tester.getCenter(oneFinder);

      expect(ansCenter.dy, moreOrLessEquals(oneCenter.dy, epsilon: 1.0));
    });

    testWidgets('PermutationNode is centered in MathRenderer (Editor)', (
      tester,
    ) async {
      final node = PermutationNode(
        n: [LiteralNode(text: 'n')],
        r: [LiteralNode(text: 'r')],
      );
      final controller = MathEditorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathRenderer(
                expression: [
                  LiteralNode(text: '1'),
                  LiteralNode(text: '+'),
                  node,
                ],
                rootKey: GlobalKey(),
                controller: controller,
                structureVersion: 0,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );

      final pFinder = find.text('P');
      expect(pFinder, findsOneWidget);

      final oneFinder = find.text('1');
      expect(oneFinder, findsOneWidget);

      final pCenter = tester.getCenter(pFinder);
      final oneCenter = tester.getCenter(oneFinder);

      expect(pCenter.dy, moreOrLessEquals(oneCenter.dy, epsilon: 1.0));
    });

    testWidgets('TrigNode label is centered in MathRenderer', (tester) async {
      final node = TrigNode(
        function: 'sin',
        argument: [
          FractionNode(
            num: [LiteralNode(text: '1')],
            den: [LiteralNode(text: '2')],
          ),
        ],
      );
      final controller = MathEditorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathRenderer(
                expression: [node],
                rootKey: GlobalKey(),
                controller: controller,
                structureVersion: 0,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );

      final labelFinder = find.text('sin');
      expect(labelFinder, findsOneWidget);

      final parenFinder = find.byType(ScalableParenthesis);
      expect(parenFinder, findsNWidgets(2));

      final labelCenter = tester.getCenter(labelFinder);
      final parenCenter = tester.getCenter(parenFinder.first);

      expect(labelCenter.dy, moreOrLessEquals(parenCenter.dy, epsilon: 1.0));
    });

    testWidgets('Arg label is centered in MathRenderer', (tester) async {
      final node = TrigNode(
        function: 'arg',
        argument: [
          FractionNode(
            num: [LiteralNode(text: '1')],
            den: [LiteralNode(text: '2')],
          ),
        ],
      );
      final controller = MathEditorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathRenderer(
                expression: [node],
                rootKey: GlobalKey(),
                controller: controller,
                structureVersion: 0,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );

      final labelFinder = find.text('arg');
      expect(labelFinder, findsOneWidget);

      final parenFinder = find.byType(ScalableParenthesis);
      expect(parenFinder, findsNWidgets(2));

      final labelCenter = tester.getCenter(labelFinder);
      final parenCenter = tester.getCenter(parenFinder.first);

      expect(labelCenter.dy, moreOrLessEquals(parenCenter.dy, epsilon: 1.0));
    });

    testWidgets('LogNode label is centered in MathRenderer', (tester) async {
      final node = LogNode(
        isNaturalLog: true,
        argument: [
          FractionNode(
            num: [LiteralNode(text: '1')],
            den: [LiteralNode(text: '2')],
          ),
        ],
      );
      final controller = MathEditorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathRenderer(
                expression: [node],
                rootKey: GlobalKey(),
                controller: controller,
                structureVersion: 0,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );

      final labelFinder = find.text('ln');
      expect(labelFinder, findsOneWidget);

      final parenFinder = find.byType(ScalableParenthesis);
      expect(parenFinder, findsNWidgets(2));

      final labelCenter = tester.getCenter(labelFinder);
      final parenCenter = tester.getCenter(parenFinder.first);

      expect(labelCenter.dy, moreOrLessEquals(parenCenter.dy, epsilon: 1.0));
    });

    testWidgets('Abs bars expand with fraction in MathRenderer', (
      tester,
    ) async {
      final node = TrigNode(
        function: 'abs',
        argument: [
          FractionNode(
            num: [LiteralNode(text: '1')],
            den: [LiteralNode(text: '2')],
          ),
        ],
      );
      final controller = MathEditorController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MathRenderer(
                expression: [node],
                rootKey: GlobalKey(),
                controller: controller,
                structureVersion: 0,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ),
        ),
      );

      final barFinder = find.byType(ScalableAbsBar);
      expect(barFinder, findsNWidgets(2));

      final barSize = tester.getSize(barFinder.first);
      expect(barSize.height, greaterThan(FONTSIZE * 1.4));
    });

    testWidgets(
      'TrigNode label follows top-level fraction bar in layered fractions',
      (tester) async {
        final node = TrigNode(
          function: 'sin',
          argument: [
            FractionNode(
              num: [LiteralNode(text: '123456')],
              den: [
                FractionNode(
                  num: [LiteralNode(text: '1')],
                  den: [
                    FractionNode(
                      num: [LiteralNode(text: '2')],
                      den: [LiteralNode(text: '3')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final controller = MathEditorController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MathRenderer(
                  expression: [node],
                  rootKey: GlobalKey(),
                  controller: controller,
                  structureVersion: 0,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        );

        final labelFinder = find.text('sin');
        expect(labelFinder, findsOneWidget);

        final labelCenter = tester.getCenter(labelFinder);
        final mainFractionBarCenter = _widestFractionBarCenter(tester);

        expect(
          labelCenter.dy,
          moreOrLessEquals(mainFractionBarCenter.dy, epsilon: 1.0),
        );
      },
    );

    testWidgets(
      'LogNode label follows top-level fraction bar in layered fractions',
      (tester) async {
        final node = LogNode(
          base: [LiteralNode(text: '10')],
          argument: [
            FractionNode(
              num: [LiteralNode(text: '123456')],
              den: [
                FractionNode(
                  num: [LiteralNode(text: '1')],
                  den: [
                    FractionNode(
                      num: [LiteralNode(text: '2')],
                      den: [LiteralNode(text: '3')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
        final controller = MathEditorController();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: MathRenderer(
                  expression: [node],
                  rootKey: GlobalKey(),
                  controller: controller,
                  structureVersion: 0,
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ),
        );

        final labelFinder = find.text('log');
        expect(labelFinder, findsOneWidget);

        final labelCenter = tester.getCenter(labelFinder);
        final mainFractionBarCenter = _widestFractionBarCenter(tester);

        expect(
          labelCenter.dy,
          moreOrLessEquals(mainFractionBarCenter.dy, epsilon: 1.0),
        );
      },
    );
  });
}
