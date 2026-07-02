import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../settings_provider.dart';

class ManageStaffScreen extends StatefulWidget {
  const ManageStaffScreen({super.key});

  @override
  State<ManageStaffScreen> createState() => _ManageStaffScreenState();
}

class _ManageStaffScreenState extends State<ManageStaffScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadStaff();
    });
  }

  void _generateInvite() async {
    try {
      final code = await context.read<SettingsProvider>().generateInviteCode();
      if (!mounted) return;

      if (code != null) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Staff Invite Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Share this 6-digit code with your staff member. They will enter it on the Login screen to join your business.'),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        code,
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.teal.shade900),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        color: Colors.teal.shade700,
                        tooltip: 'Copy Code',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Code copied to clipboard!'), duration: Duration(seconds: 2)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Valid for 24 hours.', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Failed to generate invite code'), backgroundColor: Colors.red.shade700),
        );
      }
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.wifi_off, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('You are Offline'),
            ],
          ),
          content: const Text('Generating an invite code requires an active internet connection so it can be securely registered on the server. Please connect and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Okay'),
            ),
          ],
        ),
      );
    }
  }

  void _removeStaff(String staffId, String staffName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Staff'),
        content: Text('Are you sure you want to deactivate $staffName? They will immediately lose access to the app, but their transaction history will be preserved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              // Capture the ScaffoldMessenger from the main context before popping the dialog
              final scaffoldMessenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              
              try {
                final success = await context.read<SettingsProvider>().deactivateStaff(staffId);
                if (mounted) {
                  if (success) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('$staffName has been deactivated'), backgroundColor: Colors.teal.shade700),
                    );
                  } else {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: const Text('Failed to remove staff member'), backgroundColor: Colors.red.shade700),
                    );
                  }
                }
              } catch (e) {
                if (mounted) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          const Text('Offline'),
                        ],
                      ),
                      content: const Text('Removing a staff member requires an active internet connection. Please connect and try again.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Okay'),
                        ),
                      ],
                    ),
                  );
                }
              }
            },
            child: Text('Remove', style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProv = context.watch<SettingsProvider>();
    final staffList = settingsProv.staffList;
    final currentUser = settingsProv.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: settingsProv.isLoading && staffList.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.teal))
          : Column(
              children: [
                if (currentUser?.role == 'owner')
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _generateInvite,
                        icon: const Icon(Icons.add),
                        label: const Text('Invite Staff', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: staffList.length,
                    itemBuilder: (context, index) {
                      final user = staffList[index];
                      final isMe = user.id == currentUser?.id;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        elevation: 1,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: user.role == 'owner' ? Colors.deepPurple.shade100 : Colors.teal.shade100,
                            child: Icon(
                              user.role == 'owner' ? Icons.star : Icons.person,
                              color: user.role == 'owner' ? Colors.deepPurple.shade700 : Colors.teal.shade700,
                            ),
                          ),
                          title: Text('${user.name} ${isMe ? "(You)" : ""}'),
                          subtitle: Text('${user.phone} • ${user.role.toUpperCase()}'),
                          trailing: (currentUser?.role == 'owner' && !isMe)
                              ? IconButton(
                                  icon: Icon(Icons.person_remove, color: Colors.red.shade300),
                                  onPressed: () => _removeStaff(user.id, user.name),
                                  tooltip: 'Remove Staff',
                                )
                              : null,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
