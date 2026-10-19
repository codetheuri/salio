import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/server_clock.dart';

/// A customer with their balance: debts minus payments over live entries,
/// computed every time and never stored (domain invariant 3). Above zero
/// they owe the shop; below zero they hold an advance.
class CustomerBalance {
  final CustomerRow customer;
  final int balanceCents;

  /// Entries for this customer not yet accepted by the server.
  final int unsent;

  const CustomerBalance(this.customer, this.balanceCents, this.unsent);

  bool get isUnsent => unsent > 0 || customer.syncState != SyncState.synced;
}

/// Reads and writes customers. Every write marks the record pending in the
/// same statement, so the change and its "needs sending" mark cannot part.
class CustomerRepository {
  final AppDatabase db;
  final ServerClock clock;

  /// Who is signed in: the customer's `created_by`.
  final String userId;

  CustomerRepository(this.db, this.clock, this.userId);

  static const _withBalances = '''
    SELECT c.*,
      COALESCE(SUM(CASE WHEN e.type = 'debt' THEN e.amount_cents
                        ELSE -e.amount_cents END), 0) AS balance_cents,
      COALESCE(SUM(CASE WHEN e.sync_state != 0 THEN 1 ELSE 0 END), 0) AS unsent
    FROM customers c
    LEFT JOIN ledger_entries e ON e.customer_id = c.id AND e.is_deleted = 0
    WHERE c.is_deleted = 0 {filter}
    GROUP BY c.id
  ''';

  CustomerBalance _read(QueryRow row) => CustomerBalance(
    db.customers.map(row.data),
    row.read<int>('balance_cents'),
    row.read<int>('unsent'),
  );

  /// Every live customer with their balance, by name. Updates itself when
  /// anything changes, including a sync bringing in another phone's entry.
  Stream<List<CustomerBalance>> watchAll() => db
      .customSelect(
        '${_withBalances.replaceFirst('{filter}', '')} '
        'ORDER BY c.name COLLATE NOCASE',
        readsFrom: {db.customers, db.ledgerEntries},
      )
      .watch()
      .map((rows) => rows.map(_read).toList());

  Stream<CustomerBalance?> watch(String id) => db
      .customSelect(
        _withBalances.replaceFirst('{filter}', 'AND c.id = ?'),
        variables: [Variable.withString(id)],
        readsFrom: {db.customers, db.ledgerEntries},
      )
      .watchSingleOrNull()
      .map((row) => row == null ? null : _read(row));

  /// Adds a customer on this phone. Returns its id.
  Future<String> add({required String name, String? phone}) async {
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            name: name.trim(),
            phone: Value(_blankToNull(phone)),
            createdBy: userId,
            createdAt: now,
            updatedAt: now,
            syncState: SyncState.pending,
          ),
        );
    return id;
  }

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}
