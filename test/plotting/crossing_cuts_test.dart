import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/utils/crossing_cuts.dart';

/// Surfaces cut where they cross, so a painter's sort can place every piece.
///
/// Sorted whole by the depth of their centres, triangles that straddle a
/// crossing came out half wrong, once per cell along it: teeth where a rose's
/// wall went through a spiral's and both met a saddle.
void main() {
  const int red = 0xFFFF0000, blue = 0xFF0000FF;

  SurfaceTriangles surface(List<List<double>> triangles, int colour) => (
    world: Float32List.fromList(<double>[for (final t in triangles) ...t]),
    colors: Int32List.fromList(<int>[
      for (int i = 0; i < triangles.length * 3; i++) colour,
    ]),
    count: triangles.length,
    sides: null,
  );

  // A vertical triangle in the plane x = 0, and a flat one at z = 0.
  final List<double> wall = <double>[0, -1, -1, 0, 1, -1, 0, 0, 1];
  final List<double> floor = <double>[-1, -1, 0, 1, -1, 0, 0, 1, 0];

  double area(Float32List w, int t) {
    final int i = t * 9;
    final double ux = w[i + 3] - w[i], uy = w[i + 4] - w[i + 1];
    final double uz = w[i + 5] - w[i + 2];
    final double vx = w[i + 6] - w[i], vy = w[i + 7] - w[i + 1];
    final double vz = w[i + 8] - w[i + 2];
    final double cx = uy * vz - uz * vy;
    final double cy = uz * vx - ux * vz;
    final double cz = ux * vy - uy * vx;
    return math.sqrt(cx * cx + cy * cy + cz * cz) / 2;
  }

  double totalArea(SurfaceTriangles s) {
    double sum = 0;
    for (int t = 0; t < s.count; t++) {
      sum += area(s.world, t);
    }
    return sum;
  }

  test('two crossing triangles are each cut where they cross', () {
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      surface(<List<double>>[wall], red),
      surface(<List<double>>[floor], blue),
    ]);
    expect(cut[0].count, greaterThan(1));
    expect(cut[1].count, greaterThan(1));
    // Nothing lost or gained.
    expect(totalArea(cut[0]), closeTo(2, 1e-5));
    expect(totalArea(cut[1]), closeTo(2, 1e-5));
  });

  test('every piece lies to one side of the surface it crossed', () {
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      surface(<List<double>>[wall], red),
      surface(<List<double>>[floor], blue),
    ]);
    // The wall's pieces are wholly above or below z = 0...
    for (int t = 0; t < cut[0].count; t++) {
      final List<double> z = <double>[
        cut[0].world[t * 9 + 2],
        cut[0].world[t * 9 + 5],
        cut[0].world[t * 9 + 8],
      ];
      final bool above = z.every((double v) => v >= -1e-6);
      final bool below = z.every((double v) => v <= 1e-6);
      expect(above || below, isTrue, reason: 'piece $t straddles: $z');
    }
    // ...and the floor's wholly to one side of x = 0.
    for (int t = 0; t < cut[1].count; t++) {
      final List<double> x = <double>[
        cut[1].world[t * 9],
        cut[1].world[t * 9 + 3],
        cut[1].world[t * 9 + 6],
      ];
      final bool right = x.every((double v) => v >= -1e-6);
      final bool left = x.every((double v) => v <= 1e-6);
      expect(right || left, isTrue, reason: 'piece $t straddles: $x');
    }
  });

  test('a new corner takes the colour its edge has there', () {
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      (
        world: Float32List.fromList(wall),
        // Red at the bottom, blue at the top: halfway up is half of each.
        colors: Int32List.fromList(<int>[red, red, blue]),
        count: 1,
        sides: null,
      ),
      surface(<List<double>>[floor], blue),
    ]);
    // Read unsigned: an Int32List hands back a colour with alpha as negative.
    final Set<int> colours = <int>{
      for (final int c in cut[0].colors) c & 0xFFFFFFFF,
    };
    // The cut is at z = 0, halfway from the bottom (z = -1) to the top.
    expect(colours, contains(0xFF800080));
  });

  test('surfaces that do not cross come back as they were', () {
    final SurfaceTriangles a = surface(<List<double>>[floor], red);
    final SurfaceTriangles b = surface(<List<double>>[
      <double>[-1, -1, 5, 1, -1, 5, 0, 1, 5],
    ], blue);
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[a, b]);
    expect(identical(cut[0].world, a.world), isTrue);
    expect(identical(cut[1].world, b.world), isTrue);
  });

  test('a surface on its own is never cut', () {
    // Two triangles of one surface crossing each other are its own business.
    final SurfaceTriangles one = surface(<List<double>>[wall, floor], red);
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[one]);
    expect(identical(cut.single.world, one.world), isTrue);
  });

  test('touching is not crossing', () {
    // The wall stands on the floor's edge, meeting it along a line.
    final List<double> standing = <double>[-1, -1, 0, 1, -1, 0, 0, -1, 1];
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      surface(<List<double>>[standing], red),
      surface(<List<double>>[floor], blue),
    ]);
    expect(cut[0].count, 1);
    expect(cut[1].count, 1);
  });

  test('two surfaces in one plane are left alone', () {
    final List<double> overlapping = <double>[
      -0.5,
      -1,
      0,
      1.5,
      -1,
      0,
      0.5,
      1,
      0,
    ];
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      surface(<List<double>>[overlapping], red),
      surface(<List<double>>[floor], blue),
    ]);
    expect(cut[0].count, 1);
    expect(cut[1].count, 1);
  });

  test('planes that cross outside the triangles cut nothing', () {
    // The wall's plane passes through the floor's, but the wall is off to
    // the side, past the floor's far corner.
    final List<double> aside = <double>[0, 3, -1, 0, 5, -1, 0, 4, 1];
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      surface(<List<double>>[aside], red),
      surface(<List<double>>[floor], blue),
    ]);
    expect(cut[0].count, 1);
    expect(cut[1].count, 1);
  });

  test('a fine sheet through a fine sheet is cut only along the crossing', () {
    // Two meshed planes, z = 0 and z = 0.3x, crossing along x = 0.
    List<List<double>> grid(double Function(double x, double y) z) {
      const int cells = 20;
      final List<List<double>> out = <List<double>>[];
      for (int i = 0; i < cells; i++) {
        for (int j = 0; j < cells; j++) {
          final double x0 = -1 + 2 * i / cells, x1 = -1 + 2 * (i + 1) / cells;
          final double y0 = -1 + 2 * j / cells, y1 = -1 + 2 * (j + 1) / cells;
          out
            ..add(<double>[
              x0,
              y0,
              z(x0, y0),
              x1,
              y0,
              z(x1, y0),
              x1,
              y1,
              z(x1, y1),
            ])
            ..add(<double>[
              x0,
              y0,
              z(x0, y0),
              x1,
              y1,
              z(x1, y1),
              x0,
              y1,
              z(x0, y1),
            ]);
        }
      }
      return out;
    }

    final SurfaceTriangles flat = surface(grid((x, y) => 0), red);
    final SurfaceTriangles tilted = surface(grid((x, y) => 0.3 * x), blue);
    final List<SurfaceTriangles> cut = cutAtCrossings(<SurfaceTriangles>[
      flat,
      tilted,
    ]);
    // The crossing runs along a grid line, so only the cells beside it are
    // touched, and only by a few pieces each.
    expect(cut[0].count, lessThan(flat.count + 100));
    expect(cut[1].count, lessThan(tilted.count + 100));
    expect(totalArea(cut[0]), closeTo(totalArea(flat), 1e-3));
    expect(totalArea(cut[1]), closeTo(totalArea(tilted), 1e-3));
  });
}
