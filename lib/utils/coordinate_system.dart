import 'dart:math' as math;

/// The coordinate systems an expression can be written in.
///
/// Symbols follow the convention of most calculus texts: θ is the angle
/// around the z axis in both cylindrical and spherical, and φ is measured
/// down from the z axis. That keeps the systems apart where it matters —
/// cylindrical `r` is the distance from the axis while spherical `ρ` is the
/// distance from the origin, different quantities that a shared letter would
/// make easy to confuse — and lets θ mean the same thing in both.
///
/// It is not ISO 80000-2, nor most physics texts, which write spherical as
/// (r, ϑ, φ) with the two angles the other way round: ϑ down from the axis and
/// φ around it.
enum CoordinateSystem {
  cartesian,

  /// Polar in 2D, cylindrical once z is involved — the same (r, θ) pair either
  /// way, so they are one system here rather than two that differ by whether
  /// the third variable happens to be used.
  cylindrical,
  spherical,
}

/// Combining circumflex, the hat on a unit vector.
const String _hat = '̂';

extension CoordinateSystemInfo on CoordinateSystem {
  String get label => switch (this) {
    CoordinateSystem.cartesian => 'Cartesian',
    CoordinateSystem.cylindrical => 'Polar / cylindrical',
    CoordinateSystem.spherical => 'Spherical',
  };

  /// The three variables, in axis order.
  ///
  /// φ is the textbook name for the angle down from the z axis. The engine
  /// used to read it
  /// as the golden ratio, but nothing could produce that constant — no key
  /// inserts it and there is no way to type the character — so the symbol was
  /// dead and is now the coordinate.
  List<String> get variables => switch (this) {
    CoordinateSystem.cartesian => const <String>['x', 'y', 'z'],
    CoordinateSystem.cylindrical => const <String>['r', 'θ', 'z'],
    CoordinateSystem.spherical => const <String>['ρ', 'θ', 'φ'],
  };

  /// What a unit vector key inserts — the bare symbol, without the hat.
  List<String> get unitVectorAxes => variables;

  /// What a unit vector key shows.
  List<String> get unitVectorLabels => <String>[
    for (final String v in variables) '$v$_hat',
  ];

  /// A short reminder of what the three symbols mean, for the long-press menu.
  String get hint => switch (this) {
    CoordinateSystem.cartesian => 'x, y, z',
    CoordinateSystem.cylindrical => 'r, θ, z',
    CoordinateSystem.spherical => 'ρ, θ, φ',
  };
}

/// Every symbol any system uses, so a parser can recognise them all whatever
/// the cell is currently set to.
final Set<String> allCoordinateSymbols = <String>{
  for (final CoordinateSystem s in CoordinateSystem.values) ...s.variables,
};

/// Convert a Cartesian sample into the variables of [system].
///
/// Plots are drawn by sampling Cartesian space, so an expression written in
/// another system is evaluated by converting the sample point rather than by
/// rewriting the expression. That makes both forms work through the renderers
/// already in place: `ρ = 1` becomes the unit sphere because at every sampled
/// (x, y, z) the value of ρ is known, and `r < 1 + cos(θ)` shades a cardioid
/// through the same code that shades any other region.
///
/// A point has more than one polar address — (r, θ + 2π) and (−r, θ + π) are
/// the same point as (r, θ) — and this returns the first: r ≥ 0, θ in its
/// first turn. A line that needs the others reads them from there (see
/// `PlotExpression.evaluate`), and the explicit forms `r = f(θ)` and
/// `ρ = f(θ, φ)` are traced by sweeping their angles instead
/// (see `PlotExpression.sweepsTheta`).
///
/// Returns the three values in the same order as [CoordinateSystemInfo.variables].
(double, double, double) toCoordinates(
  CoordinateSystem system,
  double x,
  double y,
  double z,
) {
  switch (system) {
    case CoordinateSystem.cartesian:
      return (x, y, z);
    case CoordinateSystem.cylindrical:
      // r is the distance from the z axis; θ is measured from the x axis.
      return (math.sqrt(x * x + y * y), _azimuth(x, y), z);
    case CoordinateSystem.spherical:
      final double r = math.sqrt(x * x + y * y);
      final double rho = math.sqrt(r * r + z * z);
      // θ from the x axis in the xy-plane, ϕ down from the z axis. At the
      // origin ϕ is undefined, and atan2(0, 0) answers zero, which is as good
      // as anything and keeps the sample finite rather than seeding NaN
      // through a whole surface.
      //
      // atan2 rather than acos(z / ρ): acos is flat at ±1, so near the z axis
      // it lost every digit — a point 1e-8 off the axis came back as ϕ = 0.
      final double phi = math.atan2(r, z);
      return (rho, _azimuth(x, y), phi);
  }
}

/// The angle around the z axis, from the positive x axis, in [0, 2π).
///
/// One turn has to start somewhere, and wherever it does θ jumps by 2π. It
/// starts on the positive x axis, as it does in most texts, so `0 < θ < 3π/2`
/// is three quadrants and r = θ traces its first whole turn. atan2 alone
/// starts it on the negative x axis, at −π: the same region came out as the
/// upper half-plane, and r = θ stopped half a turn in.
///
/// A sample a hair below the axis can round up to exactly 2π, so the interval
/// is closed at that end in practice. Both ends name the same direction.
double _azimuth(double x, double y) {
  final double theta = math.atan2(y, x);
  return theta < 0 ? theta + 2 * math.pi : theta;
}
