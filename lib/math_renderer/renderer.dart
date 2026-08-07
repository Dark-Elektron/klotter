import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'sumprod_symbol.dart';
import '../utils/constants.dart';
import 'math_editor_controller.dart';
import 'placeholder_box.dart';

// Re-export all related modules for backward compatibility
export 'math_nodes.dart';
export 'math_text_style.dart';
export 'math_editor_widgets.dart';

// Import the modules we depend on
import 'math_nodes.dart';
import 'math_text_style.dart';

/// Renders a math expression tree as Flutter widgets.
class MathRenderer extends StatelessWidget {
  final List<MathNode> expression;
  final GlobalKey rootKey;
  final MathEditorController controller;
  final int structureVersion;
  final TextScaler textScaler;

  const MathRenderer({
    super.key,
    required this.expression,
    required this.rootKey,
    required this.controller,
    required this.structureVersion,
    required this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    List<_LineInfo> lines = _splitIntoLines(expression);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children:
          lines.map((lineInfo) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: UnconstrainedBox(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderNodeList(
                    lineInfo.nodes,
                    lineInfo.startIndex,
                    fontSize: FONTSIZE,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  /// Splits expression into lines at NewlineNode boundaries
  List<_LineInfo> _splitIntoLines(List<MathNode> nodes) {
    List<_LineInfo> lines = [];
    List<MathNode> currentLine = [];
    int startIndex = 0;

    for (int i = 0; i < nodes.length; i++) {
      if (nodes[i] is NewlineNode) {
        // End current line
        if (currentLine.isEmpty) {
          currentLine.add(LiteralNode(text: ''));
        }
        lines.add(
          _LineInfo(nodes: List.from(currentLine), startIndex: startIndex),
        );
        currentLine = [];
        startIndex = i + 1;
      } else {
        currentLine.add(nodes[i]);
      }
    }

    // Add last line
    if (currentLine.isEmpty) {
      currentLine.add(LiteralNode(text: ''));
    }
    lines.add(_LineInfo(nodes: currentLine, startIndex: startIndex));

    return lines;
  }

  /// Helper to render a list of nodes with reference axis alignment
  List<Widget> _renderNodeList(
    List<MathNode> nodes,
    int startIndex, {
    required double fontSize,
    String? parentId,
    String? path,
    bool removeLeftPadding = false,
    bool removeRightPadding = false,
  }) {
    if (nodes.isEmpty) {
      return [];
    }

    // Calculate max extents for the list
    double maxAbove = 0;
    double maxBelow = 0;

    for (final node in nodes) {
      final (height, offset) = _getNodeMetrics(node, fontSize);
      if (height > 0) {
        maxAbove = math.max(maxAbove, height - offset);
        maxBelow = math.max(maxBelow, offset);
      }
    }

    // Find first and last non-empty node indices for edge padding
    int firstNonEmptyIndex = -1;
    int lastNonEmptyIndex = -1;

    for (int i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      final bool isEmpty = node is LiteralNode && node.text.isEmpty;
      if (!isEmpty) {
        if (firstNonEmptyIndex == -1) firstNonEmptyIndex = i;
        lastNonEmptyIndex = i;
      }
    }

    // Render each node with appropriate top padding to align reference axes
    return nodes.asMap().entries.map((e) {
      final node = e.value;
      final int nodeIndex = e.key;
      final (height, offset) = _getNodeMetrics(node, fontSize);

      // Top padding = maxAbove - (this node's extent above its reference)
      final topPadding = maxAbove - (height - offset);

      // Check if this node is empty LiteralNode
      final bool isEmpty = node is LiteralNode && node.text.isEmpty;

      // Determine left/right padding
      final bool isFirstNonEmpty = nodeIndex == firstNonEmptyIndex;
      final bool isLastNonEmpty = nodeIndex == lastNonEmptyIndex;

      // Standard horizontal padding between nodes
      const double standardPadding = 1.5;

      // Empty nodes get 0 padding; non-empty use edge detection
      double leftPad;
      double rightPad;

      if (isEmpty) {
        leftPad = 0.0;
        rightPad = 0.0;
      } else {
        // Remove padding on edges if requested
        leftPad =
            (removeLeftPadding && isFirstNonEmpty) ? 0.0 : standardPadding;
        rightPad =
            (removeRightPadding && isLastNonEmpty) ? 0.0 : standardPadding;
      }

      // Determine if this literal's leading operator should be treated
      // as binary (with full spacing) because it follows another node.
      bool forceLeadingOp = false;
      if (node is LiteralNode && node.text.isNotEmpty && !isFirstNonEmpty) {
        final firstChar = node.text[0];
        // Check if first char is an operator that would be padded
        const operatorChars = {
          '\u002B',
          '\u2212',
          '-',
          '\u00B7',
          '\u00D7',
          '*',
          '=',
        };
        if (operatorChars.contains(firstChar)) {
          forceLeadingOp = true;
        }
      }

      return Padding(
        padding: EdgeInsets.only(
          left: leftPad,
          right: rightPad,
          top: math.max(0, topPadding),
        ),
        child: _renderNode(
          node,
          startIndex + e.key,
          nodes,
          parentId,
          path,
          fontSize,
          forceLeadingOperatorPadding: forceLeadingOp,
        ),
      );
    }).toList();
  }

  Widget _wrapComposite({
    required Widget child,
    required MathNode node,
    required int index,
    required String? parentId,
    required String? path,
  }) {
    return _ComplexNodeWrapper(
      node: node,
      index: index,
      parentId: parentId,
      path: path,
      controller: controller,
      rootKey: rootKey,
      structureVersion: structureVersion,
      child: child,
    );
  }

  Widget _renderNode(
    MathNode node,
    int index,
    List<MathNode> siblings,
    String? parentId,
    String? path,
    double fontSize, {
    bool forceLeadingOperatorPadding = false,
  }) {
    // Skip rendering NewlineNode (it's handled by line splitting)
    if (node is NewlineNode) {
      return const SizedBox.shrink();
    }

    if (node is LiteralNode) {
      return LiteralWidget(
        key: ValueKey('${node.id}_$structureVersion'),
        node: node,
        fontSize: fontSize,
        parentId: parentId,
        path: path,
        index: index,
        rootKey: rootKey,
        controller: controller,
        structureVersion: structureVersion,
        textScaler: textScaler,
        forceLeadingOperatorPadding: forceLeadingOperatorPadding,
      );
    }

    if (node is ConstantNode) {
      return Text(
        MathTextStyle.toDisplayText(node.constant),
        style: MathTextStyle.getStyle(fontSize).copyWith(color: Colors.white),
        textScaler: textScaler,
      );
    }

    // Unit vectors are atomic tokens like constants, drawn as the axis letter
    // with a combining circumflex (x̂). The editor had metrics for these but no
    // widget case, so they measured correctly and then drew nothing — the read
    // -only result display has its own copy of this, which is why they showed
    // up in results but never in the expression being typed.
    if (node is UnitVectorNode) {
      return Text(
        '${node.axis}\u0302',
        style: MathTextStyle.getStyle(fontSize).copyWith(color: Colors.white),
        textScaler: textScaler,
      );
    }

    if (node is FractionNode) {
      final bool numEmpty = _isContentEmpty(node.numerator);
      final bool denEmpty = _isContentEmpty(node.denominator);
      final double fractionPlaceholderWidth = fontSize * 1.0;
      final double fractionPlaceholderHeight = fontSize * 0.8;

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Numerator
              numEmpty
                  ? GestureDetector(
                    onTap:
                        () => controller.navigateTo(
                          parentId: node.id,
                          path: 'num',
                          index: 0,
                          subIndex: 0,
                        ),
                    child: SizedBox(
                      width: fractionPlaceholderWidth,
                      child: PlaceholderBox(
                        fontSize: fontSize,
                        minWidth: fractionPlaceholderWidth,
                        minHeight: fractionPlaceholderHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _renderNodeList(
                            node.numerator,
                            0,
                            fontSize: fontSize,
                            parentId: node.id,
                            path: 'num',
                          ),
                        ),
                      ),
                    ),
                  )
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.numerator,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'num',
                    ),
                  ),

              // Fraction line
              Container(
                height: math.max(1.5, fontSize * 0.06),
                width: double.infinity,
                color: Colors.white,
                margin: EdgeInsets.symmetric(vertical: fontSize * 0.15),
              ),

              // Denominator
              denEmpty
                  ? GestureDetector(
                    onTap:
                        () => controller.navigateTo(
                          parentId: node.id,
                          path: 'den',
                          index: 0,
                          subIndex: 0,
                        ),
                    child: SizedBox(
                      width: fractionPlaceholderWidth,
                      child: PlaceholderBox(
                        fontSize: fontSize,
                        minWidth: fractionPlaceholderWidth,
                        minHeight: fractionPlaceholderHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _renderNodeList(
                            node.denominator,
                            0,
                            fontSize: fontSize,
                            parentId: node.id,
                            path: 'den',
                          ),
                        ),
                      ),
                    ),
                  )
                  : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.denominator,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'den',
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    if (node is ExponentNode) {
      final double powerSize =
          fontSize < FONTSIZE * 0.85 ? fontSize : fontSize * 0.8;
      final bool baseEmpty = _isContentEmpty(node.base);
      final bool powerEmpty = _isContentEmpty(node.power);

      // Fixed offset - must match metrics!
      final double fixedOffset = fontSize * -0.5;

      Widget baseWidget =
          baseEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'base',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.7,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.base,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'base',
                      removeLeftPadding: true,
                      removeRightPadding: true,
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.base,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'base',
                  removeLeftPadding: true,
                  removeRightPadding: true,
                ),
              );

      Widget powerWidget =
          powerEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'pow',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: powerSize,
                  minWidth: powerSize * 0.6,
                  minHeight: powerSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.power,
                      0,
                      fontSize: powerSize,
                      parentId: node.id,
                      path: 'pow',
                      removeLeftPadding: true,
                      removeRightPadding: true,
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.power,
                  0,
                  fontSize: powerSize,
                  parentId: node.id,
                  path: 'pow',
                  removeLeftPadding: true,
                  removeRightPadding: true,
                ),
              );

