import 'package:flutter/foundation.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/network/sync_service.dart';
import '../../core/utils/logger.dart';
import 'auth_repository.dart';

enum AuthState { initial, authenticated, unauthenticated, loading }

/// The global AuthProvider.
/// This acts as the brain of our authentication system. It checks for a secure
/// offline token on startup, handles login requests, and notifies the entire
/// app (and other providers) when the user logs in or out.
class AuthProvider extends ChangeNotifier {
  final AuthRepository _authRepository;
  final SecureStorageService _secureStorage;
  final SyncService? _syncService;

  AuthState _state = AuthState.initial;
  String? _businessId;
  String? _userId;
  String? _role;
  String? _errorMessage;
  
  bool _isSyncing = false;
  DateTime? _lastSyncCompletionTime;

  AuthProvider(this._authRepository, this._secureStorage, {SyncService? syncService})
      : _syncService = syncService;

  AuthState get state => _state;
  String? get businessId => _businessId;
  String? get userId => _userId;
  String? get role => _role;
  String? get errorMessage => _errorMessage;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncCompletionTime => _lastSyncCompletionTime;

  /// Checks if a valid token exists in secure storage. 
  /// Called exactly once when the app boots up.
  Future<void> checkAuthStatus() async {
    _state = AuthState.loading;
    notifyListeners();

    try {
      final token = await _secureStorage.getToken();
      
      // If we have a token and it hasn't expired, let the user right into the app offline!
      if (token != null && !JwtDecoder.isExpired(token)) {
        _decodeAndSetUser(token);
        _state = AuthState.authenticated;
        Logger.i('User authenticated offline from secure storage. Business ID: $_businessId');
        
        // Trigger a background sync now that we are logged in
        triggerSync();
      } else {
        _state = AuthState.unauthenticated;
        Logger.i('No valid token found. User needs to login.');
      }
    } catch (e, stackTrace) {
      Logger.e('Failed to check auth status', e, stackTrace);
      _state = AuthState.unauthenticated;
    }
    
    notifyListeners();
  }

  /// Attempts to log the user in.
  Future<bool> login(String phone, String password) async {
    _errorMessage = null;

    try {
      final token = await _authRepository.login(phone, password);
      
      // Save it securely to the device
      await _secureStorage.saveToken(token);
      
      // Extract their business scoping data
      _decodeAndSetUser(token);
      
      _state = AuthState.authenticated;
      notifyListeners();

      // Trigger background sync immediately after login
      triggerSync();
      
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Attempts to register a new business and owner.
  Future<bool> registerBusiness(String businessName, String ownerName, String phone, String password) async {
    _errorMessage = null;

    try {
      final token = await _authRepository.registerBusiness(businessName, ownerName, phone, password);
      
      // Save it securely to the device
      await _secureStorage.saveToken(token);
      
      // Extract their business scoping data
      _decodeAndSetUser(token);
      
      _state = AuthState.authenticated;
      notifyListeners();

      // Trigger background sync immediately after registration
      triggerSync();
      
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Attempts to join a business as a staff member using an invite code.
  Future<bool> joinBusiness(String inviteCode, String name, String phone, String password) async {
    _errorMessage = null;

    try {
      final token = await _authRepository.joinBusiness(inviteCode, name, phone, password);
      
      // Save it securely to the device
      await _secureStorage.saveToken(token);
      
      // Extract their business scoping data
      _decodeAndSetUser(token);
      
      _state = AuthState.authenticated;
      notifyListeners();

      // Trigger background sync immediately after joining
      triggerSync();
      
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Clears the token and boots the user to the login screen.
  Future<void> logout() async {
    // Clear all secure storage, including tokens and last_sync timestamps
    await _secureStorage.clearAll();
    _businessId = null;
    _userId = null;
    _role = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  /// Helper to extract data from the JWT without making an API call.
  void _decodeAndSetUser(String token) {
    Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
    _businessId = decodedToken['business_id'];
    _userId = decodedToken['user_id'];
    _role = decodedToken['role'];
  }

  /// Manually triggers a sync cycle and returns a status string for the UI.
  Future<String> triggerSync() async {
    if (_syncService == null) return 'error';
    if (_isSyncing) return 'syncing';
    
    _isSyncing = true;
    notifyListeners(); // Tell the UI to show a spinner

    try {
      await _syncService?.sync();
      _lastSyncCompletionTime = DateTime.now();
      return 'success';
    } catch (e) {
      if (e.toString().contains('SocketException') || e.toString().contains('offline')) {
        return 'offline';
      }
      return 'error';
    } finally {
      _isSyncing = false;
      notifyListeners(); // Tell the UI the spinner is done and data might be fresh
    }
  }
}
