import 'package:flutter/material.dart';
import 'sumprod_symbol.dart';
import 'dart:math' as math;
import 'math_nodes.dart';
import 'math_text_style.dart';
import '../utils/constants.dart';

/// A read-only widget for displaying MathNode results (no editing, no cursor)
class MathResultDisplay extends StatelessWidget {
  final List<MathNode> nodes;
  final double fontSize;
  final Color textColor;
  final TextScaler textScaler;

  const MathResultDisplay({
    super.key,
    required this.nodes,
    this.fontSize = FONTSIZE,
    this.textColor = Colors.white,
    this.textScaler = TextScaler.noScaling,
  });

  /// Calculate estimated total height of a node list given a font size.
  static double calculateTotalHeight(List<MathNode> nodes, double fontSize) {
    if (nodes.isEmpty) return 0;
    final lines = _staticSplitIntoLines(nodes);
    double total = 0;
    for (int i = 0; i < lines.length; i++) {
      total +=
          calculateLineHeight(lines[i], fontSize) +
          6; // Padding(vertical: 3) on each line
    }
    return total;
  }

  /// Estimate height for plain text (supports newline-separated lines).
  static double calculateTextHeight(String text, double fontSize) {
    if (text.isEmpty) return 0;
    final nodes = _staticTextToNodes(text);
    return calculateTotalHeight(nodes, fontSize);
  }

  /// Calculate estimated height of a single line of nodes.
  static double calculateLineHeight(List<MathNode> nodes, double fontSize) {
    if (nodes.isEmpty) return fontSize;
    double maxAbove = 0;
    double maxBelow = 0;
    for (final node in nodes) {
      final (height, offset) = _staticGetNodeMetrics(node, fontSize);
      if (height > 0) {
        maxAbove = math.max(maxAbove, height - offset);
        maxBelow = math.max(maxBelow, offset);
      }
    }
    return maxAbove + maxBelow;
  }

  static List<List<MathNode>> _staticSplitIntoLines(List<MathNode> nodes) {
    List<List<MathNode>> lines = [];
    List<MathNode> currentLine = [];
    for (var node in nodes) {
      if (node is NewlineNode) {
        lines.add(List.from(currentLine));
        currentLine = [];
      } else {
        currentLine.add(node);
      }
    }
    lines.add(currentLine);
    return lines;
  }

  static List<MathNode> _staticTextToNodes(String text) {
    final lines = text.split('\n');
    final nodes = <MathNode>[];
    for (int i = 0; i < lines.length; i++) {
      nodes.add(LiteralNode(text: lines[i]));
      if (i < lines.length - 1) {
        nodes.add(NewlineNode());
      }
    }
    return nodes;
  }

