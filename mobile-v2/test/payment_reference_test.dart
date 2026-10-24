import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/features/ledger/domain/payment_reference.dart';

// The same cases as server-v2/internal/payment/shared_vectors_test.go.
void main() {
  final v =
      jsonDecode(
            File(
              '../testdata/shared/payment_reference.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  PaymentMethod method(Object? m) => PaymentMethod.values.byName(m! as String);

  test('accepts and stores what the server does', () {
    for (final c in (v['valid'] as List).cast<Map<String, dynamic>>()) {
      final r = PaymentReference.check(
        method(c['method']),
        c['text'] as String,
      );
      expect(r.problem, isNull, reason: '${c['text']}');
      expect(r.stored, c['stored'], reason: '${c['text']}');
    }
  });

  test('refuses what the server refuses', () {
    for (final c in (v['invalid'] as List).cast<Map<String, dynamic>>()) {
      final r = PaymentReference.check(
        method(c['method']),
        c['text'] as String,
      );
      expect(r.problem, isNotNull, reason: '${c['text']}');
    }
  });
}
