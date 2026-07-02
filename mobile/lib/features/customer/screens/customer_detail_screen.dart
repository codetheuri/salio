import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/models/customer.dart';
import '../../transaction/transaction_provider.dart';
import '../customer_provider.dart';
import '../../settings/settings_provider.dart';
import 'edit_customer_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _currencyFormat = NumberFormat('#,##0', 'en_KE');

  @override
  void initState() {
    super.initState();
    // Fetch transactions as soon as the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TransactionProvider>().loadTransactionsForCustomer(widget.customer.id);
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Opens a smooth BottomSheet to record either a debt or a payment
  void _showTransactionBottomSheet(String type) {
    _amountController.clear();
    _descriptionController.clear();
    final isDebt = type == 'debt';
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Allows sheet to push up when keyboard appears
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom, // Keyboard padding
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isDebt ? 'Record New Debt' : 'Record Payment',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount (KES)',
                    prefixIcon: const Icon(Icons.attach_money),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Amount is required';
                    final amount = double.tryParse(value);
                    if (amount == null || amount <= 0) return 'Enter a valid positive number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Description (Optional)',
                    prefixIcon: const Icon(Icons.notes),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) {
                        return; // Stops here, shows red inline error text!
                      }

                      final amount = double.parse(_amountController.text);

                      // Close bottom sheet first so any future Snackbars show on the main screen
                      Navigator.pop(context);

                      // Add transaction via provider
                      final success = await context.read<TransactionProvider>().addTransaction(
                        widget.customer.id, 
                        type, 
                        amount, 
                        _descriptionController.text,
                      );

                      if (success && context.mounted) {
                       // Force the CustomerProvider to recalculate this customer's new total balance
                       context.read<CustomerProvider>().loadCustomers();
                       
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(
                           content: Text('${isDebt ? 'Debt' : 'Payment'} recorded successfully!'),
                           backgroundColor: Colors.teal.shade700,
                         ),
                       );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDebt ? Colors.red.shade600 : Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('Save ${isDebt ? 'Debt' : 'Payment'}'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      );  
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // We watch CustomerProvider to get the live, updated balance for the header
    final customerProv = context.watch<CustomerProvider>();
    final customerData = customerProv.customers.firstWhere(
      (c) => c.customer.id == widget.customer.id,
      orElse: () => CustomerWithBalance(customer: widget.customer, balance: 0),
    );

    final transactionProv = context.watch<TransactionProvider>();
    final transactions = transactionProv.customerTransactions;
    
    final staffNames = context.watch<SettingsProvider>().staffNames;

    return Scaffold(
      appBar: AppBar(
        title: Text(customerData.customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Customer',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditCustomerScreen(
                    customer: customerData.customer,
                    currentBalance: customerData.balance,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Header Card with Buttons
          Container(
            color: Colors.teal.shade700,
            width: double.infinity,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Text('Current Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                const SizedBox(height: 8),
                Text(
                  'KES ${_currencyFormat.format(customerData.balance)}',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Added by ${staffNames[customerData.customer.createdBy] ?? 'Staff'} on ${DateFormat('dd MMM yyyy').format(customerData.customer.createdAt.toLocal())}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _showTransactionBottomSheet('debt'),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Debt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _showTransactionBottomSheet('payment'),
                      icon: const Icon(Icons.remove),
                      label: const Text('Payment'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fade(duration: 500.ms).slideY(begin: -0.1, end: 0),
          
          // Transaction History Title
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Transaction History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ).animate().fade(duration: 600.ms),

          // Transaction List
          Expanded(
            child: transactionProv.isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                : transactions.isEmpty
                    ? const Center(child: Text("No transactions yet."))
                    : ListView.builder(
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          final t = transactions[index];
                          final isDebt = t.type == 'debt';
                          final date = DateTime.parse(t.transactionDate).toLocal();
                          final dateStr = '${date.day}/${date.month}/${date.year}';
                          
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isDebt ? Colors.red.shade100 : Colors.green.shade100,
                              child: Icon(
                                isDebt ? Icons.arrow_upward : Icons.arrow_downward,
                                color: isDebt ? Colors.red.shade700 : Colors.green.shade700,
                              ),
                            ),
                            title: Text(
                              t.description?.isNotEmpty == true 
                                ? t.description! 
                                : (isDebt ? 'Goods on Credit' : 'Payment Received')
                            ),
                            subtitle: Text('$dateStr • Recorded by ${staffNames[t.userId] ?? 'Staff'}'),
                            trailing: Text(
                              '${isDebt ? "+" : "-"} ${_currencyFormat.format(t.amount)}',
                              style: TextStyle(
                                color: isDebt ? Colors.red.shade700 : Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ).animate().fade(duration: 400.ms, delay: (index * 50).ms).slideX(begin: 0.1, end: 0);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
