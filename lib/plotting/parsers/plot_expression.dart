import 'dart:math' as math;

import '../../math_engine/math_engine_exact.dart';
import '../../math_renderer/math_nodes.dart';
import '../../math_engine/math_engine.dart';
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

  /// Which row of its plot this came from, and so which colour it wears.
  ///
  /// Mutable and assigned after compiling, because it is a property of the
  /// expression's place in the cell rather than of the maths.
  ///
  /// Colour used to be position in whatever list a painter happened to be
  /// iterating. Those lists are filtered — invalid lines are dropped, vector
  /// lines are dropped — and 3D re-partitions them into surfaces, standing
  /// curves and equations, indexing each from zero. The same plot therefore got
  /// different colours in 2D and in 3D, and a swatch beside a row could not
  /// have matched either. The row number is the one index that means the same
  /// thing everywhere.
  int seriesIndex = 0;

  /// Whether this row's curve is drawn.
  ///
  /// A hidden row keeps its place in [seriesIndex], so hiding one curve never
  /// recolours the others.
  bool hidden = false;

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
    bool isComplex = false,
    Expr? sweptRadius,
    this.thetaRange = defaultThetaRange,
  }) : _isComplex = isComplex,
       _sweptRadius = sweptRadius,
       _chain = null;

  /// A chain of comparisons, such as `-1 < x < 2` (see [_compileChain]).
  PlotExpression._chained(
    List<({PlotExpression part, double sign})> chain,
    this.variables, {
    required this.system,
    required this.relation,
    this.thetaRange = defaultThetaRange,
  }) : _compiled = null,
       error = null,
       isLevelSet = true,
       _isComplex = false,
       _sweptRadius = null,
       _chain = chain;

  /// The comparisons a chained line is made of, each with the sign that turns
  /// it to face "less than": where every one of them is below zero is the
  /// region, so the largest of them is below zero exactly there. Null for an
  /// ordinary line.
  final List<({PlotExpression part, double sign})>? _chain;

  final bool _isComplex;

  /// The f of an explicit polar curve `r = f(θ)` or spherical surface
  /// `ρ = f(θ, φ)` — all it takes to trace one — or null for any other line.
  final Expr? _sweptRadius;

  /// The span θ is swept over when this line is traced (see [sweepsTheta]).
  ///
  /// Part of the line rather than passed to whatever draws it, so everything
  /// that reads the line agrees about it, and so a different range makes a
  /// different line: the drawn geometry is cached against the line itself.
  final ({double min, double max}) thetaRange;

  /// Two turns, one either side of zero.
  ///
  /// A curve whose f repeats every turn looks the same over any one turn and
  /// is drawn once (see [sweptThetaRange]); for one that does not, both
  /// directions are part of it. sin(3θ)/(3θ) gives the same r at θ and −θ, so
  /// over 0 to 2π alone it came out as the top half of a shape whose bottom
  /// half was missing.
  static const ({double min, double max}) defaultThetaRange = (
    min: -2 * math.pi,
    max: 2 * math.pi,
  );

  /// True when [nodes] contain the imaginary unit anywhere, however deeply.
  ///
  /// Walked over the typed nodes rather than the compiled expression: the
  /// simplifier folds `0i` away and cancels `i - i`, so asking the [Expr]
  /// misses a unit the user plainly wrote.
  static bool usesImaginaryUnit(List<MathNode> nodes) {
    for (final MathNode n in nodes) {
      if (n is ComplexNode) return true;
      if (n is ComplexVariableNode) return true;
      if (n is LiteralNode && _textUsesImaginary(n.text)) return true;
      for (final List<MathNode> child in _childrenOf(n)) {
        if (usesImaginaryUnit(child)) return true;
      }
    }
    return false;
  }

  /// The combining low line that turns `z` into the complex variable.
  static const String complexVariableMark = '̲';

  /// `z̲`, as it is typed and displayed.
  static const String complexVariable = 'z̲';

  /// Words that contain an `i` without meaning the imaginary unit.
  ///
  /// Everything else made of letters is read as a product of single-letter
  /// variables, which is how the calculator itself reads it: `iy` is i times
  /// y, and `xiy` is x times i times y.
  static const Set<String> _wordsWithI = <String>{
    'sin',
    'sinh',
    'asin',
    'asinh',
    'ain',
    'min',
    'ans',
    'pi',
    'ceil',
    'sign',
    'li',
    'ln',
    'lim',
  };

  /// Whether [text] uses `i` as the imaginary unit.
  ///
  /// Read a word at a time rather than by looking either side of the letter.
  /// A lookahead for "not followed by a letter" rejected `x + iy` — the most
  /// ordinary way there is to write a complex number — because the unit there
  /// is followed by the variable it multiplies.
  static bool _textUsesImaginary(String text) {
    // z with a low line under it: the complex variable written as one symbol
    // rather than as x + iy. The engine never sees the mark — its tokenizer
    // drops combining characters, so this arrives as a plain `z`, which in a
    // complex line is already bound to the point of the plane. All the glyph
    // has to do is say that the line *is* complex.
    if (text.contains(complexVariableMark)) return true;
    for (final RegExpMatch m in RegExp(r'[A-Za-z]+').allMatches(text)) {
      final String word = m.group(0)!;
      if (_wordsWithI.contains(word.toLowerCase())) continue;
      if (word.contains('i')) return true;
    }
    return false;
  }

  /// The node lists hanging off [n], for walking a tree of unknown shape.
  static Iterable<List<MathNode>> _childrenOf(MathNode n) sync* {
    if (n is ComplexNode) yield n.content;
    if (n is ParenthesisNode) yield n.content;
    if (n is FractionNode) {
      yield n.numerator;
      yield n.denominator;
    }
    if (n is TrigNode) yield n.argument;
    if (n is ExponentNode) {
      yield n.base;
      yield n.power;
    }
    if (n is LogNode) {
      yield n.base;
      yield n.argument;
    }
    if (n is RootNode) {
      yield n.index;
      yield n.radicand;
    }
  }

  /// The variables a plot may bind.
  static const Set<String> plottableVariables = {'x', 'y', 'z'};

  /// The parameters a parametric plot is swept over.
  ///
  /// One of them traces a curve; both together sweep a surface. Unlike a
  /// coordinate they name no place — they are the input a position is
  /// computed from.
  static const Set<String> parameterVariables = {'u', 'v'};

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
    ({double min, double max}) thetaRange = defaultThetaRange,
  }) {
    // Read before anything simplifies: `0i` folds to nothing and `i - i`
    // cancels, so the compiled form can lose a unit the user plainly typed.
    final bool complex = usesImaginaryUnit(nodes);

    if (nodes.isEmpty) {
      return PlotExpression._(null, {}, 'Please enter a function');
    }

    // More than one comparison in a line is a chain, a < b < c, which holds
    // where every link does. It used to be split at the first comparison
    // only, and the converter dropped the second without a word: -1 < x < 2
    // came out as -1 < 2x, half a plane, with nothing to say it was wrong.
    final ({List<List<MathNode>> segments, List<String> ops}) split =
        _splitAllRelations(nodes);
    if (split.ops.length >= 2) {
      return _compileChain(split.segments, split.ops, system, thetaRange);
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
    // u and v are parameters, not places. A parametric line is swept by them
    // and returns a position, so it cannot also be a function of where it
    // already is — mixing them with a coordinate is a contradiction rather
    // than a mix of two conventions.
    final Set<String> parameters = free.intersection(parameterVariables);
    final Set<String> coords = free.intersection(allCoordinateSymbols);
    if (parameters.isNotEmpty && coords.isNotEmpty) {
      final List<String> both = <String>[...parameters, ...coords]..sort();
      return PlotExpression._(
        null,
        const <String>{},
        'Cannot mix ${both.join(' and ')}: u and v are parameters, '
        'not coordinates',
      );
    }
    if (parameters.isNotEmpty) {
      final Set<String> strays = free.difference(parameterVariables);
      if (strays.isNotEmpty) {
        final List<String> sorted = strays.toList()..sort();
        return PlotExpression._(
          null,
          const <String>{},
          'Cannot plot: unknown variable ${sorted.join(', ')}',
        );
      }
      if (_hasUnresolvedCalculus(compiled)) {
        return PlotExpression._(
          null,
          const <String>{},
          'Cannot plot: unresolved derivative or integral',
        );
      }
      return PlotExpression._(
        compiled,
        free,
        null,
        isLevelSet: isLevelSet,
        relation: relation?.$3 ?? PlotRelation.equal,
      );
    }

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
    // `i` is the imaginary unit, not something to sample over. It reaches the
    // compiler as a variable in some forms — `x+iy` splits into an `i` times a
    // `y` — and was then rejected as unknown before the complex path could
    // run, so the most ordinary way of writing a complex number would not
    // plot at all.
    if (complex) unknown.remove('i');
    if (unknown.isNotEmpty) {
      final List<String> sorted = unknown.toList()..sort();
      return PlotExpression._(
        null,
        const {},
        'Cannot plot: unknown variable ${sorted.join(', ')}',
      );
    }

    // A line with no '=' means what a bare expression means in its own system.
    // In Cartesian that is a height, y = f(x) or z = f(x, y). In polar it is
    // r = f(θ), the way every polar plotter reads it: sampled as a height
    // instead, 1 + cos(θ) came out as a step — f(0) right of the origin, f(π)
    // left of it — rather than a cardioid. In spherical, f(θ, φ) is the
    // surface ρ = f(θ, φ). Both are rewritten as the equation they stand for
    // and drawn as that equation is: r = f(θ) traced (see [isPolarCurve]),
    // ρ = f(θ, φ) marched like any other level set.
    //
    // Nothing with ρ in it has such a reading. ρ depends on z, so as a height
    // it would be z = f(ρ) with z on both sides — which used to be accepted,
    // and drawn by quietly sampling ρ at z = 0.
    if (!isLevelSet && !isVectorComponent && !complex) {
      if (system == CoordinateSystem.cylindrical &&
          free.contains('θ') &&
          !free.contains('r') &&
          !free.contains('z')) {
        return PlotExpression.compile(
          <MathNode>[LiteralNode(text: 'r='), ...nodes],
          system: system,
          thetaRange: thetaRange,
        );
      }
      if (system == CoordinateSystem.spherical) {
        if (free.contains('ρ')) {
          return PlotExpression._(
            null,
            const {},
            'Cannot plot ρ without an =: write ρ = … for a surface',
          );
        }
        return PlotExpression.compile(
          <MathNode>[LiteralNode(text: 'ρ='), ...nodes],
          system: system,
          thetaRange: thetaRange,
        );
      }
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
    // A complex line binds z to the point of the plane rather than sampling
    // over it, so the rule below — which is about z being an answer and not an
    // input — does not apply to it.
    final List<String> names = system.variables;
    if (!isVectorComponent &&
        !isLevelSet &&
        !complex &&
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
      isComplex: complex,
      sweptRadius:
          relation == null ||
                  relation.$3 != PlotRelation.equal ||
                  complex ||
                  isVectorComponent
              ? null
              : switch (system) {
                CoordinateSystem.cylindrical => _sweptRadiusOf(
                  relation.$1,
                  relation.$2,
                  'r',
                  const <String>{'θ'},
                ),
                CoordinateSystem.spherical => _sweptRadiusOf(
                  relation.$1,
                  relation.$2,
                  'ρ',
                  const <String>{'θ', 'φ'},
                ),
                CoordinateSystem.cartesian => null,
              },
      thetaRange: thetaRange,
    );
  }

  /// The f of `symbol = f(…)` or `f(…) = symbol`, when one side is [symbol]
  /// on its own and the other depends on nothing outside [angles]; null for
  /// any other equation.
  ///
  /// Only this form is traced by sweeping its angles (see [sweepsTheta]). It
  /// says where the curve or surface is for every angle, which a sampled
  /// equation cannot: every point has many polar addresses — (r, θ),
  /// (r, θ + 2π), (−r, θ + π) — and sampling asks about only one of them.
  static Expr? _sweptRadiusOf(
    List<MathNode> lhs,
    List<MathNode> rhs,
    String symbol,
    Set<String> angles,
  ) {
    bool alone(List<MathNode> side) =>
        side.length == 1 &&
        side.single is LiteralNode &&
        (side.single as LiteralNode).text.trim() == symbol;
    final List<MathNode>? radius = alone(lhs) ? rhs : (alone(rhs) ? lhs : null);
    if (radius == null) return null;
    final Expr compiled;
    try {
      compiled = MathNodeToExpr.convert(radius).simplify();
    } catch (_) {
      return null;
    }
    if (!compiled.freeVariables.every(angles.contains)) return null;
    if (_hasUnresolvedCalculus(compiled)) return null;
    return compiled;
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

  /// Every top-level comparison in [nodes], in order, with the stretches of
  /// expression between them. The operators are matched longest first at each
  /// point, so `<=` is one comparison and not `<` followed by `=`.
  static ({List<List<MathNode>> segments, List<String> ops}) _splitAllRelations(
    List<MathNode> nodes,
  ) {
    final List<List<MathNode>> segments = <List<MathNode>>[<MathNode>[]];
    final List<String> ops = <String>[];
    for (final MathNode node in nodes) {
      if (node is! LiteralNode) {
        segments.last.add(node);
        continue;
      }
      final String text = node.text;
      int start = 0;
      int i = 0;
      while (i < text.length) {
        String? hit;
        for (final String op in _relationOperators.keys) {
          if (text.startsWith(op, i) &&
              (hit == null || op.length > hit.length)) {
            hit = op;
          }
        }
        if (hit == null) {
          i++;
          continue;
        }
        if (i > start) {
          segments.last.add(LiteralNode(text: text.substring(start, i)));
        }
        ops.add(hit);
        segments.add(<MathNode>[]);
        i += hit.length;
        start = i;
      }
      if (start < text.length) {
        segments.last.add(LiteralNode(text: text.substring(start)));
      }
    }
    return (segments: segments, ops: ops);
  }

  /// A line of two or more comparisons, a < b < c: each neighbouring pair is
  /// compiled as an inequality of its own, and the line holds where all of
  /// them do.
  ///
  /// The region where every link holds is where the largest of them, each
  /// turned to read "below zero", is below zero — so the chain is one
  /// expression whose zero set is the region's whole boundary, and everything
  /// that shades, traces and marches a single inequality draws it unchanged.
  static PlotExpression _compileChain(
    List<List<MathNode>> segments,
    List<String> ops,
    CoordinateSystem system,
    ({double min, double max}) thetaRange,
  ) {
    final List<PlotRelation> relations = <PlotRelation>[
      for (final String op in ops) _relationOperators[op]!,
    ];
    if (relations.any(
      (PlotRelation r) => r == PlotRelation.equal || r == PlotRelation.notEqual,
    )) {
      return PlotExpression._(
        null,
        const <String>{},
        'A chain of comparisons can only use <, ≤, > and ≥',
      );
    }
    final List<({PlotExpression part, double sign})> chain =
        <({PlotExpression part, double sign})>[];
    final Set<String> variables = <String>{};
    CoordinateSystem? chosen;
    for (int i = 0; i < ops.length; i++) {
      final PlotExpression part = PlotExpression.compile(<MathNode>[
        ...segments[i],
        LiteralNode(text: ops[i]),
        ...segments[i + 1],
      ], system: system);
      if (!part.isValid) return part;
      if (part.isComplex || part.isParametric) {
        return PlotExpression._(
          null,
          const <String>{},
          'A chain of comparisons has to be in x, y and z',
        );
      }
      // A link with no coordinates in it, like the 0 < 1 of 0 < 1 < x, is
      // Cartesian by default and says nothing about the system.
      final bool placed = part.variables.isNotEmpty;
      if (placed && chosen != null && chosen != part.system) {
        return PlotExpression._(
          null,
          const <String>{},
          'Cannot mix coordinate systems in one chain',
        );
      }
      if (placed) chosen = part.system;
      variables.addAll(part.variables);
      final PlotRelation r = relations[i];
      final bool lessThan =
          r == PlotRelation.less || r == PlotRelation.lessEqual;
      chain.add((part: part, sign: lessThan ? 1.0 : -1.0));
    }
    // Strict if every link is; otherwise some of the boundary belongs to the
    // region and it is drawn as included.
    final bool strict = relations.every(
      (PlotRelation r) => r == PlotRelation.less || r == PlotRelation.greater,
    );
    return PlotExpression._chained(
      chain,
      variables,
      system: chosen ?? system,
      relation: strict ? PlotRelation.less : PlotRelation.lessEqual,
      thetaRange: thetaRange,
    );
  }

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
  /// The cell's lines, split on the newlines between them.
  ///
  /// Every line of a cell is its own plot on shared axes, so anything deciding
  /// what a cell *is* has to ask line by line. Asking of the whole node list
  /// reads three separate equations as one expression — which is how a cell
  /// mixing a curve and a sweep came out as a single malformed vector field
  /// and drew nothing at all.
  ///
  /// Empty lines are dropped: a trailing newline is not a plot.
  static List<List<MathNode>> splitLines(List<MathNode> nodes) {
    final List<List<MathNode>> lines = <List<MathNode>>[<MathNode>[]];
    for (final MathNode node in nodes) {
      if (node is NewlineNode) {
        lines.add(<MathNode>[]);
      } else {
        lines.last.add(node);
      }
    }
    lines.removeWhere((List<MathNode> line) => line.isEmpty);
    return lines;
  }

  static List<PlotExpression> compileAll(
    List<MathNode> nodes, {
    CoordinateSystem system = CoordinateSystem.cartesian,
    ({double min, double max}) thetaRange = defaultThetaRange,
  }) {
    final List<List<MathNode>> lines = splitLines(nodes);

    final List<PlotExpression> out = <PlotExpression>[];
    for (final List<MathNode> line in lines) {
      if (line.isEmpty) continue;
      // Stamped here, where the line's position in the cell is still known.
      out.add(
        PlotExpression.compile(line, system: system, thetaRange: thetaRange)
          ..seriesIndex = out.length,
      );
    }
    if (out.isEmpty) {
      out.add(
        PlotExpression.compile(nodes, system: system, thetaRange: thetaRange),
      );
    }
    return out;
  }

  /// Whether this expression compiled successfully.
  bool get isValid => _compiled != null || _chain != null;

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

  /// True when this line is swept by a parameter rather than sampled over
  /// space.
  bool get isParametric => variables.any(parameterVariables.contains);

  /// True when both parameters appear, so this sweeps a surface rather than
  /// tracing a curve.
  bool get isParametricSurface =>
      variables.contains('u') && variables.contains('v');

  /// Sample a parametric line at the given parameter values.
  double evaluateAt({double u = 0, double v = 0}) {
    final double value = _rawEvaluateAt(u, v);
    if (!value.isNaN) return value;
    return _limitOf(
      (double e) =>
          _rawEvaluateAt(u + e * (1 + u.abs()), v + e * (1 + v.abs())),
    );
  }

  double _rawEvaluateAt(double u, double v) {
    final Expr? c = _compiled;
    if (c == null) return double.nan;
    _bindings['u'] = u;
    _bindings['v'] = v;
    try {
      return c.evalWith(_bindings);
    } catch (_) {
      return double.nan;
    }
  }

  /// Sample the expression at a point in **Cartesian** space. Returns NaN when
  /// invalid, which painters already treat as a gap in the curve.
  ///
  /// Everything that draws — the curve tracer, the height-surface sampler,
  /// marching squares and marching tetrahedra — walks a Cartesian lattice. An
  /// expression written in another system is handled by converting the sample
  /// point rather than by rewriting the expression, so all of that machinery
  /// works unchanged: ρ = 1 comes out as the unit sphere because at every
  /// sampled (x, y, z) the value of ρ is known, and r < 1 + cos(θ) shades a
  /// cardioid through the same code that shades any other region. Only an
  /// explicit r = f(θ) is drawn another way (see [isPolarCurve]).
  ///
  /// A point has more than one polar address: (r, θ + 2π) is the same point
  /// as (r, θ), and so is (−r, θ + π). A sampled polar equation or inequality
  /// is read at every one of them whose θ lies in [thetaRange] (see
  /// [_valueAtEveryAddress]), so it covers the same turns a traced curve
  /// does. Reading only the address with r ≥ 0 and θ in one turn is what
  /// left `2r = θ` with one arm while `r = θ` had two.
  double evaluate(double x, [double y = 0, double z = 0]) {
    final (double a, double b, double d) = toCoordinates(system, x, y, z);
    if (_readsEveryAddress) return _valueAtEveryAddress(a, b, d);
    return _valueAt(a, b, d);
  }

  /// This line's value at a point given in its own coordinates — (x, y, z),
  /// (r, θ, z) or (ρ, θ, φ) — rather than at a place.
  ///
  /// Where it comes out undefined, the limit is tried (see [_limitOf]).
  double _valueAt(double a, double b, double d) {
    final double v = _rawValueAt(a, b, d);
    if (!v.isNaN) return v;
    return _limitOf(
      (double e) => _rawValueAt(
        a + e * (1 + a.abs()),
        b + e * (1 + b.abs()),
        d + e * (1 + d.abs()),
      ),
    );
  }

  /// What a line comes to at a point where it is 0/0 but carries on either
  /// side — sin(3θ)/(3θ) at θ = 0, sin(x)/x at x = 0 — or NaN where it does
  /// not.
  ///
  /// [near] reads the line a little way off the point, by the signed amount
  /// it is given. Such points are isolated, but a lattice lands on them
  /// exactly whenever the window is symmetric: the lobe of r² = sin(3θ)/(3θ)
  /// lost the cells round its tip, which stood as a slit in its wall, and a
  /// traced curve broke at θ = 0. So the line is read a hair either side, and
  /// where the two agree they are the value. Where they do not — x/|x| at 0 —
  /// or either is undefined too — √x for x < 0 — it stays undefined.
  static double _limitOf(double Function(double e) near) {
    const double hair = 1e-6;
    final double above = near(hair);
    if (!above.isFinite) return double.nan;
    final double below = near(-hair);
    if (!below.isFinite) return double.nan;
    if ((above - below).abs() > 1e-3 * (1 + above.abs() + below.abs())) {
      return double.nan;
    }
    return (above + below) / 2;
  }

  double _rawValueAt(double a, double b, double d) {
    final List<({PlotExpression part, double sign})>? chain = _chain;
    if (chain != null) {
      double largest = double.negativeInfinity;
      for (final ({PlotExpression part, double sign}) link in chain) {
        final double v = link.sign * link.part._valueAt(a, b, d);
        if (!v.isFinite) return double.nan;
        if (v > largest) largest = v;
      }
      return largest;
    }
    final Expr? c = _compiled;
    if (c == null) return double.nan;
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

  /// Whether this line is read at every polar address of a point (see
  /// [evaluate]): a sampled equation or inequality in polar, cylindrical or
  /// spherical coordinates.
  ///
  /// Not a traced line, which places its points itself, nor a height, which
  /// has one value at each point of the plane and so reads θ in its first
  /// turn only.
  late final bool _readsEveryAddress =
      isValid &&
      isLevelSet &&
      system != CoordinateSystem.cartesian &&
      _sweptRadius == null &&
      !_isComplex &&
      !isParametric;

  /// Whether the θ range applies to this line: a traced one, or a sampled
  /// one read at every address. The θ control is offered for these.
  bool get followsThetaRange => sweepsTheta || _readsEveryAddress;

  /// Which of a point's addresses can change this line's value, found once by
  /// trying a few points rather than assumed.
  ///
  /// [turns]: whether θ and θ + 2π read differently, so every turn in the
  /// range has to be read. Most lines repeat every turn, and reading them
  /// once is all it takes. [negative]: whether (−r, θ + π) reads differently
  /// from (r, θ), so an equation has to be read there as well — r² = cos 2θ
  /// does not care, 2r = θ does.
  late final ({bool turns, bool negative}) _addressesThatMatter =
      _findAddressesThatMatter();

  ({bool turns, bool negative}) _findAddressesThatMatter() {
    bool same(double p, double q) =>
        p == q || (p.isNaN && q.isNaN) || (p - q).abs() <= 1e-9 * (1 + p.abs());
    final bool spherical = system == CoordinateSystem.spherical;
    final bool dependsOnTheta = variables.contains('θ');
    bool turns = false;
    bool negative = false;
    for (final double a in const <double>[0.37, 1.3, 2.9]) {
      for (final double t in const <double>[0.23, 1.9, 3.7, 5.1]) {
        for (final double d
            in spherical
                ? const <double>[0.45, 1.7, 2.6]
                : const <double>[-0.6, 0.45, 1.7]) {
          final double here = _valueAt(a, t, d);
          if (dependsOnTheta && !turns) {
            turns = !same(here, _valueAt(a, t + 2 * math.pi, d));
          }
          if (relation == PlotRelation.equal && !negative) {
            negative =
                !same(
                  here,
                  _valueAt(-a, t + math.pi, spherical ? math.pi - d : d),
                );
          }
        }
      }
    }
    return (turns: turns, negative: negative);
  }

  /// The addresses a sampled polar equation is drawn from, one at a time.
  ///
  /// Reading every address at once and keeping the value nearest zero (see
  /// [_valueAtEveryAddress]) finds every curve, but where two of them cross —
  /// the two arms of 2r = θ meet on the y axis — the value switches from one
  /// to the other in a leap, and the drawing turns those leaps down: each
  /// crossing came out with a gap a few pixels wide. Traced address by
  /// address, each is a curve of its own and nothing switches.
  ///
  /// An address is a [sign] for the radius — (r, θ) or (−r, θ + π) — and a
  /// [turn], how many times 2π is added to θ. Empty when the line is read at
  /// one address only, and then [evaluate] is all there is to it.
  late final List<({int sign, int turn})> equationSheets = _equationSheets();

  List<({int sign, int turn})> _equationSheets() {
    if (!_readsEveryAddress || relation != PlotRelation.equal) {
      return const <({int sign, int turn})>[];
    }
    final ({bool turns, bool negative}) matter = _addressesThatMatter;
    if (!matter.turns && !matter.negative) {
      return const <({int sign, int turn})>[];
    }
    final ({double min, double max}) range = sweptThetaRange;
    const double turn = 2 * math.pi;
    return <({int sign, int turn})>[
      for (final int sign
          in matter.negative ? const <int>[1, -1] : const <int>[1])
        if (!matter.turns)
          (sign: sign, turn: 0)
        else
          // A turn is read on the near side of the cut and continued on the
          // far side (see [evaluateOnSheet]), so the first turn's far side
          // belongs to the turn before it, and the last turn's far side is
          // already read by the one before that.
          for (
            int k = ((range.min - (sign < 0 ? math.pi : 0)) / turn).ceil() - 1;
            k <= ((range.max - (sign < 0 ? math.pi : 0)) / turn).ceil() - 1;
            k++
          )
            (sign: sign, turn: k),
    ];
  }

  /// This line at the Cartesian point (x, y, z), read at one address (see
  /// [equationSheets]).
  ///
  /// θ is measured in its first turn, so it comes round from 2π to 0 across
  /// the half-plane y = 0, x > 0, and on one address the value leaps there.
  /// [continued] reads the next turn instead, which is what the address
  /// becomes on the far side: a cell lying across that half-plane reads its
  /// near corners plainly and its far ones continued, and the curve runs on
  /// through it unbroken. NaN where the address's θ is outside the range.
  double evaluateOnSheet(
    ({int sign, int turn}) sheet,
    double x,
    double y,
    double z, {
    bool continued = false,
  }) {
    final (double a, double b, double d) = toCoordinates(system, x, y, z);
    final ({double min, double max}) range = sweptThetaRange;
    const double turn = 2 * math.pi;
    final bool flipped = sheet.sign < 0;
    final double start = b + (flipped ? math.pi : 0);
    double theta;
    if (_addressesThatMatter.turns) {
      theta = start + turn * (sheet.turn + (continued ? 1 : 0));
      if (theta < range.min || theta > range.max) return double.nan;
    } else {
      // Every turn reads alike, so any one in the range will do.
      final int first = ((range.min - start) / turn).ceil();
      theta = start + turn * first;
      if (theta > range.max) return double.nan;
    }
    return _valueAt(
      flipped ? -a : a,
      theta,
      flipped && system == CoordinateSystem.spherical ? math.pi - d : d,
    );
  }

  /// This line read at every address of the point whose own coordinates are
  /// (a, b, d), with θ = b in its first turn.
  ///
  /// The addresses are combined the way the relation asks:
  ///
  /// - An inequality holds where it holds at *some* address — the least of
  ///   the values for `<`, the greatest for `>` — and only at addresses with
  ///   r ≥ 0. With a negative radius, `r < 1` would hold everywhere; it is the
  ///   rule Desmos keeps for the same reason.
  /// - An equation is on its curve where it is zero at some address, so the
  ///   value nearest zero is the one returned. Where the nearest one changes
  ///   from one address to another the value can leap from one sign to the
  ///   other without passing zero, and the drawing code already turns such
  ///   leaps down (see `crossesZero` in level_set.dart).
  ///
  /// NaN where no address of the point has θ in the range: a line confined
  /// to part of a turn is not drawn in the rest of it.
  double _valueAtEveryAddress(double a, double b, double d) {
    final ({double min, double max}) range = sweptThetaRange;
    const double turn = 2 * math.pi;
    final ({bool turns, bool negative}) matter = _addressesThatMatter;
    double? chosen;

    void consider(double v) {
      if (!v.isFinite) return;
      final double? c = chosen;
      if (c == null ||
          switch (relation) {
            PlotRelation.equal => v.abs() < c.abs(),
            PlotRelation.notEqual => v.abs() > c.abs(),
            PlotRelation.less || PlotRelation.lessEqual => v < c,
            PlotRelation.greater || PlotRelation.greaterEqual => v > c,
          }) {
        chosen = v;
      }
    }

    // Every θ + 2πk in the range; once only when the turns all read alike.
    void around(double theta, double Function(double) at) {
      final int first = ((range.min - theta) / turn).ceil();
      final int last = ((range.max - theta) / turn).floor();
      if (first > last) return;
      if (!matter.turns) {
        consider(at(theta + turn * first));
        return;
      }
      for (int k = first; k <= last; k++) {
        consider(at(theta + turn * k));
      }
    }

    around(b, (double t) => _valueAt(a, t, d));
    if (matter.negative) {
      final double far = system == CoordinateSystem.spherical ? math.pi - d : d;
      around(b + math.pi, (double t) => _valueAt(-a, t, far));
    }
    return chosen ?? double.nan;
  }

  /// True when this line is a function of a complex variable.
  ///
  /// Decided by the imaginary unit appearing anywhere in it. A line with an
  /// `i` in it cannot be sampled as a real function — [evaluate] answers NaN
  /// for the unit — so there is nothing else it could sensibly be.
  ///
  /// Read from what was typed rather than from the compiled form. The
  /// simplifier folds `0i` to nothing and cancels `i - i`, so by the time an
  /// expression is an [Expr] the unit may be gone even though the user put it
  /// there — which made `z + 0i`, the obvious way to ask for the identity, a
  /// real plot.
  ///
  /// The cost of reading it this way at all is that `f(z) = z²` is not
  /// recognised, having no `i` in it anywhere.
  bool get isComplex => _isComplex;

  /// This line at the point `x + iy` of the complex plane.
  ///
  /// The point of the plane is bound three ways, because there are three
  /// ordinary ways to write it: `z` for the whole complex number, and `x` and
  /// `y` for its real and imaginary parts, so `z`, `x+iy` and `x+yi` all mean
  /// the identity.
  ///
  /// This `z` is the complex variable and not the third coordinate. A complex
  /// line has no third coordinate — the plane is its whole domain.
  Complex evaluateComplex(double x, double y) {
    final Expr? c = _compiled;
    if (c == null) return const Complex(double.nan, double.nan);
    _complexBindings['z'] = Complex(x, y);
    _complexBindings['x'] = Complex(x, 0);
    _complexBindings['y'] = Complex(y, 0);
    // Bound rather than special-cased, because the compiler hands `i` over as
    // a variable when it sits against another symbol.
    _complexBindings['i'] = const Complex(0, 1);
    try {
      return c.evalComplexWith(_complexBindings);
    } catch (_) {
      return const Complex(double.nan, double.nan);
    }
  }

  /// Scratch space for [evaluateComplex], reused for the same reason
  /// [_bindings] is: domain colouring asks for a value per pixel.
  final Map<String, Complex> _complexBindings = <String, Complex>{};

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

  /// Whether this line is traced by sweeping its angles rather than sampled:
  /// an explicit polar curve `r = f(θ)` ([isPolarCurve]) or spherical surface
  /// `ρ = f(θ, φ)` ([isSphericalSurface]).
  ///
  /// θ is swept over [thetaRange] — φ, for a surface, from 0 to π — and each
  /// value placed where it says, the way a parametric curve is. Sampling the
  /// equation finds only the points with r ≥ 0 and θ in one turn, so
  /// r = cos 2θ came out with two of its four petals, the limaçon
  /// r = 1 + 2 cos θ without its inner loop, and anything that does not
  /// repeat every turn with one turn of itself. [evaluate] still answers
  /// `r − f(θ)` for anything that asks.
  bool get sweepsTheta => _sweptRadius != null;

  /// Whether this line is an explicit polar curve, `r = f(θ)`.
  bool get isPolarCurve =>
      _sweptRadius != null && system == CoordinateSystem.cylindrical;

  /// Whether this line is an explicit spherical surface, `ρ = f(θ, φ)`.
  bool get isSphericalSurface =>
      _sweptRadius != null && system == CoordinateSystem.spherical;

  /// What θ is actually swept over: [thetaRange], low end first, cut to a
  /// single turn when f repeats every turn.
  ///
  /// Over the default two turns r = cos 2θ would be drawn twice, on top of
  /// itself — twice the work for the same picture, and in 3D two coincident
  /// walls. Whether f repeats is checked, not assumed: sampled at points
  /// spread over the range, against the same points a turn on.
  late final ({double min, double max}) sweptThetaRange = _sweptThetaRange();

  ({double min, double max}) _sweptThetaRange() {
    final double lo = math.min(thetaRange.min, thetaRange.max);
    final double hi = math.max(thetaRange.min, thetaRange.max);
    const double turn = 2 * math.pi;
    if (_sweptRadius == null || hi - lo <= turn * (1 + 1e-12)) {
      return (min: lo, max: hi);
    }
    const int probes = 29;
    for (int i = 0; i < probes; i++) {
      // Off the round fractions of a turn, where special values cluster.
      final double theta = lo + (hi - lo - turn) * (i + 0.37) / probes;
      for (final double phi in const <double>[0.31, 1.2, 2.47]) {
        final double here = _radiusAt(theta, phi);
        final double later = _radiusAt(theta + turn, phi);
        if (here.isFinite != later.isFinite) return (min: lo, max: hi);
        if (here.isFinite && (here - later).abs() > 1e-9 * (1 + here.abs())) {
          return (min: lo, max: hi);
        }
        if (isPolarCurve) break; // f does not depend on φ
      }
    }
    return (min: lo, max: lo + turn);
  }

  /// f at the given angles, NaN where it is undefined.
  double _radiusAt(double theta, double phi) {
    final double r = _rawRadiusAt(theta, phi);
    if (!r.isNaN) return r;
    return _limitOf(
      (double e) => _rawRadiusAt(
        theta + e * (1 + theta.abs()),
        phi + e * (1 + phi.abs()),
      ),
    );
  }

  double _rawRadiusAt(double theta, double phi) {
    final Expr? radius = _sweptRadius;
    if (radius == null) return double.nan;
    _bindings['θ'] = theta;
    _bindings['φ'] = phi;
    try {
      return radius.evalWith(_bindings);
    } catch (_) {
      return double.nan;
    }
  }

  /// The point of a polar curve at [theta], or null where f is undefined
  /// there or this is not a polar curve.
  ///
  /// A negative f is not a gap: the point lies on the opposite side of the
  /// origin, which is where the missing petals and loops were.
  ({double x, double y})? polarPoint(double theta) {
    if (!isPolarCurve) return null;
    final double r = _radiusAt(theta, 0);
    if (!r.isFinite) return null;
    return (x: r * math.cos(theta), y: r * math.sin(theta));
  }

  /// The point of a spherical surface at [theta] around the z axis and [phi]
  /// down from it, or null where f is undefined there or this is not a
  /// spherical surface.
  ///
  /// As for a polar curve, a negative f is a point on the far side of the
  /// origin — through it, along the same line.
  ({double x, double y, double z})? sphericalPoint(double theta, double phi) {
    if (!isSphericalSurface) return null;
    final double rho = _radiusAt(theta, phi);
    if (!rho.isFinite) return null;
    final double across = rho * math.sin(phi);
    return (
      x: across * math.cos(theta),
      y: across * math.sin(theta),
      z: rho * math.cos(phi),
    );
  }

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
