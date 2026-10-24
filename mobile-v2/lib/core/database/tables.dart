import 'package:drift/drift.dart';

/// Where a record stands with the server.
enum SyncState {
  /// The server has this version.
  synced,

  /// Changed on this phone and not yet accepted by the server.
  pending,

  /// The server refused it; a sync issue says why. Not sent again until the
  /// user resolves it, or, for a record waiting on another, until that one
  /// is accepted.
  refused,
}

/// Columns every synced record has on the phone. Each table indexes its
/// sync_state, which sync uses to find what to send, and the column the
/// screens list it by.
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
@TableIndex(name: 'customers_sync_state', columns: {#syncState})
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
@TableIndex(name: 'ledger_entries_customer', columns: {#customerId, #isDeleted})
@TableIndex(name: 'ledger_entries_sync_state', columns: {#syncState})
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

/// A sale. Immutable once the server has it, like a ledger entry: only a
/// void changes it. A credit sale's debt is a ledger entry the server makes
/// from the sale (`SaleDebtID`), and pulled like any other.
@DataClassName('SaleRow')
@TableIndex(name: 'sales_customer', columns: {#customerId, #isDeleted})
@TableIndex(name: 'sales_sync_state', columns: {#syncState})
class Sales extends Table with SyncedRecord {
  /// Set on a credit sale; not a foreign key, for the reason on
  /// [LedgerEntries.customerId].
  TextColumn get customerId => text().nullable()();
  TextColumn get userId => text()();
  TextColumn get productName => text()();

  /// In thousandths: 1.5 bags is 1500.
  IntColumn get quantity => integer()();
  IntColumn get amountCents => integer()();

  /// `cash`, `mpesa`, `bank` or `credit`.
  TextColumn get paymentMethod => text()();
  TextColumn get reference => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get saleDate => dateTime()();
}

/// A stock note: something the shop needs to buy. Editable until it is on a
/// purchase order, which only the server records.
@DataClassName('StockRequestRow')
@TableIndex(name: 'stock_requests_sync_state', columns: {#syncState})
class StockRequests extends Table with SyncedRecord {
  TextColumn get userId => text()();
  TextColumn get productName => text()();
  DateTimeColumn get neededOn => dateTime()();
  TextColumn get notes => text().nullable()();

  /// Set by the server when the note goes on an order; never sent.
  TextColumn get purchaseOrderId => text().nullable()();

  @override
  String get tableName => 'stock_requests';
}

/// A supplier. Only phones allowed to read suppliers receive them (owners,
/// by default).
@DataClassName('SupplierRow')
@TableIndex(name: 'suppliers_sync_state', columns: {#syncState})
class Suppliers extends Table with SyncedRecord {
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text()();
}

/// A supplier's bill or a payment to them; `supplier_transactions` on the
/// wire. Immutable once recorded, like a ledger entry.
@DataClassName('SupplierEntryRow')
@TableIndex(
  name: 'supplier_entries_supplier',
  columns: {#supplierId, #isDeleted},
)
@TableIndex(name: 'supplier_entries_sync_state', columns: {#syncState})
class SupplierEntries extends Table with SyncedRecord {
  /// Not a foreign key, for the reason on [LedgerEntries.customerId].
  TextColumn get supplierId => text()();
  TextColumn get userId => text()();

  /// `bill` or `payment`.
  TextColumn get type => text()();
  IntColumn get amountCents => integer()();
  TextColumn get description => text()();
  DateTimeColumn get transactionDate => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get paymentMethod => text().nullable()();
  TextColumn get reference => text().nullable()();
  TextColumn get purchaseOrderId => text().nullable()();

  @override
  String get tableName => 'supplier_entries';
}

/// Records a resync has received so far (docs/10, §4.3). When the last page
/// is in, synced rows not listed here are ones the server no longer has,
/// and are removed. Saved with each page, so a resync cut short carries on.
@DataClassName('ResyncSeenRow')
class ResyncSeen extends Table {
  TextColumn get recordTable => text()();
  TextColumn get recordId => text()();

  @override
  Set<Column<Object>> get primaryKey => {recordTable, recordId};
}

/// The shop's people, from the team list (`list-staff`), so every entry can
/// say who recorded it, offline too. Refreshed when the app opens online;
/// never written on the phone.
@DataClassName('StaffMemberRow')
class StaffMembers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();

  /// `owner` or `staff`.
  TextColumn get role => text()();
  BoolColumn get isActive => boolean()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  String get tableName => 'staff_members';
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

/// What the server refused, or a change it undid, for the "Needs attention"
/// screen. The reasons are server-v2's (`syncengine.Reason*`).
@DataClassName('SyncIssueRow')
class SyncIssues extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordTable => text()();
  TextColumn get recordId => text()();
  TextColumn get field => text().nullable()();
  TextColumn get reason => text()();
  TextColumn get detail => text().nullable()();

  /// The server's copy of the record when it refused a change to one it
  /// holds, as JSON (B2). "Discard mine" puts it back; without one, the
  /// record never reached the server and discarding removes it.
  TextColumn get serverCopy => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
