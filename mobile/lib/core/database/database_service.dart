import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'sql_queries.dart';

class DatabaseService {
  // 1. Singleton pattern setup
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  // 2. Database getter
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 3. Initialization
  Future<Database> _initDatabase() async {
    // Finds the correct folder on the phone to safely store the DB file
    final documentsDirectory = await getApplicationDocumentsDirectory();
    // Switched to salio_v3.db to start fresh without old mock data and with updated schema
    final path = join(documentsDirectory.path, 'salio_v3.db');

    return await openDatabase(
      path,
      version: 1, 
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: _onConfigure,
    );
  }

  // Handle schema migrations for existing local databases
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add updated_at to transactions. Default it to created_at so existing records don't crash.
      await db.execute('ALTER TABLE transactions ADD COLUMN updated_at TEXT NOT NULL DEFAULT ""');
      await db.execute('UPDATE transactions SET updated_at = created_at WHERE updated_at = ""');
    }
  }

  // 4. Enable foreign keys (SQLite disables them by default for backwards compatibility)
  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // 5. Create tables on first launch
  Future<void> _onCreate(Database db, int version) async {
    // Create Tables
    await db.execute(createBusinessTable);
    await db.execute(createUsersTable);
    await db.execute(createCustomersTable);
    await db.execute(createTransactionsTable);

    // Create Indexes to speed up queries
    await db.execute(createIdxCustomerBusiness);
    await db.execute(createIdxCustomerName);
    await db.execute(createIdxTransactionCustomer);
  }
}
