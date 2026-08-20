import 'dart:math';
import 'dart:ui';
import 'package:klotter/utils/app_colors.dart';
import 'package:klotter/settings/settings_provider.dart';
import 'package:klotter/plotting/utils/plot_theme.dart';
import 'package:klotter/plotting/painters/plot_3d_painter.dart';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/models/complex_view.dart';
import 'package:klotter/plotting/models/enums.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/parsers/vector_field_parser.dart';
import 'package:klotter/plotting/utils/parametric.dart';
import 'package:klotter/plotting/utils/surface_pick.dart';

/// Reading a value off the two kinds of plot that had no readout.
///
/// A height surface is picked by marching a ray until `z - f(x, y)` changes
/// sign. Neither of these is a height, so each needed its own answer:
///
///  * A vector field's magnitude surface *is* a height — `z = |F(x, y)|` — so
///    it joins the same march rather than getting a picker of its own.
///  * A sweep is not. It is picked from the samples already computed to draw
///    it, so the marker can only land somewhere the curve was actually drawn.
void main() {
  const Size canvas = Size(400, 400);

  PlotCamera camera({double range = 5}) => PlotCamera(
    size: canvas,
    rotationX: 0.6,
    rotationZ: 0.8,
    panX: 0,
    panY: 0,
    rangeX: range,
    rangeY: range,
    rangeZ: range,
  );

  VectorFieldParser parse(List<MathNode> nodes) {
    final VectorFieldParser? f = VectorFieldParser.fromNodes(nodes);
    expect(f, isNotNull, reason: 'not read as a vector line');
    expect(f!.error, isNull, reason: f.error);
    return f;
  }

  group('a vector field magnitude surface', () {
    /// `y x̂ − x ŷ`, whose magnitude is the radius — a cone, so every touch
    /// has one unambiguous height under it.
    VectorFieldParser field() => parse(<MathNode>[
      LiteralNode(text: 'y'),
      UnitVectorNode('x'),
      LiteralNode(text: '-x'),
      UnitVectorNode('y'),
    ]);

    test('it is a field, not a sweep', () {
      // Otherwise this exercises the parametric path and proves nothing about
      // the march.
      expect(field().isParametric, isFalse);
      expect(field().is3D, isFalse);
    });

    test('a touch on the surface lands on it', () {
      final PlotCamera c = camera();
      final VectorFieldParser f = field();
      // Aim at a point known to be on the cone, then touch where it projects.
      const double x = 2.0, y = 1.0;
      final Offset touch = c.project(x, y, f.magnitude(x, y));

      final SurfaceHit? hit = pickSurface(
        c,
        const <PlotExpression>[],
        touch,
        field: f,
        surfaceMode: SurfaceMode.magnitude,
      );

      expect(hit, isNotNull, reason: 'nothing was found under the touch');
      expect(hit!.curveIndex, vectorCurveIndex);

      // On the surface, and under the finger. Not "at the point aimed at":
      // this field's magnitude is a cone, and a ray can cross a cone twice, so
      // the march is entitled to return the nearer crossing. What it may never
      // do is return a point that is not on the surface, or one that is not
      // where the user touched.
      expect(
        f.magnitude(hit.x, hit.y),
        closeTo(hit.z, 0.35),
        reason: 'the point is not on the surface it claims to be on',
      );
      expect(
        (c.project(hit.x, hit.y, hit.z) - touch).distance,
        lessThan(6),
        reason: 'the marker landed away from the touch',
      );
    });

    test('with no surface mode there is nothing to touch', () {
      // The mode is off, so no magnitude surface is drawn — picking one would
      // put a marker on something invisible.
      final PlotCamera c = camera();
      final VectorFieldParser f = field();
      //
      // Aimed at the floor rather than at the cone. With the guard removed,
      // `componentValue(none, ...)` returns 0 everywhere, so the field reads
      // as a flat sheet at z = 0 and a touch there finds it. A touch aimed at
      // the cone happens to miss that sheet, so it could not tell the two
      // apart and passed the mutation.
      final Offset onFloor = c.project(1, 1, 0);
      expect(
        pickSurface(c, const <PlotExpression>[], onFloor, field: f),
        isNull,
        reason: 'a surface was picked with no surface mode showing',
      );
      // The positive control: the same field does yield a hit once a mode is
      // chosen, so the null above is the guard and not a dead pick.
      expect(
        pickSurface(
          c,
          const <PlotExpression>[],
          c.project(2, 1, f.magnitude(2, 1)),
          field: f,
          surfaceMode: SurfaceMode.magnitude,
        ),
        isNotNull,
      );
    });
  });

  group('a parametric sweep', () {
    /// A helix: `cos(u) x̂ + sin(u) ŷ + u ẑ`.
    VectorFieldParser helix() => parse(<MathNode>[
      TrigNode(function: 'cos', argument: <MathNode>[LiteralNode(text: 'u')]),
      UnitVectorNode('x'),
      LiteralNode(text: '+'),
      TrigNode(function: 'sin', argument: <MathNode>[LiteralNode(text: 'u')]),
      UnitVectorNode('y'),
      LiteralNode(text: '+u'),
      UnitVectorNode('z'),
    ]);

    const ParameterRange u = (min: 0.0, max: 4.0);

    test('it is a sweep, and a curve rather than a surface', () {
      expect(helix().isParametric, isTrue);
      expect(helix().isParametricSurface, isFalse);
    });

    test('a touch on the curve reports the point and its parameter', () {
      final PlotCamera c = camera();
      final VectorFieldParser f = helix();
      // A point a known way along the sweep.
      const double atU = 2.5;
      final Offset touch = c.project(
        // cos and sin of 2.5, and z = u.
        -0.8011436155469337,
        0.5984721441039564,
        atU,
      );

      final SurfaceHit? hit = pickParametric(
        c,
        f,
        touch,
        uRange: u,
        vRange: defaultParameterRange,
      );

      expect(hit, isNotNull, reason: 'nothing was found on the sweep');
      expect(hit!.u, isNotNull, reason: 'a sweep hit must name its parameter');
      expect(hit.u!, closeTo(atU, 0.15));
      expect(hit.v, isNull, reason: 'a curve has no second parameter');
      expect(hit.z, closeTo(atU, 0.15), reason: 'z is u on this helix');
    });

    test(
      'the marker follows the curve rather than jumping between samples',
      () {
        // Snapping to the nearest sample left the marker up to half a step from
        // the finger, and it hopped as the finger moved. Refined onto the
        // segment, the distance from the touch should be a fraction of a pixel
        // wherever along the curve it is taken — and crucially, should not vary
        // in the sawtooth way that snapping produces.
        final PlotCamera c = camera();
        final VectorFieldParser f = helix();

        double worst = 0;
        for (int i = 0; i <= 40; i++) {
          final double atU = u.min + (u.max - u.min) * i / 40;
          final Offset touch = c.project(cos(atU), sin(atU), atU);
          final SurfaceHit? hit = pickParametric(
            c,
            f,
            touch,
            uRange: u,
            vRange: defaultParameterRange,
          );
          if (hit == null) continue;
          final double d = (c.project(hit.x, hit.y, hit.z) - touch).distance;
          if (d > worst) worst = d;
        }

        expect(
          worst,
          lessThan(2.5),
          reason:
              'the marker sat up to ${worst.toStringAsFixed(1)}px from the '
              'touch — it is snapping to samples rather than following the '
              'curve between them',
        );
      },
    );

    test('a touch far from the curve finds nothing', () {
      // Empty space is empty. Without the tolerance the marker would snap to
      // whichever sample happened to be least far away, anywhere on screen.
      final PlotCamera c = camera();
      expect(
        pickParametric(
          c,
          helix(),
          const Offset(4, 4),
          uRange: u,
          vRange: defaultParameterRange,
        ),
        isNull,
      );
    });

    test('a swept surface reports both parameters', () {
      final PlotCamera c = camera();
      final VectorFieldParser patch = parse(<MathNode>[
        LiteralNode(text: 'u'),
        UnitVectorNode('x'),
        LiteralNode(text: '+v'),
        UnitVectorNode('y'),
        LiteralNode(text: '+u*v'),
        UnitVectorNode('z'),
      ]);
      expect(patch.isParametricSurface, isTrue);

      const ParameterRange r = (min: -2.0, max: 2.0);
      final Offset touch = c.project(1, -1, -1);
      final SurfaceHit? hit = pickParametric(
        c,
        patch,
        touch,
        uRange: r,
        vRange: r,
      );

      expect(hit, isNotNull);
      expect(hit!.u, isNotNull);
      expect(hit.v, isNotNull, reason: 'a swept surface has two parameters');
      // On this patch x is u and y is v, so the parameters and the point agree.
      expect(hit.u!, closeTo(hit.x, 0.3));
      expect(hit.v!, closeTo(hit.y, 0.3));
    });
  });

  group('a complex surface', () {
    /// `(x+yi)^2`. Its real part is x²−y², its imaginary part 2xy and its
    /// modulus x²+y² — three different surfaces on the same axes, which is
    /// what makes this worth testing separately: a pick must land on the one
    /// that is showing.
    PlotExpression f() =>
        PlotExpression.compile(<MathNode>[LiteralNode(text: '(x+yi)^2')]);

    double partAt(ComplexPart part, double x, double y) {
      final w = f().evaluateComplex(x, y);
      return switch (part) {
        ComplexPart.real => w.real,
        ComplexPart.imaginary => w.imag,
        ComplexPart.modulus => w.magnitude,
      };
    }

    test('the expression under test is complex', () {
      // The trap this suite has hit before: an expression that does not
      // compile draws nothing, and then every mode agrees.
      final PlotExpression e = f();
      expect(e.isValid, isTrue, reason: e.error);
      expect(e.isComplex, isTrue);
    });

    test('only the components on show are pickable', () {
      expect(
        complexPartsOf(const ComplexView(real: true, modulus: false)),
        <ComplexPart>[ComplexPart.real],
      );
      expect(
        complexPartsOf(
          const ComplexView(real: true, imaginary: true, modulus: true),
        ),
        <ComplexPart>[
          ComplexPart.real,
          ComplexPart.imaginary,
          ComplexPart.modulus,
        ],
      );
    });

    for (final ComplexPart part in ComplexPart.values) {
      test('a touch on the ${part.name} surface lands on it', () {
        final PlotCamera c = camera(range: 3);
        const double x = 1.2, y = 0.7;
        final double h = partAt(part, x, y);
        final Offset touch = c.project(x, y, h);

        final SurfaceHit? hit = pickSurface(
          c,
          <PlotExpression>[f()],
          touch,
          complexView: ComplexView(
            real: part == ComplexPart.real,
            imaginary: part == ComplexPart.imaginary,
            modulus: part == ComplexPart.modulus,
          ),
        );

        expect(hit, isNotNull, reason: 'nothing found on the ${part.name}');
        // On the surface, and under the finger. Not necessarily at the point
        // aimed at: these surfaces are saddles and bowls, so one ray can cross
        // twice and the nearer crossing is the right answer.
        expect(
          partAt(part, hit!.x, hit.y),
          closeTo(hit.z, 0.3),
          reason: 'the point is not on the ${part.name} surface',
        );
        expect(
          (c.project(hit.x, hit.y, hit.z) - touch).distance,
          lessThan(8),
          reason: 'the marker landed away from the touch',
        );
      });
    }

    test('a component that is switched off cannot be touched', () {
      // The imaginary part of (x+yi)^2 is 2xy, which is negative where the
      // modulus and the real part are not, so a touch below the floor there
      // can only be on the imaginary surface.
      final PlotCamera c = camera(range: 3);
      const double x = 1.4, y = -1.1;
      final double h = partAt(ComplexPart.imaginary, x, y);
      expect(h, lessThan(0), reason: 'the fixture must be below the floor');
      final Offset touch = c.project(x, y, h);

      expect(
        pickSurface(
          c,
          <PlotExpression>[f()],
          touch,
          complexView: const ComplexView(imaginary: false, modulus: true),
        ),
        isNull,
        reason: 'the imaginary surface was picked while it was switched off',
      );
      expect(
        pickSurface(
          c,
          <PlotExpression>[f()],
          touch,
          complexView: const ComplexView(imaginary: true, modulus: false),
        ),
        isNotNull,
        reason: 'the same touch finds it once it is switched on',
      );
    });
  });

  group('the shaded dot field', () {
    // The last vector renderer that still drew one field. `PlotMode.field`
    // routes here rather than to the arrows, which is the distinction an
    // earlier test in this suite got wrong.
    VectorFieldParser field(String fx, String fy) => parse(<MathNode>[
      LiteralNode(text: fx),
      UnitVectorNode('x'),
      LiteralNode(text: '+$fy'),
      UnitVectorNode('y'),
    ]);

    Future<int> ink(int count) async {
      final colors = AppColors.fromType(ThemeType.dark);
      final fields = <VectorFieldParser>[
        field('y', '-x'),
        if (count > 1) field('x', 'y'),
      ];
      final painter = Plot3DPainter(
        function: PlotExpression.invalid,
        vectorParser: fields.first,
        vectorFields: fields,
        is3DFunction: false,
        rotationX: 0.6,
        rotationZ: 0.8,
        rangeX: 2,
        rangeY: 2,
        rangeZ: 2,
        panX: 0,
        panY: 0,
        plotMode: PlotMode.field,
        fieldType: FieldType.vector,
        showContour: false,
        surfaceMode: SurfaceMode.none,
        colors: colors,
        plotTheme: PlotThemeData.fromColors(colors),
      );
      final rec = ui.PictureRecorder();
      painter.paint(Canvas(rec), const Size(320, 320));
      final img = await rec.endRecording().toImage(320, 320);
      final d = (await img.toByteData())!;
      int n = 0;
      for (int i = 0; i < 320 * 320; i++) {
        final o = i * 4;
        if (d.getUint8(o + 3) < 200) continue;
        final r = d.getUint8(o), g = d.getUint8(o + 1), b = d.getUint8(o + 2);
        final mx = [r, g, b].reduce((a, c) => a > c ? a : c);
        final mn = [r, g, b].reduce((a, c) => a < c ? a : c);
        if (mx > 60 && mx - mn > 30) n++;
      }
      return n;
    }

    testWidgets('a second field is drawn too', (tester) async {
      await tester.runAsync(() async {
        final one = await ink(1);
        final two = await ink(2);
        expect(one, greaterThan(0), reason: 'one field drew nothing');
        expect(
          two,
          greaterThan(one),
          reason: 'the second field added nothing — it was not drawn',
        );
      });
    });
  });
}
