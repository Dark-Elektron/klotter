import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/utils/coordinate_system.dart';

/// The coordinate systems the variable and unit-vector keys offer.
///
/// The three keys in a group always show one system. A row reading x, θ, z
/// would be meaningless, because each symbol only means anything relative to
/// the system it belongs to.
void main() {
  group('symbols follow ISO 80000-2', () {
    test('cylindrical and spherical do not share a radial symbol', () {
      // r is the distance from the z axis, ρ the distance from the origin.
      // They are different quantities; one letter for both invites a wrong
      // formula that looks right.
      expect(CoordinateSystem.cylindrical.variables, <String>['r', 'θ', 'z']);
      expect(CoordinateSystem.spherical.variables, <String>['ρ', 'θ', 'φ']);
      expect(
        CoordinateSystem.cylindrical.variables.first,
        isNot(CoordinateSystem.spherical.variables.first),
      );
    });

    test('cartesian is unchanged', () {
      expect(CoordinateSystem.cartesian.variables, <String>['x', 'y', 'z']);
    });

    test('every system offers exactly three axes', () {
      for (final s in CoordinateSystem.values) {
        expect(s.variables, hasLength(3), reason: '$s');
        expect(s.unitVectorAxes, hasLength(3), reason: '$s');
        expect(s.unitVectorLabels, hasLength(3), reason: '$s');
      }
    });
  });

  group('unit vectors', () {
    test('carry a hat over the same symbol as the variable', () {
      for (final s in CoordinateSystem.values) {
        for (int i = 0; i < 3; i++) {
          expect(
            s.unitVectorLabels[i],
            startsWith(s.variables[i]),
            reason: '${s.label} axis $i',
          );
          expect(
            s.unitVectorLabels[i].length,
            s.variables[i].length + 1,
            reason: 'exactly one combining mark',
          );
        }
      }
    });

    test('what a key inserts is the bare symbol, not the hatted one', () {
      expect(CoordinateSystem.spherical.unitVectorAxes, <String>[
        'ρ',
        'θ',
        'φ',
      ]);
    });
  });

  group('the coordinate transform', () {
    test('cartesian passes through untouched', () {
      expect(toCoordinates(CoordinateSystem.cartesian, 1, 2, 3), (
        1.0,
        2.0,
        3.0,
      ));
    });

    test('cylindrical r ignores z', () {
      final (r, _, z) = toCoordinates(CoordinateSystem.cylindrical, 3, 4, 7);
      expect(r, closeTo(5, 1e-9));
      expect(z, 7);
    });

    test('spherical ρ is the distance from the origin', () {
      final (rho, _, _) = toCoordinates(CoordinateSystem.spherical, 1, 2, 2);
      expect(rho, closeTo(3, 1e-9));
    });

    test('the origin does not produce NaN', () {
      // ϕ is undefined there; a NaN would spread through a whole surface.
      final (rho, theta, phi) = toCoordinates(
        CoordinateSystem.spherical,
        0,
        0,
        0,
      );
      expect(rho, 0);
      expect(theta.isFinite, isTrue);
      expect(phi.isFinite, isTrue);
    });
  });
}
