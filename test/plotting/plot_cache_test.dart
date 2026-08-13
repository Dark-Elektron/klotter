import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';
import 'package:klotter/plotting/utils/plot_cache.dart';

PlotExpression fn(String t) =>
    PlotExpression.compile(<MathNode>[LiteralNode(text: t)]);

/// Geometry depends on the expression, the window and the resolution — never
/// on the camera. Rotating repainted continuously and recomputed all of it.
void main() {
  group('PlotCache', () {
    test('computes once and reuses', () {
      final cache = PlotCache<int>(4);
      var calls = 0;
      int compute() {
        calls++;
        return 42;
      }

      expect(cache.resolve('a', compute), equals(42));
      expect(cache.resolve('a', compute), equals(42));
      expect(cache.resolve('a', compute), equals(42));
      expect(calls, equals(1));
    });

    test('a different key recomputes', () {
      final cache = PlotCache<int>(4);
      var calls = 0;
      cache.resolve('a', () {
        calls++;
        return 1;
      });
      cache.resolve('b', () {
        calls++;
        return 2;
      });
      expect(calls, equals(2));
    });

    test('evicts past capacity but keeps what is in use', () {
      final cache = PlotCache<int>(2);
      cache.resolve('a', () => 1);
      cache.resolve('b', () => 2);
      cache.resolve('a', () => 99); // touch 'a' so 'b' is now oldest
      cache.resolve('c', () => 3); // evicts 'b'
      expect(cache.length, equals(2));

      var recomputed = false;
      cache.resolve('a', () {
        recomputed = true;
        return 0;
      });
      expect(recomputed, isFalse, reason: 'the in-use entry survived');
    });
  });

  group('marching results are cached', () {
    test('the same box returns an identical list', () {
      final f = fn('xx+yy+zz=1');
      final a = marchingTetrahedra(f, -5, 5, -5, 5, -5, 5);
      final b = marchingTetrahedra(f, -5, 5, -5, 5, -5, 5);
      expect(identical(a, b), isTrue, reason: 'recomputed instead of reused');
    });

    test('a changed box recomputes', () {
      final f = fn('xx+yy+zz=1');
      final a = marchingTetrahedra(f, -5, 5, -5, 5, -5, 5);
      final b = marchingTetrahedra(f, -4, 4, -4, 4, -4, 4);
      expect(identical(a, b), isFalse);
    });

    test('a different expression recomputes', () {
      final a = marchingSquares(fn('xx+yy=1'), -3, 3, -3, 3);
      final b = marchingSquares(fn('xx+yy=4'), -3, 3, -3, 3);
      expect(identical(a, b), isFalse);
    });

    test('2D segments are cached across repaints', () {
      final f = fn('xx+yy=1');
      expect(
        identical(
          marchingSquares(f, -3, 3, -3, 3),
          marchingSquares(f, -3, 3, -3, 3),
        ),
        isTrue,
      );
    });
  });

  group('height grids are cached', () {
    test('the same ranges return an identical grid', () {
      final f = fn('xx+yy');
      final a = cachedHeightGrid(f, 5, 5, 20);
      final b = cachedHeightGrid(f, 5, 5, 20);
      expect(identical(a, b), isTrue);
    });

    test('a changed range recomputes', () {
      final f = fn('xx+yy');
      expect(
        identical(cachedHeightGrid(f, 5, 5, 20), cachedHeightGrid(f, 6, 5, 20)),
        isFalse,
      );
    });

    test('undefined samples are kept, not dropped', () {
      // Callers must be able to tell "undefined" from "outside the window".
      final grid = cachedHeightGrid(fn('1/(xx+yy)'), 5, 5, 8);
      expect(grid.length, equals(9));
      expect(grid.expand((r) => r).any((v) => !v.isFinite), isTrue);
    });
  });
}
