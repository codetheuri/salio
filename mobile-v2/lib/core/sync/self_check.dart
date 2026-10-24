import 'package:logging/logging.dart';

import '../database/app_database.dart';
import '../money/money.dart';
import '../network/api_client.dart';

final _log = Logger('self_check');

/// What the last balance self-check found.
enum SelfCheck {
  /// The phone's totals equal the server's.
  matched,

  /// They differed once. Another phone may have pushed between this phone's
  /// pull and the check, so it is checked again after the next pull.
  differedOnce,

  /// They differed twice in a row: a sync bug no test imagined.
  differs,
}

/// Compares what the phone says the shop is owed, and holds in advances,
/// with the server's summary (docs/10, §4.3). Run when nothing is pending
/// and a pull has just finished, so both should describe the same records.
///
/// An alarm, not a repair: a difference is logged with totals only, never
/// names, and is meant for crash reporting once that is chosen (§13).
class BalanceSelfCheck {
  final AppDatabase db;
  final ApiClient api;

  /// The summary is a heavier query than a pull, so at most this often.
  static const every = Duration(hours: 1);

  static const _lastKey = 'self_check_at';
  static const _resultKey = 'self_check';

  BalanceSelfCheck(this.db, this.api);

  /// Runs the check if one is due, and returns what it found; null when it
  /// was not due or could not be run now.
  Future<SelfCheck?> runIfDue(DateTime now) async {
    final previous = await db.readMeta(_resultKey);
    final last = await db.readMeta(_lastKey);
    // A difference seen once is looked at again on the very next sync.
    if (previous != SelfCheck.differedOnce.name &&
        last != null &&
        now.difference(DateTime.parse(last)) < every) {
      return null;
    }
    if (await _hasUnsent()) return null;

    final local = await _localTotals();
    final summary = await api.get('/reports/summary') as Map<String, dynamic>;
    final owed = Money.parse(summary['total_outstanding_debt'] as String);
    final advances = Money.parse(summary['total_advances_held'] as String);

    final same = owed == local.owed && advances == local.advances;
    final result = same
        ? SelfCheck.matched
        : previous == SelfCheck.differedOnce.name ||
              previous == SelfCheck.differs.name
        ? SelfCheck.differs
        : SelfCheck.differedOnce;
    if (result == SelfCheck.differs) {
      _log.severe(
        'balances differ from the server: phone owed ${local.owed} '
        'advances ${local.advances}, server owed $owed advances $advances',
      );
    }
    await db.writeMeta(_lastKey, now.toUtc().toIso8601String());
    await db.writeMeta(_resultKey, result.name);
    return result;
  }

  Future<bool> _hasUnsent() async {
    final row = await db
        .customSelect(
          'SELECT EXISTS (SELECT 1 FROM customers WHERE sync_state != 0) '
          'OR EXISTS (SELECT 1 FROM ledger_entries WHERE sync_state != 0) '
          'OR EXISTS (SELECT 1 FROM sales WHERE sync_state != 0) '
          'OR EXISTS (SELECT 1 FROM push_batches) AS unsent',
        )
        .getSingle();
    return row.read<bool>('unsent');
  }

  /// The server's formula (`reports.Summary`): live entries of live
  /// customers; owed is the sum of balances above zero, advances of those
  /// below.
  Future<({int owed, int advances})> _localTotals() async {
    final row = await db
        .customSelect(
          '''
      SELECT
        COALESCE(SUM(CASE WHEN balance > 0 THEN balance END), 0) AS owed,
        COALESCE(-SUM(CASE WHEN balance < 0 THEN balance END), 0) AS advances
      FROM (
        SELECT SUM(CASE WHEN e.type = 'debt' THEN e.amount_cents
                        ELSE -e.amount_cents END) AS balance
        FROM ledger_entries e JOIN customers c ON c.id = e.customer_id
        WHERE e.is_deleted = 0 AND c.is_deleted = 0
        GROUP BY e.customer_id
      )
    ''',
          readsFrom: {db.ledgerEntries, db.customers},
        )
        .getSingle();
    return (owed: row.read<int>('owed'), advances: row.read<int>('advances'));
  }
}
