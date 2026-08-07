import 'dart:math';
import '../settings/settings_provider.dart';

/// Math solver for expressions from the new math renderer

class MathSolverNew {
  // ============== GLOBAL PRECISION SETTING ==============
  static int precision = 6; // Default precision, can be changed globally
  static NumberFormat numberFormat = NumberFormat.automatic; // NEW

  /// Call this to update precision from settings
  static void setPrecision(int value) {
    precision = value;
  }

  /// Call this to update number format from settings
  static void setNumberFormat(NumberFormat value) {
    numberFormat = value;
  }

  /// Formats a number using current precision and number format settings.
  static String formatResult(double num) {
    return _formatResult(num);
  }

  /// Main entry point - determines what type of expression and solves accordingly
  static String? solve(String expression, {Map<int, String>? ansValues}) {
    expression = expression.trim();
    if (expression.isEmpty) return null;

    // Replace ANS references first
    if (ansValues != null && ansValues.isNotEmpty) {
      expression = _preprocessAnsReferences(expression, ansValues);
    }

    // Check if it's a system of equations (multiple lines)
    if (expression.contains('\n')) {
      // Count variables across all equations
      Set<String> allVariables = {};
      List<String> equations =
          expression.split('\n').where((e) => e.trim().isNotEmpty).toList();

      for (String eq in equations) {
        allVariables.addAll(_findVariables(eq));
      }

      // Need at least as many equations as variables
      if (allVariables.length > equations.length) {
        return null; // Not enough equations
      }

      return solveLinearSystem(expression);
    }

    // Check if it's an equation
    if (expression.contains('=')) {
      // Check variable count before attempting to solve
      Set<String> variables = _findVariables(expression);

      if (variables.length > 1) {
        // More than one variable - cannot solve single equation
        return null;
      }

      return solveEquation(expression);
    }

    // Otherwise, evaluate as an expression
    return evaluate(expression);
  }
  // ============== EXPRESSION EVALUATION ==============

  /// Evaluates a mathematical expression and returns the result
  static String? evaluate(String expression) {
    try {
      expression = _preprocess(expression);
      _ExpressionParser parser = _ExpressionParser(expression);
      dynamic result = parser.parse();

      if (result is Complex) {
        return _formatComplexResult(result);
      }

      return _formatResult(
        result is double ? result : (result as num).toDouble(),
      );
    } catch (e) {
      return '';
    }
  }

  /// Format a complex number result
  static String _formatComplexResult(Complex c) {
    // Check if purely real
    if (c.imag.abs() < 1e-10) {
      return _formatResult(c.real);
    }

    // Check if purely imaginary
    if (c.real.abs() < 1e-10) {
      if ((c.imag - 1).abs() < 1e-10) return 'i';
      if ((c.imag + 1).abs() < 1e-10) return '-i';
      return '${_formatResult(c.imag)}i';
    }

    // Both real and imaginary parts
    String realStr = _formatResult(c.real);
    String imagStr = _formatResult(c.imag.abs());

    if (c.imag >= 0) {
      if ((c.imag - 1).abs() < 1e-10) return '$realStr + i';
      return '$realStr + ${imagStr}i';
    } else {
      if ((c.imag + 1).abs() < 1e-10) return '$realStr - i';
      return '$realStr - ${imagStr}i';
    }
  }

