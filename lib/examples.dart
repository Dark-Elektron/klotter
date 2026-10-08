import 'math_renderer/math_nodes.dart';

/// A plot to start from: its name, its rows as they read, what it shows, and
/// the rows themselves.
///
/// Offered on the help page, and three of them on an empty plot. Opening one
/// fills the plot on screen when nothing is typed on it, or a new plot after
/// it when something is, so nothing typed is ever written over.
class PlotExample {
  const PlotExample({
    required this.title,
    required this.reads,
    required this.shows,
    required List<List<MathNode>> Function() rows,
    this.in3D = false,
  }) : _rows = rows;

  /// What it is called on its card.
  final String title;

  /// Its rows as they read, one string to a row.
  final List<String> reads;

  /// One line on what it shows, or what to try with it.
  final String shows;

  /// Whether it opens in 3D. A plot keeps the dimension it was left in, and a
  /// surface opened into a plot left in 2D is a heat map, which is not what
  /// a saddle or a sphere is meant to look like.
  final bool in3D;

  final List<List<MathNode>> Function() _rows;

  /// The rows, built new each time: two plots opened from the same example
  /// must not share a node, or typing in one would edit the other.
  List<List<MathNode>> rows() => _rows();
}

/// A node list as the editor keeps one: text at both ends and between any two
/// structures, so the caret has somewhere to stand on either side of each.
List<MathNode> _nodes(List<Object> parts) {
  final List<MathNode> out = <MathNode>[];
  for (final Object part in parts) {
    if (part is String) {
      if (out.isNotEmpty && out.last is LiteralNode) {
        (out.last as LiteralNode).text += part;
      } else {
        out.add(LiteralNode(text: part));
      }
    } else if (part is MathNode) {
      if (out.isEmpty || out.last is! LiteralNode) out.add(LiteralNode());
      out.add(part);
    }
  }
  if (out.isEmpty || out.last is! LiteralNode) out.add(LiteralNode());
  return out;
}

MathNode _squared(String base) =>
    ExponentNode(base: _nodes(<Object>[base]), power: _nodes(<Object>['2']));

MathNode _fn(String name, List<Object> argument) =>
    TrigNode(function: name, argument: _nodes(argument));

const String _minus = '−';

/// Every example, in the order the help page lists them: the kinds of plot
/// first, a variable to tune last.
final List<PlotExample> plotExamples = <PlotExample>[
  PlotExample(
    title: 'Wave',
    reads: const <String>['sin(x)'],
    shows: 'A curve: anything in x',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            _fn('sin', <Object>['x']),
          ]),
        ],
  ),
  PlotExample(
    title: 'Circle',
    reads: const <String>['x² + y² = 1'],
    shows: 'An equation draws where both sides agree',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[_squared('x'), '+', _squared('y'), '=1']),
        ],
  ),
  PlotExample(
    title: 'Ring',
    reads: const <String>['1 ≤ x² + y² ≤ 4'],
    shows: 'Inequalities shade a region',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>['1≤', _squared('x'), '+', _squared('y'), '≤4']),
        ],
  ),
  PlotExample(
    title: 'Cardioid',
    reads: const <String>['r = 1 + cos(θ)'],
    shows: 'Polar: r and θ',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            'r=1+',
            _fn('cos', <Object>['θ']),
          ]),
        ],
  ),
  PlotExample(
    title: 'Saddle',
    reads: const <String>['x² − y²'],
    shows: 'A surface: x and y together, in 3D',
    in3D: true,
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[_squared('x'), _minus, _squared('y')]),
        ],
  ),
  PlotExample(
    title: 'Sphere',
    reads: const <String>['x² + y² + z² = 1'],
    shows: 'An equation in x, y and z is a surface',
    in3D: true,
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            _squared('x'),
            '+',
            _squared('y'),
            '+',
            _squared('z'),
            '=1',
          ]),
        ],
  ),
  PlotExample(
    title: 'Swirl',
    reads: const <String>['−y x̂ + x ŷ'],
    shows: 'Unit vectors make a vector field',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            '${_minus}y',
            UnitVectorNode('x'),
            '+x',
            UnitVectorNode('y'),
          ]),
        ],
  ),
  PlotExample(
    title: 'Helix',
    reads: const <String>['cos(u) x̂ + sin(u) ŷ + 0.2u ẑ'],
    shows: 'u sweeps out a curve',
    in3D: true,
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            _fn('cos', <Object>['u']),
            UnitVectorNode('x'),
            '+',
            _fn('sin', <Object>['u']),
            UnitVectorNode('y'),
            '+0.2u',
            UnitVectorNode('z'),
          ]),
        ],
  ),
  PlotExample(
    title: 'Complex square',
    reads: const <String>['z̲²'],
    shows: 'A function of a complex number, in colour',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>[
            ExponentNode(
              base: _nodes(<Object>[ComplexVariableNode()]),
              power: _nodes(<Object>['2']),
            ),
          ]),
        ],
  ),
  PlotExample(
    title: 'Tune a wave',
    reads: const <String>['k = 2', 'sin(kx)'],
    shows: 'Long-press the 2 and drag it',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>['k=2']),
          _nodes(<Object>[
            _fn('sin', <Object>['kx']),
          ]),
        ],
  ),
  PlotExample(
    title: 'Line',
    reads: const <String>['m = 2', 'b = 1', 'mx + b'],
    shows: 'Tune m and b to move it',
    rows:
        () => <List<MathNode>>[
          _nodes(<Object>['m=2']),
          _nodes(<Object>['b=1']),
          _nodes(<Object>['mx+b']),
        ],
  ),
];

/// The three an empty plot offers: a value to tune, an equation, a surface.
List<PlotExample> get startingExamples => <PlotExample>[
  plotExamples.firstWhere((PlotExample e) => e.title == 'Tune a wave'),
  plotExamples.firstWhere((PlotExample e) => e.title == 'Circle'),
  plotExamples.firstWhere((PlotExample e) => e.title == 'Saddle'),
];
