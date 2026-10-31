import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:labelguard_mobile/l10n/strings.dart';
import 'package:labelguard_mobile/l10n/ta.dart';

/// Every literal passed to tr(...) in lib/, adjacent strings joined and
/// escapes decoded, so a missing Tamil entry fails here instead of showing
/// English on a Tamil screen.
Set<String> trKeys() {
  const escapes = {'n': '\n', 't': '\t', "'": "'", '"': '"', r'\': r'\', r'$': r'$'};
  final keys = <String>{};
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.contains('l10n'));
  for (final f in files) {
    final s = f.readAsStringSync();
    for (final m in RegExp(r'(?<![A-Za-z0-9_.])tr\(').allMatches(s)) {
      var i = m.end;
      final parts = <String>[];
      while (true) {
        while (i < s.length && ' \t\r\n'.contains(s[i])) {
          i++;
        }
        if (i >= s.length || !"'\"".contains(s[i])) break;
        final quote = s[i++];
        final buf = StringBuffer();
        while (s[i] != quote) {
          if (s[i] == r'\') {
            buf.write(escapes[s[i + 1]] ?? s[i + 1]);
            i += 2;
          } else {
            buf.write(s[i++]);
          }
        }
        i++;
        parts.add(buf.toString());
      }
      if (parts.isNotEmpty) keys.add(parts.join());
    }
  }
  return keys;
}

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

void main() {
  tearDown(() => AppLanguage.tamil = false);

  test('every string the app shows has a Tamil translation', () {
    final keys = trKeys();
    expect(keys.length, greaterThan(200), reason: 'the scanner found too few tr() calls');
    final missing = keys.where((k) => !ta.containsKey(k)).toList()..sort();
    expect(missing, isEmpty);
  });

  test('Tamil keeps every {placeholder} of the English', () {
    final broken = ta.entries
        .where((e) => !setEquals(placeholders(e.key), placeholders(e.value)))
        .map((e) => e.key)
        .toList();
    expect(broken, isEmpty);
  });

  test('all 13 rules have Tamil names', () {
    expect(taRuleNames.keys.toSet(), {for (var n = 1; n <= 13; n++) n});
  });

  test('tr fills placeholders and follows the language switch', () {
    expect(tr('Scan #{id}', {'id': 46}), 'Scan #46');
    AppLanguage.tamil = true;
    expect(tr('Scan #{id}', {'id': 46}), 'ஸ்கேன் #46');
    expect(trRuleName(4, 'Net quantity declaration'), 'நிகர அளவு அறிவிப்பு');
    expect(trCheckStatus('fail'), 'தோல்வி');
    expect(AppLanguage.code, 'ta');
  });

  test('a string with no Tamil entry falls back to English, not blank', () {
    AppLanguage.tamil = true;
    expect(tr('Some new sentence'), 'Some new sentence');
    expect(trRuleName(99, 'Rule from a newer server'), 'Rule from a newer server');
  });

  test('translating Tamil text again leaves it unchanged', () {
    AppLanguage.tamil = true;
    final once = tr('Scan Result');
    expect(tr(once), once);
  });
}

bool setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
