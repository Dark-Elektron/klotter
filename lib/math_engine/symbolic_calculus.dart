part of 'math_engine_exact.dart';

class SymbolicCalculus {
  static int _integrationConstantCounter = -1;
  static const List<String> _subscriptDigits = [
    '\u2080',
    '\u2081',
    '\u2082',
    '\u2083',
    '\u2084',
    '\u2085',
    '\u2086',
    '\u2087',
    '\u2088',
    '\u2089',
  ];

  static T withFreshIntegrationConstants<T>(T Function() action) {
    final int previous = _integrationConstantCounter;
    _integrationConstantCounter = -1;
    try {
      return action();
    } finally {
      _integrationConstantCounter = previous;
    }
  }

  static VarExpr _nextIntegrationConstant() {
    _integrationConstantCounter += 1;
    return VarExpr('c${_toSubscript(_integrationConstantCounter)}');
  }

  static String _toSubscript(int value) {
    final String digits = value.toString();
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final int? n = int.tryParse(digits[i]);
      if (n == null) continue;
      out.write(_subscriptDigits[n]);
    }
    return out.toString();
  }

  static ExactResult? tryBuildSymbolicCalculusResult(
    List<MathNode> expression, {
    Map<int, Expr>? ansExpressions,
  }) {
    final List<MathNode> filtered =
        expression
            .where(
              (node) =>
                  node is! NewlineNode &&
                  !(node is LiteralNode && node.text.trim().isEmpty),
            )
            .toList();
    if (filtered.length != 1) return null;
    final node = filtered.first;

    if (node is DerivativeNode) {
      final bool atEmpty = ExactMathEngine._isNodeListEmpty(node.at);
      final bool bodyEmpty = ExactMathEngine._isNodeListEmpty(node.body);
      if (atEmpty && !bodyEmpty) {
        final String varName =
            MathNodeToExpr._extractLiteralText(node.variable).trim().isEmpty
                ? 'x'
                : MathNodeToExpr._extractLiteralText(node.variable).trim();
        try {
          final Expr bodyExpr = MathNodeToExpr.convert(
            node.body,
            ansExpressions: ansExpressions,
          );
          final Expr? derivative = _differentiateSymbolic(bodyExpr, varName);
          if (derivative != null) {
            return ExactMathEngine._buildExactResultFromExpr(derivative);
          }
        } catch (_) {
          // Fall back to symbolic node below.
        }
        return ExactResult(
          expr: null,
          mathNodes: [
            DerivativeNode(
              variable: ExactMathEngine._cloneNodes(node.variable),
              at: [LiteralNode(text: '')],
              body: ExactMathEngine._cloneNodes(node.body),
            ),
          ],
          isExact: true,
        );
      }
      return null;
    }

    if (node is IntegralNode) {
      final bool lowerEmpty = ExactMathEngine._isNodeListEmpty(node.lower);
      final bool upperEmpty = ExactMathEngine._isNodeListEmpty(node.upper);
      final bool bodyEmpty = ExactMathEngine._isNodeListEmpty(node.body);

      if (lowerEmpty && upperEmpty && !bodyEmpty) {
        final String varName =
            MathNodeToExpr._extractLiteralText(node.variable).trim().isEmpty
                ? 'x'
                : MathNodeToExpr._extractLiteralText(node.variable).trim();
        try {
          final Expr bodyExpr = MathNodeToExpr.convert(
            node.body,
            ansExpressions: ansExpressions,
          );
          final Expr? integral = _integrateSymbolic(bodyExpr, varName);
          if (integral != null) {
            final withConstant =
                SumExpr([integral, _nextIntegrationConstant()]).simplify();
            return ExactMathEngine._buildExactResultFromExpr(withConstant);
          }
        } catch (_) {
          // Fall back to symbolic node below.
        }
        return ExactResult(
          expr: null,
          mathNodes: [
            IntegralNode(
              variable: ExactMathEngine._cloneNodes(node.variable),
              lower: [LiteralNode(text: '')],
              upper: [LiteralNode(text: '')],
              body: ExactMathEngine._cloneNodes(node.body),
            ),
          ],
          isExact: true,
        );
      }
    }

    return null;
  }

  static bool _dependsOnVar(Expr expr, String varName) {
    if (expr is VarExpr) return expr.name == varName;
    if (expr is SumExpr) {
      return expr.terms.any((term) => _dependsOnVar(term, varName));
    }
    if (expr is ProdExpr) {
      return expr.factors.any((factor) => _dependsOnVar(factor, varName));
    }
    if (expr is DivExpr) {
      return _dependsOnVar(expr.numerator, varName) ||
          _dependsOnVar(expr.denominator, varName);
    }
    if (expr is PowExpr) {
      return _dependsOnVar(expr.base, varName) ||
          _dependsOnVar(expr.exponent, varName);
    }
    if (expr is RootExpr) {
      return _dependsOnVar(expr.radicand, varName) ||
          _dependsOnVar(expr.index, varName);
    }
    if (expr is LogExpr) {
      return _dependsOnVar(expr.argument, varName) ||
          _dependsOnVar(expr.base, varName);
    }
    if (expr is TrigExpr) {
      return _dependsOnVar(expr.argument, varName);
    }
    if (expr is AbsExpr) {
      return _dependsOnVar(expr.operand, varName);
    }
    if (expr is PermExpr) {
      return _dependsOnVar(expr.n, varName) || _dependsOnVar(expr.r, varName);
    }
    if (expr is CombExpr) {
      return _dependsOnVar(expr.n, varName) || _dependsOnVar(expr.r, varName);
    }
    if (expr is DerivativeExpr) {
      return _dependsOnVar(expr.body, varName) || expr.variable == varName;
    }
    if (expr is IntegralExpr) {
      return _dependsOnVar(expr.body, varName) ||
          expr.variable == varName ||
          (expr.lower != null && _dependsOnVar(expr.lower!, varName)) ||
          (expr.upper != null && _dependsOnVar(expr.upper!, varName));
    }
    return false;
  }

  static Expr? _differentiateSymbolic(Expr expr, String varName) {
    final Expr simplified = expr.simplify();
    if (!_dependsOnVar(simplified, varName)) {
      return IntExpr.zero;
    }

    if (simplified is VarExpr) {
      return simplified.name == varName ? IntExpr.one : IntExpr.zero;
    }
    if (simplified is IntExpr ||
        simplified is FracExpr ||
        simplified is ConstExpr ||
        simplified is ImaginaryExpr) {
      return IntExpr.zero;
    }
    if (simplified is SumExpr) {
      final List<Expr> terms = [];
      for (final term in simplified.terms) {
        final Expr? dTerm = _differentiateSymbolic(term, varName);
        if (dTerm == null) return null;
        if (!dTerm.isZero) terms.add(dTerm);
      }
      if (terms.isEmpty) return IntExpr.zero;
      return SumExpr(terms).simplify();
    }
    if (simplified is ProdExpr) {
      final List<Expr?> derivs =
          simplified.factors
              .map((factor) => _differentiateSymbolic(factor, varName))
              .toList();
      if (derivs.any((d) => d == null)) return null;

      final List<Expr> terms = [];
      for (int i = 0; i < simplified.factors.length; i++) {
        final Expr dFactor = derivs[i]!;
        if (dFactor.isZero) continue;
        final List<Expr> factors = [];
        for (int j = 0; j < simplified.factors.length; j++) {
          factors.add(j == i ? dFactor : simplified.factors[j]);
        }
        terms.add(ProdExpr(factors));
      }
      if (terms.isEmpty) return IntExpr.zero;
      return SumExpr(terms).simplify();
    }
    if (simplified is DivExpr) {
      if (!_dependsOnVar(simplified.denominator, varName)) {
        final Expr? numDeriv = _differentiateSymbolic(
          simplified.numerator,
          varName,
        );
        if (numDeriv == null) return null;
        return DivExpr(numDeriv, simplified.denominator).simplify();
      }
      final Expr? numDeriv = _differentiateSymbolic(
        simplified.numerator,
        varName,
      );
      final Expr? denDeriv = _differentiateSymbolic(
        simplified.denominator,
        varName,
      );
      if (numDeriv == null || denDeriv == null) return null;
      final Expr numerator =
          SumExpr([
            ProdExpr([numDeriv, simplified.denominator]),
            ProdExpr([IntExpr.negOne, simplified.numerator, denDeriv]),
          ]).simplify();
      final Expr denominator = PowExpr(simplified.denominator, IntExpr.from(2));
      return DivExpr(numerator, denominator).simplify();
    }
    if (simplified is PowExpr) {
      final bool baseDepends = _dependsOnVar(simplified.base, varName);
      final bool expDepends = _dependsOnVar(simplified.exponent, varName);
      if (!expDepends) {
        final Expr? baseDeriv = _differentiateSymbolic(
          simplified.base,
          varName,
        );
        if (baseDeriv == null) return null;
        final Expr? expMinusOne = _subtractOneFromRational(simplified.exponent);
        if (expMinusOne == null) return null;
        return ProdExpr([
          simplified.exponent,
          PowExpr(simplified.base, expMinusOne),
          baseDeriv,
        ]).simplify();
      }
      if (!baseDepends) {
        final Expr? expDeriv = _differentiateSymbolic(
          simplified.exponent,
          varName,
        );
        if (expDeriv == null) return null;
        final Expr lnBase = LogExpr.ln(simplified.base).simplify();
        return ProdExpr([
          PowExpr(simplified.base, simplified.exponent),
          lnBase,
          expDeriv,
        ]).simplify();
      }

      final Expr? baseDeriv = _differentiateSymbolic(simplified.base, varName);
      final Expr? expDeriv = _differentiateSymbolic(
        simplified.exponent,
        varName,
      );
      if (baseDeriv == null || expDeriv == null) return null;
      final Expr term1 =
          ProdExpr([expDeriv, LogExpr.ln(simplified.base)]).simplify();
      final Expr term2 =
          ProdExpr([
            simplified.exponent,
            DivExpr(baseDeriv, simplified.base),
          ]).simplify();
      return ProdExpr([
        PowExpr(simplified.base, simplified.exponent),
        SumExpr([term1, term2]).simplify(),
      ]).simplify();
    }
    if (simplified is RootExpr) {
      final Expr pow = PowExpr(
        simplified.radicand,
        DivExpr(IntExpr.one, simplified.index),
      );
      return _differentiateSymbolic(pow, varName);
    }
    if (simplified is LogExpr) {
      final Expr? argDeriv = _differentiateSymbolic(
        simplified.argument,
        varName,
      );
      if (argDeriv == null) return null;
      if (simplified.isNaturalLog) {
        return DivExpr(argDeriv, simplified.argument).simplify();
      }
      if (_dependsOnVar(simplified.base, varName)) return null;
      final Expr denom =
          ProdExpr([
            simplified.argument,
            LogExpr.ln(simplified.base),
          ]).simplify();
      return DivExpr(argDeriv, denom).simplify();
    }
    if (simplified is TrigExpr) {
      final Expr? argDeriv = _differentiateSymbolic(
        simplified.argument,
        varName,
      );
      if (argDeriv == null) return null;
      Expr? outer;
      switch (simplified.func) {
        case TrigFunc.sin:
          outer = TrigExpr(TrigFunc.cos, simplified.argument);
          break;
        case TrigFunc.cos:
          outer =
              ProdExpr([
                IntExpr.negOne,
                TrigExpr(TrigFunc.sin, simplified.argument),
              ]).simplify();
          break;
        case TrigFunc.tan:
          outer =
              DivExpr(
                IntExpr.one,
                PowExpr(
                  TrigExpr(TrigFunc.cos, simplified.argument),
                  IntExpr.from(2),
                ),
              ).simplify();
          break;
        case TrigFunc.asin:
          outer =
              DivExpr(
                IntExpr.one,
                RootExpr(
                  SumExpr([
                    IntExpr.one,
                    ProdExpr([
                      IntExpr.negOne,
                      PowExpr(simplified.argument, IntExpr.from(2)),
                    ]),
                  ]).simplify(),
                  IntExpr.from(2),
                ),
              ).simplify();
          break;
        case TrigFunc.acos:
          outer =
              DivExpr(
                IntExpr.negOne,
                RootExpr(
                  SumExpr([
                    IntExpr.one,
                    ProdExpr([
                      IntExpr.negOne,
                      PowExpr(simplified.argument, IntExpr.from(2)),
                    ]),
                  ]).simplify(),
                  IntExpr.from(2),
                ),
              ).simplify();
          break;
        case TrigFunc.atan:
          outer =
              DivExpr(
                IntExpr.one,
                SumExpr([
                  IntExpr.one,
                  PowExpr(simplified.argument, IntExpr.from(2)),
                ]).simplify(),
              ).simplify();
          break;
        case TrigFunc.sinh:
          outer = TrigExpr(TrigFunc.cosh, simplified.argument);
          break;
        case TrigFunc.cosh:
          outer = TrigExpr(TrigFunc.sinh, simplified.argument);
          break;
        case TrigFunc.tanh:
          outer =
              DivExpr(
                IntExpr.one,
                PowExpr(
                  TrigExpr(TrigFunc.cosh, simplified.argument),
                  IntExpr.from(2),
                ),
              ).simplify();
          break;
        case TrigFunc.asinh:
          outer =
              DivExpr(
                IntExpr.one,
                RootExpr(
                  SumExpr([
                    IntExpr.one,
                    PowExpr(simplified.argument, IntExpr.from(2)),
                  ]).simplify(),
                  IntExpr.from(2),
                ),
              ).simplify();
          break;
        case TrigFunc.acosh:
        case TrigFunc.atanh:
          outer = null;
          break;
        case TrigFunc.arg:
        case TrigFunc.re:
        case TrigFunc.im:
        case TrigFunc.sgn:
          outer = null;
          break;
      }
      if (outer == null) return null;
      return ProdExpr([outer, argDeriv]).simplify();
    }
    if (simplified is AbsExpr) {
      final Expr? argDeriv = _differentiateSymbolic(
        simplified.operand,
        varName,
      );
      if (argDeriv == null) return null;
      return ProdExpr([
        DivExpr(simplified.operand, AbsExpr(simplified.operand)),
        argDeriv,
      ]).simplify();
    }

    return null;
  }

  static Expr? _integrateSymbolic(Expr expr, String varName) {
    final Expr simplified = expr.simplify();
    if (!_dependsOnVar(simplified, varName)) {
      return ProdExpr([simplified, VarExpr(varName)]).simplify();
    }

    if (simplified is VarExpr) {
      if (simplified.name == varName) {
        final Expr exponentPlusOne = IntExpr.from(2);
        return DivExpr(
          PowExpr(simplified, exponentPlusOne),
          exponentPlusOne,
        ).simplify();
      }
      return ProdExpr([simplified, VarExpr(varName)]).simplify();
    }

    if (simplified is IntExpr ||
        simplified is FracExpr ||
        simplified is ConstExpr ||
        simplified is ImaginaryExpr) {
      return ProdExpr([simplified, VarExpr(varName)]).simplify();
    }

    if (simplified is SumExpr) {
      final List<Expr> terms = [];
      for (final term in simplified.terms) {
        final Expr? integrated = _integrateSymbolic(term, varName);
        if (integrated == null) return null;
        terms.add(integrated);
      }
      return SumExpr(terms).simplify();
    }

    if (simplified is ProdExpr) {
      final List<Expr> constants = [];
      final List<Expr> variableParts = [];
      for (final factor in simplified.factors) {
        if (_dependsOnVar(factor, varName)) {
          variableParts.add(factor);
        } else {
          constants.add(factor);
        }
      }

      if (variableParts.isEmpty) {
        return ProdExpr([...constants, VarExpr(varName)]).simplify();
      }

      final Expr combinedVar =
          variableParts.length == 1
              ? variableParts.first
              : ProdExpr(variableParts).simplify();
      if (variableParts.length > 1 && combinedVar is ProdExpr) {
        return null;
      }

      final Expr? rationalCoeff = _combineRationalFactors(constants);
      if (rationalCoeff != null) {
        final Expr? monomial = _integrateMonomialWithCoeff(
          combinedVar,
          varName,
          rationalCoeff,
        );
        if (monomial != null) return monomial;
      }

      final Expr? integrated = _integrateSymbolic(combinedVar, varName);
      if (integrated == null) return null;
      final List<Expr> factors = [...constants, integrated];
      return ProdExpr(factors).simplify();
    }

    if (simplified is DivExpr) {
      if (!_dependsOnVar(simplified.denominator, varName)) {
        final Expr? integrated = _integrateSymbolic(
          simplified.numerator,
          varName,
        );
        if (integrated == null) return null;
        return DivExpr(integrated, simplified.denominator).simplify();
      }

      final _LinearForm? linearDen = _extractLinear(
        simplified.denominator,
        varName,
      );
      if (linearDen != null &&
          !_dependsOnVar(linearDen.coefficient, varName) &&
          !_dependsOnVar(simplified.numerator, varName)) {
        final Expr scaled =
            ProdExpr([
              simplified.numerator,
              LogExpr.ln(AbsExpr(simplified.denominator)),
            ]).simplify();
        return DivExpr(scaled, linearDen.coefficient).simplify();
      }

      final Expr? denDeriv = _differentiateSymbolic(
        simplified.denominator,
        varName,
      );
      if (denDeriv != null) {
        final Expr? scalar = _extractConstantMultiple(
          simplified.numerator,
          denDeriv,
          varName,
        );
        if (scalar != null) {
          return ProdExpr([
            scalar,
            LogExpr.ln(AbsExpr(simplified.denominator)),
          ]).simplify();
        }
      }
      return null;
    }

    if (simplified is PowExpr) {
      if (!_dependsOnVar(simplified.exponent, varName)) {
        final Expr? exponentPlusOne = _addOneToRational(simplified.exponent);
        if (exponentPlusOne == null) {
          return null;
        }

        final _LinearForm? linearBase = _extractLinear(
          simplified.base,
          varName,
        );
        if (linearBase != null &&
            !_dependsOnVar(linearBase.coefficient, varName)) {
          if (_isNegativeOne(simplified.exponent)) {
            return DivExpr(
              LogExpr.ln(AbsExpr(simplified.base)),
              linearBase.coefficient,
            ).simplify();
          }

          if (exponentPlusOne.isZero) {
            return null;
          }
          final Expr denom =
              ProdExpr([linearBase.coefficient, exponentPlusOne]).simplify();
          return DivExpr(
            PowExpr(simplified.base, exponentPlusOne),
            denom,
          ).simplify();
        }
      }

      if (!_dependsOnVar(simplified.base, varName)) {
        final _LinearForm? linearExp = _extractLinear(
          simplified.exponent,
          varName,
        );
        if (linearExp != null &&
            !_dependsOnVar(linearExp.coefficient, varName)) {
          Expr denom = linearExp.coefficient;
          if (!_isBaseE(simplified.base)) {
            denom = ProdExpr([LogExpr.ln(simplified.base), denom]).simplify();
          }
          return DivExpr(
            PowExpr(simplified.base, simplified.exponent),
            denom,
          ).simplify();
        }
      }
    }

    if (simplified is RootExpr) {
      final Expr pow = PowExpr(
        simplified.radicand,
        DivExpr(IntExpr.one, simplified.index),
      );
      return _integrateSymbolic(pow, varName);
    }

    if (simplified is TrigExpr) {
      final _LinearForm? linearArg = _extractLinear(
        simplified.argument,
        varName,
      );
      if (linearArg == null || _dependsOnVar(linearArg.coefficient, varName)) {
        return null;
      }
      final Expr denom = linearArg.coefficient;
      switch (simplified.func) {
        case TrigFunc.sin:
          return DivExpr(
            ProdExpr([
              IntExpr.negOne,
              TrigExpr(TrigFunc.cos, simplified.argument),
            ]),
            denom,
          ).simplify();
        case TrigFunc.cos:
          return DivExpr(
            TrigExpr(TrigFunc.sin, simplified.argument),
            denom,
          ).simplify();
        case TrigFunc.tan:
          return DivExpr(
            ProdExpr([
              IntExpr.negOne,
              LogExpr.ln(AbsExpr(TrigExpr(TrigFunc.cos, simplified.argument))),
            ]),
            denom,
          ).simplify();
        case TrigFunc.sinh:
          return DivExpr(
            TrigExpr(TrigFunc.cosh, simplified.argument),
            denom,
          ).simplify();
        case TrigFunc.cosh:
          return DivExpr(
            TrigExpr(TrigFunc.sinh, simplified.argument),
            denom,
          ).simplify();
        case TrigFunc.tanh:
          return DivExpr(
            LogExpr.ln(TrigExpr(TrigFunc.cosh, simplified.argument)),
            denom,
          ).simplify();
        case TrigFunc.asin:
        case TrigFunc.acos:
        case TrigFunc.atan:
        case TrigFunc.asinh:
        case TrigFunc.acosh:
        case TrigFunc.atanh:
        case TrigFunc.arg:
        case TrigFunc.re:
        case TrigFunc.im:
        case TrigFunc.sgn:
          return null;
      }
    }

    return null;
  }

  static Expr? _integrateMonomialWithCoeff(
    Expr varPart,
    String varName,
    Expr coeff,
  ) {
    final Expr simplified = varPart.simplify();
    if (simplified is VarExpr && simplified.name == varName) {
      final Expr exponentPlusOne = IntExpr.from(2);
      final Expr? newCoeff = _divideRational(coeff, exponentPlusOne);
      if (newCoeff == null) return null;
      return ProdExpr([
        newCoeff,
        PowExpr(VarExpr(varName), exponentPlusOne),
      ]).simplify();
    }

    if (simplified is PowExpr &&
        simplified.base is VarExpr &&
        (simplified.base as VarExpr).name == varName &&
        !_dependsOnVar(simplified.exponent, varName)) {
      if (_isNegativeOne(simplified.exponent)) {
        return ProdExpr([
          coeff,
          LogExpr.ln(AbsExpr(VarExpr(varName))),
        ]).simplify();
      }
      final Expr? exponentPlusOne = _addOneToRational(simplified.exponent);
      if (exponentPlusOne == null || exponentPlusOne.isZero) return null;
      final Expr? newCoeff = _divideRational(coeff, exponentPlusOne);
      if (newCoeff == null) return null;
      return ProdExpr([
        newCoeff,
        PowExpr(VarExpr(varName), exponentPlusOne),
      ]).simplify();
    }

    return null;
  }

  static Expr? _combineRationalFactors(List<Expr> factors) {
    Expr acc = IntExpr.one;
    for (final factor in factors) {
      if (!_isRationalExpr(factor)) return null;
      final Expr? next = _multiplyRational(acc, factor);
      if (next == null) return null;
      acc = next;
    }
    return acc.simplify();
  }

  static bool _isRationalExpr(Expr expr) {
    return expr is IntExpr || expr is FracExpr;
  }

  static Expr? _multiplyRational(Expr left, Expr right) {
    if (!_isRationalExpr(left) || !_isRationalExpr(right)) return null;
    if (left is IntExpr) {
      return left.multiply(right).simplify();
    }
    if (left is FracExpr) {
      return left.multiply(right).simplify();
    }
    return null;
  }

  static Expr? _divideRational(Expr numerator, Expr denominator) {
    if (!_isRationalExpr(numerator) || !_isRationalExpr(denominator)) {
      return null;
    }
    if (numerator is IntExpr) {
      return numerator.divide(denominator).simplify();
    }
    if (numerator is FracExpr) {
      return numerator.divide(denominator).simplify();
    }
    return null;
  }

  static Expr? _addOneToRational(Expr exponent) {
    final Expr simplified = exponent.simplify();
    if (simplified is IntExpr) {
      return IntExpr(simplified.value + BigInt.one);
    }
    if (simplified is FracExpr) {
      final BigInt num = simplified.numerator.value;
      final BigInt den = simplified.denominator.value;
      return FracExpr(IntExpr(num + den), IntExpr(den)).simplify();
    }
    return null;
  }

  static Expr? _subtractOneFromRational(Expr exponent) {
    final Expr simplified = exponent.simplify();
    if (simplified is IntExpr) {
      return IntExpr(simplified.value - BigInt.one);
    }
    if (simplified is FracExpr) {
      final BigInt num = simplified.numerator.value;
      final BigInt den = simplified.denominator.value;
      return FracExpr(IntExpr(num - den), IntExpr(den)).simplify();
    }
    return null;
  }

  static bool _isNegativeOne(Expr exponent) {
    final Expr simplified = exponent.simplify();
    return simplified is IntExpr && simplified.value == -BigInt.one;
  }

  static bool _isBaseE(Expr base) {
    return base is ConstExpr && base.type == ConstType.e;
  }

  static _LinearForm? _extractLinear(Expr expr, String varName) {
    final Expr simplified = expr.simplify();

    final Expr? directCoeff = _extractLinearCoefficient(simplified, varName);
    if (directCoeff != null) {
      return _LinearForm(directCoeff, IntExpr.zero);
    }

    if (simplified is SumExpr) {
      Expr? linearTerm;
      final List<Expr> constants = [];
      for (final term in simplified.terms) {
        if (_dependsOnVar(term, varName)) {
          if (linearTerm != null) return null;
          linearTerm = term;
        } else {
          constants.add(term);
        }
      }
      if (linearTerm == null) return null;
      final Expr? coeff = _extractLinearCoefficient(linearTerm, varName);
      if (coeff == null) return null;
      final Expr constant =
          constants.isEmpty ? IntExpr.zero : SumExpr(constants).simplify();
      return _LinearForm(coeff, constant);
    }

    return null;
  }

  static Expr? _extractLinearCoefficient(Expr expr, String varName) {
    final Expr simplified = expr.simplify();
    if (simplified is VarExpr && simplified.name == varName) {
      return IntExpr.one;
    }
    if (simplified is ProdExpr) {
      Expr? variableFactor;
      final List<Expr> constants = [];
      for (final factor in simplified.factors) {
        if (_dependsOnVar(factor, varName)) {
          if (variableFactor != null) return null;
          variableFactor = factor;
        } else {
          constants.add(factor);
        }
      }
      if (variableFactor is VarExpr && variableFactor.name == varName) {
        if (constants.isEmpty) return IntExpr.one;
        return ProdExpr(constants).simplify();
      }
    }
    return null;
  }

  static Expr? _extractConstantMultiple(
    Expr expr,
    Expr target,
    String varName,
  ) {
    final Expr simplified = expr.simplify();
    final Expr simplifiedTarget = target.simplify();
    if (simplified.structurallyEquals(simplifiedTarget)) {
      return IntExpr.one;
    }
    if (simplified is ProdExpr) {
      Expr? variableFactor;
      final List<Expr> constants = [];
      for (final factor in simplified.factors) {
        if (_dependsOnVar(factor, varName)) {
          if (variableFactor != null) return null;
          variableFactor = factor;
        } else {
          constants.add(factor);
        }
      }
      if (variableFactor != null &&
          variableFactor.structurallyEquals(simplifiedTarget)) {
        if (constants.isEmpty) return IntExpr.one;
        return ProdExpr(constants).simplify();
      }
    }
    return null;
  }
}

class _LinearForm {
  final Expr coefficient;
  final Expr constant;

  const _LinearForm(this.coefficient, this.constant);
}
