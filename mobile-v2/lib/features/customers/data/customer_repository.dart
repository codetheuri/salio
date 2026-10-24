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

  /// Of those, the ones the server refused.
  final int refused;

  const CustomerBalance(
    this.customer,
    this.balanceCents,
    this.unsent, {
    this.refused = 0,
  });

  bool get isUnsent => unsent > 0 || customer.syncState != SyncState.synced;

  /// The customer's own state, or their entries': refused if anything was,
  /// pending if anything waits.
  SyncState get syncState =>
      refused > 0 || customer.syncState == SyncState.refused
      ? SyncState.refused
      : isUnsent
      ? SyncState.pending
      : SyncState.synced;
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
      COALESCE(SUM(CASE WHEN e.sync_state != 0 THEN 1 ELSE 0 END), 0) AS unsent,
      COALESCE(SUM(CASE WHEN e.sync_state = 2 THEN 1 ELSE 0 END), 0) AS refused
    FROM customers c
    LEFT JOIN ledger_entries e ON e.customer_id = c.id AND e.is_deleted = 0
    WHERE c.is_deleted = 0 {filter}
    GROUP BY c.id
  ''';

  CustomerBalance _read(QueryRow row) => CustomerBalance(
    db.customers.map(row.data),
    row.read<int>('balance_cents'),
    row.read<int>('unsent'),
    refused: row.read<int>('refused'),
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

  /// Edits a customer. Only the fields given change, and each is noted in
  /// `changed_fields`, so another phone's edit to a different field
  /// survives the merge on the server.
  Future<void> update(
    String id, {
    String? name,
    String? phone,
    String? notes,
  }) async {
    final changes = <String, Object?>{
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': _blankToNull(phone),
      if (notes != null) 'notes': _blankToNull(notes),
    };
    if (changes.isEmpty) return;
    if (changes['name'] == '') {
      throw ArgumentError.value(name, 'name', 'is required');
    }
    await _change(id, changes);
  }

  /// Deletes a customer (owners only; the server refuses anyone else, and
  /// refuses a balance that is not zero). A tombstone, never a removal: the
  /// deletion has to reach the other phones (domain invariant 4).
  Future<void> delete(String id) => _change(id, {'is_deleted': true});

  /// Writes [changes], marks the customer pending with a new local version,
  /// and adds the fields to `changed_fields`, in one transaction.
  Future<void> _change(String id, Map<String, Object?> changes) =>
      db.transaction(() async {
        final row = await (db.select(
          db.customers,
        )..where((c) => c.id.equals(id))).getSingle();
        // A customer not yet accepted has an empty list, meaning all of it
        // is this phone's; it stays that way.
        final isNew =
            row.syncState != SyncState.synced && row.changedFields.isEmpty;
        final fields = {
          if (row.changedFields.isNotEmpty) ...row.changedFields.split(','),
          ...changes.keys,
        };
        await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            name: changes.containsKey('name')
                ? Value(changes['name']! as String)
                : const Value.absent(),
            phone: changes.containsKey('phone')
                ? Value(changes['phone'] as String?)
                : const Value.absent(),
            notes: changes.containsKey('notes')
                ? Value(changes['notes'] as String?)
                : const Value.absent(),
            isDeleted: changes.containsKey('is_deleted')
                ? const Value(true)
                : const Value.absent(),
            updatedAt: Value(clock.now()),
            syncState: const Value(SyncState.pending),
            localVersion: Value(row.localVersion + 1),
            changedFields: Value(
              isNew ? '' : (fields.toList()..sort()).join(','),
            ),
          ),
        );
      });

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();
}
