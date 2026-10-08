import 'dart:math';

import '../../math_renderer/math_nodes.dart';
import '../models/enums.dart';
import 'plot_expression.dart';

/// A vector field written as `f₁x̂ + f₂ŷ + f₃ẑ`.
///
/// This used to split the *serialized string* at depth-0 `+`/`-` and hand each
/// axis coefficient to the old `MathParser`, which returned `0` for anything it
/// did not recognise. That was the last place the silent-zero bug survived:
/// `∫`, `Σ`, `ans` or a stray variable inside a component drew a confident
/// field of zeros instead of reporting a problem.
///
/// Components are now split from the **node tree** and compiled with
/// [PlotExpression], so a vector field understands exactly what the calculator
/// understands and says so when it cannot sample something.
class VectorFieldParser {
  final PlotExpression? xComponent;
  final PlotExpression? yComponent;
  final PlotExpression? zComponent;

  /// Non-null when a component failed to compile, so callers can surface a
  /// reason rather than draw zeros.
  final String? error;

  const VectorFieldParser({
    this.xComponent,
    this.yComponent,
    this.zComponent,
    this.error,
  });

  /// True when the components are swept by a parameter rather than sampled
  /// over space.
  ///
  /// The same notation carries both meanings, and the variables decide which:
  /// `y x̂ − x ŷ` places an arrow at every point of the plane, while
  /// `cos(u) x̂ + sin(u) ŷ` is a single point whose position depends on u, so
  /// sweeping u traces a circle. One is a field, the other a path.
  bool get isParametric => <PlotExpression?>[
    xComponent,
    yComponent,
    zComponent,
  ].any((PlotExpression? c) => c != null && c.isParametric);

  /// True when both parameters appear, so the sweep covers a surface.
  ///
  /// Counted across the whole vector rather than within one component, because
  /// that is where the second dimension comes from: `u x̂ + v ŷ` is a patch of
  /// the plane even though neither component mentions both parameters on its
  /// own.
  bool get isParametricSurface =>
      <PlotExpression?>[xComponent, yComponent, zComponent]
          .whereType<PlotExpression>()
          .expand((PlotExpression c) => c.variables)
          .toSet()
          .containsAll(PlotExpression.parameterVariables);

  /// True when [nodes] contain a unit vector anywhere at the top level.
  static bool isVectorFieldNodes(List<MathNode> nodes) =>
  // The complex variable extends UnitVectorNode for the editor's sake and
  // is emphatically not one: a line containing z̲ is a function of a
  // complex variable, not a field with a z̲ component.
  nodes.any((n) => n is UnitVectorNode && n is! ComplexVariableNode);

