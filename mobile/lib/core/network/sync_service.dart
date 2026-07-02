import 'dart:convert';
import 'dart:io';
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
class SyncService {
  final ApiClient _apiClient;
  final DatabaseService _dbService;
  final SecureStorageService _secureStorage;

  SyncService({
    ApiClient? apiClient, 
    DatabaseService? dbService,
    SecureStorageService? secureStorage,
  })  : _apiClient = apiClient ?? ApiClient(),
        _dbService = dbService ?? DatabaseService(),
        _secureStorage = secureStorage ?? SecureStorageService();

  /// Performs a full synchronization cycle: Push local changes, then Pull remote changes.
  /// Uses a Last-Write-Wins (LWW) conflict resolution strategy.
  Future<void> sync() async {
    try {
      Logger.i('Starting sync cycle...');
      final lastSync = await _secureStorage.getLastSyncTime();
      
      // 1. PUSH local changes to the server
      await _pushChanges(lastSync);

      // 2. PULL remote changes from the server
      final String? serverTimeStr = await _pullChanges(lastSync);

      // 3. Update the last sync time to the SERVER's authoritative time.
      // NEVER use DateTime.now() here, because mobile device clocks drift!
      if (serverTimeStr != null) {
        await _secureStorage.saveLastSyncTime(DateTime.parse(serverTimeStr));
      } else {
        // Fallback (only happens if server response is malformed)
        await _secureStorage.saveLastSyncTime(DateTime.now().toUtc());
      }
      
      Logger.i('Sync cycle completed successfully.');
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException')) {
        Logger.w('Device is offline. Sync aborted gracefully.');
      } else {
        Logger.e('Sync cycle failed.', e, stackTrace);
      }
      rethrow; // Let the caller know!
    }
  }

  /// Extracts all records modified since `lastSync` and sends them to the Go backend.
  Future<void> _pushChanges(DateTime? lastSync) async {
    final db = await _dbService.database;

    // If we've never synced before, we push EVERYTHING. 
    // Otherwise, push only things updated after lastSync.
    final String? whereClause = lastSync == null ? null : 'updated_at > ?';
    final List<Object>? whereArgs = lastSync == null ? null : [lastSync.toIso8601String()];

    // Gather modified customers
    final custMaps = await db.query('customers', where: whereClause, whereArgs: whereArgs);
    final customers = custMaps.map((c) => Customer.fromMap(c)).toList();

    // Gather modified transactions
    final txMaps = await db.query('transactions', where: whereClause, whereArgs: whereArgs);
    final transactions = txMaps.map((t) => TransactionRecord.fromMap(t)).toList();

    if (customers.isEmpty && transactions.isEmpty) {
      Logger.i('No local changes to push.');
      return;
    }

    final payload = {
      'customers': customers.map((c) => c.toJsonMap()).toList(),
      'transactions': transactions.map((t) => t.toJsonMap()).toList(),
    };

    // The Go backend Upserts these using Postgres ON CONFLICT (id) DO UPDATE
    final response = await _apiClient.post('/sync/push', payload);

    if (response.statusCode != 200) {
      throw Exception('Failed to push changes: ${response.statusCode} - ${response.body}');
    }
    
    Logger.i('Successfully pushed ${customers.length} customers and ${transactions.length} transactions.');
  }

  /// Requests all records modified by other users since `lastSync` and saves them locally.
  /// Returns the server's current timestamp to be used as the next `lastSync`.
  Future<String?> _pullChanges(DateTime? lastSync) async {
    final queryParams = <String, String>{};
    if (lastSync != null) {
      // The Go backend expects an RFC3339 formatted timestamp
      queryParams['last_sync'] = lastSync.toIso8601String();
    }

    final response = await _apiClient.get('/sync/pull', queryParams: queryParams);

    if (response.statusCode != 200) {
      throw Exception('Failed to pull changes: ${response.statusCode} - ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    final payload = decoded['data'] ?? {};
    
    final List<dynamic> customersList = payload['customers'] ?? [];
    final List<dynamic> transactionsList = payload['transactions'] ?? [];

    if (customersList.isEmpty && transactionsList.isEmpty) {
      Logger.i('No remote changes to pull.');
      return payload['server_time'] as String?;
    }

    final db = await _dbService.database;
    final batch = db.batch();

    // Upsert Customers into local SQLite
    // ConflictAlgorithm.replace essentially overwrites the local row with the remote row.
    for (final c in customersList) {
      final customer = Customer.fromMap(c as Map<String, dynamic>);
      batch.insert(
        'customers',
        customer.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Upsert Transactions into local SQLite
    for (final t in transactionsList) {
      final transaction = TransactionRecord.fromMap(t as Map<String, dynamic>);
      batch.insert(
        'transactions',
        transaction.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    // Commit all changes atomically so the UI doesn't flicker with half-updated state
    await batch.commit(noResult: true);
    
    Logger.i('Successfully pulled and applied ${customersList.length} customers and ${transactionsList.length} transactions.');
    
    return payload['server_time'] as String?;
  }
}
