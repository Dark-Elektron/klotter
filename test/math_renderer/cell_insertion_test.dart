// test/cell_insertion_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/renderer.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';

/// A testable version of the cell management logic extracted from _HomePageState
/// This allows us to unit test the insertion/shifting logic without widget dependencies
class CellManager {
  int count = 0;
  int activeIndex = 0;

  Map<int, MathEditorController> mathEditorControllers = {};
  Map<int, TextEditingController> textDisplayControllers = {};
  Map<int, FocusNode> focusNodes = {};
  Map<int, ScrollController> scrollControllers = {};
  Map<int, GlobalKey<MathEditorInlineState>> mathEditorKeys = {};
  Map<int, List<MathNode>?> exactResultNodes = {};
  Map<int, Expr?> exactResultExprs = {};
  Map<int, int> currentResultPage = {};
  Map<int, ValueNotifier<int>> currentResultPageNotifiers = {};
  Map<int, ValueNotifier<double>> resultPageProgressNotifiers = {};
  Map<int, ValueNotifier<int>> exactResultVersionNotifiers = {};
  Map<int, bool> plotExpanded = {};

  void createControllers(int index) {
    mathEditorControllers[index] = MathEditorController();
    textDisplayControllers[index] = TextEditingController();
    focusNodes[index] = FocusNode();
    mathEditorKeys[index] = GlobalKey<MathEditorInlineState>();
    scrollControllers[index] = ScrollController();
    currentResultPage[index] = 0;
    currentResultPageNotifiers[index] = ValueNotifier<int>(0);
    resultPageProgressNotifiers[index] = ValueNotifier<double>(0.0);
    exactResultVersionNotifiers[index] = ValueNotifier<int>(0);
    exactResultNodes[index] = null;
    exactResultExprs[index] = null;
  }

  void addDisplay({int? insertAt}) {
    // Default: insert after the active cell
    int insertIndex = insertAt ?? (activeIndex + 1);

    // Clamp to valid range
    insertIndex = insertIndex.clamp(0, count);

    if (insertIndex < count) {
      // Need to shift existing controllers to make room
      _shiftControllersUp(insertIndex);
    }

    createControllers(insertIndex);

    count += 1;
    activeIndex = insertIndex;
  }

  void _shiftControllersUp(int fromIndex) {
    // Work backwards from the end to avoid overwriting
    for (int i = count - 1; i >= fromIndex; i--) {
      int newIndex = i + 1;

      // Move all controller references
      mathEditorControllers[newIndex] = mathEditorControllers[i]!;
      textDisplayControllers[newIndex] = textDisplayControllers[i]!;
      focusNodes[newIndex] = focusNodes[i]!;
      scrollControllers[newIndex] = scrollControllers[i]!;
      mathEditorKeys[newIndex] = mathEditorKeys[i]!;
      exactResultNodes[newIndex] = exactResultNodes[i];
      exactResultExprs[newIndex] = exactResultExprs[i];
      currentResultPage[newIndex] = currentResultPage[i] ?? 0;
      currentResultPageNotifiers[newIndex] = currentResultPageNotifiers[i]!;
      resultPageProgressNotifiers[newIndex] = resultPageProgressNotifiers[i]!;
      exactResultVersionNotifiers[newIndex] = exactResultVersionNotifiers[i]!;

      // Move plot expanded state
      if (plotExpanded.containsKey(i)) {
        plotExpanded[newIndex] = plotExpanded[i]!;
      }
    }

    // Clear the old references at fromIndex
    mathEditorControllers.remove(fromIndex);
    textDisplayControllers.remove(fromIndex);
    focusNodes.remove(fromIndex);
    scrollControllers.remove(fromIndex);
    mathEditorKeys.remove(fromIndex);
    exactResultNodes.remove(fromIndex);
    exactResultExprs.remove(fromIndex);
    currentResultPage.remove(fromIndex);
    currentResultPageNotifiers.remove(fromIndex);
    resultPageProgressNotifiers.remove(fromIndex);
    exactResultVersionNotifiers.remove(fromIndex);
    plotExpanded.remove(fromIndex);
  }

