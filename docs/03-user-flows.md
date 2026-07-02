# Salio — User Flows

**Version:** 1.1  
**Date:** June 2026

This document describes every key user journey in the Salio mobile app as step-by-step flows, including the new multi-user authentication flows.

---

## Flow Notation

```
[Screen Name]  — a screen the user sees
(Action)       — something the user does
→              — leads to
```

---

## UF-00A: Owner Registration & Setup (Requires Internet)

```
[Splash Screen]
→ [Welcome Screen]
  - Options: [Create New Business] or [Log In] or [Join as Staff]
(User taps "Create New Business")
→ [Register Business Screen]
  - Inputs: Business Name, Owner Name, Phone Number, Password
  - (User fills details and taps "Register")
→ [Loading Overlay] (Calls backend API to create business and owner user)
→ [Dashboard Screen] (Empty state)
  - JWT is cached. SQLite is initialized for this business.
  - Snackbar: "Welcome to Salio!"
```

---

## UF-00B: Staff Login via Invite (Requires Internet)

```
[Welcome Screen]
(User taps "Join as Staff")
→ [Join Business Screen]
  - Inputs: Invite Code (provided by Owner), Staff Name, Phone Number, Password
  - (User fills details and taps "Join")
→ [Loading Overlay] (Validates code, creates user on backend)
→ [Syncing Overlay] (Downloads existing business data to local SQLite)
→ [Dashboard Screen]
  - Staff sees all existing customers and balances.
```

---

## UF-00C: Standard Login (Requires Internet)

```
[Welcome Screen]
(User taps "Log In")
→ [Login Screen]
  - Inputs: Phone Number, Password
  - (User fills and taps "Log In")
→ [Loading Overlay] (Validates with backend, gets JWT)
→ [Syncing Overlay] (Syncs down any fresh data to local SQLite)
→ [Dashboard Screen]
```

---

## UF-01: First Launch Offline (Cached JWT)

The very first time a user opens the app after they have previously logged in.

```
[Splash Screen]
→ App checks secure storage for JWT.
→ Token exists? Yes.
→ [Dashboard Screen] (Instantly loads from SQLite, no internet required)
```

---

## UF-02: Add a New Customer

```
[Dashboard Screen]
(User taps the "+ Add Customer" FAB button)
→ [Add Customer Screen]
  - Inputs: Name (required), Phone Number (optional)
  - (User fills in name and phone)
  - (User taps "Save Customer")
→ [Validation]
  - If name is empty → show inline error "Customer name is required"
  - If valid → save to SQLite (with `business_id` and `created_by` = current user)
→ [Dashboard Screen]
  - New customer appears in the list with balance KES 0
  - Snackbar: "Customer added successfully ✓"
```

---

## UF-03: Record a Debt (Selling on Credit)

```
[Dashboard Screen]
(User taps on a customer's name in the list)
→ [Customer Detail Screen]
(User taps "+ Add Debt")
→ [Add Transaction Screen] (type = 'debt')
  - Inputs: Amount, Description, Date
  - (User enters amount and taps "Record Debt")
→ [Validation]
  - If valid → save to SQLite (sets `user_id` = current staff member)
→ [Customer Detail Screen]
  - New debt appears. Balance increases.
```

---

## UF-04: View Customer History (Multi-User Visibility)

```
[Customer Detail Screen]
  ┌─────────────────────────────┐
  │ John Kamau        [Edit ✎] │
  │ Phone: 0712 xxx xxx         │
  │ ┌─────────────────────────┐ │
  │ │ Outstanding Balance     │ │
  │ │ KES 1,700               │ │
  │ └─────────────────────────┘ │
  │ [+ Add Debt] [Record Payment]│
  │ ─── Transaction History ─── │
  │ Jun 20 - Debt    +500       │
  │   Recorded by: You          │
  │ Jun 18 - Payment -300       │
  │   Recorded by: Jane (Staff) │
  └─────────────────────────────┘
```

---

## UF-05: Invite Staff (Owner Only)

```
[Dashboard Screen]
(User taps Settings/Profile Icon)
→ [Settings Screen]
(User taps "Manage Staff")
→ [Staff List Screen]
(User taps "Invite Staff Member")
→ [Invite Code Screen]
  - App requests a new invite code from the backend (requires internet).
  - Shows large 6-digit code: "A4F-982"
  - "Give this code to your staff member. It expires in 24 hours."
```

---

## Screen Summary Table

| Screen ID | Screen Name | Route |
|---|---|---|
| S-01 | Splash Screen | `/splash` |
| S-02 | Welcome / Auth Choice | `/welcome` |
| S-03 | Login / Register | `/auth` |
| S-04 | Dashboard | `/` (home) |
| S-05 | Add/Edit Customer | `/customers/form` |
| S-06 | Customer Detail | `/customers/:id` |
| S-07 | Add Transaction | `/transactions/form` |
| S-08 | Settings / Staff | `/settings` |
