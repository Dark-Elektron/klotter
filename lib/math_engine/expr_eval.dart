part of 'math_engine_exact.dart';

// ============================================================
// NUMERIC EVALUATION WITH VARIABLE BINDINGS
//
// [Expr.toDouble] throws on [VarExpr] because the exact engine never needs to
// put a number to a symbol. Plotting does: it samples one compiled expression
// at hundreds (2D) or thousands (3D surfaces) of points per frame.
//
// [ExprNumericEval.evalWith] is that sampling path — the same arithmetic as
// `toDouble`, but resolving [VarExpr] from a bindings map instead of throwing.
// Compile an expression to an [Expr] once, then call `evalWith` per sample;
// never re-run `MathNodeToExpr.convert`, which re-simplifies on every call.
// ============================================================

/// Thrown when [ExprNumericEval.evalWith] reaches a variable that has no
/// binding. Callers should use [ExprNumericEval.freeVariables] to validate
/// once at compile time rather than catching this per sample.
class UnboundVariableError extends Error {
  final String name;
  UnboundVariableError(this.name);

  @override
  String toString() => 'Unbound variable: $name';
}

extension ExprNumericEval on Expr {
  /// Names of the free variables in this expression.
  ///
  /// A variable bound by a derivative or integral (its variable of
  /// integration) is not free — `∫x² dx` has no free variables, while
  /// `∫(x·t) dt` has the free variable `x`.
  Set<String> get freeVariables {
    final Set<String> out = <String>{};
    _collectFreeVars(this, out);
    return out;
  }

  /// Numeric value of this expression with [bindings] substituted for its free
  /// variables.
  ///
  /// Mirrors [Expr.toDouble] exactly for variable-free expressions. Throws
  /// [UnboundVariableError] if a free variable is missing from [bindings].
  double evalWith(Map<String, double> bindings) => _evalWith(this, bindings);
}

void _collectFreeVars(Expr expr, Set<String> out) {
  if (expr is VarExpr) {
    out.add(expr.name);
  } else if (expr is SumExpr) {
    for (final Expr t in expr.terms) {
      _collectFreeVars(t, out);
    }
  } else if (expr is ProdExpr) {
    for (final Expr f in expr.factors) {
      _collectFreeVars(f, out);
    }
  } else if (expr is PowExpr) {
    _collectFreeVars(expr.base, out);
    _collectFreeVars(expr.exponent, out);
  } else if (expr is RootExpr) {
    _collectFreeVars(expr.radicand, out);
    _collectFreeVars(expr.index, out);
  } else if (expr is LogExpr) {
    _collectFreeVars(expr.argument, out);
    if (!expr.isNaturalLog) _collectFreeVars(expr.base, out);
  } else if (expr is TrigExpr) {
    _collectFreeVars(expr.argument, out);
  } else if (expr is AbsExpr) {
    _collectFreeVars(expr.operand, out);
  } else if (expr is DivExpr) {
    _collectFreeVars(expr.numerator, out);
    _collectFreeVars(expr.denominator, out);
  } else if (expr is PermExpr) {
    _collectFreeVars(expr.n, out);
    _collectFreeVars(expr.r, out);
  } else if (expr is CombExpr) {
    _collectFreeVars(expr.n, out);
    _collectFreeVars(expr.r, out);
  } else if (expr is DerivativeExpr) {
    final Set<String> inner = <String>{};
    _collectFreeVars(expr.body, inner);
    inner.remove(expr.variable);
    out.addAll(inner);
  } else if (expr is IntegralExpr) {
    final Set<String> inner = <String>{};
    _collectFreeVars(expr.body, inner);
    inner.remove(expr.variable);
    out.addAll(inner);
    final Expr? lo = expr.lower;
    final Expr? hi = expr.upper;
    if (lo != null) _collectFreeVars(lo, out);
    if (hi != null) _collectFreeVars(hi, out);
  }
  // IntExpr, FracExpr, ConstExpr, ImaginaryExpr have no variables.
}