  static bool _isListEffectivelyEmpty(List<MathNode> nodes) {
    if (nodes.isEmpty) return true;
    if (nodes.length == 1 && nodes.first is LiteralNode) {
      return (nodes.first as LiteralNode).text.trim().isEmpty;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return const SizedBox.shrink();
    }

    final lines = _splitIntoLines(nodes);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children:
          lines.map((line) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(line, fontSize),
              ),
            );
          }).toList(),
    );
  }

  List<List<MathNode>> _splitIntoLines(List<MathNode> nodes) {
    List<List<MathNode>> lines = [];
    List<MathNode> currentLine = [];

    for (var node in nodes) {
      if (node is NewlineNode) {
        lines.add(List.from(currentLine));
        currentLine = [];
      } else {
        currentLine.add(node);
      }
    }
    lines.add(currentLine);
    return lines;
  }

  List<Widget> _renderNodeList(List<MathNode> nodes, double fontSize) {
    if (nodes.isEmpty) return [];

    double maxAbove = 0;
    double maxBelow = 0;

    for (final node in nodes) {
      final (height, offset) = _getNodeMetrics(node, fontSize);
      if (height > 0) {
        maxAbove = math.max(maxAbove, height - offset);
        maxBelow = math.max(maxBelow, offset);
      }
    }

    return nodes.asMap().entries.map((e) {
      final node = e.value;
      final (height, offset) = _getNodeMetrics(node, fontSize);
      final topPadding = maxAbove - (height - offset);

      return Padding(
        padding: EdgeInsets.only(
          left: 1.5,
          right: 1.5,
          top: math.max(0, topPadding),
        ),
        child: _renderNode(node, fontSize),
      );
    }).toList();
  }

  Widget _renderNode(MathNode node, double fontSize) {
    if (node is LiteralNode) {
      if (node.text.isEmpty) {
        return const SizedBox.shrink();
      }
      return Text(
        MathTextStyle.toDisplayText(node.text),
        style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
        textScaler: textScaler,
      );
    }

    if (node is ConstantNode) {
      return Text(
        MathTextStyle.toDisplayText(node.constant),
        style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
        textScaler: textScaler,
      );
    }
    if (node is UnitVectorNode) {
      return _UnitVectorWidget(
        axis: node.axis,
        fontSize: fontSize,
        color: textColor,
      );
    }

    if (node is FractionNode) {
      return IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _renderNodeList(node.numerator, fontSize),
            ),
            Container(
              height: math.max(1.5, fontSize * 0.06),
              width: double.infinity,
              color: textColor,
              margin: EdgeInsets.symmetric(vertical: fontSize * 0.15),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _renderNodeList(node.denominator, fontSize),
            ),
          ],
        ),
      );
    }

    if (node is ExponentNode) {
      final double powerSize =
          fontSize < FONTSIZE * 0.85 ? fontSize : fontSize * 0.8;
      final double fixedOffset = fontSize * -0.5;

      final powerMetrics = _getListMetrics(node.power, powerSize);
      final double powerHeight = powerMetrics.$1;
      final double baseTopPadding = powerHeight + fixedOffset;

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: baseTopPadding),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _renderNodeList(node.base, fontSize),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _renderNodeList(node.power, powerSize),
          ),
        ],
      );
    }

    if (node is RootNode) {
      final double indexSize = fontSize * 0.7;
      final double minRadicandHeight = fontSize * 1.2;

      Widget? indexWidget;
      if (!node.isSquareRoot) {
        indexWidget = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _renderNodeList(node.index, indexSize),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (indexWidget != null)
            Padding(
              padding: const EdgeInsets.only(right: 1),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [indexWidget, SizedBox(height: fontSize * 0.35)],
              ),
            ),
          IntrinsicHeight(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minRadicandHeight),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: fontSize * 0.6,
                    child: CustomPaint(
                      painter: _RadicalPainter(
                        color: textColor,
                        strokeWidth: math.max(1.5, fontSize * 0.06),
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: textColor,
                          width: math.max(1.5, fontSize * 0.06),
                        ),
                      ),
                    ),
                    padding: EdgeInsets.only(
                      left: 3,
                      right: 4,
                      top: fontSize * 0.08,
                      bottom: 2,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: _renderNodeList(node.radicand, fontSize),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (node is LogNode) {
      final double baseSize = fontSize * 0.8;

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            node.isNaturalLog ? 'ln' : 'log',
            style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
            textScaler: textScaler,
          ),
          if (!node.isNaturalLog)
            Padding(
              padding: EdgeInsets.only(left: 1, top: fontSize * 0.5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.base, baseSize),
              ),
            ),
          if (node.isNaturalLog) SizedBox(width: fontSize * 0.05),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScalableParenthesis(
                  isOpening: true,
                  fontSize: fontSize,
                  color: textColor,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: fontSize * 0.08,
                    vertical: fontSize * 0.1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(node.argument, fontSize),
                  ),
                ),
                _ScalableParenthesis(
                  isOpening: false,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (node is TrigNode) {
      final bool isAbs = node.function.toLowerCase() == 'abs';

      if (isAbs) {
        return IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScalableAbsBar(fontSize: fontSize, color: textColor),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: fontSize * 0.15,
                  vertical: fontSize * 0.1,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderNodeList(node.argument, fontSize),
                ),
              ),
              _ScalableAbsBar(fontSize: fontSize, color: textColor),
            ],
          ),
        );
      }

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            node.function,
            style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
            textScaler: textScaler,
          ),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScalableParenthesis(
                  isOpening: true,
                  fontSize: fontSize,
                  color: textColor,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: fontSize * 0.25,
                    vertical: fontSize * 0.1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(node.argument, fontSize),
                  ),
                ),
                _ScalableParenthesis(
                  isOpening: false,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (node is ParenthesisNode) {
      return IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ScalableParenthesis(
              isOpening: true,
              fontSize: fontSize,
              color: textColor,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: fontSize * 0.15,
                vertical: fontSize * 0.1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.content, fontSize),
              ),
            ),
            _ScalableParenthesis(
              isOpening: false,
              fontSize: fontSize,
              color: textColor,
            ),
          ],
        ),
      );
    }

    if (node is PermutationNode) {
      final double smallSize = fontSize * 0.8;

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.n, smallSize),
              ),
              SizedBox(height: fontSize * 0.8),
            ],
          ),
          Text(
            'P',
            style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
            textScaler: textScaler,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: fontSize * 0.8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.r, smallSize),
              ),
            ],
          ),
        ],
      );
    }

    if (node is CombinationNode) {
      final double smallSize = fontSize * 0.8;

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.n, smallSize),
              ),
              SizedBox(height: fontSize * 1.0),
            ],
          ),
          Text(
            'C',
            style: MathTextStyle.getStyle(fontSize).copyWith(color: textColor),
            textScaler: textScaler,
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: fontSize * 0.8),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(node.r, smallSize),
              ),
            ],
          ),
        ],
      );
    }

    if (node is SummationNode || node is ProductNode) {
      final bool isSum = node is SummationNode;
      final double smallSize = fontSize * 0.7;
      final variable = isSum ? (node).variable : (node as ProductNode).variable;
      final lower = isSum ? (node).lower : (node as ProductNode).lower;
      final upper = isSum ? (node).upper : (node as ProductNode).upper;
      final body = isSum ? (node).body : (node as ProductNode).body;

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(upper, smallSize),
              ),
              SizedBox(height: fontSize * 0.1),
              SumProdSymbol(
                type: isSum ? SumProdType.sum : SumProdType.product,
                fontSize: fontSize,
                color: textColor,
              ),
              SizedBox(height: fontSize * 0.1),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(variable, smallSize),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '=',
                      style: MathTextStyle.getStyle(
                        smallSize,
                      ).copyWith(color: textColor),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(lower, smallSize),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(width: fontSize * 0.2),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScalableParenthesis(
                  isOpening: true,
                  fontSize: fontSize,
                  color: textColor,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: fontSize * 0.15),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(body, fontSize),
                  ),
                ),
                _ScalableParenthesis(
                  isOpening: false,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (node is DerivativeNode) {
      final double symbolSize = fontSize;
      final double evalSize = fontSize * 0.7;
      final double barHeight = math.max(2.0, symbolSize * 0.08);
      final double barMargin = symbolSize * 0.06;
      final variable = node.variable;
      final at = node.at;
      final body = node.body;
      final bool atEmpty = _isListEffectivelyEmpty(at);

      final Widget fraction = IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'd',
                  style: MathTextStyle.getStyle(
                    symbolSize,
                  ).copyWith(color: textColor),
                  textScaler: textScaler,
                ),
              ],
            ),
            Container(
              height: barHeight,
              width: double.infinity,
              color: textColor,
              margin: EdgeInsets.symmetric(vertical: barMargin),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'd',
                  style: MathTextStyle.getStyle(
                    symbolSize,
                  ).copyWith(color: textColor),
                  textScaler: textScaler,
                ),
                const SizedBox(width: 1),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderNodeList(variable, symbolSize),
                ),
              ],
            ),
          ],
        ),
      );

      final Widget evalWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _renderNodeList(variable, evalSize),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              '=',
              style: MathTextStyle.getStyle(
                evalSize,
              ).copyWith(color: textColor),
              textScaler: textScaler,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _renderNodeList(at, evalSize),
          ),
        ],
      );

      final bodyMetrics = _getListMetrics(body, fontSize);
      final double bodyHeight = bodyMetrics.$1;

      final numMetrics = _getListMetrics([LiteralNode(text: 'd')], symbolSize);
      final varMetrics = _getListMetrics(variable, symbolSize);
      final double denHeight = math.max(numMetrics.$1, varMetrics.$1);
      final double fracHeight =
          numMetrics.$1 + barMargin + barHeight + barMargin + denHeight;
      final double operatorHeight = math.max(fracHeight, bodyHeight);

      final double barWidth = math.max(1.2, evalSize * 0.08);

      final Widget evalHolder = SizedBox(
        height: operatorHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: barWidth, color: textColor),
            SizedBox(width: evalSize * 0.15),
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [evalWidget],
            ),
          ],
        ),
      );

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          fraction,
          SizedBox(width: fontSize * 0.2),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScalableParenthesis(
                  isOpening: true,
                  fontSize: fontSize,
                  color: textColor,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: fontSize * 0.15),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(body, fontSize),
                  ),
                ),
                _ScalableParenthesis(
                  isOpening: false,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ],
            ),
          ),
          if (!atEmpty) ...[SizedBox(width: fontSize * 0.1), evalHolder],
        ],
      );
    }

    if (node is IntegralNode) {
      final double boundSize = fontSize * 0.7;
      final double dxSize = fontSize;
      final double lowerGap = fontSize * 0.18;
      final variable = node.variable;
      final lower = node.lower;
      final upper = node.upper;
      final body = node.body;

      final bodyMetrics = _getListMetrics(body, fontSize);
      final double bodyHeight = bodyMetrics.$1;

      final Widget dxWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'd',
            style: MathTextStyle.getStyle(dxSize).copyWith(color: textColor),
            textScaler: textScaler,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _renderNodeList(variable, dxSize),
          ),
        ],
      );

      final Widget alignedDxWidget = SizedBox(
        height: bodyHeight + fontSize * 0.2,
        child: Align(alignment: Alignment.bottomCenter, child: dxWidget),
      );

      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(upper, boundSize),
              ),
              SizedBox(height: fontSize * 0.05),
              Text(
                '\u222B',
                style: MathTextStyle.getStyle(
                  fontSize * 1.4,
                ).copyWith(color: textColor),
                textScaler: textScaler,
              ),
              SizedBox(height: lowerGap),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(lower, boundSize),
              ),
            ],
          ),
          SizedBox(width: fontSize * 0.2),
          IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ScalableParenthesis(
                  isOpening: true,
                  fontSize: fontSize,
                  color: textColor,
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: fontSize * 0.15,
                    vertical: fontSize * 0.1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(body, fontSize),
                  ),
                ),
                _ScalableParenthesis(
                  isOpening: false,
                  fontSize: fontSize,
                  color: textColor,
                ),
              ],
            ),
          ),
          SizedBox(width: fontSize * 0.1),
          alignedDxWidget,
        ],
      );
    }

    if (node is ComplexNode) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ..._renderNodeList(node.content, fontSize),
          Text(
            'i',
            style: MathTextStyle.getStyle(
              fontSize,
            ).copyWith(color: textColor, fontStyle: FontStyle.italic),
            textScaler: textScaler,
          ),
        ],
      );
    }

    if (node is AnsNode) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'ans',
            style: MathTextStyle.getStyle(
              fontSize,
            ).copyWith(color: Colors.orangeAccent),
            textScaler: textScaler,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _renderNodeList(node.index, fontSize),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  static (double, double) _staticGetNodeMetrics(
    MathNode node,
    double fontSize,
  ) {
    if (node is LiteralNode) {
      return (fontSize, fontSize * 0.5);
    }

    if (node is ConstantNode) {
      return (fontSize, fontSize * 0.5);
    }
    if (node is UnitVectorNode) {
      return (fontSize, fontSize / 2);
    }

    if (node is ExponentNode) {
      final double powerSize =
          fontSize < FONTSIZE * 0.85 ? fontSize : fontSize * 0.8;
      final baseMetrics = _staticGetListMetrics(node.base, fontSize);
      final powerMetrics = _staticGetListMetrics(node.power, powerSize);
      final double baseHeight = baseMetrics.$1;
      final double baseRef = baseMetrics.$2;
      final double powerHeight = powerMetrics.$1;
      final double fixedOffset = fontSize * -0.5;
      final double totalHeight = baseHeight + fixedOffset + powerHeight;
      return (totalHeight, baseRef);
    }

    if (node is FractionNode) {
      final numMetrics = _staticGetListMetrics(node.numerator, fontSize);
      final denMetrics = _staticGetListMetrics(node.denominator, fontSize);
      final double barHeight = math.max(1.5, fontSize * 0.06);
      final double margin = fontSize * 0.15;
      final numHeight = math.max(numMetrics.$1, fontSize * 0.8);
      final denHeight = math.max(denMetrics.$1, fontSize * 0.8);
      final height = numHeight + margin + barHeight + margin + denHeight;
      final offset = denHeight + margin + barHeight / 2;
      return (height, offset);
    }

    if (node is RootNode) {
      final radicandMetrics = _staticGetListMetrics(node.radicand, fontSize);
      final double minHeight = fontSize * 1.2;
      final double topPad = fontSize * 0.08;
      final double bottomPad = 2.0;
      final height = math.max(
        minHeight,
        radicandMetrics.$1 + topPad + bottomPad,
      );
      return (height, bottomPad + radicandMetrics.$2);
    }

    if (node is ParenthesisNode) {
      final contentMetrics = _staticGetListMetrics(node.content, fontSize);
      final double vPadding = fontSize * 0.1;
      final height = math.max(fontSize, contentMetrics.$1 + vPadding * 2);
      final offset = vPadding + contentMetrics.$2;
      return (height, offset);
    }

    if (node is TrigNode) {
      final argMetrics = _staticGetListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final height = math.max(fontSize, argMetrics.$1 + vPadding * 2);
      return (height, vPadding + argMetrics.$2);
    }

    if (node is LogNode) {
      final argMetrics = _staticGetListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final double argAreaHeight = argMetrics.$1 + vPadding * 2;
      double subscriptExtent = 0;
      if (!node.isNaturalLog) {
        final baseSize = fontSize * 0.8;
        final baseMetrics = _staticGetListMetrics(node.base, baseSize);
        subscriptExtent =
            fontSize * 0.5 +
            math.max(baseMetrics.$1, baseSize * 0.7) -
            fontSize;
        subscriptExtent = math.max(0, subscriptExtent);
      }
      final height = math.max(fontSize, argAreaHeight) + subscriptExtent;
      return (height, subscriptExtent + vPadding + argMetrics.$2);
    }

    if (node is PermutationNode) {
      final double smallSize = fontSize * 0.8;
      final nMetrics = _staticGetListMetrics(node.n, smallSize);
      final rMetrics = _staticGetListMetrics(node.r, smallSize);

      final double nHeight = math.max(nMetrics.$1, smallSize * 0.7);
      final double rHeight = math.max(rMetrics.$1, smallSize * 0.7);

      final double nColumnHeight = nHeight + fontSize * 0.8;
      final double rColumnHeight = fontSize * 0.8 + rHeight;

      final double height = math.max(
        fontSize,
        math.max(nColumnHeight, rColumnHeight),
      );
      return (height, height / 2);
    }

    if (node is CombinationNode) {
      final double smallSize = fontSize * 0.8;
      final nMetrics = _staticGetListMetrics(node.n, smallSize);
      final rMetrics = _staticGetListMetrics(node.r, smallSize);

      final double nHeight = math.max(nMetrics.$1, smallSize * 0.7);
      final double rHeight = math.max(rMetrics.$1, smallSize * 0.7);

      final double nColumnHeight = nHeight + fontSize * 1.0;
      final double rColumnHeight = fontSize * 0.8 + rHeight;

      final double height = math.max(
        fontSize,
        math.max(nColumnHeight, rColumnHeight),
      );
      return (height, height / 2);
    }

    if (node is SummationNode || node is ProductNode) {
      final double smallSize = fontSize * 0.7;
      final variable =
          node is SummationNode
              ? node.variable
              : (node as ProductNode).variable;
      final lower =
          node is SummationNode ? node.lower : (node as ProductNode).lower;
      final upper =
          node is SummationNode ? node.upper : (node as ProductNode).upper;
      final body =
          node is SummationNode ? node.body : (node as ProductNode).body;

      final varMetrics = _staticGetListMetrics(variable, smallSize);
      final lowerMetrics = _staticGetListMetrics(lower, smallSize);
      final upperMetrics = _staticGetListMetrics(upper, smallSize);
      final bodyMetrics = _staticGetListMetrics(body, fontSize);

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, smallSize * 0.7);
      final double lowerHeight = math.max(
        math.max(varMetrics.$1, lowerMetrics.$1),
        smallSize * 0.7,
      );
      final double symbolColumnHeight =
          upperHeight +
          fontSize * 0.1 +
          symbolHeight +
          fontSize * 0.1 +
          lowerHeight;
      final double height = math.max(
        symbolColumnHeight,
        bodyMetrics.$1 + fontSize * 0.2,
      );
      return (height, height / 2);
    }

    if (node is DerivativeNode) {
      final double symbolSize = fontSize;
      final double barHeight = math.max(2.0, symbolSize * 0.08);
      final double barMargin = symbolSize * 0.06;
      final bodyMetrics = _staticGetListMetrics(node.body, fontSize);

      final numMetrics = _staticGetListMetrics([
        LiteralNode(text: 'd'),
      ], symbolSize);
      final varMetrics = _staticGetListMetrics(node.variable, symbolSize);
      final double denHeight = math.max(numMetrics.$1, varMetrics.$1);
      final double fracHeight =
          numMetrics.$1 + barMargin + barHeight + barMargin + denHeight;

      final double height = math.max(fracHeight, bodyMetrics.$1);
      return (height, height / 2);
    }

    if (node is IntegralNode) {
      final double boundSize = fontSize * 0.7;
      final double dxSize = fontSize;
      final double lowerGap = fontSize * 0.18;
      final lowerMetrics = _staticGetListMetrics(node.lower, boundSize);
      final upperMetrics = _staticGetListMetrics(node.upper, boundSize);
      final bodyMetrics = _staticGetListMetrics(node.body, fontSize);

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, boundSize * 0.7);
      final double lowerHeight = math.max(lowerMetrics.$1, boundSize * 0.7);
      final double symbolColumnHeight =
          upperHeight + fontSize * 0.05 + symbolHeight + lowerGap + lowerHeight;
      final double height = math.max(
        symbolColumnHeight,
        math.max(bodyMetrics.$1 + fontSize * 0.2, dxSize),
      );
      return (height, height / 2);
    }

    if (node is ComplexNode) {
      final contentMetrics = _staticGetListMetrics(node.content, fontSize);
      return (contentMetrics.$1, contentMetrics.$2);
    }

    if (node is AnsNode) {
      final indexMetrics = _staticGetListMetrics(node.index, fontSize);
      final height = math.max(fontSize, indexMetrics.$1);
      return (height, height / 2);
    }

    return (fontSize, fontSize / 2);
  }

  static (double, double) _staticGetListMetrics(
    List<MathNode> nodes,
    double fontSize,
  ) {
    if (nodes.isEmpty) {
      return (fontSize, fontSize / 2);
    }

    if (nodes.length == 1 && nodes.first is LiteralNode) {
      if ((nodes.first as LiteralNode).text.isEmpty) {
        return (fontSize, fontSize / 2);
      }
    }

    double maxAbove = 0;
    double maxBelow = 0;

    for (final node in nodes) {
      final (height, offset) = _staticGetNodeMetrics(node, fontSize);
      if (height > 0) {
        maxAbove = math.max(maxAbove, height - offset);
        maxBelow = math.max(maxBelow, offset);
      }
    }

    if (maxAbove == 0 && maxBelow == 0) {
      return (fontSize, fontSize / 2);
    }

    return (maxAbove + maxBelow, maxBelow);
  }

  (double, double) _getNodeMetrics(MathNode node, double fontSize) {
    if (node is LiteralNode) {
      return (fontSize, fontSize * 0.5);
    }

    if (node is ConstantNode) {
      return (fontSize, fontSize * 0.5);
    }

    if (node is ExponentNode) {
      final double powerSize =
          fontSize < FONTSIZE * 0.85 ? fontSize : fontSize * 0.8;
      final baseMetrics = _getListMetrics(node.base, fontSize);
      final powerMetrics = _getListMetrics(node.power, powerSize);
      final double baseHeight = baseMetrics.$1;
      final double baseRef = baseMetrics.$2;
      final double powerHeight = powerMetrics.$1;
      final double fixedOffset = fontSize * -0.5;
      final double totalHeight = baseHeight + fixedOffset + powerHeight;
      return (totalHeight, baseRef);
    }

    if (node is FractionNode) {
      final numMetrics = _getListMetrics(node.numerator, fontSize);
      final denMetrics = _getListMetrics(node.denominator, fontSize);
      final double barHeight = math.max(1.5, fontSize * 0.06);
      final double margin = fontSize * 0.15;
      final numHeight = math.max(numMetrics.$1, fontSize * 0.8);
      final denHeight = math.max(denMetrics.$1, fontSize * 0.8);
      final height = numHeight + margin + barHeight + margin + denHeight;
      final offset = denHeight + margin + barHeight / 2;
      return (height, offset);
    }

    if (node is RootNode) {
      final radicandMetrics = _getListMetrics(node.radicand, fontSize);
      final double minHeight = fontSize * 1.2;
      final double topPad = fontSize * 0.08;
      final double bottomPad = 2.0;
      final height = math.max(
        minHeight,
        radicandMetrics.$1 + topPad + bottomPad,
      );
      return (height, bottomPad + radicandMetrics.$2);
    }

    if (node is ParenthesisNode) {
      final contentMetrics = _getListMetrics(node.content, fontSize);
      final double vPadding = fontSize * 0.1;
      final height = math.max(fontSize, contentMetrics.$1 + vPadding * 2);
      final offset = vPadding + contentMetrics.$2;
      return (height, offset);
    }

    if (node is TrigNode) {
      final argMetrics = _getListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final height = math.max(fontSize, argMetrics.$1 + vPadding * 2);
      return (height, vPadding + argMetrics.$2);
    }

    if (node is LogNode) {
      final argMetrics = _getListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final double argAreaHeight = argMetrics.$1 + vPadding * 2;
      double subscriptExtent = 0;
      if (!node.isNaturalLog) {
        final baseSize = fontSize * 0.8;
        final baseMetrics = _getListMetrics(node.base, baseSize);
        subscriptExtent =
            fontSize * 0.5 +
            math.max(baseMetrics.$1, baseSize * 0.7) -
            fontSize;
        subscriptExtent = math.max(0, subscriptExtent);
      }
      final height = math.max(fontSize, argAreaHeight) + subscriptExtent;
      return (height, subscriptExtent + vPadding + argMetrics.$2);
    }

    if (node is PermutationNode) {
      final double smallSize = fontSize * 0.8;
      final nMetrics = _getListMetrics(node.n, smallSize);
      final rMetrics = _getListMetrics(node.r, smallSize);

      final double nHeight = math.max(nMetrics.$1, smallSize * 0.7);
      final double rHeight = math.max(rMetrics.$1, smallSize * 0.7);

      final double nColumnHeight = nHeight + fontSize * 0.8;
      final double rColumnHeight = fontSize * 0.8 + rHeight;

      final double height = math.max(
        fontSize,
        math.max(nColumnHeight, rColumnHeight),
      );
      return (height, height / 2);
    }

    if (node is CombinationNode) {
      final double smallSize = fontSize * 0.8;
      final nMetrics = _getListMetrics(node.n, smallSize);
      final rMetrics = _getListMetrics(node.r, smallSize);

      final double nHeight = math.max(nMetrics.$1, smallSize * 0.7);
      final double rHeight = math.max(rMetrics.$1, smallSize * 0.7);

      final double nColumnHeight = nHeight + fontSize * 1.0;
      final double rColumnHeight = fontSize * 0.8 + rHeight;

      final double height = math.max(
        fontSize,
        math.max(nColumnHeight, rColumnHeight),
      );
      return (height, height / 2);
    }

    if (node is SummationNode || node is ProductNode) {
      final double smallSize = fontSize * 0.7;
      final variable =
          node is SummationNode
              ? node.variable
              : (node as ProductNode).variable;
      final lower =
          node is SummationNode ? node.lower : (node as ProductNode).lower;
      final upper =
          node is SummationNode ? node.upper : (node as ProductNode).upper;
      final body =
          node is SummationNode ? node.body : (node as ProductNode).body;

      final varMetrics = _getListMetrics(variable, smallSize);
      final lowerMetrics = _getListMetrics(lower, smallSize);
      final upperMetrics = _getListMetrics(upper, smallSize);
      final bodyMetrics = _getListMetrics(body, fontSize);

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, smallSize * 0.7);
      final double lowerHeight = math.max(
        math.max(varMetrics.$1, lowerMetrics.$1),
        smallSize * 0.7,
      );
      final double symbolColumnHeight =
          upperHeight +
          fontSize * 0.1 +
          symbolHeight +
          fontSize * 0.1 +
          lowerHeight;
      final double height = math.max(
        symbolColumnHeight,
        bodyMetrics.$1 + fontSize * 0.2,
      );
      return (height, height / 2);
    }

    if (node is DerivativeNode) {
      final double symbolSize = fontSize;
      final double barHeight = math.max(2.0, symbolSize * 0.08);
      final double barMargin = symbolSize * 0.06;
      final bodyMetrics = _getListMetrics(node.body, fontSize);

      final numMetrics = _getListMetrics([LiteralNode(text: 'd')], symbolSize);
      final varMetrics = _getListMetrics(node.variable, symbolSize);
      final double denHeight = math.max(numMetrics.$1, varMetrics.$1);
      final double fracHeight =
          numMetrics.$1 + barMargin + barHeight + barMargin + denHeight;

      final double height = math.max(fracHeight, bodyMetrics.$1);
      return (height, height / 2);
    }

    if (node is IntegralNode) {
      final double boundSize = fontSize * 0.7;
      final double dxSize = fontSize;
      final double lowerGap = fontSize * 0.18;
      final lowerMetrics = _getListMetrics(node.lower, boundSize);
      final upperMetrics = _getListMetrics(node.upper, boundSize);
      final bodyMetrics = _getListMetrics(node.body, fontSize);

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, boundSize * 0.7);
      final double lowerHeight = math.max(lowerMetrics.$1, boundSize * 0.7);
      final double symbolColumnHeight =
          upperHeight + fontSize * 0.05 + symbolHeight + lowerGap + lowerHeight;
      final double height = math.max(
        symbolColumnHeight,
        math.max(bodyMetrics.$1 + fontSize * 0.2, dxSize),
      );
      return (height, height / 2);
    }

    if (node is ComplexNode) {
      final contentMetrics = _getListMetrics(node.content, fontSize);
      return (contentMetrics.$1, contentMetrics.$2);
    }

    if (node is AnsNode) {
      final indexMetrics = _getListMetrics(node.index, fontSize);
      final height = math.max(fontSize, indexMetrics.$1);
      return (height, height / 2);
    }

    return (fontSize, fontSize / 2);
  }

  (double, double) _getListMetrics(List<MathNode> nodes, double fontSize) {
    if (nodes.isEmpty) {
      return (fontSize, fontSize / 2);
    }

    if (nodes.length == 1 && nodes.first is LiteralNode) {
      if ((nodes.first as LiteralNode).text.isEmpty) {
        return (fontSize, fontSize / 2);
      }
    }

    double maxAbove = 0;
    double maxBelow = 0;

    for (final node in nodes) {
      final (height, offset) = _getNodeMetrics(node, fontSize);
      if (height > 0) {
        maxAbove = math.max(maxAbove, height - offset);
        maxBelow = math.max(maxBelow, offset);
      }
    }

    if (maxAbove == 0 && maxBelow == 0) {
      return (fontSize, fontSize / 2);
    }

    return (maxAbove + maxBelow, maxBelow);
  }
}