      // Get power height for layout
      final powerMetrics = _getListMetrics(node.power, powerSize);
      final double powerHeight = powerMetrics.$1;

      // Base is pushed down by: powerHeight + fixedOffset
      final double baseTopPadding = powerHeight + fixedOffset;

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Base pushed down
            Padding(
              padding: EdgeInsets.only(top: baseTopPadding),
              child: baseWidget,
            ),
            // Power at top
            powerWidget,
          ],
        ),
      );
    }

    if (node is ParenthesisNode) {
      final bool contentEmpty = _isContentEmpty(node.content);

      Widget contentWidget =
          contentEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'content',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.8,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.content,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'content',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.content,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'content',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScalableParenthesis(
                isOpening: true,
                fontSize: fontSize,
                color: Colors.white,
                textScaler: textScaler,
              ),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: fontSize * 0.15,
                  vertical: fontSize * 0.1,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [contentWidget],
                ),
              ),
              ScalableParenthesis(
                isOpening: false,
                fontSize: fontSize,
                color: Colors.white,
                textScaler: textScaler,
              ),
            ],
          ),
        ),
      );
    }

    if (node is TrigNode) {
      final bool argEmpty = _isContentEmpty(node.argument);
      final argMetrics = _getListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final double argContentHeight = argMetrics.$1;
      final double argAreaHeight = math.max(
        fontSize,
        argContentHeight + vPadding * 2,
      );
      final double argRefFromTop =
          vPadding + (argContentHeight - argMetrics.$2);
      final double labelTop =
          (argRefFromTop - fontSize / 2)
              .clamp(0.0, math.max(0.0, argAreaHeight - fontSize))
              .toDouble();

      Widget argWidget =
          argEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'arg',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.8,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.argument,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'arg',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.argument,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'arg',
                ),
              );

      if (node.function.toLowerCase() == 'abs') {
        return _wrapComposite(
          node: node,
          index: index,
          parentId: parentId,
          path: path,
          child: IntrinsicHeight(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScalableAbsBar(fontSize: fontSize, color: Colors.white),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: fontSize * 0.15,
                    vertical: vPadding,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [argWidget],
                  ),
                ),
                ScalableAbsBar(fontSize: fontSize, color: Colors.white),
              ],
            ),
          ),
        );
      }

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: Offset(0, labelTop),
                  child: Text(
                    node.function,
                    style: MathTextStyle.getStyle(
                      fontSize,
                    ).copyWith(color: Colors.white),
                    textScaler: textScaler,
                  ),
                ),
              ),
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScalableParenthesis(
                      isOpening: true,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: fontSize * 0.15,
                        vertical: vPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [argWidget],
                      ),
                    ),
                    ScalableParenthesis(
                      isOpening: false,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (node is RootNode) {
      final double indexSize = fontSize * 0.7;
      final double minRadicandHeight = fontSize * 1.2;

      final bool radicandEmpty = _isContentEmpty(node.radicand);
      final bool indexEmpty = !node.isSquareRoot && _isContentEmpty(node.index);

      // Build radicand widget
      Widget radicandWidget =
          radicandEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'radicand',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.9,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.radicand,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'radicand',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.radicand,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'radicand',
                ),
              );

      // Build index widget for nth roots
      Widget? indexWidget;
      if (!node.isSquareRoot) {
        indexWidget =
            indexEmpty
                ? GestureDetector(
                  onTap:
                      () => controller.navigateTo(
                        parentId: node.id,
                        path: 'index',
                        index: 0,
                        subIndex: 0,
                      ),
                  child: PlaceholderBox(
                    fontSize: indexSize,
                    minWidth: indexSize * 0.7,
                    minHeight: indexSize * 0.7,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _renderNodeList(
                        node.index,
                        0,
                        fontSize: indexSize,
                        parentId: node.id,
                        path: 'index',
                      ),
                    ),
                  ),
                )
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderNodeList(
                    node.index,
                    0,
                    fontSize: indexSize,
                    parentId: node.id,
                    path: 'index',
                  ),
                );
      }

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Index for nth root
            if (indexWidget != null)
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [indexWidget, SizedBox(height: fontSize * 0.35)],
                ),
              ),

            // Radical symbol + radicand
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
                        painter: RadicalSymbolPainter(
                          color: Colors.white,
                          strokeWidth: math.max(1.5, fontSize * 0.06),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white,
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [radicandWidget],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (node is LogNode) {
      final double baseSize = fontSize * 0.8;
      final argMetrics = _getListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final double argContentHeight = argMetrics.$1;
      final double argAreaHeight = math.max(
        fontSize,
        argContentHeight + vPadding * 2,
      );
      final double argRefFromTop =
          vPadding + (argContentHeight - argMetrics.$2);
      final double labelTop =
          (argRefFromTop - fontSize / 2)
              .clamp(0.0, math.max(0.0, argAreaHeight - fontSize))
              .toDouble();

      final bool baseEmpty = !node.isNaturalLog && _isContentEmpty(node.base);
      final bool argEmpty = _isContentEmpty(node.argument);

      // Build base widget (only for non-natural log)
      Widget? baseWidget;
      if (!node.isNaturalLog) {
        baseWidget =
            baseEmpty
                ? GestureDetector(
                  onTap:
                      () => controller.navigateTo(
                        parentId: node.id,
                        path: 'base',
                        index: 0,
                        subIndex: 0,
                      ),
                  child: PlaceholderBox(
                    fontSize: baseSize,
                    minWidth: baseSize * 0.6,
                    minHeight: baseSize * 0.7,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _renderNodeList(
                        node.base,
                        0,
                        fontSize: baseSize,
                        parentId: node.id,
                        path: 'base',
                      ),
                    ),
                  ),
                )
                : Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _renderNodeList(
                    node.base,
                    0,
                    fontSize: baseSize,
                    parentId: node.id,
                    path: 'base',
                  ),
                );
      }

      // Build argument widget
      Widget argWidget =
          argEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'arg',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.8,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.argument,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'arg',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.argument,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'arg',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: Offset(0, labelTop),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.isNaturalLog ? 'ln' : 'log',
                        style: MathTextStyle.getStyle(
                          fontSize,
                        ).copyWith(color: Colors.white),
                        textScaler: textScaler,
                      ),
                      if (!node.isNaturalLog && baseWidget != null)
                        Padding(
                          padding: EdgeInsets.only(
                            left: 1,
                            top: fontSize * 0.5,
                          ),
                          child: baseWidget,
                        ),
                    ],
                  ),
                ),
              ),

              // Small gap for natural log
              if (node.isNaturalLog) SizedBox(width: fontSize * 0.05),

              // Parentheses with argument
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScalableParenthesis(
                      isOpening: true,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: fontSize * 0.08,
                        vertical: vPadding,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [argWidget],
                      ),
                    ),
                    ScalableParenthesis(
                      isOpening: false,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (node is PermutationNode) {
      final double smallSize = fontSize * 0.8;

      final bool nEmpty = _isContentEmpty(node.n);
      final bool rEmpty = _isContentEmpty(node.r);

      // Build n widget (top/superscript)
      Widget nWidget =
          nEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'n',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.n,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'n',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.n,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'n',
                ),
              );

      // Build r widget (bottom/subscript)
      Widget rWidget =
          rEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'r',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.r,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'r',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.r,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'r',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // n (superscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [nWidget, SizedBox(height: fontSize * 0.8)],
            ),
            // P symbol
            Text(
              'P',
              style: MathTextStyle.getStyle(
                fontSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
            // r (subscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(height: fontSize * 0.8), rWidget],
            ),
          ],
        ),
      );
    }

    if (node is CombinationNode) {
      final double smallSize = fontSize * 0.8;

      final bool nEmpty = _isContentEmpty(node.n);
      final bool rEmpty = _isContentEmpty(node.r);

      // Build n widget (top/superscript)
      Widget nWidget =
          nEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'n',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.n,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'n',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.n,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'n',
                ),
              );

      // Build r widget (bottom/subscript)
      Widget rWidget =
          rEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'r',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.r,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'r',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.r,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'r',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // n (superscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [nWidget, SizedBox(height: fontSize * 1.0)],
            ),
            // C symbol
            Text(
              'C',
              style: MathTextStyle.getStyle(
                fontSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
            // r (subscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(height: fontSize * 0.8), rWidget],
            ),
          ],
        ),
      );
    }

    if (node is SummationNode || node is ProductNode) {
      final bool isSum = node is SummationNode;
      final double smallSize = fontSize * 0.7;
      final variable = isSum ? (node).variable : (node as ProductNode).variable;
      final lower = isSum ? (node).lower : (node as ProductNode).lower;
      final upper = isSum ? (node).upper : (node as ProductNode).upper;
      final body = isSum ? (node).body : (node as ProductNode).body;

      final bool varEmpty = _isContentEmpty(variable);
      final bool lowerEmpty = _isContentEmpty(lower);
      final bool upperEmpty = _isContentEmpty(upper);
      final bool bodyEmpty = _isContentEmpty(body);

      Widget varWidget =
          varEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'var',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      variable,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'var',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  variable,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'var',
                ),
              );

      Widget lowerWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          varWidget,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '=',
              style: MathTextStyle.getStyle(
                smallSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
          ),
          lowerEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'lower',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      lower,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'lower',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  lower,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'lower',
                ),
              ),
        ],
      );

      Widget upperWidget =
          upperEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'upper',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      upper,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'upper',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  upper,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'upper',
                ),
              );

      Widget bodyWidget =
          bodyEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'body',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.9,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      body,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'body',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  body,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'body',
                ),
              );

      // Calculate body metrics for alignment
      final bodyMetrics = _getListMetrics(body, fontSize);
      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);

      // Symbol column height
      final upperMetrics = _getListMetrics(upper, smallSize);
      final double upperHeight = math.max(upperMetrics.$1, smallSize * 0.7);
      final double symbolHeight = fontSize * 1.4;
      final lowerMetrics = _getListMetrics(lower, smallSize);
      final varMetrics = _getListMetrics(variable, smallSize);
      final double lowerHeight = math.max(
        math.max(varMetrics.$1, lowerMetrics.$1),
        smallSize * 0.7,
      );
      final double totalSymbolHeight =
          upperHeight +
          fontSize * 0.1 +
          symbolHeight +
          fontSize * 0.1 +
          lowerHeight;

      // Center alignment offset
      final double symbolCenter = totalSymbolHeight / 2;
      final double bodyCenter = bodyHeight / 2;

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Symbol column
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                upperWidget,
                SizedBox(height: fontSize * 0.1),
                SumProdSymbol(
                  type: isSum ? SumProdType.sum : SumProdType.product,
                  fontSize: fontSize,
                  color: Colors.white,
                ),
                SizedBox(height: fontSize * 0.1),
                lowerWidget,
              ],
            ),
            SizedBox(width: fontSize * 0.2),
            // Parentheses with body - vertically centered with symbol
            Padding(
              padding: EdgeInsets.only(
                top: math.max(0, symbolCenter - bodyCenter - fontSize * 0.1),
              ),
              child: IntrinsicHeight(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ScalableParenthesis(
                      isOpening: true,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: fontSize * 0.15,
                        vertical: fontSize * 0.1,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [bodyWidget],
                      ),
                    ),
                    ScalableParenthesis(
                      isOpening: false,
                      fontSize: fontSize,
                      color: Colors.white,
                      textScaler: textScaler,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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

      final bool varEmpty = _isContentEmpty(variable);
      final bool atEmpty = _isContentEmpty(at);
      final bool bodyEmpty = _isContentEmpty(body);

      Widget varWidget =
          varEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'var',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: symbolSize,
                  minWidth: symbolSize * 0.6,
                  minHeight: symbolSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      variable,
                      0,
                      fontSize: symbolSize,
                      parentId: node.id,
                      path: 'var',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  variable,
                  0,
                  fontSize: symbolSize,
                  parentId: node.id,
                  path: 'var',
                ),
              );

      Widget evalAtWidget =
          atEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'at',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: evalSize,
                  minWidth: evalSize * 0.6,
                  minHeight: evalSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      at,
                      0,
                      fontSize: evalSize,
                      parentId: node.id,
                      path: 'at',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  at,
                  0,
                  fontSize: evalSize,
                  parentId: node.id,
                  path: 'at',
                ),
              );

      Widget bodyWidget =
          bodyEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'body',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.9,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      body,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'body',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  body,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'body',
                ),
              );

      // Calculate metrics
      final bodyMetrics = _getListMetrics(body, fontSize);
      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);

      // Fraction measurements
      final numMetrics = _getListMetrics([LiteralNode(text: 'd')], symbolSize);
      final varMetrics = _getListMetrics(variable, symbolSize);
      final double numHeight = numMetrics.$1;
      final double denHeight = math.max(numMetrics.$1, varMetrics.$1);
      final double fracHeight =
          numHeight + barMargin + barHeight + barMargin + denHeight;

      // Fraction center
      final double fracCenterY = fracHeight / 2;

      // Body (parentheses) measurements
      final double vPadding = fontSize * 0.1;
      final double parenHeight = bodyHeight + vPadding * 2;

      // Body center
      final double parenCenterY = parenHeight / 2;

      // BIDIRECTIONAL centering (like integral)
      final double fracTopPadding = math.max(0, parenCenterY - fracCenterY);
      final double parenTopPadding = math.max(0, fracCenterY - parenCenterY);

      // Calculate total height and positions
      final double fracBottom = fracTopPadding + fracHeight;
      final double parenBottom = parenTopPadding + parenHeight;
      final double totalHeight = math.max(fracBottom, parenBottom);

      // Eval bar spans full height
      final double evalBarHeight = totalHeight;
      final double evalBarTopPadding = 0.0;

      String varText = '';
      for (final n in variable) {
        if (n is LiteralNode) {
          varText += n.text;
        }
      }
      final String displayVarText = varText.trim().isEmpty ? 'x' : varText;

      final Widget evalSubscript = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            MathTextStyle.toDisplayText(displayVarText),
            style: MathTextStyle.getStyle(
              evalSize,
            ).copyWith(color: Colors.white),
            textScaler: textScaler,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Text(
              '=',
              style: MathTextStyle.getStyle(
                evalSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
          ),
          evalAtWidget,
        ],
      );

      final double barWidth = math.max(1.2, evalSize * 0.08);

      // Derivative fraction widget
      Widget fracWidget = IntrinsicWidth(
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
                  ).copyWith(color: Colors.white),
                  textScaler: textScaler,
                ),
              ],
            ),
            Container(
              height: barHeight,
              width: double.infinity,
              color: Colors.white,
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
                  ).copyWith(color: Colors.white),
                  textScaler: textScaler,
                ),
                const SizedBox(width: 1),
                varWidget,
              ],
            ),
          ],
        ),
      );

      // Eval bar widget - spans full height
      Widget evalBarWidget = SizedBox(
        height: evalBarHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: barWidth, color: Colors.white),
            SizedBox(width: evalSize * 0.15),
            Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [evalSubscript],
            ),
          ],
        ),
      );

      // Parentheses widget
      Widget parenWidget = IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScalableParenthesis(
              isOpening: true,
              fontSize: fontSize,
              color: Colors.white,
              textScaler: textScaler,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: fontSize * 0.15,
                vertical: vPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bodyWidget],
              ),
            ),
            ScalableParenthesis(
              isOpening: false,
              fontSize: fontSize,
              color: Colors.white,
              textScaler: textScaler,
            ),
          ],
        ),
      );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fraction part - pushed down when body is taller
            Padding(
              padding: EdgeInsets.only(top: fracTopPadding),
              child: fracWidget,
            ),
            SizedBox(width: fontSize * 0.2),
            // Parentheses - pushed down when fraction is taller
            Padding(
              padding: EdgeInsets.only(top: parenTopPadding),
              child: parenWidget,
            ),
            // Eval bar - only for a definite (evaluated-at-a-point) derivative
            if (node.isDefinite) ...[
              SizedBox(width: fontSize * 0.1),
              Padding(
                padding: EdgeInsets.only(top: evalBarTopPadding),
                child: evalBarWidget,
              ),
            ],
          ],
        ),
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

      final bool varEmpty = _isContentEmpty(variable);
      final bool lowerEmpty = _isContentEmpty(lower);
      final bool upperEmpty = _isContentEmpty(upper);
      final bool bodyEmpty = _isContentEmpty(body);

      Widget upperWidget =
          upperEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'upper',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: boundSize,
                  minWidth: boundSize * 0.6,
                  minHeight: boundSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      upper,
                      0,
                      fontSize: boundSize,
                      parentId: node.id,
                      path: 'upper',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  upper,
                  0,
                  fontSize: boundSize,
                  parentId: node.id,
                  path: 'upper',
                ),
              );

      Widget lowerWidget =
          lowerEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'lower',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: boundSize,
                  minWidth: boundSize * 0.6,
                  minHeight: boundSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      lower,
                      0,
                      fontSize: boundSize,
                      parentId: node.id,
                      path: 'lower',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  lower,
                  0,
                  fontSize: boundSize,
                  parentId: node.id,
                  path: 'lower',
                ),
              );

      Widget varWidget =
          varEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'var',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: dxSize,
                  minWidth: dxSize * 0.6,
                  minHeight: dxSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      variable,
                      0,
                      fontSize: dxSize,
                      parentId: node.id,
                      path: 'var',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  variable,
                  0,
                  fontSize: dxSize,
                  parentId: node.id,
                  path: 'var',
                ),
              );

      Widget bodyWidget =
          bodyEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'body',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.9,
                  minHeight: fontSize * 0.9,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      body,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'body',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  body,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'body',
                ),
              );

      // Calculate metrics for alignment
      final bodyMetrics = _getListMetrics(body, fontSize);
      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);
      final double bodyRef = bodyMetrics.$2; // Reference from bottom

      final upperMetrics = _getListMetrics(upper, boundSize);
      final double upperHeight = math.max(upperMetrics.$1, boundSize * 0.7);
      final double symbolHeight = fontSize * 1.4;
      // Actual rendered height of the ∫ glyph. The nominal fontSize*1.4 under-
      // measures the text box, so for an indefinite integral (which shows only
      // the lone ∫) it must be measured to keep the symbol centered on the body.
      final TextPainter intSymbolPainter =
          TextPainter(
            text: TextSpan(
              text: '∫',
              style: MathTextStyle.getStyle(symbolHeight),
            ),
            textDirection: TextDirection.ltr,
            textScaler: textScaler,
          )..layout();
      final double intSymbolHeight = intSymbolPainter.height;
      final lowerMetrics = _getListMetrics(lower, boundSize);
      final double lowerHeight = math.max(lowerMetrics.$1, boundSize * 0.7);
      // Indefinite integrals show only the ∫ symbol (no bounds).
      final double totalSymbolHeight =
          node.isDefinite
              ? upperHeight +
                  fontSize * 0.05 +
                  symbolHeight +
                  lowerGap +
                  lowerHeight
              : intSymbolHeight;

      // Body section measurements
      final double vPadding = fontSize * 0.1;
      final double bodyTotalHeight = bodyHeight + vPadding * 2;

      // Bidirectional centering
      final double columnCenterY = totalSymbolHeight / 2;
      final double bodyCenterY = bodyTotalHeight / 2;

      final double symbolTopPadding = math.max(0, bodyCenterY - columnCenterY);
      final double bodyTopPadding = math.max(0, columnCenterY - bodyCenterY);

      // Body reference line from top of IntegralNode
      final double bodyRefFromTop =
          bodyTopPadding + vPadding + (bodyHeight - bodyRef);

      final Widget dxWidget = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'd',
            style: MathTextStyle.getStyle(dxSize).copyWith(color: Colors.white),
            textScaler: textScaler,
          ),
          varWidget,
        ],
      );

      final Widget integralSymbol = Text(
        '∫',
        style: MathTextStyle.getStyle(
          fontSize * 1.4,
        ).copyWith(color: Colors.white),
        textScaler: textScaler,
      );

      final Widget parenBodyWidget = IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScalableParenthesis(
              isOpening: true,
              fontSize: fontSize,
              color: Colors.white,
              textScaler: textScaler,
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: fontSize * 0.15,
                vertical: vPadding,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [bodyWidget],
              ),
            ),
            ScalableParenthesis(
              isOpening: false,
              fontSize: fontSize,
              color: Colors.white,
              textScaler: textScaler,
            ),
          ],
        ),
      );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Integral symbol column
            Padding(
              padding: EdgeInsets.only(top: symbolTopPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (node.isDefinite) ...[
                    upperWidget,
                    SizedBox(height: fontSize * 0.05),
                  ],
                  // A lone indefinite ∫ reads slightly low once box-centered,
                  // so nudge its paint position up to visually center it on the
                  // body. Paint-only, so the layout height (and the caret
                  // alignment) is unaffected.
                  if (node.isDefinite)
                    integralSymbol
                  else
                    Transform.translate(
                      offset: Offset(0, -symbolHeight * 0.07),
                      child: integralSymbol,
                    ),
                  if (node.isDefinite) ...[
                    SizedBox(height: lowerGap),
                    lowerWidget,
                  ],
                ],
              ),
            ),
            SizedBox(width: fontSize * 0.2),
            // Parentheses with body
            Padding(
              padding: EdgeInsets.only(top: bodyTopPadding),
              child: parenBodyWidget,
            ),
            SizedBox(width: fontSize * 0.1),
            // dx widget — BASELINE ALIGNED with body reference
            Padding(
              padding: EdgeInsets.only(top: bodyRefFromTop - dxSize / 2),
              child: dxWidget,
            ),
          ],
        ),
      );
    }

    if (node is AnsNode) {
      final bool indexEmpty = _isContentEmpty(node.index);

      Widget indexWidget =
          indexEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'index',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: fontSize,
                  minWidth: fontSize * 0.6,
                  minHeight: fontSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.index,
                      0,
                      fontSize: fontSize,
                      parentId: node.id,
                      path: 'index',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.index,
                  0,
                  fontSize: fontSize,
                  parentId: node.id,
                  path: 'index',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // "ANS" text
              Text(
                'ans',
                style: MathTextStyle.getStyle(
                  fontSize,
                ).copyWith(color: Colors.orangeAccent),
                textScaler: textScaler,
              ),
              // Index
              indexWidget,
            ],
          ),
        ),
      );
    }

    if (node is PermutationNode) {
      final double smallSize = fontSize * 0.8;

      final bool nEmpty = _isContentEmpty(node.n);
      final bool rEmpty = _isContentEmpty(node.r);

      // Build n widget (top/superscript)
      Widget nWidget =
          nEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'n',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.n,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'n',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.n,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'n',
                ),
              );

      // Build r widget (bottom/subscript)
      Widget rWidget =
          rEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'r',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.r,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'r',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.r,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'r',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // n (superscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [nWidget, SizedBox(height: fontSize * 0.8)],
            ),
            // P symbol
            Text(
              'P',
              style: MathTextStyle.getStyle(
                fontSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
            // r (subscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(height: fontSize * 0.8), rWidget],
            ),
          ],
        ),
      );
    }

    if (node is CombinationNode) {
      final double smallSize = fontSize * 0.8;

      final bool nEmpty = _isContentEmpty(node.n);
      final bool rEmpty = _isContentEmpty(node.r);

      // Build n widget (top/superscript)
      Widget nWidget =
          nEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'n',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.n,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'n',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.n,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'n',
                ),
              );

      // Build r widget (bottom/subscript)
      Widget rWidget =
          rEmpty
              ? GestureDetector(
                onTap:
                    () => controller.navigateTo(
                      parentId: node.id,
                      path: 'r',
                      index: 0,
                      subIndex: 0,
                    ),
                child: PlaceholderBox(
                  fontSize: smallSize,
                  minWidth: smallSize * 0.6,
                  minHeight: smallSize * 0.7,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _renderNodeList(
                      node.r,
                      0,
                      fontSize: smallSize,
                      parentId: node.id,
                      path: 'r',
                    ),
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _renderNodeList(
                  node.r,
                  0,
                  fontSize: smallSize,
                  parentId: node.id,
                  path: 'r',
                ),
              );

      return _wrapComposite(
        node: node,
        index: index,
        parentId: parentId,
        path: path,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // n (superscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [nWidget, SizedBox(height: fontSize * 1.0)],
            ),
            // C symbol
            Text(
              'C',
              style: MathTextStyle.getStyle(
                fontSize,
              ).copyWith(color: Colors.white),
              textScaler: textScaler,
            ),
            // r (subscript position)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [SizedBox(height: fontSize * 0.8), rWidget],
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  /// Check if a list of nodes is effectively empty
  bool _isContentEmpty(List<MathNode> nodes) {
    if (nodes.isEmpty) return true;
    if (nodes.length == 1 && nodes.first is LiteralNode) {
      return (nodes.first as LiteralNode).text.isEmpty;
    }
    return false;
  }

  /// Returns (height, referenceOffset from bottom) for a node
  (double, double) _getNodeMetrics(MathNode node, double fontSize) {
    if (node is NewlineNode) {
      return (0, 0);
    }

    if (node is LiteralNode) {
      return (fontSize, fontSize / 2);
    }

    if (node is ConstantNode) {
      return (fontSize, fontSize / 2);
    }

    if (node is UnitVectorNode) {
      return (fontSize, fontSize / 2);
    }

    if (node is ExponentNode) {
      final double powerSize =
          fontSize < FONTSIZE * 0.85 ? fontSize : fontSize * 0.8;

      final baseMetrics = _getListMetrics(node.base, fontSize);
      final powerMetrics = _getListMetrics(node.power, powerSize);

      final double baseHeight = baseMetrics.$1;
      final double baseRef = baseMetrics.$2;
      final double powerHeight = powerMetrics.$1;

      // Fixed offset: how much of power sits above base top
      final double fixedOffset = fontSize * -0.5;

      // Total height = base + fixed offset above + power height
      final double totalHeight = baseHeight + fixedOffset + powerHeight;

      // Reference is base's reference (so bases align with siblings)
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
      // Reference at bar center, measured from bottom
      final offset = denHeight + margin + barHeight / 2;

      return (height, offset);
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
      final double argAreaHeight = argMetrics.$1 + vPadding * 2;
      final double height = math.max(fontSize, argAreaHeight);
      final double extraBottom = height - argAreaHeight;
      // Reference follows argument's reference
      return (height, extraBottom + vPadding + argMetrics.$2);
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
      // Reference follows radicand's reference
      return (height, bottomPad + radicandMetrics.$2);
    }

    if (node is LogNode) {
      final argMetrics = _getListMetrics(node.argument, fontSize);
      final double vPadding = fontSize * 0.1;
      final double argAreaHeight = argMetrics.$1 + vPadding * 2;
      final double parenAreaHeight = math.max(fontSize, argAreaHeight);

      double labelHeight = fontSize;
      if (!node.isNaturalLog) {
        final baseSize = fontSize * 0.8;
        final baseMetrics = _getListMetrics(node.base, baseSize);
        final double baseHeight = math.max(baseMetrics.$1, baseSize * 0.7);
        labelHeight = math.max(fontSize, fontSize * 0.5 + baseHeight);
      }

      final double height = math.max(parenAreaHeight, labelHeight);
      final double extraBottom = height - argAreaHeight;
      // Reference follows argument's reference (within the arg area)
      return (height, extraBottom + vPadding + argMetrics.$2);
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

      return (height, height / 2); // Center of P as baseline
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

      return (height, height / 2); // Center of C as baseline
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

      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);
      final double bodyRef = bodyMetrics.$2;

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, smallSize * 0.7);
      final double lowerHeight = math.max(
        math.max(varMetrics.$1, lowerMetrics.$1),
        smallSize * 0.7,
      );

      // Symbol column height
      final double symbolColumnHeight =
          upperHeight +
          fontSize * 0.1 +
          symbolHeight +
          fontSize * 0.1 +
          lowerHeight;

      // Body section measurements (matching render code)
      final double vPadding = fontSize * 0.1;
      final double bodyTotalHeight = bodyHeight + vPadding * 2;

      // Symbol center position
      final double symbolTopOffset = upperHeight + fontSize * 0.1;
      final double symbolCenterY = symbolTopOffset + symbolHeight / 2;

      // Body top padding to center with symbol
      final double bodyTopPadding = math.max(
        0,
        symbolCenterY - bodyTotalHeight / 2,
      );

      // Total height
      final double bodyBottom = bodyTopPadding + bodyTotalHeight;
      final double totalHeight = math.max(symbolColumnHeight, bodyBottom);

      // Body reference from top of node
      // Body content starts at bodyTopPadding + vPadding
      // Body reference line from top = bodyTopPadding + vPadding + (bodyHeight - bodyRef)
      final double bodyRefFromTop =
          bodyTopPadding + vPadding + (bodyHeight - bodyRef);

      // Node reference from bottom
      final double refFromBottom = totalHeight - bodyRefFromTop;

      return (totalHeight, refFromBottom);
    }

    if (node is DerivativeNode) {
      final double symbolSize = fontSize;
      final double barHeight = math.max(2.0, symbolSize * 0.08);
      final double barMargin = symbolSize * 0.06;
      final bodyMetrics = _getListMetrics(node.body, fontSize);
      final varMetrics = _getListMetrics(node.variable, symbolSize);

      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);
      final double bodyRef = bodyMetrics.$2;

      final numMetrics = _getListMetrics([LiteralNode(text: 'd')], symbolSize);
      final double numHeight = numMetrics.$1;
      final double denHeight = math.max(numMetrics.$1, varMetrics.$1);
      final double fracHeight =
          numHeight + barMargin + barHeight + barMargin + denHeight;

      // Fraction center
      final double fracCenterY = fracHeight / 2;

      // Body (parentheses) measurements
      final double vPadding = fontSize * 0.1;
      final double parenHeight = bodyHeight + vPadding * 2;

      // Body center
      final double parenCenterY = parenHeight / 2;

      // BIDIRECTIONAL centering (matches render code)
      final double fracTopPadding = math.max(0, parenCenterY - fracCenterY);
      final double parenTopPadding = math.max(0, fracCenterY - parenCenterY);

      // Total height
      final double fracBottom = fracTopPadding + fracHeight;
      final double parenBottom = parenTopPadding + parenHeight;
      final double totalHeight = math.max(fracBottom, parenBottom);

      // Body reference from top of node
      final double bodyRefFromTop =
          parenTopPadding + vPadding + (bodyHeight - bodyRef);

      // Node reference from bottom
      final double refFromBottom = totalHeight - bodyRefFromTop;

      return (totalHeight, refFromBottom);
    }

    if (node is IntegralNode) {
      final double boundSize = fontSize * 0.7;
      final double lowerGap = fontSize * 0.18;
      final lowerMetrics = _getListMetrics(node.lower, boundSize);
      final upperMetrics = _getListMetrics(node.upper, boundSize);
      final bodyMetrics = _getListMetrics(node.body, fontSize);

      final double bodyHeight = math.max(fontSize, bodyMetrics.$1);
      final double bodyRef = bodyMetrics.$2;

      final double symbolHeight = fontSize * 1.4;
      final double upperHeight = math.max(upperMetrics.$1, boundSize * 0.7);
      final double lowerHeight = math.max(lowerMetrics.$1, boundSize * 0.7);

      // Symbol column height. Must mirror the render layout: an indefinite
      // integral shows only the ∫ glyph (measured), a definite one adds the
      // upper/lower bounds. If this diverges from the render, adjacent nodes
      // (and their caret) align to the wrong reference axis.
      final double intSymbolHeight =
          (TextPainter(
                text: TextSpan(
                  text: '∫',
                  style: MathTextStyle.getStyle(symbolHeight),
                ),
                textDirection: TextDirection.ltr,
                textScaler: textScaler,
              )..layout())
              .height;
      final double symbolColumnHeight =
          node.isDefinite
              ? upperHeight +
                  fontSize * 0.05 +
                  symbolHeight +
                  lowerGap +
                  lowerHeight
              : intSymbolHeight;

      // Body section measurements
      final double vPadding = fontSize * 0.1;
      final double bodyTotalHeight = bodyHeight + vPadding * 2;

      // FIX: Use column center for centering (matches render code)
      final double columnCenterY = symbolColumnHeight / 2;
      final double bodyCenterY = bodyTotalHeight / 2;

      // FIX: Bidirectional centering
      final double symbolTopPadding = math.max(0, bodyCenterY - columnCenterY);
      final double bodyTopPadding = math.max(0, columnCenterY - bodyCenterY);

      // Total height accounts for both paddings
      final double symbolBottom = symbolTopPadding + symbolColumnHeight;
      final double bodyBottom = bodyTopPadding + bodyTotalHeight;
      final double totalHeight = math.max(symbolBottom, bodyBottom);

      // Body reference from top of node
      final double bodyRefFromTop =
          bodyTopPadding + vPadding + (bodyHeight - bodyRef);

      // Node reference from bottom
      final double refFromBottom = totalHeight - bodyRefFromTop;

      return (totalHeight, refFromBottom);
    }

    if (node is AnsNode) {
      final indexMetrics = _getListMetrics(node.index, fontSize);
      final height = math.max(fontSize, indexMetrics.$1);
      return (height, height / 2); // Center of 'ans' as baseline
    }

    return (fontSize, fontSize / 2);
  }

  /// Returns (height, referenceOffset from bottom) for a list of nodes
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

