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

  /// True when this expression involves the imaginary unit anywhere.
  ///
  /// How a line is recognised as a complex function: [evalWith] returns NaN
  /// for [ImaginaryExpr] because it has nowhere to put the imaginary part, so
  /// an expression this is true of cannot be sampled as a real one at all.
  bool get usesImaginaryUnit => _usesImaginary(this);

  /// This expression over the complex numbers.
  ///
  /// The same walk as [evalWith] in [Complex] arithmetic. Kept as a separate
  /// traversal rather than making the real one generic: the real path is the
  /// hot one — marching squares alone asks for tens of thousands of values a
  /// frame — and boxing every intermediate to carry an imaginary part that is
  /// always zero would be paid on every one of them.
  Complex evalComplexWith(Map<String, Complex> bindings) =>
      _evalComplexWith(this, bindings);

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

// ============================================================
// COMPLEX EVALUATION
//
// Mirrors _evalWith case for case. Where the two differ it is because the
// complex answer is the more general one — `sqrt(-1)` is `i` here and NaN
// there, and `log` of a negative number has a value rather than none.
// ============================================================

bool _usesImaginary(Expr expr) {
  if (expr is ImaginaryExpr) return true;
  if (expr is SumExpr) return expr.terms.any(_usesImaginary);
  if (expr is ProdExpr) return expr.factors.any(_usesImaginary);
  if (expr is PowExpr) {
    return _usesImaginary(expr.base) || _usesImaginary(expr.exponent);
  }
  if (expr is DivExpr) {
    return _usesImaginary(expr.numerator) || _usesImaginary(expr.denominator);
  }
  if (expr is RootExpr) {
    return _usesImaginary(expr.radicand) || _usesImaginary(expr.index);
  }
  if (expr is LogExpr) {
    return _usesImaginary(expr.argument) ||
        (!expr.isNaturalLog && _usesImaginary(expr.base));
  }
  if (expr is AbsExpr) return _usesImaginary(expr.operand);
  if (expr is TrigExpr) return _usesImaginary(expr.argument);
  return false;
}

const Complex _zero = Complex(0, 0);
const Complex _one = Complex(1, 0);

Complex _evalComplexWith(Expr expr, Map<String, Complex> b) {
  if (expr is IntExpr) return Complex(expr.value.toDouble(), 0);
  if (expr is FracExpr) {
    return Complex(expr.numerator.value / expr.denominator.value, 0);
  }
  if (expr is ImaginaryExpr) return const Complex(0, 1);
  if (expr is ConstExpr) return Complex(expr.toDouble(), 0);

  if (expr is VarExpr) {
    final Complex? v = b[expr.name];
    if (v == null) throw UnboundVariableError(expr.name);
    return v;
  }

  if (expr is SumExpr) {
    Complex sum = _zero;
    for (final Expr t in expr.terms) {
      sum = sum + _evalComplexWith(t, b);
    }
    return sum;
  }

  if (expr is ProdExpr) {
    Complex prod = _one;
    for (final Expr f in expr.factors) {
      prod = prod * _evalComplexWith(f, b);
    }
    return prod;
  }

  if (expr is PowExpr) {
    return complexPow(
      _evalComplexWith(expr.base, b),
      _evalComplexWith(expr.exponent, b),
    );
  }

  if (expr is RootExpr) {
    final Complex r = _evalComplexWith(expr.radicand, b);
    final Complex n = _evalComplexWith(expr.index, b);
    if (n.imag == 0 && n.real == 2) return complexSqrt(r);
    return complexPow(r, _one / n);
  }

  if (expr is LogExpr) {
    final Complex a = complexLog(_evalComplexWith(expr.argument, b));
    if (expr.isNaturalLog) return a;
    return a / complexLog(_evalComplexWith(expr.base, b));
  }

  if (expr is DivExpr) {
    return _evalComplexWith(expr.numerator, b) /
        _evalComplexWith(expr.denominator, b);
  }

  // |z| is real, so it comes back with a zero imaginary part rather than
  // dropping out of the complex world entirely.
  if (expr is AbsExpr) {
    return Complex(_evalComplexWith(expr.operand, b).magnitude, 0);
  }

  if (expr is TrigExpr) return _evalComplexTrig(expr, b);

  // Anything else — permutations, sums over an index, a derivative — has no
  // complex meaning here. NaN rather than a wrong number.
  return const Complex(double.nan, double.nan);
}