double _evalWith(Expr expr, Map<String, double> b) {
  // Fast path: no free variables means the engine's own numeric evaluation is
  // already correct, and it handles complex sub-expressions we cannot.
  if (expr is IntExpr) return expr.value.toDouble();
  if (expr is FracExpr) {
    return expr.numerator.value / expr.denominator.value;
  }
  if (expr is ConstExpr) return expr.toDouble();
  if (expr is ImaginaryExpr) return double.nan;

  if (expr is VarExpr) {
    final double? v = b[expr.name];
    if (v == null) throw UnboundVariableError(expr.name);
    return v;
  }

  if (expr is SumExpr) {
    double sum = 0;
    for (final Expr t in expr.terms) {
      sum += _evalWith(t, b);
    }
    return sum;
  }

  if (expr is ProdExpr) {
    double prod = 1;
    for (final Expr f in expr.factors) {
      prod *= _evalWith(f, b);
    }
    return prod;
  }

  if (expr is PowExpr) {
    return realPow(_evalWith(expr.base, b), _evalWith(expr.exponent, b));
  }

  if (expr is RootExpr) {
    final double r = _evalWith(expr.radicand, b);
    final double n = _evalWith(expr.index, b);
    if (n == 2) return math.sqrt(r);
    return realPow(r, 1 / n);
  }

  if (expr is LogExpr) {
    if (expr.isNaturalLog) return math.log(_evalWith(expr.argument, b));
    return math.log(_evalWith(expr.argument, b)) /
        math.log(_evalWith(expr.base, b));
  }

  if (expr is DivExpr) {
    return _evalWith(expr.numerator, b) / _evalWith(expr.denominator, b);
  }

  if (expr is AbsExpr) {
    // |z| for a complex operand is only meaningful when nothing is bound;
    // with bindings the operand is real by construction.
    if (_collectedFreeVarsEmpty(expr.operand)) return expr.toDouble();
    return _evalWith(expr.operand, b).abs();
  }

  if (expr is TrigExpr) return _evalTrig(expr, b);

  if (expr is PermExpr) {
    final int nVal = _evalWith(expr.n, b).toInt();
    final int rVal = _evalWith(expr.r, b).toInt();
    double result = 1;
    for (int i = 0; i < rVal; i++) {
      result *= (nVal - i);
    }
    return result;
  }

  if (expr is CombExpr) {
    final int nVal = _evalWith(expr.n, b).toInt();
    int rVal = _evalWith(expr.r, b).toInt();
    if (rVal > nVal - rVal) rVal = nVal - rVal;
    double result = 1;
    for (int i = 0; i < rVal; i++) {
      result *= (nVal - i);
      result /= (i + 1);
    }
    return result;
  }

  if (expr is DerivativeExpr || expr is IntegralExpr) {
    // Symbolic calculus resolves during simplify(), which cannot see bindings.
    // With no free variables the node is a constant and the engine's own
    // evaluation is exact; otherwise it is not samplable and the caller should
    // have rejected it at compile time (see PlotExpression.compile).
    if (_collectedFreeVarsEmpty(expr)) return expr.toDouble();
    return double.nan;
  }

  // Unknown Expr subtype: fall back to the engine, which throws on variables
  // rather than inventing a value.
  return expr.toDouble();
}

double _evalTrig(TrigExpr expr, Map<String, double> b) {
  // arg/re/im/sgn need complex evaluation of the argument as an Expr, which
  // cannot accept bindings. They are exact only for variable-free arguments.
  if (expr.func == TrigFunc.arg ||
      expr.func == TrigFunc.re ||
      expr.func == TrigFunc.im ||
      expr.func == TrigFunc.sgn) {
    if (_collectedFreeVarsEmpty(expr.argument)) return expr.toDouble();
    return double.nan;
  }

  final double a = _evalWith(expr.argument, b);
  switch (expr.func) {
    case TrigFunc.sin:
      return math.sin(a);
    case TrigFunc.cos:
      return math.cos(a);
    case TrigFunc.tan:
      return math.tan(a);
    case TrigFunc.asin:
      return math.asin(a);
    case TrigFunc.acos:
      return math.acos(a);
    case TrigFunc.atan:
      return math.atan(a);
    case TrigFunc.sinh:
      return (math.exp(a) - math.exp(-a)) / 2;
    case TrigFunc.cosh:
      return (math.exp(a) + math.exp(-a)) / 2;
    case TrigFunc.tanh:
      return (math.exp(a) - math.exp(-a)) / (math.exp(a) + math.exp(-a));
    case TrigFunc.asinh:
      return math.log(a + math.sqrt(a * a + 1));
    case TrigFunc.acosh:
      return math.log(a + math.sqrt(a * a - 1));
    case TrigFunc.atanh:
      return 0.5 * math.log((1 + a) / (1 - a));
    case TrigFunc.arg:
    case TrigFunc.re:
    case TrigFunc.im:
    case TrigFunc.sgn:
      return double.nan;
  }
}

bool _collectedFreeVarsEmpty(Expr expr) {
  final Set<String> out = <String>{};
  _collectFreeVars(expr, out);
  return out.isEmpty;
}
