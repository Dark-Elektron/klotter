import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';

/// Vector fields written in a rotating basis.
///
/// `r r̂` used to report "unknown variable e_r": the engine only names e_x,
/// e_y and e_z, so a polar unit vector fell through to a free variable and the
/// internal name leaked into the error. r̂ and θ̂ point somewhere different at
/// every sample, so the field is converted to Cartesian components, which is
/// what everything downstream already draws.
void main() {
  allThreeCoordinates();
  VectorFieldParser? parse(List<MathNode> nodes) =>
      VectorFieldParser.fromNodes(nodes);

  group('cylindrical', () {
    test('r r̂ is the position field (x, y)', () {
      final f = parse(<MathNode>[LiteralNode(text: 'r'), UnitVectorNode('r')]);
      expect(f, isNotNull);
      expect(f!.error, isNull, reason: f.error);

      // At (3, 4): r = 5, r̂ = (0.6, 0.8), so the field is (3, 4).
      expect(f.xComponent!.evaluate(3, 4), closeTo(3, 1e-9));
      expect(f.yComponent!.evaluate(3, 4), closeTo(4, 1e-9));
    });

    test('θ̂ alone circulates about the origin', () {
      final f = parse(<MathNode>[UnitVectorNode('θ')]);
      expect(f, isNotNull);
      expect(f!.error, isNull, reason: f.error);

      // θ̂ = (−sin θ, cos θ). On the +x axis that is (0, 1).
      expect(f.xComponent!.evaluate(1, 0), closeTo(0, 1e-9));
      expect(f.yComponent!.evaluate(1, 0), closeTo(1, 1e-9));
      // On the +y axis it is (−1, 0).
      expect(f.xComponent!.evaluate(0, 1), closeTo(-1, 1e-9));
      expect(f.yComponent!.evaluate(0, 1), closeTo(0, 1e-9));
    });

    test('the unit vectors stay unit length', () {
      final f = parse(<MathNode>[UnitVectorNode('r')])!;
      for (final p in <List<double>>[
        <double>[1, 0],
        <double>[3, 4],
        <double>[-2, 5],
      ]) {
        final double x = f.xComponent!.evaluate(p[0], p[1]);
        final double y = f.yComponent!.evaluate(p[0], p[1]);
        expect((x * x + y * y), closeTo(1, 1e-9), reason: 'at $p');
      }
    });

    test('r̂ and θ̂ are perpendicular everywhere', () {
      final r = parse(<MathNode>[UnitVectorNode('r')])!;
      final t = parse(<MathNode>[UnitVectorNode('θ')])!;
      for (final p in <List<double>>[
        <double>[1, 0],
        <double>[3, 4],
        <double>[-2, 5],
      ]) {
        final double dot =
            r.xComponent!.evaluate(p[0], p[1]) *
                t.xComponent!.evaluate(p[0], p[1]) +
            r.yComponent!.evaluate(p[0], p[1]) *
                t.yComponent!.evaluate(p[0], p[1]);
        expect(dot, closeTo(0, 1e-9), reason: 'at $p');
      }
    });

    test('a z term still rides along untouched', () {
      final f = parse(<MathNode>[
        UnitVectorNode('r'),
        LiteralNode(text: '+2'),
        UnitVectorNode('z'),
      ]);
      expect(f!.error, isNull, reason: f.error);
      expect(f.zComponent!.evaluate(1, 1), closeTo(2, 1e-9));
    });
  });

  test('cartesian fields are untouched by any of this', () {
    final f = parse(<MathNode>[LiteralNode(text: '2'), UnitVectorNode('x')])!;
    expect(f.error, isNull, reason: f.error);
    expect(f.xComponent!.evaluate(5, 7), closeTo(2, 1e-9));
  });
}

/// A field whose components involve every coordinate.
void allThreeCoordinates() {
  test('rθθ̂ + zr̂ is a field, not a rejected height', () {
    // The components come out as functions of r, θ and z together. That is
    // fine for a vector field — all three describe *where* you are — but the
    // rule about z being the answer rather than an input was being applied to
    // them, so this reported "Cannot plot z with r or θ" no matter what.
    final f = VectorFieldParser.fromNodes(<MathNode>[
      LiteralNode(text: 'r'),
      LiteralNode(text: 'θ'),
      UnitVectorNode('θ'),
      LiteralNode(text: '+z'),
      UnitVectorNode('r'),
    ]);

    expect(f, isNotNull);
    expect(f!.error, isNull, reason: f.error);
    expect(f.xComponent, isNotNull);
    expect(f.yComponent, isNotNull);

    // At (1, 0, 2): r = 1, θ = 0, so the field is rθ·θ̂ + z·r̂
    //             = 0·(0,1) + 2·(1,0) = (2, 0).
    expect(f.xComponent!.evaluate(1, 0, 2), closeTo(2, 1e-9));
    expect(f.yComponent!.evaluate(1, 0, 2), closeTo(0, 1e-9));
  });

  test('a scalar height still may not mix z with r or θ', () {
    // The rule is still right where it belongs: without an =, z is the answer.
    final e = PlotExpression.compile(<MathNode>[LiteralNode(text: 'r+z')]);
    expect(e.isValid, isFalse);
    expect(e.error, contains('='));
  });
}
