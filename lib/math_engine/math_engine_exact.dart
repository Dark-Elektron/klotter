// lib/math_engine/math_engine_exact.dart

import 'dart:math' as math;
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/math_engine/math_engine.dart';
part 'symbolic_calculus.dart';
part 'expr_eval.dart';

/// Real-valued power that also returns the real root of a negative base when
/// the exponent is a rational p/q with an odd denominator (e.g. an nth root
/// such as `(-8)^(1/3) == -2`). `dart:math`'s `pow` returns `NaN` for a
/// negative base with a fractional exponent, so those cases are handled here.
/// Genuinely complex cases (e.g. `(-1)^(1/2)`) still return `NaN`.
double realPow(double b, double exp) {
  if (b >= 0 || exp == exp.roundToDouble()) {
    return math.pow(b, exp).toDouble();
  }
  for (int q = 3; q <= 99; q += 2) {
    final double pDouble = exp * q;
    final double pRounded = pDouble.roundToDouble();
    if ((pDouble - pRounded).abs() < 1e-9) {
      final double magnitude = math.pow(b.abs(), exp).toDouble();
      // Sign is (-1)^p: negative only when the numerator is odd.
      return (pRounded.toInt().abs() % 2 == 1) ? -magnitude : magnitude;
    }
  }
  return math.pow(b, exp).toDouble();
}

// ============================================================
// SECTION 1: EXPRESSION BASE CLASS
// ============================================================

/// Base class for all symbolic mathematical expressions.
///
/// The Expr tree represents mathematical expressions symbolically,
/// allowing for exact computation and simplification.
abstract class Expr {
  /// Simplify this expression as much as possible.
  Expr simplify();

  /// Get numerical approximation.
  double toDouble();

  /// Check if this expression equals another structurally.
  bool structurallyEquals(Expr other);

  /// Get a canonical string signature for combining like terms.
  /// For example, 3√2 and 5√2 both have signature "root:2:2"
  String get termSignature;

  /// Get the coefficient part (e.g., 3 in 3√2)
  Expr get coefficient;

  /// Get the base part (e.g., √2 in 3√2)
  Expr get baseExpr;

  /// Is this expression exactly zero?
  bool get isZero;

  /// Is this expression exactly one?
  bool get isOne;

  /// Is this a rational number (integer or fraction)?
  bool get isRational;

  /// Is this exactly an integer?
  bool get isInteger;

  /// Negate this expression
  Expr negate();

  /// Convert to MathNode for rendering
  List<MathNode> toMathNode();

  /// Create a deep copy
  Expr copy();

  /// Does this expression contain imaginary parts?
  bool get hasImaginary;

  @override
  String toString();
}

// ============================================================
// SECTION 2: INTEGER EXPRESSION
// ============================================================

/// Helper for consistent number formatting in exact results
class ExactNumberFormatter {
  static const String smallCapsE = '\u1D07';
  static final BigInt threshold = BigInt.from(10).pow(15);

  static String formatBigInt(BigInt value, {bool isWholeNumber = false}) {
    BigInt absVal = value.abs();
    bool useScientific = false;

    final format = MathSolverNew.numberFormat;

    if (format == NumberFormat.scientific) {
      // Rule: always use scientific for any non-zero number
      if (absVal > BigInt.zero) {
        useScientific = true;
      }
    } else if (format == NumberFormat.automatic) {
      // Rule: scientific if >= 1e6
      if (absVal >= BigInt.from(1000000)) {
        useScientific = true;
      }
    }
    // Plain rule: never use scientific (useScientific = false)

    if (useScientific) {
      String s = absVal.toString();
      int p = MathSolverNew.precision;
      int len = s.length;
      int exponent = len - 1;

      // Rounding logic for BigInt to match precision p (decimal places)
      if (len > p + 1) {
        String prefix = s.substring(0, p + 1);
        int nextDigit = int.parse(s[p + 1]);
        if (nextDigit >= 5) {
          BigInt rounded = BigInt.parse(prefix) + BigInt.one;
          String roundedStr = rounded.toString();
          if (roundedStr.length > prefix.length) {
            exponent += 1;
            s = roundedStr;
          } else {
            s = roundedStr;
          }
        } else {
          s = prefix;
        }
      }

      // Format as mantissa with dot after first digit
      String mantissa = s[0];
      String rest = s.substring(1).replaceAll(RegExp(r'0+$'), '');
      if (rest.isNotEmpty) {
        mantissa += '.$rest';
      }

      String result = '$mantissa$smallCapsE$exponent';
      return value < BigInt.zero ? '\u2212$result' : result;
    }

    String resultStr = absVal.toString();
    if (format == NumberFormat.plain) {
      resultStr = MathSolverNew.addCommas(resultStr);
    }

    if (value < BigInt.zero) {
      return '\u2212$resultStr';
    }
    return resultStr;
  }
}

/// Represents an exact integer value.
class IntExpr extends Expr {
  final BigInt value;

  IntExpr(this.value);

  /// Convenience constructor from int
  IntExpr.from(int v) : value = BigInt.from(v);

  /// Common constants
  static final IntExpr zero = IntExpr(BigInt.zero);
  static final IntExpr one = IntExpr(BigInt.one);
  static final IntExpr two = IntExpr(BigInt.two);
  static final IntExpr negOne = IntExpr(-BigInt.one);

  @override
  bool get hasImaginary => false;

  @override
  Expr simplify() => this;

  @override
  double toDouble() => value.toDouble();

  @override
  bool structurallyEquals(Expr other) {
    return other is IntExpr && other.value == value;
  }

  @override
  String get termSignature => 'int:1'; // All integers combine together

  @override
  Expr get coefficient => this;

  @override
  Expr get baseExpr => IntExpr.one;

  @override
  bool get isZero => value == BigInt.zero;

  @override
  bool get isOne => value == BigInt.one;

  @override
  bool get isRational => true;

  @override
  bool get isInteger => true;

  @override
  Expr negate() => IntExpr(-value);

  @override
  List<MathNode> toMathNode() {
    return [
      LiteralNode(
        text: ExactNumberFormatter.formatBigInt(value, isWholeNumber: true),
      ),
    ];
  }

  @override
  Expr copy() => IntExpr(value);

  @override
  String toString() =>
      ExactNumberFormatter.formatBigInt(value, isWholeNumber: true);

  /// Arithmetic operations returning Expr
  Expr add(Expr other) {
    if (other is IntExpr) {
      return IntExpr(value + other.value);
    }
    if (other is FracExpr) {
      // a + (n/d) = (a*d + n) / d
      return FracExpr(
        IntExpr(value * other.denominator.value + other.numerator.value),
        other.denominator,
      ).simplify();
    }
    return SumExpr([this, other]).simplify();
  }

  Expr subtract(Expr other) {
    return add(other.negate());
  }

  Expr multiply(Expr other) {
    if (other is IntExpr) {
      return IntExpr(value * other.value);
    }
    if (other is FracExpr) {
      return FracExpr(
        IntExpr(value * other.numerator.value),
        other.denominator,
      ).simplify();
    }
    return ProdExpr([this, other]).simplify();
  }

  Expr divide(Expr other) {
    if (other is IntExpr) {
      return FracExpr(this, other).simplify();
    }
    if (other is FracExpr) {
      // a / (n/d) = a*d / n
      return FracExpr(
        IntExpr(value * other.denominator.value),
        other.numerator,
      ).simplify();
    }
    return FracExpr(this, other).simplify();
  }

  Expr power(Expr exponent) {
    if (exponent is IntExpr) {
      if (exponent.value == BigInt.zero) return IntExpr.one;
      if (exponent.value == BigInt.one) return this;
      if (exponent.value > BigInt.zero) {
        return IntExpr(value.pow(exponent.value.toInt()));
      }
      // Negative exponent: a^(-n) = 1 / a^n
      return FracExpr(IntExpr.one, IntExpr(value.pow(-exponent.value.toInt())));
    }
    return PowExpr(this, exponent).simplify();
  }
}

// ============================================================
// SECTION 3: FRACTION EXPRESSION
// ============================================================

/// Represents an exact fraction n/d.
// ============================================================
// SECTION 3: FRACTION EXPRESSION
// ============================================================

/// Represents an exact fraction n/d.
class FracExpr extends Expr {
  final IntExpr numerator;
  final IntExpr denominator;

  FracExpr(Expr num, Expr den)
    : numerator =
          num is IntExpr
              ? num
              : throw ArgumentError('Numerator must be IntExpr'),
      denominator =
          den is IntExpr
              ? den
              : throw ArgumentError('Denominator must be IntExpr');

  /// Convenience constructor from ints
  FracExpr.from(int n, int d)
    : numerator = IntExpr.from(n),
      denominator = IntExpr.from(d);

  @override
  bool get hasImaginary => false;

  @override
  Expr simplify() {
    BigInt n = numerator.value;
    BigInt d = denominator.value;

    // Handle zero
    if (n == BigInt.zero) return IntExpr.zero;

    // Handle division by zero (return as-is, or could throw)
    if (d == BigInt.zero) return this;

    // Make denominator positive
    if (d < BigInt.zero) {
      n = -n;
      d = -d;
    }

    // Reduce to lowest terms
    BigInt g = n.gcd(d).abs();
    n = n ~/ g;
    d = d ~/ g;

    // If denominator is 1, return integer
    if (d == BigInt.one) {
      return IntExpr(n);
    }

    return FracExpr(IntExpr(n), IntExpr(d));
  }

  @override
  double toDouble() => numerator.value / denominator.value;

  @override
  bool structurallyEquals(Expr other) {
    if (other is FracExpr) {
      Expr thisSimp = simplify();
      Expr otherSimp = other.simplify();
      if (thisSimp is IntExpr && otherSimp is IntExpr) {
        return thisSimp.value == otherSimp.value;
      }
      if (thisSimp is FracExpr && otherSimp is FracExpr) {
        return thisSimp.numerator.value == otherSimp.numerator.value &&
            thisSimp.denominator.value == otherSimp.denominator.value;
      }
    }
    if (other is IntExpr) {
      Expr thisSimp = simplify();
      return thisSimp is IntExpr && thisSimp.value == other.value;
    }
    return false;
  }

  @override
  String get termSignature => 'int:1'; // Rationals combine with integers

  @override
  Expr get coefficient => this;

  @override
  Expr get baseExpr => IntExpr.one;

  @override
  bool get isZero => numerator.value == BigInt.zero;

  @override
  bool get isOne {
    Expr s = simplify();
    return s is IntExpr && s.value == BigInt.one;
  }

  @override
  bool get isRational => true;

  @override
  bool get isInteger {
    Expr s = simplify();
    return s is IntExpr;
  }

  @override
  Expr negate() => FracExpr(numerator.negate() as IntExpr, denominator);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();
    if (simplified is IntExpr) {
      return simplified.toMathNode();
    }

    FracExpr frac = simplified as FracExpr;

    // Check if the fraction is negative (numerator is negative)
    bool isNegative = frac.numerator.value < BigInt.zero;

    if (isNegative) {
      // Put negative sign outside the fraction
      BigInt absNumerator = frac.numerator.value.abs();
      return [
        LiteralNode(text: '−'),
        FractionNode(
          num: [
            LiteralNode(text: ExactNumberFormatter.formatBigInt(absNumerator)),
          ],
          den: [
            LiteralNode(
              text: ExactNumberFormatter.formatBigInt(frac.denominator.value),
            ),
          ],
        ),
      ];
    } else {
      return [
        FractionNode(
          num: [
            LiteralNode(
              text: ExactNumberFormatter.formatBigInt(frac.numerator.value),
            ),
          ],
          den: [
            LiteralNode(
              text: ExactNumberFormatter.formatBigInt(frac.denominator.value),
            ),
          ],
        ),
      ];
    }
  }

  @override
  Expr copy() => FracExpr(IntExpr(numerator.value), IntExpr(denominator.value));

  @override
  String toString() {
    Expr s = simplify();
    if (s is IntExpr) return s.toString();
    return '$numerator/$denominator';
  }

  /// Add another expression to this fraction
  Expr add(Expr other) {
    if (other is IntExpr) {
      return FracExpr(
        IntExpr(numerator.value + other.value * denominator.value),
        denominator,
      ).simplify();
    }
    if (other is FracExpr) {
      return FracExpr(
        IntExpr(
          numerator.value * other.denominator.value +
              other.numerator.value * denominator.value,
        ),
        IntExpr(denominator.value * other.denominator.value),
      ).simplify();
    }
    return SumExpr([this, other]).simplify();
  }

  Expr subtract(Expr other) => add(other.negate());

  Expr multiply(Expr other) {
    if (other is IntExpr) {
      return FracExpr(
        IntExpr(numerator.value * other.value),
        denominator,
      ).simplify();
    }
    if (other is FracExpr) {
      return FracExpr(
        IntExpr(numerator.value * other.numerator.value),
        IntExpr(denominator.value * other.denominator.value),
      ).simplify();
    }
    return ProdExpr([this, other]).simplify();
  }

  Expr divide(Expr other) {
    if (other is IntExpr) {
      return FracExpr(
        numerator,
        IntExpr(denominator.value * other.value),
      ).simplify();
    }
    if (other is FracExpr) {
      return FracExpr(
        IntExpr(numerator.value * other.denominator.value),
        IntExpr(denominator.value * other.numerator.value),
      ).simplify();
    }
    return DivExpr(this, other).simplify();
  }
}

// ============================================================
// SECTION 4: SYMBOLIC CONSTANTS
// ============================================================

/// Represents a symbolic constant like π, e, φ (golden ratio)
class ConstExpr extends Expr {
  final ConstType type;

  ConstExpr(this.type);

  @override
  bool get hasImaginary => false;

  static final ConstExpr pi = ConstExpr(ConstType.pi);
  static final ConstExpr e = ConstExpr(ConstType.e);
  static final ConstExpr epsilon0 = ConstExpr(ConstType.epsilon0);
  static final ConstExpr mu0 = ConstExpr(ConstType.mu0);
  static final ConstExpr c0 = ConstExpr(ConstType.c0);
  static final ConstExpr eMinus = ConstExpr(ConstType.eMinus);

  @override
  Expr simplify() => this;

  @override
  double toDouble() {
    switch (type) {
      case ConstType.pi:
        return math.pi;
      case ConstType.e:
        return math.e;
      case ConstType.epsilon0:
        return 8.8541878128e-12; // vacuum permittivity F/m
      case ConstType.mu0:
        return 1.25663706212e-6; // vacuum permeability H/m
      case ConstType.c0:
        return 299792458.0; // speed of light m/s
      case ConstType.eMinus:
        return 1.602176634e-19; // elementary charge C
    }
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is ConstExpr && other.type == type;
  }

  @override
  String get termSignature => 'const:${type.name}';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => false;

  @override
  bool get isOne => false;

  @override
  bool get isRational => false;

  @override
  bool get isInteger => false;

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    switch (type) {
      case ConstType.pi:
        return [LiteralNode(text: 'π')];
      case ConstType.e:
        return [LiteralNode(text: 'e')];
      case ConstType.epsilon0:
        return [ConstantNode('ε₀')];
      case ConstType.mu0:
        return [ConstantNode('μ₀')];
      case ConstType.c0:
        return [ConstantNode('c₀')];
      case ConstType.eMinus:
        return [ConstantNode('e⁻')];
    }
  }

  @override
  Expr copy() => ConstExpr(type);

  @override
  String toString() {
    switch (type) {
      case ConstType.pi:
        return 'π';
      case ConstType.e:
        return 'e';
      case ConstType.epsilon0:
        return 'ε₀';
      case ConstType.mu0:
        return 'μ₀';
      case ConstType.c0:
        return 'c₀';
      case ConstType.eMinus:
        return 'e⁻';
    }
  }
}

/// Named constants the engine knows.
///
/// The golden ratio used to be here. Nothing could reach it — no key inserts
/// it and neither `φ` nor the word could be typed — and `φ` is now the
/// spherical polar angle, an ordinary variable.
enum ConstType { pi, e, epsilon0, mu0, c0, eMinus }

// ============================================================
// SECTION 4.5: IMAGINARY UNIT
// ============================================================

/// Represents the imaginary unit i = √(-1)
class ImaginaryExpr extends Expr {
  ImaginaryExpr();

  /// Singleton instance
  static final ImaginaryExpr i = ImaginaryExpr();

  @override
  Expr simplify() => this;

  @override
  double toDouble() => double.nan; // i has no real value

  @override
  bool structurallyEquals(Expr other) => other is ImaginaryExpr;

  @override
  String get termSignature => 'i:1';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => false;

  @override
  bool get isOne => false;

  @override
  bool get isRational => false;

  @override
  bool get isInteger => false;

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() => [LiteralNode(text: 'i')];

  @override
  bool get hasImaginary => true;

  @override
  Expr copy() => ImaginaryExpr();

  @override
  String toString() => 'i';
}

// ============================================================
// SECTION 5: SUM EXPRESSION
// ============================================================

// ============================================================
// SECTION 5: SUM EXPRESSION
// ============================================================

/// Represents a sum of terms: a + b + c + .
class SumExpr extends Expr {
  final List<Expr> terms;

  SumExpr(this.terms);

  @override
  bool get hasImaginary => terms.any((t) => t.hasImaginary);

  @override
  Expr simplify() {
    if (terms.isEmpty) return IntExpr.zero;
    if (terms.length == 1) return terms[0].simplify();

    // Step 1: Simplify all terms and flatten nested sums
    List<Expr> flat = [];
    for (Expr term in terms) {
      Expr simplified = term.simplify();
      if (simplified is SumExpr) {
        flat.addAll(simplified.terms);
      } else if (!simplified.isZero) {
        flat.add(simplified);
      }
    }

    if (flat.isEmpty) return IntExpr.zero;
    if (flat.length == 1) return flat[0];

    // Step 2: Group by signature, tracking first occurrence position
    Map<String, List<Expr>> groups = {};
    Map<String, int> firstOccurrence = {};

    for (int i = 0; i < flat.length; i++) {
      Expr term = flat[i];
      String sig = term.termSignature;

      if (!groups.containsKey(sig)) {
        groups[sig] = [];
        firstOccurrence[sig] = i;
      }
      groups[sig]!.add(term);
    }

    // Step 3: Combine each group
    Map<String, Expr> combinedTerms = {};

    for (var entry in groups.entries) {
      String sig = entry.key;
      List<Expr> group = entry.value;

      if (group.length == 1) {
        combinedTerms[sig] = group[0];
      } else {
        // Sum the coefficients
        Expr coeffSum = _sumCoefficientsHelper(group);

        if (coeffSum.isZero) {
          continue; // Terms cancel - skip
        }

        Expr base = group[0].baseExpr;

        if (base.isOne) {
          combinedTerms[sig] = coeffSum;
        } else if (coeffSum.isOne) {
          combinedTerms[sig] = base;
        } else if (coeffSum is IntExpr && coeffSum.value == -BigInt.one) {
          combinedTerms[sig] = base.negate();
        } else {
          combinedTerms[sig] = ProdExpr([coeffSum, base]).simplify();
        }
      }
    }

    // Step 4: Build result list ordered by first occurrence
    List<MapEntry<String, int>> sortedByPosition =
        firstOccurrence.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    List<Expr> result = [];
    for (var entry in sortedByPosition) {
      String sig = entry.key;
      Expr? combined = combinedTerms[sig];
      if (combined != null && !combined.isZero) {
        result.add(combined);
      }
    }

    if (result.isEmpty) return IntExpr.zero;
    if (result.length == 1) return result[0];

    // Step 5: Sort so real terms come before imaginary terms
    result = _sortRealBeforeImaginary(result);

    // Step 6: Try to factor common symbolic factors across terms
    final Expr? factored = _tryFactorCommon(result);
    if (factored != null) return factored;

    return SumExpr(result);
  }

  /// Sort terms so real parts come before imaginary parts
  List<Expr> _sortRealBeforeImaginary(List<Expr> terms) {
    List<Expr> realTerms = [];
    List<Expr> imaginaryTerms = [];

    for (Expr term in terms) {
      if (term.hasImaginary) {
        imaginaryTerms.add(term);
      } else {
        realTerms.add(term);
      }
    }

    return [...realTerms, ...imaginaryTerms];
  }

  bool _containsIntegrationConstant(Expr expr) {
    if (expr is VarExpr) {
      return _isIntegrationConstantVariable(expr.name);
    }
    if (expr is SumExpr) {
      return expr.terms.any(_containsIntegrationConstant);
    }
    if (expr is ProdExpr) {
      return expr.factors.any(_containsIntegrationConstant);
    }
    if (expr is DivExpr) {
      return _containsIntegrationConstant(expr.numerator) ||
          _containsIntegrationConstant(expr.denominator);
    }
    if (expr is PowExpr) {
      return _containsIntegrationConstant(expr.base) ||
          _containsIntegrationConstant(expr.exponent);
    }
    if (expr is RootExpr) {
      return _containsIntegrationConstant(expr.radicand) ||
          _containsIntegrationConstant(expr.index);
    }
    if (expr is LogExpr) {
      return _containsIntegrationConstant(expr.base) ||
          _containsIntegrationConstant(expr.argument);
    }
    if (expr is TrigExpr) {
      return _containsIntegrationConstant(expr.argument);
    }
    if (expr is AbsExpr) {
      return _containsIntegrationConstant(expr.operand);
    }
    return false;
  }

  bool _isIntegrationConstantVariable(String name) {
    return RegExp(r'^c[\u2080-\u2089]+$').hasMatch(name);
  }

  Expr? _tryFactorCommon(List<Expr> terms) {
    if (terms.length < 2) return null;

    final List<_FactorTerm> termData =
        terms.map(_splitTermForFactoring).toList();

    final Set<String> allVars = {};
    for (final term in termData) {
      allVars.addAll(term.varPowers.keys);
    }
    if (allVars.length < 2) return null;

    final Map<String, BigInt> commonVarPowers = Map<String, BigInt>.from(
      termData.first.varPowers,
    );

    for (int i = 1; i < termData.length; i++) {
      final Map<String, BigInt> powers = termData[i].varPowers;
      for (final key in commonVarPowers.keys.toList()) {
        final BigInt other = powers[key] ?? BigInt.zero;
        final BigInt minExp =
            other < commonVarPowers[key]! ? other : commonVarPowers[key]!;
        if (minExp == BigInt.zero) {
          commonVarPowers.remove(key);
        } else {
          commonVarPowers[key] = minExp;
        }
      }
    }

    Map<String, int> commonOtherCounts = _countFactorSignatures(
      termData.first.otherFactors,
    );
    for (int i = 1; i < termData.length; i++) {
      final Map<String, int> counts = _countFactorSignatures(
        termData[i].otherFactors,
      );
      for (final key in commonOtherCounts.keys.toList()) {
        final int minCount = math.min(
          commonOtherCounts[key]!,
          counts[key] ?? 0,
        );
        if (minCount == 0) {
          commonOtherCounts.remove(key);
        } else {
          commonOtherCounts[key] = minCount;
        }
      }
    }

    if (commonVarPowers.isEmpty && commonOtherCounts.isEmpty) {
      return null;
    }

    final List<Expr> commonFactors = [];
    final Set<String> usedVars = {};
    final Map<String, int> remainingOthers = Map<String, int>.from(
      commonOtherCounts,
    );

    for (final factor in termData.first.factors) {
      final String? varName = _variableName(factor);
      if (varName != null && !usedVars.contains(varName)) {
        final BigInt? exp = commonVarPowers[varName];
        if (exp != null && exp > BigInt.zero) {
          commonFactors.add(_buildVarFactor(varName, exp));
          usedVars.add(varName);
        }
        continue;
      }

      final String sig = factor.termSignature;
      final int? count = remainingOthers[sig];
      if (count != null && count > 0) {
        commonFactors.add(factor);
        remainingOthers[sig] = count - 1;
      }
    }

    if (commonFactors.isEmpty) return null;

    // Keep expanded forms for expressions carrying integration constants,
    // e.g., x^3/6 + c₀x + c₁ instead of x*(x^2/6 + c₀) + c₁.
    if (commonFactors.length == 1 &&
        terms.any((term) => _containsIntegrationConstant(term))) {
      return null;
    }

    final Expr commonExpr =
        commonFactors.length == 1
            ? commonFactors.first
            : ProdExpr(commonFactors);

    final List<Expr> newTerms = [];
    for (final term in termData) {
      final Map<String, BigInt> remainderVarPowers = {};
      term.varPowers.forEach((name, exp) {
        final BigInt common = commonVarPowers[name] ?? BigInt.zero;
        final BigInt rem = exp - common;
        if (rem > BigInt.zero) {
          remainderVarPowers[name] = rem;
        }
      });

      final Map<String, int> removeOthers = Map<String, int>.from(
        commonOtherCounts,
      );
      final Set<String> usedVarInTerm = {};
      final List<Expr> remainderFactors = [];

      for (final factor in term.factors) {
        final String? varName = _variableName(factor);
        if (varName != null && !usedVarInTerm.contains(varName)) {
          usedVarInTerm.add(varName);
          final BigInt? remExp = remainderVarPowers[varName];
          if (remExp != null && remExp > BigInt.zero) {
            remainderFactors.add(_buildVarFactor(varName, remExp));
          }
          continue;
        }

        final String sig = factor.termSignature;
        final int? count = removeOthers[sig];
        if (count != null && count > 0) {
          removeOthers[sig] = count - 1;
          continue;
        }
        remainderFactors.add(factor);
      }

      Expr remainder;
      if (remainderFactors.isEmpty) {
        remainder = IntExpr.one;
      } else if (remainderFactors.length == 1) {
        remainder = remainderFactors.first;
      } else {
        remainder = ProdExpr(remainderFactors);
      }

      final Expr coeff = term.coefficient;
      Expr termExpr;
      if (remainder.isOne) {
        termExpr = coeff;
      } else if (coeff.isOne) {
        termExpr = remainder;
      } else {
        termExpr = ProdExpr([coeff, remainder]);
      }

      if (!termExpr.isZero) {
        newTerms.add(termExpr);
      }
    }

    if (newTerms.isEmpty) return null;

    final Expr inner =
        newTerms.length == 1 ? newTerms.first : SumExpr(newTerms);

    if (inner.isOne) return commonExpr;
    if (commonExpr.isOne) return inner;

    final List<Expr> finalFactors = [];
    if (commonExpr is ProdExpr) {
      finalFactors.addAll(commonExpr.factors);
    } else {
      finalFactors.add(commonExpr);
    }
    if (inner is ProdExpr) {
      finalFactors.addAll(inner.factors);
    } else {
      finalFactors.add(inner);
    }
    return ProdExpr(finalFactors);
  }

