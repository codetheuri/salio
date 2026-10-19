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
  }) => db
      .into(db.ledgerEntries)
      .insert(
        LedgerEntriesCompanion.insert(
          id: '0197a000-0000-7000-8000-${(++n).toString().padLeft(12, '0')}',
          customerId: customerId,
          userId: 'u1',
          type: type,
          amountCents: cents,
          description: Value(description),
          transactionDate: t.add(Duration(hours: n)),
          createdAt: t,
          updatedAt: t,
          syncState: state,
        ),
      );

  await customer(
    longCustomerId,
    'Bartholomew Kipchumba Arap Kiprotich Wanyonyi',
    '+254 712 345 678',
  );
  await entry(
    longCustomerId,
    'debt',
    123456789,
    'Two bags of fertiliser, three litres of cooking oil and a crate of '
        'sodas, to be paid at the end of the month',
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
    '0700111222',
  );
  await entry('0197a000-0000-7000-8000-00000000000c', 'payment', 20000, 'Cash');
  for (var i = 0; i < 12; i++) {
    final id =
        '0197a000-0000-7000-8000-0000000001${i.toString().padLeft(2, '0')}';
    await customer(id, 'Customer number $i', '07000000$i');
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
