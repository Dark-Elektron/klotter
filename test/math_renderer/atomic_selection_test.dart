import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/math_editor_widgets.dart';
import 'package:klotter/math_renderer/math_nodes.dart';

/// π, x̂ and z̲ can be selected, and are selected whole.
///
/// Only literals reported their position, so these symbols were not in the
/// layout registry at all: a long press found the nearest literal instead, and
/// with one at the start of a cell there was no box to put the caret in front
/// of. They are one object each — x̂ is not an x with a mark on it — so a press
/// takes the whole node.
void main() {
  Future<MathEditorController> pumpWith(
    WidgetTester tester,
    List<MathNode> nodes,
  ) async {
    final controller = MathEditorController();
    addTearDown(controller.dispose);
    controller.expression.addAll(nodes);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: MathEditorInline(controller: controller),
            ),
          ),
        ),
      ),
    );
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    return controller;
  }

  testWidgets('an atomic symbol reports where it is', (tester) async {
    // Without a box in the registry nothing can find it: not selection, not a
    // tap, not the caret.
    final controller = await pumpWith(tester, <MathNode>[
      ConstantNode('π'),
      LiteralNode(text: '+1'),
    ]);

    final Iterable<dynamic> atomic = controller.layoutRegistry.values.where(
      (dynamic i) => i.isAtomic as bool,
    );
    expect(
      atomic,
      isNotEmpty,
      reason: 'the constant never reported a box, so it cannot be reached',
    );
  });

  testWidgets('long-pressing it selects the whole node', (tester) async {
    final controller = await pumpWith(tester, <MathNode>[
      ConstantNode('π'),
      LiteralNode(text: '+1'),
    ]);

    final dynamic info = controller.layoutRegistry.values.firstWhere(
      (dynamic i) => i.isAtomic as bool,
    );
    controller.selectAtPosition((info.rect as Rect).center);
    await tester.pump();

    expect(
      controller.hasSelection,
      isTrue,
      reason: 'pressing on π selected nothing',
    );
    final sel = controller.selection!;
    // One node, anchored inside itself rather than spanning into the next.
    // Spanning sent cut down the multi-node path, which deletes the following
    // node instead of this one.
    expect(
      sel.start.nodeIndex,
      sel.end.nodeIndex,
      reason: 'the selection reaches into the next node, so cut takes that too',
    );
    expect(sel.start.charIndex, 0, reason: 'it starts partway into the symbol');
    expect(sel.end.charIndex, 1, reason: 'it does not cover the whole symbol');
  });

  testWidgets('a unit vector is reachable too', (tester) async {
    final controller = await pumpWith(tester, <MathNode>[UnitVectorNode('x')]);
    expect(
      controller.layoutRegistry.values.where((dynamic i) => i.isAtomic as bool),
      isNotEmpty,
      reason: 'x̂ never reported a box',
    );
  });

  testWidgets('cut removes the symbol and nothing else', (tester) async {
    // Copy and paste worked; cut did not. The selection spanned node n to
    // n+1, which took deletion down its multi-node path — that removes the
    // *following* node and handles this one separately.
    final controller = await pumpWith(tester, <MathNode>[
      ConstantNode('π'),
      LiteralNode(text: '+1'),
    ]);

    final dynamic info = controller.layoutRegistry.values.firstWhere(
      (dynamic i) => i.isAtomic as bool,
    );
    controller.selectAtPosition((info.rect as Rect).center);
    await tester.pump();
    controller.cutSelection();
    await tester.pump();

    expect(
      controller.expression.whereType<ConstantNode>(),
      isEmpty,
      reason: 'cut left the symbol where it was',
    );
    expect(
      controller.expression.whereType<LiteralNode>().map((n) => n.text).join(),
      '+1',
      reason: 'cut took the neighbouring text as well',
    );
    expect(
      MathEditorController.clipboard?.nodes.whereType<ConstantNode>(),
      isNotEmpty,
      reason: 'nothing reached the clipboard, so there is nothing to paste',
    );
  });
}