  void removeDisplay(int indexToRemove) {
    if (count <= 1) return;

    mathEditorControllers[indexToRemove]?.dispose();
    mathEditorControllers.remove(indexToRemove);
    textDisplayControllers[indexToRemove]?.dispose();
    textDisplayControllers.remove(indexToRemove);
    focusNodes[indexToRemove]?.dispose();
    focusNodes.remove(indexToRemove);
    scrollControllers[indexToRemove]?.dispose();
    scrollControllers.remove(indexToRemove);
    mathEditorKeys.remove(indexToRemove);
    exactResultNodes.remove(indexToRemove);
    exactResultExprs.remove(indexToRemove);
    currentResultPage.remove(indexToRemove);
    currentResultPageNotifiers[indexToRemove]?.dispose();
    currentResultPageNotifiers.remove(indexToRemove);
    resultPageProgressNotifiers[indexToRemove]?.dispose();
    resultPageProgressNotifiers.remove(indexToRemove);
    exactResultVersionNotifiers[indexToRemove]?.dispose();
    exactResultVersionNotifiers.remove(indexToRemove);
    plotExpanded.remove(indexToRemove);

    int newActiveIndex;
    if (activeIndex == indexToRemove) {
      newActiveIndex = indexToRemove > 0 ? indexToRemove - 1 : 0;
    } else if (activeIndex > indexToRemove) {
      newActiveIndex = activeIndex - 1;
    } else {
      newActiveIndex = activeIndex;
    }

    _reindexControllers();

    count -= 1;
    activeIndex = newActiveIndex;
  }

  void _reindexControllers() {
    List<int> oldKeys = mathEditorControllers.keys.toList()..sort();

    Map<int, MathEditorController> newMathControllers = {};
    Map<int, TextEditingController> newDisplayControllers = {};
    Map<int, FocusNode> newFocusNodes = {};
    Map<int, ScrollController> newScrollControllers = {};
    Map<int, GlobalKey<MathEditorInlineState>> newMathEditorKeys = {};
    Map<int, List<MathNode>?> newExactResultNodes = {};
    Map<int, Expr?> newExactResultExprs = {};
    Map<int, int> newCurrentResultPage = {};
    Map<int, ValueNotifier<int>> newCurrentResultPageNotifiers = {};
    Map<int, ValueNotifier<double>> newResultPageProgressNotifiers = {};
    Map<int, ValueNotifier<int>> newExactResultVersionNotifiers = {};
    Map<int, bool> newPlotExpanded = {};

    for (int newIndex = 0; newIndex < oldKeys.length; newIndex++) {
      int oldKey = oldKeys[newIndex];
      newMathControllers[newIndex] = mathEditorControllers[oldKey]!;
      newDisplayControllers[newIndex] = textDisplayControllers[oldKey]!;
      newFocusNodes[newIndex] = focusNodes[oldKey]!;
      newScrollControllers[newIndex] = scrollControllers[oldKey]!;
      newMathEditorKeys[newIndex] = mathEditorKeys[oldKey]!;
      newExactResultNodes[newIndex] = exactResultNodes[oldKey];
      newExactResultExprs[newIndex] = exactResultExprs[oldKey];
      newCurrentResultPage[newIndex] = currentResultPage[oldKey] ?? 0;
      newCurrentResultPageNotifiers[newIndex] =
          currentResultPageNotifiers[oldKey]!;
      newResultPageProgressNotifiers[newIndex] =
          resultPageProgressNotifiers[oldKey]!;
      newExactResultVersionNotifiers[newIndex] =
          exactResultVersionNotifiers[oldKey]!;
      if (plotExpanded.containsKey(oldKey)) {
        newPlotExpanded[newIndex] = plotExpanded[oldKey]!;
      }
    }

    mathEditorControllers = newMathControllers;
    textDisplayControllers = newDisplayControllers;
    focusNodes = newFocusNodes;
    scrollControllers = newScrollControllers;
    mathEditorKeys = newMathEditorKeys;
    exactResultNodes = newExactResultNodes;
    exactResultExprs = newExactResultExprs;
    currentResultPage = newCurrentResultPage;
    currentResultPageNotifiers = newCurrentResultPageNotifiers;
    resultPageProgressNotifiers = newResultPageProgressNotifiers;
    exactResultVersionNotifiers = newExactResultVersionNotifiers;
    plotExpanded = newPlotExpanded;
  }

