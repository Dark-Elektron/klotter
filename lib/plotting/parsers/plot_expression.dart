import '../../math_engine/math_engine_exact.dart';
import '../../math_renderer/math_nodes.dart';
import '../../utils/coordinate_system.dart';

/// How the two sides of a relation compare.
///
/// The distinction is what gets drawn: an equation is a curve, an inequality
/// is a region. Strictness is drawn too — a boundary that is part of the
/// answer is solid, one that is excluded is dashed.
enum PlotRelation {
  equal,
  greater,
  greaterEqual,
  less,
  lessEqual,
  notEqual;

  /// Whether the boundary itself satisfies the relation.
  bool get includesBoundary =>
      this == PlotRelation.equal ||
      this == PlotRelation.greaterEqual ||
      this == PlotRelation.lessEqual;

  /// Whether this shades an area rather than tracing a line.
  bool get isRegion => this != PlotRelation.equal;

  /// Does a signed value of `lhs - rhs` satisfy this relation?
  bool holds(double value) {
    if (!value.isFinite) return false;
    return switch (this) {
      PlotRelation.equal => value == 0,
      PlotRelation.greater => value > 0,
      PlotRelation.greaterEqual => value >= 0,
      PlotRelation.less => value < 0,
      PlotRelation.lessEqual => value <= 0,
      PlotRelation.notEqual => value != 0,
    };
  }
}

/// A calculator expression compiled once for repeated numeric sampling.
///
/// Replaces the standalone `MathParser`, which had its own tokenizer and
/// returned `0` for anything it did not recognise — so `∫`, `d/dx`, `Σ`, `Π`,
/// `nPr`/`nCr` and `ans` expressions plotted as a silent flat line at zero.
/// Compiling through [MathNodeToExpr] means the plot understands exactly what
/// the calculator understands, and reports an [error] for anything it cannot
/// sample instead of inventing a value.
///
/// Compile once, sample many times: [evaluate] walks a prebuilt [Expr] tree and
/// does no parsing.
class PlotExpression {
  /// The compiled expression, or null when [error] is set.
  final Expr? _compiled;

  /// Free variables actually present, restricted to x/y/z.
  final Set<String> variables;

  /// Human-readable reason this expression cannot be plotted, or null.
  final String? error;

  /// True when the source was an equation. [evaluate] then returns
  /// `lhs - rhs`, so the curve or surface is the set where it is zero, rather
  /// than a height to draw directly.
  final bool isLevelSet;

  /// Which system the symbols in this expression belong to.
  final CoordinateSystem system;

  /// How the two sides compare, when this line is a relation at all.
  final PlotRelation relation;

  PlotExpression._(
    this._compiled,
    this.variables,
    this.error, {
    this.isLevelSet = false,
    this.system = CoordinateSystem.cartesian,
    this.relation = PlotRelation.equal,
  });

  /// The variables a plot may bind.
  static const Set<String> plottableVariables = {'x', 'y', 'z'};

  /// The system whose symbols cover [free], or null when none does.
  ///
  /// Tried in order, so a line using only shared symbols settles on the
  /// simplest reading. That costs nothing: where two systems share a symbol
  /// they also agree on its meaning — z is the same height in Cartesian and
  /// cylindrical, θ the same azimuth in cylindrical and spherical — so either
  /// choice samples to the same numbers.
  static CoordinateSystem? _systemFor(Set<String> free) {
    if (free.isEmpty) return CoordinateSystem.cartesian;
    for (final CoordinateSystem s in CoordinateSystem.values) {
      if (free.every(s.variables.contains)) return s;
    }
    return null;
  }

