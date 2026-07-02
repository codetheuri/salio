import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../auth_provider.dart';

class JoinBusinessScreen extends StatefulWidget {
  const JoinBusinessScreen({super.key});

  @override
  State<JoinBusinessScreen> createState() => _JoinBusinessScreenState();
}

class _JoinBusinessScreenState extends State<JoinBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _inviteCodeController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleJoin() async {
    ScaffoldMessenger.of(context).clearSnackBars();
    
    if (!_formKey.currentState!.validate()) return;
    
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final authProvider = context.read<AuthProvider>();
    
    // We will need to add a joinBusiness method to AuthProvider
    final success = await authProvider.joinBusiness(
      _inviteCodeController.text.trim(),
      _nameController.text.trim(),
      _phoneController.text.trim(),
      _passwordController.text.trim(),
    );

    if (!mounted) return;

    if (!success) {
      setState(() => _isLoading = false);
      // We don't show a snackbar anymore, the error will be displayed inline via context.watch
    } else {
      // Success! Pop back so the AuthWrapper can route us to the Dashboard
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = context.watch<AuthProvider>().errorMessage;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a Business'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.teal.shade800,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.handshake, size: 80, color: Colors.teal.shade700),
                const SizedBox(height: 16),
                const Text(
                  'Welcome to Salio!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter the invite code provided by your manager to create your staff account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),

                if (errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            errorMessage,
                            style: TextStyle(color: Colors.red.shade700, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Invite Code
                TextFormField(
                  controller: _inviteCodeController,
                  decoration: InputDecoration(
                    labelText: '6-Digit Invite Code',
                    prefixIcon: const Icon(Icons.key),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().length < 6 ? 'Please enter a valid code' : null,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),

                // Name
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Your Full Name',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Name is required' : null,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),

                // Phone
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Your Phone Number',
                    prefixIcon: const Icon(Icons.phone),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Phone is required' : null,
                ),
                const SizedBox(height: 16),

                // Password
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Create a Password',
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.length < 4 ? 'Password must be at least 4 characters' : null,
                ),
                const SizedBox(height: 32),

                // Submit
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleJoin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Join Business', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 32),
                const Center(
                  child: Text(
                    'Salio App\nDeveloped by Joseph Theuri',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
