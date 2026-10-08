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

// ============================================================
// GAMMA AND FACTORIAL
// ============================================================

/// The Lanczos approximation's coefficients for g = 7, nine terms: good to
/// about fifteen digits across the right half-plane.
const double lanczosG = 7;
const List<double> lanczosCoefficients = <double>[
  0.99999999999980993,
  676.5203681218851,
  -1259.1392167224028,
  771.32342877765313,
  -176.61502916214059,
  12.507343278686905,
  -0.13857109526572012,
  9.9843695780195716e-6,
  1.5056327351493116e-7,
];

/// √(2π), which every Lanczos sum is scaled by.
const double sqrtTwoPi = 2.5066282746310002;

/// n! for n from 0 to 170, each the double nearest the exact value. Past 170
/// a factorial is more than a double can hold.
final List<double> _wholeFactorials = () {
  final List<double> out = <double>[1];
  BigInt f = BigInt.one;
  for (int n = 1; n <= 170; n++) {
    f *= BigInt.from(n);
    out.add(f.toDouble());
  }
  return out;
}();

/// Γ(x), the gamma function: (x − 1)! extended to every real number.
///
/// The Lanczos approximation right of ½ and the reflection formula
/// Γ(x)·Γ(1 − x) = π / sin(πx) left of it. A whole number is looked up
/// rather than approximated, so Γ(5) is 24 and not 23.999999999999996. NaN at
/// zero and the negative whole numbers, which are poles; infinite past about
/// 171.6, where Γ outgrows a double.
double gamma(double x) {
  if (x.isNaN || x == double.negativeInfinity) return double.nan;
  if (x == double.infinity) return double.infinity;
  if (x == x.roundToDouble()) {
    if (x <= 0) return double.nan;
    if (x <= 171) return _wholeFactorials[x.toInt() - 1];
    return double.infinity;
  }
  if (x < 0.5) return math.pi / (_sinPi(x) * gamma(1 - x));
  final double z = x - 1;
  double a = lanczosCoefficients[0];
  for (int i = 1; i < lanczosCoefficients.length; i++) {
    a += lanczosCoefficients[i] / (z + i);
  }
  final double t = z + lanczosG + 0.5;
  // t^(z + ½) taken in two halves, with e^(−t) between them: whole, it
  // overflows near x = 143 while Γ itself is finite to 171.
  final double half = math.pow(t, (z + 0.5) / 2).toDouble();
  return sqrtTwoPi * a * half * (half * math.exp(-t));
}

/// x!, which is Γ(x + 1): the factorial of every real number but the
/// negative whole ones.
double factorial(double x) => gamma(x + 1);

/// sin(πx), reduced first: sin(math.pi * x) loses digits as x grows, and the
/// reflection formula divides by it.
double _sinPi(double x) {
  final double r = x % 2; // [0, 2), whatever the sign of x
  return math.sin(math.pi * r);
}