  void dispose() {
    for (var controller in mathEditorControllers.values) {
      controller.dispose();
    }
    for (var controller in textDisplayControllers.values) {
      controller.dispose();
    }
    for (var focusNode in focusNodes.values) {
      focusNode.dispose();
    }
    for (var scrollController in scrollControllers.values) {
      scrollController.dispose();
    }
    for (var notifier in currentResultPageNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in resultPageProgressNotifiers.values) {
      notifier.dispose();
    }
    for (var notifier in exactResultVersionNotifiers.values) {
      notifier.dispose();
    }
  }
}

void main() {
  group('CellManager - addDisplay', () {
    late CellManager cellManager;

    setUp(() {
      cellManager = CellManager();
      // Initialize with one cell
      cellManager.createControllers(0);
      cellManager.count = 1;
      cellManager.activeIndex = 0;
    });

    tearDown(() {
      cellManager.dispose();
    });

    test('adds first cell correctly', () {
      final freshManager = CellManager();
      freshManager.addDisplay(insertAt: 0);

      expect(freshManager.count, 1);
      expect(freshManager.activeIndex, 0);
      expect(freshManager.mathEditorControllers.containsKey(0), true);
      expect(freshManager.textDisplayControllers.containsKey(0), true);

      freshManager.dispose();
    });

    test('adds cell at end when no insertAt specified (after active)', () {
      // Start with cell 0
      cellManager.textDisplayControllers[0]!.text = 'cell0';

      // Add cell - should insert after activeIndex (0), so at index 1
      cellManager.addDisplay();

      expect(cellManager.count, 2);
      expect(cellManager.activeIndex, 1); // New cell is active
      expect(cellManager.mathEditorControllers.containsKey(0), true);
      expect(cellManager.mathEditorControllers.containsKey(1), true);
      expect(
        cellManager.textDisplayControllers[0]!.text,
        'cell0',
      ); // Original preserved
    });

    test('adds cell at specific index and shifts others', () {
      // Set up 3 cells with content
      cellManager.textDisplayControllers[0]!.text = 'cell0';

      cellManager.addDisplay(); // Adds cell 1
      cellManager.textDisplayControllers[1]!.text = 'cell1';

      cellManager.addDisplay(); // Adds cell 2
      cellManager.textDisplayControllers[2]!.text = 'cell2';

      expect(cellManager.count, 3);

      // Now insert at index 1 (between cell0 and cell1)
      cellManager.addDisplay(insertAt: 1);

      expect(cellManager.count, 4);
      expect(cellManager.activeIndex, 1); // New cell is active

      // Verify content shifted correctly
      expect(cellManager.textDisplayControllers[0]!.text, 'cell0'); // Unchanged
      expect(cellManager.textDisplayControllers[1]!.text, ''); // New empty cell
      expect(
        cellManager.textDisplayControllers[2]!.text,
        'cell1',
      ); // Shifted from 1 to 2
      expect(
        cellManager.textDisplayControllers[3]!.text,
        'cell2',
      ); // Shifted from 2 to 3
    });

    test('adds cell at beginning (index 0) and shifts all', () {
      // Set up 2 cells with content
      cellManager.textDisplayControllers[0]!.text = 'original0';

      cellManager.addDisplay();
      cellManager.textDisplayControllers[1]!.text = 'original1';

      expect(cellManager.count, 2);

      // Insert at beginning
      cellManager.addDisplay(insertAt: 0);

      expect(cellManager.count, 3);
      expect(cellManager.activeIndex, 0);

      // Verify all shifted
      expect(cellManager.textDisplayControllers[0]!.text, ''); // New empty cell
      expect(
        cellManager.textDisplayControllers[1]!.text,
        'original0',
      ); // Shifted
      expect(
        cellManager.textDisplayControllers[2]!.text,
        'original1',
      ); // Shifted
    });

    test('inserts after active cell by default', () {
      // Set up 3 cells
      cellManager.textDisplayControllers[0]!.text = 'A';
      cellManager.addDisplay();
      cellManager.textDisplayControllers[1]!.text = 'B';
      cellManager.addDisplay();
      cellManager.textDisplayControllers[2]!.text = 'C';

      // Set active to middle cell
      cellManager.activeIndex = 1;

      // Add without specifying index
      cellManager.addDisplay();

      expect(cellManager.count, 4);
      expect(cellManager.activeIndex, 2); // Inserted after old active (1)

      // Verify order: A, B, [new], C
      expect(cellManager.textDisplayControllers[0]!.text, 'A');
      expect(cellManager.textDisplayControllers[1]!.text, 'B');
      expect(cellManager.textDisplayControllers[2]!.text, ''); // New cell
      expect(cellManager.textDisplayControllers[3]!.text, 'C'); // Shifted
    });

    test('all controller maps are shifted correctly', () {
      cellManager.addDisplay();
      cellManager.addDisplay();

      // Mark cells so we can track them
      cellManager.currentResultPage[0] = 10;
      cellManager.currentResultPage[1] = 20;
      cellManager.currentResultPage[2] = 30;

      // Insert at index 1
      cellManager.addDisplay(insertAt: 1);

      expect(cellManager.count, 4);

      // Verify currentResultPage shifted correctly
      expect(cellManager.currentResultPage[0], 10); // Unchanged
      expect(cellManager.currentResultPage[1], 0); // New cell (default)
      expect(cellManager.currentResultPage[2], 20); // Shifted from 1
      expect(cellManager.currentResultPage[3], 30); // Shifted from 2
    });

    test('handles insertAt clamped to valid range', () {
      // Try to insert at negative index
      cellManager.addDisplay(insertAt: -5);
      expect(cellManager.count, 2);
      expect(cellManager.activeIndex, 0); // Clamped to 0

      // Try to insert beyond count
      cellManager.addDisplay(insertAt: 100);
      expect(cellManager.count, 3);
      expect(cellManager.activeIndex, 2); // Clamped to count (2)
    });

    test('keys are contiguous after insertion', () {
      cellManager.addDisplay();
      cellManager.addDisplay();
      cellManager.addDisplay(insertAt: 1);

      final keys = cellManager.mathEditorControllers.keys.toList()..sort();
      expect(keys, [0, 1, 2, 3]);

      // Verify all maps have same keys
      expect(cellManager.textDisplayControllers.keys.toList()..sort(), [
        0,
        1,
        2,
        3,
      ]);
      expect(cellManager.focusNodes.keys.toList()..sort(), [0, 1, 2, 3]);
      expect(cellManager.scrollControllers.keys.toList()..sort(), [0, 1, 2, 3]);
    });
  });

  group('CellManager - removeDisplay', () {
    late CellManager cellManager;

    setUp(() {
      cellManager = CellManager();
      // Set up 3 cells
      cellManager.createControllers(0);
      cellManager.count = 1;
      cellManager.addDisplay();
      cellManager.addDisplay();

      cellManager.textDisplayControllers[0]!.text = 'A';
      cellManager.textDisplayControllers[1]!.text = 'B';
      cellManager.textDisplayControllers[2]!.text = 'C';
      cellManager.activeIndex = 1;
    });

    tearDown(() {
      cellManager.dispose();
    });

    test('removes cell and reindexes correctly', () {
      cellManager.removeDisplay(1);

      expect(cellManager.count, 2);
      expect(cellManager.textDisplayControllers[0]!.text, 'A');
      expect(cellManager.textDisplayControllers[1]!.text, 'C'); // Was index 2
    });

    test('does not remove last cell', () {
      cellManager.removeDisplay(0);
      cellManager.removeDisplay(0);

      expect(cellManager.count, 1);

      // Try to remove last cell
      cellManager.removeDisplay(0);

      expect(cellManager.count, 1); // Still 1
    });

    test('updates activeIndex correctly when removing active cell', () {
      cellManager.activeIndex = 1;
      cellManager.removeDisplay(1);

      expect(cellManager.activeIndex, 0); // Moved to previous
    });

    test('updates activeIndex correctly when removing cell before active', () {
      cellManager.activeIndex = 2;
      cellManager.removeDisplay(0);

      expect(cellManager.activeIndex, 1); // Decremented
    });
  });

  group('CellManager - integration scenarios', () {
    late CellManager cellManager;

    setUp(() {
      cellManager = CellManager();
      cellManager.createControllers(0);
      cellManager.count = 1;
      cellManager.activeIndex = 0;
    });

    tearDown(() {
      cellManager.dispose();
    });

    test('add, insert, remove sequence maintains consistency', () {
      // Add cells: [A]
      cellManager.textDisplayControllers[0]!.text = 'A';

      // Add B: [A, B]
      cellManager.addDisplay();
      cellManager.textDisplayControllers[1]!.text = 'B';

      // Add C: [A, B, C]
      cellManager.addDisplay();
      cellManager.textDisplayControllers[2]!.text = 'C';

      // Insert X at 1: [A, X, B, C]
      cellManager.addDisplay(insertAt: 1);
      cellManager.textDisplayControllers[1]!.text = 'X';

      expect(cellManager.count, 4);
      expect(cellManager.textDisplayControllers[0]!.text, 'A');
      expect(cellManager.textDisplayControllers[1]!.text, 'X');
      expect(cellManager.textDisplayControllers[2]!.text, 'B');
      expect(cellManager.textDisplayControllers[3]!.text, 'C');

      // Remove B (index 2): [A, X, C]
      cellManager.removeDisplay(2);

      expect(cellManager.count, 3);
      expect(cellManager.textDisplayControllers[0]!.text, 'A');
      expect(cellManager.textDisplayControllers[1]!.text, 'X');
      expect(cellManager.textDisplayControllers[2]!.text, 'C');

      // Insert Y at 0: [Y, A, X, C]
      cellManager.addDisplay(insertAt: 0);
      cellManager.textDisplayControllers[0]!.text = 'Y';

      expect(cellManager.count, 4);
      expect(cellManager.textDisplayControllers[0]!.text, 'Y');
      expect(cellManager.textDisplayControllers[1]!.text, 'A');
      expect(cellManager.textDisplayControllers[2]!.text, 'X');
      expect(cellManager.textDisplayControllers[3]!.text, 'C');
    });

    test('rapid insertions at same index', () {
      cellManager.textDisplayControllers[0]!.text = 'original';

      // Insert multiple times at index 0
      for (int i = 1; i <= 5; i++) {
        cellManager.addDisplay(insertAt: 0);
        cellManager.textDisplayControllers[0]!.text = 'inserted$i';
      }

      expect(cellManager.count, 6);

      // Most recent insertion is at 0
      expect(cellManager.textDisplayControllers[0]!.text, 'inserted5');
      expect(cellManager.textDisplayControllers[1]!.text, 'inserted4');
      expect(cellManager.textDisplayControllers[2]!.text, 'inserted3');
      expect(cellManager.textDisplayControllers[3]!.text, 'inserted2');
      expect(cellManager.textDisplayControllers[4]!.text, 'inserted1');
      expect(cellManager.textDisplayControllers[5]!.text, 'original');
    });

    test('insert at end is same as append', () {
      cellManager.textDisplayControllers[0]!.text = 'A';
      cellManager.addDisplay();
      cellManager.textDisplayControllers[1]!.text = 'B';

      // Insert at end (count = 2)
      cellManager.addDisplay(insertAt: 2);
      cellManager.textDisplayControllers[2]!.text = 'C';

      expect(cellManager.count, 3);
      expect(cellManager.textDisplayControllers[0]!.text, 'A');
      expect(cellManager.textDisplayControllers[1]!.text, 'B');
      expect(cellManager.textDisplayControllers[2]!.text, 'C');
    });
  });
}
