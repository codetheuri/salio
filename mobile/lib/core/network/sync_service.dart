import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database/database_service.dart';
import '../models/customer.dart';
import '../models/transaction_record.dart';
import '../storage/secure_storage.dart';
import '../utils/logger.dart';
import 'api_client.dart';

/// SyncService is the orchestrator for the offline-first architecture.
/// It bridges the local SQLite database and the remote PostgreSQL database
/// by running a Push (upload local changes) and Pull (download remote changes) cycle.
///
/// ## Why a cursor and not a timestamp
///
/// Pull used to ask the server for everything changed after a stored timestamp,
/// and then store the server's clock as the next watermark. That loses records.
///
/// On the server, a row's `updated_at` is set when its transaction *begins*, but
/// the row only becomes visible to others when that transaction *commits*. If
/// another device pulled in between, it saw nothing, yet still advanced its
/// watermark to "now" — a moment later than the timestamp the pending row would
/// carry. Once committed, that row sat permanently below the watermark and was
/// never returned again. Logging out appeared to fix it only because logout
/// cleared the stored watermark.
///
/// The server now issues a monotonic cursor, and this client advances it only as
/// far as the records it actually received. It cannot step over an unseen write.
class SyncService {
  final ApiClient _apiClient;
  final DatabaseService _dbService;
  final SecureStorageService _secureStorage;

  /// Guards against an unbounded loop if a server ever reported `has_more`
  /// without advancing the cursor. Each page carries up to 500 records, so this
  /// is far beyond any real backlog.
  static const int _maxPagesPerSync = 100;

  SyncService({
    ApiClient? apiClient,
    DatabaseService? dbService,
    SecureStorageService? secureStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? DatabaseService(),
        _secureStorage = secureStorage ?? SecureStorageService();

  /// Performs a full synchronization cycle: push local changes, then pull remote ones.
  Future<void> sync() async {
    try {
      Logger.i('Starting sync cycle...');

      await _pushChanges();
      await _pullChanges();

      Logger.i('Sync cycle completed successfully.');
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException')) {
        Logger.w('Device is offline. Sync aborted gracefully.');
      } else {
        Logger.e('Sync cycle failed.', e, stackTrace);
      }
      rethrow;
    }
  }

  /// Sends everything modified since the last successful push.
  Future<void> _pushChanges() async {
    final db = await _dbService.database;
    final lastPushedAt = await _secureStorage.getLastPushedAt();

    final String? whereClause = lastPushedAt == null ? null : 'updated_at > ?';
    final List<Object>? whereArgs =
        lastPushedAt == null ? null : [lastPushedAt.toIso8601String()];

    final custMaps = await db.query('customers', where: whereClause, whereArgs: whereArgs);
    final customers = custMaps.map((c) => Customer.fromMap(c)).toList();

    final txMaps = await db.query('transactions', where: whereClause, whereArgs: whereArgs);
    final transactions = txMaps.map((t) => TransactionRecord.fromMap(t)).toList();

    if (customers.isEmpty && transactions.isEmpty) {
      Logger.i('No local changes to push.');
      return;
    }

    // The watermark comes from the records being sent, never from the clock.
    // Using `now` would mark as pushed any row written while this request was in
    // flight — the same mistake, in miniature, that the pull cursor fixes.
    DateTime highWater = lastPushedAt ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();
    for (final c in customers) {
      if (c.updatedAt.isAfter(highWater)) highWater = c.updatedAt;
    }
    for (final t in transactions) {
      if (t.updatedAt.isAfter(highWater)) highWater = t.updatedAt;
    }

    final payload = {
      'customers': customers.map((c) => c.toJsonMap()).toList(),
      'transactions': transactions.map((t) => t.toJsonMap()).toList(),
    };

    final response = await _apiClient.post('/sync/push', payload);
    if (response.statusCode != 200) {
      throw Exception('Failed to push changes: ${response.statusCode} - ${response.body}');
    }

    await _secureStorage.saveLastPushedAt(highWater);
    Logger.i('Pushed ${customers.length} customers and ${transactions.length} transactions.');
  }

  /// Downloads remote changes, following pagination until the server reports
  /// nothing further.
  Future<void> _pullChanges() async {
    var cursor = await _secureStorage.getSyncCursor();
    var pages = 0;
    var totalCustomers = 0;
    var totalTransactions = 0;

    while (true) {
      if (++pages > _maxPagesPerSync) {
        Logger.w('Stopping pull after $_maxPagesPerSync pages; will resume next sync.');
        break;
      }

      final response = await _apiClient.get(
        '/sync/pull',
        queryParams: {'cursor': cursor.toString()},
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to pull changes: ${response.statusCode} - ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      final payload = decoded['data'] ?? {};

      final List<dynamic> customersList = payload['customers'] ?? [];
      final List<dynamic> transactionsList = payload['transactions'] ?? [];
      final int nextCursor = (payload['next_cursor'] as num?)?.toInt() ?? cursor;
      final bool hasMore = payload['has_more'] == true;

      if (customersList.isNotEmpty || transactionsList.isNotEmpty) {
        await _applyRemoteChanges(customersList, transactionsList);
        totalCustomers += customersList.length;
        totalTransactions += transactionsList.length;
      }

      final advanced = nextCursor > cursor;

      // Persist after each page. A connection dropped mid-backlog then resumes
      // where it left off rather than restarting from the beginning.
      if (advanced) {
        cursor = nextCursor;
        await _secureStorage.saveSyncCursor(cursor);
      }

      if (!hasMore) break;

      // Defensive: a server reporting more work without moving the cursor would
      // otherwise spin until the page cap.
      if (!advanced) {
        Logger.w('Server reported more changes but the cursor did not advance; stopping.');
        break;
      }
    }

    if (totalCustomers == 0 && totalTransactions == 0) {
      Logger.i('No remote changes to pull.');
    } else {
      Logger.i('Pulled $totalCustomers customers and $totalTransactions transactions.');
    }
  }

  /// Writes one page of remote changes into local SQLite atomically, so the UI
  /// never observes a half-applied batch.
  Future<void> _applyRemoteChanges(
    List<dynamic> customersList,
    List<dynamic> transactionsList,
  ) async {
    final db = await _dbService.database;
    final batch = db.batch();

    for (final c in customersList) {
      final customer = Customer.fromMap(c as Map<String, dynamic>);
      batch.insert('customers', customer.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final t in transactionsList) {
      final transaction = TransactionRecord.fromMap(t as Map<String, dynamic>);
      batch.insert('transactions', transaction.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await batch.commit(noResult: true);
  }
}
