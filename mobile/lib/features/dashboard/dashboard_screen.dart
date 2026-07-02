import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:flutter_animate/flutter_animate.dart';

import '../auth/auth_provider.dart';
import '../customer/customer_provider.dart';
import '../customer/screens/add_customer_screen.dart';
import '../customer/screens/customer_detail_screen.dart';
import '../reports/screens/reports_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../settings/settings_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // We watch the CustomerProvider. If data changes in SQLite, this screen rebuilds instantly!
    final customerProv = context.watch<CustomerProvider>();
    
    // We watch the SettingsProvider to get the dynamic Business Name
    final settingsProv = context.watch<SettingsProvider>();
    final businessName = settingsProv.business?.name ?? 'Salio Dashboard';
    
    // Enterprise Standard: Centralized currency formatter for Kenya Shillings
    final currencyFormat = NumberFormat('#,##0', 'en_KE');

    return Scaffold(
      appBar: AppBar(
        title: Text(businessName, style: const TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Sync Indicator & Manual Trigger
          Consumer<AuthProvider>(
            builder: (context, authProv, child) {
              if (authProv.isSyncing) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    ),
                  ),
                );
              }
              return IconButton(
                icon: const Icon(Icons.sync),
                tooltip: 'Sync Data',
                onPressed: () async {
                  final status = await context.read<AuthProvider>().triggerSync();
                  if (!context.mounted) return;
                  
                  if (status == 'success') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Sync completed successfully!'), backgroundColor: Colors.teal.shade700),
                    );
                  } else if (status == 'offline') {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(Icons.wifi_off, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Text('Offline Mode'),
                          ],
                        ),
                        content: const Text('You are currently offline. Salio will automatically sync your changes to the server as soon as you reconnect.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Okay'),
                          ),
                        ],
                      ),
                    );
                  } else if (status == 'error') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: const Text('Sync failed. Please try again later.'), backgroundColor: Colors.red.shade700),
                    );
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Summary Card (Now dynamic!)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.teal.shade700,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Column(
                  children: [
                    const Text(
                      'Total Unpaid Debts',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'KES ${currencyFormat.format(customerProv.totalOutstanding)}', 
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ).animate().fade(duration: 500.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),

            // 2. Quick Actions Title
            const Text('Quick Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                .animate().fade(duration: 600.ms),
            const SizedBox(height: 12),
            
            // 3. Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AddCustomerScreen()),
                      );
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('New Customer'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ReportsScreen()),
                      );
                    },
                    icon: const Icon(Icons.analytics),
                    label: const Text('Reports'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal.shade900,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ).animate().fade(duration: 700.ms).slideY(begin: 0.1, end: 0),
            const SizedBox(height: 24),

            // 4. Customers List Title & Search
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Customers', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${customerProv.customers.length}',
                    style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ],
            ).animate().fade(duration: 800.ms),
            const SizedBox(height: 12),
            
            TextField(
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey.shade200,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                context.read<CustomerProvider>().searchCustomers(value);
              },
            ),
            const SizedBox(height: 16),
            
            // 5. Dynamic Scrollable List of REAL Customers from SQLite
            Expanded(
              child: customerProv.isLoading
                  ? const Center(child: CircularProgressIndicator(color: Colors.teal))
                  : customerProv.customers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                customerProv.searchQuery.isEmpty 
                                  ? "No customers yet. Tap 'New Customer' to begin!"
                                  : "No customers found for '${customerProv.searchQuery}'",
                                style: const TextStyle(color: Colors.grey),
                              ),
                              if (customerProv.searchQuery.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddCustomerScreen(initialName: customerProv.searchQuery),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.person_add),
                                  label: Text('Add "${customerProv.searchQuery}" as New Customer'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal.shade50,
                                    foregroundColor: Colors.teal.shade900,
                                    elevation: 0,
                                  ),
                                ),
                              ]
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: customerProv.customers.length,
                          itemBuilder: (context, index) {
                            final c = customerProv.customers[index];
                            final balanceStr = 'KES ${currencyFormat.format(c.balance)}';
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              elevation: 1,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.teal.shade100,
                                  child: Text(
                                    c.customer.name.isNotEmpty ? c.customer.name[0].toUpperCase() : '?',
                                    style: TextStyle(color: Colors.teal.shade900, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(c.customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                trailing: Text(
                                  c.balance > 0 ? 'Owes $balanceStr' : 'Cleared ✓',
                                  style: TextStyle(
                                    color: c.balance > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => CustomerDetailScreen(customer: c.customer),
                                    ),
                                  );
                                },
                              ),
                            ).animate().fade(duration: 400.ms, delay: (index * 50).ms).slideX(begin: 0.1, end: 0);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
