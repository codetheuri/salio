// lib/features/customer/customer_repository.dart
import '../../core/models/customer.dart';

/// Abstract interface for Customer data operations.
/// 
/// Enterprise Practice: Dependency Inversion.
/// The UI and State layers will depend on this interface, NOT the SQLite implementation.
/// This makes our code highly testable (we can create a MockCustomerRepository) and
/// flexible (if we ever switch from SQLite to Realm/Hive, the UI doesn't care).
abstract class CustomerRepository {
  Future<List<Customer>> getAll(String businessId);
  Future<List<CustomerWithBalance>> getAllWithBalances(String businessId);
  Future<Customer?> getById(String businessId, String id);
  Future<void> add(Customer customer);
  Future<void> update(Customer customer);
  Future<void> softDelete(String businessId, String id);
}
