import 'dart:convert';
import '../math_renderer/renderer.dart';

class MathExpressionSerializer {
  // Unicode characters used in the editor
  static const String _plusSign = '\u002B';
  static const String _minusSign = '\u2212';
  static const String _multiplySign = '\u00B7';

  /// Converts the expression tree to a PEMDAS-compliant string
  static String serialize(List<MathNode> expression) {
    final result = _serializeList(expression);
    return _cleanupExpression(result);
  }

  static String _serializeList(List<MathNode> nodes) {
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < nodes.length; i++) {
      buffer.write(_serializeNode(nodes[i]));
    }
    return buffer.toString();
  }

  static String _serializeNode(MathNode node) {
    if (node is LiteralNode) {
      return _normalizeLiteral(node.text);
    } else if (node is NewlineNode) {
      return '\n';
    } else if (node is FractionNode) {
      String num = _serializeList(node.numerator);
      String den = _serializeList(node.denominator);
      return '(($num)/($den))';
    } else if (node is ExponentNode) {
      String base = _serializeList(node.base);
      String power = _serializeList(node.power);
      if (_containsOperators(base)) {
        base = '($base)';
      }
      return '$base^($power)';
    } else if (node is ParenthesisNode) {
      String content = _serializeList(node.content);
      return '($content)';
    } else if (node is TrigNode) {
      String arg = _serializeList(node.argument);
      return '${node.function}($arg)';
    } else if (node is LogNode) {
      String arg = _serializeList(node.argument);
      if (node.isNaturalLog) {
        return 'ln($arg)';
      } else {
        String base = _serializeList(node.base);
        // log_n(x) = ln(x) / ln(n)
        return '(ln($arg)/ln($base))';
      }
    } else if (node is RootNode) {
      String radicand = _serializeList(node.radicand);
      if (node.isSquareRoot) {
        return 'sqrt($radicand)';
      } else {
        String index = _serializeList(node.index);
        return '(($radicand)^(1/($index)))';
      }
    } else if (node is PermutationNode) {
      String n = _serializeList(node.n);
      String r = _serializeList(node.r);
      return 'perm($n,$r)'; // Changed from '${n}P${r}'
    } else if (node is CombinationNode) {
      String n = _serializeList(node.n);
      String r = _serializeList(node.r);
      return 'comb($n,$r)'; // Changed from '${n}C${r}'
    } else if (node is SummationNode) {
      String v = _serializeList(node.variable);
      String lower = _serializeList(node.lower);
      String upper = _serializeList(node.upper);
      String body = _serializeList(node.body);
      return 'sum($v,$lower,$upper,$body)';
    } else if (node is DerivativeNode) {
      String v = _serializeList(node.variable);
      String at = _serializeList(node.at);
      String body = _serializeList(node.body);
      return 'diff($v,$at,$body)';
    } else if (node is IntegralNode) {
      String v = _serializeList(node.variable);
      String lower = _serializeList(node.lower);
      String upper = _serializeList(node.upper);
      String body = _serializeList(node.body);
      return 'int($v,$lower,$upper,$body)';
    } else if (node is ProductNode) {
      String v = _serializeList(node.variable);
      String lower = _serializeList(node.lower);
      String upper = _serializeList(node.upper);
      String body = _serializeList(node.body);
      return 'prod($v,$lower,$upper,$body)';
    } else if (node is AnsNode) {
      String idx = _serializeList(node.index);
      return 'ans$idx';
    } else if (node is ConstantNode) {
      return node.constant;
    } else if (node is UnitVectorNode) {
      return 'e_${node.axis}';
    }
    return '';
  }

  /// Converts unicode operators to standard operators
  static String _normalizeLiteral(String text) {
    return text
        .replaceAll(_multiplySign, '*')
        .replaceAll(_minusSign, '-')
        .replaceAll(_plusSign, '+');
  }

  /// Checks if expression contains +, -, *, /
  static bool _containsOperators(String expr) {
    return expr.contains('+') ||
        expr.contains('-') ||
        expr.contains('*') ||
        expr.contains('/');
  }

  /// Cleans up the final expression
  static String _cleanupExpression(String expr) {
    // Remove unnecessary double parentheses
    String result = expr;

    // Handle implicit multiplication: 2(x+1) -> 2*(x+1), (x)(y) -> (x)*(y)
    result = _addImplicitMultiplication(result);

    // Remove leading + sign
    if (result.startsWith('+')) {
      result = result.substring(1);
    }

    return result;
  }

  /// Adds implicit multiplication where needed
  static String _addImplicitMultiplication(String expr) {
    StringBuffer result = StringBuffer();

    for (int i = 0; i < expr.length; i++) {
      String current = expr[i];
      result.write(current);

      if (i < expr.length - 1) {
        String next = expr[i + 1];

        bool needsMultiply = false;

        // Check if this is scientific notation (e.g., 2E5, 2e-3)
        bool isScientificNotation = false;
        if (_isDigit(current) && (next == 'E' || next == 'e')) {
          // Look ahead to see if it's followed by digit or +/-
          if (i + 2 < expr.length) {
            String afterE = expr[i + 2];
            if (_isDigit(afterE) || afterE == '+' || afterE == '-') {
              isScientificNotation = true;
            }
          }
        }

        // Check if next char is P or C (permutation/combination operator)
        bool isPermCombOperator =
            (next == 'P' || next == 'C') &&
            _isDigit(current) &&
            _hasDigitAfterOperator(expr, i + 1);

        if (_isDigit(current) &&
            _isLetter(next) &&
            !isPermCombOperator &&
            !isScientificNotation) {
          needsMultiply = true;
        } else if (_isDigit(current) && next == '(') {
          needsMultiply = true;
        } else if (current == ')' && _isDigit(next)) {
          needsMultiply = true;
        } else if (current == ')' && _isLetter(next)) {
          needsMultiply = true;
        } else if (current == ')' && next == '(') {
          needsMultiply = true;
        } else if (_isLetter(current) && next == '(') {
          if (!_isFunction(expr, i)) {
            needsMultiply = true;
          }
        }

        if (needsMultiply) {
          result.write('*');
        }
      }
    }

    return result.toString();
  }

  /// Checks if there's a digit or opening parenthesis after P or C (to confirm it's a perm/comb operator)
  static bool _hasDigitAfterOperator(String expr, int operatorIndex) {
    if (operatorIndex + 1 < expr.length) {
      String nextChar = expr[operatorIndex + 1];
      return _isDigit(nextChar) || nextChar == '(';
    }
    return false;
  }

  static bool _isDigit(String char) {
    return char.isNotEmpty && '0123456789.'.contains(char);
  }

  static bool _isLetter(String char) {
    return char.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(char);
  }

  static bool _isFunction(String expr, int index) {
    // Common function names to check
    const functions = [
      'sin',
      'cos',
      'tan',
      'asin',
      'acos',
      'atan',
      'sinh',
      'cosh',
      'tanh',
      'asinh',
      'acosh',
      'atanh',
      'log',
      'ln',
      'sqrt',
      'abs',
      'arg',
      're',
      'im',
      'sgn',
      'diff',
      'int',
      'perm',
      'comb',
      'sum',
      'prod',
    ];

    for (String func in functions) {
      if (index >= func.length - 1) {
        String potentialFunc = expr.substring(
          index - func.length + 1,
          index + 1,
        );
        if (potentialFunc.toLowerCase() == func) {
          return true;
        }
      }
    }
    return false;
  }

  /// Converts expression to a format suitable for equation solving
  /// Returns the expression with proper operator precedence
  static String toSolverFormat(List<MathNode> expression) {
    return serialize(expression);
  }

  /// Extracts variable names from the expression
  static Set<String> extractVariables(List<MathNode> expression) {
    Set<String> variables = {};
    _extractVariablesFromList(expression, variables);
    return variables;
  }

  static void _extractVariablesFromList(
    List<MathNode> nodes,
    Set<String> variables,
  ) {
    for (final node in nodes) {
      _extractVariablesFromNode(node, variables);
    }
  }

  static void _extractVariablesFromNode(MathNode node, Set<String> variables) {
    if (node is LiteralNode) {
      // Find all letter sequences that are not part of numbers
      RegExp varRegex = RegExp(r'[a-zA-Z]+');
      for (Match match in varRegex.allMatches(node.text)) {
        String potential = match.group(0)!;
        // Exclude common function names and imaginary unit
        const excluded = {
          'sin',
          'cos',
          'tan',
          'log',
          'ln',
          'sqrt',
          'abs',
          'arg',
          're',
          'im',
          'sgn',
          'sum',
          'prod',
          'p',
          'c',
          'i', // imaginary unit
        };
        if (!excluded.contains(potential.toLowerCase())) {
          variables.add(potential);
        }
      }
    } else if (node is FractionNode) {
      _extractVariablesFromList(node.numerator, variables);
      _extractVariablesFromList(node.denominator, variables);
    } else if (node is ExponentNode) {
      _extractVariablesFromList(node.base, variables);
      _extractVariablesFromList(node.power, variables);
    } else if (node is ParenthesisNode) {
      _extractVariablesFromList(node.content, variables);
    } else if (node is LogNode) {
      _extractVariablesFromList(node.base, variables);
      _extractVariablesFromList(node.argument, variables);
    } else if (node is AnsNode) {
      // Don't extract variables from ANS index - it's just a reference number
      // Don't extract variables from ANS index - it's just a reference number
      // But if someone puts a variable in there, we might want to ignore it
    } else if (node is ConstantNode) {
      // Constants are not variables to be solved for
    } else if (node is UnitVectorNode) {
      // Unit vectors are not variables to be solved for
    } else if (node is SummationNode) {
      // Variables in the body are bound by the summation variable
      _extractVariablesFromList(node.lower, variables);
      _extractVariablesFromList(node.upper, variables);
      _extractVariablesFromList(node.body, variables);
      final bound = _serializeList(node.variable).trim();
      if (bound.isNotEmpty) {
        variables.remove(bound);
      }
    } else if (node is DerivativeNode) {
      _extractVariablesFromList(node.at, variables);
      _extractVariablesFromList(node.body, variables);
      final bound = _serializeList(node.variable).trim();
      if (bound.isNotEmpty) {
        variables.remove(bound);
      }
    } else if (node is IntegralNode) {
      _extractVariablesFromList(node.lower, variables);
      _extractVariablesFromList(node.upper, variables);
      _extractVariablesFromList(node.body, variables);
      final bound = _serializeList(node.variable).trim();
      if (bound.isNotEmpty) {
        variables.remove(bound);
      }
    } else if (node is ProductNode) {
      _extractVariablesFromList(node.lower, variables);
      _extractVariablesFromList(node.upper, variables);
      _extractVariablesFromList(node.body, variables);
      final bound = _serializeList(node.variable).trim();
      if (bound.isNotEmpty) {
        variables.remove(bound);
      }
    }
  }

  /// Checks if the expression is an equation (contains =)
  static bool isEquation(List<MathNode> expression) {
    return serialize(expression).contains('=');
  }

  /// Splits an equation into LHS and RHS
  static List<String>? splitEquation(List<MathNode> expression) {
    String expr = serialize(expression);
    if (!expr.contains('=')) return null;

    List<String> parts = expr.split('=');
    if (parts.length != 2) return null;

    return [parts[0].trim(), parts[1].trim()];
  }

  // ============== JSON SERIALIZATION FOR PERSISTENCE ==============

  /// Converts expression tree to JSON string for storage
  static String serializeToJson(List<MathNode> expression) {
    List<Map<String, dynamic>> jsonList =
        expression.map((node) => _nodeToJson(node)).toList();
    return jsonEncode(jsonList);
  }

  /// Converts JSON string back to expression tree
  static List<MathNode> deserializeFromJson(String jsonString) {
    if (jsonString.isEmpty) return [LiteralNode()];

    try {
      List<dynamic> jsonList = jsonDecode(jsonString);
      List<MathNode> nodes =
          jsonList
              .map((json) => _jsonToNode(json as Map<String, dynamic>))
              .toList();
      return nodes.isNotEmpty ? nodes : [LiteralNode()];
    } catch (e) {
      return [LiteralNode()];
    }
  }

  /// Convert a single MathNode to JSON map
  static Map<String, dynamic> _nodeToJson(MathNode node) {
    if (node is LiteralNode) {
      return {'type': 'literal', 'text': node.text};
    }

    if (node is FractionNode) {
      return {
        'type': 'fraction',
        'numerator': node.numerator.map((n) => _nodeToJson(n)).toList(),
        'denominator': node.denominator.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is ExponentNode) {
      return {
        'type': 'exponent',
        'base': node.base.map((n) => _nodeToJson(n)).toList(),
        'power': node.power.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is ParenthesisNode) {
      return {
        'type': 'parenthesis',
        'content': node.content.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is TrigNode) {
      return {
        'type': 'trig',
        'function': node.function,
        'argument': node.argument.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is RootNode) {
      return {
        'type': 'root',
        'isSquareRoot': node.isSquareRoot,
        'index': node.index.map((n) => _nodeToJson(n)).toList(),
        'radicand': node.radicand.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is LogNode) {
      return {
        'type': 'log',
        'isNaturalLog': node.isNaturalLog,
        'base': node.base.map((n) => _nodeToJson(n)).toList(),
        'argument': node.argument.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is PermutationNode) {
      return {
        'type': 'permutation',
        'n': node.n.map((n) => _nodeToJson(n)).toList(),
        'r': node.r.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is CombinationNode) {
      return {
        'type': 'combination',
        'n': node.n.map((n) => _nodeToJson(n)).toList(),
        'r': node.r.map((n) => _nodeToJson(n)).toList(),
      };
    }
    if (node is SummationNode) {
      return {
        'type': 'summation',
        'variable': node.variable.map((n) => _nodeToJson(n)).toList(),
        'lower': node.lower.map((n) => _nodeToJson(n)).toList(),
        'upper': node.upper.map((n) => _nodeToJson(n)).toList(),
        'body': node.body.map((n) => _nodeToJson(n)).toList(),
      };
    }
    if (node is DerivativeNode) {
      return {
        'type': 'derivative',
        'variable': node.variable.map((n) => _nodeToJson(n)).toList(),
        'at': node.at.map((n) => _nodeToJson(n)).toList(),
        'body': node.body.map((n) => _nodeToJson(n)).toList(),
        'isDefinite': node.isDefinite,
      };
    }
    if (node is IntegralNode) {
      return {
        'type': 'integral',
        'variable': node.variable.map((n) => _nodeToJson(n)).toList(),
        'lower': node.lower.map((n) => _nodeToJson(n)).toList(),
        'upper': node.upper.map((n) => _nodeToJson(n)).toList(),
        'body': node.body.map((n) => _nodeToJson(n)).toList(),
        'isDefinite': node.isDefinite,
      };
    }
    if (node is ProductNode) {
      return {
        'type': 'product',
        'variable': node.variable.map((n) => _nodeToJson(n)).toList(),
        'lower': node.lower.map((n) => _nodeToJson(n)).toList(),
        'upper': node.upper.map((n) => _nodeToJson(n)).toList(),
        'body': node.body.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is AnsNode) {
      return {
        'type': 'ans',
        'index': node.index.map((n) => _nodeToJson(n)).toList(),
      };
    }

    if (node is NewlineNode) {
      return {'type': 'newline'};
    }

    if (node is ConstantNode) {
      return {'type': 'constant', 'constant': node.constant};
    }
    if (node is UnitVectorNode) {
      return {'type': 'unit_vector', 'axis': node.axis};
    }

    // Fallback for unknown node types
    return {'type': 'literal', 'text': ''};
  }

  /// Convert JSON map back to MathNode
  static MathNode _jsonToNode(Map<String, dynamic> json) {
    String type = json['type'] as String? ?? 'literal';

    switch (type) {
      case 'literal':
        return LiteralNode(text: json['text'] as String? ?? '');

      case 'fraction':
        return FractionNode(
          num: _jsonToNodeList(json['numerator']),
          den: _jsonToNodeList(json['denominator']),
        );

      case 'exponent':
        return ExponentNode(
          base: _jsonToNodeList(json['base']),
          power: _jsonToNodeList(json['power']),
        );

      case 'parenthesis':
        return ParenthesisNode(content: _jsonToNodeList(json['content']));

      case 'trig':
        return TrigNode(
          function: json['function'] as String? ?? 'sin',
          argument: _jsonToNodeList(json['argument']),
        );

      case 'root':
        bool isSquare = json['isSquareRoot'] as bool? ?? false;
        return RootNode(
          isSquareRoot: isSquare,
          index: _jsonToNodeList(json['index']),
          radicand: _jsonToNodeList(json['radicand']),
        );

      case 'log':
        return LogNode(
          isNaturalLog: json['isNaturalLog'] as bool? ?? false,
          base: _jsonToNodeList(json['base']),
          argument: _jsonToNodeList(json['argument']),
        );

      case 'permutation':
        return PermutationNode(
          n: _jsonToNodeList(json['n']),
          r: _jsonToNodeList(json['r']),
        );

      case 'combination':
        return CombinationNode(
          n: _jsonToNodeList(json['n']),
          r: _jsonToNodeList(json['r']),
        );
      case 'summation':
        return SummationNode(
          variable: _jsonToNodeList(json['variable']),
          lower: _jsonToNodeList(json['lower']),
          upper: _jsonToNodeList(json['upper']),
          body: _jsonToNodeList(json['body']),
        );
      case 'derivative':
        return DerivativeNode(
          variable: _jsonToNodeList(json['variable']),
          at: _jsonToNodeList(json['at']),
          body: _jsonToNodeList(json['body']),
          isDefinite: json['isDefinite'] as bool? ?? true,
        );
      case 'integral':
        return IntegralNode(
          variable: _jsonToNodeList(json['variable']),
          lower: _jsonToNodeList(json['lower']),
          upper: _jsonToNodeList(json['upper']),
          body: _jsonToNodeList(json['body']),
          isDefinite: json['isDefinite'] as bool? ?? true,
        );
      case 'product':
        return ProductNode(
          variable: _jsonToNodeList(json['variable']),
          lower: _jsonToNodeList(json['lower']),
          upper: _jsonToNodeList(json['upper']),
          body: _jsonToNodeList(json['body']),
        );

      case 'ans':
        return AnsNode(index: _jsonToNodeList(json['index']));

      case 'newline':
        return NewlineNode();

      case 'constant':
        return ConstantNode(json['constant'] as String? ?? '');
      case 'unit_vector':
        return UnitVectorNode(json['axis'] as String? ?? 'x');

      default:
        return LiteralNode();
    }
  }

  /// Helper to convert JSON list to List\<MathNode>
  static List<MathNode> _jsonToNodeList(dynamic jsonList) {
    if (jsonList == null) return [LiteralNode()];

    try {
      List<MathNode> nodes =
          (jsonList as List)
              .map((item) => _jsonToNode(item as Map<String, dynamic>))
              .toList();
      return nodes.isNotEmpty ? nodes : [LiteralNode()];
    } catch (e) {
      return [LiteralNode()];
    }
  }
}
