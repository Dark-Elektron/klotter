part of 'math_engine_exact.dart';

// ============================================================
// COMPILED EVALUATION
//
// [ExprNumericEval.evalWith] walks the tree for every sample: a chain of type
// tests at every node, a map lookup at every variable, a BigInt conversion at
// every constant, and for |…| a fresh walk of the subtree to see whether it
// holds a variable. A plot asks for hundreds of thousands of samples, so the
// walk was most of what drawing cost: 230 ms for the 274,625 samples of the
// tooth surface on a 64³ lattice.
//
// Compiling does the walk once. Each variable becomes a numbered slot, every
// part without a variable becomes the number it comes to, and a small whole
// power becomes multiplication instead of a call to pow. What is left is a
// tree of closures doing only arithmetic.
//
// The walk stays as the reference: a compiled function answers as it does,
// value for value, except that an unrolled power can differ in its last bit.
// The tests hold the two together.
// ============================================================

/// A real expression compiled to a function of its variables' values.
///
/// Slot i of the argument holds the value of the i-th variable named when it
/// was compiled (see [ExprCompile.compileReal]).
typedef RealFunction = double Function(Float64List slots);

/// [RealFunction] over the complex numbers.
typedef ComplexFunction = Complex Function(List<Complex> slots);

extension ExprCompile on Expr {
  /// This expression as a function of [variables], each read from its slot.
  ///
  /// A variable not among [variables] throws [UnboundVariableError] when it
  /// is reached, as [ExprNumericEval.evalWith] does for one not bound.
  RealFunction compileReal(List<String> variables) =>
      _compileReal(this, variables);

  /// [compileReal] over the complex numbers, answering as
  /// [ExprNumericEval.evalComplexWith] does.
  ComplexFunction compileComplex(List<String> variables) =>
      _compileComplex(this, variables);
}

/// The largest whole power multiplied out rather than handed to pow. Past it
/// pow is as quick, and the repeated squaring rounds more often.
const int _largestUnrolledPower = 64;

