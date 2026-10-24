import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/quantity/quantity.dart';
import 'package:salio/features/sales/domain/sale_debt.dart';

// The same cases as server-v2/internal/sales/shared_vectors_test.go.
void main() {
  final v =
      jsonDecode(File('../testdata/shared/sale_debt.json').readAsStringSync())
          as Map<String, dynamic>;

  test('the namespace is the server\'s', () {
    expect(SaleDebt.namespace, v['namespace']);
  });

  test('a credit sale\'s debt has the id the server gives it', () {
    final ids = (v['ids'] as List).cast<Map<String, dynamic>>();
    expect(ids, isNotEmpty);
    for (final c in ids) {
      expect(SaleDebt.idFor(c['sale'] as String), c['debt']);
      expect(
        SaleDebt.idFor((c['sale'] as String).toUpperCase()),
        c['debt'],
        reason: 'the id\'s text is read in lower case',
      );
    }
  });

  test('and the server\'s words', () {
    final cases = (v['descriptions'] as List).cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);
    for (final c in cases) {
      expect(
        SaleDebt.description(
          c['product'] as String,
          Quantity.parse(c['quantity'] as String),
        ),
        c['want'],
      );
    }
  });
}