  /// Compile [nodes] from a calculator cell.
  factory PlotExpression.compile(
    List<MathNode> nodes, {
    CoordinateSystem system = CoordinateSystem.cartesian,
    bool isVectorComponent = false,
  }) {
    if (nodes.isEmpty) {
      return PlotExpression._(null, {}, 'Please enter a function');
    }

    // An equation is a level set, not a height. Rewriting it as `lhs - rhs`
    // and plotting where that vanishes is what turns x²+y²=1 into a circle
    // and x²+y²+z²=1 into a sphere.
    //
    // Until this existed the '=' was silently dropped by the converter and
    // only the left side was drawn — x²+y²=1 came out as a paraboloid, with
    // no error to say so.
    final (List<MathNode>, List<MathNode>, PlotRelation)? relation =
        _splitRelation(nodes);
    final bool isLevelSet = relation != null;
    final List<MathNode> source =
        relation == null
            ? nodes
            : <MathNode>[
              ...relation.$1,
              LiteralNode(text: '-'),
              ParenthesisNode(content: relation.$2),
            ];

    if (relation != null && (relation.$1.isEmpty || _isBlank(relation.$2))) {
      return PlotExpression._(
        null,
        {},
        'Both sides of the comparison are needed',
      );
    }

    Expr compiled;
    try {
      compiled = MathNodeToExpr.convert(source).simplify();
    } catch (e) {
      return PlotExpression._(null, {}, 'Invalid function syntax');
    }

    final Set<String> free = compiled.freeVariables;
    // Which system a line is written in is read off its own symbols rather
    // than set anywhere. Every system converts to Cartesian before it is
    // drawn, so one plot can carry x + y on one line and r on the next and
    // both are fine. What is not fine is a single *line* written half in
    // each, because then its symbols contradict one another.
    // Only the coordinate symbols choose the system. Anything else is simply
    // an unknown name, and falls through to the error below that says so —
    // routing it through here instead reported a mix of nothing at all.
    final Set<String> coords = free.intersection(allCoordinateSymbols);
    final CoordinateSystem? inferred = _systemFor(coords);
    if (inferred == null) {
      final List<String> mixed = coords.toList()..sort();
      return PlotExpression._(
        null,
        const <String>{},
        'Cannot mix ${mixed.join(' and ')} in one line: '
        'they belong to different coordinate systems',
      );
    }
    system = inferred;

    final Set<String> unknown = free.difference(system.variables.toSet());
    if (unknown.isNotEmpty) {
      final List<String> sorted = unknown.toList()..sort();
      return PlotExpression._(
        null,
        const {},
        'Cannot plot: unknown variable ${sorted.join(', ')}',
      );
    }

    // Without an '=' a line is a height, z = f(...), so z is the answer rather
    // than an input. Mixing z with x or y leaves nothing to sample it over:
    // `x+z` was evaluated with z bound to 0 and drew the graph of x, with
    // nothing to say the z had been dropped. An equation is the way to plot a
    // relation among all three.
    // A vector field's components are functions of position, so all three
    // coordinates are inputs to them. The rule below is about a *height*,
    // where the third coordinate is the answer rather than something to
    // sample over — applying it to a component rejected fields like
    // rθθ̂ + zr̂, whose components legitimately mention all three.
    final List<String> names = system.variables;
    if (!isVectorComponent &&
        !isLevelSet &&
        free.contains(names[2]) &&
        (free.contains(names[0]) || free.contains(names[1]))) {
      return PlotExpression._(
        null,
        const {},
        'Cannot plot ${names[2]} with ${names[0]} or ${names[1]}: '
        'add an = to make it a surface',
      );
    }

    // Symbolic calculus resolves during simplify(), which cannot see the
    // sampled value of x. An unresolved derivative/integral that still depends
    // on a plot variable is not samplable — say so rather than draw zeros.
    if (_hasUnresolvedCalculus(compiled)) {
      return PlotExpression._(
        null,
        {},
        'Cannot plot: unresolved derivative or integral',
      );
    }

    return PlotExpression._(
      compiled,
      free,
      null,
      isLevelSet: isLevelSet,
      system: system,
      relation: relation?.$3 ?? PlotRelation.equal,
    );
  }