  /// Preprocesses the expression for evaluation
  static String _preprocess(String expr) {
    // Remove spaces
    expr = expr.replaceAll(' ', '');

    expr = expr.replaceAll('\u00B7', '*'); // middle dot ·
    expr = expr.replaceAll('\u00D7', '*'); // times sign ×

    // Convert small caps E back to regular e for parsing
    expr = expr.replaceAll('\u1D07', 'E');

    expr = expr.replaceAll('\u00B0', '*($pi/180)'); // degrees

    // Handle πi and iπ patterns BEFORE general π replacement
    // πi -> (π)*(i) and iπ -> (i)*(π)
    expr = expr.replaceAll('\u03C0i', '($pi)*(i)');
    expr = expr.replaceAll('i\u03C0', '(i)*($pi)');

    // Also handle with multiplication sign already present
    expr = expr.replaceAll('\u03C0*i', '($pi)*(i)');
    expr = expr.replaceAll('i*\u03C0', '(i)*($pi)');

    // Replace pi constant - only add * if preceded by digit, ), or subscript 0.
    // No negative lookahead here; sin(π), cos(π), tan(π), and 2π must all convert.
    expr = expr.replaceAllMapped(RegExp(r'([\d\)\u2080])?\u03C0'), (match) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*($pi)';
      }
      return '($pi)';
    });

    // Replace standalone e (Euler's number), but not e⁻ (elementary charge)
    // Also don't replace if it's part of 'exp' or already replaced.
    // First, protect lowercase-'e' scientific notation (e.g. 2e3, 1.5e-10) so
    // the Euler replacement does not corrupt it: a scientific 'e' is preceded
    // by a digit/decimal point and followed by an optional sign and a digit —
    // the same shape the number parser recognises. It is restored just after.
    final sciSentinel = String.fromCharCode(1);
    expr = expr.replaceAllMapped(
      RegExp(r'(?<=[\d.])e(?=[+\-]?\d)'),
      (_) => sciSentinel,
    );
    expr = expr.replaceAllMapped(
      RegExp(r'([\d\)\u2080])?(?<![a-zA-Z\$])e(?![a-zA-Z\u207b])'),
      (match) {
        String? before = match.group(1);
        if (before != null) {
          return '$before*($e)';
        }
        return '($e)';
      },
    );

    // Restore protected scientific-notation exponents.
    expr = expr.replaceAll(sciSentinel, 'e');

    // Default mode is radians; explicit "rad" unit suffix is a no-op.
    expr = expr.replaceAll(
      RegExp(r'(?<=[\d\)])rad\b', caseSensitive: false),
      '',
    );

    // Replace physical constants
    // Vacuum permittivity ε₀ = 8.8541878128e-12 F/m
    expr = expr.replaceAllMapped(RegExp(r'([\d\)\u2080\u03C0])?\u03B5\u2080'), (
      match,
    ) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*(8.8541878128e-12)';
      }
      return '(8.8541878128e-12)';
    });

    // Vacuum permeability μ₀ = 1.25663706212e-6 H/m
    expr = expr.replaceAllMapped(RegExp(r'([\d\)\u2080\u03C0])?\u03BC\u2080'), (
      match,
    ) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*(1.25663706212e-6)';
      }
      return '(1.25663706212e-6)';
    });

    // Speed of light c₀ = 299792458 m/s
    expr = expr.replaceAllMapped(RegExp(r'([\d\)\u2080\u03C0])?c\u2080'), (
      match,
    ) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*(299792458)';
      }
      return '(299792458)';
    });

    // elementary charge e⁻ = 1.602176634e-19 C
    expr = expr.replaceAllMapped(RegExp(r'([\d\)\u2080\u03C0])?e\u207b'), (
      match,
    ) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*(1.602176634e-19)';
      }
      return '(1.602176634e-19)';
    });

    // Process special functions
    expr = _preprocessPermuCombination(expr);
    expr = _processFactorials(expr);
    expr = _preprocessSummationProduct(expr);
    expr = _preprocessDerivativeIntegral(expr);

    // --- Implicit Multiplication ---
    // 1. Number followed by '('
    expr = expr.replaceAllMapped(
      RegExp(r'(\d)\('),
      (match) => '${match.group(1)}*(',
    );

    // 2. ')' followed by number
    expr = expr.replaceAllMapped(
      RegExp(r'\)(\d)'),
      (match) => ')*${match.group(1)}',
    );

    // 3. ')' followed by '('
    expr = expr.replaceAllMapped(RegExp(r'\)\('), (match) => ')*(');

    // 4. ')' followed by 'i'
    expr = expr.replaceAllMapped(
      RegExp(r'\)(i)(?![a-zA-Z])'),
      (match) => ')*(i)',
    );

    // 5. 'i' followed by '('
    expr = expr.replaceAllMapped(
      RegExp(r'(?<![a-zA-Z])(i)\('),
      (match) => '(i)*(',
    );

    return expr;
  }

  /// Evaluates an expression string to a double
  static double _evaluateExpression(String expr) {
    _ExpressionParser parser = _ExpressionParser(expr);
    return parser.parse();
  }

  // ============== EQUATION SOLVING ==============

  /// Solves an equation (linear or quadratic)
  /// Only solves if there's exactly one variable
  static String? solveEquation(String equation) {
    equation = equation.replaceAll(' ', '');

    // Find all unique variables in the equation
    Set<String> variables = _findVariables(equation);

    // If no variables, just evaluate the expression
    if (variables.isEmpty) {
      return evaluate('${equation.replaceAll('=', '-(')})');
    }

    // If more than one variable, return null or the original equation
    // (needs more equations to solve)
    if (variables.length > 1) {
      return null; // Or return equation to show it as-is
    }

    // Exactly one variable - proceed to solve
    String variable = variables.first;

    List<String> parts = equation.split('=');
    if (parts.length != 2) return null;

    String lhs = parts[0].trim();
    String rhs = parts[1].trim();

    // Get coefficients for both sides
    List<double> coeffsLHS = _getCoefficients(lhs, variable);
    List<double> coeffsRHS = _getCoefficients(rhs, variable);

    double a = coeffsLHS[0] - coeffsRHS[0]; // x^2 coefficient
    double b = coeffsLHS[1] - coeffsRHS[1]; // x coefficient
    double c = coeffsLHS[2] - coeffsRHS[2]; // constant

    // Linear equation (a = 0)
    if (a.abs() < 1e-10) {
      if (b.abs() < 1e-10) {
        if (c.abs() < 1e-10) return "Infinite solutions";
        return "No solution";
      }
      return '$variable = ${_formatResult(-c / b)}';
    }

    // Quadratic equation
    if (c.abs() < 1e-10) {
      // x(ax + b) = 0
      return '$variable = 0\n$variable = ${_formatResult(-b / a)}';
    }

    double discriminant = b * b - 4 * a * c;

    if (discriminant < 0) {
      // Complex roots
      double realPart = -b / (2 * a);
      double imagPart = sqrt(-discriminant) / (2 * a);
      return '$variable = ${_formatResult(realPart)} ± ${_formatResult(imagPart.abs())}i';
    }

    // Real roots using numerically stable formula
    double root1, root2;
    if (discriminant == 0) {
      root1 = root2 = -b / (2 * a);
    } else {
      // Use citardauq formula for numerical stability
      double sqrtDisc = sqrt(discriminant);
      if (b >= 0) {
        root1 = (-b - sqrtDisc) / (2 * a);
        root2 = (2 * c) / (-b - sqrtDisc);
      } else {
        root1 = (2 * c) / (-b + sqrtDisc);
        root2 = (-b + sqrtDisc) / (2 * a);
      }
    }

    if ((root1 - root2).abs() < 1e-10) {
      return '$variable = ${_formatResult(root1)}';
    }

    return '$variable = ${_formatResult(root1)}\n$variable = ${_formatResult(root2)}';
  }

  /// Find all unique variables in an expression
  static Set<String> _findVariables(String expression) {
    Set<String> variables = {};

    // Reserved function names and constants to exclude
    const reserved = {
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
      'exp',
      'diff',
      'int',
      'perm',
      'comb',
      'ans',
      'e',
      'pi',
      'i',
    };

    // Find all letter sequences
    RegExp letterRegex = RegExp(r'[a-zA-Z]+');

    for (Match match in letterRegex.allMatches(expression)) {
      String potential = match.group(0)!.toLowerCase();

      // Check if it's a reserved word
      if (!reserved.contains(potential)) {
        // For single letters, add them as variables
        // For multi-letter sequences not in reserved, check each letter
        if (match.group(0)!.length == 1) {
          variables.add(match.group(0)!);
        } else if (!reserved.contains(potential)) {
          // Multi-letter non-reserved - might be implicit multiplication like "xy"
          // Add each letter as a separate variable
          for (int i = 0; i < match.group(0)!.length; i++) {
            String char = match.group(0)![i];
            if (!reserved.contains(char.toLowerCase())) {
              variables.add(char);
            }
          }
        }
      }
    }

    return variables;
  }

  /// Extracts coefficients [a, b, c] for ax^2 + bx + c
  static List<double> _getCoefficients(String expression, String variable) {
    double a = 0, b = 0, c = 0;

    expression = expression.replaceAll(' ', '');

    // Ensure starts with sign
    if (!expression.startsWith('+') && !expression.startsWith('-')) {
      expression = '+$expression';
    }

    // Split into terms by + or - while keeping the sign
    List<String> terms = [];
    String currentTerm = '';

    for (int i = 0; i < expression.length; i++) {
      String char = expression[i];
      if ((char == '+' || char == '-') && i > 0) {
        if (currentTerm.isNotEmpty) {
          terms.add(currentTerm.trim());
        }
        currentTerm = char;
      } else {
        currentTerm += char;
      }
    }
    if (currentTerm.isNotEmpty) {
      terms.add(currentTerm.trim());
    }

    String quadSuffix = '$variable^(2)';
    String quadSuffixAlt = variable + r'^2';

    for (String term in terms) {
      // Check for quadratic term: ends with x^(2) or x^2
      if (term.endsWith(quadSuffix) || term.endsWith(quadSuffixAlt)) {
        String coeffPart;
        if (term.endsWith(quadSuffix)) {
          coeffPart = term.substring(0, term.length - quadSuffix.length);
        } else {
          coeffPart = term.substring(0, term.length - quadSuffixAlt.length);
        }
        if (coeffPart.endsWith('*')) {
          coeffPart = coeffPart.substring(0, coeffPart.length - 1);
        }
        double coeff = _parseCoefficient(coeffPart);
        a += coeff;
      }
      // Check for linear term: contains variable but no ^
      else if (term.contains(variable) && !term.contains('^')) {
        int varIndex = term.indexOf(variable);
        String coeffPart = term.substring(0, varIndex);
        String remainder = term.substring(varIndex + variable.length);
        if (coeffPart.endsWith('*')) {
          coeffPart = coeffPart.substring(0, coeffPart.length - 1);
        }
        if ((coeffPart.isEmpty || coeffPart == '+' || coeffPart == '-') &&
            remainder.startsWith('/')) {
          coeffPart = '${coeffPart}1$remainder';
        }
        double coeff = _parseCoefficient(coeffPart);
        b += coeff;
      }
      // Constant term: no variable
      else if (!term.contains(variable)) {
        c += _parseCoefficient(term);
      }
    }

    return [a, b, c];
  }

  /// Parses a coefficient string, handling empty/sign-only cases
  static double _parseCoefficient(String coeff) {
    coeff = coeff.trim();
    if (coeff.isEmpty || coeff == '+') return 1.0;
    if (coeff == '-') return -1.0;
    String normalized = coeff;
    if (normalized.startsWith('+')) {
      normalized = normalized.substring(1);
    }
    try {
      return double.parse(normalized);
    } catch (_) {}

    try {
      normalized = _preprocess(normalized);
      _ExpressionParser parser = _ExpressionParser(normalized);
      dynamic result = parser.parse();
      if (result is Complex) {
        if (result.imag.abs() < 1e-10) return result.real;
        return 0.0;
      }
      return (result as num).toDouble();
    } catch (_) {
      return 0.0;
    }
  }

  // ============== LINEAR SYSTEM SOLVING ==============

  /// Solves a system of linear equations using Cramer's rule
  static String? solveLinearSystem(String equationsString) {
    List<String> equations = equationsString.replaceAll(' ', '').split('\n');
    equations = equations.where((eq) => eq.trim().isNotEmpty).toList();

    if (equations.isEmpty || equations.length > 3) return null;

    Set<String> variableSet = {};
    List<Map<String, double>> equationCoefficients = [];
    List<double> constants = [];

    const reserved = {
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
      'exp',
      'e',
      'pi',
      'i',
    };

    ({Map<String, double> coeffs, double constant})? parseSide(String side) {
      final coeffs = <String, double>{};
      double constant = 0.0;

      side = side.replaceAll(' ', '');
      if (side.isEmpty) {
        return (coeffs: coeffs, constant: constant);
      }

      if (!side.startsWith('+') && !side.startsWith('-')) {
        side = '+$side';
      }

      List<String> terms = [];
      String currentTerm = '';
      for (int i = 0; i < side.length; i++) {
        String char = side[i];
        if ((char == '+' || char == '-') && i > 0) {
          if (currentTerm.isNotEmpty) {
            terms.add(currentTerm);
          }
          currentTerm = char;
        } else {
          currentTerm += char;
        }
      }
      if (currentTerm.isNotEmpty) {
        terms.add(currentTerm);
      }

      for (String term in terms) {
        term = term.trim();
        if (term.isEmpty || term == '+' || term == '-') continue;
        if (term.contains('^')) return null;

        final matches = RegExp(r'[a-zA-Z]').allMatches(term).toList();
        if (matches.isEmpty) {
          constant += _parseCoefficient(term);
          continue;
        }

        final variables = matches.map((m) => m.group(0)!).toSet();
        if (variables.length != 1) return null;
        if (matches.length != 1) return null;

        final varName = variables.first;
        if (reserved.contains(varName)) return null;

        String coeffPart = term.replaceAll(varName, '');
        coeffPart = coeffPart.replaceAll('*', '');
        if (RegExp(r'^[+-]?/').hasMatch(coeffPart)) {
          coeffPart = coeffPart.replaceFirst('/', '1/');
        }
        double coeff = _parseCoefficient(coeffPart);
        coeffs[varName] = (coeffs[varName] ?? 0) + coeff;
      }

      return (coeffs: coeffs, constant: constant);
    }

    RegExp equationRegex = RegExp(r'(.+)=([^=]+)');

    for (String eq in equations) {
      final match = equationRegex.firstMatch(eq);
      if (match == null) return null;

      String leftSide = match.group(1)!;
      String rightSide = match.group(2)!;

      final leftParsed = parseSide(leftSide);
      final rightParsed = parseSide(rightSide);
      if (leftParsed == null || rightParsed == null) return null;

      Map<String, double> equationMap = {};
      for (final entry in leftParsed.coeffs.entries) {
        equationMap[entry.key] = (equationMap[entry.key] ?? 0) + entry.value;
      }
      for (final entry in rightParsed.coeffs.entries) {
        equationMap[entry.key] = (equationMap[entry.key] ?? 0) - entry.value;
      }

      double combinedConstant = leftParsed.constant - rightParsed.constant;

      constants.add(-combinedConstant);
      equationCoefficients.add(equationMap);
      variableSet.addAll(equationMap.keys);
    }

    List<String> variables = variableSet.toList()..sort();
    if (variables.length != equations.length) {
      return null;
    }

    List<List<double>> coefficients = [];
    for (var equationMap in equationCoefficients) {
      List<double> row = variables.map((v) => equationMap[v] ?? 0.0).toList();
      coefficients.add(row);
    }

    double mainDet = _determinant(coefficients);

    if (mainDet.abs() < 1e-10) return null;

    StringBuffer solution = StringBuffer();
    for (int i = 0; i < variables.length; i++) {
      List<List<double>> tempMatrix = [];
      for (int j = 0; j < coefficients.length; j++) {
        List<double> row = List.from(coefficients[j]);
        row[i] = constants[j];
        tempMatrix.add(row);
      }
      double value = _determinant(tempMatrix) / mainDet;
      solution.writeln('${variables[i]} = ${_formatResult(value)}');
    }

    return solution.toString().trim();
  }

  /// Calculates determinant of a matrix recursively
  static double _determinant(List<List<double>> matrix) {
    int n = matrix.length;
    if (n == 1) return matrix[0][0];
    if (n == 2) {
      return matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0];
    }

    double det = 0;
    for (int i = 0; i < n; i++) {
      List<List<double>> subMatrix = [];
      for (int j = 1; j < n; j++) {
        subMatrix.add([...matrix[j]]..removeAt(i));
      }
      det += (i % 2 == 0 ? 1 : -1) * matrix[0][i] * _determinant(subMatrix);
    }
    return det;
  }

  // ============== SPECIAL FUNCTIONS ==============

  /// Replaces ANS references with actual values
  static String _preprocessAnsReferences(
    String expr,
    Map<int, String> ansValues,
  ) {
    RegExp ansRegex = RegExp(r'ans(\d+)', caseSensitive: false);

    return expr.replaceAllMapped(ansRegex, (match) {
      String indexStr = match.group(1) ?? '';

      int? index = int.tryParse(indexStr);
      if (index == null) {
        return '(0)';
      }

      if (!ansValues.containsKey(index)) {
        return '(0)';
      }

      String? value = ansValues[index];

      if (value == null || value.isEmpty) {
        return '(0)';
      }

      if (double.tryParse(value) == null) {
        List<String> lines = value.split('\n');
        for (String line in lines) {
          RegExp numRegex = RegExp(r'=\s*(-?\d+\.?\d*)');
          Match? numMatch = numRegex.firstMatch(line);
          if (numMatch != null) {
            return '(${numMatch.group(1)})';
          }
        }
        return '(0)';
      }

      return '($value)';
    });
  }

  // ============== PERMUTATION & COMBINATION ==============

  static String _preprocessPermuCombination(String expr) {
    expr = _processPermComb(expr, 'perm', true);
    expr = _processPermComb(expr, 'comb', false);
    return expr;
  }

  static String _preprocessSummationProduct(String expr) {
    expr = _processSumProd(expr, 'sum', false);
    expr = _processSumProd(expr, 'prod', true);
    return expr;
  }

  static String _preprocessDerivativeIntegral(String expr) {
    expr = _processDerivative(expr);
    expr = _processIntegral(expr);
    return expr;
  }

  static String _processDerivative(String expr) {
    int searchOffset = 0;
    while (true) {
      int startIndex = expr.indexOf('diff(', searchOffset);
      if (startIndex == -1) break;

      int openParen = startIndex + 'diff'.length;
      int closeParen = _findMatchingParen(expr, openParen);
      if (closeParen == -1) {
        searchOffset = startIndex + 1;
        continue;
      }

      String content = expr.substring(openParen + 1, closeParen);
      List<String>? parts = _splitTopLevelArgs(content, 3);
      if (parts == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      String varStr = parts[0].trim();
      String atStr = parts[1].trim();
      String bodyStr = parts[2].trim();

      if (varStr.isEmpty || bodyStr.isEmpty) {
        throw Exception('Incomplete derivative arguments');
      }

      // Numerical solver requires 'at' value
      if (atStr.isEmpty) {
        searchOffset = startIndex + 1;
        continue;
      }

      double? atVal = _evaluateSimpleExpression(atStr);
      if (atVal == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      double h = 1e-6 * max(1.0, atVal.abs());
      String plusExpr = _replaceVariable(
        bodyStr,
        varStr,
        (atVal + h).toString(),
      );
      String minusExpr = _replaceVariable(
        bodyStr,
        varStr,
        (atVal - h).toString(),
      );

      double fPlus = _evaluateExpression(_preprocess(plusExpr));
      double fMinus = _evaluateExpression(_preprocess(minusExpr));
      double result = (fPlus - fMinus) / (2 * h);

      String resultStr;
      if ((result - result.roundToDouble()).abs() < 1e-10) {
        resultStr = result.round().toString();
      } else {
        resultStr = result.toString();
      }

      expr =
          expr.substring(0, startIndex) +
          resultStr +
          expr.substring(closeParen + 1);
      searchOffset = startIndex + resultStr.length;
    }

    return expr;
  }

  static String _processIntegral(String expr) {
    int searchOffset = 0;
    while (true) {
      int startIndex = expr.indexOf('int(', searchOffset);
      if (startIndex == -1) break;

      int openParen = startIndex + 'int'.length;
      int closeParen = _findMatchingParen(expr, openParen);
      if (closeParen == -1) {
        searchOffset = startIndex + 1;
        continue;
      }

      String content = expr.substring(openParen + 1, closeParen);
      List<String>? parts = _splitTopLevelArgs(content, 4);
      if (parts == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      String varStr = parts[0].trim();
      String lowerStr = parts[1].trim();
      String upperStr = parts[2].trim();
      String bodyStr = parts[3].trim();

      if (varStr.isEmpty ||
          lowerStr.isEmpty ||
          upperStr.isEmpty ||
          bodyStr.isEmpty) {
        throw Exception('Incomplete integral arguments');
      }

      double? lowerVal = _evaluateSimpleExpression(lowerStr);
      double? upperVal = _evaluateSimpleExpression(upperStr);
      if (lowerVal == null || upperVal == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      double a = lowerVal;
      double b = upperVal;
      double sign = 1.0;
      if (a > b) {
        final temp = a;
        a = b;
        b = temp;
        sign = -1.0;
      }

      const int n = 200; // Simpson's rule requires even n
      double h = (b - a) / n;

      double sum = 0.0;
      for (int i = 0; i <= n; i++) {
        double x = a + h * i;
        String replaced = _replaceVariable(bodyStr, varStr, x.toString());
        double fx = _evaluateExpression(_preprocess(replaced));

        if (i == 0 || i == n) {
          sum += fx;
        } else if (i % 2 == 0) {
          sum += 2 * fx;
        } else {
          sum += 4 * fx;
        }
      }

      double result = sign * (sum * h / 3.0);

      String resultStr;
      if ((result - result.roundToDouble()).abs() < 1e-10) {
        resultStr = result.round().toString();
      } else {
        resultStr = result.toString();
      }

      expr =
          expr.substring(0, startIndex) +
          resultStr +
          expr.substring(closeParen + 1);
      searchOffset = startIndex + resultStr.length;
    }

    return expr;
  }

  static String _processPermComb(
    String expr,
    String funcName,
    bool isPermutation,
  ) {
    int searchOffset = 0;
    while (true) {
      int startIndex = expr.indexOf('$funcName(', searchOffset);
      if (startIndex == -1) break;

      int openParen = startIndex + funcName.length;

      int closeParen = _findMatchingParen(expr, openParen);
      if (closeParen == -1) {
        searchOffset = startIndex + 1;
        continue;
      }

      String content = expr.substring(openParen + 1, closeParen);

      int commaIndex = _findSeparatingComma(content);
      if (commaIndex == -1) {
        searchOffset = startIndex + 1;
        continue;
      }

      String nExpr = content.substring(0, commaIndex).trim();
      String rExpr = content.substring(commaIndex + 1).trim();

      if (nExpr.isEmpty || rExpr.isEmpty) {
        throw Exception('Incomplete $funcName arguments');
      }

      double? nValue = _evaluateSimpleExpression(nExpr);
      double? rValue = _evaluateSimpleExpression(rExpr);

      if (nValue == null || rValue == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      int n = nValue.toInt();
      int r = rValue.toInt();

      double result =
          isPermutation ? permutationDouble(n, r) : combinationDouble(n, r);

      String resultStr;
      if (result == result.roundToDouble() && result.abs() < 1e15) {
        resultStr = result.toInt().toString();
      } else {
        resultStr = result.toString();
      }

      expr =
          expr.substring(0, startIndex) +
          resultStr +
          expr.substring(closeParen + 1);
      searchOffset = startIndex + resultStr.length;
    }

    return expr;
  }

  static int _findMatchingParen(String expr, int openIndex) {
    if (openIndex >= expr.length || expr[openIndex] != '(') return -1;

    int depth = 1;
    for (int i = openIndex + 1; i < expr.length; i++) {
      if (expr[i] == '(') {
        depth++;
      } else if (expr[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  static int _findSeparatingComma(String content) {
    int depth = 0;
    for (int i = 0; i < content.length; i++) {
      if (content[i] == '(') {
        depth++;
      } else if (content[i] == ')') {
        depth--;
      } else if (content[i] == ',' && depth == 0) {
        return i;
      }
    }
    return -1;
  }

  static double? _evaluateSimpleExpression(String expr) {
    try {
      expr = expr.trim();
      while (expr.startsWith('(') && expr.endsWith(')')) {
        if (_findMatchingParen(expr, 0) == expr.length - 1) {
          expr = expr.substring(1, expr.length - 1).trim();
        } else {
          break;
        }
      }

      double? direct = double.tryParse(expr);
      if (direct != null) return direct;

      String preprocessed = _preprocessSimple(expr);
      return _evaluateExpression(preprocessed);
    } catch (e) {
      return null;
    }
  }

  static String _processSumProd(String expr, String funcName, bool isProduct) {
    int searchOffset = 0;
    while (true) {
      int startIndex = expr.indexOf('$funcName(', searchOffset);
      if (startIndex == -1) break;

      int openParen = startIndex + funcName.length;
      int closeParen = _findMatchingParen(expr, openParen);
      if (closeParen == -1) {
        searchOffset = startIndex + 1;
        continue;
      }

      String content = expr.substring(openParen + 1, closeParen);
      List<String>? parts = _splitTopLevelArgs(content, 4);
      if (parts == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      String varStr = parts[0].trim();
      String lowerStr = parts[1].trim();
      String upperStr = parts[2].trim();
      String bodyStr = parts[3].trim();

      if (varStr.isEmpty ||
          lowerStr.isEmpty ||
          upperStr.isEmpty ||
          bodyStr.isEmpty) {
        throw Exception('Incomplete $funcName arguments');
      }

      double? lowerVal = _evaluateSimpleExpression(lowerStr);
      double? upperVal = _evaluateSimpleExpression(upperStr);
      if (lowerVal == null || upperVal == null) {
        searchOffset = startIndex + 1;
        continue;
      }

      int lower = lowerVal.round();
      int upper = upperVal.round();

      if (lower > upper) {
        String emptyResult = isProduct ? '1' : '0';
        expr =
            expr.substring(0, startIndex) +
            emptyResult +
            expr.substring(closeParen + 1);
        searchOffset = startIndex + emptyResult.length;
        continue;
      }

      double result = isProduct ? 1.0 : 0.0;
      for (int i = lower; i <= upper; i++) {
        String replaced = _replaceVariable(bodyStr, varStr, i.toString());
        String preprocessed = _preprocess(replaced);
        double val = _evaluateExpression(preprocessed);
        if (isProduct) {
          result *= val;
        } else {
          result += val;
        }
      }

      String resultStr;
      if ((result - result.roundToDouble()).abs() < 1e-10) {
        resultStr = result.round().toString();
      } else {
        resultStr = result.toString();
      }

      expr =
          expr.substring(0, startIndex) +
          resultStr +
          expr.substring(closeParen + 1);
      searchOffset = startIndex + resultStr.length;
    }

    return expr;
  }

  static List<String>? _splitTopLevelArgs(String content, int expected) {
    List<String> parts = [];
    int depth = 0;
    int lastIndex = 0;
    for (int i = 0; i < content.length; i++) {
      final ch = content[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
      } else if (ch == ',' && depth == 0) {
        parts.add(content.substring(lastIndex, i));
        lastIndex = i + 1;
      }
    }
    parts.add(content.substring(lastIndex));
    if (parts.length != expected) return null;
    return parts;
  }

  static String _replaceVariable(String body, String variable, String value) {
    final pattern = RegExp(
      r'(?<![a-zA-Z0-9_])' + RegExp.escape(variable) + r'(?![a-zA-Z0-9_])',
    );
    return body.replaceAll(pattern, value);
  }

  static String _preprocessSimple(String expr) {
    expr = expr.replaceAll(' ', '');
    expr = expr.replaceAll('\u00B7', '*');
    expr = expr.replaceAll('\u00D7', '*');
    expr = expr.replaceAll('\u1D07', 'E');
    expr = expr.replaceAll('\u00B0', '*($pi/180)');

    expr = expr.replaceAllMapped(RegExp(r'([\d\)])?\u03C0'), (match) {
      String? before = match.group(1);
      if (before != null) {
        return '$before*($pi)';
      }
      return '($pi)';
    });

    expr = expr.replaceAllMapped(
      RegExp(r'([\d\)])?(?<![a-zA-Z])e(?![a-zA-Z])'),
      (match) {
        String? before = match.group(1);
        if (before != null) {
          return '$before*($e)';
        }
        return '($e)';
      },
    );

    // Default mode is radians; explicit "rad" unit suffix is a no-op.
    expr = expr.replaceAll(
      RegExp(r'(?<=[\d\)])rad\b', caseSensitive: false),
      '',
    );

    expr = _processFactorials(expr);
    expr = _preprocessSummationProduct(expr);
    expr = _preprocessDerivativeIntegral(expr);

    return expr;
  }

  // Keep old int versions for backward compatibility
  static int factorial(int n) {
    if (n <= 1) return 1;
    int result = 1;
    for (int i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  static int permutation(int n, int r) {
    if (r > n) return 0;
    return factorial(n) ~/ factorial(n - r);
  }

  static int combination(int n, int r) {
    if (r > n) return 0;
    return factorial(n) ~/ (factorial(r) * factorial(n - r));
  }

  // New double versions for large numbers
  static double permutationDouble(int n, int r) {
    if (r > n || r < 0 || n < 0) return 0;

    double result = 1;
    for (int i = 0; i < r; i++) {
      result *= (n - i);
    }
    return result;
  }

  static double combinationDouble(int n, int r) {
    if (r > n || r < 0 || n < 0) return 0;

    if (r > n - r) {
      r = n - r;
    }

    double result = 1;
    for (int i = 0; i < r; i++) {
      result *= (n - i);
      result /= (i + 1);
    }
    return result;
  }

  /// Process factorials n!
  static String _processFactorials(String expr) {
    RegExp regex = RegExp(r'(\d+)!');
    return expr.replaceAllMapped(regex, (match) {
      int n = int.parse(match.group(1)!);
      return _factorial(n).toString();
    });
  }

  /// Exact factorial. Uses [BigInt] so values `n >= 21` (which overflow a
  /// 64-bit `int`, e.g. `21! == 51090942171709440000`) are computed correctly.
  static BigInt _factorial(int n) {
    if (n <= 1) return BigInt.one;
    BigInt result = BigInt.one;
    for (int i = 2; i <= n; i++) {
      result *= BigInt.from(i);
    }
    return result;
  }

  // ============== FORMATTING ==============
  // ============== FORMATTING ==============
  static String _formatResult(double num) {
    if (num.isNaN || num.isInfinite) return num.toString();

    // Check if it's effectively zero (allow for very small physical constants)
    if (num.abs() < 1e-30) {
      return '0';
    }

    switch (numberFormat) {
      case NumberFormat.scientific:
        return _formatScientific(num);
      case NumberFormat.plain:
        return _formatPlain(num);
      case NumberFormat.automatic:
        return _formatAutomatic(num);
    }
  }

  /// Automatic format - scientific only for very large/small numbers
  static String _formatAutomatic(double num) {
    if (num == 0) return '0';

    // Automatic uses scientific notation if >= 1e6 or <= 1e-6 (absolute value)
    final abs = num.abs();
    if (abs >= 1e6 || abs <= 1e-6) {
      return _formatScientific(num);
    }

    // Check if it's effectively an integer
    if ((num - num.roundToDouble()).abs() < 1e-10) {
      return num.round().toString(); // No commas
    }

    String formatted = num.toStringAsFixed(precision);
    // Remove trailing zeros
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    return formatted; // No commas
  }

  /// Plain format - with commas, never scientific notation
  static String _formatPlain(double num) {
    // Check if it's effectively an integer
    if ((num - num.roundToDouble()).abs() < 1e-10) {
      return addCommas(num.round().toString());
    }

    String formatted = num.toStringAsFixed(precision);
    // Remove trailing zeros
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }

    // Split into integer and decimal parts
    List<String> parts = formatted.split('.');
    String integerPart = addCommas(parts[0]);

    if (parts.length > 1 && parts[1].isNotEmpty) {
      return '$integerPart.${parts[1]}';
    }
    return integerPart;
  }

  /// Adds commas to an integer string (handles negative numbers)
  static String addCommas(String numStr) {
    bool isNegative = numStr.startsWith('-');
    if (isNegative) {
      numStr = numStr.substring(1);
    }

    StringBuffer result = StringBuffer();
    int count = 0;

    for (int i = numStr.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) {
        result.write(',');
      }
      result.write(numStr[i]);
      count++;
    }

    String reversed = result.toString().split('').reversed.join();
    return isNegative ? '-$reversed' : reversed;
  }

  /// Formats a number in scientific notation (e.g., 1.23E6)
  static String _formatScientific(double num) {
    if (num == 0) return '0';

    // Use Dart's built-in exponential formatting
    String expStr = num.toStringAsExponential(precision);

    // Split into mantissa and exponent parts
    List<String> parts = expStr.toLowerCase().split('e');
    String mantissa = parts[0];
    String exponent = parts[1];

    // Remove trailing zeros from mantissa
    if (mantissa.contains('.')) {
      mantissa = mantissa.replaceAll(RegExp(r'0+$'), '');
      mantissa = mantissa.replaceAll(RegExp(r'\.$'), '');
    }
    // Format exponent (remove leading +)
    if (exponent.startsWith('+')) {
      exponent = exponent.substring(1);
    }
    // If exponent is 0, still use scientific format as requested, but Dart's toStringAsExponential
    // handles 0 exponent as 'e0' which we format to 'E0'.

    return '$mantissa\u1D07$exponent';
  }
}

// ============== EXPRESSION PARSER ==============

/// Recursive descent parser for mathematical expressions
// ============== EXPRESSION PARSER ==============

// ============== EXPRESSION PARSER ==============

class _PercentValue {
  final dynamic value;
  _PercentValue(this.value);
}

/// Recursive descent parser for mathematical expressions
class _ExpressionParser {
  final String expression;
  int _pos = 0;

  _ExpressionParser(this.expression);

  dynamic parse() {
    dynamic result = _parseAddSubtract();
    if (_pos < expression.length) {
      throw FormatException(
        'Unexpected character at position $_pos: ${expression[_pos]}',
      );
    }
    return _finalizeResult(result);
  }

  dynamic _parseAddSubtract() {
    dynamic left = _parseMultiplyDivide();

    while (_pos < expression.length) {
      String op = _currentChar();
      if (op != '+' && op != '-') break;
      _pos++;
      dynamic right = _parseMultiplyDivide();

      left = _unwrapPercent(left);

      // Convert to Complex for operation
      dynamic rightValue =
          right is _PercentValue ? _percentOf(left, right.value) : right;
      rightValue = _unwrapPercent(rightValue);

      Complex l = _toComplex(left);
      Complex r = _toComplex(rightValue);

      if (op == '+') {
        left = l + r;
      } else {
        left = l - r;
      }
    }

    return _simplifyResult(left);
  }

  dynamic _parseMultiplyDivide() {
    dynamic left = _parseUnary();

    while (_pos < expression.length) {
      String op = _currentChar();
      if (op != '*' && op != '/') break;
      _pos++;
      dynamic right = _parseUnary();

      left = _unwrapPercent(left);
      right = _unwrapPercent(right);

      if (op == '/' && left is! Complex && right is! Complex) {
        final l = _toDouble(left);
        final r = _toDouble(right);
        if (r == 0) {
          if (l == 0) {
            left = double.nan;
          } else {
            left = l.isNegative ? double.negativeInfinity : double.infinity;
          }
          continue;
        }
      }

      // Convert to Complex for operation
      Complex l = _toComplex(left);
      Complex r = _toComplex(right);

      if (op == '*') {
        left = l * r;
      } else {
        left = l / r;
      }
    }

    return _simplifyResult(left);
  }

  /// Factorial of a value reached by the parser (e.g. `(19+2)!`). Defined for
  /// non-negative integers only; anything else yields NaN. Uses BigInt for
  /// precision, then converts to double for the numeric pipeline.
  dynamic _applyFactorial(dynamic value) {
    if (value is Complex && value.imag.abs() > 1e-12) return double.nan;
    final double d = _toDouble(value);
    if (d.isNaN || d.isInfinite || d < 0) return double.nan;
    if ((d - d.roundToDouble()).abs() > 1e-9) return double.nan;
    final int n = d.round();
    BigInt result = BigInt.one;
    for (int i = 2; i <= n; i++) {
      result *= BigInt.from(i);
    }
    return result.toDouble();
  }

  dynamic _parsePower() {
    dynamic base = _parsePrimary();

    // Postfix factorial. Plain `n!` is handled earlier by _processFactorials,
    // but factorials of parenthesised/other primaries (e.g. `(19+2)!`) reach
    // the parser and are applied here. Binds tighter than `^`.
    while (_pos < expression.length && _currentChar() == '!') {
      _pos++;
      base = _applyFactorial(_unwrapPercent(base));
    }

    // Exponentiation is right-associative and binds tighter than unary minus
    // on the base but looser on the exponent, so `-2^2 == -4` and
    // `2^3^2 == 2^(3^2) == 512` and `2^-3 == 0.125`. The exponent is parsed
    // via `_parseUnary` (which recurses back into `_parsePower`), giving both
    // right-associativity and support for a signed exponent.
    if (_pos < expression.length && _currentChar() == '^') {
      _pos++;
      dynamic exponent = _parseUnary();
      base = _unwrapPercent(base);
      exponent = _unwrapPercent(exponent);

      // Check if base is Euler's number e
      bool baseIsE = false;
      if (base is double && (base - e).abs() < 1e-9) {
        baseIsE = true;
      } else if (base is Complex &&
          (base.real - e).abs() < 1e-9 &&
          base.imag.abs() < 1e-9) {
        baseIsE = true;
      }

      // Handle e^(complex) using Euler's formula
      if (baseIsE) {
        Complex expC = _toComplex(exponent);
        // e^(a+bi) = e^a * (cos(b) + i*sin(b))
        double expReal = exp(expC.real);
        double cosB = cos(expC.imag);
        double sinB = sin(expC.imag);
        base = Complex(expReal * cosB, expReal * sinB);
      } else if (base is Complex || exponent is Complex) {
        // General complex power: z^w = e^(w * ln(z))
        base = _complexPow(_toComplex(base), _toComplex(exponent));
      } else {
        // Real power
        double b = _toDouble(base);
        double exp = _toDouble(exponent);
        base = _realPow(b, exp);
      }
    }

    return _simplifyResult(base);
  }

  /// Real-valued power that also returns the real root of a negative base
  /// when the exponent is a rational p/q with an odd denominator (e.g. an
  /// nth root such as `(-8)^(1/3) == -2`). `dart:math`'s `pow` returns `NaN`
  /// for a negative base with a fractional exponent, so those cases are
  /// handled explicitly here. Genuinely complex cases (e.g. `(-1)^(1/2)`)
  /// still return `NaN` and are handled by the complex path elsewhere.
  double _realPow(double b, double exp) {
    if (b >= 0 || exp == exp.roundToDouble()) {
      return pow(b, exp).toDouble();
    }
    // Look for a small odd denominator q such that exp ≈ p/q.
    for (int q = 3; q <= 99; q += 2) {
      final double pDouble = exp * q;
      final double pRounded = pDouble.roundToDouble();
      if ((pDouble - pRounded).abs() < 1e-9) {
        final double magnitude = pow(b.abs(), exp).toDouble();
        // Sign is (-1)^p: negative only when the numerator is odd.
        return (pRounded.toInt().abs() % 2 == 1) ? -magnitude : magnitude;
      }
    }
    return pow(b, exp).toDouble();
  }

  dynamic _parseUnary() {
    if (_pos < expression.length) {
      if (_currentChar() == '-') {
        _pos++;
        dynamic val = _parseUnary();
        if (val is _PercentValue) {
          return _PercentValue(_negate(val.value));
        }
        if (val is Complex) {
          return Complex(-val.real, -val.imag);
        }
        return -_toDouble(val);
      }
      if (_currentChar() == '+') {
        _pos++;
        dynamic val = _parseUnary();
        if (val is _PercentValue) {
          return _PercentValue(val.value);
        }
        return val;
      }
    }
    return _parsePower();
  }

  dynamic _parsePrimary() {
    // Parentheses
    if (_currentChar() == '(') {
      _pos++;
      dynamic result = _parseAddSubtract();
      if (_currentChar() != ')') {
        throw FormatException('Missing closing parenthesis');
      }
      _pos++;
      if (_pos < expression.length && _currentChar() == '%') {
        _pos++;
        return _PercentValue(result);
      }
      return result;
    }

    // Check for standalone 'i' (imaginary unit)
    if (_currentChar() == 'i' && _isStandaloneI()) {
      _pos++;
      if (_pos < expression.length && _currentChar() == '%') {
        _pos++;
        return _PercentValue(Complex(0, 1));
      }
      return Complex(0, 1);
    }

    // Functions
    String? func = _tryParseFunction();
    if (func != null) {
      if (_currentChar() != '(') {
        throw FormatException('Expected ( after function $func');
      }
      _pos++;
      dynamic arg = _parseAddSubtract();
      if (_currentChar() != ')') {
        throw FormatException('Missing closing parenthesis for $func');
      }
      _pos++;
      dynamic result = _applyFunction(func, arg);
      if (_pos < expression.length && _currentChar() == '%') {
        _pos++;
        return _PercentValue(result);
      }
      return result;
    }

    // Number (possibly with imaginary part)
    dynamic result = _parseNumberOrComplex();
    if (_pos < expression.length && _currentChar() == '%') {
      _pos++;
      return _PercentValue(result);
    }
    return result;
  }

  /// Check if 'i' at current position is standalone (imaginary unit)
  bool _isStandaloneI() {
    if (_currentChar() != 'i') return false;

    // Check character before (if not at start)
    if (_pos > 0) {
      String prev = expression[_pos - 1];
      // If preceded by a letter, it's part of an identifier
      if (_isLetter(prev)) return false;
    }

    // Check character after (if not at end)
    if (_pos + 1 < expression.length) {
      String next = expression[_pos + 1];
      // If followed by a letter or digit, it's part of an identifier
      if (_isLetter(next)) return false;
    }

    return true;
  }

  String? _tryParseFunction() {
    const functions = [
      'sinh',
      'cosh',
      'tanh',
      'asinh',
      'acosh',
      'atanh',
      'sin',
      'cos',
      'tan',
      'asin',
      'acos',
      'atan',
      'log',
      'ln',
      'sqrt',
      'abs',
      'arg',
      're',
      'im',
      'sgn',
      'exp',
    ];

    for (String func in functions) {
      if (_pos + func.length <= expression.length &&
          expression.substring(_pos, _pos + func.length).toLowerCase() ==
              func) {
        // Make sure it's followed by '(' to confirm it's a function
        if (_pos + func.length < expression.length &&
            expression[_pos + func.length] == '(') {
          _pos += func.length;
          return func;
        }
      }
    }
    return null;
  }

  dynamic _applyFunction(String func, dynamic arg) {
    if (arg is Complex) {
      return _applyComplexFunction(func, arg);
    }

    double a = _toDouble(arg);
    switch (func) {
      case 'sin':
        return sin(a);
      case 'cos':
        return cos(a);
      case 'tan':
        return tan(a);
      case 'asin':
        return asin(a);
      case 'acos':
        return acos(a);
      case 'atan':
        return atan(a);
      case 'sinh':
        return (exp(a) - exp(-a)) / 2;
      case 'cosh':
        return (exp(a) + exp(-a)) / 2;
      case 'tanh':
        return (exp(a) - exp(-a)) / (exp(a) + exp(-a));
      case 'asinh':
        return log(a + sqrt(a * a + 1));
      case 'acosh':
        return log(a + sqrt(a * a - 1));
      case 'atanh':
        return 0.5 * log((1 + a) / (1 - a));
      case 'log':
        return log(a) / ln10;
      case 'ln':
        return log(a);
      case 'sqrt':
        if (a < 0) {
          return Complex(0, sqrt(-a));
        }
        return sqrt(a);
      case 'abs':
        return a.abs();
      case 'arg':
        return atan2(0.0, a);
      case 're':
        return a;
      case 'im':
        return 0.0;
      case 'sgn':
        if (a > 0) return 1.0;
        if (a < 0) return -1.0;
        return 0.0;
      case 'exp':
        return exp(a);
      default:
        throw FormatException('Unknown function: $func');
    }
  }

  Complex _applyComplexFunction(String func, Complex z) {
    switch (func) {
      case 'abs':
        return Complex(z.magnitude, 0);
      case 'arg':
        return Complex(atan2(z.imag, z.real), 0);
      case 're':
        return Complex(z.real, 0);
      case 'im':
        return Complex(z.imag, 0);
      case 'sgn':
        if (z.real == 0 && z.imag == 0) {
          return Complex(0, 0);
        }
        return z / Complex(z.magnitude, 0);
      case 'exp':
        return _complexExp(z);
      case 'ln':
        return _complexLn(z);
      case 'log':
        Complex lnZ = _complexLn(z);
        return Complex(lnZ.real / ln10, lnZ.imag / ln10);
      case 'sqrt':
        return _complexSqrt(z);
      case 'sin':
        // sin(z) = (e^(iz) - e^(-iz)) / (2i)
        Complex iz = Complex(-z.imag, z.real);
        Complex eiz = _complexExp(iz);
        Complex emiz = _complexExp(Complex(z.imag, -z.real));
        Complex diff = eiz - emiz;
        return Complex(diff.imag / 2, -diff.real / 2);
      case 'cos':
        // cos(z) = (e^(iz) + e^(-iz)) / 2
        Complex iz2 = Complex(-z.imag, z.real);
        Complex eiz2 = _complexExp(iz2);
        Complex emiz2 = _complexExp(Complex(z.imag, -z.real));
        Complex sum = eiz2 + emiz2;
        return Complex(sum.real / 2, sum.imag / 2);
      case 'tan':
        Complex sinZ = _applyComplexFunction('sin', z);
        Complex cosZ = _applyComplexFunction('cos', z);
        return sinZ / cosZ;
      case 'sinh':
        // sinh(z) = (e^z - e^(-z)) / 2
        Complex ez = _complexExp(z);
        Complex emz = _complexExp(Complex(-z.real, -z.imag));
        return Complex((ez.real - emz.real) / 2, (ez.imag - emz.imag) / 2);
      case 'cosh':
        // cosh(z) = (e^z + e^(-z)) / 2
        Complex ez2 = _complexExp(z);
        Complex emz2 = _complexExp(Complex(-z.real, -z.imag));
        return Complex((ez2.real + emz2.real) / 2, (ez2.imag + emz2.imag) / 2);
      case 'tanh':
        Complex sinhZ = _applyComplexFunction('sinh', z);
        Complex coshZ = _applyComplexFunction('cosh', z);
        return sinhZ / coshZ;
      default:
        throw FormatException('Complex function not implemented: $func');
    }
  }

  dynamic _parseNumberOrComplex() {
    int start = _pos;

    // Handle optional sign
    String sign = '';
    if (_pos < expression.length &&
        (_currentChar() == '-' || _currentChar() == '+')) {
      sign = _currentChar();
      _pos++;
    }

    // Check if this is just 'i' with optional sign (e.g., "i", "-i", "+i")
    if (_pos < expression.length && _currentChar() == 'i' && _isStandaloneI()) {
      _pos++; // consume 'i'
      double coeff = (sign == '-') ? -1.0 : 1.0;
      return Complex(0, coeff);
    }

    // Parse digits before decimal
    bool hasDigits = false;
    while (_pos < expression.length && _isDigit(_currentChar())) {
      hasDigits = true;
      _pos++;
    }

    // Parse decimal part
    if (_pos < expression.length && _currentChar() == '.') {
      _pos++;
      while (_pos < expression.length && _isDigit(_currentChar())) {
        hasDigits = true;
        _pos++;
      }
    }

    // Parse exponent (scientific notation)
    if (hasDigits &&
        _pos < expression.length &&
        (_currentChar() == 'e' || _currentChar() == 'E')) {
      // Check if this is scientific notation
      if (_pos + 1 < expression.length) {
        String nextChar = expression[_pos + 1];
        if (_isDigit(nextChar) || nextChar == '+' || nextChar == '-') {
          _pos++;
          if (_pos < expression.length &&
              (_currentChar() == '+' || _currentChar() == '-')) {
            _pos++;
          }
          while (_pos < expression.length && _isDigit(_currentChar())) {
            _pos++;
          }
        }
      }
    }

    // Check if followed by 'i' (imaginary coefficient like 2i or 3.5i)
    bool isImaginary = false;
    if (_pos < expression.length && _currentChar() == 'i' && _isStandaloneI()) {
      isImaginary = true;
      _pos++;
    }

    if (!hasDigits) {
      throw FormatException('Expected number at position $start');
    }

    String numStr = expression.substring(start, isImaginary ? _pos - 1 : _pos);
    double value = double.parse(numStr);

    if (isImaginary) {
      return Complex(0, value);
    }

    return value;
  }

  String _currentChar() {
    if (_pos >= expression.length) return '';
    return expression[_pos];
  }

  bool _isDigit(String char) {
    return char.isNotEmpty && '0123456789'.contains(char);
  }

  bool _isLetter(String char) {
    return char.isNotEmpty && RegExp(r'[a-zA-Z]').hasMatch(char);
  }

  // Type conversion helpers
  double _toDouble(dynamic val) {
    if (val is double) return val;
    if (val is int) return val.toDouble();
    if (val is _PercentValue) return _toDouble(_percentToValue(val.value));
    if (val is Complex) return val.real;
    return 0.0;
  }

  Complex _toComplex(dynamic val) {
    if (val is Complex) return val;
    if (val is _PercentValue) return _toComplex(_percentToValue(val.value));
    if (val is double) return Complex(val, 0);
    if (val is int) return Complex(val.toDouble(), 0);
    return Complex(0, 0);
  }

  /// Simplify result - convert Complex with zero imaginary to double
  dynamic _simplifyResult(dynamic val) {
    if (val is Complex && val.imag.abs() < 1e-10) {
      return val.real;
    }
    return val;
  }

  dynamic _unwrapPercent(dynamic val) {
    if (val is _PercentValue) {
      return _percentToValue(val.value);
    }
    return val;
  }

  dynamic _finalizeResult(dynamic val) {
    return _simplifyResult(_unwrapPercent(val));
  }

  dynamic _percentToValue(dynamic val) {
    if (val is Complex) {
      return Complex(val.real / 100, val.imag / 100);
    }
    return _toDouble(val) / 100;
  }

  dynamic _percentOf(dynamic base, dynamic percentVal) {
    final Complex b = _toComplex(base);
    final Complex p = _toComplex(_percentToValue(percentVal));
    return b * p;
  }

  dynamic _negate(dynamic val) {
    if (val is Complex) {
      return Complex(-val.real, -val.imag);
    }
    return -_toDouble(val);
  }

  // Complex math operations
  Complex _complexExp(Complex z) {
    double expReal = exp(z.real);
    return Complex(expReal * cos(z.imag), expReal * sin(z.imag));
  }

  Complex _complexLn(Complex z) {
    return Complex(log(z.magnitude), z.phase);
  }

  Complex _complexSqrt(Complex z) {
    double r = z.magnitude;
    double theta = z.phase;
    double sqrtR = sqrt(r);
    return Complex(sqrtR * cos(theta / 2), sqrtR * sin(theta / 2));
  }

  Complex _complexPow(Complex base, Complex exponent) {
    if (base.real == 0 && base.imag == 0) {
      return Complex(0, 0);
    }
    // z^w = e^(w * ln(z))
    Complex lnBase = _complexLn(base);
    Complex product = exponent * lnBase;
    return _complexExp(product);
  }
}

// ============== COMPLEX NUMBER CLASS ==============

class Complex {
  final double real;
  final double imag;

  Complex(this.real, this.imag);

  Complex operator +(Complex other) =>
      Complex(real + other.real, imag + other.imag);
  Complex operator -(Complex other) =>
      Complex(real - other.real, imag - other.imag);
  Complex operator *(Complex other) => Complex(
    real * other.real - imag * other.imag,
    real * other.imag + imag * other.real,
  );
  Complex operator /(Complex other) {
    double denom = other.real * other.real + other.imag * other.imag;
    return Complex(
      (real * other.real + imag * other.imag) / denom,
      (imag * other.real - real * other.imag) / denom,
    );
  }

  double get magnitude => sqrt(real * real + imag * imag);
  double get phase => atan2(imag, real);

  @override
  String toString() {
    String realStr = _formatNum(real);
    String imagStr = _formatNum(imag.abs());
    if (imag >= 0) {
      return "$realStr + ${imagStr}i";
    } else {
      return "$realStr - ${imagStr}i";
    }
  }

  String _formatNum(double num) {
    if ((num - num.roundToDouble()).abs() < 1e-10) {
      return num.round().toString();
    }
    String formatted = num.toStringAsFixed(MathSolverNew.precision);
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    return formatted;
  }
}
