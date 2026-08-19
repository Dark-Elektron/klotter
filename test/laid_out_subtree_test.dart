import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/utils/laid_out_subtree.dart';

/// A child that is attached, believes it is clean, and holds no size.
///
/// This state cannot be built from the widget layer — it comes from
/// AnimatedSize's own layout timing — so it is modelled directly. Everything
/// else about the box is ordinary; only `hasSize` lies, which is exactly the
/// shape of the two crash reports.
/// Both ways a missing size reaches this box.
///
/// Reported twice from the app, from different directions: once as a hit test
/// during startup, once as `RenderProxyBox.performLayout` reading `child.size`
/// while the app was resumed.
void main() {
  // The sizeless-child cases are not tested here, and the reason is worth
  // recording. A stub that reports `hasSize == false` cannot be put in a
  // widget tree: the framework's own post-layout check reads it first and
  // asserts "RenderBox did not set its size during layout" before the guard is
  // ever reached. The state comes from AnimatedSize's layout timing and cannot
  // be reproduced from outside it.
  //
  // So the layout fallback in RenderLaidOutSubtree.performLayout is verified by
  // reading it, not by a test. What is tested is that the guard is inert on an
  // ordinary subtree — that it lays out to the child's size and passes taps
  // through — which is what would break if the guard were wrong in the common
  // case.
  Widget target(VoidCallback onTap) => GestureDetector(
    // Opaque: a GestureDetector over a bare SizedBox defers to its child, and
    // a bare SizedBox is not hit-testable, so such a target is missed with or
    // without the guard and proves nothing.
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: const SizedBox(width: 80, height: 80),
  );

  testWidgets('an ordinary subtree lays out and is hit as usual', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: LaidOutSubtree(child: target(() => taps++))),
      ),
    );
    final RenderLaidOutSubtree guard = tester.renderObject(
      find.byType(LaidOutSubtree),
    );
    expect(guard.size, const Size(80, 80));
    expect(guard.tookFallback, isFalse);

    await tester.tap(find.byType(GestureDetector));
    expect(taps, 1, reason: 'the guard swallowed a tap it should have passed');
  });
}