  /// Split [nodes] at a top-level `=`, or null when there is not one.
  ///
  /// The scan looks *inside* `LiteralNode` text as well as between nodes,
  /// because the editor coalesces typed characters — `x^2+y^2=1` arrives as a
  /// single literal, not as three nodes.
  /// The operators a relation can be built on, longest first so that a
  /// two-character form is never mistaken for its first character.
  static const Map<String, PlotRelation> _relationOperators =
      <String, PlotRelation>{
        '≥': PlotRelation.greaterEqual,
        '≤': PlotRelation.lessEqual,
        '≠': PlotRelation.notEqual,
        '>=': PlotRelation.greaterEqual,
        '<=': PlotRelation.lessEqual,
        '=': PlotRelation.equal,
        '>': PlotRelation.greater,
        '<': PlotRelation.less,
      };

  static (List<MathNode>, List<MathNode>, PlotRelation)? _splitRelation(
    List<MathNode> nodes,
  ) {
    for (int i = 0; i < nodes.length; i++) {
      final MathNode node = nodes[i];
      if (node is! LiteralNode) continue;

      int at = -1;
      int width = 0;
      PlotRelation relation = PlotRelation.equal;
      for (final MapEntry<String, PlotRelation> op
          in _relationOperators.entries) {
        final int found = node.text.indexOf(op.key);
        if (found < 0) continue;
        // Earliest operator in the text wins; on a tie the longer one does,
        // so ">=" is not read as ">" followed by a stray "=".
        if (at < 0 || found < at || (found == at && op.key.length > width)) {
          at = found;
          width = op.key.length;
          relation = op.value;
        }
      }
      if (at < 0) continue;

      final List<MathNode> lhs = <MathNode>[
        ...nodes.take(i),
        if (at > 0) LiteralNode(text: node.text.substring(0, at)),
      ];
      final List<MathNode> rhs = <MathNode>[
        if (at + width < node.text.length)
          LiteralNode(text: node.text.substring(at + width)),
        ...nodes.skip(i + 1),
      ];
      return (lhs, rhs, relation);
    }
    return null;
  }

  static bool _isBlank(List<MathNode> nodes) =>
      nodes.isEmpty ||
      nodes.every((n) => n is LiteralNode && n.text.trim().isEmpty);

  /// Compile every line of a cell as its own curve.
  ///
  /// The action button inserts a [NewlineNode] rather than starting a new
  /// cell, so one cell holds several expressions that share a plot. Blank
  /// lines are dropped; a cell with no newline yields a single entry, so
  /// callers never need to special-case the common case.
  static List<PlotExpression> compileAll(
    List<MathNode> nodes, {
    CoordinateSystem system = CoordinateSystem.cartesian,
  }) {
    final List<List<MathNode>> lines = <List<MathNode>>[<MathNode>[]];
    for (final MathNode node in nodes) {
      if (node is NewlineNode) {
        lines.add(<MathNode>[]);
      } else {
        lines.last.add(node);
      }
    }

    final List<PlotExpression> out = <PlotExpression>[];
    for (final List<MathNode> line in lines) {
      if (line.isEmpty) continue;
      out.add(PlotExpression.compile(line, system: system));
    }
    if (out.isEmpty) {
      out.add(PlotExpression.compile(nodes, system: system));
    }
    return out;
  }

  /// Whether this expression compiled successfully.
  bool get isValid => _compiled != null;

  /// Whether the expression depends on the nth variable of its system.
  ///
  /// By position, not by name: the first variable is x in Cartesian, r in
  /// cylindrical and ρ in spherical, and everything that asks "does this vary
  /// along the first axis" means the same thing in all three.
  bool _uses(int axis) => variables.contains(system.variables[axis]);

  /// True when the expression depends on the first variable (x, r or ρ).
  bool get usesX => _uses(0);

  /// True when the expression depends on the second variable (y or θ).
  bool get usesY => _uses(1);

  /// True when the expression depends on the third variable (z or φ).
  bool get usesZ => _uses(2);

  /// Whether this line is a surface rather than a curve.
  ///
  /// Only a genuinely two-variable height is. `z = cos(y)` is a valid surface
  /// in the strict sense — a sheet extruded along x — but drawing it that way
  /// answers a question nobody asked: someone who types cos(y) wants the
  /// cosine curve, not a corrugated plane. So a line is a surface only when it
  /// varies in both directions, and a single-variable line stays a curve even
  /// when it shares the axes with a surface.
  bool get isSurface => !isLevelSet && usesX && usesY;

