import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/transaction_record.dart';
import '../../core/utils/logger.dart';
import 'transaction_repository.dart';

/// The brain for managing transaction data in the UI.
class TransactionProvider extends ChangeNotifier {
  final TransactionRepository _repository;
  
  String? _businessId;
  String? _userId;
  DateTime? _lastSyncTime;
  String? _currentCustomerId;

  List<TransactionRecord> _customerTransactions = [];
  bool _isLoading = false;
  String? _errorMessage;

  TransactionProvider(this._repository);

  List<TransactionRecord> get customerTransactions => _customerTransactions;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Triggered by AuthProvider when a user logs in/out, or when a background sync finishes.
  void updateAuthData(String? businessId, String? userId, DateTime? syncTime) {
    bool shouldReload = false;

    if (_businessId != businessId) {
      _businessId = businessId;
      _userId = userId;
      
      if (_businessId == null) {
        // User logged out, clear memory
        _customerTransactions = [];
        _currentCustomerId = null;
        notifyListeners();
      }
    }

    // If a background sync just finished, and we are currently viewing a customer's transactions,
    // we MUST reload the SQLite data into the UI so new transactions appear instantly.
    if (_lastSyncTime != syncTime) {
      _lastSyncTime = syncTime;
      shouldReload = true;
    }

    if (shouldReload && _businessId != null && _currentCustomerId != null) {
      loadTransactionsForCustomer(_currentCustomerId!);
    }
  }

  /// Fetches the transaction history for a specific customer
  Future<void> loadTransactionsForCustomer(String customerId) async {
    if (_businessId == null) return;
    
    _currentCustomerId = customerId;
    _isLoading = true;
    _errorMessage = null;
    
    Future.microtask(() => notifyListeners());

    try {
      _customerTransactions = await _repository.getByCustomerId(_businessId!, customerId);
    } catch (e) {
      _errorMessage = 'Failed to load transaction history.';
      Logger.e('TransactionProvider load error', e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Adds a new debt or payment to the database
  Future<bool> addTransaction(String customerId, String type, double amount, String? description) async {
    if (_businessId == null || _userId == null) return false;

    try {
      final newTransaction = TransactionRecord(
        id: const Uuid().v4(),
        businessId: _businessId!,
        customerId: customerId,
        userId: _userId!,
        type: type, // MUST be 'debt' or 'payment'
        amount: amount,
        description: description?.trim(),
        transactionDate: DateTime.now().toUtc().toIso8601String(),
        updatedAt: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      );

      await _repository.add(newTransaction);
      
      // Instantly refresh the UI list for this customer
      await loadTransactionsForCustomer(customerId);
      return true;
    } catch (e) {
      _errorMessage = 'Failed to save transaction.';
      notifyListeners();
      return false;
    }
  }
}
