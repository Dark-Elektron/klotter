import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The maths core is plain Dart.
///
/// The engines, the serializer and the node tree they work on must not reach
/// Flutter, directly or through anything they import. They did: both engines
/// imported the settings, a Flutter ChangeNotifier, for one enum, and the
/// serializer imported the renderer for the node classes it re-exports. Plain
/// Dart is what lets the core become a package of its own, shared with klator
/// and tested with `dart test`, instead of a copy kept in step by hand.
void main() {
  test('nothing the engine imports reaches Flutter', () {
    final Directory lib = Directory('lib');
    final List<String> start = <String>[
      for (final FileSystemEntity f in Directory('lib/math_engine').listSync())
        if (f is File && f.path.endsWith('.dart')) f.path,
    ];
    expect(start, isNotEmpty);

    final RegExp directive = RegExp(
      r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''',
      multiLine: true,
    );
    final Set<String> seen = <String>{};
    final List<String> queue = <String>[...start.map(_normal)];
    final List<String> offences = <String>[];

    while (queue.isNotEmpty) {
      final String path = queue.removeLast();
      if (!seen.add(path)) continue;
      final String source = File(path).readAsStringSync();
      for (final RegExpMatch m in directive.allMatches(source)) {
        final String uri = m.group(1)!;
        if (uri.startsWith('dart:')) {
          if (uri == 'dart:ui') offences.add('$path imports $uri');
          continue;
        }
        if (uri.startsWith('package:') && !uri.startsWith('package:klotter/')) {
          offences.add('$path imports $uri');
          continue;
        }
        final String target =
            uri.startsWith('package:klotter/')
                ? _normal(
                  '${lib.path}/${uri.substring('package:klotter/'.length)}',
                )
                : _normal('${File(path).parent.path}/$uri');
        queue.add(target);
      }
    }

    // Everything reached stays inside the core: the engine and the nodes.
    for (final String path in seen) {
      final bool inCore =
          path.startsWith('lib/math_engine/') ||
          path == 'lib/math_renderer/math_nodes.dart';
      if (!inCore) offences.add('the core reaches $path');
    }
    expect(offences, isEmpty, reason: offences.join('\n'));
  });
}

/// [path] with forward slashes and no `.` or `..` segments.
String _normal(String path) {
  final List<String> out = <String>[];
  for (final String part in path.replaceAll(r'\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      out.removeLast();
    } else {
      out.add(part);
    }
  }
  return out.join('/');
}
