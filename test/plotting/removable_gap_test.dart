import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/plotting/parsers/plot_expression.dart';
import 'package:klotter/plotting/utils/level_set.dart';

/// A line that is 0/0 at a single point but carries on either side of it —
/// sin(x)/x at x = 0 — is drawn through that point.
///
/// The point is isolated, but a lattice lands on it exactly whenever the
/// window is symmetric, and it came out undefined. The cells round it were
/// dropped: the lobes of r² = sin(3θ)/(3θ) lost their tips, which stood as a
/// slit in the wall in 3D, and a traced curve broke where θ = 0.
void main() {
  MathNode trig(String fn, String arg) =>
      TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: arg)]);
  List<MathNode> sinc(String lhs) => <MathNode>[
    LiteralNode(text: '$lhs='),
    FractionNode(
      num: <MathNode>[trig('sin', '3θ')],
      den: <MathNode>[LiteralNode(text: '3θ')],
    ),
  ];
  PlotExpression lit(String s) =>
      PlotExpression.compile(<MathNode>[LiteralNode(text: s)]);

  test('sin(x)/x is 1 at 0', () {
    final PlotExpression f = PlotExpression.compile(<MathNode>[
      FractionNode(
        num: <MathNode>[trig('sin', 'x')],
        den: <MathNode>[LiteralNode(text: 'x')],
      ),
    ]);
    expect(f.evaluate(0), closeTo(1, 1e-9));
  });

  test('a jump, or a stretch where a line is undefined, stays a gap', () {
    // x/√(x²) is −1 on one side of 0 and 1 on the other: nothing to fill in.
    final PlotExpression sign = PlotExpression.compile(<MathNode>[
      FractionNode(
        num: <MathNode>[LiteralNode(text: 'x')],
        den: <MathNode>[
          RootNode(
            radicand: <MathNode>[
              ExponentNode(
                base: <MathNode>[LiteralNode(text: 'x')],
                power: <MathNode>[LiteralNode(text: '2')],
              ),
            ],
            isSquareRoot: true,
          ),
        ],
      ),
    ]);
    expect(sign.evaluate(-0.5), closeTo(-1, 1e-12));
    expect(sign.evaluate(0.5), closeTo(1, 1e-12));
    expect(sign.evaluate(0).isNaN, isTrue);
    // And x^0.5 is undefined all the way along the negative axis.
    expect(lit('x^0.5').evaluate(-1).isNaN, isTrue);
  });

  test('the lobes of r² = sin(3θ)/(3θ) keep their tips', () {
    const double b = 1.3;
    final List<LevelSegment> curve = marchingSquares(
      PlotExpression.compile(sinc('r^2')),
      -b,
      b,
      -b,
      b,
      resolution: 80,
    );
    // Every end of every segment is shared with another, except within a
    // cell of the origin, where all the small loops meet and θ means
    // nothing.
    final double grain = 2 * b * 1e-9;
    (int, int) key(double x, double y) => (
      (x / grain).round(),
      (y / grain).round(),
    );
    final Map<(int, int), int> uses = <(int, int), int>{};
    for (final LevelSegment s in curve) {
      uses.update(key(s.x1, s.y1), (int n) => n + 1, ifAbsent: () => 1);
      uses.update(key(s.x2, s.y2), (int n) => n + 1, ifAbsent: () => 1);
    }
    for (final LevelSegment s in curve) {
      for (final (double x, double y) in <(double, double)>[
        (s.x1, s.y1),
        (s.x2, s.y2),
      ]) {
        if (uses[key(x, y)] != 1) continue;
        expect(
          math.sqrt(x * x + y * y),
          lessThan(2 * b / 80 * 1.5),
          reason: 'loose end at ($x, $y)',
        );
      }
    }
  });

  test('the traced r = sin(3θ)/(3θ) runs through its tip', () {
    final List<LevelSegment> curve = marchingSquares(
      PlotExpression.compile(sinc('r')),
      -1.5,
      1.5,
      -1.5,
      1.5,
    );
    double distanceTo(double x, double y) {
      double best = double.infinity;
      for (final LevelSegment s in curve) {
        final double dx = s.x2 - s.x1, dy = s.y2 - s.y1;
        final double len2 = dx * dx + dy * dy;
        final double t =
            len2 == 0
                ? 0
                : (((x - s.x1) * dx + (y - s.y1) * dy) / len2).clamp(0.0, 1.0);
        best = math.min(
          best,
          math.sqrt(
            math.pow(s.x1 + t * dx - x, 2) + math.pow(s.y1 + t * dy - y, 2),
          ),
        );
      }
      return best;
    }

    expect(distanceTo(1, 0), lessThan(1e-3));
  });
}