  _FactorTerm _splitTermForFactoring(Expr term) {
    final Expr coeff = term.coefficient;
    final Expr base = term.baseExpr;
    final List<Expr> factors = _extractBaseFactors(base);

    final Map<String, BigInt> varPowers = {};
    final List<Expr> otherFactors = [];

    for (final factor in factors) {
      final String? varName = _variableName(factor);
      final BigInt? exp = _variableExponent(factor);
      if (varName != null && exp != null) {
        varPowers[varName] = (varPowers[varName] ?? BigInt.zero) + exp;
      } else {
        otherFactors.add(factor);
      }
    }

    return _FactorTerm(
      coefficient: coeff,
      factors: factors,
      varPowers: varPowers,
      otherFactors: otherFactors,
    );
  }

  List<Expr> _extractBaseFactors(Expr base) {
    if (base is ProdExpr) return base.factors;
    if (base.isOne) return <Expr>[];
    return <Expr>[base];
  }

  String? _variableName(Expr factor) {
    if (factor is VarExpr) return factor.name;
    if (factor is PowExpr &&
        factor.base is VarExpr &&
        factor.exponent is IntExpr) {
      final BigInt exp = (factor.exponent as IntExpr).value;
      if (exp > BigInt.zero) {
        return (factor.base as VarExpr).name;
      }
    }
    return null;
  }

  BigInt? _variableExponent(Expr factor) {
    if (factor is VarExpr) return BigInt.one;
    if (factor is PowExpr &&
        factor.base is VarExpr &&
        factor.exponent is IntExpr) {
      final BigInt exp = (factor.exponent as IntExpr).value;
      if (exp > BigInt.zero) return exp;
    }
    return null;
  }

  Expr _buildVarFactor(String name, BigInt exponent) {
    if (exponent == BigInt.one) return VarExpr(name);
    return PowExpr(VarExpr(name), IntExpr(exponent));
  }

  Map<String, int> _countFactorSignatures(List<Expr> factors) {
    final Map<String, int> counts = {};
    for (final factor in factors) {
      final String sig = factor.termSignature;
      counts[sig] = (counts[sig] ?? 0) + 1;
    }
    return counts;
  }

  /// Sum the coefficients of a list of like terms
  Expr _sumCoefficientsHelper(List<Expr> termList) {
    Expr sum = IntExpr.zero;
    for (Expr term in termList) {
      Expr coeff = term.coefficient;
      if (sum is IntExpr && coeff is IntExpr) {
        sum = IntExpr(sum.value + coeff.value);
      } else if (sum is IntExpr && coeff is FracExpr) {
        sum = coeff.add(sum);
      } else if (sum is FracExpr && coeff is IntExpr) {
        sum = sum.add(coeff);
      } else if (sum is FracExpr && coeff is FracExpr) {
        sum = sum.add(coeff);
      } else {
        sum = SumExpr([sum, coeff]).simplify();
      }
    }
    return sum;
  }

  @override
  double toDouble() {
    double sum = 0;
    for (Expr term in terms) {
      sum += term.toDouble();
    }
    return sum;
  }

  @override
  bool structurallyEquals(Expr other) {
    if (other is! SumExpr) return false;
    if (other.terms.length != terms.length) return false;
    for (int i = 0; i < terms.length; i++) {
      if (!terms[i].structurallyEquals(other.terms[i])) return false;
    }
    return true;
  }

  @override
  String get termSignature =>
      'sum:${terms.map((t) => t.termSignature).join('+')}';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => terms.every((t) => t.isZero);

  @override
  bool get isOne => false;

  @override
  bool get isRational => terms.every((t) => t.isRational);

  @override
  bool get isInteger => false;

  @override
  Expr negate() => SumExpr(terms.map((t) => t.negate()).toList());

  @override
  List<MathNode> toMathNode() {
    if (terms.isEmpty) return [LiteralNode(text: '0')];

    // Sort terms: real before imaginary for display
    List<Expr> sortedTerms = _sortRealBeforeImaginary(terms);

    List<MathNode> nodes = [];

    for (int i = 0; i < sortedTerms.length; i++) {
      Expr term = sortedTerms[i];

      bool isNegative = _isNegativeTerm(term);
      Expr absTerm = isNegative ? _absoluteTerm(term) : term;

      if (i == 0) {
        if (isNegative) {
          nodes.add(LiteralNode(text: '−'));
        }
        nodes.addAll(absTerm.toMathNode());
      } else {
        if (isNegative) {
          nodes.add(LiteralNode(text: '−'));
        } else {
          nodes.add(LiteralNode(text: '+'));
        }
        nodes.addAll(absTerm.toMathNode());
      }
    }

    return nodes;
  }

  /// Check if a term is negative
  bool _isNegativeTerm(Expr term) {
    if (term is IntExpr) return term.value < BigInt.zero;
    if (term is FracExpr) return term.numerator.value < BigInt.zero;
    if (term is ProdExpr && term.factors.isNotEmpty) {
      Expr coeff = term.coefficient;
      if (coeff is IntExpr) return coeff.value < BigInt.zero;
      if (coeff is FracExpr) return coeff.numerator.value < BigInt.zero;
    }
    if (term is DivExpr) {
      if (term.numerator is IntExpr) {
        return (term.numerator as IntExpr).value < BigInt.zero;
      }
      if (term.numerator is FracExpr) {
        return (term.numerator as FracExpr).numerator.value < BigInt.zero;
      }
    }
    return false;
  }

  /// Get absolute value of a term
  Expr _absoluteTerm(Expr term) {
    if (term is IntExpr) return IntExpr(term.value.abs());
    if (term is FracExpr) {
      return FracExpr(IntExpr(term.numerator.value.abs()), term.denominator);
    }
    if (term is ProdExpr && term.factors.isNotEmpty) {
      Expr coeff = term.coefficient;
      Expr base = term.baseExpr;

      Expr absCoeff;
      if (coeff is IntExpr) {
        absCoeff = IntExpr(coeff.value.abs());
      } else if (coeff is FracExpr) {
        absCoeff = FracExpr(
          IntExpr(coeff.numerator.value.abs()),
          coeff.denominator,
        );
      } else {
        absCoeff = coeff;
      }

      if (absCoeff.isOne) return base;
      return ProdExpr([absCoeff, base]);
    }
    if (term is DivExpr) {
      if (term.numerator is IntExpr &&
          (term.numerator as IntExpr).value < BigInt.zero) {
        return DivExpr(
          IntExpr((term.numerator as IntExpr).value.abs()),
          term.denominator,
        );
      }
      if (term.numerator is FracExpr &&
          (term.numerator as FracExpr).numerator.value < BigInt.zero) {
        return DivExpr(
          FracExpr(
            IntExpr((term.numerator as FracExpr).numerator.value.abs()),
            (term.numerator as FracExpr).denominator,
          ),
          term.denominator,
        );
      }
    }
    return term;
  }

  @override
  Expr copy() => SumExpr(terms.map((t) => t.copy()).toList());

  @override
  String toString() => terms.map((t) => t.toString()).join(' + ');
}

class _FactorTerm {
  final Expr coefficient;
  final List<Expr> factors;
  final Map<String, BigInt> varPowers;
  final List<Expr> otherFactors;

  const _FactorTerm({
    required this.coefficient,
    required this.factors,
    required this.varPowers,
    required this.otherFactors,
  });
}

// ============================================================
// SECTION 6: PRODUCT EXPRESSION
// ============================================================

/// Represents a product of factors: a * b * c * ...
class ProdExpr extends Expr {
  final List<Expr> factors;

  ProdExpr(this.factors);

  @override
  bool get hasImaginary => factors.any((f) => f.hasImaginary);

  @override
  Expr simplify() {
    if (factors.isEmpty) return IntExpr.one;
    if (factors.length == 1) return factors[0].simplify();

    // Step 1: Simplify all factors and flatten nested products
    List<Expr> flat = [];
    Expr numericPart = IntExpr.one; // Accumulate numeric factors

    for (Expr factor in factors) {
      Expr simplified = factor.simplify();

      // Check for zero - entire product is zero
      if (simplified.isZero) return IntExpr.zero;

      // Skip ones
      if (simplified.isOne) continue;

      if (simplified is ProdExpr) {
        // Flatten nested product
        for (Expr f in simplified.factors) {
          if (f.isRational) {
            numericPart = _multiplyRational(numericPart, f);
          } else {
            flat.add(f);
          }
        }
      } else if (simplified.isRational) {
        numericPart = _multiplyRational(numericPart, simplified);
      } else {
        flat.add(simplified);
      }
    }

    // Check if numeric part is zero
    if (numericPart.isZero) return IntExpr.zero;

    // Add numeric part at front if not 1
    if (!numericPart.isOne) {
      flat.insert(0, numericPart);
    }

    if (flat.isEmpty) return IntExpr.one;
    if (flat.length == 1) return flat[0];

    // Step 1.5: Merge a leading rational factor into a division with a rational denominator
    if (flat.isNotEmpty && flat.first.isRational) {
      final int divIndex = flat.indexWhere((f) => f is DivExpr);
      if (divIndex > 0) {
        final DivExpr div = flat[divIndex] as DivExpr;
        final Expr den = div.denominator.simplify();
        if (den is IntExpr || den is FracExpr) {
          final Expr coeff = flat.removeAt(0);
          // divIndex shifted left by 1 after removing coeff
          flat.removeAt(divIndex - 1);
          final Expr newNumerator = ProdExpr([coeff, div.numerator]).simplify();
          final Expr merged = DivExpr(newNumerator, den).simplify();
          flat.insert(0, merged);

          if (flat.length == 1) return flat[0];
        }
      }
    }

    // Step 1.6: Pull rational denominators out of division factors.
    // This lets expressions like x * (x^2/6) simplify to x^3/6.
    Expr pulledRational = IntExpr.one;
    List<Expr> rewritten = [];
    bool extractedRationalDivisor = false;

    for (final factor in flat) {
      if (factor is DivExpr) {
        final Expr den = factor.denominator.simplify();
        if (den is IntExpr || den is FracExpr) {
          final Expr reciprocal = DivExpr(IntExpr.one, den).simplify();
          if (reciprocal is IntExpr || reciprocal is FracExpr) {
            pulledRational = _multiplyRational(pulledRational, reciprocal);
            rewritten.add(factor.numerator);
            extractedRationalDivisor = true;
            continue;
          }
        }
      }
      rewritten.add(factor);
    }

    if (extractedRationalDivisor) {
      if (!pulledRational.isOne) {
        rewritten.insert(0, pulledRational);
      }
      return ProdExpr(rewritten).simplify();
    }

    // Step 2: Distribute over sums if any factor is a SumExpr
    // Find all SumExpr indices
    List<int> sumIndices = [];
    for (int i = 0; i < flat.length; i++) {
      if (flat[i] is SumExpr) sumIndices.add(i);
    }

    // Handle two or more SumExprs with FOIL-style expansion: (a+b)*(c+d) = ac + ad + bc + bd
    if (sumIndices.length >= 2) {
      SumExpr first = flat[sumIndices[0]] as SumExpr;
      SumExpr second = flat[sumIndices[1]] as SumExpr;

      List<Expr> otherFactors = [];
      for (int i = 0; i < flat.length; i++) {
        if (i != sumIndices[0] && i != sumIndices[1]) {
          otherFactors.add(flat[i]);
        }
      }

      List<Expr> expandedTerms = [];
      for (Expr a in first.terms) {
        for (Expr b in second.terms) {
          if (otherFactors.isEmpty) {
            expandedTerms.add(ProdExpr([a, b]).simplify());
          } else {
            expandedTerms.add(ProdExpr([a, b, ...otherFactors]).simplify());
          }
        }
      }

      return SumExpr(expandedTerms).simplify();
    }

    // Handle single SumExpr: (a + b) * c = a*c + b*c
    if (sumIndices.length == 1) {
      int sumIndex = sumIndices[0];
      SumExpr sumFactor = flat[sumIndex] as SumExpr;
      List<Expr> otherFactors = [
        ...flat.sublist(0, sumIndex),
        ...flat.sublist(sumIndex + 1),
      ];

      // Distribute: multiply each term in the sum by the other factors
      List<Expr> distributedTerms = [];
      for (Expr term in sumFactor.terms) {
        if (otherFactors.isEmpty) {
          distributedTerms.add(term);
        } else {
          Expr product = ProdExpr([term, ...otherFactors]).simplify();
          distributedTerms.add(product);
        }
      }

      return SumExpr(distributedTerms).simplify();
    }

    // Step 3: Combine like bases (e.g., √2 * √2 = 2, i * i = -1)
    flat = _combineLikeBases(flat);

    if (flat.isEmpty) return IntExpr.one;

    // Step 3.5: Ensure all rationals are combined (including those from Step 3)
    List<Expr> finalFactors = [];
    Expr finalNumeric = IntExpr.one;
    for (Expr f in flat) {
      if (f.isRational) {
        finalNumeric = _multiplyRational(finalNumeric, f);
      } else {
        finalFactors.add(f);
      }
    }

    if (!finalNumeric.isOne || finalFactors.isEmpty) {
      finalFactors.insert(0, finalNumeric);
    }

    if (finalFactors.isEmpty) return IntExpr.one;
    if (finalFactors.length == 1 && finalFactors[0].isOne) return IntExpr.one;
    if (finalFactors.length == 1) return finalFactors[0];

    // Step 4: Sort for canonical order
    finalFactors.sort((a, b) => _compareFactors(a, b));

    return ProdExpr(finalFactors);
  }

  /// Multiply two rational expressions
  static Expr _multiplyRational(Expr a, Expr b) {
    if (a is IntExpr && b is IntExpr) {
      return IntExpr(a.value * b.value);
    }
    if (a is IntExpr && b is FracExpr) {
      return FracExpr(
        IntExpr(a.value * b.numerator.value),
        b.denominator,
      ).simplify();
    }
    if (a is FracExpr && b is IntExpr) {
      return FracExpr(
        IntExpr(a.numerator.value * b.value),
        a.denominator,
      ).simplify();
    }
    if (a is FracExpr && b is FracExpr) {
      return FracExpr(
        IntExpr(a.numerator.value * b.numerator.value),
        IntExpr(a.denominator.value * b.denominator.value),
      ).simplify();
    }
    return ProdExpr([a, b]);
  }

  /// Combine factors with the same base (e.g., √2 * √3 = √6, √2 * √2 = 2)
  static List<Expr> _combineLikeBases(List<Expr> factors) {
    // Handle imaginary units first: i * i = -1
    int imaginaryCount = 0;
    List<Expr> nonImaginary = [];

    for (Expr f in factors) {
      if (f is ImaginaryExpr) {
        imaginaryCount++;
      } else {
        nonImaginary.add(f);
      }
    }

    // i^1 = i, i^2 = -1, i^3 = -i, i^4 = 1, i^5 = i, ...
    int mod = imaginaryCount % 4;
    Expr imaginaryResult;
    switch (mod) {
      case 0:
        imaginaryResult = IntExpr.one;
        break;
      case 1:
        imaginaryResult = ImaginaryExpr.i;
        break;
      case 2:
        imaginaryResult = IntExpr.negOne;
        break;
      case 3:
        imaginaryResult = ProdExpr([IntExpr.negOne, ImaginaryExpr.i]);
        break;
      default:
        imaginaryResult = IntExpr.one;
    }

    // If we have imaginary result, add it
    if (imaginaryCount > 0 && !imaginaryResult.isOne) {
      if (imaginaryResult is ProdExpr) {
        // -i case: add factors separately
        for (Expr f in imaginaryResult.factors) {
          nonImaginary.add(f);
        }
      } else {
        nonImaginary.add(imaginaryResult);
      }
    }

    // Group RootExpr with same index
    Map<int, List<RootExpr>> rootGroups = {};
    List<Expr> others = [];

    for (Expr f in nonImaginary) {
      if (f is RootExpr && f.index is IntExpr) {
        int idx = (f.index as IntExpr).value.toInt();
        rootGroups.putIfAbsent(idx, () => []);
        rootGroups[idx]!.add(f);
      } else {
        others.add(f);
      }
    }

    // Combine roots with same index: √a * √b = √(ab)
    List<Expr> result = List.from(others);

    for (var entry in rootGroups.entries) {
      int index = entry.key;
      List<RootExpr> roots = entry.value;

      if (roots.length == 1) {
        result.add(roots[0]);
      } else {
        // Multiply all radicands
        Expr combinedRadicand = IntExpr.one;
        for (RootExpr r in roots) {
          combinedRadicand =
              ProdExpr([combinedRadicand, r.radicand]).simplify();
        }
        // Create new root and simplify
        result.add(RootExpr(combinedRadicand, IntExpr.from(index)).simplify());
      }
    }

    // Combine like variable bases (e.g., y*y = y^2, y^2*y = y^3)
    Map<String, BigInt> varPowers = {};
    List<Expr> othersCombined = [];

    for (Expr f in result) {
      if (f is VarExpr) {
        varPowers[f.name] = (varPowers[f.name] ?? BigInt.zero) + BigInt.one;
        continue;
      }
      if (f is PowExpr && f.base is VarExpr && f.exponent is IntExpr) {
        final String name = (f.base as VarExpr).name;
        final BigInt exp = (f.exponent as IntExpr).value;
        varPowers[name] = (varPowers[name] ?? BigInt.zero) + exp;
        continue;
      }
      othersCombined.add(f);
    }

    for (var entry in varPowers.entries) {
      final BigInt exp = entry.value;
      if (exp == BigInt.zero) continue;
      final Expr base = VarExpr(entry.key);
      if (exp == BigInt.one) {
        othersCombined.add(base);
      } else {
        othersCombined.add(PowExpr(base, IntExpr(exp)).simplify());
      }
    }

    return othersCombined;
  }

  /// Compare factors for canonical ordering
  static int _compareFactors(Expr a, Expr b) {
    // Order: numbers first, then roots, then others
    if (a.isRational && !b.isRational) return -1;
    if (!a.isRational && b.isRational) return 1;
    if (a is RootExpr && b is! RootExpr) return -1;
    if (a is! RootExpr && b is RootExpr) return 1;
    return a.toString().compareTo(b.toString());
  }

  @override
  double toDouble() {
    double prod = 1;
    for (Expr factor in factors) {
      prod *= factor.toDouble();
    }
    return prod;
  }

  @override
  bool structurallyEquals(Expr other) {
    if (other is! ProdExpr) return false;
    if (other.factors.length != factors.length) return false;
    for (int i = 0; i < factors.length; i++) {
      if (!factors[i].structurallyEquals(other.factors[i])) return false;
    }
    return true;
  }

  @override
  String get termSignature {
    // Signature excludes numeric coefficient
    List<String> nonNumeric = [];
    for (Expr f in factors) {
      if (!f.isRational) {
        nonNumeric.add(f.termSignature);
      }
    }
    if (nonNumeric.isEmpty) return 'int:1';
    // KEY FIX: Single non-numeric factor - use its signature directly
    if (nonNumeric.length == 1) return nonNumeric[0];
    return 'prod:${nonNumeric.join('*')}';
  }

  @override
  Expr get coefficient {
    // Return the numeric part
    Expr coeff = IntExpr.one;
    for (Expr f in factors) {
      if (f.isRational) {
        coeff = _multiplyRational(coeff, f);
      }
    }
    return coeff;
  }

  @override
  Expr get baseExpr {
    // Return the non-numeric part
    List<Expr> nonNumeric = factors.where((f) => !f.isRational).toList();
    if (nonNumeric.isEmpty) return IntExpr.one;
    if (nonNumeric.length == 1) return nonNumeric[0];
    return ProdExpr(nonNumeric);
  }

  @override
  bool get isZero => factors.any((f) => f.isZero);

  @override
  bool get isOne => factors.every((f) => f.isOne);

  @override
  bool get isRational => factors.every((f) => f.isRational);

  @override
  bool get isInteger => false;

  @override
  Expr negate() {
    List<Expr> newFactors = List.from(factors);
    if (newFactors.isNotEmpty && newFactors[0].isRational) {
      newFactors[0] = newFactors[0].negate();
    } else {
      newFactors.insert(0, IntExpr.negOne);
    }
    return ProdExpr(newFactors);
  }

  static bool _isVariableLikeFactor(Expr expr) {
    return expr is VarExpr || (expr is PowExpr && expr.base is VarExpr);
  }

  static bool _isImplicitCoeffTarget(Expr expr) {
    return expr is RootExpr ||
        expr is ConstExpr ||
        expr is ImaginaryExpr ||
        _isVariableLikeFactor(expr);
  }

  static bool _isImplicitMultiplicationPair(Expr left, Expr right) {
    if (left.isRational) {
      return _isImplicitCoeffTarget(right);
    }

    // Keep symbolic products compact: c₀x, c₀xy, x^2y, etc.
    if (_isVariableLikeFactor(left) && _isVariableLikeFactor(right)) {
      return true;
    }

    return false;
  }

  @override
  List<MathNode> toMathNode() {
    if (factors.isEmpty) return [LiteralNode(text: '1')];

    List<MathNode> nodes = [];

    for (int i = 0; i < factors.length; i++) {
      if (i > 0) {
        // Add multiplication sign between factors, except for implied products.
        bool implicit = _isImplicitMultiplicationPair(
          factors[i - 1],
          factors[i],
        );
        if (!implicit) {
          nodes.add(LiteralNode(text: '·'));
        }
      }
      nodes.addAll(factors[i].toMathNode());
    }

    return nodes;
  }

  @override
  Expr copy() => ProdExpr(factors.map((f) => f.copy()).toList());

  @override
  String toString() => factors.map((f) => f.toString()).join('·');
}

// ============================================================
// SECTION 7: POWER EXPRESSION
// ============================================================

/// Represents base^exponent
class PowExpr extends Expr {
  final Expr base;
  final Expr exponent;

  PowExpr(this.base, this.exponent);