/// Widget for rendering a literal text node.
class LiteralWidget extends StatefulWidget {
  final LiteralNode node;
  final double fontSize;
  final String? parentId;
  final String? path;
  final int index;
  final GlobalKey rootKey;
  final MathEditorController controller;
  final int structureVersion;
  final TextScaler textScaler;
  final bool forceLeadingOperatorPadding;

  const LiteralWidget({
    super.key,
    required this.node,
    required this.fontSize,
    required this.parentId,
    required this.path,
    required this.index,
    required this.rootKey,
    required this.controller,
    required this.structureVersion,
    required this.textScaler,
    this.forceLeadingOperatorPadding = false,
  });

  @override
  State<LiteralWidget> createState() => _LiteralWidgetState();
}

class _LiteralWidgetState extends State<LiteralWidget> {
  int _lastReportedVersion = -1;
  final GlobalKey _textKey = GlobalKey();
  bool _layoutRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reportLayout());
  }

  @override
  void didUpdateWidget(covariant LiteralWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.structureVersion != widget.structureVersion ||
        oldWidget.node.id != widget.node.id ||
        oldWidget.node.text != widget.node.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportLayout());
    }
  }

  void _reportLayout() {
    if (!mounted) return;
    if (_lastReportedVersion == widget.structureVersion) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      _scheduleLayoutRetry();
      return;
    }

    final RenderBox? rootBox =
        widget.rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null || !rootBox.attached) {
      _scheduleLayoutRetry();
      return;
    }

    final globalPos = box.localToGlobal(Offset.zero);
    final relativePos = rootBox.globalToLocal(globalPos);
    final rect = relativePos & box.size;

    RenderParagraph? renderParagraph;
    final renderObject = _textKey.currentContext?.findRenderObject();
    if (renderObject is RenderParagraph) {
      renderParagraph = renderObject;
    }

    widget.controller.registerNodeLayout(
      NodeLayoutInfo(
        rect: rect,
        node: widget.node,
        parentId: widget.parentId,
        path: widget.path,
        index: widget.index,
        fontSize: widget.fontSize,
        textScaler: widget.textScaler,
        renderParagraph: renderParagraph,
        forceLeadingOperatorPadding: widget.forceLeadingOperatorPadding,
      ),
    );

    _lastReportedVersion = widget.structureVersion;
  }

  void _scheduleLayoutRetry() {
    if (_layoutRetryScheduled) return;
    _layoutRetryScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutRetryScheduled = false;
      if (!mounted) return;
      if (_lastReportedVersion == widget.structureVersion) return;
      _reportLayout();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.node.text;

    if (text.isEmpty) {
      return SizedBox(
        width: math.max(2.0, widget.fontSize * 0.06),
        height: widget.fontSize,
      );
    }

    final displayText = MathTextStyle.toDisplayText(
      text,
      forceLeadingOperatorPadding: widget.forceLeadingOperatorPadding,
    );

    return Text(
      key: _textKey,
      displayText,
      style: MathTextStyle.getStyle(
        widget.fontSize,
      ).copyWith(color: Colors.white),
      textScaler: widget.textScaler,
    );
  }
}