Complex _evalComplexTrig(TrigExpr expr, Map<String, Complex> b) {
  final Complex z = _evalComplexWith(expr.argument, b);
  switch (expr.func) {
    case TrigFunc.sin:
      // sin(x + iy) = sin x cosh y + i cos x sinh y
      return Complex(
        math.sin(z.real) * _cosh(z.imag),
        math.cos(z.real) * _sinh(z.imag),
      );
    case TrigFunc.cos:
      return Complex(
        math.cos(z.real) * _cosh(z.imag),
        -math.sin(z.real) * _sinh(z.imag),
      );
    case TrigFunc.tan:
      return _evalComplexTrigOf(TrigFunc.sin, z) /
          _evalComplexTrigOf(TrigFunc.cos, z);
    case TrigFunc.sinh:
      return Complex(
        _sinh(z.real) * math.cos(z.imag),
        _cosh(z.real) * math.sin(z.imag),
      );
    case TrigFunc.cosh:
      return Complex(
        _cosh(z.real) * math.cos(z.imag),
        _sinh(z.real) * math.sin(z.imag),
      );
    case TrigFunc.tanh:
      return _evalComplexTrigOf(TrigFunc.sinh, z) /
          _evalComplexTrigOf(TrigFunc.cosh, z);
    // Real-valued readings of a complex number, so each returns a real.
    case TrigFunc.arg:
      return Complex(z.phase, 0);
    case TrigFunc.re:
      return Complex(z.real, 0);
    case TrigFunc.im:
      return Complex(z.imag, 0);
    case TrigFunc.sgn:
      final double m = z.magnitude;
      return m == 0 ? _zero : Complex(z.real / m, z.imag / m);
    // The inverse functions have branch cuts that want more care than a
    // formula each; until they are done properly they say so rather than
    // returning something plausible and wrong.
    case TrigFunc.asin:
    case TrigFunc.acos:
    case TrigFunc.atan:
    case TrigFunc.asinh:
    case TrigFunc.acosh:
    case TrigFunc.atanh:
      return const Complex(double.nan, double.nan);
  }
}

/// [_evalComplexTrig] for an argument already evaluated.
Complex _evalComplexTrigOf(TrigFunc func, Complex z) {
  switch (func) {
    case TrigFunc.sin:
      return Complex(
        math.sin(z.real) * _cosh(z.imag),
        math.cos(z.real) * _sinh(z.imag),
      );
    case TrigFunc.cos:
      return Complex(
        math.cos(z.real) * _cosh(z.imag),
        -math.sin(z.real) * _sinh(z.imag),
      );
    case TrigFunc.sinh:
      return Complex(
        _sinh(z.real) * math.cos(z.imag),
        _cosh(z.real) * math.sin(z.imag),
      );
    case TrigFunc.cosh:
      return Complex(
        _cosh(z.real) * math.cos(z.imag),
        _sinh(z.real) * math.sin(z.imag),
      );
    default:
      return const Complex(double.nan, double.nan);
  }
}

double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

/// The principal logarithm: `ln|z| + i·arg z`, with `arg` in (-π, π].
///
/// Undefined at zero, where the modulus has no logarithm and the argument has
/// no value.
Complex complexLog(Complex z) {
  if (z.real == 0 && z.imag == 0) {
    return const Complex(double.negativeInfinity, 0);
  }
  return Complex(math.log(z.magnitude), z.phase);
}

/// `e^z`.
Complex complexExp(Complex z) {
  final double m = math.exp(z.real);
  return Complex(m * math.cos(z.imag), m * math.sin(z.imag));
}

/// The principal square root.
Complex complexSqrt(Complex z) {
  if (z.real == 0 && z.imag == 0) return _zero;
  final double m = math.sqrt(z.magnitude);
  final double half = z.phase / 2;
  return Complex(m * math.cos(half), m * math.sin(half));
}

/// `base^exponent`, by way of `exp(exponent · log base)`.
///
/// Zero is special-cased: `log 0` is not finite, so the general formula would
/// give NaN for `0^2`, which has a perfectly good answer.
Complex complexPow(Complex base, Complex exponent) {
  if (base.real == 0 && base.imag == 0) {
    if (exponent.real == 0 && exponent.imag == 0) return _one;
    return _zero;
  }
  return complexExp(exponent * complexLog(base));
}
