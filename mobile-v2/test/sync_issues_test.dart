// The "Needs attention" screen and what each of its buttons does to the
// records (docs/10, §4.3). The layout tests cover how it fits.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/session/permissions.dart';
import 'package:salio/features/sync_issues/data/sync_issue_repository.dart';

import 'layout/harness.dart';
import 'support/fixtures.dart';

void main() {
  setUpAll(loadFonts);

  testWidgets('says what happened to each record, and what can be done', (
    tester,
  ) async {
    addTearDown(() => resetView(tester));
    setView(tester, const Size(360, 2400));
    final app = await AppUnderTest.open(
      tester,
      role: Role.owner,
      route: '/more/attention',
    );

    expect(
      find.textContaining('M-Pesa code is already recorded'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Payment of KES 999,999.99 from Bartholomew Kipchumba '
        'Arap Kiprotich Wanyonyi',
      ),
      findsOneWidget,
    );
    expect(
      find.text('A customer with this phone number already exists.'),
      findsOneWidget,
    );
    expect(find.text('Not deleted: the balance is not zero.'), findsOneWidget);
    expect(find.textContaining('Only an owner can do this'), findsOneWidget);
    expect(find.textContaining('Waiting for its customer'), findsOneWidget);
    expect(find.text('A record no longer on this phone'), findsOneWidget);
    // Notes have OK; records kept aside have Discard mine; the duplicate
    // customer can also be merged into the one the server has.
    expect(find.text('OK'), findsNWidgets(2));
    expect(find.text('Discard mine'), findsNWidgets(4));
    expect(find.text('Use the existing customer'), findsOneWidget);

    await tester.tap(find.text('OK').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('OK'), findsOneWidget);

    // Discarding asks first.
    await tester.tap(find.text('Discard mine').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Discard mine'), findsNWidgets(4));

    expect(app.errors, isEmpty);
    await app.close();
  });

  group('the actions', () {
    late AppDatabase db;
    late SyncIssueRepository repo;
    setUp(() async {
      db = await seededDatabase();
      repo = SyncIssueRepository(db);
    });
    tearDown(() => db.close());

    Future<SyncIssueView> issue(String reason, String table) async =>
        (await repo.watchAll().first).firstWhere(
          (v) => v.reason == reason && v.table == table,
        );

    test('discarding a record the server never had removes it', () async {
      final view = await issue('duplicate', 'transactions');
      await repo.discard(view.issue);
      expect(
        await (db.select(
          db.ledgerEntries,
        )..where((e) => e.id.equals(view.issue.recordId))).get(),
        isEmpty,
      );
      expect(
        (await repo.watchAll().first).map((v) => v.issue.id),
        isNot(contains(view.issue.id)),
      );
    });

    test('discarding a change to a record the server has puts its copy '
        'back', () async {
      const id = '0197a000-0000-7000-8000-00000000000b';
      await (db.update(db.customers)..where((c) => c.id.equals(id))).write(
        const CustomersCompanion(
          name: Value('Typo'),
          syncState: Value(SyncState.refused),
          changedFields: Value('name'),
        ),
      );
      await db
          .into(db.syncIssues)
          .insert(
            SyncIssuesCompanion.insert(
              recordTable: 'customers',
              recordId: id,
              reason: 'invalid',
              serverCopy: Value(
                jsonEncode({
                  'id': id,
                  'name': 'Akinyi',
                  'created_by': 'u1',
                  'created_at': '2026-10-14T07:15:00.000Z',
                  'updated_at': '2026-10-14T07:15:00.000Z',
                }),
              ),
              createdAt: DateTime.utc(2026, 10, 24),
            ),
          );
      await repo.discard((await issue('invalid', 'customers')).issue);

      final c = await (db.select(
        db.customers,
      )..where((c) => c.id.equals(id))).getSingle();
      expect(c.name, 'Akinyi');
      expect(c.syncState, SyncState.synced);
      expect(c.changedFields, '');
    });

    test('using the existing customer moves the entries and drops the '
        'copy', () async {
      const copy = '0197a000-0000-7000-8000-00000000000d';
      const existing = '0197a000-0000-7000-8000-00000000000c';
      await db
          .into(db.ledgerEntries)
          .insert(
            LedgerEntriesCompanion.insert(
              id: 'moved',
              customerId: copy,
              userId: 'u1',
              type: 'debt',
              amountCents: 700,
              description: const Value('Soap'),
              transactionDate: DateTime.utc(2026, 10, 24),
              createdAt: DateTime.utc(2026, 10, 24),
              updatedAt: DateTime.utc(2026, 10, 24),
              syncState: SyncState.refused,
            ),
          );
      final view = await issue('duplicate', 'customers');
      expect(view.existingCustomerId, existing);
      await repo.useExisting(view.issue, existing);

      final moved = await (db.select(
        db.ledgerEntries,
      )..where((e) => e.id.equals('moved'))).getSingle();
      expect(moved.customerId, existing);
      expect(moved.syncState, SyncState.pending);
      expect(moved.localVersion, 1);
      expect(
        await (db.select(db.customers)..where((c) => c.id.equals(copy))).get(),
        isEmpty,
      );
    });
  });
}
