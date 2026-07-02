# Salio — Mobile App Architecture

**Version:** 1.1  
**Date:** June 2026

This document defines the technical architecture of the Salio Flutter mobile application, including the offline-first authentication and multi-user data scoping strategy.

---

## 1. Architecture Pattern: Feature-First Clean Architecture

```
UI (Widgets/Screens)
      ↓ calls
State Management (Provider + ChangeNotifier)
      ↓ calls
Repository (abstract business logic layer)
      ↓ calls
Database Layer (sqflite)  <-- AND -->  Auth/Sync Layer (http)
      ↓ reads/writes                         ↓ sends/receives
SQLite (local device storage)           Go Backend (PostgreSQL)
```

---

## 2. Folder Structure

```
mobile/
└── lib/
    ├── main.dart
    │
    ├── core/
    │   ├── database/
    │   │   ├── database_service.dart
    │   │   └── sql_queries.dart
    │   ├── network/                   # NEW: API client
    │   │   └── api_client.dart        # Handles HTTP, JWT injection, Error parsing
    │   ├── storage/                   # NEW: Secure storage
    │   │   └── secure_storage.dart    # flutter_secure_storage wrapper for JWT
    │   ├── models/
    │   │   ├── user.dart
    │   │   ├── customer.dart
    │   │   └── transaction.dart
    │   └── theme/
    │
    ├── features/
    │   │
    │   ├── auth/                      # NEW: Auth feature
    │   │   ├── auth_repository.dart   # API calls for login/register
    │   │   ├── auth_provider.dart     # Manages login state, JWT caching
    │   │   └── screens/
    │   │       └── login_screen.dart
    │   │
    │   ├── dashboard/
    │   │
    │   ├── customer/
    │   │   └── customer_repository.dart # All queries now scope by business_id
    │   │
    │   └── transaction/
    │
    └── router/
        └── app_router.dart
```

---

## 3. State Management: Provider + Auth Scoping

We use the **Provider** package. With the addition of Auth, the root of our app needs to react to the Authentication state.

### Auth State Flow
1. App launches → `AuthProvider.checkAuthStatus()`
2. Reads `secure_storage` for JWT.
3. If token exists → parse it to get `current_user_id` and `current_business_id`.
4. Router directs to `DashboardScreen`.
5. If no token → Router directs to `WelcomeScreen`.

```dart
// Dependency Injection at the root
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => AuthProvider()),
    // Other providers use ProxyProvider to get the current business_id from Auth
    ChangeNotifierProxyProvider<AuthProvider, CustomerProvider>(
      create: (_) => CustomerProvider(),
      update: (_, auth, customerProvider) => 
          customerProvider!..updateAuthData(auth.businessId, auth.userId),
    ),
  ],
  child: const SalioApp(),
)
```

---

## 4. Database Layer: Multi-Tenant Scoping

Because multiple businesses could technically be logged into the same device (e.g., if a user logs out and another user logs in), **every single SQLite query MUST be scoped to the `business_id`**.

```dart
// Bad:
// SELECT * FROM customers;

// Good:
// SELECT * FROM customers WHERE business_id = ? AND is_deleted = 0;
```

When `CustomerRepository.add(Customer)` is called, it automatically injects the current user's `business_id` and `user_id` (as `created_by`) into the SQLite insert statement.

---

## 5. Offline-First Authentication Strategy

1. **Online Requirement**: Creating an account, logging in, or joining via invite code *requires* internet.
2. **JWT Storage**: Upon successful login, the Go backend returns a JWT containing `user_id`, `business_id`, and `role`. This is stored using `flutter_secure_storage`.
3. **Offline Day-to-Day**: 
   - The app reads the JWT from secure storage on boot.
   - It trusts the cached token (until the server rejects it during a background sync).
   - All UI reads/writes hit the local SQLite database. No loading spinners for saving debts.
4. **Data Sync**: When internet is detected, a background worker pushes new SQLite records to the Go backend and pulls any records created by *other staff members*.

---

## 6. Key Dart Packages (Updated)

| Package | Version | Purpose |
|---|---|---|
| `sqflite` | ^2.3.0 | SQLite local database |
| `provider` | ^6.1.0 | State management |
| `flutter_secure_storage` | ^9.0.0 | **NEW**: Securely store JWT and auth tokens |
| `http` | ^1.2.0 | **NEW**: Making REST API calls to Go backend |
| `jwt_decoder` | ^2.0.1 | **NEW**: Decoding JWT to extract business_id without hitting the network |
| `uuid` | ^4.3.0 | Generate UUID v4 |
