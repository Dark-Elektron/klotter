import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';

/// Vector fields used to split the serialized *string* and evaluate each
/// component with the old MathParser, which returned 0 for anything it did not
/// recognise. They now split from the node tree and compile through the engine.
void main() {
  List<MathNode> lit(String t) => <MathNode>[LiteralNode(text: t)];

  group('detection', () {
    test('a plain expression is not a vector field', () {
      expect(VectorFieldParser.fromNodes(lit('2x')), isNull);
      expect(VectorFieldParser.isVectorFieldNodes(lit('2x')), isFalse);
    });

    test('a unit vector anywhere makes it a field', () {
      final nodes = <MathNode>[LiteralNode(text: 'x'), UnitVectorNode('x')];
      expect(VectorFieldParser.isVectorFieldNodes(nodes), isTrue);
      expect(VectorFieldParser.fromNodes(nodes), isNotNull);
    });
  });

  group('component splitting', () {
    test('splits x̂ and ŷ terms and evaluates each', () {
      // y·x̂ + x·ŷ  — the classic rotational field.
      final nodes = <MathNode>[
        LiteralNode(text: 'y'),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        LiteralNode(text: 'x'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.error, isNull);
      expect(field.is3D, isFalse);

      final (fx, fy, fz) = field.evaluate(2, 3);
      expect(fx, closeTo(3, 1e-9)); // y
      expect(fy, closeTo(2, 1e-9)); // x
      expect(fz, closeTo(0, 1e-9));
    });

    test('a bare unit vector means a coefficient of one', () {
      final nodes = <MathNode>[
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '2'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      final (fx, fy, _) = field.evaluate(5, 7);
      expect(fx, closeTo(1, 1e-9));
      expect(fy, closeTo(2, 1e-9));
    });

    test('a negative term is negated, not dropped', () {
      // -x·x̂ + ŷ
      final nodes = <MathNode>[
        LiteralNode(text: '-x'),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      final (fx, fy, _) = field.evaluate(4, 0);
      expect(fx, closeTo(-4, 1e-9));
      expect(fy, closeTo(1, 1e-9));
    });

    test('subtraction between terms negates the following one', () {
      // 2x̂ - 3ŷ
      final nodes = <MathNode>[
        LiteralNode(text: '2'),
        UnitVectorNode('x'),
        LiteralNode(text: '-3'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      final (fx, fy, _) = field.evaluate(0, 0);
      expect(fx, closeTo(2, 1e-9));
      expect(fy, closeTo(-3, 1e-9));
    });

    test('a ẑ term makes the field 3D', () {
      final nodes = <MathNode>[
        LiteralNode(text: 'x'),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        LiteralNode(text: 'y'),
        UnitVectorNode('y'),
        LiteralNode(text: '+'),
        LiteralNode(text: 'z'),
        UnitVectorNode('z'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.is3D, isTrue);
      final (fx, fy, fz) = field.evaluate(1, 2, 3);
      expect(fx, closeTo(1, 1e-9));
      expect(fy, closeTo(2, 1e-9));
      expect(fz, closeTo(3, 1e-9));
    });
  });

  group('derived quantities', () {
    test('magnitude and componentValue agree with evaluate', () {
      final nodes = <MathNode>[
        LiteralNode(text: '3'),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '4'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.magnitude(0, 0), closeTo(5, 1e-9));
      expect(field.componentValue(SurfaceMode.x, 0, 0), closeTo(3, 1e-9));
      expect(field.componentValue(SurfaceMode.y, 0, 0), closeTo(4, 1e-9));
      expect(
        field.componentValue(SurfaceMode.magnitude, 0, 0),
        closeTo(5, 1e-9),
      );
      expect(field.componentValue(SurfaceMode.none, 0, 0), equals(0));
    });

    test('normalized returns a unit vector, and zero at a null point', () {
      final nodes = <MathNode>[
        LiteralNode(text: '3'),
        UnitVectorNode('x'),
        LiteralNode(text: '+'),
        LiteralNode(text: '4'),
        UnitVectorNode('y'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      final (nx, ny, _) = field.normalized(0, 0);
      expect(nx, closeTo(0.6, 1e-9));
      expect(ny, closeTo(0.8, 1e-9));

      final zero =
          VectorFieldParser.fromNodes(<MathNode>[
            LiteralNode(text: '0'),
            UnitVectorNode('x'),
          ])!;
      expect(zero.normalized(0, 0), equals((0.0, 0.0, 0.0)));
    });
  });

  group('errors are reported, never plotted as zero', () {
    test('an unknown variable in a component is surfaced', () {
      final nodes = <MathNode>[LiteralNode(text: 'q'), UnitVectorNode('x')];
      final field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.error, isNotNull);
      expect(field.error, contains('unknown variable'));
    });

    test('an unresolved integral in a component is surfaced', () {
      // The old string parser drew a confident field of zeros here.
      final nodes = <MathNode>[
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x')],
          isDefinite: false,
        ),
        UnitVectorNode('x'),
      ];
      final field = VectorFieldParser.fromNodes(nodes)!;
      expect(field.error, isNotNull);
    });

    test('a valid field reports no error', () {
      final nodes = <MathNode>[LiteralNode(text: 'y'), UnitVectorNode('x')];
      expect(VectorFieldParser.fromNodes(nodes)!.error, isNull);
    });
  });
}
