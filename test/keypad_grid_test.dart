import 'package:flutter_test/flutter_test.dart';

import 'package:klotter/keypad/keypad.dart';

/// Every tablet key is placed, exactly once, in both orientations.
///
/// The layouts used to be tables of integer positions indexing into widget
/// lists built elsewhere. Nothing named anything, so a key could be added to a
/// builder and simply never appear — which is what happened to the export key:
/// it took index 17, no table mentioned 17, and it vanished from both tablets
/// with no error. Naming the cells makes that a failing test instead.
void main() {
  final List<String> allKeys = tabletKeyNames;

  for (final bool landscape in <bool>[false, true]) {
    final String which = landscape ? 'landscape' : 'portrait';

    group('the $which grid', () {
      final List<List<String?>> grid = tabletGridFor(landscape: landscape);

      List<String> placed() => <String>[
        for (final List<String?> row in grid)
          for (final String? name in row)
            if (name != null) name,
      ];

      test('is the right shape', () {
        expect(grid, hasLength(landscape ? 3 : 4));
        for (final List<String?> row in grid) {
          expect(row, hasLength(landscape ? 20 : 15), reason: '$row');
        }
      });

      test('places every key', () {
        final Set<String> missing = allKeys.toSet().difference(
          placed().toSet(),
        );
        expect(missing, isEmpty, reason: 'never placed: $missing');
      });

      test('places no key twice', () {
        final List<String> all = placed();
        final Set<String> seen = <String>{};
        final Set<String> twice = <String>{};
        for (final String name in all) {
          if (!seen.add(name)) twice.add(name);
        }
        expect(twice, isEmpty, reason: 'placed more than once: $twice');
      });

      test('invents no key', () {
        final Set<String> unknown = placed().toSet().difference(
          allKeys.toSet(),
        );
        expect(unknown, isEmpty, reason: 'not a real key: $unknown');
      });

      test('has the export key', () {
        // The one this whole test exists for.
        expect(placed(), contains('ext.export'));
      });
    });
  }

  test('both orientations carry exactly the same keys', () {
    Set<String> keysOf(bool landscape) => <String>{
      for (final List<String?> row in tabletGridFor(landscape: landscape))
        for (final String? name in row)
          if (name != null) name,
    };
    expect(keysOf(false), equals(keysOf(true)));
    expect(keysOf(false), hasLength(allKeys.length));
  });
}
