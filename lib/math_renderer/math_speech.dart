import 'math_nodes.dart';

/// What a screen reader says for an expression.
///
/// The editor draws an expression glyph by glyph, so what a screen reader
/// finds there on its own is a scatter of characters: a raised 2 with no word
/// for what it does, a fraction bar that is not text at all. This reads the
/// node tree instead and says the expression as it would be read aloud —
/// x² + y² = 1 is "x squared plus y squared equals 1".
///
/// Nothing is recorded or played. TalkBack speaks these words in its own
/// voice, as it speaks every other label in the app.
///
/// Anything whose extent the words alone would leave open — a fraction, a
/// power, a root or a sum with more than one term in it — is closed with an
/// "end", so √(x + 1) and √x + 1 do not sound the same.
class MathSpeech {
  const MathSpeech._();

  /// [nodes] in words, or "empty" when nothing is typed.
  static String describe(List<MathNode> nodes) {
    final String said = _list(nodes);
    return said.isEmpty ? 'empty' : said;
  }

  static String _list(List<MathNode> nodes) =>
      _join(<String>[for (final MathNode n in nodes) _node(n)]);

  static String _join(Iterable<String> parts) => parts
      .where((String p) => p.isNotEmpty)
      .join(' ')
      .replaceAll(RegExp(' {2,}'), ' ')
      .replaceAll(' ,', ',')
      .trim();

  /// One word, which needs nothing to say where it ends.
  static bool _simple(String said) => !said.contains(' ');

  static String _node(MathNode n) {
    if (n is LiteralNode) return _text(n.text);
    if (n is FractionNode) {
      final String top = _list(n.numerator);
      final String bottom = _list(n.denominator);
      if (_simple(top) && _simple(bottom)) return '$top over $bottom';
      return 'fraction $top, over $bottom, end fraction';
    }
    if (n is ExponentNode) {
      final String base = _list(n.base);
      final String power = _list(n.power);
      if (power == '2') return '$base squared';
      if (power == '3') return '$base cubed';
      if (_simple(power)) return '$base to the power $power';
      return '$base to the power $power, end power';
    }
    if (n is TrigNode) {
      final String name = _functions[n.function] ?? n.function;
      final String argument = _list(n.argument);
      // The brackets it is drawn with, when there is more than a word in
      // them: sin(x + 1) is not sin(x) + 1.
      if (_simple(argument)) return '$name of $argument';
      return '$name of open bracket $argument close bracket';
    }
    if (n is LogNode) {
      final String argument = _list(n.argument);
      final String of =
          _simple(argument) ? argument : 'open bracket $argument close bracket';
      if (n.isNaturalLog) return 'natural log of $of';
      final String base = _list(n.base);
      if (base.isEmpty || base == '10') return 'log of $of';
      return 'log base $base of $of';
    }
    if (n is RootNode) {
      final String index = _list(n.index);
      final String radicand = _list(n.radicand);
      final String root = switch (index) {
        _ when n.isSquareRoot => 'square root',
        '' || '2' => 'square root',
        '3' => 'cube root',
        _ => 'root $index',
      };
      if (_simple(radicand)) return '$root of $radicand';
      return '$root of $radicand, end root';
    }
    if (n is ParenthesisNode) {
      return 'open bracket ${_list(n.content)} close bracket';
    }
    if (n is PermutationNode) {
      return 'permutations of ${_list(n.n)} taken ${_list(n.r)} at a time';
    }
    if (n is CombinationNode) {
      return '${_list(n.n)} choose ${_list(n.r)}';
    }
    if (n is SummationNode) {
      return 'sum from ${_list(n.variable)} equals ${_list(n.lower)} '
          'to ${_list(n.upper)} of ${_list(n.body)}, end sum';
    }
    if (n is ProductNode) {
      return 'product from ${_list(n.variable)} equals ${_list(n.lower)} '
          'to ${_list(n.upper)} of ${_list(n.body)}, end product';
    }
    if (n is DerivativeNode) {
      final String variable = _list(n.variable);
      final String at = _list(n.at);
      return _join(<String>[
        'derivative with respect to $variable of ${_list(n.body)},',
        if (n.isDefinite && at.isNotEmpty) 'at $variable equals $at,',
        'end derivative',
      ]);
    }
    if (n is IntegralNode) {
      final String lower = _list(n.lower);
      final String upper = _list(n.upper);
      final bool bounded = n.isDefinite && (lower + upper).isNotEmpty;
      return _join(<String>[
        bounded ? 'integral from $lower to $upper of' : 'integral of',
        '${_list(n.body)},',
        'd ${_list(n.variable)}',
      ]);
    }
    if (n is ComplexNode) return '${_list(n.content)} i';
    if (n is NewlineNode) return ',';
    if (n is AnsNode) return 'answer ${_list(n.index)}';
    if (n is ConstantNode) return _constants[n.constant] ?? _text(n.constant);
    // Before the unit vector it extends.
    if (n is ComplexVariableNode) return 'complex z';
    if (n is UnitVectorNode) return '${_letter(n.axis)} hat';
    return '';
  }