/// Custom painter for the radical (square root) symbol.
class RadicalSymbolPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  RadicalSymbolPainter({required this.color, required this.strokeWidth});

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

    // Small horizontal tick at start
    double tickStartX = 0;
    double tickStartY = height * 0.55;
    double tickEndX = width * 0.25;
    double tickEndY = height * 0.6;

    // V bottom point
    double vBottomX = width * 0.5;
    double vBottomY = height - (strokeWidth / 2);

    // Top right of V (connects to vinculum)
    double vTopX = width;
    double vTopY = strokeWidth / 2;

    path.moveTo(tickStartX, tickStartY);
    path.lineTo(tickEndX, tickEndY);
    path.lineTo(vBottomX, vBottomY);
    path.lineTo(vTopX, vTopY);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RadicalSymbolPainter oldDelegate) {
    return color != oldDelegate.color || strokeWidth != oldDelegate.strokeWidth;
  }
}

/// Wrapper for composite nodes to register their layout bounds
class _ComplexNodeWrapper extends StatefulWidget {
  final Widget child;
  final MathNode node;
  final int index;
  final String? parentId;
  final String? path;
  final MathEditorController controller;
  final GlobalKey rootKey;
  final int structureVersion;

  const _ComplexNodeWrapper({
    required this.child,
    required this.node,
    required this.index,
    required this.parentId,
    required this.path,
    required this.controller,
    required this.rootKey,
    required this.structureVersion,
  });

