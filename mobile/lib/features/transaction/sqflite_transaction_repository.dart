import 'package:sqflite/sqflite.dart';
import '../../core/database/database_service.dart';
import '../../core/models/transaction_record.dart';
import '../../core/utils/exceptions.dart';
import '../../core/utils/logger.dart';
import 'transaction_repository.dart';


/// Concrete SQLite implementation of the TransactionRepository.
class SqfliteTransactionRepository implements TransactionRepository {
  final DatabaseService _dbService;

  SqfliteTransactionRepository({DatabaseService? dbService}) 
      : _dbService = dbService ?? DatabaseService();

  @override
  Future<List<TransactionRecord>> getByCustomerId(String businessId, String customerId) async {
    try {
      final db = await _dbService.database;
      final maps = await db.query(
        'transactions',
        where: 'customer_id = ? AND business_id = ? AND is_deleted = 0', // Strict tenant isolation
        whereArgs: [customerId, businessId],
        orderBy: 'transaction_date DESC, created_at DESC', // Newest transactions first
      );
      return maps.map((e) => TransactionRecord.fromMap(e)).toList();
    } catch (e, stackTrace) {
      Logger.e('Failed to fetch transactions for customer: $customerId', e, stackTrace);
      throw SalioDatabaseException('Could not load transaction history.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> add(TransactionRecord transaction) async {
    try {
      final db = await _dbService.database;
      // We use ConflictAlgorithm.fail because UUIDs should never collide. If they do, it's a severe bug.
      await db.insert('transactions', transaction.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
      Logger.i('Added new transaction: ${transaction.id}');
    } catch (e, stackTrace) {
      Logger.e('Failed to insert transaction.', e, stackTrace);
      throw SalioDatabaseException('Could not save transaction.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> softDelete(String businessId, String id) async {
    try {
      final db = await _dbService.database;
      await db.update(
        'transactions',
        {
          'is_deleted': 1, 
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [id, businessId],
      );
      Logger.i('Soft-deleted transaction: $id');
    } catch (e, stackTrace) {
      Logger.e('Failed to delete transaction.', e, stackTrace);
      throw SalioDatabaseException('Could not delete transaction.', originalError: e, stackTrace: stackTrace);
    }
  }
}