  /// Split [nodes] into per-axis components and compile each.
  ///
  /// Returns null when there is no unit vector to key off, which is how the
  /// caller decides this is an ordinary scalar expression. [definitions] are
  /// the values the plot's other rows give its letters.
  static VectorFieldParser? fromNodes(
    List<MathNode> nodes, {
    PlotDefinitions? definitions,
  }) {
    if (!isVectorFieldNodes(nodes)) return null;

    final terms = _splitTerms(nodes);

    // What each term adds to the x, y and z components. A term is summed into
    // every component its unit vector has, rather than dropped into one slot
    // per axis: slots let 2x̂ + 3x̂ keep only the 3x̂, let x̂ + r̂ lose the x̂,
    // and had no room for a ρ̂ that leans into all three axes at once.
    final List<List<MathNode>> xParts = <List<MathNode>>[];
    final List<List<MathNode>> yParts = <List<MathNode>>[];
    final List<List<MathNode>> zParts = <List<MathNode>>[];

    for (final _Term term in terms) {
      final List<MathNode> body = term.nodes;
      if (body.isEmpty) continue;

      // The unit vector marks which axis this term belongs to. It is normally
      // last (`3x·x̂`) but tolerate it leading (`x̂·3x`) too.
      UnitVectorNode? axis;
      final List<MathNode> coefficient = <MathNode>[];
      for (final MathNode n in body) {
        if (n is UnitVectorNode && n is! ComplexVariableNode && axis == null) {
          axis = n;
        } else {
          coefficient.add(n);
        }
      }
      if (axis == null) continue; // a scalar term in a vector expression

      // `x̂` on its own means a coefficient of 1; `-x̂` means -1.
      final List<MathNode> withSign = _applySign(coefficient, term.negative);

      final List<_Factor?> column = _cartesianColumn(axis.axis);
      final List<List<List<MathNode>>> parts = <List<List<MathNode>>>[
        xParts,
        yParts,
        zParts,
      ];
      for (int i = 0; i < 3; i++) {
        final _Factor? factor = column[i];
        if (factor == null) continue;
        // A Cartesian unit vector contributes its coefficient as typed, so a
        // field written in x̂, ŷ, ẑ compiles exactly as it always has.
        if (!factor.negative && factor.nodes.isEmpty) {
          parts[i].add(withSign);
          continue;
        }
        parts[i].add(<MathNode>[
          if (factor.negative) LiteralNode(text: '-'),
          ParenthesisNode(content: withSign),
          LiteralNode(text: '*'),
          ...factor.nodes,
        ]);
      }
    }

    // A field written in a rotating basis becomes Cartesian components here
    // rather than anywhere downstream. r̂, θ̂, ρ̂ and φ̂ point somewhere
    // different at every sample, so the conversion is per point — but it can
    // be *written* as an expression, because θ and φ are variables the
    // sampler already knows how to supply (see [_cartesianColumn]). So the
    // Cartesian components are built as node trees and compiled like any
    // other expression. Nothing that draws a vector field need change.
    List<MathNode>? sum(List<List<MathNode>> parts) {
      if (parts.isEmpty) return null;
      if (parts.length == 1) return parts.single;
      return <MathNode>[
        for (int i = 0; i < parts.length; i++) ...<MathNode>[
          if (i > 0) LiteralNode(text: '+'),
          ParenthesisNode(content: parts[i]),
        ],
      ];
    }

    final List<MathNode>? xNodes = sum(xParts);
    final List<MathNode>? yNodes = sum(yParts);
    final List<MathNode>? zNodes = sum(zParts);

    if (xNodes == null && yNodes == null && zNodes == null) return null;

    PlotExpression? compile(List<MathNode>? n) =>
        n == null
            ? null
            : PlotExpression.compile(
              n,
              isVectorComponent: true,
              definitions: definitions,
            );

    final x = compile(xNodes);
    final y = compile(yNodes);
    final z = compile(zNodes);

    final String? firstError =
        <PlotExpression?>[x, y, z]
            .where((e) => e != null && !e.isValid)
            .map((e) => e!.error)
            .firstOrNull;

    return VectorFieldParser(
      xComponent: x,
      yComponent: y,
      zComponent: z,
      error: firstError,
    );
  }

