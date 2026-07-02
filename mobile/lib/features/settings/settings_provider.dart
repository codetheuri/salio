import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/models/business.dart';
import '../../core/models/user.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/logger.dart';
import 'sqflite_settings_repository.dart';

class SettingsProvider extends ChangeNotifier {
  final SqfliteSettingsRepository _repository;
  
  String? _businessId;
  String? _userId;

  Business? _business;
  User? _currentUser;
  bool _isLoading = false;

  SettingsProvider(this._repository);

  Business? get business => _business;
  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  void updateAuthData(String? businessId, String? userId) {
    if (_businessId != businessId || _userId != userId) {
      _businessId = businessId;
      _userId = userId;
      
      if (_businessId != null && _userId != null) {
        loadProfile();
      } else {
        _business = null;
        _currentUser = null;
        notifyListeners();
      }
    }
  }

  final ApiClient _apiClient = ApiClient();

  Future<bool> updateBusinessName(String newName) async {
    if (_business == null) return false;

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Send update to Go Backend
      final response = await _apiClient.put('/business', {'name': newName});
      if (response.statusCode != 200) {
        throw Exception('Failed to update business on server');
      }

      // 2. Update Local SQLite Database
      final updatedBusiness = _business!.copyWith(
        name: newName,
        updatedAt: DateTime.now().toUtc(),
      );
      await _repository.updateBusiness(updatedBusiness);
      _business = updatedBusiness;
      return true;
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        Logger.w('Offline: Cannot update business name.');
      } else {
        Logger.e('Failed to update business name', e, stackTrace);
      }
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadProfile() async {
    if (_businessId == null || _userId == null) return;
    
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    try {
      // 1. Try to fetch fresh profile from Server
      final response = await _apiClient.get('/users/me');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body)['data'];
        _business = Business.fromMap(data['business']);
        _currentUser = User.fromMap(data['user']);
        
        // Save to SQLite for offline access
        await _repository.updateBusiness(_business!);
        await _repository.saveUser(_currentUser!);
      } else {
        // Fallback to SQLite if offline
        _business = await _repository.getBusiness(_businessId!);
        _currentUser = await _repository.getUser(_userId!);
      }
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        Logger.w('Offline: Using local profile data.');
      } else {
        Logger.e('Failed to load profile', e, stackTrace);
      }
      // Fallback to SQLite if offline
      _business = await _repository.getBusiness(_businessId!);
      _currentUser = await _repository.getUser(_userId!);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    
    // Also load staff mapping for UI display (transactions/customers)
    await loadStaff();
  }

  List<User> _staffList = [];
  List<User> get staffList => _staffList;

  // A map of User ID -> Name for quick UI lookups
  Map<String, String> get staffNames {
    return {for (var user in _staffList) user.id: user.name};
  }

  Future<void> loadStaff() async {
    try {
      final response = await _apiClient.get('/staff');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> list = data['data'] ?? [];
        _staffList = list.map((e) => User.fromMap(e as Map<String, dynamic>)).toList();
        
        // Save them locally so we have their names offline
        for (var staff in _staffList) {
          await _repository.saveUser(staff);
        }
        
        notifyListeners();
      } else {
        // Fallback: try to load all users from SQLite if offline
        _staffList = await _repository.getAllUsers();
        notifyListeners();
      }
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        Logger.w('Offline: Using local staff list.');
      } else {
        Logger.e('Failed to load staff list', e, stackTrace);
      }
      _staffList = await _repository.getAllUsers();
      notifyListeners();
    }
  }

  Future<String?> generateInviteCode() async {
    try {
      final response = await _apiClient.post('/auth/invite', {});
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return data['data']['invite_code'] as String?;
      }
      return null;
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        Logger.w('Offline: Cannot generate invite code.');
      } else {
        Logger.e('Failed to generate invite code', e, stackTrace);
      }
      rethrow;
    }
  }

  Future<bool> deactivateStaff(String staffId) async {
    try {
      final response = await _apiClient.delete('/staff/$staffId');
      if (response.statusCode == 200) {
        await loadStaff();
        return true;
      }
      return false;
    } catch (e, stackTrace) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        Logger.w('Offline: Cannot deactivate staff.');
      } else {
        Logger.e('Failed to deactivate staff', e, stackTrace);
      }
      rethrow;
    }
  }
}
