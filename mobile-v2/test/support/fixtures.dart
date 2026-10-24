// Data and fakes for widget tests: a seeded in-memory database, a fixed
// session, and a network that is always offline.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/session/account_store.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/core/session/session.dart';
import 'package:salio/core/session/session_controller.dart';

/// A customer the layout tests open, with a long name and a large balance.
const longCustomerId = '0197a000-0000-7000-8000-00000000000a';

/// Their first entry: a long description, overdue, recorded by staff.
const longEntryId = '0197a000-0000-7000-8000-000000000001';

/// The member of staff who recorded it, with a long name.
const staffUserId = '0197a000-0000-7000-8000-0000000000u2';

Session sessionFor(Role role) => Session(
  Account(
    userId: '0197a000-0000-7000-8000-0000000000u1',
    businessId: '0197a000-0000-7000-8000-0000000000b1',
    name: role == Role.owner ? 'Amina Wanjiku Mwangi' : 'Juma Otieno',
    phone: '0712345678',
    role: role,
    businessName: 'Mama Amina General Store and Agrovet',
    lastUsedAt: DateTime.utc(2026, 10, 19),
  ),
  'token',
);

/// A session controller that is already signed in, or signed out.
class FixedSession extends SessionController {
  final Session? session;

  FixedSession(this.session);

  @override
  Future<Session?> build() async => session;

  @override
  Future<void> signOut() async => state = const AsyncData(null);

  @override
  Future<void> endedByServer(String reason) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(Session(current.account, null, endedReason: reason));
  }
}

/// An in-memory database with customers whose names and amounts push the
/// layout: very long, very large, zero, an advance, unsent.
Future<AppDatabase> seededDatabase() async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  // Streams close at once when a screen stops listening, instead of on a
  // timer that a widget test's fake clock would never fire.
  final db = AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
  final t = DateTime.utc(2026, 10, 14, 7, 15);
  Future<void> customer(String id, String name, String? phone) => db
      .into(db.customers)
      .insert(
        CustomersCompanion.insert(
          id: id,
          name: name,
          phone: Value(phone),
          createdBy: 'u1',
          createdAt: t,
          updatedAt: t,
          syncState: SyncState.synced,
        ),
      );
  var n = 0;
  Future<void> entry(
    String customerId,
    String type,
    int cents,
    String description, {
    SyncState state = SyncState.synced,
    DateTime? due,
    String userId = 'u1',
  }) => db
      .into(db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          id: '0197a000-0000-7000-8000-${(++n).toString().padLeft(12, '0')}',
          customerId: customerId,
          userId: userId,
          type: type,
          amountCents: cents,
          description: Value(description),
          dueDate: Value(due),
          transactionDate: t.add(Duration(hours: n)),
          createdAt: t,
          updatedAt: t,
          syncState: state,
        ),
      );

  await customer(
    longCustomerId,
    'Bartholomew Kipchumba Arap Kiprotich Wanyonyi',
    '+254712345678',
  );
  await entry(
    longCustomerId,
    'debt',
    123456789,
    'Two bags of fertiliser, three litres of cooking oil and a crate of '
        'sodas, to be paid at the end of the month',
    due: DateTime.utc(2026, 10, 1),
    userId: staffUserId,
  );
  // Over a limit, so the account card shows its longest lines.
  await (db.update(db.customers)..where((c) => c.id.equals(longCustomerId)))
      .write(const CustomersCompanion(creditLimitCents: Value(10000000)));
  await db
      .into(db.staffMembers)
      .insert(
        StaffMembersCompanion.insert(
          id: staffUserId,
          name: 'Wanjiru Nyambura Kamau-Odhiambo',
          role: 'staff',
          isActive: true,
        ),
      );
  await entry(longCustomerId, 'payment', 50000, 'M-Pesa');
  await entry(
    longCustomerId,
    'debt',
    1500,
    'Matches',
    state: SyncState.pending,
  );
  await customer('0197a000-0000-7000-8000-00000000000b', 'Akinyi', null);
  await customer(
    '0197a000-0000-7000-8000-00000000000c',
    'Otieno',
    '+254700111222',
  );
  await entry('0197a000-0000-7000-8000-00000000000c', 'payment', 20000, 'Cash');
  // One issue of each sort the Needs attention screen words differently,
  // on records with the longest names: a refused payment, a duplicate
  // customer the phone can merge, notes the server undid a change, a
  // record waiting for its customer, and one no longer on the phone.
  const duplicate = '0197a000-0000-7000-8000-00000000000d';
  await customer(duplicate, 'Otieno', '+254700111222');
  await (db.update(db.customers)..where((c) => c.id.equals(duplicate))).write(
    const CustomersCompanion(syncState: Value(SyncState.refused)),
  );
  await entry(
    longCustomerId,
    'payment',
    99999999,
    'M-Pesa',
    state: SyncState.refused,
  );
  Future<void> issue(String table, String id, String reason) => db
      .into(db.syncIssues)
      .insert(
        SyncIssuesCompanion.insert(
          recordTable: table,
          recordId: id,
          reason: reason,
          createdAt: t,
        ),
      );
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-${n.toString().padLeft(12, '0')}',
    'duplicate',
  );
  await issue('customers', duplicate, 'duplicate');
  await issue('customers', longCustomerId, 'has_balance');
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-000000000001',
    'forbidden',
  );
  await issue(
    'transactions',
    '0197a000-0000-7000-8000-000000000003',
    'unknown_customer',
  );
  await issue('sales', 'gone', 'invalid');

  for (var i = 0; i < 12; i++) {
    final id =
        '0197a000-0000-7000-8000-0000000001${i.toString().padLeft(2, '0')}';
    await customer(
      id,
      'Customer number $i',
      '+2547000001${i.toString().padLeft(2, '0')}',
    );
    await entry(id, 'debt', 1000 * (i + 1), 'Bread');
  }
  return db;
}

/// No network: every request fails as it does with no signal.
class OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => throw DioException.connectionError(
    requestOptions: options,
    reason: 'offline in tests',
  );

  @override
  void close({bool force = false}) {}
}
