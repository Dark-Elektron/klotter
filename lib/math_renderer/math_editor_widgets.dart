import 'dart:async';

import 'package:flutter/material.dart';
import 'expression_selection.dart';
import 'math_editor_controller.dart';
import 'math_speech.dart';
import 'scrub.dart';
import 'renderer.dart';
import '../utils/render_box.dart';

/// The main math editor widget that handles user interaction.
class MathEditorInline extends StatefulWidget {
  final MathEditorController controller;
  final bool showCursor;
  final VoidCallback? onFocus;
  final double? minWidth;

  /// Called when a drag-to-tune gesture changes a number, so the surrounding
  /// screen (notably the plot) can rebuild against the new expression.
  final VoidCallback? onExpressionChanged;

  const MathEditorInline({
    super.key,
    required this.controller,
    this.showCursor = true,
    this.onFocus,
    this.minWidth,
    this.onExpressionChanged,
  });

  @override
  State<MathEditorInline> createState() => MathEditorInlineState();
}

class MathEditorInlineState extends State<MathEditorInline> {
  /// Whether the caret is in the shown half of its blink: 1 shown, 0 hidden.
  ///
  /// Toggled by a timer, not run by an animation. The caret is only ever on or
  /// off, but an AnimationController on repeat ticks every vsync, and every
  /// tick repainted — so with a caret on screen, which is always, the app drew
  /// a full frame 120 times a second doing nothing, re-rasterising the plot
  /// each time. Measured on a Galaxy A54: 526 frames in six idle seconds. The
  /// timer repaints twice a second, when the caret actually changes.
  final ValueNotifier<double> _cursorPhase = ValueNotifier<double>(1);
  Timer? _blinkTimer;

  static const Duration _blinkHalfPeriod = Duration(milliseconds: 530);

  void _startBlink() {
    _blinkTimer?.cancel();
    _cursorPhase.value = 1;
    _blinkTimer = Timer.periodic(_blinkHalfPeriod, (_) {
      _cursorPhase.value = _cursorPhase.value >= 0.5 ? 0 : 1;
    });
  }

