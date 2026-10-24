import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/phone/phone.dart';
import '../../../core/time/server_clock.dart';
import '../../ledger/domain/payment_reference.dart';

/// A supplier with what the shop owes them: bills minus payments over live
/// entries, derived every time (domain invariant 3). Above zero the shop
/// owes them; below zero they hold a prepayment.
class SupplierBalance {
  final SupplierRow supplier;
  final int balanceCents;

  /// Entries not yet accepted by the server, and of those, the refused.
  final int unsent;
  final int refused;

  const SupplierBalance(
    this.supplier,
    this.balanceCents,
    this.unsent, {
    this.refused = 0,
  });

  SyncState get syncState =>
      refused > 0 || supplier.syncState == SyncState.refused
      ? SyncState.refused
      : unsent > 0 || supplier.syncState != SyncState.synced
      ? SyncState.pending
      : SyncState.synced;
}

/// Suppliers and their bills and payments: the customer ledger turned
/// around. Owners only, by default; a phone without `suppliers.read` never
/// receives any (live scenario 9). The rules are the server's
/// (`supplier.ValidateSupplier`, `supplier.ValidateEntry`).
class SupplierRepository {
  final AppDatabase db;
  final ServerClock clock;
  final String userId;

  SupplierRepository(this.db, this.clock, this.userId);

  static const _withBalances = '''
    SELECT s.*,
      COALESCE(SUM(CASE WHEN e.type = 'bill' THEN e.amount_cents
                        ELSE -e.amount_cents END), 0) AS balance_cents,
      COALESCE(SUM(CASE WHEN e.sync_state != 0 THEN 1 ELSE 0 END), 0) AS unsent,
      COALESCE(SUM(CASE WHEN e.sync_state = 2 THEN 1 ELSE 0 END), 0) AS refused
    FROM suppliers s
    LEFT JOIN supplier_entries e ON e.supplier_id = s.id AND e.is_deleted = 0
    WHERE s.is_deleted = 0 {filter}
    GROUP BY s.id
  ''';

  SupplierBalance _read(QueryRow row) => SupplierBalance(
    db.suppliers.map(row.data),
    row.read<int>('balance_cents'),
    row.read<int>('unsent'),
    refused: row.read<int>('refused'),
  );

  /// Live suppliers by name, matching [search] in the name or phone.
  Stream<List<SupplierBalance>> watchList({String search = ''}) {
    final term = search.trim();
    final digits = Phone.searchDigits(term);
    final where = term.isEmpty
        ? ''
        : digits == null
        ? r"AND s.name LIKE ? ESCAPE '\'"
        : r"AND (s.name LIKE ? ESCAPE '\' OR s.phone LIKE ?)";
    return db
        .customSelect(
          '${_withBalances.replaceFirst('{filter}', where)} '
          'ORDER BY s.name COLLATE NOCASE',
          variables: [
            if (term.isNotEmpty) Variable.withString('%${_escape(term)}%'),
            if (term.isNotEmpty && digits != null)
              Variable.withString('%$digits%'),
          ],
          readsFrom: {db.suppliers, db.supplierEntries},
        )
        .watch()
        .map((rows) => rows.map(_read).toList());
  }

  Stream<SupplierBalance?> watch(String id) => db
      .customSelect(
        _withBalances.replaceFirst('{filter}', 'AND s.id = ?'),
        variables: [Variable.withString(id)],
        readsFrom: {db.suppliers, db.supplierEntries},
      )
      .watchSingleOrNull()
      .map((row) => row == null ? null : _read(row));

