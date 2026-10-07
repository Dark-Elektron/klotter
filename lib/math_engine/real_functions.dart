import 'dart:math' as math;

// Hyperbolic functions and their inverses, for doubles.
//
// dart:math has none of them, and the textbook formulas built from exp each
// lose part of the range. (e^a − e^−a) / (e^a + e^−a) is inf/inf, so NaN, once
// e^a overflows near |a| = 710: tanh(1000x) plotted as nothing past x = 0.71.
// log(a + √(a² + 1)) cancels to log 0 for large negative a, so asinh(−1e8)
// had no value, and a² overflows for acosh long before the answer does.
//
// Each function here is the series near zero, the asymptote far out, and the
// formula in between, which keeps full range and about twelve correct digits
// or better everywhere.

/// Below this the series' first two terms are exact to double precision, while
/// the exp and log forms lose digits to cancellation.
const double _tiny = 1e-4;

/// Beyond this e^−2|a| < 5e−18, below the last bit of a double beside 1, so the
/// smaller exponential no longer changes the result.
const double hyperbolicFar = 20;

/// Beyond this a² ± 1 is a² to double precision, and squaring would soon
/// overflow while the answer itself is barely past 20.
const double _huge = 1e8;

/// The hyperbolic sine.
double sinh(double a) {
  final double x = a.abs();
  if (x < _tiny) return a + a * a * a / 6;
  if (x > hyperbolicFar) {
    // e^x / 2, written so it does not overflow before the answer does.
    final double r = math.exp(x - math.ln2);
    return a.isNegative ? -r : r;
  }
  final double e = math.exp(a);
  return (e - 1 / e) / 2;
}

/// The hyperbolic cosine.
double cosh(double a) {
  final double x = a.abs();
  if (x > hyperbolicFar) return math.exp(x - math.ln2);
  final double e = math.exp(x);
  return (e + 1 / e) / 2;
}

/// The hyperbolic tangent: ±1 far out rather than inf/inf.
double tanh(double a) {
  final double x = a.abs();
  final double r;
  if (x < _tiny) {
    r = x - x * x * x / 3;
  } else if (x > hyperbolicFar) {
    r = 1;
  } else {
    final double e = math.exp(-2 * x);
    r = (1 - e) / (1 + e);
  }
  return a.isNegative ? -r : r;
}

/// The inverse hyperbolic sine, odd by construction so a large negative
/// argument does not cancel to log 0.
double asinh(double a) {
  final double x = a.abs();
  final double r;
  if (x < _tiny) {
    r = x - x * x * x / 6;
  } else if (x > _huge) {
    r = math.log(x) + math.ln2;
  } else {
    r = math.log(x + math.sqrt(x * x + 1));
  }
  return a.isNegative ? -r : r;
}

/// The inverse hyperbolic cosine, NaN below 1.
double acosh(double a) {
  if (a > _huge) return math.log(a) + math.ln2;
  // (a − 1)(a + 1) rather than a² − 1: a − 1 is exact near 1, where the
  // difference of squares loses most of its digits.
  return math.log(a + math.sqrt((a - 1) * (a + 1)));
}

/// The inverse hyperbolic tangent: ±∞ at ±1, NaN beyond.
double atanh(double a) {
  final double x = a.abs();
  final double r;
  if (x < _tiny) {
    r = x + x * x * x / 3;
  } else {
    r = 0.5 * math.log((1 + x) / (1 - x));
  }
  return a.isNegative ? -r : r;
}