  void _stopBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
  }

  final GlobalKey _containerKey = GlobalKey();
  int _lastStructureVersion = -1;

  OverlayEntry? _selectionOverlay;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    if (widget.showCursor) _startBlink();

    widget.controller.setContainerKey(_containerKey);
    widget.controller.onSelectionCleared = _onSelectionCleared;

    // The caret is placed as each node reports its layout, which happens while
    // this frame is still being laid out. On a fresh build there is no such
    // report for the node the cursor is already in — reopening the app
    // restores every row from storage with a cursor set — so the caret keeps
    // whatever rect it had and is drawn away from the expression.
    //
    // Asking once the frame is over costs nothing and needs no delay: the
    // registry is filled by then, and with nothing in it the call is a no-op.
    _placeCaretAfterLayout();
  }

  /// True while a check is already queued, so a burst of rebuilds does not
  /// queue one per build.
  bool _caretPlacementQueued = false;

  /// The container's size when the nodes last reported their positions.
  Size? _reportedAt;

  /// Bumped when the box changes, and added to the structure version handed to
  /// the renderer.
  ///
  /// A node reports its position once per structure version and then stops —
  /// `_lastReportedVersion == widget.structureVersion` in the renderer. That is
  /// what makes a keystroke the only thing that repairs a stale caret: editing
  /// changes the version, so every node reports afresh. Clearing the registry
  /// alone does not, because clearing does not make anything build; it just
  /// empties the registry and takes tap targeting with it.
  ///
  /// Counting the epoch in gives the same effect without inventing an edit.
  int _layoutEpoch = 0;

  /// Re-measures once the frame is over, and re-registers if the box moved.
  ///
  /// Each node reports its rect *relative to the container* while the frame is
  /// being laid out. That is right for the container it was measured in — but
  /// on opening the app a row is built before the panel around it has settled
  /// on a width, and the content is centred, so when the real width arrives
  /// every glyph shifts right while the registered rects stay where they were.
  ///
  /// The glyphs are drawn from the live layout so they look correct; the caret
  /// is drawn from the registry, so it alone sits out to the left. Tapping does
  /// not help, because a tap is resolved against the same stale registry —
  /// only something that clears it does, which is why backspacing a character
  /// or swiping to another plot and back put it right.
  void _placeCaretAfterLayout() {
    if (_caretPlacementQueued) return;
    _caretPlacementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _caretPlacementQueued = false;
      if (!mounted) return;

      final RenderBox? box = laidOutBox(_containerKey.currentContext);
      final Size? now = box?.size;
      final Size? before = _reportedAt;
      _reportedAt = now;

      // A different box than the rects were measured against means they
      // describe a layout that no longer exists. Asking for a fresh round of
      // reports puts the registry back in step with what is on screen; the
      // build that follows clears the old entries as it goes, so nothing is
      // left empty in between.
      if (now != null && before != null && now != before) {
        setState(() => _layoutEpoch++);
        return;
      }

      widget.controller.recalculateCursorPosition();
    });
  }

  void _onSelectionCleared() {
    if (mounted) {
      _removeSelectionOverlay();
    }
  }

  @override
  void dispose() {
    _removeSelectionOverlay();
    _stopBlink();
    _cursorPhase.dispose();
    widget.controller.onSelectionCleared = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MathEditorInline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.onSelectionCleared = null;
      widget.controller.onSelectionCleared = _onSelectionCleared;
      widget.controller.setContainerKey(_containerKey);
    }
    if (oldWidget.showCursor != widget.showCursor) {
      if (widget.showCursor) {
        if (_blinkTimer == null) _startBlink();
      } else {
        _stopBlink();
      }
    }
  }

  // ============== GESTURE HANDLERS ==============

  void _handlePointerDown(PointerDownEvent event) {
    widget.onFocus?.call();

    if (widget.controller.hasSelection) {
      widget.controller.clearSelection(notify: false);
    }
    if (_selectionOverlay != null) {
      _removeSelectionOverlay();
    }

    final RenderBox? containerBox = laidOutBox(_containerKey.currentContext);
    if (containerBox == null) return;

    final RenderBox? myBox = laidOutBox(context);
    if (myBox == null) return;

    final globalPos = myBox.localToGlobal(event.localPosition);
    final localToContainer = containerBox.globalToLocal(globalPos);

    _processTap(localToContainer, isDoubleTap: false, isLongPress: false);
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    widget.onFocus?.call();

    final RenderBox? containerBox = laidOutBox(_containerKey.currentContext);
    if (containerBox == null) return;

    final RenderBox? gestureBox = laidOutBox(context);
    if (gestureBox == null) return;

    final globalPoint = gestureBox.localToGlobal(details.localPosition);
    final localToContainer = containerBox.globalToLocal(globalPoint);

    _doubleTapPosition = localToContainer;
    _processTap(localToContainer, isDoubleTap: true, isLongPress: false);
  }

  void _processTap(
    Offset localToContainer, {
    required bool isDoubleTap,
    required bool isLongPress,
  }) {
    final bounds = widget.controller.getContentBounds();

    if (bounds != null) {
      const padding = 15.0;
      // The tap's height decides which line's start or end is meant. The
      // bounds span every line, so without it a tap past the end of a short
      // second line reads as "past the end of the expression" and the caret
      // goes to the end of the longest line instead.
      if (localToContainer.dx < bounds.left - padding) {
        widget.controller.moveCursorToStartWithRect(atY: localToContainer.dy);
        return;
      }
      if (localToContainer.dx > bounds.right + padding) {
        widget.controller.moveCursorToEndWithRect(atY: localToContainer.dy);
        return;
      }
    }

    if (isLongPress) {
      widget.controller.selectAtPosition(localToContainer);
    } else {
      widget.controller.tapAt(localToContainer);
    }
  }

  void _handleDoubleTap() {
    if (MathEditorController.clipboard != null &&
        !MathEditorController.clipboard!.isEmpty) {
      _showPasteOnlyOverlay();
    }
  }

  // ============== DRAG TO TUNE ==============

  /// The number currently being scrubbed, if any.
  ScrubTarget? _scrubTarget;
  double _scrubStartX = 0;

  Offset? _toContainer(Offset local) {
    final RenderBox? containerBox = laidOutBox(_containerKey.currentContext);
    final RenderBox? gestureBox = laidOutBox(context);
    if (containerBox == null || gestureBox == null) return null;
    return containerBox.globalToLocal(gestureBox.localToGlobal(local));
  }

  void _handleLongPress(LongPressStartDetails details) {
    widget.onFocus?.call();

    final Offset? localToContainer = _toContainer(details.localPosition);
    if (localToContainer == null) return;

    // Long-press over a number tunes it; long-press anywhere else selects, as
    // before. Disambiguating here avoids inventing a second gesture on a
    // surface that already owns tap, double-tap, long-press and pan.
    final ScrubTarget? target = widget.controller.scrubTargetAt(
      localToContainer,
    );
    if (target != null) {
      // Drop any live selection first. This path returns early, so it used to
      // leave one standing: select something, then long-press a number to
      // tune it, and the next backspace deleted the old selection rather than
      // a character — which after a select-all is the whole expression.
      //
      // In klator, where there is no tuning, a long press over a number
      // selects it and the selection is always replaced. Here it is not, so
      // it has to be cleared deliberately.
      if (widget.controller.hasSelection) {
        widget.controller.clearSelection();
      }
      setState(() {
        _scrubTarget = target;
        _scrubStartX = details.localPosition.dx;
      });
      return;
    }

    _processTap(localToContainer, isDoubleTap: false, isLongPress: true);

    if (widget.controller.hasSelection) {
      _showSelectionOverlay();
    }
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    final ScrubTarget? target = _scrubTarget;
    if (target == null) return;
    final double dx = details.localPosition.dx - _scrubStartX;
    widget.controller.applyScrub(
      target,
      target.initialValue + dx * target.perPixel,
    );
    widget.onExpressionChanged?.call();
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_scrubTarget == null) return;
    setState(() => _scrubTarget = null);
    widget.onExpressionChanged?.call();
  }

  // ============== SELECTION OVERLAY ==============

  void _showSelectionOverlay() {
    _removeSelectionOverlay();

    _selectionOverlay = OverlayEntry(
      builder:
          (context) => SelectionOverlayWidget(
            controller: widget.controller,
            containerKey: _containerKey,
            cursorLocalPosition: null,
            onCopy: _handleCopy,
            onCut: _handleCut,
            onPaste: _handlePaste,
            onDismiss: _handleDismissSelection,
          ),
    );

    Overlay.of(context).insert(_selectionOverlay!);
  }

  void _showPasteOnlyOverlay() {
    _removeSelectionOverlay();

    _selectionOverlay = OverlayEntry(
      builder:
          (context) => SelectionOverlayWidget(
            controller: widget.controller,
            containerKey: _containerKey,
            cursorLocalPosition: _doubleTapPosition,
            onCopy: null,
            onCut: null,
            onPaste: _handlePaste,
            onDismiss: _handleDismissPasteMenu,
          ),
    );

    Overlay.of(context).insert(_selectionOverlay!);
  }

  void _removeSelectionOverlay() {
    _selectionOverlay?.remove();
    _selectionOverlay = null;
    // Don't clear _doubleTapPosition here, it might be about to be used by _showPasteOnlyOverlay
  }

  void _handleCopy() {
    widget.controller.copySelection();
    _handleDismissSelection();
  }

  void _handleCut() {
    widget.controller.cutSelection();
    _removeSelectionOverlay();
  }

  void _handlePaste() {
    widget.controller.pasteClipboard();
    _doubleTapPosition = null;
    _removeSelectionOverlay();
  }

  void _handleDismissSelection() {
    widget.controller.clearSelection();
    _removeSelectionOverlay();
  }

  void _handleDismissPasteMenu() {
    _doubleTapPosition = null;
    _removeSelectionOverlay();
  }

  void showPasteMenu() {
    if (MathEditorController.clipboard != null &&
        !MathEditorController.clipboard!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showPasteOnlyOverlay();
        }
      });
    }
  }

  void clearOverlay() {
    _removeSelectionOverlay();
  }

  // ============== BUILD ==============

  /// A screen reader's double tap, which arrives with no place on the
  /// expression: the row is chosen, and the caret goes to its end, where
  /// typing carries on from.
  void _chooseFromScreenReader() {
    widget.onFocus?.call();
    widget.controller.moveCursorToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);

    // One node for the whole expression, said in words (see [MathSpeech]):
    // the glyphs it is drawn with mean nothing read one at a time. Taps reach
    // the editor as raw pointer events, which a screen reader cannot send, so
    // the node carries a tap of its own.
    return ListenableBuilder(
      listenable: widget.controller,
      builder:
          (context, child) => Semantics(
            container: true,
            label: MathSpeech.describe(widget.controller.expression),
            selected: widget.showCursor,
            onTap: _chooseFromScreenReader,
            onTapHint: 'type here',
            excludeSemantics: true,
            child: child,
          ),
      child: _buildEditor(textScaler),
    );
  }

  Widget _buildEditor(TextScaler textScaler) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Every build, so a box that settles late is noticed. The check itself
        // is one guarded post-frame callback, not one per build.
        _placeCaretAfterLayout();
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _handlePointerDown,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTapDown: _handleDoubleTapDown,
            onDoubleTap: _handleDoubleTap,
            onLongPressStart: _handleLongPress,
            onLongPressMoveUpdate: _handleLongPressMove,
            onLongPressEnd: _handleLongPressEnd,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth:
                    widget.minWidth ??
                    (constraints.maxWidth.isFinite ? constraints.maxWidth : 0),
                // The row's tap target. Kept a touch above the glyph height so
                // a row stays reliably tappable, but no taller: with several
                // rows stacked, every spare pixel here is a gap repeated down
                // the list and space taken from the plot.
                minHeight: 34,
              ),
              child: RepaintBoundary(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    // The renderer's version, which moves when the structure
                    // changes and when the box does.
                    final structureVersion =
                        widget.controller.structureVersion + _layoutEpoch;
                    if (_lastStructureVersion != structureVersion) {
                      _lastStructureVersion = structureVersion;
                      widget.controller.clearLayoutRegistry();
                      // Everything the caret was placed by has just been
                      // thrown away, so place it again once the new layout has
                      // been reported.
                      _placeCaretAfterLayout();
                    }

                    if (widget.controller.hasSelection &&
                        _selectionOverlay != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _selectionOverlay?.markNeedsBuild();
                      });
                    }

                    return CursorOverlay(
                      notifier: widget.controller.cursorPaintNotifier,
                      blinkAnimation: _cursorPhase,
                      showCursor: widget.showCursor,
                      child: KeyedSubtree(
                        key: _containerKey,
                        child: MathRenderer(
                          expression: widget.controller.expression,
                          rootKey: _containerKey,
                          controller: widget.controller,
                          structureVersion: structureVersion,
                          textScaler: textScaler,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
