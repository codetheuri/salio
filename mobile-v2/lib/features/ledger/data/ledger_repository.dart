import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/server_clock.dart';
import '../domain/payment_reference.dart';

/// Reads and records ledger entries. Entries are never edited: a mistake is
/// corrected with a void and a new entry (domain invariant 2).
class LedgerRepository {
  final AppDatabase db;
  final ServerClock clock;

  /// Who is signed in: the entry's `user_id`, "recorded by".
  final String userId;

  LedgerRepository(this.db, this.clock, this.userId);

  /// A customer's entries, newest first, voided ones included: they stay
  /// in the history, crossed out, and out of the balance.
  Stream<List<LedgerEntryRow>> watchFor(String customerId) =>
      (db.select(db.ledgerEntries)
            ..where((e) => e.customerId.equals(customerId))
            ..orderBy([
              (e) => OrderingTerm.desc(e.transactionDate),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .watch();

  /// Records a payment on this phone. [reference] is an M-Pesa code or a
  /// bank reference, checked by the server's rule; an M-Pesa code may be on
  /// only one live payment, which the server checks (a second phone's copy
  /// comes back as a duplicate). A payment above the balance becomes an
  /// advance, as on the server.
  Future<String> recordPayment({
    required String customerId,
    required int amountCents,
    required PaymentMethod method,
    String reference = '',
    required String description,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description', 'is required');
    }
    final ref = PaymentReference.check(method, reference);
    if (ref.problem != null) {
      throw ArgumentError.value(reference, 'reference', ref.problem!.name);
    }
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            id: id,
            customerId: customerId,
            userId: userId,
            type: 'payment',
            amountCents: amountCents,
            description: Value(description.trim()),
            transactionDate: now,
            createdAt: now,
            updatedAt: now,
            paymentMethod: Value(method.wire),
            reference: Value(ref.stored),
            syncState: SyncState.pending,
          ),
        );
    return id;
  }

  /// Voids an entry (owners only; the server refuses anyone else). The
  /// entry stays, marked deleted, as a paper ledger keeps a crossed-out
  /// line (domain invariant 2).
  Future<void> voidEntry(String id) => db.transaction(() async {
    final row = await (db.select(
      db.ledgerEntries,
    )..where((e) => e.id.equals(id))).getSingle();
    if (row.isDeleted) return;
    await (db.update(db.ledgerEntries)..where((e) => e.id.equals(id))).write(
      LedgerEntriesCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(clock.now()),
        syncState: const Value(SyncState.pending),
        localVersion: Value(row.localVersion + 1),
      ),
    );
  });

  /// One entry, kept up to date: its void, or the server's answer, shows.
  Stream<LedgerEntryRow?> watchEntry(String id) => (db.select(
    db.ledgerEntries,
  )..where((e) => e.id.equals(id))).watchSingleOrNull();

  /// Records a debt on this phone, dated by the server's clock. Returns its
  /// id. The amount is in cents and must be above zero; the description is
  /// required, as on the server (`ledger.ValidateEntry`). [dueDate] is the
  /// day the customer agreed to pay by, held as UTC midnight of that day.
  Future<String> recordDebt({
    required String customerId,
    required int amountCents,
    required String description,
    DateTime? dueDate,
  }) async {
    if (amountCents <= 0) {
      throw ArgumentError.value(amountCents, 'amountCents', 'must be above 0');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(description, 'description', 'is required');
    }
    final now = clock.now();
    final id = const Uuid().v7();
    await db
        .into(db.ledgerEntries)
        .insert(
          LedgerEntriesCompanion.insert(
            id: id,
            customerId: customerId,
            userId: userId,
            type: 'debt',
            amountCents: amountCents,
            description: Value(description.trim()),
            transactionDate: now,
            createdAt: now,
            updatedAt: now,
            dueDate: Value(
              dueDate == null
                  ? null
                  : DateTime.utc(dueDate.year, dueDate.month, dueDate.day),
            ),
            syncState: SyncState.pending,
          ),
        );
    return id;
  }
}