  @override
  Expr simplify() {
    Expr b = base.simplify();
    Expr e = exponent.simplify();

    // x^0 = 1
    if (e.isZero) return IntExpr.one;

    // x^1 = x
    if (e.isOne) return b;

    // 0^n = 0 (for positive n)
    if (b.isZero && !e.isZero) return IntExpr.zero;

    // 1^n = 1
    if (b.isOne) return IntExpr.one;

    // Handle e^(ix) = cos(x) + i*sin(x) (Euler's formula)
    if (b is ConstExpr && b.type == ConstType.e && e.hasImaginary) {
      Expr? eulerResult = _tryEulerFormula(e);
      if (eulerResult != null) {
        return eulerResult.simplify();
      }
    }

    // Integer^Integer: compute if reasonable
    if (b is IntExpr && e is IntExpr) {
      BigInt baseVal = b.value;
      BigInt expVal = e.value;

      if (expVal > BigInt.zero && expVal.toInt() <= 100) {
        // Compute power for small positive exponents
        return IntExpr(baseVal.pow(expVal.toInt()));
      }

      if (expVal < BigInt.zero) {
        // a^(-n) = 1/a^n
        return FracExpr(
          IntExpr.one,
          IntExpr(baseVal.pow(-expVal.toInt())),
        ).simplify();
      }
    }

    // Fraction^Integer: compute for small integer exponents
    if (b is FracExpr && e is IntExpr) {
      final BigInt expVal = e.value;
      final BigInt absExp = expVal.abs();
      if (absExp <= BigInt.from(100)) {
        if (expVal.isNegative && b.numerator.value == BigInt.zero) {
          return PowExpr(b, e);
        }
        final int pow = absExp.toInt();
        final BigInt numBase =
            expVal.isNegative ? b.denominator.value : b.numerator.value;
        final BigInt denBase =
            expVal.isNegative ? b.numerator.value : b.denominator.value;
        return FracExpr(
          IntExpr(numBase.pow(pow)),
          IntExpr(denBase.pow(pow)),
        ).simplify();
      }
    }

    // (a^m)^n = a^(m*n)
    if (b is PowExpr) {
      Expr newExp = ProdExpr([b.exponent, e]).simplify();
      return PowExpr(b.base, newExp).simplify();
    }

    // Fractional exponent: a^(1/n) = nth root of a
    if (e is FracExpr) {
      Expr eSimp = e.simplify();
      if (eSimp is FracExpr && eSimp.numerator.value == BigInt.one) {
        // a^(1/n) = RootExpr(a, n)
        return RootExpr(b, eSimp.denominator).simplify();
      }
      if (eSimp is FracExpr) {
        // a^(m/n) = RootExpr(a^m, n)
        Expr raised = PowExpr(b, eSimp.numerator).simplify();
        return RootExpr(raised, eSimp.denominator).simplify();
      }
    }

    return PowExpr(b, e);
  }

  /// Try to apply Euler's formula: e^(ix) = cos(x) + i*sin(x)
  /// Also handles e^(a + ix) = e^a * (cos(x) + i*sin(x))
  Expr? _tryEulerFormula(Expr exponent) {
    // First, try to split the exponent into real and imaginary parts
    var parts = _splitRealAndImaginary(exponent);
    if (parts == null) return null;

    Expr? realPart = parts.$1;
    Expr? imagCoefficient = parts.$2; // This is x in ix

    // If there's no imaginary part, this isn't for Euler's formula
    if (imagCoefficient == null) return null;

    // Build cos(x) + i*sin(x)
    Expr eulerPart = SumExpr([
      TrigExpr(TrigFunc.cos, imagCoefficient),
      ProdExpr([ImaginaryExpr.i, TrigExpr(TrigFunc.sin, imagCoefficient)]),
    ]);

    // If there's a real part, multiply by e^(real)
    if (realPart != null && !realPart.isZero) {
      Expr eToReal = PowExpr(ConstExpr.e, realPart);
      return ProdExpr([eToReal, eulerPart]);
    }

    return eulerPart;
  }

  /// Split an expression into real and imaginary coefficient parts
  /// Returns (realPart, imaginaryCoefficient) where the full expression = realPart + i * imaginaryCoefficient
  /// Returns null if unable to parse
  (Expr?, Expr?)? _splitRealAndImaginary(Expr expr) {
    // Case 1: Just i alone -> (null, 1)
    if (expr is ImaginaryExpr) {
      return (null, IntExpr.one);
    }

    // Case 2: Product containing i (could be i*π, π*i, 2*i*π, etc.)
    if (expr is ProdExpr) {
      bool hasI = false;
      List<Expr> nonIFactors = [];

      for (Expr factor in expr.factors) {
        if (factor is ImaginaryExpr) {
          hasI = true;
        } else {
          nonIFactors.add(factor);
        }
      }

      if (hasI) {
        // The imaginary coefficient is the product of all non-i factors
        Expr imagCoeff;
        if (nonIFactors.isEmpty) {
          imagCoeff = IntExpr.one;
        } else if (nonIFactors.length == 1) {
          imagCoeff = nonIFactors[0];
        } else {
          imagCoeff = ProdExpr(nonIFactors).simplify();
        }
        return (null, imagCoeff);
      }

      // No i in product - it's purely real
      return (expr, null);
    }

    // Case 3: Sum - split into real and imaginary terms
    if (expr is SumExpr) {
      List<Expr> realTerms = [];
      List<Expr> imagCoefficients = [];

      for (Expr term in expr.terms) {
        var termParts = _splitRealAndImaginary(term);
        if (termParts == null) return null;

        if (termParts.$1 != null && !termParts.$1!.isZero) {
          realTerms.add(termParts.$1!);
        }
        if (termParts.$2 != null && !termParts.$2!.isZero) {
          imagCoefficients.add(termParts.$2!);
        }
      }

      Expr? realPart;
      if (realTerms.isEmpty) {
        realPart = null;
      } else if (realTerms.length == 1) {
        realPart = realTerms[0];
      } else {
        realPart = SumExpr(realTerms).simplify();
      }

      Expr? imagCoeff;
      if (imagCoefficients.isEmpty) {
        imagCoeff = null;
      } else if (imagCoefficients.length == 1) {
        imagCoeff = imagCoefficients[0];
      } else {
        imagCoeff = SumExpr(imagCoefficients).simplify();
      }

      return (realPart, imagCoeff);
    }

    // Case 4: Division containing i in numerator
    if (expr is DivExpr) {
      if (expr.numerator.hasImaginary && !expr.denominator.hasImaginary) {
        var numParts = _splitRealAndImaginary(expr.numerator);
        if (numParts != null) {
          Expr? newReal =
              numParts.$1 != null
                  ? DivExpr(numParts.$1!, expr.denominator).simplify()
                  : null;
          Expr? newImag =
              numParts.$2 != null
                  ? DivExpr(numParts.$2!, expr.denominator).simplify()
                  : null;
          return (newReal, newImag);
        }
      }
      // Real division
      if (!expr.hasImaginary) {
        return (expr, null);
      }
    }

    // Case 5: Negated imaginary
    if (expr is ProdExpr && expr.factors.length >= 2) {
      // Check for patterns like -1 * i * something
      bool hasNegOne = false;
      bool hasI = false;
      List<Expr> others = [];

      for (Expr factor in expr.factors) {
        if (factor is IntExpr && factor.value == -BigInt.one) {
          hasNegOne = true;
        } else if (factor is ImaginaryExpr) {
          hasI = true;
        } else {
          others.add(factor);
        }
      }

      if (hasI) {
        Expr imagCoeff;
        if (others.isEmpty) {
          imagCoeff = hasNegOne ? IntExpr.negOne : IntExpr.one;
        } else if (others.length == 1) {
          imagCoeff = hasNegOne ? others[0].negate() : others[0];
        } else {
          Expr prod = ProdExpr(others).simplify();
          imagCoeff = hasNegOne ? prod.negate() : prod;
        }
        return (null, imagCoeff);
      }
    }

    // Not a form we can handle - check if it has imaginary
    if (expr.hasImaginary) {
      return null;
    }

    // Purely real
    return (expr, null);
  }

  @override
  bool get hasImaginary => base.hasImaginary || exponent.hasImaginary;

  @override
  double toDouble() => realPow(base.toDouble(), exponent.toDouble());

  @override
  bool structurallyEquals(Expr other) {
    return other is PowExpr &&
        base.structurallyEquals(other.base) &&
        exponent.structurallyEquals(other.exponent);
  }

  @override
  String get termSignature {
    Expr simpBase = base.simplify();
    Expr simpExp = exponent.simplify();
    return 'pow:$simpBase^$simpExp';
  }

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => base.isZero;

  @override
  bool get isOne => base.isOne || exponent.isZero;

  @override
  bool get isRational {
    if (base.isRational && exponent is IntExpr) {
      return (exponent as IntExpr).value >= BigInt.zero;
    }
    return false;
  }

  @override
  bool get isInteger {
    if (base is IntExpr && exponent is IntExpr) {
      return (exponent as IntExpr).value >= BigInt.zero;
    }
    return false;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    return [
      ExponentNode(base: base.toMathNode(), power: exponent.toMathNode()),
    ];
  }

  @override
  Expr copy() => PowExpr(base.copy(), exponent.copy());

  @override
  String toString() => '($base)^($exponent)';
}

// ============================================================
// SECTION 8: ROOT EXPRESSION (SURDS)
// ============================================================

/// Represents the nth root of a value: ⁿ√radicand
class RootExpr extends Expr {
  final Expr radicand;
  final Expr index; // 2 for square root, 3 for cube root, etc.

  RootExpr(this.radicand, this.index);

  @override
  bool get hasImaginary => radicand.hasImaginary || index.hasImaginary;

  /// Convenience constructor for square root
  RootExpr.sqrt(this.radicand) : index = IntExpr.two;

  @override
  Expr simplify() {
    Expr rad = radicand.simplify();
    Expr idx = index.simplify();

    // √1 = 1
    if (rad.isOne) return IntExpr.one;

    // √0 = 0
    if (rad.isZero) return IntExpr.zero;

    // Only simplify when index is a positive integer
    if (idx is! IntExpr || idx.value <= BigInt.zero) {
      return RootExpr(rad, idx);
    }

    int n = idx.value.toInt();

    // For integer radicands, extract perfect nth powers
    if (rad is IntExpr) {
      if (n == 2 && rad.value < BigInt.zero) {
        // sqrt(-x) = i * sqrt(x)
        return ProdExpr([
          ImaginaryExpr.i,
          RootExpr.sqrt(IntExpr(rad.value.abs())).simplify(),
        ]).simplify();
      }
      return _simplifyIntegerRoot(rad.value, n);
    }

    // For fraction radicands: √(a/b) = √a / √b
    if (rad is FracExpr) {
      // For square roots, rationalize denominator: √(a/b) = √(ab) / b
      if (n == 2) {
        Expr newRadicand =
            ProdExpr([rad.numerator, rad.denominator]).simplify();
        Expr root = RootExpr.sqrt(newRadicand).simplify();
        return DivExpr(root, rad.denominator).simplify();
      }

      Expr numRoot = RootExpr(rad.numerator, idx).simplify();
      Expr denRoot = RootExpr(rad.denominator, idx).simplify();

      // Return as symbolic division of roots
      return DivExpr(numRoot, denRoot).simplify();
    }

    // For products: √(ab) - already handled by product combination

    return RootExpr(rad, idx);
  }

  /// Simplify √n by extracting perfect square factors
  Expr _simplifyIntegerRoot(BigInt n, int rootIndex) {
    if (n < BigInt.zero && rootIndex % 2 == 0) {
      // Even root of negative number - complex, keep as is for now
      return RootExpr(IntExpr(n), IntExpr.from(rootIndex));
    }

    bool isNegative = n < BigInt.zero;
    n = n.abs();

    // Factor out perfect nth powers
    // e.g., √72 = √(36*2) = 6√2

    Map<BigInt, int> factors = _primeFactorize(n);

    BigInt outsideRoot = BigInt.one;
    BigInt insideRoot = BigInt.one;

    for (var entry in factors.entries) {
      BigInt prime = entry.key;
      int power = entry.value;

      // How many complete groups of rootIndex can we extract?
      int extracted = power ~/ rootIndex;
      int remaining = power % rootIndex;

      // prime^extracted comes outside the root
      if (extracted > 0) {
        outsideRoot *= prime.pow(extracted);
      }

      // prime^remaining stays inside
      if (remaining > 0) {
        insideRoot *= prime.pow(remaining);
      }
    }

    // Handle odd roots of negative numbers
    if (isNegative && rootIndex % 2 == 1) {
      outsideRoot = -outsideRoot;
    }

    if (insideRoot == BigInt.one) {
      // Perfect nth power!
      return IntExpr(outsideRoot);
    }

    if (outsideRoot == BigInt.one) {
      // Nothing to extract
      return RootExpr(IntExpr(insideRoot), IntExpr.from(rootIndex));
    }

    // coefficient * root(insideRoot, rootIndex)
    return ProdExpr([
      IntExpr(outsideRoot),
      RootExpr(IntExpr(insideRoot), IntExpr.from(rootIndex)),
    ]);
  }

  /// Prime factorization of a positive integer
  Map<BigInt, int> _primeFactorize(BigInt n) {
    Map<BigInt, int> factors = {};
    BigInt divisor = BigInt.two;

    while (divisor * divisor <= n) {
      while (n % divisor == BigInt.zero) {
        factors[divisor] = (factors[divisor] ?? 0) + 1;
        n ~/= divisor;
      }
      divisor += BigInt.one;
    }

    if (n > BigInt.one) {
      factors[n] = (factors[n] ?? 0) + 1;
    }

    return factors;
  }
  // In RootExpr class, replace the termSignature getter:

  @override
  String get termSignature {
    // Use actual simplified values to distinguish √2 from √3
    Expr simpIndex = index.simplify();
    Expr simpRadicand = radicand.simplify();
    return 'root:$simpIndex:$simpRadicand';
  }

  @override
  double toDouble() {
    double r = radicand.toDouble();
    double n = index.toDouble();
    if (n == 2) return math.sqrt(r);
    // realPow returns the real odd root of a negative radicand (e.g. ∛(-8) == -2)
    // instead of the NaN that math.pow gives for a negative base.
    return realPow(r, 1 / n);
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is RootExpr &&
        radicand.structurallyEquals(other.radicand) &&
        index.structurallyEquals(other.index);
  }

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => radicand.isZero;

  @override
  bool get isOne => radicand.isOne;

  @override
  bool get isRational {
    // √n is rational only if n is a perfect square
    Expr simplified = simplify();
    return simplified is IntExpr || simplified is FracExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    // If it simplified to a rational, use that
    if (simplified != this &&
        (simplified is IntExpr || simplified is FracExpr)) {
      return simplified.toMathNode();
    }

    // If it's a product (coefficient * root), render that
    if (simplified is ProdExpr) {
      return simplified.toMathNode();
    }

    // Render as root node
    RootExpr root = simplified is RootExpr ? simplified : this;
    bool isSquareRoot =
        root.index is IntExpr && (root.index as IntExpr).value == BigInt.two;

    return [
      RootNode(
        isSquareRoot: isSquareRoot,
        index: isSquareRoot ? null : root.index.toMathNode(),
        radicand: root.radicand.toMathNode(),
      ),
    ];
  }

  @override
  Expr copy() => RootExpr(radicand.copy(), index.copy());

  @override
  String toString() {
    if (index is IntExpr && (index as IntExpr).value == BigInt.two) {
      return '√$radicand';
    }
    return '$index√$radicand';
  }
}

// ============================================================
// SECTION 9: LOGARITHM EXPRESSION
// ============================================================

/// Represents log_base(argument)
class LogExpr extends Expr {
  final Expr base;
  final Expr argument;
  final bool isNaturalLog;

  LogExpr(this.base, this.argument, {this.isNaturalLog = false});

  @override
  bool get hasImaginary => base.hasImaginary || argument.hasImaginary;

  /// Natural logarithm
  LogExpr.ln(this.argument) : base = ConstExpr.e, isNaturalLog = true;

  /// Common logarithm (base 10)
  LogExpr.log10(this.argument) : base = IntExpr.from(10), isNaturalLog = false;

  @override
  Expr simplify() {
    Expr b = base.simplify();
    Expr arg = argument.simplify();

    // log_a(1) = 0
    if (arg.isOne) return IntExpr.zero;

    // log_a(a) = 1
    if (arg.structurallyEquals(b)) return IntExpr.one;

    // log_a(a^n) = n
    if (arg is PowExpr && arg.base.structurallyEquals(b)) {
      return arg.exponent.simplify();
    }

    // For integer base and argument, check if result is integer
    if (b is IntExpr &&
        arg is IntExpr &&
        b.value > BigInt.one &&
        arg.value > BigInt.zero) {
      int? result = _tryComputeIntLog(b.value, arg.value);
      if (result != null) {
        return IntExpr.from(result);
      }
    }

    return LogExpr(b, arg, isNaturalLog: isNaturalLog);
  }

  /// Try to compute log_base(arg) if it's an integer
  int? _tryComputeIntLog(BigInt base, BigInt arg) {
    if (arg == BigInt.one) return 0;

    BigInt current = base;
    int power = 1;

    while (current < arg) {
      current *= base;
      power++;
      if (power > 100) return null; // Prevent infinite loop
    }

    if (current == arg) return power;
    return null;
  }

  @override
  double toDouble() {
    if (isNaturalLog) {
      return math.log(argument.toDouble());
    }
    return math.log(argument.toDouble()) / math.log(base.toDouble());
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is LogExpr &&
        base.structurallyEquals(other.base) &&
        argument.structurallyEquals(other.argument);
  }

  // In LogExpr class, replace the termSignature getter:

  @override
  String get termSignature {
    Expr simpBase = base.simplify();
    Expr simpArg = argument.simplify();
    return 'log:$simpBase:$simpArg';
  }

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => argument.isOne;

  @override
  bool get isOne => argument.structurallyEquals(base);

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr || simplified is FracExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    // If simplified to integer, render that
    if (simplified is IntExpr) {
      return simplified.toMathNode();
    }

    LogExpr log = simplified is LogExpr ? simplified : this;

    return [
      LogNode(
        isNaturalLog: log.isNaturalLog,
        base:
            log.isNaturalLog ? [LiteralNode(text: 'e')] : log.base.toMathNode(),
        argument: log.argument.toMathNode(),
      ),
    ];
  }

  @override
  Expr copy() =>
      LogExpr(base.copy(), argument.copy(), isNaturalLog: isNaturalLog);

  @override
  String toString() {
    if (isNaturalLog) return 'ln($argument)';
    return 'log_$base($argument)';
  }
}

// ============================================================
// SECTION 10: TRIGONOMETRIC EXPRESSION
// ============================================================

enum TrigFunc {
  sin,
  cos,
  tan,
  asin,
  acos,
  atan,
  sinh,
  cosh,
  tanh,
  asinh,
  acosh,
  atanh,
  arg,
  re,
  im,
  sgn,
}

/// Represents a trigonometric function
class TrigExpr extends Expr {
  final TrigFunc func;
  final Expr argument;

  TrigExpr(this.func, this.argument);

  @override
  bool get hasImaginary => argument.hasImaginary;

  @override
  Expr simplify() {
    Expr arg = argument.simplify();

    if (func == TrigFunc.arg ||
        func == TrigFunc.re ||
        func == TrigFunc.im ||
        func == TrigFunc.sgn) {
      final Expr? special = _trySimplifyComplexFunction(arg);
      if (special != null) return special;
      return TrigExpr(func, arg);
    }

    // Check for known exact values
    Expr? exact = _tryExactValue(arg);
    if (exact != null) return exact;

    return TrigExpr(func, arg);
  }

  /// Try to find exact value for common angles
  Expr? _tryExactValue(Expr arg) {
    // Handle zero argument explicitly
    if (arg.isZero) {
      switch (func) {
        case TrigFunc.sin:
          return IntExpr.zero; // sin(0) = 0
        case TrigFunc.cos:
          return IntExpr.one; // cos(0) = 1
        case TrigFunc.tan:
          return IntExpr.zero; // tan(0) = 0
        case TrigFunc.asin:
          return IntExpr.zero; // asin(0) = 0
        case TrigFunc.atan:
          return IntExpr.zero; // atan(0) = 0
        case TrigFunc.acos:
          // acos(0) = π/2
          return DivExpr(ConstExpr.pi, IntExpr.two).simplify();
        case TrigFunc.sinh:
          return IntExpr.zero; // sinh(0) = 0
        case TrigFunc.cosh:
          return IntExpr.one; // cosh(0) = 1
        case TrigFunc.tanh:
          return IntExpr.zero; // tanh(0) = 0
        case TrigFunc.asinh:
          return IntExpr.zero; // asinh(0) = 0
        case TrigFunc.acosh:
          return null; // acosh(0) not real
        case TrigFunc.atanh:
          return IntExpr.zero; // atanh(0) = 0
        case TrigFunc.arg:
          return IntExpr.zero;
        case TrigFunc.re:
          return IntExpr.zero;
        case TrigFunc.im:
          return IntExpr.zero;
        case TrigFunc.sgn:
          return IntExpr.zero;
      }
    }

    // Handle argument = 1 for inverse trig
    if (arg.isOne) {
      switch (func) {
        case TrigFunc.asin:
          // asin(1) = π/2
          return DivExpr(ConstExpr.pi, IntExpr.two).simplify();
        case TrigFunc.acos:
          return IntExpr.zero; // acos(1) = 0
        case TrigFunc.atan:
          // atan(1) = π/4
          return DivExpr(ConstExpr.pi, IntExpr.from(4)).simplify();
        case TrigFunc.arg:
        case TrigFunc.re:
        case TrigFunc.im:
        case TrigFunc.sgn:
        default:
          break;
      }
    }

    // Handle argument = -1 for inverse trig
    if (arg is IntExpr && arg.value == -BigInt.one) {
      switch (func) {
        case TrigFunc.asin:
          // asin(-1) = -π/2
          return DivExpr(ConstExpr.pi, IntExpr.from(-2)).simplify();
        case TrigFunc.acos:
          // acos(-1) = π
          return ConstExpr.pi;
        case TrigFunc.arg:
        case TrigFunc.re:
        case TrigFunc.im:
        case TrigFunc.sgn:
        default:
          break;
      }
    }

    // Convert argument to a multiple of π for checking
    _PiFraction? piFrac = _asPiFraction(arg);
    if (piFrac == null) return null;

    // Normalize to [0, 2π)
    int num = piFrac.numerator % (2 * piFrac.denominator);
    if (num < 0) num += 2 * piFrac.denominator;
    int den = piFrac.denominator;

    switch (func) {
      case TrigFunc.sin:
        return _sinExact(num, den);
      case TrigFunc.cos:
        return _cosExact(num, den);
      case TrigFunc.tan:
        Expr? sinVal = _sinExact(num, den);
        Expr? cosVal = _cosExact(num, den);
        if (sinVal != null && cosVal != null && !cosVal.isZero) {
          final Expr simplifiedSin = sinVal.simplify();
          final Expr simplifiedCos = cosVal.simplify();

          // Keep exact ±1 for common-angle tangent values where sin/cos share
          // the same magnitude but differ in sign (e.g. tan(3π/4) = -1).
          if (simplifiedSin.structurallyEquals(simplifiedCos)) {
            return IntExpr.one;
          }
          if (simplifiedSin.structurallyEquals(
                simplifiedCos.negate().simplify(),
              ) ||
              simplifiedCos.structurallyEquals(
                simplifiedSin.negate().simplify(),
              )) {
            return IntExpr.negOne;
          }

          return DivExpr(simplifiedSin, simplifiedCos).simplify();
        }
        return null;
      default:
        return null;
    }
  }

  Expr? _trySimplifyComplexFunction(Expr arg) {
    final Complex? value = _tryEvalComplexValue(arg);
    if (value == null) return null;

    switch (func) {
      case TrigFunc.arg:
        return _exprFromDouble(math.atan2(value.imag, value.real));
      case TrigFunc.re:
        return _exprFromDouble(value.real);
      case TrigFunc.im:
        return _exprFromDouble(value.imag);
      case TrigFunc.sgn:
        final double mag = value.magnitude;
        if (mag < _complexEvalEpsilon) return IntExpr.zero;
        final double real = value.real / mag;
        final double imag = value.imag / mag;
        if (imag.abs() < _complexEvalEpsilon) {
          return real >= 0 ? IntExpr.one : IntExpr.negOne;
        }
        return _buildComplexExpr(real, imag);
      default:
        return null;
    }
  }

  Expr _buildComplexExpr(double real, double imag) {
    final Expr realExpr = _exprFromDouble(real);
    final Expr imagExpr = _exprFromDouble(imag);

    if (imagExpr.isZero) return realExpr;

    final Expr imagTerm = ProdExpr([imagExpr, ImaginaryExpr.i]).simplify();

    if (realExpr.isZero) return imagTerm;

    return SumExpr([realExpr, imagTerm]).simplify();
  }