RealFunction _compileReal(Expr e, List<String> vars) {
  // Anything without a variable is a number: work it out now, once. If
  // working it out throws, the walk threw at every sample, so this does too.
  if (_collectedFreeVarsEmpty(e)) {
    final double value;
    try {
      value = _evalWith(e, const <String, double>{});
    } catch (error) {
      return (Float64List _) => throw error;
    }
    return (Float64List _) => value;
  }

  if (e is VarExpr) {
    final int slot = vars.indexOf(e.name);
    if (slot < 0) {
      final String name = e.name;
      return (Float64List _) => throw UnboundVariableError(name);
    }
    return switch (slot) {
      0 => (Float64List s) => s[0],
      1 => (Float64List s) => s[1],
      2 => (Float64List s) => s[2],
      _ => (Float64List s) => s[slot],
    };
  }

  if (e is SumExpr) {
    final List<RealFunction> t = <RealFunction>[
      for (final Expr term in e.terms) _compileReal(term, vars),
    ];
    // Starting from 0, as the walk does, keeps the sign of a zero the same:
    // 0 + −0 is +0.
    switch (t.length) {
      case 2:
        final RealFunction a = t[0], b = t[1];
        return (Float64List s) => (0.0 + a(s)) + b(s);
      case 3:
        final RealFunction a = t[0], b = t[1], c = t[2];
        return (Float64List s) => ((0.0 + a(s)) + b(s)) + c(s);
    }
    return (Float64List s) {
      double sum = 0;
      for (int i = 0; i < t.length; i++) {
        sum += t[i](s);
      }
      return sum;
    };
  }

  if (e is ProdExpr) {
    final List<RealFunction> f = <RealFunction>[
      for (final Expr factor in e.factors) _compileReal(factor, vars),
    ];
    switch (f.length) {
      case 2:
        final RealFunction a = f[0], b = f[1];
        return (Float64List s) => a(s) * b(s);
      case 3:
        final RealFunction a = f[0], b = f[1], c = f[2];
        return (Float64List s) => a(s) * b(s) * c(s);
    }
    return (Float64List s) {
      double product = 1;
      for (int i = 0; i < f.length; i++) {
        product *= f[i](s);
      }
      return product;
    };
  }

  if (e is PowExpr) {
    final RealFunction base = _compileReal(e.base, vars);
    if (_collectedFreeVarsEmpty(e.exponent)) {
      final double p;
      try {
        p = _evalWith(e.exponent, const <String, double>{});
      } catch (error) {
        // The walk reads the base first, so its failure is the one seen.
        final Object failure = error;
        return (Float64List s) {
          base(s);
          throw failure;
        };
      }
      return _powerOf(base, p);
    }
    final RealFunction exponent = _compileReal(e.exponent, vars);
    return (Float64List s) => realPow(base(s), exponent(s));
  }

  if (e is RootExpr) {
    final RealFunction radicand = _compileReal(e.radicand, vars);
    if (_collectedFreeVarsEmpty(e.index)) {
      final double n;
      try {
        n = _evalWith(e.index, const <String, double>{});
      } catch (error) {
        final Object failure = error;
        return (Float64List s) {
          radicand(s);
          throw failure;
        };
      }
      if (n == 2) return (Float64List s) => math.sqrt(radicand(s));
      final double Function(double) root = _realPowerFor(1 / n);
      return (Float64List s) => root(radicand(s));
    }
    final RealFunction index = _compileReal(e.index, vars);
    return (Float64List s) {
      final double r = radicand(s);
      final double n = index(s);
      if (n == 2) return math.sqrt(r);
      return realPow(r, 1 / n);
    };
  }

  if (e is LogExpr) {
    final RealFunction argument = _compileReal(e.argument, vars);
    if (e.isNaturalLog) return (Float64List s) => math.log(argument(s));
    if (_collectedFreeVarsEmpty(e.base)) {
      final double logBase;
      try {
        logBase = math.log(_evalWith(e.base, const <String, double>{}));
      } catch (error) {
        final Object failure = error;
        return (Float64List s) {
          argument(s);
          throw failure;
        };
      }
      return (Float64List s) => math.log(argument(s)) / logBase;
    }
    final RealFunction base = _compileReal(e.base, vars);
    return (Float64List s) => math.log(argument(s)) / math.log(base(s));
  }

  if (e is DivExpr) {
    final RealFunction n = _compileReal(e.numerator, vars);
    final RealFunction d = _compileReal(e.denominator, vars);
    return (Float64List s) => n(s) / d(s);
  }

  // Its operand holds a variable, or the whole would have been folded above,
  // so this is the plain absolute value — decided here, where the walk asked
  // again at every sample.
  if (e is AbsExpr) {
    final RealFunction operand = _compileReal(e.operand, vars);
    return (Float64List s) => operand(s).abs();
  }

  if (e is TrigExpr) {
    final double Function(double)? f = _realFunction(e.func);
    // arg, re, im and sgn of an argument that varies have no real value.
    if (f == null) return (Float64List _) => double.nan;
    final RealFunction argument = _compileReal(e.argument, vars);
    return (Float64List s) => f(argument(s));
  }

  if (e is FactorialExpr) {
    final RealFunction operand = _compileReal(e.operand, vars);
    return (Float64List s) => factorial(operand(s));
  }

  if (e is PermExpr) {
    final RealFunction n = _compileReal(e.n, vars);
    final RealFunction r = _compileReal(e.r, vars);
    return (Float64List s) {
      final int nVal = n(s).toInt();
      final int rVal = r(s).toInt();
      double result = 1;
      for (int i = 0; i < rVal; i++) {
        result *= (nVal - i);
      }
      return result;
    };
  }

  if (e is CombExpr) {
    final RealFunction n = _compileReal(e.n, vars);
    final RealFunction r = _compileReal(e.r, vars);
    return (Float64List s) {
      final int nVal = n(s).toInt();
      int rVal = r(s).toInt();
      if (rVal > nVal - rVal) rVal = nVal - rVal;
      double result = 1;
      for (int i = 0; i < rVal; i++) {
        result *= (nVal - i);
        result /= (i + 1);
      }
      return result;
    };
  }

  // A derivative or integral that still varies resolves only symbolically,
  // and simplify() could not; the walk has no value for it either.
  if (e is DerivativeExpr || e is IntegralExpr) {
    return (Float64List _) => double.nan;
  }

  // Any other kind of node: what the walk does with it, the engine's own
  // evaluation, which throws on a variable rather than invent a value.
  return (Float64List _) => e.toDouble();
}

