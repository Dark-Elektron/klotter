import 'dart:math' as math;

/// The coordinate systems an expression can be written in.
///
/// Symbols follow ISO 80000-2, which keeps the systems apart on purpose:
/// cylindrical uses `r` for the distance from the axis while spherical uses
/// `ρ` for the distance from the origin. They are different quantities, and
/// giving them the same letter is a reliable way to write a wrong formula.
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
  /// φ is the ISO spelling of the spherical angle. The engine used to read it
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
/// (x, y, z) the value of ρ is known, and `r = 1 + cos(θ)` traces a cardioid
/// through the same marching-squares code that draws any other implicit curve.
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
      return (math.sqrt(x * x + y * y), math.atan2(y, x), z);
    case CoordinateSystem.spherical:
      final double rho = math.sqrt(x * x + y * y + z * z);
      // θ from the x axis in the xy-plane, ϕ down from the z axis. At the
      // origin ϕ is undefined; zero is as good as anything and keeps the
      // sample finite rather than seeding NaN through a whole surface.
      final double phi = rho == 0 ? 0.0 : math.acos((z / rho).clamp(-1.0, 1.0));
      return (rho, math.atan2(y, x), phi);
  }
}
