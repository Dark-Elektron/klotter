import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/plotting/models/point_3d.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// A level surface is lit, and the light has to come from the lattice.
///
/// Every point on a marched surface satisfies the same equation, so with one
/// flat colour a fold, a neck and a flat sheet are the same block of colour.
/// Shading is what tells them apart — but only if the normals are smooth. The
/// obvious source, one normal per triangle taken from its own corners, is not:
/// marching tetrahedra makes slivers, and a sliver's cross product is rounding
/// error. The gradient of the sampled lattice costs no extra evaluation of the
/// expression and has no such tail.
void main() {
  PlotExpression compile(String src) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: src)]);

  test('the normal is the surface normal, everywhere on a sphere', () {
    // A sphere's normal is its own radius vector, so every marched normal has
    // a known right answer to be checked against.
    final LevelSurface s = marchedSurface(
      compile('xx+yy+zz=4'),
      -3,
      3,
      -3,
      3,
      -3,
      3,
    );
    expect(s.triangles, isNotEmpty);
    expect(s.normals.length, s.triangles.length * 9);

    final List<double> off = <double>[];
    for (int t = 0; t < s.triangles.length; t++) {
      final LevelTriangle tri = s.triangles[t];
      for (int v = 0; v < 3; v++) {
        final Point3D corner = v == 0 ? tri.a : (v == 1 ? tri.b : tri.c);
        final double px = corner.x;
        final double py = corner.y;
        final double pz = corner.z;
        final double r = sqrt(px * px + py * py + pz * pz);
        if (r == 0) continue;

        final int i = t * 9 + v * 3;
        final double nx = s.normals[i];
        final double ny = s.normals[i + 1];
        final double nz = s.normals[i + 2];
        expect(
          sqrt(nx * nx + ny * ny + nz * nz),
          closeTo(1, 1e-5),
          reason: 'normals are meant to come out of the marcher unit length',
        );
        // Two-sided: the shading uses |n.l|, so a globally flipped normal is
        // the same surface. Only the angle matters.
        final double cosine = ((nx * px + ny * py + nz * pz) / r).abs();
        off.add(acos(cosine.clamp(0.0, 1.0)) * 180 / pi);
      }
    }

    off.sort();
    double q(double p) => off[(p * (off.length - 1)).round()];
    // A sphere is the case the lattice gets exactly right — a central
    // difference is exact on a quadratic — so the measured figures are 0.0
    // median and 0.016 at the worst, and these limits are still a wide margin.
    // They are tight enough to be worth something: a normal per triangle face
    // is 4 to 8 degrees out at the median on this same sphere, and on a
    // quartic it reaches 30 degrees at the 99th percentile and 90 at the
    // worst — a few hundred triangles lit at random.
    expect(q(0.5), lessThan(0.1), reason: 'median ${q(0.5)} degrees off');
    expect(q(0.99), lessThan(0.5), reason: 'p99 ${q(0.99)} degrees off');
    expect(q(1.0), lessThan(1.0), reason: 'worst ${q(1.0)} degrees off');
  });

  test('triangles meeting at a point agree which way the surface faces', () {
    // This is what stops the shading speckling. Two triangles sharing a vertex
    // interpolate the same two lattice gradients to the same place, so they
    // light it the same way and the shading runs smoothly over the join.
    final LevelSurface s = marchedSurface(
      compile('xx+yy+zz=4'),
      -3,
      3,
      -3,
      3,
      -3,
      3,
    );

    final Map<String, List<List<double>>> atPoint =
        <String, List<List<double>>>{};
    for (int t = 0; t < s.triangles.length; t++) {
      final LevelTriangle tri = s.triangles[t];
      for (int v = 0; v < 3; v++) {
        final Point3D corner = v == 0 ? tri.a : (v == 1 ? tri.b : tri.c);
        final String key = <double>[
          corner.x,
          corner.y,
          corner.z,
        ].map((double c) => (c * 1e6).round().toString()).join(',');
        final int i = t * 9 + v * 3;
        (atPoint[key] ??= <List<double>>[]).add(<double>[
          s.normals[i],
          s.normals[i + 1],
          s.normals[i + 2],
        ]);
      }
    }

    int shared = 0;
    double worst = 0;
    for (final List<List<double>> group in atPoint.values) {
      if (group.length < 2) continue;
      shared++;
      for (final List<double> n in group.skip(1)) {
        final List<double> first = group.first;
        final double dot = (first[0] * n[0] + first[1] * n[1] + first[2] * n[2])
            .abs()
            .clamp(0.0, 1.0);
        worst = max(worst, acos(dot) * 180 / pi);
      }
    }

    expect(shared, greaterThan(100), reason: 'no vertices were shared at all');
    // Measured across 9,974 shared vertices: 0.023 degrees at the worst.
    expect(
      worst,
      lessThan(0.1),
      reason: 'triangles disagreed by $worst degrees at a shared vertex',
    );
  });

  testWidgets('the lit surface reads as a solid, not as a flat cut-out', (
    tester,
  ) async {
    await tester.runAsync(() async {
      const int side = 300;
      final AppColors colors = AppColors.fromType(ThemeType.dark);
      final PlotExpression sphere = compile('xx+yy+zz=4');
      final painter = Plot3DPainter(
        function: sphere,
        functions: <PlotExpression>[sphere],
        showMesh: false,
        is3DFunction: false,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 3,
        rangeY: 3,
        rangeZ: 3,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.function,
        fieldType: FieldType.scalar,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: PlotThemeData.fromColors(colors),
      );
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(300, 300));
      final ui.Image image = await recorder.endRecording().toImage(side, side);
      final ByteData data = (await image.toByteData())!;

      // The sphere is the only blue thing on a dark theme's plot, so its own
      // pixels can be picked out without pinning the palette's exact value.
      final List<int> onSphere = <int>[];
      // Below the colorbar, which is a blue-to-red ramp and would otherwise be
      // counted as sphere.
      for (int y = side ~/ 3; y < side; y++) {
        for (int x = 0; x < side; x++) {
          final int p = (y * side + x) * 4;
          final int r = data.getUint8(p);
          final int g = data.getUint8(p + 1);
          final int b = data.getUint8(p + 2);
          if (b > 100 && b > r + 40 && b >= g) onSphere.add(b);
        }
      }

      expect(onSphere.length, greaterThan(2000), reason: 'no sphere was drawn');
      onSphere.sort();
      final int dim = onSphere[(onSphere.length * 0.02).round()];
      final int bright = onSphere[(onSphere.length * 0.98).round()];
      // Unlit, every one of these pixels held the same number and a fold read
      // as nothing at all. The band is bounded below by the ambient floor, so
      // a good spread is expected rather than hoped for.
      expect(
        bright - dim,
        greaterThan(40),
        reason: 'the surface spans only $dim..$bright: it is barely lit',
      );
      // Smoothness is not asserted here on purpose. Neighbouring pixels do
      // step by 13 to 29 levels across about 3% of the surface, clustered
      // along the lower silhouette, but that is the tessellation and the depth
      // sort showing through rather than anything about the light: the same
      // measurement comes out at 3.5% with a normal per triangle face and 3.3%
      // with these, and at 0.3% with the shading switched off entirely, which
      // is flat colour hiding it rather than not having it. What the normals
      // have to be is checked directly in the two tests above.
    });
  });
}