  /// The axis a single-variable curve runs along.
  ///
  /// The variable's own axis carries the parameter and the value is drawn
  /// perpendicular to it. sin(x) and cos(y) put their value on the height
  /// axis; sin(z), whose parameter already *is* the height axis, puts its
  /// value on x, standing the wave up the z axis instead.
  ///
  /// 'x' also covers a constant, which has no variable to run along.
  String get curveAxis {
    if (usesZ && !usesX && !usesY) return 'z';
    if (usesY && !usesX) return 'y';
    return 'x';
  }

  /// Sample the expression at a point in **Cartesian** space. Returns NaN when
  /// invalid, which painters already treat as a gap in the curve.
  ///
  /// Everything that draws — the curve tracer, the height-surface sampler,
  /// marching squares and marching tetrahedra — walks a Cartesian lattice. An
  /// expression written in another system is handled by converting the sample
  /// point rather than by rewriting the expression, so all of that machinery
  /// works unchanged: ρ = 1 comes out as the unit sphere because at every
  /// sampled (x, y, z) the value of ρ is known, and r = 1 + cos(θ) traces a
  /// cardioid through the same code that draws any other implicit curve.
  double evaluate(double x, [double y = 0, double z = 0]) {
    final Expr? c = _compiled;
    if (c == null) return double.nan;
    final (double a, double b, double d) = toCoordinates(system, x, y, z);
    final List<String> names = system.variables;
    // The binding map is reused rather than rebuilt. Sampling is the hot path
    // by a wide margin — marching squares alone asks for ~48,000 values per
    // frame while the window is moving — and a fresh three-entry map for each
    // of those is pure allocation.
    _bindings[names[0]] = a;
    _bindings[names[1]] = b;
    _bindings[names[2]] = d;
    try {
      return c.evalWith(_bindings);
    } catch (_) {
      return double.nan;
    }
  }

  /// Scratch space for [evaluate]. Safe to share because painting is
  /// single-threaded and the map never outlives the call.
  final Map<String, double> _bindings = <String, double>{};

  /// An expression that always evaluates to NaN — used where a component of a
  /// vector field is absent.
  static final PlotExpression invalid = PlotExpression._(
    null,
    {},
    'No expression',
  );

  /// A level set of the first two variables is a curve; add the third and it
  /// is a surface.
  /// A level set of two variables is a curve; of three, a surface.
  ///
  /// Spherical counts whatever it mentions: ρ, θ and φ only exist as a way of
  /// describing 3D space, so ρ = 1 is a sphere even though it never names the
  /// third symbol. In Cartesian and cylindrical the third symbol is z, whose
  /// absence genuinely does mean a flat curve.
  bool get isImplicitSurface =>
      isLevelSet && (usesZ || system == CoordinateSystem.spherical);

  static bool _hasUnresolvedCalculus(Expr expr) {
    if (expr is DerivativeExpr || expr is IntegralExpr) {
      return expr.freeVariables.isNotEmpty;
    }
    if (expr is SumExpr) return expr.terms.any(_hasUnresolvedCalculus);
    if (expr is ProdExpr) return expr.factors.any(_hasUnresolvedCalculus);
    if (expr is PowExpr) {
      return _hasUnresolvedCalculus(expr.base) ||
          _hasUnresolvedCalculus(expr.exponent);
    }
    if (expr is RootExpr) {
      return _hasUnresolvedCalculus(expr.radicand) ||
          _hasUnresolvedCalculus(expr.index);
    }
    if (expr is LogExpr) {
      return _hasUnresolvedCalculus(expr.argument) ||
          (!expr.isNaturalLog && _hasUnresolvedCalculus(expr.base));
    }
    if (expr is TrigExpr) return _hasUnresolvedCalculus(expr.argument);
    if (expr is AbsExpr) return _hasUnresolvedCalculus(expr.operand);
    if (expr is DivExpr) {
      return _hasUnresolvedCalculus(expr.numerator) ||
          _hasUnresolvedCalculus(expr.denominator);
    }
    return false;
  }
}
