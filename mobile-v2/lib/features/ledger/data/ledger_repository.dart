import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/time/server_clock.dart';

/// Reads and records ledger entries. Entries are never edited: a mistake is
/// corrected with a void and a new entry (domain invariant 2).
class LedgerRepository {
  final AppDatabase db;
  final ServerClock clock;

  /// Who is signed in: the entry's `user_id`, "recorded by".
  final String userId;

  LedgerRepository(this.db, this.clock, this.userId);

  /// A customer's live entries, newest first.
  Stream<List<LedgerEntryRow>> watchFor(String customerId) =>
      (db.select(db.ledgerEntries)
            ..where(
              (e) =>
                  e.customerId.equals(customerId) & e.isDeleted.equals(false),
            )
            ..orderBy([
              (e) => OrderingTerm.desc(e.transactionDate),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
          .watch();

  /// Records a debt on this phone, dated by the server's clock. Returns its
  /// id. The amount is in cents and must be above zero; the description is
  /// required, as on the server (`ledger.ValidateEntry`).
  Future<String> recordDebt({
    required String customerId,
    required int amountCents,
    required String description,
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
            syncState: SyncState.pending,
          ),
        );
    return id;
  }
}
