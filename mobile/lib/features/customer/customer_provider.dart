import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/customer.dart';
import '../../core/utils/exceptions.dart';
import '../../core/utils/logger.dart';
import 'customer_repository.dart';

/// The brain for managing customer data in the UI.
class CustomerProvider extends ChangeNotifier {
  final CustomerRepository _repository;
  
  // We need to know who is logged in to properly scope the database queries
  String? _businessId;
  String? _userId;
  DateTime? _lastSyncTime;

  List<CustomerWithBalance> _customers = [];
  bool _isLoading = false;
  String? _errorMessage;
  String _searchQuery = '';

  CustomerProvider(this._repository);

  String get searchQuery => _searchQuery;

  /// Returns customers, filtered by search query if one exists
  List<CustomerWithBalance> get customers {
    if (_searchQuery.isEmpty) return _customers;
    final lowerQuery = _searchQuery.toLowerCase();
    return _customers.where((c) => c.customer.name.toLowerCase().contains(lowerQuery)).toList();
  }
  
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Automatically calculates the total sum of all unpaid debts.
  double get totalOutstanding {
    return _customers.fold(0.0, (sum, c) => sum + c.balance);
  }

  /// This is a critical enterprise pattern.
  /// When the user logs in or logs out, the AuthProvider tells this CustomerProvider
  /// that the businessId has changed. This prevents data leaks between accounts on the same phone.
  /// We also listen to `syncTime` to automatically refresh the SQLite data when a background sync finishes!
  void updateAuthData(String? businessId, String? userId, DateTime? syncTime) {
    bool shouldReload = false;

    if (_businessId != businessId) {
      _businessId = businessId;
      _userId = userId;
      shouldReload = true;
    }

    // If a background sync just finished, we MUST reload the SQLite data into the UI
    if (_lastSyncTime != syncTime) {
      _lastSyncTime = syncTime;
      shouldReload = true;
    }

    if (shouldReload) {
      if (_businessId != null) {
        // New user logged in OR new data synced, fetch it!
        loadCustomers();
      } else {
        // User logged out, clear memory immediately
        _customers = [];
        notifyListeners();
      }
    }
  }

  /// Updates the search query and notifies UI to filter the list
  void searchCustomers(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Fetches customers from local SQLite
  Future<void> loadCustomers() async {
    if (_businessId == null) return;
    
    _isLoading = true;
    _errorMessage = null;
    
    // microtask prevents UI rebuild collision errors
    Future.microtask(() => notifyListeners()); 

    try {
      _customers = await _repository.getAllWithBalances(_businessId!);
    } catch (e) {
      _errorMessage = 'Failed to load customers. Please try again.';
      Logger.e('CustomerProvider load error', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new customer to the database
  Future<bool> addCustomer(String name, String? phone, String? notes) async {
    if (_businessId == null || _userId == null) return false;

    try {
      final newCustomer = Customer(
        id: const Uuid().v4(), // Generate unique ID offline
        businessId: _businessId!,
        name: name.trim(),
        phone: phone?.trim(),
        notes: notes?.trim(),
        createdBy: _userId!,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );

      await _repository.add(newCustomer);
      
      // Refresh the UI list
      await loadCustomers();
      return true;
    } catch (e) {
      if (e is SalioDatabaseException) {
        _errorMessage = e.message;
      } else {
        _errorMessage = 'Failed to add customer.';
      }
      notifyListeners();
      return false;
    }
  }

  /// Updates an existing customer in the database
  Future<bool> updateCustomer(Customer updatedCustomer) async {
    try {
      await _repository.update(updatedCustomer);
      await loadCustomers();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to update customer.';
      notifyListeners();
      return false;
    }
  }

  /// Soft deletes a customer (only if balance is 0)
  Future<bool> deleteCustomer(String customerId) async {
    if (_businessId == null) return false;
    try {
      await _repository.softDelete(_businessId!, customerId);
      await loadCustomers();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete customer.';
      notifyListeners();
      return false;
    }
  }
}
