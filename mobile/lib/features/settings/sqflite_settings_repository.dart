import 'package:sqflite/sqflite.dart';
import '../../core/database/database_service.dart';
import '../../core/models/business.dart';
import '../../core/models/user.dart';

class SqfliteSettingsRepository {
  final DatabaseService _dbService;

  SqfliteSettingsRepository({DatabaseService? dbService}) 
      : _dbService = dbService ?? DatabaseService();

  Future<Business?> getBusiness(String businessId) async {
    final db = await _dbService.database;
    final maps = await db.query('business', where: 'id = ?', whereArgs: [businessId]);
    if (maps.isNotEmpty) {
      return Business.fromMap(maps.first);
    }
    return null;
  }

  Future<User?> getUser(String userId) async {
    final db = await _dbService.database;
    final maps = await db.query('users', where: 'id = ?', whereArgs: [userId]);
    if (maps.isNotEmpty) {
      return User.fromMap(maps.first);
    }
    return null;
  }

  Future<List<User>> getAllUsers() async {
    final db = await _dbService.database;
    final maps = await db.query('users');
    return maps.map((e) => User.fromMap(e)).toList();
  }

  Future<void> updateBusiness(Business business) async {
    final db = await _dbService.database;
    await db.insert(
      'business',
      business.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveUser(User user) async {
    final db = await _dbService.database;
    await db.insert(
      'users',
      user.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
