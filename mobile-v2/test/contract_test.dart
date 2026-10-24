// The app against its snapshot of server-v2's API (test/contract/openapi.json,
// refreshed by scripts/contract.sh). The live tests prove the app works with
// a real server; this proves, without one, that what the app sends and reads
// is in the contract. It matters most for what the app sends: server-v2's
// REST routes reject fields they do not know, and a sync push ignores them
// (B14), so an extra key there would be silently lost rather than refused.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:salio/core/database/app_database.dart';
import 'package:salio/core/sync/sync_kinds.dart';
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
      ('get', '/api/v1/reports/summary'),
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

  test('a pushed sale, stock note, supplier and supplier entry have only '
      'fields the server knows', () {
    final sale = Wire.sale(
      SaleRow(
        id: 's',
        customerId: 'c',
        userId: 'u',
        productName: 'DAP',
        quantity: 1500,
        amountCents: 350000,
        paymentMethod: 'credit',
        reference: 'r',
        dueDate: _t,
        notes: 'n',
        saleDate: _t,
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
      ),
    );
    expect(_properties('SyncSale'), containsAll(sale.keys));
    final note = Wire.stockRequest(
      StockRequestRow(
        id: 'r',
        userId: 'u',
        productName: 'Duodip',
        neededOn: _t,
        notes: 'n',
        purchaseOrderId: 'po',
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
      ),
    );
    expect(_properties('SyncStockRequest'), containsAll(note.keys));
    final supplier = Wire.supplier(
      SupplierRow(
        id: 's',
        name: 'Elgon',
        phone: '07',
        notes: 'n',
        createdBy: 'u',
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
      ),
    );
    expect(_properties('SyncSupplier'), containsAll(supplier.keys));
    final bill = Wire.supplierEntry(
      SupplierEntryRow(
        id: 'b',
        supplierId: 's',
        userId: 'u',
        type: 'bill',
        amountCents: 100,
        description: 'd',
        transactionDate: _t,
        dueDate: _t,
        paymentMethod: 'bank',
        reference: 'r',
        purchaseOrderId: 'po',
        createdAt: _t,
        updatedAt: _t,
        isDeleted: false,
        syncState: SyncState.pending,
        localVersion: 1,
      ),
    );
    expect(_properties('SyncSupplierTransaction'), containsAll(bill.keys));
  });

  test('a push batch has only fields the server knows', () {
    expect(
      _properties('PushInputBody'),
      containsAll(['operation_id', for (final kind in syncKinds) kind.wire]),
    );
  });

  // B14: a newer app's extra field costs nothing on an older server. Were
  // this lost, one new field would fail every push from every newer phone.
  test('the server ignores push fields it does not know', () {
    for (final schema in [
      'PushInputBody',
      'SyncCustomer',
      'SyncTransaction',
      'SyncSale',
      'SyncStockRequest',
      'SyncSupplier',
      'SyncSupplierTransaction',
    ]) {
      expect(_schema(schema)['additionalProperties'], isTrue, reason: schema);
    }
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
    final kinds = [for (final kind in syncKinds) kind.wire];
    expect(_properties('PullView'), containsAll(kinds));
    expect(
      _properties('PushView'),
      containsAll(['conflicts', 'current', 'replayed', 'server_time']),
    );
    expect(_properties('ServerCopies'), containsAll(kinds));
    expect(
      _properties('SummaryView'),
      containsAll(['total_outstanding_debt', 'total_advances_held']),
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
