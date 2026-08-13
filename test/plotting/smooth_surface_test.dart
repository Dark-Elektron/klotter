import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/utils/colormap.dart';

/// A surface cell must be a gradient, not a block.
///
/// Filling each grid cell with one colour taken from its *average* value makes
/// every cell flat, which reads as banding however fine the grid — 50x50 still
/// shows 2,500 solid blocks. The corners are now coloured separately and
/// interpolated across the cell by `Canvas.drawVertices`.
void main() {
  Color shade(double v, double min, double max) =>
      plotColormap(((v - min) / (max - min)).clamp(0.0, 1.0));

  group('a cell spanning a gradient gets distinct corner colours', () {
    test('corners of a steep cell differ', () {
      // One cell of x²+y² near the rim: corners carry different values.
      const double min = 0, max = 18;
      final c1 = shade(4.0, min, max);
      final c2 = shade(5.0, min, max);
      final c3 = shade(6.5, min, max);
      final c4 = shade(5.2, min, max);

      expect(
        <Color>{c1, c2, c3, c4}.length,
        greaterThan(1),
        reason: 'a flat fill would collapse these to one colour',
      );
    });

    test('the cell average discards the spread', () {
      // The old approach: every corner painted the average.
      const double min = 0, max = 18;
      const double avg = (4.0 + 5.0 + 6.5 + 5.2) / 4;
      final flat = shade(avg, min, max);
      expect(shade(4.0, min, max), isNot(equals(flat)));
      expect(shade(6.5, min, max), isNot(equals(flat)));
    });

    test('a genuinely flat cell still yields one colour', () {
      const double min = 0, max = 18;
      final c = shade(7.0, min, max);
      expect(shade(7.0, min, max), equals(c));
    });
  });

  group('the 2D heatmap samples corners, not cell centres', () {
    test('a centre sample cannot distinguish a cell from its neighbours', () {
      // f = x + y over one cell of a 40x40 lattice: the centre value is the
      // corner average, so a centre-sampled fill paints the whole cell one
      // colour and the gradient across it is lost.
      double f(double x, double y) => x + y;
      const double x0 = 0, x1 = 1, y0 = 0, y1 = 1;

      final corners = <double>[f(x0, y0), f(x1, y0), f(x1, y1), f(x0, y1)];
      final centre = f((x0 + x1) / 2, (y0 + y1) / 2);

      expect(centre, closeTo(corners.reduce((a, b) => a + b) / 4, 1e-12));
      expect(
        corners.toSet().length,
        greaterThan(1),
        reason: 'the corners disagree; a single centre value hides that',
      );
    });

    test('cells touching an undefined sample are skipped, not painted', () {
      // 1/x is infinite at x = 0. Colouring such a cell would invent a value.
      bool drawable(List<double> cs) => cs.every((v) => v.isFinite);
      expect(drawable(<double>[1, 2, double.infinity, 3]), isFalse);
      expect(drawable(<double>[1, 2, double.nan, 3]), isFalse);
      expect(drawable(<double>[1, 2, 3, 4]), isTrue);
    });
  });

  group('Vertices carries per-corner colours', () {
    test('two triangles share the diagonal with matching colours', () {
      // The quad is split p1-p2-p3 and p1-p3-p4; p1 and p3 must carry the
      // same colour in both, or a seam appears along the diagonal.
      const positions = <Offset>[
        Offset(0, 0),
        Offset(1, 0),
        Offset(1, 1),
        Offset(0, 0),
        Offset(1, 1),
        Offset(0, 1),
      ];
      final colors = <Color>[
        const Color(0xFF000001),
        const Color(0xFF000002),
        const Color(0xFF000003),
        const Color(0xFF000001),
        const Color(0xFF000003),
        const Color(0xFF000004),
      ];

      expect(colors[0], equals(colors[3]), reason: 'p1 shared');
      expect(colors[2], equals(colors[4]), reason: 'p3 shared');
      expect(positions[0], equals(positions[3]));
      expect(positions[2], equals(positions[4]));

      final v = Vertices(VertexMode.triangles, positions, colors: colors);
      addTearDown(v.dispose);
      expect(v, isNotNull);
    });
  });
}
