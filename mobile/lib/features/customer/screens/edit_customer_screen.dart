import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/models/customer.dart';
import '../customer_provider.dart';

class EditCustomerScreen extends StatefulWidget {
  final Customer customer;
  final double currentBalance;

  const EditCustomerScreen({super.key, required this.customer, required this.currentBalance});

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Prefill the controllers with the existing customer data
    _nameController = TextEditingController(text: widget.customer.name);
    _phoneController = TextEditingController(text: widget.customer.phone ?? '');
    _notesController = TextEditingController(text: widget.customer.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _updateCustomer() async {
    if (!_formKey.currentState!.validate()) return;
    
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    
    final updatedCustomer = widget.customer.copyWith(
      name: _nameController.text.trim(),
      phone: _phoneController.text.isNotEmpty ? _phoneController.text.trim() : null,
      notes: _notesController.text.isNotEmpty ? _notesController.text.trim() : null,
      updatedAt: DateTime.now().toUtc(),
    );

    final success = await context.read<CustomerProvider>().updateCustomer(updatedCustomer);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Customer updated successfully!'), backgroundColor: Colors.teal.shade700),
      );
      Navigator.of(context).pop(); // Go back to detail screen
    } else {
      final error = context.read<CustomerProvider>().errorMessage ?? 'Failed to update customer.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
    }
  }

  Future<void> _deleteCustomer() async {
    // Business Rule: Cannot delete a customer who owes money or has prepaid money
    if (widget.currentBalance != 0) {
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot delete a customer with a non-zero balance.'), 
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text('Are you sure you want to delete ${widget.customer.name}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    final success = await context.read<CustomerProvider>().deleteCustomer(widget.customer.id);
    
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
       // Pop back TWICE: Once from Edit Screen, once from Detail Screen to get back to Dashboard
       Navigator.of(context).popUntil((route) => route.isFirst);
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer deleted.'), backgroundColor: Colors.black87),
      );
    } else {
       final error = context.read<CustomerProvider>().errorMessage ?? 'Failed to delete customer.';
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Customer', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Customer Name *',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Name is required' : null,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  prefixIcon: const Icon(Icons.notes),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 32),
              
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateCustomer,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Update Customer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 24),

              // Enterprise Logic: Delete Button
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _deleteCustomer,
                icon: const Icon(Icons.delete),
                label: const Text('Delete Customer'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              
              if (widget.currentBalance != 0)
                 Padding(
                   padding: const EdgeInsets.only(top: 8.0),
                   child: Text(
                     'You can only delete customers with a zero balance.',
                     textAlign: TextAlign.center,
                     style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                   ),
                 ),
            ],
          ),
        ),
      ),
    );
  }
}
