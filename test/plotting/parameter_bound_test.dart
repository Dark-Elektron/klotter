import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/plotting/widgets/parameter_range_panel.dart';

/// Parameter bounds are nearly always multiples of π, so they have to be
/// typeable and readable as such.
void main() {
  group('reading a bound', () {
    test('plain numbers', () {
      expect(parseParameterBound('0'), 0);
      expect(parseParameterBound('2.5'), 2.5);
      expect(parseParameterBound(' -3 '), -3);
    });

    test('multiples of π, however they are spelled', () {
      expect(parseParameterBound('π'), closeTo(math.pi, 1e-12));
      expect(parseParameterBound('pi'), closeTo(math.pi, 1e-12));
      expect(parseParameterBound('2π'), closeTo(2 * math.pi, 1e-12));
      expect(parseParameterBound('2pi'), closeTo(2 * math.pi, 1e-12));
      expect(parseParameterBound('-π'), closeTo(-math.pi, 1e-12));
      expect(parseParameterBound('π/2'), closeTo(math.pi / 2, 1e-12));
      expect(parseParameterBound('-3π/4'), closeTo(-3 * math.pi / 4, 1e-12));
    });

    test('nonsense is rejected rather than guessed at', () {
      // Null, not a substituted default: a silently corrected bound is a plot
      // of something the user did not ask for.
      expect(parseParameterBound(''), isNull);
      expect(parseParameterBound('two pi'), isNull);
      expect(parseParameterBound('π/0'), isNull);
      expect(parseParameterBound('x'), isNull);
    });
  });

  group('writing a bound back', () {
    test('names the fractions worth naming', () {
      expect(formatParameterBound(0), '0');
      expect(formatParameterBound(math.pi), 'π');
      expect(formatParameterBound(2 * math.pi), '2π');
      expect(formatParameterBound(math.pi / 2), 'π/2');
      expect(formatParameterBound(-math.pi / 4), '-π/4');
    });

    test('falls back to a decimal for anything else', () {
      expect(formatParameterBound(1), '1');
      expect(formatParameterBound(2.5), '2.5');
      // Not 0.32π or some ratio nobody recognises.
      expect(formatParameterBound(1.0), isNot(contains('π')));
    });

    test('round-trips', () {
      for (final double v in <double>[
        0,
        1,
        -2.5,
        math.pi,
        -math.pi / 3,
        2 * math.pi,
      ]) {
        expect(
          parseParameterBound(formatParameterBound(v)),
          closeTo(v, 1e-9),
          reason: 'lost $v through "${formatParameterBound(v)}"',
        );
      }
    });
  });
}