class _UnitVectorWidget extends StatelessWidget {
  final String axis;
  final double fontSize;
  final Color color;

  const _UnitVectorWidget({
    required this.axis,
    required this.fontSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = MathTextStyle.getStyle(fontSize).copyWith(color: color);
    final hatStyle = baseStyle;

    return SizedBox(
      height: fontSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [Text('$axis\u0302', style: hatStyle)],
          ),
        ],
      ),
    );
  }
}

/// Simple radical painter for read-only display
class _RadicalPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _RadicalPainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    final path = Path();
    double width = size.width;
    double height = size.height;

    double tickStartX = 0;
    double tickStartY = height * 0.55;
    double tickEndX = width * 0.25;
    double tickEndY = height * 0.6;
    double vBottomX = width * 0.5;
    double vBottomY = height - (strokeWidth / 2);
    double vTopX = width;
    double vTopY = strokeWidth / 2;

    path.moveTo(tickStartX, tickStartY);
    path.lineTo(tickEndX, tickEndY);
    path.lineTo(vBottomX, vBottomY);
    path.lineTo(vTopX, vTopY);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _RadicalPainter oldDelegate) {
    return color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
  }
}

/// Scalable parenthesis for read-only display
class _ScalableParenthesis extends StatelessWidget {
  final bool isOpening;
  final double fontSize;
  final Color color;

