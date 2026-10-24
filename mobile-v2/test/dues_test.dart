import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/features/ledger/domain/dues.dart';

// The same cases as server-v2/internal/reports/shared_vectors_test.go.
void main() {
  final cases =
      (jsonDecode(File('../testdata/shared/dues.json').readAsStringSync())
              as Map<String, dynamic>)['cases']
          as List<dynamic>;
  DateTime? day(Object? s) =>
      s == null ? null : DateTime.parse('${s}T00:00:00Z');
  String? text(DateTime? d) => d?.toIso8601String().substring(0, 10);

  for (final c in cases.cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      final dues = Dues.of(
        [
          for (final l
              in (c['lines'] as List<dynamic>).cast<Map<String, dynamic>>())
            DueLine(
              isDebt: l['type'] == 'debt',
              cents: l['cents'] as int,
              due: day(l['due']),
            ),
        ],
        day(c['as_of'])!,
        withinDays: c['within_days'] as int,
      );
      expect(dues.totalCents, c['total']);
      expect(dues.overdueCents, c['overdue']);
      expect(dues.dueSoonCents, c['due_soon']);
      expect(text(dues.earliestDue), c['earliest_due']);
      expect(text(dues.nextDue), c['next_due']);
    });
  }
}