  /// A supplier's bills and payments, newest first, voided ones included.
  Stream<List<SupplierEntryRow>> watchEntries(String supplierId) =>
      (db.select(db.supplierEntries)
            ..where((e) => e.supplierId.equals(supplierId))
            ..orderBy([
              (e) => OrderingTerm.desc(e.transactionDate),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .watch();

  Stream<SupplierEntryRow?> watchEntry(String id) => (db.select(
    db.supplierEntries,
  )..where((e) => e.id.equals(id))).watchSingleOrNull();

  /// Adds a supplier. [phone] is optional, in any form, stored as E.164.
  Future<String> add({
    required String name,
    String phone = '',
    String notes = '',
  }) async {
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: id,
            name: _name(name),
            phone: Value(_phone(phone)),
            notes: Value(_blankToNull(notes)),
            createdBy: userId,
            createdAt: now,
            updatedAt: now,
            syncState: SyncState.pending,
          ),
        );
    return id;
  }

  Future<void> update(
    String id, {
    required String name,
    String phone = '',
    String notes = '',
  }) => _change(
    id,
    SuppliersCompanion(
      name: Value(_name(name)),
      phone: Value(_phone(phone)),
      notes: Value(_blankToNull(notes)),
    ),
  );

  /// Removes a supplier: only at a zero balance, which the server checks
  /// again (`has_balance`).
  Future<void> delete(String id) =>
      _change(id, const SuppliersCompanion(isDeleted: Value(true)));

  Future<void> _change(String id, SuppliersCompanion change) =>
      db.transaction(() async {
        final row = await (db.select(
          db.suppliers,
        )..where((s) => s.id.equals(id))).getSingle();
        await (db.update(db.suppliers)..where((s) => s.id.equals(id))).write(
          change.copyWith(
            updatedAt: Value(clock.now()),
            syncState: const Value(SyncState.pending),
            localVersion: Value(row.localVersion + 1),
          ),
        );
      });

  /// Goods received on credit: the shop now owes the supplier. [dueDate]
  /// is the day it is to be paid by, as UTC midnight.
  Future<String> recordBill({
    required String supplierId,
    required int amountCents,
    required String description,
    DateTime? dueDate,
  }) => _entry(
    supplierId: supplierId,
    type: 'bill',
    amountCents: amountCents,
    description: description,
    dueDate: dueDate == null
        ? null
        : DateTime.utc(dueDate.year, dueDate.month, dueDate.day),
  );

  /// The shop paying a supplier: a method is required, and an M-Pesa code
  /// or bank reference follows the payment rule.
  Future<String> recordPayment({
    required String supplierId,
    required int amountCents,
    required PaymentMethod method,
    String reference = '',
    required String description,
  }) {
    final ref = PaymentReference.check(method, reference);
    if (ref.problem != null) {
      throw ArgumentError.value(reference, 'reference', ref.problem!.name);
    }
    return _entry(
      supplierId: supplierId,
      type: 'payment',
      amountCents: amountCents,
      description: description,
      method: method.wire,
      reference: ref.stored,
    );
  }

  Future<String> _entry({
    required String supplierId,
    required String type,
    required int amountCents,
    required String description,
    DateTime? dueDate,
    String? method,
    String? reference,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
    }
    final text = description.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(description, 'description', 'is required');
    }
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.supplierEntries)
        .insert(
          SupplierEntriesCompanion.insert(
            id: id,
            supplierId: supplierId,
            userId: userId,
            type: type,
            amountCents: amountCents,
            description: text,
            transactionDate: now,
            dueDate: Value(dueDate),
            paymentMethod: Value(method),
            reference: Value(reference),
            createdAt: now,
            updatedAt: now,
            syncState: SyncState.pending,
          ),
        );
    return id;
  }

  /// Voids a bill or payment (owners): it stays in the history, crossed
  /// out, and leaves the balance.
  Future<void> voidEntry(String id) => db.transaction(() async {
    final row = await (db.select(
      db.supplierEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    if (row.isDeleted) return;
    await (db.update(db.supplierEntries)..where((e) => e.id.equals(id))).write(
      SupplierEntriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(clock.now()),
        syncState: const Value(SyncState.pending),
        localVersion: Value(row.localVersion + 1),
      ),
    );
  });

  static String _name(String name) {
    final t = name.trim();
    if (t.isEmpty) throw ArgumentError.value(name, 'name', 'is required');
    return t;
  }

  static String? _phone(String phone) {
    if (phone.trim().isEmpty) return null;
    return Phone.normalize(phone) ??
        (throw ArgumentError.value(phone, 'phone', 'not a phone number'));
  }

  static String? _blankToNull(String s) => s.trim().isEmpty ? null : s.trim();

  static String _escape(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