  const _ScalableParenthesis({
    required this.isOpening,
    required this.fontSize,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: fontSize * 1),
      child: CustomPaint(
        size: Size(fontSize * 0.2, double.infinity),
        painter: _ParenthesisPainter(
          isOpening: isOpening,
          color: color,
          strokeWidth: math.max(1.5, fontSize * 0.06),
        ),
      ),
    );
  }
}

class _ParenthesisPainter extends CustomPainter {
  final bool isOpening;
  final Color color;
  final double strokeWidth;

  _ParenthesisPainter({
    required this.isOpening,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final path = Path();
    double padding = size.height * 0.05;
    double bowAmount = size.width * 0.3;

    if (isOpening) {
      path.moveTo(size.width, padding);
      path.quadraticBezierTo(
        -bowAmount,
        size.height / 2,
        size.width,
        size.height - padding,
      );
    } else {
      path.moveTo(0, padding);
      path.quadraticBezierTo(
        size.width + bowAmount,
        size.height / 2,
        0,
        size.height - padding,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ParenthesisPainter oldDelegate) {
    return oldDelegate.isOpening != isOpening ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Scalable absolute value bar for read-only display
class _ScalableAbsBar extends StatelessWidget {
  final double fontSize;
  final Color color;

  const _ScalableAbsBar({
    required this.fontSize,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: fontSize * 1),
      child: CustomPaint(
        size: Size(fontSize * 0.12, double.infinity),
        painter: _AbsBarPainter(
          color: color,
          strokeWidth: math.max(1.5, fontSize * 0.06),
        ),
      ),
    );
  }
}

class _AbsBarPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _AbsBarPainter({
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    final double padding = size.height * 0.05;
    final double x = size.width / 2;

    canvas.drawLine(
      Offset(x, padding),
      Offset(x, size.height - padding),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _AbsBarPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}
