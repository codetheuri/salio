import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/quantity/quantity.dart';

// The same cases as server-v2/internal/quantity/shared_vectors_test.go.
void main() {
  final vectors =
      jsonDecode(File('../testdata/shared/quantity.json').readAsStringSync())
          as Map<String, dynamic>;

  test('parses what the server parses', () {
    for (final c
        in (vectors['parse'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(
        Quantity.parse(c['text'] as String),
        c['thousandths'],
        reason: '${c['text']}',
      );
    }
  });

  test('refuses what the server refuses', () {
    for (final text in (vectors['invalid'] as List<dynamic>).cast<String>()) {
      expect(
        () => Quantity.parse(text),
        throwsFormatException,
        reason: '"$text"',
      );
    }
  });

  test('writes what the server writes', () {
    for (final c
        in (vectors['wire'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(Quantity.toWire(c['thousandths'] as int), c['text']);
    }
  });
}
