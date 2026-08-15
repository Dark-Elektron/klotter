import 'dart:math';

import '../../math_renderer/math_nodes.dart';
import '../../utils/coordinate_system.dart';
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

  /// True when [nodes] contain a unit vector anywhere at the top level.
  static bool isVectorFieldNodes(List<MathNode> nodes) =>
      nodes.any((n) => n is UnitVectorNode);

  /// Split [nodes] into per-axis components and compile each.
  ///
  /// Returns null when there is no unit vector to key off, which is how the
  /// caller decides this is an ordinary scalar expression.
  static VectorFieldParser? fromNodes(List<MathNode> nodes) {
    if (!isVectorFieldNodes(nodes)) return null;

    final terms = _splitTerms(nodes);

    // Named for what they mean rather than which axis: the same slot holds x
    // or r or ρ depending on the basis the field was written in.
    List<MathNode>? radial;
    List<MathNode>? azimuthal;
    List<MathNode>? polar;
    CoordinateSystem basis = CoordinateSystem.cartesian;

    for (final _Term term in terms) {
      final List<MathNode> body = term.nodes;
      if (body.isEmpty) continue;

      // The unit vector marks which axis this term belongs to. It is normally
      // last (`3x·x̂`) but tolerate it leading (`x̂·3x`) too.
      UnitVectorNode? axis;
      final List<MathNode> coefficient = <MathNode>[];
      for (final MathNode n in body) {
        if (n is UnitVectorNode && axis == null) {
          axis = n;
        } else {
          coefficient.add(n);
        }
      }
      if (axis == null) continue; // a scalar term in a vector expression

      // `x̂` on its own means a coefficient of 1; `-x̂` means -1.
      final List<MathNode> withSign = _applySign(coefficient, term.negative);

      switch (axis.axis) {
        case 'x':
        case 'r':
        case 'ρ':
          radial = withSign;
        case 'y':
        case 'θ':
          azimuthal = withSign;
        case 'z':
        case 'φ':
          polar = withSign;
      }
      if (axis.axis != 'x' && axis.axis != 'y' && axis.axis != 'z') {
        basis =
            (axis.axis == 'ρ' || axis.axis == 'φ')
                ? CoordinateSystem.spherical
                : CoordinateSystem.cylindrical;
      }
    }

    // A field written in a rotating basis becomes Cartesian components here
    // rather than anywhere downstream. r-hat and theta-hat point somewhere
    // different at every sample, so the conversion is per point — but it can
    // be *written* as an expression, because θ is itself a variable the
    // sampler already knows how to supply:
    //
    //   r̂ = (cos θ, sin θ)        θ̂ = (−sin θ, cos θ)
    //
    // so the Cartesian components are built as node trees and compiled like
    // any other expression. Nothing that draws a vector field need change.
    List<MathNode>? xNodes;
    List<MathNode>? yNodes;
    List<MathNode>? zNodes;

    if (basis == CoordinateSystem.cartesian) {
      xNodes = radial;
      yNodes = azimuthal;
      zNodes = polar;
    } else {
      List<MathNode> trig(String fn) => <MathNode>[
        TrigNode(function: fn, argument: <MathNode>[LiteralNode(text: 'θ')]),
      ];
      List<MathNode>? combine(
        List<MathNode>? first,
        String firstTrig,
        bool negateFirst,
        List<MathNode>? second,
        String secondTrig,
      ) {
        if (first == null && second == null) return null;
        return <MathNode>[
          if (first != null) ...<MathNode>[
            if (negateFirst) LiteralNode(text: '-'),
            ParenthesisNode(content: first),
            LiteralNode(text: '*'),
            ...trig(firstTrig),
          ],
          if (first != null && second != null) LiteralNode(text: '+'),
          if (second != null) ...<MathNode>[
            ParenthesisNode(content: second),
            LiteralNode(text: '*'),
            ...trig(secondTrig),
          ],
        ];
      }

      xNodes = combine(azimuthal, 'sin', true, radial, 'cos');
      yNodes = combine(radial, 'sin', false, azimuthal, 'cos');
      zNodes = polar;
    }

    if (xNodes == null && yNodes == null && zNodes == null) return null;

    PlotExpression? compile(List<MathNode>? n) =>
        n == null ? null : PlotExpression.compile(n, isVectorComponent: true);

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

class _Term {
  final bool negative;
  final List<MathNode> nodes = <MathNode>[];
  _Term({required this.negative});
}
