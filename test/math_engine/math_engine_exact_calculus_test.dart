// ignore_for_file: no_leading_underscores_for_local_identifiers

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_engine/math_engine_exact.dart';
import 'package:klotter/math_renderer/math_editor_controller.dart';
import 'package:klotter/math_renderer/renderer.dart';

void main() {
  bool _hasPowOfVar(Expr expr, String name, int exponent) {
    bool found = false;
    void visit(Expr node) {
      if (found) return;
      if (node is PowExpr &&
          node.base is VarExpr &&
          node.exponent is IntExpr &&
          (node.base as VarExpr).name == name &&
          (node.exponent as IntExpr).value == BigInt.from(exponent)) {
        found = true;
        return;
      }
      if (node is ProdExpr) {
        for (final factor in node.factors) {
          visit(factor);
        }
      } else if (node is SumExpr) {
        for (final term in node.terms) {
          visit(term);
        }
      } else if (node is DivExpr) {
        visit(node.numerator);
        visit(node.denominator);
      }
    }

    visit(expr);
    return found;
  }

  bool _hasHalfFactor(Expr expr) {
    bool found = false;
    void visit(Expr node) {
      if (found) return;
      if (node is FracExpr) {
        if ((node.numerator).value == BigInt.one &&
            (node.denominator).value == BigInt.from(2)) {
          found = true;
          return;
        }
      }
      if (node is DivExpr &&
          node.denominator is IntExpr &&
          (node.denominator as IntExpr).value == BigInt.from(2)) {
        found = true;
        return;
      }
      if (node is ProdExpr) {
        for (final factor in node.factors) {
          visit(factor);
        }
      } else if (node is SumExpr) {
        for (final term in node.terms) {
          visit(term);
        }
      } else if (node is DivExpr) {
        visit(node.numerator);
        visit(node.denominator);
      }
    }

    visit(expr);
    return found;
  }

  String _toSubscript(int value) {
    const List<String> digits = [
      '\u2080',
      '\u2081',
      '\u2082',
      '\u2083',
      '\u2084',
      '\u2085',
      '\u2086',
      '\u2087',
      '\u2088',
      '\u2089',
    ];
    final String raw = value.toString();
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < raw.length; i++) {
      final int d = int.parse(raw[i]);
      buffer.write(digits[d]);
    }
    return buffer.toString();
  }

  bool _isIntegrationConstant(Expr expr, {int? index}) {
    if (expr is! VarExpr) return false;
    if (index != null) {
      return expr.name == 'c${_toSubscript(index)}';
    }
    return RegExp(r'^c[\u2080-\u2089]+$').hasMatch(expr.name);
  }

  bool _hasOneSixthFactor(Expr expr) {
    bool found = false;
    void visit(Expr node) {
      if (found) return;
      if (node is FracExpr) {
        if (node.numerator.value == BigInt.one &&
            node.denominator.value == BigInt.from(6)) {
          found = true;
          return;
        }
      }
      if (node is DivExpr &&
          node.denominator is IntExpr &&
          (node.denominator as IntExpr).value == BigInt.from(6)) {
        found = true;
        return;
      }
      if (node is ProdExpr) {
        for (final factor in node.factors) {
          visit(factor);
        }
      } else if (node is SumExpr) {
        for (final term in node.terms) {
          visit(term);
        }
      } else if (node is DivExpr) {
        visit(node.numerator);
        visit(node.denominator);
      }
    }

    visit(expr);
    return found;
  }

  double _evaluateExprWithBindings(Expr expr, Map<String, int> bindings) {
    final Map<String, Expr> exprBindings = {
      for (final entry in bindings.entries)
        entry.key: IntExpr.from(entry.value),
    };
    final Expr substituted =
        MathNodeToExpr.convert(
          expr.toMathNode(),
          varBindings: exprBindings,
        ).simplify();
    return substituted.toDouble();
  }

  bool _hasVariable(Expr expr, String name) {
    bool found = false;
    void visit(Expr node) {
      if (found) return;
      if (node is VarExpr && node.name == name) {
        found = true;
        return;
      }
      if (node is SumExpr) {
        for (final term in node.terms) {
          visit(term);
        }
      } else if (node is ProdExpr) {
        for (final factor in node.factors) {
          visit(factor);
        }
      } else if (node is DivExpr) {
        visit(node.numerator);
        visit(node.denominator);
      } else if (node is PowExpr) {
        visit(node.base);
        visit(node.exponent);
      }
    }

    visit(expr);
    return found;
  }

  bool _hasExplicitMultiplyNode(List<MathNode> nodes) {
    bool found = false;

    bool isMultiplyLiteral(String text) {
      final t = text.trim();
      return t == '·' || t == 'Â·' || t == '*' || t == '×' || t == 'Ã—';
    }

    void visit(List<MathNode> list) {
      for (final node in list) {
        if (found) return;

        if (node is LiteralNode) {
          if (isMultiplyLiteral(node.text)) {
            found = true;
            return;
          }
        } else if (node is FractionNode) {
          visit(node.numerator);
          visit(node.denominator);
        } else if (node is ExponentNode) {
          visit(node.base);
          visit(node.power);
        } else if (node is ParenthesisNode) {
          visit(node.content);
        } else if (node is TrigNode) {
          visit(node.argument);
        } else if (node is RootNode) {
          visit(node.index);
          visit(node.radicand);
        } else if (node is LogNode) {
          visit(node.base);
          visit(node.argument);
        } else if (node is PermutationNode) {
          visit(node.n);
          visit(node.r);
        } else if (node is CombinationNode) {
          visit(node.n);
          visit(node.r);
        } else if (node is SummationNode) {
          visit(node.variable);
          visit(node.lower);
          visit(node.upper);
          visit(node.body);
        } else if (node is DerivativeNode) {
          visit(node.variable);
          visit(node.at);
          visit(node.body);
        } else if (node is IntegralNode) {
          visit(node.variable);
          visit(node.lower);
          visit(node.upper);
          visit(node.body);
        } else if (node is ProductNode) {
          visit(node.variable);
          visit(node.lower);
          visit(node.upper);
          visit(node.body);
        } else if (node is ComplexNode) {
          visit(node.content);
        } else if (node is AnsNode) {
          visit(node.index);
        }
      }
    }

    visit(nodes);
    return found;
  }

  group('ExactMathEngine - Implicit Multiplication', () {
    test('splits xy into x * y', () {
      final expr = MathNodeToExpr.convert([LiteralNode(text: 'xy')]);
      expect(expr, isA<ProdExpr>());
      final prod = expr as ProdExpr;
      expect(prod.factors.length, equals(2));
      expect(prod.factors[0], isA<VarExpr>());
      expect(prod.factors[1], isA<VarExpr>());
      expect((prod.factors[0] as VarExpr).name, equals('x'));
      expect((prod.factors[1] as VarExpr).name, equals('y'));
    });

    test('combines like variables into powers', () {
      final simplified = ProdExpr([VarExpr('y'), VarExpr('y')]).simplify();
      expect(simplified, isA<PowExpr>());
      final pow = simplified as PowExpr;
      expect(pow.base, isA<VarExpr>());
      expect((pow.base as VarExpr).name, equals('y'));
      expect(pow.exponent, isA<IntExpr>());
      expect((pow.exponent as IntExpr).value, equals(BigInt.from(2)));
    });
  });

  group('ExactMathEngine - Calculus', () {
    test('editor builds 52xy^2 as 52*x*y^2', () {
      final controller = MathEditorController();
      for (final ch in ['5', '2', 'x', 'y', '^', '2']) {
        controller.insertCharacter(ch);
      }
      final expr = MathNodeToExpr.convert(controller.expression).simplify();
      expect(expr, isA<ProdExpr>());
      final prod = expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) => factor is IntExpr && factor.value == BigInt.from(52),
        ),
        isTrue,
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
      );
      expect(
        prod.factors.any(
          (factor) =>
              factor is PowExpr &&
              factor.base is VarExpr &&
              (factor.base as VarExpr).name == 'y' &&
              factor.exponent is IntExpr &&
              (factor.exponent as IntExpr).value == BigInt.from(2),
        ),
        isTrue,
      );
    });

    test('derivative of 52xy^2 returns 52y^2', () {
      final controller = MathEditorController();
      for (final ch in ['5', '2', 'x', 'y', '^', '2']) {
        controller.insertCharacter(ch);
      }
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: controller.expression,
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      final expr = result.expr!.simplify();
      expect(expr, isA<ProdExpr>());
      final prod = expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) => factor is IntExpr && factor.value == BigInt.from(52),
        ),
        isTrue,
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isFalse,
      );
      expect(
        prod.factors.any(
          (factor) =>
              factor is PowExpr &&
              factor.base is VarExpr &&
              (factor.base as VarExpr).name == 'y' &&
              factor.exponent is IntExpr &&
              (factor.exponent as IntExpr).value == BigInt.from(2),
        ),
        isTrue,
      );
    });

    test('integral of xy^2 returns (x^2*y^2)/2 + c₀', () {
      final controller = MathEditorController();
      for (final ch in ['x', 'y', '^', '2']) {
        controller.insertCharacter(ch);
      }
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: controller.expression,
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      expect(
        sum.terms.any((term) => _isIntegrationConstant(term, index: 0)),
        isTrue,
      );
      final nonConstant = sum.terms.firstWhere(
        (term) => !_isIntegrationConstant(term),
      );
      expect(_hasPowOfVar(nonConstant, 'x', 2), isTrue);
      expect(_hasPowOfVar(nonConstant, 'y', 2), isTrue);
      expect(_hasHalfFactor(nonConstant), isTrue);
    });

    test('indefinite integral in compound expression (+ 4) includes + c₀', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x')],
        ),
        LiteralNode(text: '+'),
        LiteralNode(text: '4'),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      // Should have x^2/2, 4, and c₀
      expect(sum.terms.any((t) => _isIntegrationConstant(t, index: 0)), isTrue);
      expect(
        sum.terms.any((t) => t is IntExpr && t.value == BigInt.from(4)),
        isTrue,
      );
      final xPart = sum.terms.firstWhere(
        (t) =>
            !_isIntegrationConstant(t) &&
            (t is! IntExpr || t.value != BigInt.from(4)),
      );
      expect(_hasPowOfVar(xPart, 'x', 2), isTrue);
    });

    test('evaluates derivative diff(x,2,x^2) = 4', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '2')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, isNotNull);
      expect(result.numerical!, closeTo(4.0, 1e-3));
    });

    test('derivative without evaluation point returns symbolic', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<ProdExpr>());
      final prod = result.expr as ProdExpr;
      expect(prod.factors.length, equals(2));
      expect(prod.factors[0], isA<IntExpr>());
      expect((prod.factors[0] as IntExpr).value, equals(BigInt.from(2)));
      expect(prod.factors[1], isA<VarExpr>());
      expect((prod.factors[1] as VarExpr).name, equals('x'));
    });

    test('derivative of 3x^2 returns 6x', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: '3x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<ProdExpr>());
      final prod = result.expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) => factor is IntExpr && factor.value == BigInt.from(6),
        ),
        isTrue,
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
      );
    });

    test('derivative of 3*x^2 with structured ExponentNode returns 6x', () {
      // This tests how the UI would structure 3x^2:
      // LiteralNode('3') followed by ExponentNode(base: x, power: 2)
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [
            LiteralNode(text: '3'),
            ExponentNode(
              base: [LiteralNode(text: 'x')],
              power: [LiteralNode(text: '2')],
            ),
          ],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      // Should be 6x, not 18x
      expect(result.expr, isA<ProdExpr>());
      final prod = result.expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) => factor is IntExpr && factor.value == BigInt.from(6),
        ),
        isTrue,
        reason: 'Expected coefficient 6 for derivative of 3x^2',
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
        reason: 'Expected variable x in derivative of 3x^2',
      );
    });

    test('derivative of (3x)^2 returns 18x', () {
      // This tests the case where 3x is all in the base: (3x)^2
      // Derivative should be 2*(3x)*3 = 18x
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [
            ExponentNode(
              base: [LiteralNode(text: '3x')],
              power: [LiteralNode(text: '2')],
            ),
          ],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      // Should be 18x for (3x)^2
      expect(result.expr, isA<ProdExpr>());
      final prod = result.expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) => factor is IntExpr && factor.value == BigInt.from(18),
        ),
        isTrue,
        reason: 'Expected coefficient 18 for derivative of (3x)^2',
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'x'),
        isTrue,
        reason: 'Expected variable x in derivative of (3x)^2',
      );
    });

    test('evaluates integral int(x,0,1,x) = 0.5', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, isNotNull);
      expect(result.numerical!, closeTo(0.5, 1e-3));
    });

    test('integral handles reversed bounds', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '0')],
          body: [LiteralNode(text: 'x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.numerical, isNotNull);
      expect(result.numerical!, closeTo(-0.5, 1e-3));
    });

    test('indefinite integral returns symbolic + c₀', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      expect(
        sum.terms.any((term) => _isIntegrationConstant(term, index: 0)),
        isTrue,
      );
      expect(sum.terms.any((term) => term is DivExpr), isTrue);
    });

    test('indefinite integral of 3x^2+3 returns x^3+3x+c₀', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: '3x^2+3')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      expect(
        sum.terms.any((term) => _isIntegrationConstant(term, index: 0)),
        isTrue,
      );
      expect(
        sum.terms.any(
          (term) =>
              term is PowExpr &&
              term.base is VarExpr &&
              (term.base as VarExpr).name == 'x' &&
              term.exponent is IntExpr &&
              (term.exponent as IntExpr).value == BigInt.from(3),
        ),
        isTrue,
      );
      expect(
        sum.terms.any(
          (term) =>
              term is ProdExpr &&
              term.factors.any(
                (factor) => factor is IntExpr && factor.value == BigInt.from(3),
              ) &&
              term.factors.any(
                (factor) => factor is VarExpr && factor.name == 'x',
              ),
        ),
        isTrue,
      );
    });

    test('indefinite integral of x*x^2 returns x^4/4+c₀', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x*x^2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      expect(
        sum.terms.any((term) => _isIntegrationConstant(term, index: 0)),
        isTrue,
      );
      expect(_hasPowOfVar(sum, 'x', 4), isTrue);
    });

    test('integral reduces repeating decimals to simple fraction', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '0')],
          upper: [LiteralNode(text: '1')],
          body: [LiteralNode(text: 'x^2+2x')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.mathNodes, isNotNull);
      final frac = result.mathNodes!.whereType<FractionNode>().first;
      expect((frac.numerator.first as LiteralNode).text, equals('4'));
      expect((frac.denominator.first as LiteralNode).text, equals('3'));
    });

    test('summation combines like terms into a single coefficient', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '2')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'xy/2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      final expr = result.expr!.simplify();
      expect(expr, isA<ProdExpr>());
      final prod = expr as ProdExpr;
      expect(
        prod.factors.any(
          (factor) =>
              factor is FracExpr &&
              factor.numerator.value == BigInt.from(5) &&
              factor.denominator.value == BigInt.from(2),
        ),
        isTrue,
      );
      expect(
        prod.factors.any((factor) => factor is VarExpr && factor.name == 'y'),
        isTrue,
      );
    });

    test('derivative combines like terms with fractional coefficients', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'xy/2+xy/2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      final expr = result.expr!.simplify();
      expect(expr, isA<VarExpr>());
      final v = expr as VarExpr;
      expect(v.name, equals('y'));
    });

    test('integral combines like terms before adding constant', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'xy/2+xy/2')],
        ),
      ];
      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      final sum = result.expr as SumExpr;
      final nonConstant = sum.terms.where(
        (term) => !_isIntegrationConstant(term),
      );
      expect(nonConstant.length, equals(1));
      final term = nonConstant.first;
      expect(_hasPowOfVar(term, 'x', 2), isTrue);
      expect(
        term is ProdExpr &&
            term.factors.any(
              (factor) => factor is VarExpr && factor.name == 'y',
            ),
        isTrue,
      );
      expect(_hasHalfFactor(term), isTrue);
    });

    test('double integral of x returns x^3/6 + c₀x + c₁', () {
      final inner = IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '')],
        upper: [LiteralNode(text: '')],
        body: [LiteralNode(text: 'x')],
      );
      final outer = IntegralNode(
        variable: [LiteralNode(text: 'x')],
        lower: [LiteralNode(text: '')],
        upper: [LiteralNode(text: '')],
        body: [inner],
      );

      final result = ExactMathEngine.evaluate([outer]);
      expect(result.expr, isNotNull);
      expect(result.expr, isA<SumExpr>());
      expect(result.mathNodes, isNotNull);
      expect(_hasExplicitMultiplyNode(result.mathNodes!), isFalse);

      final sum = result.expr as SumExpr;
      expect(_hasVariable(sum, 'c${_toSubscript(0)}'), isTrue);
      expect(_hasVariable(sum, 'c${_toSubscript(1)}'), isTrue);

      expect(_hasPowOfVar(sum, 'x', 3), isTrue);
      expect(_hasOneSixthFactor(sum), isTrue);
      expect(
        sum.terms.any(
          (term) =>
              term is ProdExpr &&
              term.factors.any(
                (f) => f is VarExpr && f.name == 'c${_toSubscript(0)}',
              ) &&
              term.factors.any((f) => f is VarExpr && f.name == 'x'),
        ),
        isTrue,
      );
    });

    test('integration constants reset per evaluation call', () {
      final nodes = [
        IntegralNode(
          variable: [LiteralNode(text: 'x')],
          lower: [LiteralNode(text: '')],
          upper: [LiteralNode(text: '')],
          body: [LiteralNode(text: 'x')],
        ),
      ];

      final first = ExactMathEngine.evaluate(nodes);
      final second = ExactMathEngine.evaluate(nodes);

      expect(first.expr, isA<SumExpr>());
      expect(second.expr, isA<SumExpr>());

      final firstSum = first.expr as SumExpr;
      final secondSum = second.expr as SumExpr;

      expect(
        firstSum.terms.any((t) => _isIntegrationConstant(t, index: 0)),
        isTrue,
      );
      expect(
        secondSum.terms.any((t) => _isIntegrationConstant(t, index: 0)),
        isTrue,
      );
      expect(
        firstSum.terms.any((t) => _isIntegrationConstant(t, index: 1)),
        isFalse,
      );
      expect(
        secondSum.terms.any((t) => _isIntegrationConstant(t, index: 1)),
        isFalse,
      );
    });

    test(
      'derivative with multiple variables keeps non-target variables symbolic',
      () {
        final nodes = [
          DerivativeNode(
            variable: [LiteralNode(text: 'x')],
            at: [LiteralNode(text: '')],
            body: [LiteralNode(text: 'xy+yz+x^2z')],
          ),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.expr, isNotNull);

        final Expr expr = result.expr!.simplify();
        final double numeric = _evaluateExprWithBindings(expr, {
          'x': 2,
          'y': 3,
          'z': 5,
        });

        // y + 2xz at x=2, y=3, z=5 -> 3 + 20 = 23
        expect(numeric, equals(23.0));
      },
    );

    test(
      'evaluated derivative substitutes target variable while preserving others',
      () {
        final nodes = [
          DerivativeNode(
            variable: [LiteralNode(text: 'x')],
            at: [LiteralNode(text: '9')],
            body: [LiteralNode(text: 'x^2y')],
          ),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.expr, isNotNull);

        final Expr expr = result.expr!.simplify();
        expect(_hasVariable(expr, 'x'), isFalse);
        expect(_hasVariable(expr, 'y'), isTrue);
        expect(_evaluateExprWithBindings(expr, {'y': 4}), equals(72.0));
      },
    );

    test(
      'double mixed partial derivative handles cross-variable evaluation',
      () {
        final nodes = [
          DerivativeNode(
            variable: [LiteralNode(text: 'x')],
            at: [LiteralNode(text: '')],
            body: [
              DerivativeNode(
                variable: [LiteralNode(text: 'y')],
                at: [LiteralNode(text: '2')],
                body: [LiteralNode(text: 'x^2y^3z^4')],
              ),
            ],
          ),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.expr, isNotNull);

        final Expr expr = result.expr!.simplify();
        expect(_hasVariable(expr, 'y'), isFalse);
        expect(_hasVariable(expr, 'x'), isTrue);
        expect(_hasVariable(expr, 'z'), isTrue);
        expect(_evaluateExprWithBindings(expr, {'x': 3, 'z': 2}), equals(1152));
      },
    );

    test(
      'triple mixed partial derivative produces expected symbolic result',
      () {
        final nodes = [
          DerivativeNode(
            variable: [LiteralNode(text: 'x')],
            at: [LiteralNode(text: '')],
            body: [
              DerivativeNode(
                variable: [LiteralNode(text: 'y')],
                at: [LiteralNode(text: '')],
                body: [
                  DerivativeNode(
                    variable: [LiteralNode(text: 'z')],
                    at: [LiteralNode(text: '')],
                    body: [LiteralNode(text: 'x^2y^3z^4')],
                  ),
                ],
              ),
            ],
          ),
        ];

        final result = ExactMathEngine.evaluate(nodes);
        expect(result.expr, isNotNull);

        final Expr expr = result.expr!.simplify();
        expect(_evaluateExprWithBindings(expr, {'x': 1, 'y': 1, 'z': 1}), 24.0);
        expect(
          _evaluateExprWithBindings(expr, {'x': 2, 'y': 3, 'z': 4}),
          27648.0,
        );
      },
    );

    test('triple mixed partial derivative respects all evaluation points', () {
      final nodes = [
        DerivativeNode(
          variable: [LiteralNode(text: 'x')],
          at: [LiteralNode(text: '4')],
          body: [
            DerivativeNode(
              variable: [LiteralNode(text: 'y')],
              at: [LiteralNode(text: '3')],
              body: [
                DerivativeNode(
                  variable: [LiteralNode(text: 'z')],
                  at: [LiteralNode(text: '2')],
                  body: [LiteralNode(text: 'x^2y^3z^4')],
                ),
              ],
            ),
          ],
        ),
      ];

      final result = ExactMathEngine.evaluate(nodes);
      final double value =
          result.numerical ?? result.expr!.simplify().toDouble();
      expect(value, equals(6912.0));
      if (result.expr != null) {
        expect(_hasVariable(result.expr!.simplify(), 'x'), isFalse);
        expect(_hasVariable(result.expr!.simplify(), 'y'), isFalse);
        expect(_hasVariable(result.expr!.simplify(), 'z'), isFalse);
      }
    });

    test('summation with multiple variables scales each symbolic term', () {
      final nodes = [
        SummationNode(
          variable: [LiteralNode(text: 'i')],
          lower: [LiteralNode(text: '1')],
          upper: [LiteralNode(text: '3')],
          body: [LiteralNode(text: 'iy+z')],
        ),
      ];

      final result = ExactMathEngine.evaluate(nodes);
      expect(result.expr, isNotNull);

      final Expr expr = result.expr!.simplify();
      final double numeric = _evaluateExprWithBindings(expr, {'y': 2, 'z': 3});

      // (1y+z) + (2y+z) + (3y+z) = 6y + 3z -> 6*2 + 3*3 = 21
      expect(numeric, equals(21.0));
    });
  });
}
