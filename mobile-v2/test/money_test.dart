import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/money/money.dart';

// The same cases as server-v2/internal/money/shared_vectors_test.go.
void main() {
  final vectors =
      jsonDecode(File('../testdata/shared/money.json').readAsStringSync())
          as Map<String, dynamic>;

  test('parses what the server parses', () {
    for (final c
        in (vectors['parse'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(
        Money.parse(c['text'] as String),
        c['cents'],
        reason: '${c['text']}',
      );
    }
  });

  test('refuses what the server refuses', () {
    for (final text in (vectors['invalid'] as List<dynamic>).cast<String>()) {
      expect(() => Money.parse(text), throwsFormatException, reason: '"$text"');
      expect(Money.tryParse(text), isNull);
    }
  });

  test('writes what the server writes', () {
    for (final c
        in (vectors['wire'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(Money.toWire(c['cents'] as int), c['text']);
    }
  });

  test('formats for people', () {
    expect(Money.format(0), 'KES 0.00');
    expect(Money.format(125050), 'KES 1,250.50');
    expect(Money.format(123456789), 'KES 1,234,567.89');
    expect(Money.format(-5), '-KES 0.05');
    expect(Money.format(125000, compact: true), 'KES 1,250');
    expect(Money.format(125050, compact: true), 'KES 1,250.50');
  });
}
