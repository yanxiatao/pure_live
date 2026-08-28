import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Literal `i18n('key')` call sites must resolve in every shipped locale.
///
/// A merge that drops or renames a translation key is otherwise invisible: the
/// UI quietly renders the raw key at runtime. This caught `en.json` losing
/// `quality_limited_to`, `quality_stream_unchanged`, `audience_yy_detail` and
/// `audience_ranking_rule_desc` while call sites still used them.
final RegExp _literalKey = RegExp('''i18n\\(\\s*(['"])([A-Za-z0-9_]+)\\1''');

/// Vendored third-party sources are excluded from repo-wide text scanning, the
/// same way `tool/local_ci.ps1` excludes them from formatting.
const List<String> _excludedPathParts = <String>['lib/core/scripts', 'lib\\gen'];

void main() {
  test('every literal i18n key exists in en.json and zh.json', () {
    final Map<String, Set<String>> present = <String, Set<String>>{};
    for (final entry in const <String, String>{'en': 'en.json', 'zh': 'zh.json'}.entries) {
      final File file = File('assets/translations/${entry.value}');
      expect(file.existsSync(), isTrue, reason: '${file.path} must exist');
      final Map<String, dynamic> decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      present[entry.key] = decoded.keys.toSet();
    }

    final List<String> offenders = <String>[];
    int checkedKeys = 0;
    for (final FileSystemEntity entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (_excludedPathParts.any(entity.path.contains)) {
        continue;
      }
      final List<String> lines = entity.readAsLinesSync();
      for (int index = 0; index < lines.length; index++) {
        for (final RegExpMatch match in _literalKey.allMatches(lines[index])) {
          final String key = match.group(2)!;
          checkedKeys++;
          final List<String> missing = present.entries
              .where((entry) => !entry.value.contains(key))
              .map((entry) => entry.key)
              .toList();
          if (missing.isNotEmpty) {
            offenders.add('$key -> missing in ${missing.join(', ')} (${'${entity.path}:${index + 1}'})');
          }
        }
      }
    }

    expect(checkedKeys, greaterThan(500), reason: 'the scan must actually find literal i18n keys');
    expect(offenders, isEmpty, reason: 'untranslated keys:\n${offenders.join('\n')}');
  });
}
