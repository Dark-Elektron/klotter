import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/math_renderer/math_text_style.dart';

void main() {
  group('Cursor logic with forceLeadingOperatorPadding', () {
    test('getCursorOffset with padding flag', () {
      // "+65", normally unary ('+65' -> length 3),
      // but with forceLeadingOperatorPadding=true it's binary (' + 65' -> length 6)

      const TextScaler textScaler = TextScaler.noScaling;
      const double fontSize = 24.0;

      // We expect the cursor offset at index 1 (after '+') to be different.
      final offsetWithoutFlag = MathTextStyle.getCursorOffset(
        '+65',
        1,
        fontSize,
        textScaler,
        forceLeadingOperatorPadding: false,
      );

      final offsetWithFlag = MathTextStyle.getCursorOffset(
        '+65',
        1,
        fontSize,
        textScaler,
        forceLeadingOperatorPadding: true,
      );

      // With flag, string is " + 65". Index 1 (after '+') maps to display index 2 (after ' +').
      // Without flag, string is "+65". Index 1 (after '+') maps to display index 1.
      expect(offsetWithFlag, greaterThan(offsetWithoutFlag));
    });

    test('getCharIndexForOffset with padding flag', () {
      const TextScaler textScaler = TextScaler.noScaling;
      const double fontSize = 24.0;

      // If we query at an xOffset far enough, the index should map correctly back to logic chars.
      // Get the x-coordinate after '+' when padded.
      final paddedOffset = MathTextStyle.getCursorOffset(
        '+65',
        1,
        fontSize,
        textScaler,
        forceLeadingOperatorPadding: true,
      );

      final logicalIndex = MathTextStyle.getCharIndexForOffset(
        '+65',
        paddedOffset,
        fontSize,
        textScaler,
        forceLeadingOperatorPadding: true,
      );

      expect(logicalIndex, equals(1));
    });
  });
}