  /// Check if expr is a rational multiple of π
  _PiFraction? _asPiFraction(Expr expr) {
    if (expr is ConstExpr && expr.type == ConstType.pi) {
      return _PiFraction(1, 1);
    }

    if (expr is ProdExpr) {
      Expr? piPart;
      Expr? coeff;

      for (Expr f in expr.factors) {
        if (f is ConstExpr && f.type == ConstType.pi) {
          piPart = f;
        } else if (f.isRational) {
          coeff = coeff == null ? f : ProdExpr([coeff, f]).simplify();
        }
      }

      if (piPart != null && coeff != null) {
        if (coeff is IntExpr) {
          return _PiFraction(coeff.value.toInt(), 1);
        }
        if (coeff is FracExpr) {
          return _PiFraction(
            coeff.numerator.value.toInt(),
            coeff.denominator.value.toInt(),
          );
        }
      }
    }

    if (expr is FracExpr) {
      _PiFraction? numFrac = _asPiFraction(expr.numerator);
      final den = expr.denominator;
      if (numFrac != null) {
        return _PiFraction(
          numFrac.numerator,
          numFrac.denominator * den.value.toInt(),
        );
      }
    }

    if (expr is DivExpr) {
      _PiFraction? numFrac = _asPiFraction(expr.numerator);
      final den = expr.denominator;
      if (numFrac != null && den is IntExpr) {
        return _PiFraction(
          numFrac.numerator,
          numFrac.denominator * den.value.toInt(),
        );
      }
    }

    return null;
  }

  /// Get exact value of sin(num*π/den)
  Expr? _sinExact(int num, int den) {
    // Reduce to first quadrant and track sign
    int sign = 1;

    // Normalize to [0, 2π): sin(x + 2π) = sin(x). Without this, arguments
    // outside [0, 2π] (e.g. sin(13π/6)) fall through and return null even
    // though an exact value exists. Matches the reduction in _cosExact.
    num = num % (2 * den);
    if (num < 0) num += 2 * den;

    // sin is positive in [0, π], negative in [π, 2π]
    if (num > den) {
      sign = -1;
      num = 2 * den - num;
    }
    if (num > den) {
      num = 2 * den - num;
    }

    // Now num/den is in [0, 1] representing [0, π]
    // sin(π - x) = sin(x)
    if (num * 2 > den) {
      num = den - num;
    }

    // Known values for sin in [0, π/2]
    // sin(0) = 0
    if (num == 0) return IntExpr.zero;

    // sin(π/6) = 1/2
    if (num * 6 == den) {
      return sign == 1 ? FracExpr.from(1, 2) : FracExpr.from(-1, 2);
    }

    // sin(π/4) = √2/2
    if (num * 4 == den) {
      Expr val = DivExpr(RootExpr.sqrt(IntExpr.two), IntExpr.two);
      return sign == 1 ? val : val.negate();
    }

    // sin(π/3) = √3/2
    if (num * 3 == den) {
      Expr val = DivExpr(RootExpr.sqrt(IntExpr.from(3)), IntExpr.two);
      return sign == 1 ? val : val.negate();
    }

    // sin(π/2) = 1
    if (num * 2 == den) {
      return sign == 1 ? IntExpr.one : IntExpr.negOne;
    }

    return null;
  }

  /// Get exact value of cos(num*π/den)
  Expr? _cosExact(int num, int den) {
    // cos(x) = sin(π/2 - x) = sin((den - 2*num)/(2*den) * π)
    // But simpler: use cos(x) = sin(π/2 + x) relationship

    int sign = 1;

    // cos is positive in [0, π/2] and [3π/2, 2π], negative in [π/2, 3π/2]
    // Normalize to [0, 2π]
    num = num % (2 * den);
    if (num < 0) num += 2 * den;

    // cos(-x) = cos(x), so we can work with positive
    if (num > den) {
      num = 2 * den - num;
    }

    // Now num/den is in [0, 1] representing [0, π]
    if (num * 2 > den) {
      sign = -1;
      num = den - num;
    }

    // Known values for cos in [0, π/2]
    // cos(0) = 1
    if (num == 0) return sign == 1 ? IntExpr.one : IntExpr.negOne;

    // cos(π/6) = √3/2
    if (num * 6 == den) {
      Expr val = DivExpr(RootExpr.sqrt(IntExpr.from(3)), IntExpr.two);
      return sign == 1 ? val : val.negate();
    }

    // cos(π/4) = √2/2
    if (num * 4 == den) {
      Expr val = DivExpr(RootExpr.sqrt(IntExpr.two), IntExpr.two);
      return sign == 1 ? val : val.negate();
    }

    // cos(π/3) = 1/2
    if (num * 3 == den) {
      return sign == 1 ? FracExpr.from(1, 2) : FracExpr.from(-1, 2);
    }

    // cos(π/2) = 0
    if (num * 2 == den) return IntExpr.zero;

    return null;
  }

  @override
  double toDouble() {
    if (func == TrigFunc.arg ||
        func == TrigFunc.re ||
        func == TrigFunc.im ||
        func == TrigFunc.sgn) {
      final Complex? c = _tryEvalComplexValue(argument);
      if (c == null) return double.nan;
      switch (func) {
        case TrigFunc.arg:
          return math.atan2(c.imag, c.real);
        case TrigFunc.re:
          return c.real;
        case TrigFunc.im:
          return c.imag;
        case TrigFunc.sgn:
          if (c.real.abs() < _complexEvalEpsilon &&
              c.imag.abs() < _complexEvalEpsilon) {
            return 0.0;
          }
          if (c.imag.abs() < _complexEvalEpsilon) {
            return c.real > 0 ? 1.0 : -1.0;
          }
          return double.nan;
        default:
          return double.nan;
      }
    }

    double a = argument.toDouble();
    switch (func) {
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

  @override
  bool structurallyEquals(Expr other) {
    return other is TrigExpr &&
        func == other.func &&
        argument.structurallyEquals(other.argument);
  }

  // ============================================================
  // SECTION 10: TRIGONOMETRIC EXPRESSION (continued)
  // ============================================================
  // In TrigExpr class, replace the termSignature getter (the one that was cut off):

  @override
  String get termSignature {
    Expr simpArg = argument.simplify();
    return 'trig:${func.name}:$simpArg';
  }

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero {
    Expr simplified = simplify();
    return simplified is IntExpr && simplified.isZero;
  }

  @override
  bool get isOne {
    Expr simplified = simplify();
    return simplified is IntExpr && simplified.isOne;
  }

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr || simplified is FracExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    // If simplified to something else, render that
    if (simplified is! TrigExpr) {
      return simplified.toMathNode();
    }

    String funcName;
    switch (func) {
      case TrigFunc.sin:
        funcName = 'sin';
        break;
      case TrigFunc.cos:
        funcName = 'cos';
        break;
      case TrigFunc.tan:
        funcName = 'tan';
        break;
      case TrigFunc.asin:
        funcName = 'asin';
        break;
      case TrigFunc.acos:
        funcName = 'acos';
        break;
      case TrigFunc.atan:
        funcName = 'atan';
        break;
      case TrigFunc.sinh:
        funcName = 'sinh';
        break;
      case TrigFunc.cosh:
        funcName = 'cosh';
        break;
      case TrigFunc.tanh:
        funcName = 'tanh';
        break;
      case TrigFunc.asinh:
        funcName = 'asinh';
        break;
      case TrigFunc.acosh:
        funcName = 'acosh';
        break;
      case TrigFunc.atanh:
        funcName = 'atanh';
        break;
      case TrigFunc.arg:
        funcName = 'arg';
        break;
      case TrigFunc.re:
        funcName = 'Re';
        break;
      case TrigFunc.im:
        funcName = 'Im';
        break;
      case TrigFunc.sgn:
        funcName = 'sgn';
        break;
    }

    return [TrigNode(function: funcName, argument: argument.toMathNode())];
  }

  @override
  Expr copy() => TrigExpr(func, argument.copy());

  @override
  String toString() => '${func.name}($argument)';
}

/// Helper class for representing fractions of π
class _PiFraction {
  final int numerator;
  final int denominator;

  _PiFraction(this.numerator, this.denominator);
}

const double _complexEvalEpsilon = 1e-12;

Expr _exprFromDouble(double value) {
  return MathNodeToExpr._doubleToExpr(value);
}

Complex? _tryEvalComplexValue(Expr expr) {
  if (expr is IntExpr) {
    return Complex(expr.value.toDouble(), 0);
  }
  if (expr is FracExpr) {
    return Complex(
      expr.numerator.value.toDouble() / expr.denominator.value.toDouble(),
      0,
    );
  }
  if (expr is ConstExpr) {
    return Complex(expr.toDouble(), 0);
  }
  if (expr is ImaginaryExpr) {
    return Complex(0, 1);
  }
  if (expr is SumExpr) {
    Complex sum = Complex(0, 0);
    for (final term in expr.terms) {
      final Complex? c = _tryEvalComplexValue(term);
      if (c == null) return null;
      sum = sum + c;
    }
    return sum;
  }
  if (expr is ProdExpr) {
    Complex prod = Complex(1, 0);
    for (final factor in expr.factors) {
      final Complex? c = _tryEvalComplexValue(factor);
      if (c == null) return null;
      prod = prod * c;
    }
    return prod;
  }
  if (expr is DivExpr) {
    final Complex? num = _tryEvalComplexValue(expr.numerator);
    final Complex? den = _tryEvalComplexValue(expr.denominator);
    if (num == null || den == null) return null;
    if (den.magnitude < _complexEvalEpsilon) return null;
    return num / den;
  }
  if (expr is PowExpr) {
    final Complex? base = _tryEvalComplexValue(expr.base);
    final Complex? exponent = _tryEvalComplexValue(expr.exponent);
    if (base == null || exponent == null) return null;
    if (exponent.imag.abs() > _complexEvalEpsilon) return null;
    if (base.magnitude < _complexEvalEpsilon) return Complex(0, 0);
    final double power = exponent.real;
    final double r = base.magnitude;
    final double theta = base.phase;
    final double rPow = math.pow(r, power).toDouble();
    return Complex(
      rPow * math.cos(theta * power),
      rPow * math.sin(theta * power),
    );
  }
  if (expr is RootExpr) {
    final Complex? rad = _tryEvalComplexValue(expr.radicand);
    final Complex? idx = _tryEvalComplexValue(expr.index);
    if (rad == null || idx == null) return null;
    if (rad.imag.abs() > _complexEvalEpsilon) return null;
    if (idx.imag.abs() > _complexEvalEpsilon) return null;
    if (idx.real.abs() < _complexEvalEpsilon) return null;
    if (rad.real < 0) return null;
    final double value = math.pow(rad.real, 1 / idx.real).toDouble();
    return Complex(value, 0);
  }
  if (expr is LogExpr) {
    final Complex? arg = _tryEvalComplexValue(expr.argument);
    if (arg == null || arg.imag.abs() > _complexEvalEpsilon) return null;
    final Complex base =
        expr.isNaturalLog
            ? Complex(math.e, 0)
            : (_tryEvalComplexValue(expr.base) ?? Complex(0, 0));
    if (base.magnitude < _complexEvalEpsilon ||
        base.imag.abs() > _complexEvalEpsilon) {
      return null;
    }
    if (arg.real <= 0 || base.real <= 0) return null;
    final double result =
        expr.isNaturalLog
            ? math.log(arg.real)
            : math.log(arg.real) / math.log(base.real);
    return Complex(result, 0);
  }
  if (expr is TrigExpr) {
    final Complex? arg = _tryEvalComplexValue(expr.argument);
    if (arg == null) return null;
    if (arg.imag.abs() > _complexEvalEpsilon) return null;
    final double a = arg.real;
    switch (expr.func) {
      case TrigFunc.sin:
        return Complex(math.sin(a), 0);
      case TrigFunc.cos:
        return Complex(math.cos(a), 0);
      case TrigFunc.tan:
        return Complex(math.tan(a), 0);
      case TrigFunc.asin:
        return Complex(math.asin(a), 0);
      case TrigFunc.acos:
        return Complex(math.acos(a), 0);
      case TrigFunc.atan:
        return Complex(math.atan(a), 0);
      case TrigFunc.sinh:
        return Complex((math.exp(a) - math.exp(-a)) / 2, 0);
      case TrigFunc.cosh:
        return Complex((math.exp(a) + math.exp(-a)) / 2, 0);
      case TrigFunc.tanh:
        return Complex(
          (math.exp(a) - math.exp(-a)) / (math.exp(a) + math.exp(-a)),
          0,
        );
      case TrigFunc.asinh:
        return Complex(math.log(a + math.sqrt(a * a + 1)), 0);
      case TrigFunc.acosh:
        return Complex(math.log(a + math.sqrt(a * a - 1)), 0);
      case TrigFunc.atanh:
        return Complex(0.5 * math.log((1 + a) / (1 - a)), 0);
      case TrigFunc.arg:
        return Complex(math.atan2(arg.imag, arg.real), 0);
      case TrigFunc.re:
        return Complex(arg.real, 0);
      case TrigFunc.im:
        return Complex(0, 0);
      case TrigFunc.sgn:
        if (arg.magnitude < _complexEvalEpsilon) return Complex(0, 0);
        return Complex(arg.real / arg.magnitude, arg.imag / arg.magnitude);
    }
  }
  if (expr is AbsExpr) {
    final Complex? val = _tryEvalComplexValue(expr.operand);
    if (val == null) return null;
    return Complex(val.magnitude, 0);
  }

  return null;
}

// ============================================================
// SECTION 11: ABSOLUTE VALUE EXPRESSION
// ============================================================

/// Represents |expr|
class AbsExpr extends Expr {
  final Expr operand;

  AbsExpr(this.operand);

  @override
  bool get hasImaginary => operand.hasImaginary;

  @override
  Expr simplify() {
    Expr op = operand.simplify();

    // |n| for integer n
    if (op is IntExpr) {
      return IntExpr(op.value.abs());
    }

    // |a/b| = |a|/|b|
    if (op is FracExpr) {
      return FracExpr(
        IntExpr(op.numerator.value.abs()),
        IntExpr(op.denominator.value.abs()),
      ).simplify();
    }

    // |√x| = √x for x ≥ 0
    if (op is RootExpr) {
      // Assuming radicand is non-negative for real roots
      return op;
    }

    return AbsExpr(op);
  }

  @override
  double toDouble() {
    final Complex? value = _tryEvalComplexValue(operand);
    if (value != null) return value.magnitude;
    return operand.toDouble().abs();
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is AbsExpr && operand.structurallyEquals(other.operand);
  }
  // In AbsExpr class, replace the termSignature getter:

  @override
  String get termSignature {
    Expr simpOp = operand.simplify();
    return 'abs:$simpOp';
  }

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => operand.isZero;

  @override
  bool get isOne => operand.isOne || (operand.negate().simplify().isOne);

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr || simplified is FracExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    if (simplified is! AbsExpr) {
      return simplified.toMathNode();
    }

    // Render as |operand| using parentheses with | characters
    // For now, use TrigNode with "abs" function name
    return [TrigNode(function: 'abs', argument: operand.toMathNode())];
  }

  @override
  Expr copy() => AbsExpr(operand.copy());

  @override
  String toString() => '|$operand|';
}

// ============================================================
// SECTION 12: GENERAL FRACTION EXPRESSION (for symbolic fractions)
// ============================================================

/// Represents a fraction with any Expr as numerator and denominator
/// This is different from FracExpr which only holds IntExpr
class DivExpr extends Expr {
  final Expr numerator;
  final Expr denominator;

  DivExpr(this.numerator, this.denominator);

  static ({Expr coefficient, Expr remainder}) _splitRationalFactor(Expr expr) {
    if (expr is IntExpr || expr is FracExpr) {
      return (coefficient: expr, remainder: IntExpr.one);
    }

    if (expr is ProdExpr) {
      Expr coeff = IntExpr.one;
      final List<Expr> remainder = [];
      for (final factor in expr.factors) {
        if (factor.isRational) {
          coeff = _multiplyRational(coeff, factor);
        } else {
          remainder.add(factor);
        }
      }

      final Expr remExpr =
          remainder.isEmpty
              ? IntExpr.one
              : (remainder.length == 1
                  ? remainder.first
                  : ProdExpr(remainder).simplify());
      return (coefficient: coeff, remainder: remExpr);
    }

    return (coefficient: IntExpr.one, remainder: expr);
  }

  static Expr _multiplyRational(Expr a, Expr b) {
    if (a is IntExpr && b is IntExpr) {
      return IntExpr(a.value * b.value);
    }
    if (a is IntExpr && b is FracExpr) {
      return FracExpr(
        IntExpr(a.value * b.numerator.value),
        b.denominator,
      ).simplify();
    }
    if (a is FracExpr && b is IntExpr) {
      return FracExpr(
        IntExpr(a.numerator.value * b.value),
        a.denominator,
      ).simplify();
    }
    if (a is FracExpr && b is FracExpr) {
      return FracExpr(
        IntExpr(a.numerator.value * b.numerator.value),
        IntExpr(a.denominator.value * b.denominator.value),
      ).simplify();
    }
    return ProdExpr([a, b]).simplify();
  }

  static Expr _divideRational(Expr numerator, Expr denominator) {
    if (numerator is IntExpr) {
      return numerator.divide(denominator).simplify();
    }
    if (numerator is FracExpr) {
      return numerator.divide(denominator).simplify();
    }
    return DivExpr(numerator, denominator).simplify();
  }

  ({Expr coefficient, Expr numerator, Expr denominator}) _splitForLikeTerms() {
    final Expr num = numerator.simplify();
    final Expr den = denominator.simplify();

    final numSplit = _splitRationalFactor(num);
    final denSplit = _splitRationalFactor(den);

    final Expr coeff = _divideRational(
      numSplit.coefficient,
      denSplit.coefficient,
    );

    return (
      coefficient: coeff,
      numerator: numSplit.remainder,
      denominator: denSplit.remainder,
    );
  }

  @override
  Expr simplify() {
    Expr num = numerator.simplify();
    Expr den = denominator.simplify();

    // 0 / x = 0
    if (num.isZero) return IntExpr.zero;

    // x / 1 = x
    if (den.isOne) return num;

    // x / x = 1 (if x ≠ 0)
    if (num.structurallyEquals(den) && !den.isZero) {
      return IntExpr.one;
    }

    // If both are integers, use FracExpr
    if (num is IntExpr && den is IntExpr) {
      return FracExpr(num, den).simplify();
    }

    // If both are fractions, compute
    if (num is FracExpr && den is FracExpr) {
      return num.divide(den);
    }

    if (num is IntExpr && den is FracExpr) {
      return IntExpr(num.value).divide(den);
    }

    if (num is FracExpr && den is IntExpr) {
      return num.divide(den);
    }

    // √a / √b = √(a/b)
    if (num is RootExpr && den is RootExpr) {
      if (num.index.structurallyEquals(den.index)) {
        return RootExpr(
          DivExpr(num.radicand, den.radicand).simplify(),
          num.index,
        ).simplify();
      }
    }

    // a√b / c = (a/c)√b
    if (num is ProdExpr && den.isRational) {
      int ratIdx = num.factors.indexWhere((f) => f.isRational);
      if (ratIdx != -1) {
        Expr ratFactor = num.factors[ratIdx];
        Expr simplifiedCoeff = DivExpr(ratFactor, den).simplify();

        // Avoid infinite recursion by checking if anything changed
        bool changed = simplifiedCoeff is IntExpr;
        if (!changed && simplifiedCoeff is FracExpr) {
          if (ratFactor is IntExpr && den is IntExpr) {
            changed =
                simplifiedCoeff.numerator.value != ratFactor.value ||
                simplifiedCoeff.denominator.value != den.value;
          } else {
            changed = !ratFactor.structurallyEquals(simplifiedCoeff);
          }
        }

        // Check if separation is needed regardless of simplification
        // We need to look ahead to see if complex functions are involved
        bool shouldSeparate = false;
        List<Expr> tempOtherFactors = List.from(num.factors)..removeAt(ratIdx);
        Expr tempRemainder =
            tempOtherFactors.length == 1
                ? tempOtherFactors[0]
                : ProdExpr(tempOtherFactors).simplify();

        if (simplifiedCoeff is FracExpr &&
            _hasComplexFunctions(tempRemainder)) {
          shouldSeparate = true;
        }

        if (changed || shouldSeparate) {
          List<Expr> otherFactors = List.from(num.factors)..removeAt(ratIdx);
          Expr remainder =
              otherFactors.length == 1
                  ? otherFactors[0]
                  : ProdExpr(otherFactors).simplify();

          if (simplifiedCoeff is IntExpr) {
            if (simplifiedCoeff.isOne) return remainder;
            return ProdExpr([simplifiedCoeff, remainder]).simplify();
          } else if (simplifiedCoeff is FracExpr) {
            // Check if we should split the fraction:
            // Only if the remainder has complex functions (Trig, Log, Root)
            // or if the user prefers, we keep variables inside the fraction.
            bool hasComplex = _hasComplexFunctions(remainder);

            if (hasComplex) {
              return ProdExpr([simplifiedCoeff, remainder]).simplify();
            }

            // Otherwise keep as single fraction
            return DivExpr(
              ProdExpr([simplifiedCoeff.numerator, remainder]).simplify(),
              simplifiedCoeff.denominator,
            );
          }
        }
      }
    }

    // (a/b) / c = a / (b*c)
    if (num is FracExpr) {
      return DivExpr(
        num.numerator,
        ProdExpr([num.denominator, den]),
      ).simplify();
    }
    if (num is DivExpr) {
      return DivExpr(
        num.numerator,
        ProdExpr([num.denominator, den]),
      ).simplify();
    }

    // a / (b/c) = (a*c) / b
    if (den is FracExpr) {
      return DivExpr(
        ProdExpr([num, den.denominator]),
        den.numerator,
      ).simplify();
    }
    if (den is DivExpr) {
      return DivExpr(
        ProdExpr([num, den.denominator]),
        den.numerator,
      ).simplify();
    }

    // (a + b) / c = a/c + b/c
    // Distribute division over addition if the denominator is not a sum
    if (num is SumExpr && den is! SumExpr) {
      List<Expr> newTerms = [];
      for (Expr term in num.terms) {
        newTerms.add(DivExpr(term, den).simplify());
      }
      return SumExpr(newTerms).simplify();
    }

    return DivExpr(num, den);
  }

  bool _hasComplexFunctions(Expr expr) {
    if (expr is TrigExpr || expr is LogExpr || expr is RootExpr) return true;
    if (expr is ProdExpr) {
      return expr.factors.any((f) => _hasComplexFunctions(f));
    }
    if (expr is PowExpr) {
      return _hasComplexFunctions(expr.base);
    }
    return false;
  }

  @override
  bool get hasImaginary => numerator.hasImaginary || denominator.hasImaginary;

  @override
  double toDouble() => numerator.toDouble() / denominator.toDouble();

  @override
  bool structurallyEquals(Expr other) {
    return other is DivExpr &&
        numerator.structurallyEquals(other.numerator) &&
        denominator.structurallyEquals(other.denominator);
  }
  // In DivExpr class, replace the termSignature getter:

  @override
  String get termSignature {
    final split = _splitForLikeTerms();
    final Expr baseNum = split.numerator;
    final Expr baseDen = split.denominator;

    if (baseDen is IntExpr && baseDen.isOne) {
      return baseNum.termSignature;
    }

    return 'div:${baseNum.termSignature}/${baseDen.termSignature}';
  }

  @override
  Expr get coefficient => _splitForLikeTerms().coefficient;

  @override
  Expr get baseExpr {
    final split = _splitForLikeTerms();
    final Expr baseNum = split.numerator;
    final Expr baseDen = split.denominator;

    if (baseDen is IntExpr && baseDen.isOne) {
      return baseNum;
    }

    if (baseNum is IntExpr && baseNum.isOne) {
      return DivExpr(IntExpr.one, baseDen).simplify();
    }

    return DivExpr(baseNum, baseDen).simplify();
  }

  @override
  bool get isZero => numerator.isZero;

  @override
  bool get isOne => numerator.structurallyEquals(denominator);

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr || simplified is FracExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => DivExpr(numerator.negate(), denominator);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    if (simplified is! DivExpr) {
      return simplified.toMathNode();
    }

