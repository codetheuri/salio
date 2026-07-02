import 'package:sqflite/sqflite.dart';
import '../../core/database/database_service.dart';
import '../../core/models/customer.dart';
import '../../core/utils/exceptions.dart';
import '../../core/utils/logger.dart';
import 'customer_repository.dart';

/// Concrete SQLite implementation of the CustomerRepository.
class SqfliteCustomerRepository implements CustomerRepository {
  final DatabaseService _dbService;

  // Uses Dependency Injection so we can pass a mocked DatabaseService during tests
  SqfliteCustomerRepository({DatabaseService? dbService}) 
      : _dbService = dbService ?? DatabaseService();

  @override
  Future<List<Customer>> getAll(String businessId) async {
    try {
      final db = await _dbService.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'customers',
        where: 'business_id = ? AND is_deleted = 0', // Strict tenant isolation
        whereArgs: [businessId],
        orderBy: 'name ASC',
      );
      return maps.map((e) => Customer.fromMap(e)).toList();
    } catch (e, stackTrace) {
      Logger.e('Failed to fetch customers for business: $businessId', e, stackTrace);
      throw SalioDatabaseException('Could not load customers.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<List<CustomerWithBalance>> getAllWithBalances(String businessId) async {
    try {
      final db = await _dbService.database;
      
      // Standard ORMs struggle with complex aggregated JOINs. 
      // Using a raw query here is the most performant and reliable enterprise approach.
      const query = '''
        SELECT
            c.*,
            COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE 0 END), 0) -
            COALESCE(SUM(CASE WHEN t.type = 'payment' THEN t.amount ELSE 0 END), 0) AS balance
        FROM customers c
        LEFT JOIN transactions t ON c.id = t.customer_id AND t.is_deleted = 0
        WHERE c.business_id = ? AND c.is_deleted = 0
        GROUP BY c.id
        ORDER BY balance DESC, c.name ASC;
      ''';
      
      final List<Map<String, dynamic>> maps = await db.rawQuery(query, [businessId]);
      
      return maps.map((map) {
        final customer = Customer.fromMap(map);
        // SQLite stores floats as REAL, which Dart maps to num.
        // We safely cast it to double to prevent type crashes.
        final balance = (map['balance'] as num).toDouble();
        return CustomerWithBalance(customer: customer, balance: balance);
      }).toList();
    } catch (e, stackTrace) {
      Logger.e('Failed to fetch customers with balances.', e, stackTrace);
      throw SalioDatabaseException('Could not load dashboard data.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<Customer?> getById(String businessId, String id) async {
    try {
      final db = await _dbService.database;
      final maps = await db.query(
        'customers',
        where: 'id = ? AND business_id = ? AND is_deleted = 0',
        whereArgs: [id, businessId],
      );
      if (maps.isEmpty) return null;
      return Customer.fromMap(maps.first);
    } catch (e, stackTrace) {
      Logger.e('Failed to fetch customer by ID: $id', e, stackTrace);
      throw SalioDatabaseException('Could not load customer details.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> add(Customer customer) async {
    try {
      final db = await _dbService.database;
      
      // Strict Phone Number Validation (Enterprise Pattern)
      if (customer.phone != null && customer.phone!.isNotEmpty) {
        final existing = await db.query(
          'customers',
          where: 'business_id = ? AND phone = ? AND is_deleted = 0',
          whereArgs: [customer.businessId, customer.phone],
        );
        if (existing.isNotEmpty) {
          throw SalioDatabaseException('A customer with this phone number already exists.');
        }
      }

      await db.insert('customers', customer.toMap(), conflictAlgorithm: ConflictAlgorithm.fail);
      Logger.i('Added new customer: ${customer.id}');
    } catch (e, stackTrace) {
      Logger.e('Failed to insert customer.', e, stackTrace);
      if (e is SalioDatabaseException) rethrow; // Pass validation messages through
      throw SalioDatabaseException('Could not save new customer.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> update(Customer customer) async {
    try {
      final db = await _dbService.database;
      await db.update(
        'customers',
        customer.toMap(),
        where: 'id = ? AND business_id = ?',
        whereArgs: [customer.id, customer.businessId],
      );
      Logger.i('Updated customer: ${customer.id}');
    } catch (e, stackTrace) {
      Logger.e('Failed to update customer.', e, stackTrace);
      throw SalioDatabaseException('Could not update customer.', originalError: e, stackTrace: stackTrace);
    }
  }

  @override
  Future<void> softDelete(String businessId, String id) async {
    try {
      final db = await _dbService.database;
      await db.update(
        'customers',
        {
          'is_deleted': 1, 
          'updated_at': DateTime.now().toUtc().toIso8601String()
        },
        where: 'id = ? AND business_id = ?',
        whereArgs: [id, businessId],
      );
      Logger.i('Soft-deleted customer: $id');
    } catch (e, stackTrace) {
      Logger.e('Failed to delete customer.', e, stackTrace);
      throw SalioDatabaseException('Could not delete customer.', originalError: e, stackTrace: stackTrace);
    }
  }
}