  /// Typed text: numbers whole, letters one at a time — `2kx` is 2 times k
  /// times x — and operators as their words.
  static String _text(String text) {
    final List<String> words = <String>[];
    final StringBuffer number = StringBuffer();
    void endNumber() {
      if (number.isEmpty) return;
      words.add(number.toString());
      number.clear();
    }

    for (final int rune in text.runes) {
      final String c = String.fromCharCode(rune);
      if ('0123456789.'.contains(c)) {
        number.write(c);
        continue;
      }
      endNumber();
      if (c.trim().isEmpty) continue;
      // The low line that makes z the complex variable, as it was once typed.
      if (c == '̲') {
        if (words.isNotEmpty && words.last == 'z') words.last = 'complex z';
        continue;
      }
      words.add(_symbols[c] ?? _letter(c));
    }
    endNumber();
    return _join(words);
  }

  static String _letter(String c) => _greek[c] ?? c;

  static const Map<String, String> _symbols = <String, String>{
    '+': 'plus',
    '-': 'minus',
    '−': 'minus',
    '×': 'times',
    '*': 'times',
    '·': 'times',
    '÷': 'divided by',
    '/': 'divided by',
    '=': 'equals',
    '≠': 'not equal to',
    '<': 'less than',
    '>': 'greater than',
    '≤': 'less than or equal to',
    '≥': 'greater than or equal to',
    '^': 'to the power',
    '(': 'open bracket',
    ')': 'close bracket',
    '!': 'factorial',
    '%': 'percent',
    '°': 'degrees',
    ',': ',',
    'ᴇ': 'times ten to the power',
    '²': 'squared',
    '³': 'cubed',
    '∞': 'infinity',
  };

  static const Map<String, String> _greek = <String, String>{
    'π': 'pi',
    'θ': 'theta',
    'φ': 'phi',
    'ρ': 'rho',
    'α': 'alpha',
    'β': 'beta',
    'γ': 'gamma',
    'λ': 'lambda',
    'μ': 'mu',
    'σ': 'sigma',
    'ω': 'omega',
  };

  static const Map<String, String> _functions = <String, String>{
    'sin': 'sine',
    'cos': 'cosine',
    'tan': 'tangent',
    'asin': 'inverse sine',
    'acos': 'inverse cosine',
    'atan': 'inverse tangent',
    'sinh': 'hyperbolic sine',
    'cosh': 'hyperbolic cosine',
    'tanh': 'hyperbolic tangent',
    'asinh': 'inverse hyperbolic sine',
    'acosh': 'inverse hyperbolic cosine',
    'atanh': 'inverse hyperbolic tangent',
    'abs': 'absolute value',
    'arg': 'argument',
    'Re': 'real part',
    'Im': 'imaginary part',
    'sgn': 'sign',
  };

  static const Map<String, String> _constants = <String, String>{
    'ε₀': 'permittivity of free space',
    'μ₀': 'permeability of free space',
    'c₀': 'speed of light',
    'e⁻': 'elementary charge',
  };
}
