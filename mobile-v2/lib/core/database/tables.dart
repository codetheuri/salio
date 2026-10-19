import 'package:drift/drift.dart';

/// Where a record stands with the server.
enum SyncState {
  /// The server has this version.
  synced,

  /// Changed on this phone and not yet accepted by the server.
  pending,

  /// The server refused it; a sync issue says why. Not sent again until the
  /// user resolves it (M2).
  refused,
}

/// Columns every synced record has on the phone.
///
/// There is no business_id: each account has its own database file, so a
/// file holds exactly one shop (docs/10, D5). A cross-shop leak would need
/// the wrong file, not a forgotten filter.
mixin SyncedRecord on Table {
  TextColumn get id => text()();
  DateTimeColumn get createdAt => dateTime()();

  /// When this version was made, by the server's clock (docs/10, D8).
  DateTimeColumn get updatedAt => dateTime()();

  /// A tombstone: nothing is deleted outright, or the next sync from another
  /// phone would bring it back.
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  IntColumn get syncState => intEnum<SyncState>()();

  /// Goes up with every local change. A push batch remembers the version it
  /// carried; a record edited while its batch was in flight stays pending
  /// for the next one (docs/10, §4.3).
  IntColumn get localVersion => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CustomerRow')
class Customers extends Table with SyncedRecord {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
  IntColumn get creditLimitCents => integer().nullable()();

  /// The fields edited on this phone since the last accepted push, comma
  /// separated. Empty while pending means a new record: all of it is ours.
  TextColumn get changedFields => text().withDefault(const Constant(''))();
}

@DataClassName('LedgerEntryRow')
class LedgerEntries extends Table with SyncedRecord {
  /// Not a foreign key, on purpose. Pull pages follow the server's single
  /// change sequence across every table, so an entry can arrive before its
  /// customer does (when the customer was edited after the entry was made).
  /// A foreign key would fail that page, and with it a new phone's first
  /// sync. The server guarantees the link.
  TextColumn get customerId => text()();
  TextColumn get userId => text()();

  /// `debt` or `payment`.
  TextColumn get type => text()();

  /// Always above zero; the type gives the direction.
  IntColumn get amountCents => integer()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get transactionDate => dateTime()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get saleId => text().nullable()();

  @override
  String get tableName => 'ledger_entries';
}

/// Small values the sync engine keeps: the pull cursor, the clock offset,
/// the last successful sync.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// A push batch, frozen before it is sent: its operation_id and its exact
/// body. A retry sends this body again, so the server's replay of its first
/// answer is always an answer to the same records (docs/10, §4.3).
@DataClassName('PushBatchRow')
class PushBatches extends Table {
  TextColumn get operationId => text()();

  /// The JSON body, exactly as sent.
  TextColumn get body => text()();

  /// The records it carries and the local version of each, as JSON:
  /// `[{"table":"customers","id":"…","version":3}, …]`.
  TextColumn get records => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

/// What the server refused, for the "Needs attention" screen (M2).
@DataClassName('SyncIssueRow')
class SyncIssues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordTable => text()();
  TextColumn get recordId => text()();
  TextColumn get field => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get detail => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
