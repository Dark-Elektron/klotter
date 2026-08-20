import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Survives a child that has not been laid out.
///
/// Under [AnimatedSize] a child can end up attached, not flagged as needing
/// layout, and yet holding no size — the framework's own invariant broken, not
/// ours. Two things then go wrong, and both have been seen in the wild on this
/// app's keypad:
///
///  * **Hit testing.** `RenderBox.hitTest` asserts a size and throws rather
///    than returning a miss, so the first pointer after launch could kill the
///    frame.
///  * **Layout.** `RenderProxyBox.performLayout` lays its child out and then
///    reads `child.size`, which asserts the same thing. A resume changes the
///    media query, that relayout reaches a child in this state, and the app
///    dies during `drawFrame` — with the read coming from this very box.
///
/// Neither is worth a crash. A miss is the honest answer to a pointer when
/// nothing is laid out, and one frame at the smallest allowed size is a far
/// better answer to layout than bringing the app down; the follow-up frame is
/// requested so the real size arrives immediately after.
///
/// This is the input-and-layout companion of `laidOutBox`, which does the same
/// job for code reading geometry out of a [GlobalKey].
class LaidOutSubtree extends SingleChildRenderObjectWidget {
  const LaidOutSubtree({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderLaidOutSubtree();
}

/// Public only so a test can drive [performLayout] with a sizeless child,
/// which is the state that cannot be produced from the widget layer.
class RenderLaidOutSubtree extends RenderProxyBox {
  /// Set when the child came back from layout without a size, so a test can
  /// tell the fallback from an ordinary pass.
  bool tookFallback = false;

  @override
  void performLayout() {
    final RenderBox? target = child;
    if (target == null) {
      size = computeSizeForNoChild(constraints);
      return;
    }

    // Laid out unconditionally.
    //
    // A guard was tried here that spotted a clean, sizeless child *before* the
    // call and skipped it, because the debug build's early-exit path inside
    // `layout` reads `size` and asserts:
    //
    //     'hasSize': RenderBox was not laid out: RenderFlex
    //     #3  RenderBox.debugResetSize
    //     #6  RenderLaidOutSubtree.performLayout
    //
    // Skipping the call avoided that assertion and was much worse. This box
    // wraps the keypad, so a skipped layout meant the fallback below ran at
    // every launch and the keypad was invisible until a hot restart — a rare
    // crash in debug traded for a broken start every single time.
    //
    // The assertion is debug-only: `debugResetSize` does not exist in a
    // release build, so a published app cannot hit it. Left as it is until
    // there is a fix that does not cost more than the fault.
    target.layout(constraints, parentUsesSize: true);
    if (target.hasSize) {
      tookFallback = false;
      size = target.size;
      return;
    }

    // Laying the child out did not give it a size, which means `layout` took
    // its early exit: the child believes it is clean while holding nothing.
    // Nothing can be read from it this frame.
    tookFallback = true;
    size = constraints.smallest;
    // Ask again once this frame is over. Without this the keypad would stay
    // collapsed at whatever size was invented here, turning a crash into a
    // permanently broken layout, which is not an improvement.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!attached) return;
      // The child has to be dirtied too, not just this box. Marking only
      // itself, the next pass found the child still clean and still sizeless
      // and fell back again, for ever: a crash traded for a keypad stuck at
      // nothing, which is no better.
      child?.markNeedsLayout();
      markNeedsLayout();
    });
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final RenderBox? target = child;
    // Both, because either can be the unmeasured one: this box is skipped
    // while it is itself unsized, and the descent is refused while the child
    // is.
    if (!hasSize || (target != null && !target.hasSize)) return false;
    return super.hitTest(result, position: position);
  }
}
