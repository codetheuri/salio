import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/phone/phone.dart';

// The same cases as server-v2/internal/phone/phone_test.go and the SQL of
// migration 00010.
void main() {
  final vectors =
      jsonDecode(File('../testdata/shared/phone.json').readAsStringSync())
          as Map<String, dynamic>;

  test('stores what the server stores', () {
    for (final c
        in (vectors['normalize'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      expect(
        Phone.normalize(c['text'] as String),
        c['e164'],
        reason: '${c['text']}',
      );
    }
  });

  test('refuses what the server refuses', () {
    for (final text in (vectors['invalid'] as List<dynamic>).cast<String>()) {
      expect(Phone.normalize(text), isNull, reason: '"$text"');
    }
  });

  test('shows a Kenyan number the way shops say it', () {
    expect(Phone.display('+254712345678'), '0712 345 678');
    expect(Phone.display('+442079460958'), '+442079460958');
    expect(Phone.display('ask at the counter'), 'ask at the counter');
  });

  test('searches by the digits that matter', () {
    expect(Phone.searchDigits('0712 3'), '7123');
    expect(Phone.searchDigits('+254 712'), '712');
    expect(Phone.searchDigits('Mama 2'), isNull);
  });
}