/// [base] raised to the constant [p], decided once.
RealFunction _powerOf(RealFunction base, double p) {
  // A whole power, the commonest by far: x², x³, the degree-4 surfaces. pow
  // rounds once where repeated multiplication rounds at each step, so the two
  // can differ in the last bit.
  if (p == p.roundToDouble() && p.abs() <= _largestUnrolledPower) {
    final int n = p.toInt();
    switch (n) {
      case 0:
        // pow(x, 0) is 1 for every x, NaN included.
        return (Float64List s) {
          base(s);
          return 1.0;
        };
      case 1:
        return base;
      case 2:
        return (Float64List s) {
          final double x = base(s);
          return x * x;
        };
      case 3:
        return (Float64List s) {
          final double x = base(s);
          return x * x * x;
        };
      case 4:
        return (Float64List s) {
          final double x = base(s);
          final double x2 = x * x;
          return x2 * x2;
        };
      case -1:
        return (Float64List s) => 1 / base(s);
      case -2:
        return (Float64List s) {
          final double x = base(s);
          return 1 / (x * x);
        };
    }
    final bool reciprocal = n < 0;
    final int m = n.abs();
    return (Float64List s) {
      double x = base(s);
      double result = 1;
      for (int k = m; k > 0; k >>= 1) {
        if (k & 1 == 1) result *= x;
        x *= x;
      }
      return reciprocal ? 1 / result : result;
    };
  }
  final double Function(double) power = _realPowerFor(p);
  return (Float64List s) => power(base(s));
}

/// [realPow] with its exponent fixed at [p].
///
/// Whether a negative base has a real root depends only on the exponent's
/// denominator, so the search for it is done here, once, rather than at every
/// sample. Answers exactly as realPow does.
double Function(double) _realPowerFor(double p) {
  if (p == p.roundToDouble()) {
    return (double b) => math.pow(b, p).toDouble();
  }
  for (int q = 3; q <= 99; q += 2) {
    final double pDouble = p * q;
    final double pRounded = pDouble.roundToDouble();
    if ((pDouble - pRounded).abs() < 1e-9) {
      // Negative only when the numerator is odd.
      final bool odd = pRounded.toInt().abs() % 2 == 1;
      return (double b) {
        if (b >= 0) return math.pow(b, p).toDouble();
        final double magnitude = math.pow(b.abs(), p).toDouble();
        return odd ? -magnitude : magnitude;
      };
    }
  }
  return (double b) => math.pow(b, p).toDouble();
}

