import 'package:klotter/math_engine/math_engine.dart';
import 'package:klotter/math_renderer/math_nodes.dart';
import 'package:klotter/math_renderer/math_text_style.dart';

List<MathNode> decimalizeExactNodes(List<MathNode> nodes) {
  final result = <MathNode>[];
  for (final node in nodes) {
    result.addAll(_decimalizeExactNode(node));
  }
  return result;
}

List<MathNode> _decimalizeExactNode(MathNode node) {
  if (node is FractionNode) {
    final numSplit = _splitLeadingNumericFactor(node.numerator);
    final denSplit = _splitLeadingNumericFactor(node.denominator);

    if (numSplit.hasNumeric || denSplit.hasNumeric) {
      final double denomCoeff =
          denSplit.coefficient == 0.0 ? 1.0 : denSplit.coefficient;
      final double coeff = numSplit.coefficient / denomCoeff;

      final numRemainder = decimalizeExactNodes(numSplit.remainder);
      final denRemainder = decimalizeExactNodes(denSplit.remainder);

      if (numRemainder.isEmpty && denRemainder.isEmpty) {
        return [LiteralNode(text: _formatDecimalNumber(coeff))];
      }

      final result = <MathNode>[];
      if (coeff != 1.0) {
        result.add(LiteralNode(text: _formatDecimalNumber(coeff)));
      }

      if (denRemainder.isEmpty) {
        result.addAll(numRemainder);
        return result;
      }

      final numNodes =
          numRemainder.isEmpty ? [LiteralNode(text: '1')] : numRemainder;
      result.add(FractionNode(num: numNodes, den: denRemainder));
      return result;
    }

    return [
      FractionNode(
        num: decimalizeExactNodes(node.numerator),
        den: decimalizeExactNodes(node.denominator),
      ),
    ];
  }

  if (node is ExponentNode) {
    return [
      ExponentNode(
        base: decimalizeExactNodes(node.base),
        power: decimalizeExactNodes(node.power),
      ),
    ];
  }

  if (node is RootNode) {
    return [
      RootNode(
        isSquareRoot: node.isSquareRoot,
        index: decimalizeExactNodes(node.index),
        radicand: decimalizeExactNodes(node.radicand),
      ),
    ];
  }

  if (node is LogNode) {
    return [
      LogNode(
        isNaturalLog: node.isNaturalLog,
        base: decimalizeExactNodes(node.base),
        argument: decimalizeExactNodes(node.argument),
      ),
    ];
  }

  if (node is TrigNode) {
    return [
      TrigNode(
        function: node.function,
        argument: decimalizeExactNodes(node.argument),
      ),
    ];
  }

  if (node is ParenthesisNode) {
    return [ParenthesisNode(content: decimalizeExactNodes(node.content))];
  }

  if (node is PermutationNode) {
    return [
      PermutationNode(
        n: decimalizeExactNodes(node.n),
        r: decimalizeExactNodes(node.r),
      ),
    ];
  }

  if (node is CombinationNode) {
    return [
      CombinationNode(
        n: decimalizeExactNodes(node.n),
        r: decimalizeExactNodes(node.r),
      ),
    ];
  }

  if (node is SummationNode) {
    return [
      SummationNode(
        variable: decimalizeExactNodes(node.variable),
        lower: decimalizeExactNodes(node.lower),
        upper: decimalizeExactNodes(node.upper),
        body: decimalizeExactNodes(node.body),
      ),
    ];
  }

  if (node is ProductNode) {
    return [
      ProductNode(
        variable: decimalizeExactNodes(node.variable),
        lower: decimalizeExactNodes(node.lower),
        upper: decimalizeExactNodes(node.upper),
        body: decimalizeExactNodes(node.body),
      ),
    ];
  }

  if (node is DerivativeNode) {
    return [
      DerivativeNode(
        variable: decimalizeExactNodes(node.variable),
        at: decimalizeExactNodes(node.at),
        body: decimalizeExactNodes(node.body),
        isDefinite: node.isDefinite,
      ),
    ];
  }

  if (node is IntegralNode) {
    return [
      IntegralNode(
        variable: decimalizeExactNodes(node.variable),
        lower: decimalizeExactNodes(node.lower),
        upper: decimalizeExactNodes(node.upper),
        body: decimalizeExactNodes(node.body),
        isDefinite: node.isDefinite,
      ),
    ];
  }

  if (node is ComplexNode) {
    return [ComplexNode(content: decimalizeExactNodes(node.content))];
  }

  if (node is AnsNode) {
    return [AnsNode(index: decimalizeExactNodes(node.index))];
  }

  if (node is ConstantNode) {
    return [ConstantNode(node.constant)];
  }

  if (node is ComplexVariableNode) {
    return [ComplexVariableNode()];
  }
  if (node is UnitVectorNode) {
    return [UnitVectorNode(node.axis)];
  }

  if (node is LiteralNode) {
    return [LiteralNode(text: node.text)];
  }

  if (node is NewlineNode) {
    return [NewlineNode()];
  }

  return [node];
}

double? _tryParseNumericLiteral(List<MathNode> nodes) {
  if (nodes.length != 1) return null;
  final node = nodes.first;
  if (node is! LiteralNode) return null;

  String text = node.text.trim();
  if (text.isEmpty) return null;

  text = text
      .replaceAll('\u2212', '-')
      .replaceAll('\u1D07', 'E')
      .replaceAll(',', '');

  return double.tryParse(text);
}

class _NumericFactorSplit {
  final double coefficient;
  final List<MathNode> remainder;
  final bool hasNumeric;

  const _NumericFactorSplit({
    required this.coefficient,
    required this.remainder,
    required this.hasNumeric,
  });
}

_NumericFactorSplit _splitLeadingNumericFactor(List<MathNode> nodes) {
  if (nodes.isEmpty) {
    return const _NumericFactorSplit(
      coefficient: 1.0,
      remainder: <MathNode>[],
      hasNumeric: false,
    );
  }

  final first = nodes.first;

  if (first is LiteralNode) {
    final num = _tryParseNumberString(first.text);
    if (num != null) {
      final remainder = _stripLeadingMultiply(nodes.sublist(1));
      return _NumericFactorSplit(
        coefficient: num,
        remainder: remainder,
        hasNumeric: true,
      );
    }
  }

  if (first is FractionNode) {
    final numVal = _tryParseNumericLiteral(first.numerator);
    final denVal = _tryParseNumericLiteral(first.denominator);
    if (numVal != null && denVal != null && denVal != 0.0) {
      final remainder = _stripLeadingMultiply(nodes.sublist(1));
      return _NumericFactorSplit(
        coefficient: numVal / denVal,
        remainder: remainder,
        hasNumeric: true,
      );
    }
  }

  return _NumericFactorSplit(
    coefficient: 1.0,
    remainder: nodes,
    hasNumeric: false,
  );
}

List<MathNode> _stripLeadingMultiply(List<MathNode> nodes) {
  if (nodes.isEmpty) return nodes;
  final first = nodes.first;
  if (first is LiteralNode) {
    final text = first.text.trim();
    if (text == MathTextStyle.multiplySign ||
        text == MathTextStyle.multiplyDot ||
        text == MathTextStyle.multiplyTimes ||
        text == '*' ||
        text == '·' ||
        text == '×') {
      return nodes.sublist(1);
    }
  }
  return nodes;
}

double? _tryParseNumberString(String text) {
  String normalized = text
      .trim()
      .replaceAll('\u2212', '-')
      .replaceAll('\u1D07', 'E')
      .replaceAll(',', '');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

String _formatDecimalNumber(double value) {
  return MathSolverNew.formatResult(value);
}
