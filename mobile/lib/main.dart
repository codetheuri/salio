import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Services
import 'core/storage/secure_storage.dart';
import 'core/network/api_client.dart';
import 'core/network/sync_service.dart';
import 'features/auth/http_auth_repository.dart';
import 'features/customer/sqflite_customer_repository.dart';
import 'features/transaction/sqflite_transaction_repository.dart';
import 'features/settings/sqflite_settings_repository.dart';

// Providers
import 'features/auth/auth_provider.dart';
import 'features/customer/customer_provider.dart';
import 'features/transaction/transaction_provider.dart';
import 'features/settings/settings_provider.dart';

// Screens
import 'features/auth/screens/login_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Instantiate our core services (Dependency Injection)
  final secureStorage = SecureStorageService();
  final apiClient = ApiClient(secureStorage: secureStorage);
  
  // Phase 2: We swap the Mock implementation for the real HttpAuthRepository!
  final authRepository = HttpAuthRepository(apiClient: apiClient);
  
  final customerRepository = SqfliteCustomerRepository();
  final transactionRepository = SqfliteTransactionRepository();
  final settingsRepository = SqfliteSettingsRepository();

  // Phase 3: Setup the Sync Service
  final syncService = SyncService(
    apiClient: apiClient, 
    secureStorage: secureStorage,
  );

  runApp(
    MultiProvider(
      providers: [
        // 1. AuthProvider sits at the top of the tree
        ChangeNotifierProvider(
          create: (_) => AuthProvider(authRepository, secureStorage, syncService: syncService)..checkAuthStatus(),
        ),
        
        // 2. CustomerProvider sits below it using a ProxyProvider.
        // This is crucial: it allows CustomerProvider to "listen" to AuthProvider.
        // When a user logs in, or when a background sync finishes, this triggers!
        ChangeNotifierProxyProvider<AuthProvider, CustomerProvider>(
          create: (_) => CustomerProvider(customerRepository),
          update: (_, auth, customerProvider) {
            return customerProvider!..updateAuthData(auth.businessId, auth.userId, auth.lastSyncCompletionTime);
          },
        ),
        
        // 3. TransactionProvider
        ChangeNotifierProxyProvider<AuthProvider, TransactionProvider>(
          create: (_) => TransactionProvider(transactionRepository),
          update: (_, auth, transactionProvider) {
            return transactionProvider!..updateAuthData(auth.businessId, auth.userId, auth.lastSyncCompletionTime);
          },
        ),
        
        // 4. SettingsProvider
        ChangeNotifierProxyProvider<AuthProvider, SettingsProvider>(
          create: (_) => SettingsProvider(settingsRepository),
          update: (_, auth, settingsProvider) {
            return settingsProvider!..updateAuthData(auth.businessId, auth.userId);
          },
        ),
      ],
      child: const SalioApp(),
    ),
  );
}

class SalioApp extends StatelessWidget {
  const SalioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Salio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const AuthWrapper(),
    );
  }
}

/// AuthWrapper acts as our routing brain. 
/// It listens to AuthProvider and shows the correct screen automatically.
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthProvider>().state;

    switch (authState) {
      case AuthState.initial:
      case AuthState.loading:
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: Colors.teal),
          ),
        );
      case AuthState.unauthenticated:
        return const LoginScreen();
      case AuthState.authenticated:
        return const DashboardScreen();
    }
  }
}
