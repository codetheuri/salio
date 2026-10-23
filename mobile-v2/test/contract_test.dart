// The app against its snapshot of server-v2's API (test/contract/openapi.json,
// refreshed by scripts/contract.sh). The live tests prove the app works with
// a real server; this proves, without one, that what the app sends and reads
// is in the contract. It matters most for what the app sends: server-v2
// rejects fields it does not know (docs/10, B14), so one extra key in a sync
// record would fail every push.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/sync/wire.dart';

final _doc =
    jsonDecode(File('test/contract/openapi.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _schema(String name) =>
    ((_doc['components'] as Map<String, dynamic>)['schemas']
            as Map<String, dynamic>)[name]
        as Map<String, dynamic>;

Set<String> _properties(String schema) =>
    (_schema(schema)['properties'] as Map<String, dynamic>).keys.toSet();

final _t = DateTime.utc(2026, 10, 19, 8);

void main() {
  test('every endpoint the app calls is in the contract', () {
    final paths = _doc['paths'] as Map<String, dynamic>;
    for (final (method, path) in [
      ('post', '/api/v1/auth/login'),
      ('get', '/api/v1/business'),
      ('get', '/api/v1/sync/pull'),
      ('post', '/api/v1/sync/push'),
      ('get', '/api/v1/app/version'),
    ]) {
      expect(
        (paths[path] as Map<String, dynamic>?)?[method],
        isNotNull,
        reason: '${method.toUpperCase()} $path',
      );
    }
  });

  test('a pushed customer has only fields the server knows', () {
    final json = Wire.customer(
      CustomerRow(
        id: 'c',
        name: 'Akinyi',
        phone: '0712',
        notes: 'n',
        createdBy: 'u',
        creditLimitCents: 500000,
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
        // Every field marked, so every optional key is sent.
        changedFields: Wire.customerFields.join(','),
      ),
    );
    expect(_properties('SyncCustomer'), containsAll(json.keys));
  });

  test('a pushed entry has only fields the server knows', () {
    final json = Wire.entry(
      LedgerEntryRow(
        id: 'e',
        customerId: 'c',
        userId: 'u',
        type: 'payment',
        amountCents: 100,
        description: 'd',
        transactionDate: _t,
        paymentMethod: 'mpesa',
        reference: 'QWE123RTY4',
        dueDate: _t,
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
      ),
    );
    expect(_properties('SyncTransaction'), containsAll(json.keys));
  });

  test('a push batch has only fields the server knows', () {
    expect(
      _properties('PushInputBody'),
      containsAll(['operation_id', 'customers', 'transactions']),
    );
  });

  test('what the app reads from the server is in the contract', () {
    expect(
      _properties('PullView'),
      containsAll([
        'customers',
        'transactions',
        'next_cursor',
        'has_more',
        'resync_required',
        'server_time',
      ]),
    );
    expect(
      _properties('PushView'),
      containsAll(['conflicts', 'replayed', 'server_time']),
    );
    expect(
      _properties('SyncConflict'),
      containsAll(['table', 'id', 'field', 'reason', 'detail']),
    );
    expect(_properties('LoginInputBody'), containsAll(['phone', 'password']));
    expect(
      _properties('ReleaseInfo'),
      containsAll([
        'version',
        'build',
        'min_build',
        'rollout_percent',
        'notes',
        'files',
      ]),
    );
    expect(_properties('ReleaseFile'), containsAll(['url', 'sha256', 'size']));
  });
}
