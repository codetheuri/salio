import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../auth/auth_provider.dart';
import '../settings_provider.dart';
import 'edit_business_screen.dart';
import 'manage_staff_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final business = settingsProv.business;
    final user = settingsProv.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: settingsProv.isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // Business Profile Section
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: Column(
                            children: [
                              CircleAvatar(
                                radius: 40,
                                backgroundColor: Colors.teal.shade100,
                                child: Icon(Icons.store, size: 40, color: Colors.teal.shade700),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                business?.name ?? 'Loading...',
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Business ID: ${business?.id ?? ''}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (business != null && user?.role == 'owner')
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            icon: const Icon(Icons.edit, color: Colors.grey),
                            tooltip: 'Edit Business Name',
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EditBusinessScreen(business: business),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // User Profile Section
                const Text('My Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(user?.name ?? 'Loading...'),
                  subtitle: Text('Role: ${user?.role.toUpperCase() ?? ''}'),
                ),
                ListTile(
                  leading: const Icon(Icons.phone),
                  title: Text(user?.phone ?? 'No phone'),
                ),
                const Divider(),
                const SizedBox(height: 16),

                // Actions
                if (user?.role == 'owner')
                  ListTile(
                    leading: const Icon(Icons.people),
                    title: const Text('Manage Staff'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const ManageStaffScreen()),
                      );
                    },
                  ),
                ListTile(
                  leading: Icon(Icons.logout, color: Colors.red.shade700),
                  title: Text('Log Out', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
                  onTap: () {
                    context.read<AuthProvider>().logout();
                    Navigator.pop(context); // close settings screen after logout
                  },
                ),
                
                const SizedBox(height: 48),
                const Center(
                  child: Text(
                    'Salio App\nDeveloped by Joseph Theuri',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
