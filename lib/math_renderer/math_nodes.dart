/// Base class for all math expression nodes.
abstract class MathNode {
  // Monotonic per-process id source. Ids are used as keys in layout/selection
  // caches, so they must be unique within a session; a random 31-bit value
  // risked birthday-paradox collisions over a long session. Ids are never
  // persisted (serialization stores structure only), so resetting to 0 on
  // each launch is fine.
  static int _nextId = 0;

  final String id;
  MathNode() : id = (_nextId++).toString();
}

/// A literal text node containing numbers, variables, and operators.
class LiteralNode extends MathNode {
  String text;
  LiteralNode({this.text = ""});
}

/// A fraction node with numerator and denominator.
class FractionNode extends MathNode {
  List<MathNode> numerator;
  List<MathNode> denominator;
  FractionNode({List<MathNode>? num, List<MathNode>? den})
    : numerator = num ?? [LiteralNode()],
      denominator = den ?? [LiteralNode()];
}

/// An exponent node with base and power.
class ExponentNode extends MathNode {
  List<MathNode> base;
  List<MathNode> power;
  ExponentNode({List<MathNode>? base, List<MathNode>? power})
    : base = base ?? [LiteralNode()],
      power = power ?? [LiteralNode()];
}

/// A logarithm node supporting natural log and log with custom base.
class LogNode extends MathNode {
  List<MathNode> base; // The subscript (n in log_n)
  List<MathNode> argument; // What we're taking log of
  bool isNaturalLog; // If true, it's ln (no base shown)

  LogNode({
    List<MathNode>? base,
    List<MathNode>? argument,
    this.isNaturalLog = false,
  }) : base = base ?? [LiteralNode(text: "10")],
       argument = argument ?? [LiteralNode()];
}

/// A trigonometric function node (sin, cos, tan, etc.).
class TrigNode extends MathNode {
  final String function; // sin, cos, tan, asin, acos, atan, log, ln
  List<MathNode> argument;
  TrigNode({required this.function, List<MathNode>? argument})
    : argument = argument ?? [LiteralNode()];
}

/// A root node supporting square roots and nth roots.
class RootNode extends MathNode {
  List<MathNode> index; // The n in ⁿ√
  List<MathNode> radicand; // What's under the root
  final bool isSquareRoot; // If true, don't show index (it's 2)
  RootNode({
    List<MathNode>? index,
    List<MathNode>? radicand,
    this.isSquareRoot = false,
  }) : index = index ?? [LiteralNode(text: isSquareRoot ? "2" : "")],
       radicand = radicand ?? [LiteralNode()];
}

/// A permutation node (nPr).
class PermutationNode extends MathNode {
  List<MathNode> n; // Top number
  List<MathNode> r; // Bottom number
  PermutationNode({List<MathNode>? n, List<MathNode>? r})
    : n = n ?? [LiteralNode()],
      r = r ?? [LiteralNode()];
}

/// A combination node (nCr).
class CombinationNode extends MathNode {
  List<MathNode> n; // Top number
  List<MathNode> r; // Bottom number
  CombinationNode({List<MathNode>? n, List<MathNode>? r})
      : n = n ?? [LiteralNode()],
        r = r ?? [LiteralNode()];
}

/// A summation node (sigma) with variable, bounds, and body.
class SummationNode extends MathNode {
  List<MathNode> variable; // The index variable (e.g., x)
  List<MathNode> lower; // Lower bound
  List<MathNode> upper; // Upper bound
  List<MathNode> body; // Expression to sum
  SummationNode({
    List<MathNode>? variable,
    List<MathNode>? lower,
    List<MathNode>? upper,
    List<MathNode>? body,
  }) : variable = variable ?? [LiteralNode(text: 'x')],
       lower = lower ?? [LiteralNode()],
       upper = upper ?? [LiteralNode()],
       body = body ?? [LiteralNode()];
}

/// A product node (pi) with variable, bounds, and body.
class ProductNode extends MathNode {
  List<MathNode> variable; // The index variable (e.g., x)
  List<MathNode> lower; // Lower bound
  List<MathNode> upper; // Upper bound
  List<MathNode> body; // Expression to multiply
  ProductNode({
    List<MathNode>? variable,
    List<MathNode>? lower,
    List<MathNode>? upper,
    List<MathNode>? body,
  }) : variable = variable ?? [LiteralNode(text: 'x')],
       lower = lower ?? [LiteralNode()],
       upper = upper ?? [LiteralNode()],
       body = body ?? [LiteralNode()];
}

/// A derivative node (d/dx). When [isDefinite] is true it is evaluated at a
/// point ([at]); when false it is a symbolic (indefinite) derivative and the
/// evaluation point is neither shown nor editable.
class DerivativeNode extends MathNode {
  List<MathNode> variable; // Variable of differentiation (e.g., x)
  List<MathNode> at; // Evaluation point (x = a)
  List<MathNode> body; // Expression to differentiate
  final bool isDefinite;
  DerivativeNode({
    List<MathNode>? variable,
    List<MathNode>? at,
    List<MathNode>? body,
    this.isDefinite = true,
  }) : variable = variable ?? [LiteralNode(text: 'x')],
       at = at ?? [LiteralNode()],
       body = body ?? [LiteralNode()];
}

/// An integral node. When [isDefinite] is true it has lower/upper bounds;
/// when false it is an indefinite integral and the bounds are neither shown
/// nor editable.
class IntegralNode extends MathNode {
  List<MathNode> variable; // Integration variable (e.g., x)
  List<MathNode> lower; // Lower bound
  List<MathNode> upper; // Upper bound
  List<MathNode> body; // Integrand
  final bool isDefinite;
  IntegralNode({
    List<MathNode>? variable,
    List<MathNode>? lower,
    List<MathNode>? upper,
    List<MathNode>? body,
    this.isDefinite = true,
  }) : variable = variable ?? [LiteralNode(text: 'x')],
       lower = lower ?? [LiteralNode()],
       upper = upper ?? [LiteralNode()],
       body = body ?? [LiteralNode()];
}

/// A complex number node (i * content).
class ComplexNode extends MathNode {
  List<MathNode> content; // The coefficient of i
  ComplexNode({List<MathNode>? content}) : content = content ?? [LiteralNode()];
}

/// A newline node for multi-line expressions.
class NewlineNode extends MathNode {
  NewlineNode() : super();
}

/// A parenthesis node wrapping content.
class ParenthesisNode extends MathNode {
  List<MathNode> content;
  ParenthesisNode({List<MathNode>? content})
    : content = content ?? [LiteralNode()];
}

/// An answer reference node (ans0, ans1, etc.).
class AnsNode extends MathNode {
  List<MathNode> index; // The reference number (0, 1, 2, etc.)

  AnsNode({List<MathNode>? index}) : index = index ?? [LiteralNode()];
}

/// A constant node (e.g. ε₀, μ₀) treated as an atomic unit.
class ConstantNode extends MathNode {
  final String constant;
  ConstantNode(this.constant);
}

/// A unit vector node (e_x, e_y, e_z) treated as an atomic unit.
class UnitVectorNode extends MathNode {
  final String axis; // x, y, z
  UnitVectorNode(this.axis);
}
