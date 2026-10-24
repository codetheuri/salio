import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/phone/phone.dart';
import '../../../core/time/server_clock.dart';
import '../../ledger/domain/dues.dart';

/// Which customers the list shows (docs/10, §2.3).
enum CustomerFilter {
  all,

  /// Owe the shop something.
  owing,

  /// Owe something past its agreed day.
  overdue,

  /// Owe more than their credit limit.
  overLimit,

  /// Hold an advance: the shop owes them.
  advance,

  /// Owe nothing and are owed nothing.
  cleared;

  bool matches(CustomerBalance c) => switch (this) {
    all => true,
    owing => c.balanceCents > 0,
    overdue => c.dues.isOverdue,
    overLimit => c.isOverLimit,
    advance => c.balanceCents < 0,
    cleared => c.balanceCents == 0,
  };
}

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

  /// What is owed and when it falls due, by the server's first-in,
  /// first-out rule.
  final Dues dues;

  const CustomerBalance(
    this.customer,
    this.balanceCents,
    this.unsent, {
    this.refused = 0,
    this.dues = Dues.none,
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

  int? get creditLimitCents => customer.creditLimitCents;

  /// How much more they may owe before reaching their limit; null with no
  /// limit, below zero when over it.
  int? get availableCents {
    final limit = creditLimitCents;
    return limit == null ? null : limit - balanceCents;
  }

  bool get isOverLimit => (availableCents ?? 0) < 0;

  /// Whether a debt of [cents] would take them over their limit. Only a
  /// warning: the shop decides (the server records it either way).
  bool wouldExceedLimit(int cents) {
    final available = availableCents;
    return available != null && cents > available;
  }
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

  /// Every live entry of the customers who have a debt with a due date, in
  /// the order dues are worked out: only those customers can be overdue or
  /// due soon, so the others are not read at all.
  static const _dueLines = '''
    SELECT customer_id, type, amount_cents, due_date FROM ledger_entries
    WHERE is_deleted = 0 AND customer_id IN (
      SELECT customer_id FROM ledger_entries
      WHERE is_deleted = 0 AND type = 'debt' AND due_date IS NOT NULL {filter})
    ORDER BY customer_id, transaction_date, created_at
  ''';

  CustomerBalance _read(QueryRow row, Dues dues) => CustomerBalance(
    db.customers.map(row.data),
    row.read<int>('balance_cents'),
    row.read<int>('unsent'),
    refused: row.read<int>('refused'),
    dues: dues,
  );

  Future<Map<String, Dues>> _dues(DateTime today, {String? customerId}) async {
    final rows = await db
        .customSelect(
          _dueLines.replaceFirst(
            '{filter}',
            customerId == null ? '' : 'AND customer_id = ?',
          ),
          variables: [if (customerId != null) Variable.withString(customerId)],
        )
        .get();
    final lines = <String, List<DueLine>>{};
    for (final r in rows) {
      (lines[r.read<String>('customer_id')] ??= []).add(
        DueLine(
          isDebt: r.read<String>('type') == 'debt',
          cents: r.read<int>('amount_cents'),
          due: r.readNullable<DateTime>('due_date'),
        ),
      );
    }
    return {for (final e in lines.entries) e.key: Dues.of(e.value, today)};
  }

  /// Live customers with their balances and dues, by name, that match
  /// [search] (name, or phone digits in any form) and [filter]. Updates
  /// itself when anything changes, including a sync bringing in another
  /// phone's entry.
  Stream<List<CustomerBalance>> watchList({
    required DateTime today,
    String search = '',
    CustomerFilter filter = CustomerFilter.all,
  }) {
    final term = search.trim();
    final digits = Phone.searchDigits(term);
    final where = term.isEmpty
        ? ''
        : digits == null
        ? r"AND c.name LIKE ? ESCAPE '\'"
        : r"AND (c.name LIKE ? ESCAPE '\' OR c.phone LIKE ?)";
    return db
        .customSelect(
          '${_withBalances.replaceFirst('{filter}', where)} '
          'ORDER BY c.name COLLATE NOCASE',
          variables: [
            if (term.isNotEmpty) Variable.withString('%${_escape(term)}%'),
            if (term.isNotEmpty && digits != null)
              Variable.withString('%$digits%'),
          ],
          readsFrom: {db.customers, db.ledgerEntries},
        )
        .watch()
        .asyncMap((rows) async {
          final dues = await _dues(today);
          return [
            for (final row in rows)
              _read(row, dues[row.read<String>('id')] ?? Dues.none),
          ].where(filter.matches).toList();
        });
  }

  /// Every live customer, by name.
  Stream<List<CustomerBalance>> watchAll() => watchList(today: clock.now());

  Stream<CustomerBalance?> watch(String id, {DateTime? today}) => db
      .customSelect(
        _withBalances.replaceFirst('{filter}', 'AND c.id = ?'),
        variables: [Variable.withString(id)],
        readsFrom: {db.customers, db.ledgerEntries},
      )
      .watchSingleOrNull()
      .asyncMap((row) async {
        if (row == null) return null;
        final dues = await _dues(today ?? clock.now(), customerId: id);
        return _read(row, dues[id] ?? Dues.none);
      });

  /// A live customer already holding [phone] (in any form), other than
  /// [except]: adding them again would be refused by the server as a
  /// duplicate, so the screen offers the existing one.
  Future<CustomerRow?> findByPhone(String phone, {String? except}) async {
    final stored = Phone.normalize(phone);
    if (stored == null) return null;
    final query = db.select(db.customers)
      ..where(
        (c) =>
            c.phone.equals(stored) &
            c.isDeleted.equals(false) &
            (except == null ? const Constant(true) : c.id.equals(except).not()),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Adds a customer on this phone. Returns its id. [phone] may be in any
  /// form, and is stored as the server stores it (B15); null or blank is a
  /// walk-in customer with no phone.
  Future<String> add({required String name, String? phone}) async {
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            name: name.trim(),
            phone: Value(_stored(phone)),
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
  /// survives the merge on the server. A blank [phone] or [notes] clears it.
  Future<void> update(
    String id, {
    String? name,
    String? phone,
    String? notes,
  }) async {
    final changes = <String, Object?>{
      if (name != null) 'name': name.trim(),
      if (phone != null) 'phone': _stored(phone),
      if (notes != null) 'notes': _blankToNull(notes),
    };
    if (changes.isEmpty) return;
    if (changes['name'] == '') {
      throw ArgumentError.value(name, 'name', 'is required');
    }
    await _change(id, changes);
  }

  /// Sets, or with null removes, how much the customer may owe (owners;
  /// the server refuses anyone else).
  Future<void> setCreditLimit(String id, int? cents) {
    if (cents != null && cents < 0) {
      throw ArgumentError.value(cents, 'cents', 'cannot be negative');
    }
    return _change(id, {'credit_limit': cents});
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
        Value<T> pick<T>(String field) => changes.containsKey(field)
            ? Value(changes[field] as T)
            : const Value.absent();
        await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
          CustomersCompanion(
            name: pick<String>('name'),
            phone: pick<String?>('phone'),
            notes: pick<String?>('notes'),
            creditLimitCents: pick<int?>('credit_limit'),
            isDeleted: pick<bool>('is_deleted'),
            updatedAt: Value(clock.now()),
            syncState: const Value(SyncState.pending),
            localVersion: Value(row.localVersion + 1),
            changedFields: Value(
              isNew ? '' : (fields.toList()..sort()).join(','),
            ),
          ),
        );
      });

  /// A number in its stored form; blank is none. An unreadable number is
  /// refused here: the screens check it first, so this is a bug guard.
  static String? _stored(String? phone) {
    final raw = _blankToNull(phone);
    if (raw == null) return null;
    final stored = Phone.normalize(raw);
    if (stored == null) {
      throw ArgumentError.value(phone, 'phone', 'is not a phone number');
    }
    return stored;
  }

  static String? _blankToNull(String? s) =>
      s == null || s.trim().isEmpty ? null : s.trim();

  /// LIKE treats % and _ as wildcards; a name with either is searched for
  /// as typed.
  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
