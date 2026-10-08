part of 'plot_expression.dart';

/// The values a plot's rows give its letters: a row `k = 2` gives k the value
/// 2 in every other row of the plot.
///
/// The letters are the variable key's — a, b, k, p, m and n — and only they
/// can be given one. x, y and z say where a curve is rather than what shapes
/// it, u and v are what a sweep runs over, and e, i and π already mean
/// something.
///
/// A row that gives a value is not drawn. Its number tunes like any other —
/// long-press it and drag — and every curve that uses the letter moves with
/// it, which is what a letter is worth a row of its own for.
class PlotDefinitions {
  PlotDefinitions._(this.values, this.rows, this.errors);

  /// A plot that gives none of its letters a value.
  static final PlotDefinitions none = PlotDefinitions._(
    const <String, Expr>{},
    const <int, String>{},
    const <int, String>{},
  );

  /// The letters a row can give a value to, as the variable key offers them.
  static const List<String> names = <String>['a', 'b', 'k', 'p', 'm', 'n'];

  /// Each letter that has a value, and the value.
  final Map<String, Expr> values;

  /// The rows that give a letter a value, by row number, with the letter.
  ///
  /// Every row shaped like one is here, including those that could not be
  /// read (see [errors]): none of them is a curve to draw.
  final Map<int, String> rows;

  /// Why a row giving a value could not be read, by row number.
  final Map<int, String> errors;

  /// What a row is compiled with: each letter that has a value bound to it,
  /// and the rest of [names] bound to themselves.
  ///
  /// Binding the rest to themselves changes nothing about what they mean — k
  /// without a value is still k, and still says it has none — but it tells
  /// the engine they are letters. A word with a bound letter in it is read as
  /// its letters multiplied, so `pi` typed as p and then i is p times i, not
  /// π, and `max` is m times a times x.
  late final Map<String, Expr> bindings = _bindingsOf(values);

  static Map<String, Expr> _bindingsOf(Map<String, Expr> values) =>
      <String, Expr>{
        for (final String name in names) name: values[name] ?? VarExpr(name),
      };

  /// The letter [line] gives a value to, or null when it gives none.
  ///
  /// Read off the line's shape alone — one of [names] on its own, an `=`,
  /// then anything — so the row panel can tell a value from a curve without
  /// compiling either. `k =` with nothing after it is one too, waiting for
  /// its value: drawn as a relation instead it would say both sides of a
  /// comparison are needed, which is not what is missing.
  static String? nameDefinedBy(List<MathNode> line) {
    final ({List<List<MathNode>> segments, List<String> ops}) split =
        PlotExpression._splitAllRelations(line);
    if (split.ops.length != 1 || split.ops.single != '=') return null;
    final List<MathNode> lhs = split.segments.first;
    if (!lhs.every((MathNode n) => n is LiteralNode)) return null;
    final String name =
        lhs.map((MathNode n) => (n as LiteralNode).text).join().trim();
    return names.contains(name) ? name : null;
  }

  /// The values given among [lines], each line one row of the plot.
  ///
  /// Worked out in whatever order they allow rather than top to bottom, so
  /// `b = 2a` can sit above the row giving a its value.
  static PlotDefinitions read(List<List<MathNode>> lines) {
    final Map<int, String> rows = <int, String>{};
    final Map<int, String> errors = <int, String>{};
    final Map<String, int> firstRow = <String, int>{};
    final Map<int, List<MathNode>> given = <int, List<MathNode>>{};
    for (int row = 0; row < lines.length; row++) {
      final String? name = nameDefinedBy(lines[row]);
      if (name == null) continue;
      rows[row] = name;
      final int? earlier = firstRow[name];
      if (earlier != null) {
        errors[row] = '$name already has a value, in row ${earlier + 1}';
        continue;
      }
      firstRow[name] = row;
      given[row] = PlotExpression._splitAllRelations(lines[row]).segments.last;
    }
    if (rows.isEmpty) return none;

    final Map<String, Expr> values = <String, Expr>{};
    final Map<int, String> waiting = <int, String>{
      for (final int row in given.keys) row: rows[row]!,
    };
    bool moved = true;
    while (waiting.isNotEmpty && moved) {
      moved = false;
      for (final int row in waiting.keys.toList()) {
        final String name = waiting[row]!;
        final ({Expr? value, String? error, bool waits}) read = _readValue(
          name,
          given[row]!,
          values,
          waiting.values.toSet(),
        );
        if (read.waits) continue;
        waiting.remove(row);
        moved = true;
        if (read.value != null) values[name] = read.value!;
        if (read.error != null) errors[row] = read.error!;
      }
    }
    // Whatever is still waiting is waiting on itself, through one row or
    // through several.
    waiting.forEach((int row, String name) {
      errors[row] = '$name cannot be worked out: its value depends on itself';
    });
    return PlotDefinitions._(values, rows, errors);
  }