  @override
  State<_ComplexNodeWrapper> createState() => _ComplexNodeWrapperState();
}

class _ComplexNodeWrapperState extends State<_ComplexNodeWrapper> {
  bool _registerRetryScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void didUpdateWidget(covariant _ComplexNodeWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.structureVersion != widget.structureVersion ||
        oldWidget.node.id != widget.node.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _register());
    }
  }

  void _register() {
    if (!mounted) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) {
      _scheduleRegisterRetry();
      return;
    }

    final RenderBox? rootBox =
        widget.rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null || !rootBox.attached) {
      _scheduleRegisterRetry();
      return;
    }

    final globalPos = box.localToGlobal(Offset.zero);
    final relativePos = rootBox.globalToLocal(globalPos);
    final rect = relativePos & box.size;

    widget.controller.registerComplexNodeLayout(
      ComplexNodeInfo(
        node: widget.node,
        parentId: widget.parentId,
        path: widget.path,
        index: widget.index,
        rect: rect,
      ),
    );
  }

  void _scheduleRegisterRetry() {
    if (_registerRetryScheduled) return;
    _registerRetryScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerRetryScheduled = false;
      if (!mounted) return;
      _register();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// A scalable parenthesis widget that grows with content height.
class ScalableParenthesis extends StatelessWidget {
  final bool isOpening;
  final double fontSize;
  final Color color;
  final TextScaler textScaler;

  const ScalableParenthesis({
    super.key,
    required this.isOpening,
    required this.fontSize,
    this.color = Colors.white,
    required this.textScaler,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: fontSize * 1),
      child: CustomPaint(
        size: Size(fontSize * 0.2, double.infinity), // Reduced from 0.35
        painter: ParenthesisPainter(
          isOpening: isOpening,
          color: color,
          strokeWidth: math.max(1.5, fontSize * 0.06),
        ),
      ),
    );
  }
}

