import 'package:flutter/material.dart';

void main() {
  runApp(const SalioApp());
}

class SalioApp extends StatelessWidget {
  const SalioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salio',
      // This removes the "DEBUG" banner in the top right corner
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Salio Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Summary Card
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: Colors.teal.shade700,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
                child: Column(
                  children: [
                    Text(
                      'Total Unpaid Debts',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'KES 45,500', // We will make this dynamic later!
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Quick Actions Title
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 3. Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      print("Add Customer Pressed!");
                    },
                    icon: const Icon(Icons.person_add),
                    label: const Text('New Customer '),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      print("Record Payment Pressed!");
                    },
                    icon: const Icon(Icons.payment),
                    label: const Text('Record Payment'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.teal.shade50,
                      foregroundColor: Colors.teal.shade900,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 4. Recent Customers List Title
            const Text(
              'Recent Customers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 5. Scrollable List of Customers
            Expanded(
              child: ListView(
                children: [
                  _buildCustomerTile(
                    'John Doe',
                    'Owes KES 1,200',
                    Colors.red.shade700,
                  ),
                  _buildCustomerTile(
                    'Jane Smith',
                    'Owes KES 500',
                    Colors.red.shade700,
                  ),
                  _buildCustomerTile(
                    'Alice K',
                    'Cleared',
                    Colors.green.shade700,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // A helper function to build list items cleanly
  Widget _buildCustomerTile(String name, String status, Color statusColor) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: 1,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.shade100,
          child: Text(
            name[0],
            style: TextStyle(
              color: Colors.teal.shade900,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: Text(
          status,
          style: TextStyle(
            color: statusColor,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        onTap: () {
          print("$name clicked!");
        },
      ),
    );
  }
}
