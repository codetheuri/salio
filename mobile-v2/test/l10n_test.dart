import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Swahili must have every English message, with the same placeholders. The
// generator would otherwise show English for a missing key without a word.
Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('lib/app/l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

Set<String> _messages(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Names in `{name}` or `{name, plural, …}`. Not the words inside a plural
/// branch, such as `=1{1 record}`.
Set<String> _placeholders(String message) => RegExp(
  r'\{(\w+)(?=[,}])',
).allMatches(message).map((m) => m.group(1)!).toSet();

void main() {
  final en = _arb('en');
  final sw = _arb('sw');

  test('Swahili has exactly the English messages', () {
    expect(_messages(sw), _messages(en));
  });

  test('every message has the same placeholders in both languages', () {
    for (final key in _messages(en)) {
      expect(
        _placeholders(sw[key] as String),
        _placeholders(en[key] as String),
        reason: key,
      );
    }
  });

  test('no message is empty', () {
    for (final arb in [en, sw]) {
      for (final key in _messages(arb)) {
        expect((arb[key] as String).trim(), isNotEmpty, reason: key);
      }
    }
  });
}