/// Custom painter for parenthesis curves.
class ParenthesisPainter extends CustomPainter {
  final bool isOpening;
  final Color color;
  final double strokeWidth;

  ParenthesisPainter({
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

    // Control the bow amount here (lower = less bow)
    // Original was -size.width for opening and 2 * size.width for closing
    double bowAmount =
        size.width * 0.3; // Adjust this value (0.0 = straight, 1.0 = more bow)

    if (isOpening) {
      path.moveTo(size.width, padding);
      path.quadraticBezierTo(
        -bowAmount, // Changed from -size.width
        size.height / 2,
        size.width,
        size.height - padding,
      );
    } else {
      path.moveTo(0, padding);
      path.quadraticBezierTo(
        size.width + bowAmount, // Changed from 2 * size.width
        size.height / 2,
        0,
        size.height - padding,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ParenthesisPainter oldDelegate) {
    return oldDelegate.isOpening != isOpening ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// A scalable absolute value bar that grows with content height.
class ScalableAbsBar extends StatelessWidget {
  final double fontSize;
  final Color color;

  const ScalableAbsBar({
    super.key,
    required this.fontSize,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: fontSize * 1),
      child: CustomPaint(
        size: Size(fontSize * 0.12, double.infinity),
        painter: AbsBarPainter(
          color: color,
          strokeWidth: math.max(1.5, fontSize * 0.06),
        ),
      ),
    );
  }
}

/// Custom painter for absolute value bars.
class AbsBarPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  AbsBarPainter({required this.color, required this.strokeWidth});

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
  bool shouldRepaint(covariant AbsBarPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Information about a complex node's location in the tree
class ComplexNodeInfo {
  final MathNode node;
  final String? parentId;
  final String? path;
  final int index;
  final Rect rect;

  ComplexNodeInfo({
    required this.node,
    required this.parentId,
    required this.path,
    required this.index,
    required this.rect,
  });
}

/// Layout information for a literal node, used for cursor positioning.
class NodeLayoutInfo {
  final Rect rect;
  final LiteralNode node;
  final String? parentId;
  final String? path;
  final int index;
  final double fontSize;
  final TextScaler textScaler;
  final RenderParagraph? renderParagraph;
  final bool forceLeadingOperatorPadding;

  // Cached display text - computed once
  String? _displayText;
  String get displayText =>
      _displayText ??= MathTextStyle.toDisplayText(
        node.text,
        forceLeadingOperatorPadding: forceLeadingOperatorPadding,
      );

  NodeLayoutInfo({
    required this.rect,
    required this.node,
    required this.parentId,
    required this.path,
    required this.index,
    required this.fontSize,
    required this.textScaler,
    this.renderParagraph,
    this.forceLeadingOperatorPadding = false,
  });
}

/// Helper class to track line info
class _LineInfo {
  final List<MathNode> nodes;
  final int startIndex;

  _LineInfo({required this.nodes, required this.startIndex});
}

/// Overlay widget for rendering the blinking cursor.
class CursorOverlay extends SingleChildRenderObjectWidget {
  final CursorPaintNotifier notifier;
  final Animation<double> blinkAnimation;
  final bool showCursor;

  const CursorOverlay({
    super.key,
    required super.child,
    required this.notifier,
    required this.blinkAnimation,
    required this.showCursor,
  });

  @override
  RenderCursorOverlay createRenderObject(BuildContext context) {
    return RenderCursorOverlay(
      notifier: notifier,
      blinkAnimation: blinkAnimation,
      showCursor: showCursor,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderCursorOverlay renderObject,
  ) {
    renderObject
      ..notifier = notifier
      ..blinkAnimation = blinkAnimation
      ..showCursor = showCursor;
  }
}

/// Render object for the cursor overlay.
class RenderCursorOverlay extends RenderProxyBox {
  RenderCursorOverlay({
    required CursorPaintNotifier notifier,
    required Animation<double> blinkAnimation,
    required bool showCursor,
  }) : _notifier = notifier,
       _blinkAnimation = blinkAnimation,
       _showCursor = showCursor {
    _notifier.onNeedsPaint = markNeedsPaint;
    _blinkAnimation.addListener(markNeedsPaint);
  }

  CursorPaintNotifier _notifier;
  set notifier(CursorPaintNotifier value) {
    if (_notifier == value) return;
    _notifier.onNeedsPaint = null;
    _notifier = value;
    _notifier.onNeedsPaint = markNeedsPaint;
    markNeedsPaint();
  }

  Animation<double> _blinkAnimation;
  set blinkAnimation(Animation<double> value) {
    if (_blinkAnimation == value) return;
    _blinkAnimation.removeListener(markNeedsPaint);
    _blinkAnimation = value;
    _blinkAnimation.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _showCursor;
  set showCursor(bool value) {
    if (_showCursor == value) return;
    _showCursor = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Restore the callback when re-attached
    _notifier.onNeedsPaint = markNeedsPaint;
    _blinkAnimation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _notifier.onNeedsPaint = null;
    _blinkAnimation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    // Paint child first (the math expression)
    super.paint(context, offset);

    // Paint cursor on top
    if (_showCursor &&
        _blinkAnimation.value >= 0.5 &&
        _notifier.rect != Rect.zero) {
      final paint =
          Paint()
            ..color = Colors.yellowAccent
            ..style = PaintingStyle.fill;

      context.canvas.drawRect(_notifier.rect.shift(offset), paint);
    }
  }
}
