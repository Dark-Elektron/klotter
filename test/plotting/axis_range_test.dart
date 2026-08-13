import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:klotter/plotting/widgets/axis_range_sheet.dart';

/// Axis bounds are typed, not gestured — there is no pinch that lands exactly
/// on x ∈ [0, 2π]. The parser is deliberately small: what people actually type
/// for a bound, not the whole expression engine.
void main() {
  group('parseBound accepts plain numbers', () {
    test('integers and decimals, signed', () {
      expect(parseBound('5'), equals(5));
      expect(parseBound('-2.5'), equals(-2.5));
      expect(parseBound(' 0.25 '), equals(0.25));
      expect(parseBound('1e3'), equals(1000));
    });
  });

  group('parseBound accepts the constants people use for bounds', () {
    test('pi and e, bare and scaled', () {
      expect(parseBound('pi'), closeTo(math.pi, 1e-12));
      expect(parseBound('2pi'), closeTo(2 * math.pi, 1e-12));
      expect(parseBound('-pi'), closeTo(-math.pi, 1e-12));
      expect(parseBound('e'), closeTo(math.e, 1e-12));
      expect(parseBound('π'), closeTo(math.pi, 1e-12));
    });

    test('one multiply or divide', () {
      expect(parseBound('pi/2'), closeTo(math.pi / 2, 1e-12));
      expect(parseBound('-pi/2'), closeTo(-math.pi / 2, 1e-12));
      expect(parseBound('3*pi'), closeTo(3 * math.pi, 1e-12));
      expect(parseBound('2pi/3'), closeTo(2 * math.pi / 3, 1e-12));
    });
  });

  group('parseBound rejects what it cannot mean', () {
    test('empty, words, and division by zero', () {
      expect(parseBound(''), isNull);
      expect(parseBound('   '), isNull);
      expect(parseBound('abc'), isNull);
      expect(parseBound('pi/0'), isNull);
    });

    test('anything needing the real engine', () {
      // Better to refuse than to half-evaluate: a bound that silently means
      // something else is worse than one that asks to be retyped.
      expect(parseBound('sin(1)'), isNull);
      expect(parseBound('1+2'), isNull);
      expect(parseBound('2pi*3/4'), isNull);
    });
  });
}