    DivExpr div = simplified;

    // Check if the result is negative
    bool isNegative = false;
    Expr numToRender = div.numerator;

    if (div.numerator is IntExpr) {
      IntExpr numInt = div.numerator as IntExpr;
      if (numInt.value < BigInt.zero) {
        isNegative = true;
        numToRender = IntExpr(numInt.value.abs());
      }
    } else if (div.numerator is FracExpr) {
      FracExpr numFrac = div.numerator as FracExpr;
      if (numFrac.numerator.value < BigInt.zero) {
        isNegative = true;
        numToRender = FracExpr(
          IntExpr(numFrac.numerator.value.abs()),
          numFrac.denominator,
        );
      }
    }

    List<MathNode> result = [];

    if (isNegative) {
      result.add(LiteralNode(text: '−'));
    }

    result.add(
      FractionNode(
        num: numToRender.toMathNode(),
        den: div.denominator.toMathNode(),
      ),
    );

    return result;
  }

  @override
  Expr copy() => DivExpr(numerator.copy(), denominator.copy());

  @override
  String toString() => '($numerator)/($denominator)';
}

// ============================================================
// SECTION 13: PERMUTATION AND COMBINATION EXPRESSIONS
// ============================================================

/// Represents nPr (permutation)
class PermExpr extends Expr {
  final Expr n;
  final Expr r;

  PermExpr(this.n, this.r);

  @override
  bool get hasImaginary => n.hasImaginary || r.hasImaginary;

  @override
  Expr simplify() {
    Expr nSimp = n.simplify();
    Expr rSimp = r.simplify();

    // If both are non-negative integers, compute
    if (nSimp is IntExpr && rSimp is IntExpr) {
      BigInt nVal = nSimp.value;
      BigInt rVal = rSimp.value;

      if (nVal >= BigInt.zero && rVal >= BigInt.zero && rVal <= nVal) {
        // P(n,r) = n! / (n-r)!
        BigInt result = BigInt.one;
        for (BigInt i = nVal - rVal + BigInt.one; i <= nVal; i += BigInt.one) {
          result *= i;
        }
        return IntExpr(result);
      }
    }

    return PermExpr(nSimp, rSimp);
  }

  @override
  double toDouble() {
    int nVal = n.toDouble().toInt();
    int rVal = r.toDouble().toInt();

    double result = 1;
    for (int i = 0; i < rVal; i++) {
      result *= (nVal - i);
    }
    return result;
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is PermExpr &&
        n.structurallyEquals(other.n) &&
        r.structurallyEquals(other.r);
  }

  @override
  String get termSignature => 'perm:${n.termSignature}:${r.termSignature}';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => false;

  @override
  bool get isOne {
    Expr simplified = simplify();
    return simplified is IntExpr && simplified.isOne;
  }

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    if (simplified is IntExpr) {
      return simplified.toMathNode();
    }

    return [PermutationNode(n: n.toMathNode(), r: r.toMathNode())];
  }

  @override
  Expr copy() => PermExpr(n.copy(), r.copy());

  @override
  String toString() => 'P($n,$r)';
}

/// Represents nCr (combination)
class CombExpr extends Expr {
  final Expr n;
  final Expr r;

  CombExpr(this.n, this.r);

  @override
  bool get hasImaginary => n.hasImaginary || r.hasImaginary;

  @override
  Expr simplify() {
    Expr nSimp = n.simplify();
    Expr rSimp = r.simplify();

    // If both are non-negative integers, compute
    if (nSimp is IntExpr && rSimp is IntExpr) {
      BigInt nVal = nSimp.value;
      BigInt rVal = rSimp.value;

      if (nVal >= BigInt.zero && rVal >= BigInt.zero && rVal <= nVal) {
        // C(n,r) = n! / (r! * (n-r)!)
        // Use the more efficient formula: C(n,r) = P(n,r) / r!

        // Optimize: use smaller of r and n-r
        if (rVal > nVal - rVal) {
          rVal = nVal - rVal;
        }

        BigInt result = BigInt.one;
        for (BigInt i = BigInt.zero; i < rVal; i += BigInt.one) {
          result *= (nVal - i);
          result ~/= (i + BigInt.one);
        }
        return IntExpr(result);
      }
    }

    return CombExpr(nSimp, rSimp);
  }

  @override
  double toDouble() {
    int nVal = n.toDouble().toInt();
    int rVal = r.toDouble().toInt();

    if (rVal > nVal - rVal) {
      rVal = nVal - rVal;
    }

    double result = 1;
    for (int i = 0; i < rVal; i++) {
      result *= (nVal - i);
      result /= (i + 1);
    }
    return result;
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is CombExpr &&
        n.structurallyEquals(other.n) &&
        r.structurallyEquals(other.r);
  }

  @override
  String get termSignature => 'comb:${n.termSignature}:${r.termSignature}';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => false;

  @override
  bool get isOne {
    Expr simplified = simplify();
    return simplified is IntExpr && simplified.isOne;
  }

  @override
  bool get isRational {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  bool get isInteger {
    Expr simplified = simplify();
    return simplified is IntExpr;
  }

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    Expr simplified = simplify();

    if (simplified is IntExpr) {
      return simplified.toMathNode();
    }

    return [CombinationNode(n: n.toMathNode(), r: r.toMathNode())];
  }

  @override
  Expr copy() => CombExpr(n.copy(), r.copy());

  @override
  String toString() => 'C($n,$r)';
}

// ============================================================
// SECTION 13.5: CALCULUS EXPRESSIONS (for nested calculus)
// ============================================================

/// Represents a symbolic derivative: d/d(var) (body)
class DerivativeExpr extends Expr {
  final Expr body;
  final String variable;

  DerivativeExpr(this.body, this.variable);

  @override
  bool get hasImaginary => body.hasImaginary;

  @override
  Expr simplify() {
    final Expr simplifiedBody = body.simplify();
    final Expr? result = SymbolicCalculus._differentiateSymbolic(
      simplifiedBody,
      variable,
    );
    if (result != null) return result.simplify();
    return DerivativeExpr(simplifiedBody, variable);
  }

  @override
  double toDouble() {
    return simplify().toDouble();
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is DerivativeExpr &&
        other.variable == variable &&
        other.body.structurallyEquals(body);
  }

  @override
  String get termSignature => 'diff($variable,${body.termSignature})';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => simplify().isZero;

  @override
  bool get isOne => simplify().isOne;

  @override
  bool get isRational => false;

  @override
  bool get isInteger => false;

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    return [
      DerivativeNode(
        variable: [LiteralNode(text: variable)],
        at: [LiteralNode(text: '')],
        body: body.toMathNode(),
      ),
    ];
  }

  @override
  Expr copy() => DerivativeExpr(body.copy(), variable);

  @override
  String toString() => 'diff($variable, $body)';
}

/// Represents a symbolic integral: ∫ body d(var)
class IntegralExpr extends Expr {
  final Expr body;
  final String variable;
  final Expr? lower;
  final Expr? upper;

  IntegralExpr(this.body, this.variable, {this.lower, this.upper});

  @override
  bool get hasImaginary => body.hasImaginary;

  @override
  Expr simplify() {
    final Expr simplifiedBody = body.simplify();
    // For now, only handle indefinite integrals symbolically
    if (lower == null && upper == null) {
      final Expr? result = SymbolicCalculus._integrateSymbolic(
        simplifiedBody,
        variable,
      );
      if (result != null) {
        return SumExpr([
          result,
          SymbolicCalculus._nextIntegrationConstant(),
        ]).simplify();
      }
    }
    return IntegralExpr(
      simplifiedBody,
      variable,
      lower: lower?.simplify(),
      upper: upper?.simplify(),
    );
  }

  @override
  double toDouble() {
    return simplify().toDouble();
  }

  @override
  bool structurallyEquals(Expr other) {
    if (other is! IntegralExpr) return false;
    if (other.variable != variable) return false;
    if (!other.body.structurallyEquals(body)) return false;
    if ((other.lower == null) != (lower == null)) return false;
    if ((other.upper == null) != (upper == null)) return false;
    if (lower != null && !other.lower!.structurallyEquals(lower!)) return false;
    if (upper != null && !other.upper!.structurallyEquals(upper!)) return false;
    return true;
  }

  @override
  String get termSignature => 'int($variable,${body.termSignature})';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => simplify().isZero;

  @override
  bool get isOne => simplify().isOne;

  @override
  bool get isRational => false;

  @override
  bool get isInteger => false;

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    return [
      IntegralNode(
        variable: [LiteralNode(text: variable)],
        lower: lower?.toMathNode() ?? [LiteralNode(text: '')],
        upper: upper?.toMathNode() ?? [LiteralNode(text: '')],
        body: body.toMathNode(),
      ),
    ];
  }

  @override
  Expr copy() => IntegralExpr(
    body.copy(),
    variable,
    lower: lower?.copy(),
    upper: upper?.copy(),
  );

  @override
  String toString() {
    if (lower == null && upper == null) return 'int($variable, $body)';
    return 'int($variable, $body, $lower, $upper)';
  }
}

// ============================================================
// SECTION 14: VARIABLE EXPRESSION (for equation solving)
// ============================================================

/// Represents a symbolic variable like x, y, z
class VarExpr extends Expr {
  final String name;

  VarExpr(this.name);

  @override
  bool get hasImaginary => false;

  @override
  Expr simplify() => this;

  @override
  double toDouble() {
    throw UnsupportedError('Cannot convert variable $name to double');
  }

  @override
  bool structurallyEquals(Expr other) {
    return other is VarExpr && other.name == name;
  }

  @override
  String get termSignature => 'var:$name';

  @override
  Expr get coefficient => IntExpr.one;

  @override
  Expr get baseExpr => this;

  @override
  bool get isZero => false;

  @override
  bool get isOne => false;

  @override
  bool get isRational => false;

  @override
  bool get isInteger => false;

  @override
  Expr negate() => ProdExpr([IntExpr.negOne, this]);

  @override
  List<MathNode> toMathNode() {
    if (name == 'e_x') return [UnitVectorNode('x')];
    if (name == 'e_y') return [UnitVectorNode('y')];
    if (name == 'e_z') return [UnitVectorNode('z')];
    return [LiteralNode(text: name)];
  }

  @override
  Expr copy() => VarExpr(name);

  @override
  String toString() => name;
}

// ============================================================
// SECTION 15: MATHNODE TO EXPR CONVERTER
// ============================================================

/// Converts a MathNode tree to an Expr tree for symbolic computation
class MathNodeToExpr {
  /// Maximum iterations for summation/product to prevent freezing
  static final BigInt _maxSumProdIterations = BigInt.from(10000);

  /// Reserved function names that should not be treated as variables
  static const Set<String> _reservedNames = {
    'sin',
    'cos',
    'tan',
    'asin',
    'acos',
    'atan',
    'sinh',
    'cosh',
    'tanh',
    'asinh',
    'acosh',
    'atanh',
    'log',
    'ln',
    'sqrt',
    'abs',
    'arg',
    're',
    'im',
    'sgn',
    'exp',
    'perm',
    'comb',
    'sum',
    'prod',
    'diff',
    'int',
    'ans',
  };

  /// Convert a list of MathNodes to an Expr
  static Expr convert(
    List<MathNode> nodes, {
    Map<int, Expr>? ansExpressions,
    Map<String, Expr>? varBindings,
  }) {
    if (nodes.isEmpty) {
      return IntExpr.zero;
    }

    // First, tokenize the nodes to resolve structured content and handle implicit multiplication
    List<_Token> tokens = _tokenize(nodes, ansExpressions, varBindings);

    if (tokens.isEmpty) {
      return IntExpr.zero;
    }

    // Parse tokens into Expr tree
    _TokenParser parser = _TokenParser(tokens);
    return parser.parse().simplify();
  }

  /// Tokenize the MathNode list into a flat list of tokens
  static List<_Token> _tokenize(
    List<MathNode> nodes,
    Map<int, Expr>? ansExpressions,
    Map<String, Expr>? varBindings,
  ) {
    List<_Token> rawTokens = [];
    for (var node in nodes) {
      rawTokens.addAll(_tokenizeNode(node, ansExpressions, varBindings));
    }

    if (rawTokens.isEmpty) return [];

    List<_Token> tokens = [rawTokens[0]];
    for (int i = 1; i < rawTokens.length; i++) {
      _Token lastToken = tokens.last;
      _Token currentToken = rawTokens[i];

      if (_needsImplicitMultiply(lastToken, currentToken)) {
        tokens.add(_Token(_TokenType.operator, '*'));
      }
      tokens.add(currentToken);
    }

    return tokens;
  }

  /// Check if implicit multiplication is needed between two tokens
  static bool _needsImplicitMultiply(_Token left, _Token right) {
    // Number followed by ( or expression
    if (left.type == _TokenType.number && right.type == _TokenType.lparen) {
      return true;
    }
    if (left.type == _TokenType.number && right.type == _TokenType.expr) {
      return true;
    }

    // ) followed by ( or number or expression
    if (left.type == _TokenType.rparen && right.type == _TokenType.lparen) {
      return true;
    }
    if (left.type == _TokenType.rparen && right.type == _TokenType.number) {
      return true;
    }
    if (left.type == _TokenType.rparen && right.type == _TokenType.expr) {
      return true;
    }

    // Expression followed by expression, (, or number
    if (left.type == _TokenType.expr && right.type == _TokenType.expr) {
      return true;
    }
    if (left.type == _TokenType.expr && right.type == _TokenType.lparen) {
      return true;
    }
    if (left.type == _TokenType.expr && right.type == _TokenType.number) {
      return true;
    }

    // Number followed by expression
    if (left.type == _TokenType.number && right.type == _TokenType.expr) {
      return true;
    }

    return false;
  }

