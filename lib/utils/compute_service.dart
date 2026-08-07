import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import '../math_engine/math_engine.dart';
import '../math_engine/math_engine_exact.dart';
import '../math_engine/math_expression_serializer.dart';
import '../math_renderer/math_nodes.dart';
import '../settings/settings_provider.dart';

/// Result of a background computation for a single cell.
class CellComputeResult {
  final int cellIndex;
  final int version;
  final String decimalResult;
  final List<MathNode>? exactNodes;
  final Expr? exactExpr;

  CellComputeResult({
    required this.cellIndex,
    required this.version,
    required this.decimalResult,
    this.exactNodes,
    this.exactExpr,
  });
}

/// Input data for the isolate computation.
/// All fields must be sendable across isolate boundaries.
class _ComputeInput {
  final List<MathNode> expression;
  final Map<int, String>? ansValues;
  final Map<int, Expr>? ansExpressions;
  final NumberFormat numberFormat;
  final int precision;

  _ComputeInput({
    required this.expression,
    this.ansValues,
    this.ansExpressions,
    required this.numberFormat,
    required this.precision,
  });
}

/// Output data from the isolate computation.
class _ComputeOutput {
  final String decimalResult;
  final List<MathNode>? exactNodes;
  final Expr? exactExpr;

  _ComputeOutput({
    required this.decimalResult,
    this.exactNodes,
    this.exactExpr,
  });
}

/// Service that manages debounced, isolate-based computation.
///
/// For each cell, computations are debounced (default 150ms) so that
/// rapid typing only triggers one computation after the user pauses.
/// Each computation runs in a background isolate so the UI stays responsive.
/// Stale results are discarded via per-cell version tracking.
class ComputeService {
  /// Debounce duration before starting computation.
  final Duration debounceDuration;

  /// Callback invoked on the main thread when a computation completes.
  final void Function(CellComputeResult result)? onResult;

  /// Per-cell debounce timers.
  final Map<int, Timer> _debounceTimers = {};

  /// Per-cell version counters for staleness detection.
  final Map<int, int> _versions = {};

  ComputeService({
    this.debounceDuration = const Duration(milliseconds: 150),
    this.onResult,
  });

  /// Request computation for a cell. Debounces and cancels stale requests.
  void computeForCell({
    required int cellIndex,
    required List<MathNode> expression,
    Map<int, String>? ansValues,
    Map<int, Expr>? ansExpressions,
  }) {
    // Bump version to invalidate any in-flight computation
    final version = (_versions[cellIndex] ?? 0) + 1;
    _versions[cellIndex] = version;

    // Cancel any pending debounce timer for this cell
    _debounceTimers[cellIndex]?.cancel();

    // Start a new debounce timer
    _debounceTimers[cellIndex] = Timer(debounceDuration, () {
      _runComputation(
        cellIndex: cellIndex,
        version: version,
        expression: expression,
        ansValues: ansValues,
        ansExpressions: ansExpressions,
        numberFormat: MathSolverNew.numberFormat,
        precision: MathSolverNew.precision,
      );
    });
  }

  /// Run computation immediately (no debounce). Used for cascade updates
  /// where the triggering cell has already been debounced.
  void computeForCellImmediate({
    required int cellIndex,
    required List<MathNode> expression,
    Map<int, String>? ansValues,
    Map<int, Expr>? ansExpressions,
  }) {
    // Bump version to invalidate any in-flight computation
    final version = (_versions[cellIndex] ?? 0) + 1;
    _versions[cellIndex] = version;

    // Cancel any pending debounce timer for this cell
    _debounceTimers[cellIndex]?.cancel();

    _runComputation(
      cellIndex: cellIndex,
      version: version,
      expression: expression,
      ansValues: ansValues,
      ansExpressions: ansExpressions,
      numberFormat: MathSolverNew.numberFormat,
      precision: MathSolverNew.precision,
    );
  }

  Future<void> _runComputation({
    required int cellIndex,
    required int version,
    required List<MathNode> expression,
    Map<int, String>? ansValues,
    Map<int, Expr>? ansExpressions,
    required NumberFormat numberFormat,
    required int precision,
  }) async {
    try {
      final input = _ComputeInput(
        expression: expression,
        ansValues: ansValues,
        ansExpressions: ansExpressions,
        numberFormat: numberFormat,
        precision: precision,
      );

      final output = await Isolate.run(() => _computeInIsolate(input));

      // Check if this result is still current
      if (_versions[cellIndex] != version) {
        // A newer computation was requested; discard this stale result
        return;
      }

      onResult?.call(
        CellComputeResult(
          cellIndex: cellIndex,
          version: version,
          decimalResult: output.decimalResult,
          exactNodes: output.exactNodes,
          exactExpr: output.exactExpr,
        ),
      );
    } catch (e) {
      // Check staleness even on error
      if (_versions[cellIndex] != version) return;

      debugPrint('ComputeService: error in cell $cellIndex: $e');

      onResult?.call(
        CellComputeResult(
          cellIndex: cellIndex,
          version: version,
          decimalResult: '',
          exactNodes: null,
          exactExpr: null,
        ),
      );
    }
  }

  /// Cancel all pending computations for a specific cell.
  void cancelCell(int cellIndex) {
    _debounceTimers[cellIndex]?.cancel();
    _debounceTimers.remove(cellIndex);
    // Bump version so any in-flight isolate results are discarded
    _versions[cellIndex] = (_versions[cellIndex] ?? 0) + 1;
  }

  /// Cancel all pending computations.
  void cancelAll() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    // Bump all versions
    for (final key in _versions.keys.toList()) {
      _versions[key] = _versions[key]! + 1;
    }
  }

  /// Dispose of the service — cancels all timers.
  void dispose() {
    cancelAll();
  }
}

/// Top-level function that runs inside the isolate.
/// Must be a top-level or static function (no closures).
_ComputeOutput _computeInIsolate(_ComputeInput input) {
  // 0. Synchronize formatting settings
  MathSolverNew.setNumberFormat(input.numberFormat);
  MathSolverNew.setPrecision(input.precision);

  // 1. Serialize expression to string (for decimal engine)
  final String exprString = MathExpressionSerializer.serialize(
    input.expression,
  );

  // 2. Run exact engine
  String decimalResult = '';
  List<MathNode>? exactNodes;
  Expr? exactExpr;

  try {
    final exactResult = ExactMathEngine.evaluate(
      input.expression,
      ansExpressions: input.ansExpressions,
    );

    if (!exactResult.isEmpty && !exactResult.hasError) {
      if (exactResult.mathNodes != null && exactResult.mathNodes!.isNotEmpty) {
        exactNodes = exactResult.mathNodes;
        exactExpr = exactResult.expr;
      }

      // Check if exact result should be used as the decimal result
      if ((exactResult.expr?.hasImaginary ?? false) ||
          exprString.contains('i')) {
        decimalResult = exactResult.toNumericalString();
      }
    }
  } catch (_) {
    // Exact engine failed, continue to decimal engine
  }

  // 3. Run decimal engine (unless exact engine already provided the result)
  if (decimalResult.isEmpty) {
    try {
      decimalResult =
          MathSolverNew.solve(exprString, ansValues: input.ansValues) ?? '';
    } catch (_) {
      decimalResult = '';
    }
  }

  return _ComputeOutput(
    decimalResult: decimalResult,
    exactNodes: exactNodes,
    exactExpr: exactExpr,
  );
}
