import 'package:flutter/material.dart';
import 'expression_selection.dart';
import 'math_editor_controller.dart';
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

class MathEditorInlineState extends State<MathEditorInline>
    with SingleTickerProviderStateMixin {
  late AnimationController _cursorBlinkController;
  final GlobalKey _containerKey = GlobalKey();
  int _lastStructureVersion = -1;

  OverlayEntry? _selectionOverlay;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _cursorBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 530),
    );
    if (widget.showCursor) {
      _cursorBlinkController.repeat(reverse: true);
    }

    widget.controller.setContainerKey(_containerKey);
    widget.controller.onSelectionCleared = _onSelectionCleared;

    // // Schedule cursor recalculation after initial layout is complete
    // // We use a small delay to ensure the renderer has had time to report layout
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (mounted) {
    //     Future.delayed(const Duration(milliseconds: 50), () {
    //       if (mounted) {
    //         widget.controller.recalculateCursorPosition();
    //       }
    //     });
    //   }
    // });
  }

  void _onSelectionCleared() {
    if (mounted) {
      _removeSelectionOverlay();
    }
  }

  @override
  void dispose() {
    _removeSelectionOverlay();
    _cursorBlinkController.dispose();
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
        if (!_cursorBlinkController.isAnimating) {
          _cursorBlinkController.repeat(reverse: true);
        }
      } else {
        _cursorBlinkController.stop();
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

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
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
                minHeight: 40,
              ),
              child: RepaintBoundary(
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final structureVersion = widget.controller.structureVersion;
                    if (_lastStructureVersion != structureVersion) {
                      _lastStructureVersion = structureVersion;
                      widget.controller.clearLayoutRegistry();
                    }

                    if (widget.controller.hasSelection &&
                        _selectionOverlay != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _selectionOverlay?.markNeedsBuild();
                      });
                    }

                    return CursorOverlay(
                      notifier: widget.controller.cursorPaintNotifier,
                      blinkAnimation: _cursorBlinkController,
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