  /// Tokenize a single MathNode
  static List<_Token> _tokenizeNode(
    MathNode node,
    Map<int, Expr>? ansExpressions,
    Map<String, Expr>? varBindings,
  ) {
    if (node is LiteralNode) {
      return _tokenizeLiteral(node.text, varBindings);
    }

    if (node is FractionNode) {
      Expr num = convert(
        node.numerator,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr den = convert(
        node.denominator,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      return [_Token.fromExpr(DivExpr(num, den))];
    }

    if (node is ExponentNode) {
      Expr base = convert(
        node.base,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr power = convert(
        node.power,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      return [_Token.fromExpr(PowExpr(base, power))];
    }

    if (node is RootNode) {
      Expr radicand = convert(
        node.radicand,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr index;
      if (node.isSquareRoot) {
        index = IntExpr.two;
      } else {
        index = convert(
          node.index,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
      }
      return [_Token.fromExpr(RootExpr(radicand, index))];
    }

    if (node is LogNode) {
      Expr argument = convert(
        node.argument,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      if (node.isNaturalLog) {
        return [_Token.fromExpr(LogExpr.ln(argument))];
      } else {
        Expr base = convert(
          node.base,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
        return [_Token.fromExpr(LogExpr(base, argument))];
      }
    }

    if (node is TrigNode) {
      Expr argument = convert(
        node.argument,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      TrigFunc func;
      switch (node.function.toLowerCase()) {
        case 'sin':
          func = TrigFunc.sin;
          break;
        case 'cos':
          func = TrigFunc.cos;
          break;
        case 'tan':
          func = TrigFunc.tan;
          break;
        case 'asin':
          func = TrigFunc.asin;
          break;
        case 'acos':
          func = TrigFunc.acos;
          break;
        case 'atan':
          func = TrigFunc.atan;
          break;
        case 'sinh':
          func = TrigFunc.sinh;
          break;
        case 'cosh':
          func = TrigFunc.cosh;
          break;
        case 'tanh':
          func = TrigFunc.tanh;
          break;
        case 'asinh':
          func = TrigFunc.asinh;
          break;
        case 'acosh':
          func = TrigFunc.acosh;
          break;
        case 'atanh':
          func = TrigFunc.atanh;
          break;
        case 'arg':
          func = TrigFunc.arg;
          break;
        case 're':
          func = TrigFunc.re;
          break;
        case 'im':
          func = TrigFunc.im;
          break;
        case 'sgn':
          func = TrigFunc.sgn;
          break;
        case 'abs':
          return [_Token.fromExpr(AbsExpr(argument))];
        default:
          // Unknown function, return as-is
          return [_Token.fromExpr(TrigExpr(TrigFunc.sin, argument))];
      }
      return [_Token.fromExpr(TrigExpr(func, argument))];
    }

    if (node is ParenthesisNode) {
      Expr content = convert(
        node.content,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      // Just return the content - parentheses are for grouping
      return [_Token.fromExpr(content)];
    }

    if (node is PermutationNode) {
      Expr n = convert(
        node.n,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr r = convert(
        node.r,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      return [_Token.fromExpr(PermExpr(n, r))];
    }

    if (node is CombinationNode) {
      Expr n = convert(
        node.n,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr r = convert(
        node.r,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      return [_Token.fromExpr(CombExpr(n, r))];
    }

    if (node is SummationNode || node is ProductNode) {
      final bool isSum = node is SummationNode;
      final variable = isSum ? node.variable : (node as ProductNode).variable;
      final lower = isSum ? node.lower : (node as ProductNode).lower;
      final upper = isSum ? node.upper : (node as ProductNode).upper;
      final body = isSum ? node.body : (node as ProductNode).body;

      final String varName =
          _extractLiteralText(variable).trim().isEmpty
              ? 'x'
              : _extractLiteralText(variable).trim();

      Expr lowerExpr = convert(
        lower,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr upperExpr = convert(
        upper,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );

      BigInt? lowerInt = _tryGetIntValue(lowerExpr);
      BigInt? upperInt = _tryGetIntValue(upperExpr);
      if (lowerInt == null || upperInt == null) {
        // Non-integer bounds — cannot iterate; return empty (no result shown)
        return [];
      }

      if (lowerInt > upperInt) {
        return [_Token.fromExpr(isSum ? IntExpr.zero : IntExpr.one)];
      }

      // Cap iteration count to prevent freezing on large ranges
      if (upperInt - lowerInt + BigInt.one > _maxSumProdIterations) {
        return [];
      }

      Expr acc = isSum ? IntExpr.zero : IntExpr.one;
      BigInt i = lowerInt;
      while (i <= upperInt) {
        final nextBindings = <String, Expr>{
          if (varBindings != null) ...varBindings,
          varName: IntExpr(i),
        };
        Expr term = convert(
          body,
          ansExpressions: ansExpressions,
          varBindings: nextBindings,
        );
        acc =
            isSum
                ? SumExpr([acc, term]).simplify()
                : ProdExpr([acc, term]).simplify();
        i = i + BigInt.one;
      }

      return [_Token.fromExpr(acc)];
    }

    if (node is DerivativeNode) {
      final String varName =
          MathNodeToExpr._extractLiteralText(node.variable).trim().isEmpty
              ? 'x'
              : MathNodeToExpr._extractLiteralText(node.variable).trim();

      final Expr body = convert(
        node.body,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );

      // If 'at' is empty, it's a symbolic derivative
      if (MathNodeToExpr._extractLiteralText(node.at).trim().isEmpty) {
        return [_Token.fromExpr(DerivativeExpr(body, varName))];
      }

      Expr atExpr = convert(
        node.at,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );

      // Prefer symbolic differentiation first so expressions like d/dx(x^2y) at x=9
      // become 18y instead of falling back to unresolved symbolic derivatives.
      final Expr symbolicDerivative = DerivativeExpr(body, varName).simplify();
      if (symbolicDerivative is! DerivativeExpr) {
        final Expr substituted = _substituteExprVariable(
          symbolicDerivative,
          varName,
          atExpr,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
        return [_Token.fromExpr(substituted)];
      }

      double atVal;
      try {
        atVal = atExpr.toDouble();
      } catch (e) {
        // Fallback: if 'at' is symbolic (contains variables), return a DerivativeExpr
        // so it can be handled by SymbolicCalculus if possible.
        return [_Token.fromExpr(DerivativeExpr(body, varName))];
      }

      double h = 1e-6 * math.max(1.0, atVal.abs());
      final nextBindingsPlus = <String, Expr>{
        if (varBindings != null) ...varBindings,
        varName: _doubleToExpr(atVal + h),
      };
      final nextBindingsMinus = <String, Expr>{
        if (varBindings != null) ...varBindings,
        varName: _doubleToExpr(atVal - h),
      };

      double fPlus;
      double fMinus;
      try {
        fPlus =
            convert(
              node.body,
              ansExpressions: ansExpressions,
              varBindings: nextBindingsPlus,
            ).toDouble();
        fMinus =
            convert(
              node.body,
              ansExpressions: ansExpressions,
              varBindings: nextBindingsMinus,
            ).toDouble();
      } catch (e) {
        // Fallback to symbolic if numerical fails
        return [_Token.fromExpr(DerivativeExpr(body, varName))];
      }

      double result = (fPlus - fMinus) / (2 * h);
      if (result.isNaN || result.isInfinite) {
        // Non-differentiable or singular at this point — fall back to symbolic
        return [_Token.fromExpr(DerivativeExpr(body, varName))];
      }
      return [_Token.fromExpr(_doubleToExpr(result).simplify())];
    }

    if (node is IntegralNode) {
      final String varName =
          MathNodeToExpr._extractLiteralText(node.variable).trim().isEmpty
              ? 'x'
              : MathNodeToExpr._extractLiteralText(node.variable).trim();

      // If bounds are empty, it's a symbolic indefinite integral
      if (MathNodeToExpr._extractLiteralText(node.lower).trim().isEmpty &&
          MathNodeToExpr._extractLiteralText(node.upper).trim().isEmpty) {
        Expr body = convert(
          node.body,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
        return [_Token.fromExpr(IntegralExpr(body, varName))];
      }

      Expr lowerExpr = convert(
        node.lower,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );
      Expr upperExpr = convert(
        node.upper,
        ansExpressions: ansExpressions,
        varBindings: varBindings,
      );

      // Definite integral numerical using Simpson's Rule
      double a, b;
      try {
        a = lowerExpr.toDouble();
        b = upperExpr.toDouble();
      } catch (e) {
        // Fallback: if bounds are symbolic, return an IntegralExpr
        Expr body = convert(
          node.body,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
        return [
          _Token.fromExpr(
            IntegralExpr(body, varName, lower: lowerExpr, upper: upperExpr),
          ),
        ];
      }

      double sign = 1.0;
      if (a > b) {
        final temp = a;
        a = b;
        b = temp;
        sign = -1.0;
      }

      const int n = 200; // Simpson's rule requires even n
      double h = (b - a) / n;

      double sum = 0.0;
      for (int i = 0; i <= n; i++) {
        double x = a + h * i;
        final nextBindings = <String, Expr>{
          if (varBindings != null) ...varBindings,
          varName: _doubleToExpr(x),
        };
        double fx;
        try {
          fx =
              convert(
                node.body,
                ansExpressions: ansExpressions,
                varBindings: nextBindings,
              ).toDouble();
        } catch (e) {
          return [_Token.fromExpr(IntExpr.zero)];
        }

        if (fx.isNaN || fx.isInfinite) {
          // Singularity or undefined value in integrand — return symbolic
          Expr body = convert(
            node.body,
            ansExpressions: ansExpressions,
            varBindings: varBindings,
          );
          return [
            _Token.fromExpr(
              IntegralExpr(body, varName, lower: lowerExpr, upper: upperExpr),
            ),
          ];
        }

        if (i == 0 || i == n) {
          sum += fx;
        } else if (i % 2 == 0) {
          sum += 2 * fx;
        } else {
          sum += 4 * fx;
        }
      }

      double result = sign * (sum * h / 3.0);
      if (result.isNaN || result.isInfinite) {
        Expr body = convert(
          node.body,
          ansExpressions: ansExpressions,
          varBindings: varBindings,
        );
        return [
          _Token.fromExpr(
            IntegralExpr(body, varName, lower: lowerExpr, upper: upperExpr),
          ),
        ];
      }
      return [_Token.fromExpr(_doubleToExpr(result).simplify())];
    }

    // Plain `z`: in a complex line that name is already bound to the point of
    // the plane, so the glyph needs no separate identity in the engine. What
    // it adds is upstream — a line containing it is read as complex.
    if (node is ComplexVariableNode) {
      return [_Token.fromExpr(VarExpr('z'))];
    }
    if (node is UnitVectorNode) {
      return [_Token.fromExpr(VarExpr('e_${node.axis}'))];
    }
    if (node is ConstantNode) {
      ConstType type;
      switch (node.constant) {
        case '\u03C0':
          type = ConstType.pi;
          break;
        case 'e':
          type = ConstType.e;
          break;
        case '\u03B5\u2080':
          type = ConstType.epsilon0;
          break;
        case '\u03BC\u2080':
        case '\u00B5\u2080':
          type = ConstType.mu0;
          break;
        case 'c\u2080':
          type = ConstType.c0;
          break;
        case 'e\u207b':
          type = ConstType.eMinus;
          break;
        default:
          return [_Token.fromExpr(VarExpr(node.constant))];
      }
      return [_Token.fromExpr(ConstExpr(type))];
    }

    if (node is AnsNode) {
      // ANS reference - resolve against the map
      String indexStr = _extractLiteralText(node.index);
      int? idx = int.tryParse(indexStr);
      if (idx != null &&
          ansExpressions != null &&
          ansExpressions.containsKey(idx)) {
        Expr? resolved = ansExpressions[idx];
        if (resolved != null) {
          return [_Token.fromExpr(resolved)];
        }
      }
      // If not resolvable, treat as variable ansX
      return [_Token.fromExpr(VarExpr('ans$indexStr'))];
    }

    if (node is NewlineNode) {
      // Ignore newlines for expression evaluation
      return [];
    }

    return [];
  }

  /// Extract text from a list of MathNodes (for simple cases like ANS index)
  static String _extractLiteralText(List<MathNode> nodes) {
    StringBuffer buffer = StringBuffer();
    for (MathNode node in nodes) {
      if (node is LiteralNode) {
        buffer.write(node.text);
      }
    }
    return buffer.toString();
  }

  static BigInt? _tryGetIntValue(Expr expr) {
    if (expr is IntExpr) return expr.value;
    if (expr is FracExpr) {
      if (expr.denominator.value == BigInt.one) {
        return expr.numerator.value;
      }
    }
    return null;
  }

  static Expr _doubleToExpr(double value) {
    return _TokenParser(const <_Token>[])._doubleToFraction(value);
  }

  static Expr _substituteExprVariable(
    Expr expr,
    String variable,
    Expr value, {
    Map<int, Expr>? ansExpressions,
    Map<String, Expr>? varBindings,
  }) {
    return convert(
      expr.toMathNode(),
      ansExpressions: ansExpressions,
      varBindings: <String, Expr>{
        if (varBindings != null) ...varBindings,
        variable: value,
      },
    ).simplify();
  }

  /// Tokenize a literal string into tokens
  static List<_Token> _tokenizeLiteral(
    String text,
    Map<String, Expr>? varBindings,
  ) {
    List<_Token> tokens = [];
    text = text.trim();

    if (text.isEmpty) {
      return tokens;
    }

    // Normalize operators
    text = text.replaceAll('\u00B7', '*'); // middle dot
    text = text.replaceAll('\u00D7', '*'); // times sign
    text = text.replaceAll('\u2212', '-'); // minus sign
    text = text.replaceAll('\u00F7', '/'); // division sign

    int i = 0;
    while (i < text.length) {
      String char = text[i];

      // Skip whitespace
      if (char == ' ') {
        i++;
        continue;
      }

      // Degree suffix: x° -> x * (π/180)
      if (char == '\u00B0' || char == '\u00BA') {
        if (tokens.isNotEmpty && _canApplyPostfixUnit(tokens.last)) {
          tokens.add(_Token(_TokenType.operator, '*'));
          tokens.add(
            _Token.fromExpr(
              DivExpr(ConstExpr.pi, IntExpr.from(180)).simplify(),
            ),
          );
        }
        i++;
        continue;
      }

      // Operators (including postfix '!' for factorial)
      if (char == '+' ||
          char == '-' ||
          char == '*' ||
          char == '/' ||
          char == '^' ||
          char == '%' ||
          char == '!') {
        tokens.add(_Token(_TokenType.operator, char));
        i++;
        continue;
      }

      // Equals
      if (char == '=') {
        tokens.add(_Token(_TokenType.equals, char));
        i++;
        continue;
      }

      // Parentheses
      if (char == '(') {
        tokens.add(_Token(_TokenType.lparen, '('));
        i++;
        continue;
      }
      if (char == ')') {
        tokens.add(_Token(_TokenType.rparen, ')'));
        i++;
        continue;
      }

      // Numbers (including decimals and scientific notation)
      if (_isDigit(char) ||
          (char == '.' && i + 1 < text.length && _isDigit(text[i + 1]))) {
        String numStr = '';
        while (i < text.length && (_isDigit(text[i]) || text[i] == '.')) {
          numStr += text[i];
          i++;
        }

        // Check for scientific notation
        if (i < text.length &&
            (text[i] == 'e' || text[i] == 'E' || text[i] == '\u1D07')) {
          numStr += 'e';
          i++;
          if (i < text.length && (text[i] == '+' || text[i] == '-')) {
            numStr += text[i];
            i++;
          }
          while (i < text.length && _isDigit(text[i])) {
            numStr += text[i];
            i++;
          }
        }

        tokens.add(_Token(_TokenType.number, numStr));
        continue;
      }

      // Check for π (pi constant)
      if (char == 'π' || char == '\u03C0') {
        tokens.add(_Token.fromExpr(ConstExpr.pi));
        i++;
        continue;
      }

      // Letters (variables or function names)
      if (_isLetter(char)) {
        String word = '';
        while (i < text.length && (_isLetter(text[i]) || _isDigit(text[i]))) {
          // Stop if we hit a special character like π
          if (text[i] == 'π' || text[i] == '\u03C0') {
            break;
          }
          word += text[i];
          i++;
        }

        if (varBindings != null && varBindings.containsKey(word)) {
          tokens.add(_Token.fromExpr(varBindings[word]!));
          continue;
        }

        // Radian suffix is a no-op in default radian mode: xrad == x
        if (word.toLowerCase() == 'rad' &&
            tokens.isNotEmpty &&
            _canApplyPostfixUnit(tokens.last)) {
          continue;
        }

        // Check for constants
        if (word == 'pi' || word == 'PI') {
          tokens.add(_Token.fromExpr(ConstExpr.pi));
          continue;
        }

        // Standalone 'e' or 'i'
        if (word == 'e') {
          tokens.add(_Token.fromExpr(ConstExpr.e));
          continue;
        }
        if (word == 'i') {
          tokens.add(_Token.fromExpr(ImaginaryExpr.i));
          continue;
        }
        if (word == 'ε₀' || word == '\u03B5\u2080' || word == 'epsilon0') {
          tokens.add(_Token.fromExpr(ConstExpr.epsilon0));
          continue;
        }
        if (word == 'μ₀' ||
            word == '\u03BC\u2080' ||
            word == '\u00B5\u2080' ||
            word == 'mu0') {
          tokens.add(_Token.fromExpr(ConstExpr.mu0));
          continue;
        }
        if (word == 'c₀' || word == 'c\u2080') {
          tokens.add(_Token.fromExpr(ConstExpr.c0));
          continue;
        }
        if (word == 'e⁻' || word == 'e\u207b') {
          tokens.add(_Token.fromExpr(ConstExpr.eMinus));
          continue;
        }

        // Check for reserved function names (handled by nodes, but just in case)
        if (_reservedNames.contains(word.toLowerCase())) {
          tokens.add(_Token.fromExpr(VarExpr(word)));
          continue;
        }

        // Regular variable(s): split multi-letter into implicit multiplication
        if (word.length == 1) {
          tokens.add(_Token.fromExpr(VarExpr(word)));
        } else {
          // Check if the whole word is a known multiple-character variable (should have been caught by varBindings above)
          // otherwise split it
          for (int j = 0; j < word.length; j++) {
            String c = word[j];
            if (j > 0) {
              tokens.add(_Token(_TokenType.operator, '*'));
            }
            // Check for digits inside word (e.g. x2)
            if (_isDigit(c)) {
              tokens.add(_Token(_TokenType.number, c));
            } else if (varBindings != null && varBindings.containsKey(c)) {
              tokens.add(_Token.fromExpr(varBindings[c]!));
            } else {
              tokens.add(_Token.fromExpr(VarExpr(c)));
            }
          }
        }
        continue;
      }
      // Unknown character - skip
      i++;
    }

    return tokens;
  }

  static bool _canApplyPostfixUnit(_Token token) {
    return token.type == _TokenType.number ||
        token.type == _TokenType.expr ||
        token.type == _TokenType.rparen;
  }

  static bool _isDigit(String char) {
    return char.isNotEmpty && '0123456789'.contains(char);
  }

  static bool _isLetter(String char) {
    return char.isNotEmpty &&
        RegExp(
          r'[a-zA-Z\u0370-\u03FF\u1D00-\u1D7F\u2080-\u2089\u2070-\u207F]',
        ).hasMatch(char);
  }
}

// ============================================================
// SECTION 16: TOKEN TYPES AND PARSER
// ============================================================

enum _TokenType {
  number,
  operator,
  lparen,
  rparen,
  equals,
  expr, // Pre-built Expr from structured nodes
}

class _Token {
  final _TokenType type;
  final String value;
  final Expr? expr;

  _Token(this.type, this.value) : expr = null;

  _Token.fromExpr(Expr e) : type = _TokenType.expr, value = '', expr = e;
}

class _ParsedExpr {
  final Expr expr;
  final bool isPercent;
  const _ParsedExpr(this.expr, [this.isPercent = false]);
}

/// Parser for token list into Expr tree
class _TokenParser {
  final List<_Token> tokens;
  int pos = 0;

  _TokenParser(this.tokens);

  Expr parse() {
    return _parseAddSub().expr;
  }

  _ParsedExpr _parseAddSub() {
    _ParsedExpr left = _parseMulDiv();

    while (pos < tokens.length) {
      _Token token = tokens[pos];
      if (token.type != _TokenType.operator) break;

      String val = token.value.trim();
      bool isPlus = val == '+' || val == '\u002B';
      bool isMinus = val == '-' || val == '\u2212' || val == '\u002D';

      if (!isPlus && !isMinus) break;

      pos++;
      _ParsedExpr right = _parseMulDiv();

      Expr leftExpr = _unwrapPercent(left);
      Expr rightExpr =
          right.isPercent
              ? _percentOf(leftExpr, right.expr)
              : _unwrapPercent(right);

      if (isPlus) {
        left = _ParsedExpr(SumExpr([leftExpr, rightExpr]));
      } else {
        left = _ParsedExpr(SumExpr([leftExpr, rightExpr.negate()]));
      }
    }

    return left;
  }

  _ParsedExpr _parseMulDiv() {
    _ParsedExpr left = _parseUnary();

    while (pos < tokens.length) {
      _Token token = tokens[pos];

      // Explicit multiplication or division
      if (token.type == _TokenType.operator &&
          (token.value == '*' || token.value == '/')) {
        pos++;
        _ParsedExpr right = _parseUnary();
        Expr leftExpr = _unwrapPercent(left);
        Expr rightExpr = _unwrapPercent(right);
        if (token.value == '*') {
          left = _ParsedExpr(ProdExpr([leftExpr, rightExpr]));
        } else {
          left = _ParsedExpr(DivExpr(leftExpr, rightExpr));
        }
      }
      // Implicit multiplication (e.g., 2i, 2(3), (2)3)
      else if (_isNextPrimary()) {
        _ParsedExpr right = _parseUnary();
        Expr leftExpr = _unwrapPercent(left);
        Expr rightExpr = _unwrapPercent(right);
        left = _ParsedExpr(ProdExpr([leftExpr, rightExpr]));
      } else {
        break;
      }
    }

    return left;
  }

  bool _isNextPrimary() {
    if (pos >= tokens.length) return false;
    _Token token = tokens[pos];
    return token.type == _TokenType.number ||
        token.type == _TokenType.lparen ||
        token.type == _TokenType.expr;
  }

  _ParsedExpr _consumePercent(_ParsedExpr parsed) {
    if (pos < tokens.length &&
        tokens[pos].type == _TokenType.operator &&
        tokens[pos].value == '%') {
      pos++;
      return _ParsedExpr(parsed.expr, true);
    }
    return parsed;
  }

  Expr _unwrapPercent(_ParsedExpr parsed) {
    if (parsed.isPercent) {
      return _percentToValue(parsed.expr);
    }
    return parsed.expr;
  }

  Expr _percentToValue(Expr expr) {
    return DivExpr(expr, IntExpr.from(100)).simplify();
  }

  Expr _percentOf(Expr base, Expr percentExpr) {
    return ProdExpr([base, _percentToValue(percentExpr)]).simplify();
  }

  _ParsedExpr _parsePower() {
    _ParsedExpr base = _parsePrimary();

    // Postfix factorial (e.g. `(19+2)!`). Only defined for a non-negative
    // integer; anything else throws so the exact result is dropped and the
    // decimal engine handles it. Computed exactly with BigInt.
    while (pos < tokens.length &&
        tokens[pos].type == _TokenType.operator &&
        tokens[pos].value == '!') {
      pos++;
      final Expr simplified = _unwrapPercent(base).simplify();
      if (simplified is IntExpr && simplified.value >= BigInt.zero) {
        BigInt r = BigInt.one;
        for (BigInt k = BigInt.two; k <= simplified.value; k += BigInt.one) {
          r *= k;
        }
        base = _ParsedExpr(IntExpr(r));
      } else {
        throw const FormatException(
          'factorial requires a non-negative integer',
        );
      }
    }

    // Exponentiation is right-associative and binds tighter than unary minus
    // on the base (so `-2^2 == -4`), while the exponent is parsed via
    // `_parseUnary` (which recurses back into `_parsePower`), giving both
    // right-associativity (`2^3^2 == 2^(3^2)`) and a signed exponent.
    if (pos < tokens.length) {
      _Token token = tokens[pos];
      if (token.type == _TokenType.operator && token.value == '^') {
        pos++;
        _ParsedExpr exponent = _parseUnary();
        Expr baseExpr = _unwrapPercent(base);
        Expr expExpr = _unwrapPercent(exponent);
        base = _ParsedExpr(PowExpr(baseExpr, expExpr));
      }
    }

    return base;
  }

  _ParsedExpr _parseUnary() {
    if (pos < tokens.length) {
      _Token token = tokens[pos];

      if (token.type == _TokenType.operator && token.value == '-') {
        pos++;
        _ParsedExpr operand = _parseUnary();
        return _ParsedExpr(operand.expr.negate(), operand.isPercent);
      }

      if (token.type == _TokenType.operator && token.value == '+') {
        pos++;
        _ParsedExpr operand = _parseUnary();
        return _ParsedExpr(operand.expr, operand.isPercent);
      }
    }

    return _parsePower();
  }

  _ParsedExpr _parsePrimary() {
    if (pos >= tokens.length) {
      return _ParsedExpr(IntExpr.zero);
    }

    _Token token = tokens[pos];

    // Pre-built expression from structured node
    if (token.type == _TokenType.expr) {
      pos++;
      _ParsedExpr parsed = _ParsedExpr(token.expr!);
      return _consumePercent(parsed);
    }

    // Number
    if (token.type == _TokenType.number) {
      pos++;
      _ParsedExpr parsed = _ParsedExpr(_parseNumber(token.value));
      return _consumePercent(parsed);
    }

    // Parenthesized expression
    if (token.type == _TokenType.lparen) {
      pos++; // consume (
      _ParsedExpr inner = _parseAddSub();

      if (pos < tokens.length && tokens[pos].type == _TokenType.rparen) {
        pos++; // consume )
      }

      return _consumePercent(_ParsedExpr(inner.expr));
    }

    // Fallback
    return _ParsedExpr(IntExpr.zero);
  }

  /// Parse a number string into an Expr
  Expr _parseNumber(String numStr) {
    // Try parsing as integer first
    BigInt? intVal = BigInt.tryParse(numStr);
    if (intVal != null) {
      return IntExpr(intVal);
    }

    // Try parsing as double
    double? doubleVal = double.tryParse(numStr);
    if (doubleVal != null) {
      // Convert to fraction if possible
      return _doubleToFraction(doubleVal);
    }

    return IntExpr.zero;
  }

  /// Convert a double to a fraction (for simple decimals)
  /// Convert a double to a fraction (for simple decimals and scientific notation)
  Expr _doubleToFraction(double value) {
    // Handle zero
    if (value == 0) {
      return IntExpr.zero;
    }

    // Check if it's effectively an integer
    if (value.abs() >= 1 && (value - value.roundToDouble()).abs() < 1e-10) {
      return IntExpr.from(value.round());
    }

    // Try a simple rational approximation for repeating decimals
    final Expr? approx = _approximateFraction(value);
    if (approx != null) {
      return approx;
    }

    // Handle scientific notation properly
    // Convert to a fraction: 1e-7 = 1/10000000
    String str = value.toString();

    // Check for scientific notation in the string representation
    int eIndex = str.toLowerCase().indexOf('e');
    if (eIndex != -1) {
      // Parse mantissa and exponent
      String mantissaStr = str.substring(0, eIndex);
      String expStr = str.substring(eIndex + 1);

      double mantissa = double.parse(mantissaStr);
      int exponent = int.parse(expStr);

      // Convert mantissa to fraction first
      Expr mantissaExpr = _mantissaToFraction(mantissa);

      if (exponent >= 0) {
        // Positive exponent: multiply by 10^exponent
        BigInt multiplier = BigInt.from(10).pow(exponent);
        if (mantissaExpr is IntExpr) {
          return IntExpr(mantissaExpr.value * multiplier);
        } else if (mantissaExpr is FracExpr) {
          return FracExpr(
            IntExpr(mantissaExpr.numerator.value * multiplier),
            mantissaExpr.denominator,
          ).simplify();
        }
      } else {
        // Negative exponent: divide by 10^|exponent|
        BigInt divisor = BigInt.from(10).pow(-exponent);
        if (mantissaExpr is IntExpr) {
          return FracExpr(mantissaExpr, IntExpr(divisor)).simplify();
        } else if (mantissaExpr is FracExpr) {
          return FracExpr(
            mantissaExpr.numerator,
            IntExpr(mantissaExpr.denominator.value * divisor),
          ).simplify();
        }
      }

      // Fallback
      return FracExpr(
        IntExpr.one,
        IntExpr(BigInt.from(10).pow(-exponent)),
      ).simplify();
    }

    // Regular decimal handling
    int decimalIndex = str.indexOf('.');
    if (decimalIndex == -1) {
      return IntExpr.from(value.toInt());
    }

    String decimalPart = str.substring(decimalIndex + 1);
    int decimalPlaces = decimalPart.length;

    // Limit decimal places for sanity
    if (decimalPlaces > 15) {
      decimalPlaces = 15;
    }

    // Create fraction: value = intPart + decPart/10^decimalPlaces
    BigInt denominator = BigInt.from(10).pow(decimalPlaces);
    BigInt numerator = BigInt.from((value * denominator.toDouble()).round());

    return FracExpr(IntExpr(numerator), IntExpr(denominator)).simplify();
  }

  Expr? _approximateFraction(
    double value, {
    int maxDenominator = 1000,
    double tolerance = 1e-7,
  }) {
    if (!value.isFinite) return null;

    final double absValue = value.abs();
    if (absValue == 0) return IntExpr.zero;

    final (num, den) = _bestRationalApproximation(absValue, maxDenominator);
    if (den == 0) return null;

    final double approx = num / den;
    final double error = (absValue - approx).abs();
    final double allowed = tolerance * math.max(1.0, absValue);

    if (error > allowed) return null;

    if (num == 0) {
      return absValue < (tolerance * 0.1) ? IntExpr.zero : null;
    }

    final int signedNum = value.isNegative ? -num : num;
    if (den == 1) {
      return IntExpr.from(signedNum);
    }

    return FracExpr(
      IntExpr(BigInt.from(signedNum)),
      IntExpr(BigInt.from(den)),
    ).simplify();
  }

  (int, int) _bestRationalApproximation(double value, int maxDenominator) {
    if (value.isNaN || value.isInfinite) return (0, 0);
    if (value == value.floorToDouble()) return (value.toInt(), 1);

    const double epsilon = 1e-12;
    int a0 = value.floor();
    int p0 = 1;
    int q0 = 0;
    int p1 = a0;
    int q1 = 1;
    double frac = value - a0;

    while (frac > epsilon) {
      double inv = 1.0 / frac;
      int a = inv.floor();
      int p2 = a * p1 + p0;
      int q2 = a * q1 + q0;

      if (q2 > maxDenominator) {
        break;
      }

      p0 = p1;
      q0 = q1;
      p1 = p2;
      q1 = q2;
      frac = inv - a;
    }

    return (p1, q1);
  }

  /// Helper to convert a mantissa (like 1.5) to a fraction
  Expr _mantissaToFraction(double mantissa) {
    if (mantissa == mantissa.roundToDouble()) {
      return IntExpr.from(mantissa.round());
    }

    String str = mantissa.toString();
    int decimalIndex = str.indexOf('.');
    if (decimalIndex == -1) {
      return IntExpr.from(mantissa.toInt());
    }

    String decimalPart = str.substring(decimalIndex + 1);
    int decimalPlaces = decimalPart.length;

    BigInt denominator = BigInt.from(10).pow(decimalPlaces);
    BigInt numerator = BigInt.from((mantissa * denominator.toDouble()).round());

    return FracExpr(IntExpr(numerator), IntExpr(denominator)).simplify();
  }
}

// ============================================================
// SECTION 17: MAIN ENGINE CLASS
// ============================================================

/// Main entry point for exact symbolic math computation
class ExactMathEngine {
  /// Evaluate an expression from MathNode tree
  static ExactResult evaluate(
    List<MathNode> expression, {
    Map<int, Expr>? ansExpressions,
  }) {
    return SymbolicCalculus.withFreshIntegrationConstants(() {
      try {
        if (_isEmptyExpression(expression)) {
          return ExactResult.empty();
        }

        // Normalize expression nodes (split embedded = and \n)
        expression = _normalizeNodes(expression);

        final ExactResult? symbolicCalculus = _tryBuildSymbolicCalculusResult(
          expression,
          ansExpressions: ansExpressions,
        );
        if (symbolicCalculus != null) {
          return symbolicCalculus;
        }

        if (_isIncompleteExpression(expression)) {
          // print('DEBUG: Incomplete expression');
          return ExactResult.empty();
        }

        // 1. Handle multi-line results (system of equations)
        if (expression.any((n) => n is NewlineNode)) {
          // print('DEBUG: Routing to _solveMultiLine');
          return _solveMultiLine(expression, ansExpressions);
        }

        // 2. Handle single equation
        if (expression.any((n) => n is LiteralNode && n.text.contains('='))) {
          // print('DEBUG: Routing to _solveSingleEquation');
          return _solveSingleEquation(expression, ansExpressions);
        }

        // 3. Regular expression evaluation
        Expr expr = MathNodeToExpr.convert(
          expression,
          ansExpressions: ansExpressions,
        );

        Expr simplified = expr.simplify();

        double? numerical;
        try {
          numerical = simplified.toDouble();
        } catch (e) {
          numerical = null;
        }

        if (numerical != null && numerical.isNaN) {
          // If it's NaN but has imaginary parts, that's expected for pure 'i' expressions
          if (!(simplified.hasImaginary)) {
            return ExactResult.empty();
          }
        }

        if (numerical != null && numerical.isInfinite) {
          return ExactResult(
            expr: simplified,
            mathNodes: [
              LiteralNode(text: numerical.isNegative ? '\u2212∞' : '∞'),
            ],
            numerical: numerical,
          );
        }

        return ExactResult(
          expr: simplified,
          mathNodes: simplified.toMathNode(),
          numerical: numerical,
          isExact: _hasIrrationalParts(simplified),
        );
      } catch (e) {
        return ExactResult.empty();
      }
    });
  }

  static ExactResult? _tryBuildSymbolicCalculusResult(
    List<MathNode> expression, {
    Map<int, Expr>? ansExpressions,
  }) {
    return SymbolicCalculus.tryBuildSymbolicCalculusResult(
      expression,
      ansExpressions: ansExpressions,
    );
  }

  static ExactResult _buildExactResultFromExpr(Expr expr) {
    final Expr simplified = expr.simplify();
    double? numerical;
    try {
      numerical = simplified.toDouble();
    } catch (_) {
      numerical = null;
    }
    return ExactResult(
      expr: simplified,
      mathNodes: simplified.toMathNode(),
      numerical: numerical,
      isExact: _hasIrrationalParts(simplified),
    );
  }

  /// Format an Expr as a decimal-oriented string while keeping symbolic structure.
  /// This converts rational coefficients to decimals using current precision settings.
  static String formatExprDecimal(Expr expr) {
    return _DecimalExprFormatter.format(expr);
  }

  static List<MathNode> _cloneNodes(List<MathNode> nodes) {
    return nodes.map(_cloneNode).toList();
  }

  static MathNode _cloneNode(MathNode node) {
    if (node is LiteralNode) {
      return LiteralNode(text: node.text);
    }
    if (node is FractionNode) {
      return FractionNode(
        num: _cloneNodes(node.numerator),
        den: _cloneNodes(node.denominator),
      );
    }
    if (node is ExponentNode) {
      return ExponentNode(
        base: _cloneNodes(node.base),
        power: _cloneNodes(node.power),
      );
    }
    if (node is LogNode) {
      return LogNode(
        base: _cloneNodes(node.base),
        argument: _cloneNodes(node.argument),
        isNaturalLog: node.isNaturalLog,
      );
    }
    if (node is TrigNode) {
      return TrigNode(
        function: node.function,
        argument: _cloneNodes(node.argument),
      );
    }
    if (node is RootNode) {
      return RootNode(
        index: _cloneNodes(node.index),
        radicand: _cloneNodes(node.radicand),
        isSquareRoot: node.isSquareRoot,
      );
    }
    if (node is PermutationNode) {
      return PermutationNode(n: _cloneNodes(node.n), r: _cloneNodes(node.r));
    }
    if (node is CombinationNode) {
      return CombinationNode(n: _cloneNodes(node.n), r: _cloneNodes(node.r));
    }
    if (node is SummationNode) {
      return SummationNode(
        variable: _cloneNodes(node.variable),
        lower: _cloneNodes(node.lower),
        upper: _cloneNodes(node.upper),
        body: _cloneNodes(node.body),
      );
    }
    if (node is ProductNode) {
      return ProductNode(
        variable: _cloneNodes(node.variable),
        lower: _cloneNodes(node.lower),
        upper: _cloneNodes(node.upper),
        body: _cloneNodes(node.body),
      );
    }
    if (node is DerivativeNode) {
      return DerivativeNode(
        variable: _cloneNodes(node.variable),
        at: _cloneNodes(node.at),
        body: _cloneNodes(node.body),
      );
    }
    if (node is IntegralNode) {
      return IntegralNode(
        variable: _cloneNodes(node.variable),
        lower: _cloneNodes(node.lower),
        upper: _cloneNodes(node.upper),
        body: _cloneNodes(node.body),
      );
    }
    if (node is ParenthesisNode) {
      return ParenthesisNode(content: _cloneNodes(node.content));
    }
    if (node is AnsNode) {
      return AnsNode(index: _cloneNodes(node.index));
    }
    if (node is ConstantNode) {
      return ConstantNode(node.constant);
    }
    if (node is ComplexVariableNode) {
      return ComplexVariableNode();
    }
    if (node is UnitVectorNode) {
      return UnitVectorNode(node.axis);
    }
    if (node is ComplexNode) {
      return ComplexNode(content: _cloneNodes(node.content));
    }
    if (node is NewlineNode) {
      return NewlineNode();
    }
    return LiteralNode(text: '');
  }

  static ExactResult _solveMultiLine(
    List<MathNode> expression,
    Map<int, Expr>? ansExpressions,
  ) {
    List<List<MathNode>> linesData = [];
    List<MathNode> currentLine = [];
    for (var node in expression) {
      if (node is NewlineNode) {
        if (currentLine.isNotEmpty) linesData.add(List.from(currentLine));
        currentLine = [];
      } else {
        currentLine.add(node);
      }
    }
    if (currentLine.isNotEmpty) linesData.add(currentLine);

    if (linesData.isEmpty) return ExactResult.empty();

    // If it's multi-line, it's either an expression list or a system of equations
    bool isSystem = linesData.any(
      (line) => line.any((n) => n is LiteralNode && n.text.contains('=')),
    );

    if (isSystem) {
      return _solveLinearSystem(linesData, ansExpressions);
    }

    // Default: Multi-line expressions (though usually results are single line)
    // For now, just evaluate the first line or join them?
    // Let's just evaluate the first line for simplicity if it's not a system
    return evaluate(linesData.first, ansExpressions: ansExpressions);
  }

  static ExactResult _solveSingleEquation(
    List<MathNode> expression,
    Map<int, Expr>? ansExpressions,
  ) {
    // Split into left and right
    int eqIndex = expression.indexWhere(
      (n) => n is LiteralNode && n.text.contains('='),
    );
    if (eqIndex == -1) return ExactResult.empty();

    List<MathNode> leftNodes = expression.sublist(0, eqIndex);
    List<MathNode> rightNodes = expression.sublist(eqIndex + 1);

    // Some literal nodes might contain '=' and other text, but usually it's just '='
    // If LiteralNode has "x = 5", we need to be careful.
    // In our renderer, '=' is usually its own LiteralNode.

    Expr left = MathNodeToExpr.convert(
      leftNodes,
      ansExpressions: ansExpressions,
    );
    Expr right = MathNodeToExpr.convert(
      rightNodes,
      ansExpressions: ansExpressions,
    );

    // Rearrange to f(x) = 0
    Expr combined = SumExpr([left, right.negate()]).simplify();

    // Find variables
    Set<String> variables = _findVariables(combined);
    if (variables.isEmpty) return ExactResult.empty();
    if (variables.length > 1) {
      // Cannot solve single equation with multiple variables symbolically easily here
      return ExactResult.empty();
    }

    String varName = variables.first;

    // Try quadratic solver
    var solutions = _solveQuadratic(combined, varName);
    if (solutions != null && solutions.isNotEmpty) {
      List<MathNode> nodes = [];
      for (int i = 0; i < solutions.length; i++) {
        if (i > 0) nodes.add(NewlineNode());
        nodes.add(LiteralNode(text: '$varName = '));
        nodes.addAll(solutions[i].toMathNode());
      }
      return ExactResult(
        expr: solutions.first, // Just a representative
        mathNodes: nodes,
        isExact: true,
      );
    }

    // Try linear solver if quadratic failed (or was linear)
    var linearSol = _solveLinear(combined, varName);
    if (linearSol != null) {
      List<MathNode> nodes = [LiteralNode(text: '$varName = ')];
      nodes.addAll(linearSol.toMathNode());
      return ExactResult(expr: linearSol, mathNodes: nodes, isExact: true);
    }

    return ExactResult.empty();
  }

  static Set<String> _findVariables(Expr expr) {
    Set<String> vars = {};
    if (expr is VarExpr) {
      vars.add(expr.name);
    } else if (expr is SumExpr) {
      for (var t in expr.terms) {
        vars.addAll(_findVariables(t));
      }
    } else if (expr is ProdExpr) {
      for (var f in expr.factors) {
        vars.addAll(_findVariables(f));
      }
    } else if (expr is DivExpr) {
      vars.addAll(_findVariables(expr.numerator));
      vars.addAll(_findVariables(expr.denominator));
    } else if (expr is PowExpr) {
      vars.addAll(_findVariables(expr.base));
      vars.addAll(_findVariables(expr.exponent));
    } else if (expr is RootExpr) {
      vars.addAll(_findVariables(expr.radicand));
      vars.addAll(_findVariables(expr.index));
    } else if (expr is LogExpr) {
      vars.addAll(_findVariables(expr.argument));
      vars.addAll(_findVariables(expr.base));
    } else if (expr is TrigExpr) {
      vars.addAll(_findVariables(expr.argument));
    }
    return vars;
  }

  static ({Expr a, Expr b, Expr c})? _polyCoeffs(Expr expr, String varName) {
    Expr add(Expr left, Expr right) => SumExpr([left, right]).simplify();
    Expr mul(Expr left, Expr right) => ProdExpr([left, right]).simplify();

    ({Expr a, Expr b, Expr c})? multiplyPoly(
      ({Expr a, Expr b, Expr c}) p,
      ({Expr a, Expr b, Expr c}) q,
    ) {
      final a4 = mul(p.a, q.a);
      final a3 = add(mul(p.a, q.b), mul(p.b, q.a));
      if (!a4.isZero || !a3.isZero) return null;

      final a2 = add(add(mul(p.a, q.c), mul(p.b, q.b)), mul(p.c, q.a));
      final a1 = add(mul(p.b, q.c), mul(p.c, q.b));
      final a0 = mul(p.c, q.c);
      return (a: a2, b: a1, c: a0);
    }

    expr = expr.simplify();

    if (!_findVariables(expr).contains(varName)) {
      return (a: IntExpr.zero, b: IntExpr.zero, c: expr);
    }

    if (expr is VarExpr && expr.name == varName) {
      return (a: IntExpr.zero, b: IntExpr.one, c: IntExpr.zero);
    }

    if (expr is PowExpr) {
      if (expr.exponent is IntExpr) {
        final exp = (expr.exponent as IntExpr).value;
        if (exp == BigInt.zero) {
          return (a: IntExpr.zero, b: IntExpr.zero, c: IntExpr.one);
        }
        if (exp == BigInt.one) {
          return _polyCoeffs(expr.base, varName);
        }
        if (exp == BigInt.two) {
          final baseCoeffs = _polyCoeffs(expr.base, varName);
          if (baseCoeffs == null) return null;
          if (!baseCoeffs.a.isZero) return null;
          return multiplyPoly(baseCoeffs, baseCoeffs);
        }
      }
      return null;
    }

    if (expr is SumExpr) {
      Expr a = IntExpr.zero;
      Expr b = IntExpr.zero;
      Expr c = IntExpr.zero;
      for (final term in expr.terms) {
        final termCoeffs = _polyCoeffs(term, varName);
        if (termCoeffs == null) return null;
        a = add(a, termCoeffs.a);
        b = add(b, termCoeffs.b);
        c = add(c, termCoeffs.c);
      }
      return (a: a, b: b, c: c);
    }

    if (expr is ProdExpr) {
      ({Expr a, Expr b, Expr c}) acc = (
        a: IntExpr.zero,
        b: IntExpr.zero,
        c: IntExpr.one,
      );
      for (final factor in expr.factors) {
        final factorCoeffs = _polyCoeffs(factor, varName);
        if (factorCoeffs == null) return null;
        final next = multiplyPoly(acc, factorCoeffs);
        if (next == null) return null;
        acc = next;
      }
      return acc;
    }

    if (expr is DivExpr) {
      if (_findVariables(expr.denominator).contains(varName)) return null;
      final numCoeffs = _polyCoeffs(expr.numerator, varName);
      if (numCoeffs == null) return null;
      final den = expr.denominator.simplify();
      Expr div(Expr value) => DivExpr(value, den).simplify();
      return (a: div(numCoeffs.a), b: div(numCoeffs.b), c: div(numCoeffs.c));
    }

    return null;
  }

  static Map<String, Expr> _getPolynomialCoeffs(Expr expr, String varName) {
    final coeffs = _polyCoeffs(expr, varName);
    return {
      'c2': coeffs?.a ?? IntExpr.zero,
      'c1': coeffs?.b ?? IntExpr.zero,
      'c0': coeffs?.c ?? IntExpr.zero,
    };
  }

  static Expr? _solveLinear(Expr combined, String varName) {
    var coeffs = _getLinearCoeffs(combined, varName);
    if (coeffs == null) return null;
    Expr a = coeffs.$1;
    Expr b = coeffs.$2; // b is the constant term in ax + b = 0

    if (a.isZero) return null;

    // x = -b / a
    return DivExpr(b.negate(), a).simplify();
  }

  static (Expr, Expr)? _getLinearCoeffs(Expr expr, String varName) {
    final coeffs = _polyCoeffs(expr, varName);
    if (coeffs == null) return null;
    if (!coeffs.a.isZero) return null;
    return (coeffs.b, coeffs.c);
  }

  static List<Expr>? _solveQuadratic(Expr combined, String varName) {
    var coeffs = _getPolynomialCoeffs(combined, varName);
    Expr a = coeffs['c2']!;
    Expr b = coeffs['c1']!;
    Expr c = coeffs['c0']!;

    if (a.isZero) return null;

    // x = (-b ± √(b^2 - 4ac)) / 2a
    Expr discriminant =
        SumExpr([
          PowExpr(b, IntExpr.two),
          ProdExpr([IntExpr.from(-4), a, c]),
        ]).simplify();

    Expr rootD = RootExpr(discriminant, IntExpr.two).simplify();

    final Expr denom = ProdExpr([IntExpr.two, a]).simplify();
    final Expr baseTerm = DivExpr(b.negate(), denom).simplify();
    final Expr rootCoeff = DivExpr(IntExpr.one, denom).simplify();
    final Expr rootTerm = ProdExpr([rootCoeff, rootD]).simplify();

    Expr sol1 = SumExpr([baseTerm, rootTerm]).simplify();
    Expr sol2 = SumExpr([baseTerm, rootTerm.negate()]).simplify();

    bool zeroDisc = discriminant.isZero;
    try {
      final double discVal = discriminant.toDouble();
      if (discVal.abs() < 1e-12) {
        zeroDisc = true;
      } else {
        zeroDisc = false;
      }
    } catch (_) {}

    if (zeroDisc) return [sol1];
    return [sol1, sol2];
  }

  static ExactResult _solveLinearSystem(
    List<List<MathNode>> lines,
    Map<int, Expr>? ansExpressions,
  ) {
    List<(Map<String, Expr>, Expr)> equations = [];
    Set<String> allVars = {};

    for (var line in lines) {
      int eqIndex = line.indexWhere(
        (n) => n is LiteralNode && n.text.contains('='),
      );
      Expr left, right;
      if (eqIndex != -1) {
        left = MathNodeToExpr.convert(
          line.sublist(0, eqIndex),
          ansExpressions: ansExpressions,
        );
        right = MathNodeToExpr.convert(
          line.sublist(eqIndex + 1),
          ansExpressions: ansExpressions,
        );
      } else {
        left = MathNodeToExpr.convert(line, ansExpressions: ansExpressions);
        right = IntExpr.zero;
      }

      Expr combined = SumExpr([left, right.negate()]).simplify();
      Set<String> lineVars = _findVariables(combined);
      allVars.addAll(lineVars);

      // Extract coefficients ax + by + ... + const = 0 => ax + by + ... = -const
      Map<String, Expr> coeffs = {};
      Expr constant = IntExpr.zero;

      List<Expr> terms = (combined is SumExpr) ? combined.terms : [combined];
      for (var term in terms) {
        bool matched = false;
        for (var v in lineVars) {
          if (term is VarExpr && term.name == v) {
            coeffs[v] =
                SumExpr([coeffs[v] ?? IntExpr.zero, IntExpr.one]).simplify();
            matched = true;
            break;
          } else if (term is ProdExpr &&
              term.factors.any((f) => f is VarExpr && f.name == v)) {
            List<Expr> others =
                term.factors
                    .where((f) => !(f is VarExpr && f.name == v))
                    .toList();
            Expr coeff =
                others.isEmpty
                    ? IntExpr.one
                    : (others.length == 1 ? others.first : ProdExpr(others));
            coeffs[v] = SumExpr([coeffs[v] ?? IntExpr.zero, coeff]).simplify();
            matched = true;
            break;
          }
        }
        if (!matched) {
          constant = SumExpr([constant, term]).simplify();
        }
      }
      equations.add((coeffs, constant.negate().simplify()));
    }

    List<String> sortedVars = allVars.toList()..sort();
    if (sortedVars.length > equations.length || sortedVars.isEmpty) {
      return ExactResult.empty();
    }

    // We only solve square systems for now
    if (sortedVars.length != equations.length) {
      // Try solving as many as possible? No, usually expect square.
      return ExactResult.empty();
    }

    // Matrix form: A * X = B
    List<List<Expr>> matrixA = [];
    List<Expr> vectorB = [];

    for (var eq in equations) {
      List<Expr> row = [];
      for (var v in sortedVars) {
        row.add(eq.$1[v] ?? IntExpr.zero);
      }
      matrixA.add(row);
      vectorB.add(eq.$2);
    }

    Expr detA = _determinantExpr(matrixA).simplify();
    if (detA.isZero) return ExactResult.empty();

    List<MathNode> resultNodes = [];
    for (int i = 0; i < sortedVars.length; i++) {
      List<List<Expr>> matrixAi = [];
      for (int r = 0; r < matrixA.length; r++) {
        List<Expr> row = List.from(matrixA[r]);
        row[i] = vectorB[r];
        matrixAi.add(row);
      }
      Expr detAi = _determinantExpr(matrixAi).simplify();
      Expr solution = DivExpr(detAi, detA).simplify();

      if (i > 0) resultNodes.add(NewlineNode());
      resultNodes.add(LiteralNode(text: '${sortedVars[i]} = '));
      resultNodes.addAll(solution.toMathNode());
    }

    return ExactResult(
      expr: IntExpr.zero, // Dummy
      mathNodes: resultNodes,
      isExact: true,
    );
  }

  static Expr _determinantExpr(List<List<Expr>> matrix) {
    int n = matrix.length;
    if (n == 1) return matrix[0][0];
    if (n == 2) {
      return SumExpr([
        ProdExpr([matrix[0][0], matrix[1][1]]),
        ProdExpr([IntExpr.negOne, matrix[0][1], matrix[1][0]]),
      ]);
    }

    List<Expr> terms = [];
    for (int i = 0; i < n; i++) {
      List<List<Expr>> subMatrix = [];
      for (int j = 1; j < n; j++) {
        List<Expr> row = List.from(matrix[j]);
        row.removeAt(i);
        subMatrix.add(row);
      }
      Expr subDet = _determinantExpr(subMatrix);
      Expr term = ProdExpr([matrix[0][i], subDet]);
      if (i % 2 != 0) term = term.negate();
      terms.add(term);
    }
    return SumExpr(terms);
  }

  /// Normalizes expression nodes by splitting LiteralNodes containing '=' or '\n'
  static List<MathNode> _normalizeNodes(List<MathNode> nodes) {
    List<MathNode> result = [];
    for (var node in nodes) {
      if (node is LiteralNode) {
        String text = node.text;
        if (text.contains('\n') || text.contains('=')) {
          // Split by \n first
          List<String> lines = text.split('\n');
          for (int i = 0; i < lines.length; i++) {
            if (i > 0) result.add(NewlineNode());

            // Split by = within each line
            String line = lines[i];
            List<String> parts = line.split('=');
            for (int j = 0; j < parts.length; j++) {
              if (j > 0) result.add(LiteralNode(text: '='));
              if (parts[j].isNotEmpty) {
                result.add(LiteralNode(text: parts[j]));
              }
            }
          }
        } else {
          result.add(node);
        }
      } else {
        result.add(node);
      }
    }
    return result;
  }

  /// Check if the expression is empty
  static bool _isEmptyExpression(List<MathNode> expression) {
    if (expression.isEmpty) return true;

    for (MathNode node in expression) {
      if (node is LiteralNode) {
        String text = node.text.trim();
        // Remove operators to see if there's actual content
        text =
            text
                .replaceAll(RegExp(r'[+\-*/^·×÷\u00B7\u00D7\u2212]'), '')
                .trim();
        if (text.isNotEmpty) return false;
      } else if (node is! NewlineNode) {
        // Any structured node (fraction, root, etc.) means non-empty
        return false;
      }
    }
    return true;
  }

  /// Check if the expression is incomplete

  // In math_engine_exact.dart, update the _isIncompleteExpression method:

  /// Check if the expression is incomplete
  // In math_engine_exact.dart, REPLACE _hasEmptyRequiredFields():
  static bool _hasEmptyRequiredFields(List<MathNode> nodes) {
    for (MathNode node in nodes) {
      if (node is FractionNode) {
        if (_isNodeListEmpty(node.numerator) ||
            _isNodeListEmpty(node.denominator)) {
          return true;
        }
        if (_hasInvalidContent(node.numerator) ||
            _hasInvalidContent(node.denominator)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.numerator) ||
            _hasEmptyRequiredFields(node.denominator)) {
          return true;
        }
      } else if (node is ExponentNode) {
        if (_isNodeListEmpty(node.base) || _isNodeListEmpty(node.power)) {
          return true;
        }
        if (_hasInvalidContent(node.base) || _hasInvalidContent(node.power)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.base) ||
            _hasEmptyRequiredFields(node.power)) {
          return true;
        }
      } else if (node is RootNode) {
        if (_isNodeListEmpty(node.radicand)) {
          return true;
        }
        if (_hasInvalidContent(node.radicand)) {
          return true;
        }
        if (!node.isSquareRoot && _isNodeListEmpty(node.index)) {
          return true;
        }
        if (!node.isSquareRoot && _hasInvalidContent(node.index)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.radicand)) {
          return true;
        }
        if (!node.isSquareRoot && _hasEmptyRequiredFields(node.index)) {
          return true;
        }
      } else if (node is LogNode) {
        if (_isNodeListEmpty(node.argument)) {
          return true;
        }
        if (_hasInvalidContent(node.argument)) {
          return true;
        }
        if (!node.isNaturalLog && _isNodeListEmpty(node.base)) {
          return true;
        }
        if (!node.isNaturalLog && _hasInvalidContent(node.base)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.argument)) {
          return true;
        }
        if (!node.isNaturalLog && _hasEmptyRequiredFields(node.base)) {
          return true;
        }
      } else if (node is TrigNode) {
        if (_isNodeListEmpty(node.argument)) {
          return true;
        }
        if (_hasInvalidContent(node.argument)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.argument)) {
          return true;
        }
      } else if (node is ParenthesisNode) {
        if (_isNodeListEmpty(node.content)) {
          return true;
        }
        if (_hasInvalidContent(node.content)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.content)) {
          return true;
        }
      } else if (node is PermutationNode) {
        if (_isNodeListEmpty(node.n) || _isNodeListEmpty(node.r)) {
          return true;
        }
        if (_hasInvalidContent(node.n) || _hasInvalidContent(node.r)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.n) ||
            _hasEmptyRequiredFields(node.r)) {
          return true;
        }
      } else if (node is CombinationNode) {
        if (_isNodeListEmpty(node.n) || _isNodeListEmpty(node.r)) {
          return true;
        }
        if (_hasInvalidContent(node.n) || _hasInvalidContent(node.r)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.n) ||
            _hasEmptyRequiredFields(node.r)) {
          return true;
        }
      } else if (node is SummationNode) {
        if (_isNodeListEmpty(node.variable) ||
            _isNodeListEmpty(node.lower) ||
            _isNodeListEmpty(node.upper) ||
            _isNodeListEmpty(node.body)) {
          return true;
        }
        if (_hasInvalidContent(node.variable) ||
            _hasInvalidContent(node.lower) ||
            _hasInvalidContent(node.upper) ||
            _hasInvalidContent(node.body)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.variable) ||
            _hasEmptyRequiredFields(node.lower) ||
            _hasEmptyRequiredFields(node.upper) ||
            _hasEmptyRequiredFields(node.body)) {
          return true;
        }
      } else if (node is ProductNode) {
        if (_isNodeListEmpty(node.variable) ||
            _isNodeListEmpty(node.lower) ||
            _isNodeListEmpty(node.upper) ||
            _isNodeListEmpty(node.body)) {
          return true;
        }
        if (_hasInvalidContent(node.variable) ||
            _hasInvalidContent(node.lower) ||
            _hasInvalidContent(node.upper) ||
            _hasInvalidContent(node.body)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.variable) ||
            _hasEmptyRequiredFields(node.lower) ||
            _hasEmptyRequiredFields(node.upper) ||
            _hasEmptyRequiredFields(node.body)) {
          return true;
        }
      } else if (node is DerivativeNode) {
        if (_isNodeListEmpty(node.variable) || _isNodeListEmpty(node.body)) {
          return true;
        }
        if (_hasInvalidContent(node.variable) ||
            _hasInvalidContent(node.body)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.variable) ||
            _hasEmptyRequiredFields(node.body)) {
          return true;
        }
      } else if (node is IntegralNode) {
        if (_isNodeListEmpty(node.variable) || _isNodeListEmpty(node.body)) {
          return true;
        }
        if (_hasInvalidContent(node.variable) ||
            _hasInvalidContent(node.body)) {
          return true;
        }
        if (_hasEmptyRequiredFields(node.variable) ||
            _hasEmptyRequiredFields(node.body)) {
          return true;
        }
      }
    }
    return false;
  }

  // ADD this new helper method in ExactMathEngine class:
  /// Check if a node list has invalid content (trailing operators, etc.)
  static bool _hasInvalidContent(List<MathNode> nodes) {
    if (nodes.isEmpty) return false;

    // Serialize the content and check for issues
    String content = _serializeNodeListForValidation(nodes);

    if (content.isEmpty) return false;

    String trimmed = content.trim();
    if (trimmed.isEmpty) return false;

    // Check for trailing operators
    if (_endsWithOperator(trimmed)) {
      return true;
    }

    // Check for leading invalid operators (*, /, ^)
    if (_startsWithInvalidOperator(trimmed)) {
      return true;
    }

    // Check for consecutive operators
    if (_hasConsecutiveOperators(trimmed)) {
      return true;
    }

    return false;
  }

  // ADD this new helper method in ExactMathEngine class:
  /// Serialize a node list for validation (simpler than full serialization)
  static String _serializeNodeListForValidation(List<MathNode> nodes) {
    StringBuffer buffer = StringBuffer();

    for (MathNode node in nodes) {
      if (node is LiteralNode) {
        buffer.write(node.text);
      } else if (node is FractionNode) {
        String num = _serializeNodeListForValidation(node.numerator);
        String den = _serializeNodeListForValidation(node.denominator);
        if (num.trim().isEmpty || den.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($num/$den)');
        }
      } else if (node is ExponentNode) {
        String base = _serializeNodeListForValidation(node.base);
        String power = _serializeNodeListForValidation(node.power);
        if (base.trim().isEmpty || power.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($base^$power)');
        }
      } else if (node is RootNode) {
        String radicand = _serializeNodeListForValidation(node.radicand);
        if (radicand.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('sqrt($radicand)');
        }
      } else if (node is LogNode) {
        String arg = _serializeNodeListForValidation(node.argument);
        if (arg.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('log($arg)');
        }
      } else if (node is TrigNode) {
        String arg = _serializeNodeListForValidation(node.argument);
        if (arg.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('${node.function}($arg)');
        }
      } else if (node is ParenthesisNode) {
        String content = _serializeNodeListForValidation(node.content);
        if (content.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($content)');
        }
      } else if (node is PermutationNode) {
        String n = _serializeNodeListForValidation(node.n);
        String r = _serializeNodeListForValidation(node.r);
        if (n.trim().isEmpty || r.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('P($n,$r)');
        }
      } else if (node is CombinationNode) {
        String n = _serializeNodeListForValidation(node.n);
        String r = _serializeNodeListForValidation(node.r);
        if (n.trim().isEmpty || r.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('C($n,$r)');
        }
      } else if (node is AnsNode) {
        buffer.write('ans');
      }
    }

    return buffer.toString();
  }

  // 4. REVERT _isNodeListEmpty to the original working version:
  static bool _isNodeListEmpty(List<MathNode> nodes) {
    if (nodes.isEmpty) return true;

    for (MathNode node in nodes) {
      if (node is LiteralNode) {
        if (node.text.trim().isNotEmpty) {
          return false;
        }
      } else if (node is! NewlineNode) {
        return false;
      }
    }
    return true;
  }

  // 5. Keep _isIncompleteExpression as it was originally (from your code):
  static bool _isIncompleteExpression(List<MathNode> expression) {
    // Get the serialized form to check for trailing operators
    String serialized = _serializeForValidation(expression);

    if (serialized.isEmpty) return true;

    // Check if ends with an operator
    String trimmed = serialized.trim();
    if (trimmed.isEmpty) return true;

    // Check for trailing operators
    if (_endsWithOperator(trimmed)) {
      return true;
    }

    // Check for leading operators (except minus for negative)
    if (_startsWithInvalidOperator(trimmed)) {
      return true;
    }

    // Check for consecutive operators (like ++ or +*)
    if (_hasConsecutiveOperators(trimmed)) {
      return true;
    }

    // Check for empty required fields in structured nodes
    if (_hasEmptyRequiredFields(expression)) {
      return true;
    }

    return false;
  }

  /// Serialize expression for validation purposes
  static String _serializeForValidation(List<MathNode> nodes) {
    StringBuffer buffer = StringBuffer();

    for (MathNode node in nodes) {
      if (node is LiteralNode) {
        buffer.write(node.text);
      } else if (node is ComplexVariableNode) {
        buffer.write('z');
      } else if (node is UnitVectorNode) {
        buffer.write('e_${node.axis}');
      } else if (node is ConstantNode) {
        buffer.write(node.constant);
      } else if (node is FractionNode) {
        String num = _serializeForValidation(node.numerator);
        String den = _serializeForValidation(node.denominator);
        if (num.trim().isEmpty || den.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($num/$den)');
        }
      } else if (node is ExponentNode) {
        String base = _serializeForValidation(node.base);
        String power = _serializeForValidation(node.power);
        if (base.trim().isEmpty || power.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($base^$power)');
        }
      } else if (node is RootNode) {
        String radicand = _serializeForValidation(node.radicand);
        if (radicand.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('sqrt($radicand)');
        }
      } else if (node is LogNode) {
        String arg = _serializeForValidation(node.argument);
        if (arg.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('log($arg)');
        }
      } else if (node is TrigNode) {
        String arg = _serializeForValidation(node.argument);
        if (arg.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('${node.function}($arg)');
        }
      } else if (node is ParenthesisNode) {
        String content = _serializeForValidation(node.content);
        if (content.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('($content)');
        }
      } else if (node is PermutationNode) {
        String n = _serializeForValidation(node.n);
        String r = _serializeForValidation(node.r);
        if (n.trim().isEmpty || r.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('P($n,$r)');
        }
      } else if (node is CombinationNode) {
        String n = _serializeForValidation(node.n);
        String r = _serializeForValidation(node.r);
        if (n.trim().isEmpty || r.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('C($n,$r)');
        }
      } else if (node is SummationNode) {
        String v = _serializeForValidation(node.variable);
        String lower = _serializeForValidation(node.lower);
        String upper = _serializeForValidation(node.upper);
        String body = _serializeForValidation(node.body);
        if (v.trim().isEmpty ||
            lower.trim().isEmpty ||
            upper.trim().isEmpty ||
            body.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('sum($v,$lower,$upper,$body)');
        }
      } else if (node is DerivativeNode) {
        String v = _serializeForValidation(node.variable);
        String at = _serializeForValidation(node.at);
        String body = _serializeForValidation(node.body);
        if (v.trim().isEmpty || at.trim().isEmpty || body.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('diff($v,$at,$body)');
        }
      } else if (node is IntegralNode) {
        String v = _serializeForValidation(node.variable);
        String lower = _serializeForValidation(node.lower);
        String upper = _serializeForValidation(node.upper);
        String body = _serializeForValidation(node.body);
        if (v.trim().isEmpty ||
            lower.trim().isEmpty ||
            upper.trim().isEmpty ||
            body.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('int($v,$lower,$upper,$body)');
        }
      } else if (node is ProductNode) {
        String v = _serializeForValidation(node.variable);
        String lower = _serializeForValidation(node.lower);
        String upper = _serializeForValidation(node.upper);
        String body = _serializeForValidation(node.body);
        if (v.trim().isEmpty ||
            lower.trim().isEmpty ||
            upper.trim().isEmpty ||
            body.trim().isEmpty) {
          buffer.write('EMPTY_FIELD');
        } else {
          buffer.write('prod($v,$lower,$upper,$body)');
        }
      } else if (node is AnsNode) {
        buffer.write('ans');
      }
    }

    return buffer.toString();
  }

  /// Check if string ends with an operator
  static bool _endsWithOperator(String s) {
    if (s.isEmpty) return false;

    // Normalize operators
    s = s
        .replaceAll('\u00B7', '*')
        .replaceAll('\u00D7', '*')
        .replaceAll('\u2212', '-')
        .replaceAll('÷', '/');

    String lastChar = s[s.length - 1];
    return lastChar == '+' ||
        lastChar == '-' ||
        lastChar == '*' ||
        lastChar == '/' ||
        lastChar == '^' ||
        lastChar == '(';
  }

  /// Check if string starts with an invalid operator
  static bool _startsWithInvalidOperator(String s) {
    if (s.isEmpty) return false;

    // Normalize operators
    s = s
        .replaceAll('\u00B7', '*')
        .replaceAll('\u00D7', '*')
        .replaceAll('\u2212', '-')
        .replaceAll('÷', '/');

    String firstChar = s[0];
    // Leading minus is OK (negative number), leading plus is OK too
    // But leading *, /, ^ are invalid
    return firstChar == '*' || firstChar == '/' || firstChar == '^';
  }

  /// Check for consecutive operators
  static bool _hasConsecutiveOperators(String s) {
    // Normalize operators
    s = s
        .replaceAll('\u00B7', '*')
        .replaceAll('\u00D7', '*')
        .replaceAll('\u2212', '-')
        .replaceAll('÷', '/');

    // Check for patterns like ++, +*, *+, etc.
    // But allow +- or -+ (for things like 3+-2)
    RegExp badPatterns = RegExp(r'[+\-*/^][*/^]|[*/^][+\-*/^]');
    return badPatterns.hasMatch(s);
  }

  /// Format a complex expression numerically
  static String _formatComplexNumerical(Expr expr, int precision) {
    // Try to split into real and imaginary parts
    // Very simple split for Sum and Prod
    double real = 0;
    double imag = 0;

    void process(Expr e, double multiplier) {
      if (e is SumExpr) {
        for (var t in e.terms) {
          process(t, multiplier);
        }
      } else if (e is ProdExpr) {
        double rPart = 1.0;
        bool hasI = false;
        for (var f in e.factors) {
          if (f is ImaginaryExpr) {
            hasI = true;
          } else {
            rPart *= f.toDouble();
          }
        }
        if (hasI) {
          imag += multiplier * rPart;
        } else {
          real += multiplier * rPart;
        }
      } else if (e is ImaginaryExpr) {
        imag += multiplier;
      } else {
        real += multiplier * e.toDouble();
      }
    }

    process(expr, 1.0);

    String formatPart(double d) {
      if ((d - d.roundToDouble()).abs() < 1e-10) {
        return d.round().toString();
      }
      String f = d.toStringAsFixed(precision);
      if (f.contains('.')) {
        f = f.replaceAll(RegExp(r'0+$'), '');
        f = f.replaceAll(RegExp(r'\.$'), '');
      }
      return f;
    }

    if (imag == 0) return formatPart(real);
    if (real == 0) {
      if (imag == 1) return 'i';
      if (imag == -1) return '\u2212i';
      String iPartStr = formatPart(imag);
      if (iPartStr.startsWith('-') || iPartStr.startsWith('\u2212')) {
        String absPart = iPartStr.substring(1);
        return '\u2212${absPart}i';
      }
      return '${iPartStr}i';
    }

    String sign = imag < 0 ? ' \u2212 ' : ' + ';
    double absImag = imag.abs();
    String iPartStr = absImag == 1 ? 'i' : '${formatPart(absImag)}i';

    return '${formatPart(real)}$sign$iPartStr';
  }

  /// Check if expression has irrational parts
  static bool _hasIrrationalParts(Expr expr) {
    if (expr is RootExpr) {
      Expr simplified = expr.simplify();
      return simplified is RootExpr ||
          (simplified is ProdExpr &&
              simplified.factors.any((f) => f is RootExpr));
    }
    if (expr is LogExpr) {
      Expr simplified = expr.simplify();
      return simplified is LogExpr;
    }
    if (expr is TrigExpr) {
      Expr simplified = expr.simplify();
      return simplified is TrigExpr;
    }
    if (expr is ConstExpr) return true;
    if (expr is SumExpr) return expr.terms.any(_hasIrrationalParts);
    if (expr is ProdExpr) return expr.factors.any(_hasIrrationalParts);
    if (expr is DivExpr) {
      return _hasIrrationalParts(expr.numerator) ||
          _hasIrrationalParts(expr.denominator);
    }
    if (expr is PowExpr) {
      return _hasIrrationalParts(expr.base) ||
          _hasIrrationalParts(expr.exponent);
    }
    return false;
  }

  /// Evaluate and return only the MathNode result
  static List<MathNode>? evaluateToMathNode(List<MathNode> expression) {
    ExactResult result = evaluate(expression);
    if (result.hasError || result.isEmpty) return null;
    return result.mathNodes;
  }

  /// Evaluate and return only the numerical approximation
  static double? evaluateToDouble(List<MathNode> expression) {
    ExactResult result = evaluate(expression);
    if (result.isEmpty) return null;
    return result.numerical;
  }
}

/// Result of exact evaluation
/// Result of exact evaluation
/// Result of exact evaluation
class ExactResult {
  final Expr? expr;
  final List<MathNode>? mathNodes;
  final double? numerical;
  final bool isExact;
  final String? error;
  final bool isEmpty;

  ExactResult({this.expr, this.mathNodes, this.numerical, this.isExact = true})
    : error = null,
      isEmpty = false;

  ExactResult.error(this.error)
    : expr = null,
      mathNodes = null,
      numerical = null,
      isExact = false,
      isEmpty = false;

  ExactResult.empty()
    : expr = null,
      mathNodes = null,
      numerical = null,
      isExact = false,
      error = null,
      isEmpty = true;

  bool get hasError => error != null;

  String toExactString() {
    if (hasError) return error!;
    if (isEmpty) return '';
    if (expr == null) return '';
    return expr!.toString();
  }

  String toNumericalString({int precision = 6}) {
    if (isEmpty) return '';

    if (expr != null && expr!.hasImaginary) {
      return ExactMathEngine._formatComplexNumerical(expr!, precision);
    }

    if (numerical == null) return '';
    if (numerical!.isNaN) return '';
    if (numerical!.isInfinite) {
      return numerical!.isNegative ? '\u2212∞' : '∞';
    }

    if ((numerical! - numerical!.roundToDouble()).abs() < 1e-10) {
      String s = numerical!.round().abs().toString();
      return numerical!.isNegative ? '\u2212$s' : s;
    }

    String formatted = numerical!.abs().toStringAsFixed(precision);
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    return numerical!.isNegative ? '\u2212$formatted' : formatted;
  }
}

class _DecimalExprFormatter {
  static String format(Expr expr) {
    return _format(expr.simplify());
  }

  static String _format(Expr expr) {
    if (expr is IntExpr || expr is FracExpr) {
      return MathSolverNew.formatResult(expr.toDouble());
    }
    if (expr is ConstExpr || expr is ImaginaryExpr) {
      return expr.toString();
    }
    if (expr is VarExpr) {
      return expr.name;
    }
    if (expr is SumExpr) {
      return _formatSum(expr);
    }
    if (expr is ProdExpr) {
      return _formatProduct(expr);
    }
    if (expr is DivExpr) {
      return _formatDivision(expr);
    }
    if (expr is PowExpr) {
      return _formatPower(expr);
    }
    if (expr is RootExpr) {
      return _formatRoot(expr);
    }
    if (expr is LogExpr) {
      return _formatLog(expr);
    }
    if (expr is TrigExpr) {
      return _formatTrig(expr);
    }
    if (expr is AbsExpr) {
      return '|${_format(expr.operand)}|';
    }
    if (expr is PermExpr) {
      return 'P(${_format(expr.n)},${_format(expr.r)})';
    }
    if (expr is CombExpr) {
      return 'C(${_format(expr.n)},${_format(expr.r)})';
    }
    return expr.toString();
  }

  static String _formatSum(SumExpr sumExpr) {
    if (sumExpr.terms.isEmpty) return '0';
    final terms = sumExpr.terms;
    final buffer = StringBuffer();

    for (int i = 0; i < terms.length; i++) {
      final term = terms[i];
      final bool isNegative = _isNegativeTerm(term);
      final Expr absTerm = isNegative ? _absoluteTerm(term) : term;
      final String termText = _format(absTerm);

      if (i == 0) {
        if (isNegative) {
          buffer.write('-');
        }
        buffer.write(termText);
      } else {
        buffer.write(isNegative ? ' - ' : ' + ');
        buffer.write(termText);
      }
    }
    return buffer.toString();
  }

  static String _formatProduct(ProdExpr prodExpr) {
    if (prodExpr.factors.isEmpty) return '1';
    final factors = prodExpr.factors;
    final buffer = StringBuffer();

    for (int i = 0; i < factors.length; i++) {
      final factor = factors[i];
      String factorText = _format(factor);

      if (_needsParensInProduct(factor)) {
        factorText = '($factorText)';
      }

      if (i > 0) {
        final Expr prev = factors[i - 1];
        final bool implicit = _isImplicitMultiplication(prev, factor);
        if (!implicit) {
          buffer.write('·');
        }
      }
      buffer.write(factorText);
    }

    return buffer.toString();
  }

  static String _formatDivision(DivExpr divExpr) {
    final Expr numerator = divExpr.numerator.simplify();
    final Expr denominator = divExpr.denominator.simplify();

    final _RationalSplit numSplit = _splitLeadingRational(numerator);
    final _RationalSplit denSplit = _splitLeadingRational(denominator);

    if (numSplit.hasNumeric || denSplit.hasNumeric) {
      final double denomCoeff =
          denSplit.coefficient == 0.0 ? 1.0 : denSplit.coefficient;
      final double coeff = numSplit.coefficient / denomCoeff;

      final Expr remainderNumerator = numSplit.remainder;
      final Expr remainderDenominator = denSplit.remainder;

      final bool numIsOne =
          remainderNumerator is IntExpr && remainderNumerator.isOne;
      final bool denIsOne =
          remainderDenominator is IntExpr && remainderDenominator.isOne;

      final String coeffText = MathSolverNew.formatResult(coeff);

      if (numIsOne && denIsOne) {
        return coeffText;
      }

      if (denIsOne) {
        String remainderText = _format(remainderNumerator);
        if (_needsParensInProduct(remainderNumerator)) {
          remainderText = '($remainderText)';
        }

        if (coeffText == '1') return remainderText;
        if (coeffText == '-1') return '-$remainderText';

        final bool implicit = _isImplicitCoeffTarget(remainderNumerator);
        final String joiner = implicit ? '' : '·';
        return '$coeffText$joiner$remainderText';
      }

      final String numText = numIsOne ? '1' : _format(remainderNumerator);
      final String denText = _format(remainderDenominator);
      String fracText = '($numText)/($denText)';

      if (coeffText == '1') return fracText;
      if (coeffText == '-1') return '-$fracText';

      return '$coeffText·$fracText';
    }

    final String numText = _format(numerator);
    final String denText = _format(denominator);
    return '($numText)/($denText)';
  }

  static String _formatPower(PowExpr powExpr) {
    String baseText = _format(powExpr.base);
    String expText = _format(powExpr.exponent);

    if (_needsParensInPowerBase(powExpr.base)) {
      baseText = '($baseText)';
    }
    if (_needsParensInPowerExponent(powExpr.exponent)) {
      expText = '($expText)';
    }

    return '$baseText^$expText';
  }

  static String _formatRoot(RootExpr rootExpr) {
    final String radicandText = _format(rootExpr.radicand);
    if (rootExpr.index is IntExpr &&
        (rootExpr.index as IntExpr).value == BigInt.two) {
      return 'sqrt($radicandText)';
    }
    final String indexText = _format(rootExpr.index);
    return 'root($indexText,$radicandText)';
  }

  static String _formatLog(LogExpr logExpr) {
    final String argText = _format(logExpr.argument);
    if (logExpr.isNaturalLog) {
      return 'ln($argText)';
    }
    final String baseText = _format(logExpr.base);
    return 'log_$baseText($argText)';
  }

  static String _formatTrig(TrigExpr trigExpr) {
    final String argText = _format(trigExpr.argument);
    return '${trigExpr.func.name}($argText)';
  }

  static bool _needsParensInProduct(Expr expr) {
    return expr is SumExpr || expr is DivExpr;
  }

  static bool _needsParensInPowerBase(Expr expr) {
    return expr is SumExpr || expr is ProdExpr || expr is DivExpr;
  }

  static bool _needsParensInPowerExponent(Expr expr) {
    return expr is SumExpr || expr is ProdExpr || expr is DivExpr;
  }

  static bool _isImplicitMultiplication(Expr left, Expr right) {
    return ProdExpr._isImplicitMultiplicationPair(left, right);
  }

  static bool _isImplicitCoeffTarget(Expr expr) {
    return ProdExpr._isImplicitCoeffTarget(expr);
  }

  static _RationalSplit _splitLeadingRational(Expr expr) {
    if (expr is IntExpr || expr is FracExpr) {
      return _RationalSplit(
        coefficient: expr.toDouble(),
        remainder: IntExpr.one,
        hasNumeric: true,
      );
    }

    if (expr is ProdExpr &&
        expr.factors.isNotEmpty &&
        expr.factors.first.isRational) {
      final double coeff = expr.factors.first.toDouble();
      final rest = expr.factors.sublist(1);
      final Expr remainder =
          rest.isEmpty
              ? IntExpr.one
              : (rest.length == 1 ? rest.first : ProdExpr(rest).simplify());
      return _RationalSplit(
        coefficient: coeff,
        remainder: remainder,
        hasNumeric: true,
      );
    }

    return _RationalSplit(coefficient: 1.0, remainder: expr, hasNumeric: false);
  }

  static bool _isNegativeTerm(Expr term) {
    if (term is IntExpr) return term.value < BigInt.zero;
    if (term is FracExpr) return term.numerator.value < BigInt.zero;
    if (term is ProdExpr && term.factors.isNotEmpty) {
      Expr coeff = term.coefficient;
      if (coeff is IntExpr) return coeff.value < BigInt.zero;
      if (coeff is FracExpr) return coeff.numerator.value < BigInt.zero;
    }
    if (term is DivExpr) {
      if (term.numerator is IntExpr) {
        return (term.numerator as IntExpr).value < BigInt.zero;
      }
      if (term.numerator is FracExpr) {
        return (term.numerator as FracExpr).numerator.value < BigInt.zero;
      }
    }
    return false;
  }

  static Expr _absoluteTerm(Expr term) {
    if (term is IntExpr) return IntExpr(term.value.abs());
    if (term is FracExpr) {
      return FracExpr(IntExpr(term.numerator.value.abs()), term.denominator);
    }
    if (term is ProdExpr && term.factors.isNotEmpty) {
      Expr coeff = term.coefficient;
      Expr base = term.baseExpr;

      Expr absCoeff;
      if (coeff is IntExpr) {
        absCoeff = IntExpr(coeff.value.abs());
      } else if (coeff is FracExpr) {
        absCoeff = FracExpr(
          IntExpr(coeff.numerator.value.abs()),
          coeff.denominator,
        );
      } else {
        absCoeff = coeff;
      }

      if (absCoeff.isOne) return base;
      return ProdExpr([absCoeff, base]);
    }
    if (term is DivExpr) {
      if (term.numerator is IntExpr &&
          (term.numerator as IntExpr).value < BigInt.zero) {
        return DivExpr(
          IntExpr((term.numerator as IntExpr).value.abs()),
          term.denominator,
        );
      }
      if (term.numerator is FracExpr &&
          (term.numerator as FracExpr).numerator.value < BigInt.zero) {
        return DivExpr(
          FracExpr(
            IntExpr((term.numerator as FracExpr).numerator.value.abs()),
            (term.numerator as FracExpr).denominator,
          ),
          term.denominator,
        );
      }
    }
    return term;
  }
}

class _RationalSplit {
  final double coefficient;
  final Expr remainder;
  final bool hasNumeric;

  const _RationalSplit({
    required this.coefficient,
    required this.remainder,
    required this.hasNumeric,
  });
}

// ============================================================
// SECTION 18: UTILITY EXTENSIONS
// ============================================================

/// Extension methods for easier Expr creation
extension ExprExtensions on int {
  IntExpr toExpr() => IntExpr.from(this);
}

extension BigIntExprExtensions on BigInt {
  IntExpr toExpr() => IntExpr(this);
}

/// Helper function to create expressions easily
Expr frac(int num, int den) => FracExpr.from(num, den);
Expr sqrt(Expr radicand) => RootExpr.sqrt(radicand);
Expr sqrtInt(int n) => RootExpr.sqrt(IntExpr.from(n));
Expr sum(List<Expr> terms) => SumExpr(terms);
Expr prod(List<Expr> factors) => ProdExpr(factors);
Expr pow(Expr base, Expr exp) => PowExpr(base, exp);
Expr ln(Expr arg) => LogExpr.ln(arg);
Expr log(Expr base, Expr arg) => LogExpr(base, arg);