  /// The unit vector [axis] in Cartesian components — one column of the
  /// matrix that takes the local basis to x̂, ŷ, ẑ. Null where a component is
  /// zero, and an empty factor where it is one.
  ///
  ///   r̂ = (cos θ, sin θ, 0)               θ̂ = (−sin θ, cos θ, 0)
  ///   ρ̂ = (sin φ cos θ, sin φ sin θ, cos φ)
  ///   φ̂ = (cos φ cos θ, cos φ sin θ, −sin φ)
  ///
  /// θ̂ is the same vector in cylindrical and spherical, since both measure θ
  /// the same way, so it never needs to know which system it came from. ρ̂
  /// and φ̂ used to be read as r̂ and ẑ, which put ρ̂ flat in the xy-plane
  /// everywhere and pointed φ̂ up where it points down.
  static List<_Factor?> _cartesianColumn(String axis) {
    List<MathNode> trig(String fn, String variable) => <MathNode>[
      TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: variable)]),
    ];
    List<MathNode> times(List<MathNode> a, List<MathNode> b) => <MathNode>[
      ...a,
      LiteralNode(text: '*'),
      ...b,
    ];
    _Factor plus(List<MathNode> nodes) => (negative: false, nodes: nodes);
    _Factor minus(List<MathNode> nodes) => (negative: true, nodes: nodes);
    const _Factor one = (negative: false, nodes: <MathNode>[]);

    return switch (axis) {
      'x' => <_Factor?>[one, null, null],
      'y' => <_Factor?>[null, one, null],
      'z' => <_Factor?>[null, null, one],
      'r' => <_Factor?>[plus(trig('cos', 'θ')), plus(trig('sin', 'θ')), null],
      'θ' => <_Factor?>[minus(trig('sin', 'θ')), plus(trig('cos', 'θ')), null],
      'ρ' => <_Factor?>[
        plus(times(trig('sin', 'φ'), trig('cos', 'θ'))),
        plus(times(trig('sin', 'φ'), trig('sin', 'θ'))),
        plus(trig('cos', 'φ')),
      ],
      'φ' => <_Factor?>[
        plus(times(trig('cos', 'φ'), trig('cos', 'θ'))),
        plus(times(trig('cos', 'φ'), trig('sin', 'θ'))),
        minus(trig('sin', 'φ')),
      ],
      _ => <_Factor?>[null, null, null],
    };
  }

  /// Coefficient nodes with the term's sign folded in.
  static List<MathNode> _applySign(List<MathNode> coefficient, bool negative) {
    final List<MathNode> body =
        coefficient.isEmpty ? <MathNode>[LiteralNode(text: '1')] : coefficient;
    if (!negative) return body;
    return <MathNode>[LiteralNode(text: '-'), ParenthesisNode(content: body)];
  }

  /// Break a flat node list into additive terms.
  ///
  /// Splitting has to look *inside* `LiteralNode` text as well as between
  /// nodes, because the editor coalesces typed characters — `2x+3` can arrive
  /// as a single literal rather than three nodes. Nested content already lives
  /// inside its own node (parentheses, fractions), so a flat scan is enough.
  static List<_Term> _splitTerms(List<MathNode> nodes) {
    final List<_Term> terms = <_Term>[_Term(negative: false)];

    void startTerm({required bool negative}) {
      terms.add(_Term(negative: negative));
    }

    for (final MathNode node in nodes) {
      if (node is! LiteralNode) {
        terms.last.nodes.add(node);
        continue;
      }

      final StringBuffer buffer = StringBuffer();
      void flush() {
        if (buffer.isEmpty) return;
        terms.last.nodes.add(LiteralNode(text: buffer.toString()));
        buffer.clear();
      }

      for (final String ch in node.text.split('')) {
        if (ch == '+' || ch == '-' || ch == '−') {
          final bool atStart =
              buffer.isEmpty && terms.last.nodes.isEmpty && terms.length == 1;
          if (atStart) {
            // Leading unary sign on the very first term.
            terms.last = _Term(negative: ch != '+');
            continue;
          }
          flush();
          startTerm(negative: ch != '+');
        } else {
          buffer.write(ch);
        }
      }
      flush();
    }

    return terms;
  }

  bool get is3D => zComponent != null;

  double _eval(PlotExpression? e, double x, double y, double z) =>
      e == null ? 0 : e.evaluate(x, y, z);

  (double, double, double) evaluate(double x, double y, [double z = 0]) {
    return (
      _eval(xComponent, x, y, z),
      _eval(yComponent, x, y, z),
      _eval(zComponent, x, y, z),
    );
  }

  double magnitude(double x, double y, [double z = 0]) {
    final (fx, fy, fz) = evaluate(x, y, z);
    return sqrt(fx * fx + fy * fy + fz * fz);
  }

  double componentValue(SurfaceMode mode, double x, double y, [double z = 0]) {
    final (fx, fy, fz) = evaluate(x, y, z);
    switch (mode) {
      case SurfaceMode.x:
        return fx;
      case SurfaceMode.y:
        return fy;
      case SurfaceMode.z:
        return fz;
      case SurfaceMode.magnitude:
        return sqrt(fx * fx + fy * fy + fz * fz);
      case SurfaceMode.none:
        return 0;
    }
  }

  (double, double, double) normalized(double x, double y, [double z = 0]) {
    final (fx, fy, fz) = evaluate(x, y, z);
    final mag = sqrt(fx * fx + fy * fy + fz * fz);
    if (mag < 1e-10) return (0, 0, 0);
    return (fx / mag, fy / mag, fz / mag);
  }

  @override
  String toString() =>
      'Vector(x: ${xComponent != null}, y: ${yComponent != null}, '
      'z: ${zComponent != null})';
}

/// One entry of a basis column: what a unit vector's coefficient is
/// multiplied by to give its share of a Cartesian component.
typedef _Factor = ({bool negative, List<MathNode> nodes});

class _Term {
  final bool negative;
  final List<MathNode> nodes = <MathNode>[];
  _Term({required this.negative});
}