  /// The value [source] gives [name], or why it gives none, or that it
  /// needs a letter in [waiting] first.
  static ({Expr? value, String? error, bool waits}) _readValue(
    String name,
    List<MathNode> source,
    Map<String, Expr> values,
    Set<String> waiting,
  ) {
    ({Expr? value, String? error, bool waits}) fails(String why) => (
      value: null,
      error: why,
      waits: false,
    );
    if (PlotExpression._isBlank(source)) {
      return fails('Give $name a value, such as $name = 1');
    }
    if (PlotExpression.usesImaginaryUnit(source)) {
      return fails('$name has to be a real number');
    }
    final Expr value;
    try {
      value =
          MathNodeToExpr.convert(
            source,
            varBindings: _bindingsOf(values),
          ).simplify();
    } catch (_) {
      return fails('Invalid value for $name');
    }
    final Set<String> free = value.freeVariables;
    if (free.any(waiting.contains)) {
      return (value: null, error: null, waits: true);
    }
    if (free.isNotEmpty) {
      final List<String> sorted = free.toList()..sort();
      final List<String> letters = sorted.where(names.contains).toList();
      if (letters.isNotEmpty) {
        return fails(
          '$name uses ${_listed(letters)}, which '
          '${letters.length == 1 ? 'has' : 'have'} no value',
        );
      }
      return fails(
        '$name has to be a number: it cannot depend on ${_listed(sorted)}',
      );
    }
    final double number;
    try {
      number = value.toDouble();
    } catch (_) {
      return fails('$name has to be a number');
    }
    if (!number.isFinite) return fails('$name has no finite value');
    return (value: value, error: null, waits: false);
  }

  /// Why a line using [unknown] cannot be drawn.
  ///
  /// A letter from the variable key that has no value is not a typing
  /// mistake: it is waiting for a row to give it one, so the message says
  /// where the value goes rather than that the letter is unknown.
  String unknownVariables(Set<String> unknown) {
    final List<String> sorted = unknown.toList()..sort();
    if (!sorted.every(names.contains)) {
      return 'Cannot plot: unknown variable ${sorted.join(', ')}';
    }
    final bool one = sorted.length == 1;
    final String has = one ? 'has' : 'have';
    final List<String> rowless =
        sorted.where((String name) => !rows.containsValue(name)).toList();
    // Each has a row giving it a value that cannot be read yet, and that row
    // says why.
    if (rowless.isEmpty) {
      return 'Cannot plot: ${_listed(sorted)} $has no value until '
          '${one ? 'the row giving it is' : 'the rows giving them are'} fixed';
    }
    return 'Cannot plot: ${_listed(sorted)} $has no value. '
        'Add a row such as ${rowless.first} = 1';
  }

  /// The values a row reads, written out for its compile key, from the row
  /// as `MathExpressionSerializer.serializeToJson` wrote it.
  ///
  /// A row compiles again when one of these moves and only then, so tuning k
  /// redraws the curves that use k and leaves every other curve — and the
  /// geometry already worked out for it — alone. Read from the saved form
  /// because every letter typed is in a literal's text there however deeply
  /// it sits, in a sum's body or an integral's bound, and every kind of node
  /// has to be written out to be saved at all. A letter whose row cannot be
  /// read yet is written as `?`, so its message changes when the row does.
  String valuesReadBy(String serializedRow) {
    if (rows.isEmpty) return '';
    final Set<String> letters = <String>{
      for (final RegExpMatch m in _literalText.allMatches(serializedRow))
        ...m.group(1)!.split(''),
    };
    return <String>[
      for (final String name in names)
        if (letters.contains(name))
          if (values[name] case final Expr value)
            '$name=${value.toDouble()}'
          else if (rows.containsValue(name))
            '$name=?',
    ].join(',');
  }

  static final RegExp _literalText = RegExp(r'"text":"((?:[^"\\]|\\.)*)"');

  static String _listed(List<String> letters) => switch (letters.length) {
    1 => letters.single,
    _ =>
      '${letters.sublist(0, letters.length - 1).join(', ')} '
          'and ${letters.last}',
  };
}