ComplexFunction _compileComplex(Expr e, List<String> vars) {
  if (_collectedFreeVarsEmpty(e)) {
    final Complex value;
    try {
      value = _evalComplexWith(e, const <String, Complex>{});
    } catch (error) {
      return (List<Complex> _) => throw error;
    }
    return (List<Complex> _) => value;
  }

  if (e is VarExpr) {
    final int slot = vars.indexOf(e.name);
    if (slot < 0) {
      final String name = e.name;
      return (List<Complex> _) => throw UnboundVariableError(name);
    }
    return (List<Complex> s) => s[slot];
  }

  if (e is SumExpr) {
    final List<ComplexFunction> t = <ComplexFunction>[
      for (final Expr term in e.terms) _compileComplex(term, vars),
    ];
    return (List<Complex> s) {
      Complex sum = _zero;
      for (int i = 0; i < t.length; i++) {
        sum = sum + t[i](s);
      }
      return sum;
    };
  }

  if (e is ProdExpr) {
    final List<ComplexFunction> f = <ComplexFunction>[
      for (final Expr factor in e.factors) _compileComplex(factor, vars),
    ];
    // From one, as the walk does: 1 × (∞ + 0i) is not ∞ + 0i but ∞ + NaN·i,
    // and a value that differed there would colour a pole differently.
    return (List<Complex> s) {
      Complex product = _one;
      for (int i = 0; i < f.length; i++) {
        product = product * f[i](s);
      }
      return product;
    };
  }

  if (e is PowExpr) {
    final ComplexFunction base = _compileComplex(e.base, vars);
    if (_collectedFreeVarsEmpty(e.exponent)) {
      final Complex p;
      try {
        p = _evalComplexWith(e.exponent, const <String, Complex>{});
      } catch (error) {
        final Object failure = error;
        return (List<Complex> s) {
          base(s);
          throw failure;
        };
      }
      // A whole power by multiplying, which is both quicker and closer than
      // exp(n·log z); the two agree to rounding away from z = 0.
      if (p.imag == 0 &&
          p.real == p.real.roundToDouble() &&
          p.real.abs() <= _largestUnrolledPower &&
          p.real != 0) {
        final int n = p.real.toInt();
        final bool reciprocal = n < 0;
        final int m = n.abs();
        return (List<Complex> s) {
          final Complex z = base(s);
          // Zero to any power but zero is zero, as complexPow has it.
          if (z.real == 0 && z.imag == 0) return _zero;
          Complex x = z;
          Complex result = _one;
          for (int k = m; k > 0; k >>= 1) {
            if (k & 1 == 1) result = result * x;
            if (k > 1) x = x * x;
          }
          return reciprocal ? _one / result : result;
        };
      }
      return (List<Complex> s) => complexPow(base(s), p);
    }
    final ComplexFunction exponent = _compileComplex(e.exponent, vars);
    return (List<Complex> s) => complexPow(base(s), exponent(s));
  }

  if (e is RootExpr) {
    final ComplexFunction radicand = _compileComplex(e.radicand, vars);
    final ComplexFunction index = _compileComplex(e.index, vars);
    return (List<Complex> s) {
      final Complex r = radicand(s);
      final Complex n = index(s);
      if (n.imag == 0 && n.real == 2) return complexSqrt(r);
      return complexPow(r, _one / n);
    };
  }

  if (e is LogExpr) {
    final ComplexFunction argument = _compileComplex(e.argument, vars);
    if (e.isNaturalLog) return (List<Complex> s) => complexLog(argument(s));
    final ComplexFunction base = _compileComplex(e.base, vars);
    return (List<Complex> s) => complexLog(argument(s)) / complexLog(base(s));
  }

  if (e is DivExpr) {
    final ComplexFunction n = _compileComplex(e.numerator, vars);
    final ComplexFunction d = _compileComplex(e.denominator, vars);
    return (List<Complex> s) => n(s) / d(s);
  }

  // |z| is real, so it comes back with a zero imaginary part.
  if (e is AbsExpr) {
    final ComplexFunction operand = _compileComplex(e.operand, vars);
    return (List<Complex> s) => Complex(operand(s).magnitude, 0);
  }

  if (e is TrigExpr) {
    final Complex Function(Complex) f = _complexFunction(e.func);
    final ComplexFunction argument = _compileComplex(e.argument, vars);
    return (List<Complex> s) => f(argument(s));
  }

  if (e is FactorialExpr) {
    final ComplexFunction operand = _compileComplex(e.operand, vars);
    return (List<Complex> s) => complexGamma(operand(s) + _one);
  }

  // Permutations, a derivative and the rest have no complex meaning here: NaN
  // rather than a wrong number, as in the walk.
  return (List<Complex> _) => const Complex(double.nan, double.nan);
}
