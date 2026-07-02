// lib/features/transaction/transaction_repository.dart
import '../../core/models/transaction_record.dart';

/// Abstract interface for Transaction data operations.
abstract class TransactionRepository {
  Future<List<TransactionRecord>> getByCustomerId(String businessId, String customerId);
  Future<void> add(TransactionRecord transaction);
  Future<void> softDelete(String businessId, String id);
}
