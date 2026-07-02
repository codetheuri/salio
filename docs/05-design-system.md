# Salio — Design System

**Version:** 1.0  
**Date:** June 2026

This document defines the visual identity, color palette, typography, spacing, and component guidelines for the Salio mobile application.

---

## 1. Design Philosophy

Salio is built for a **non-technical, time-pressured** shop owner. The design must be:

- **Glanceable**: Key information (who owes, how much) visible in under 2 seconds.
- **Thumb-friendly**: All primary actions reachable with one thumb on a mid-size phone.
- **High-contrast**: Readable in bright outdoor light (shops, markets, open-air stalls).
- **Trustworthy**: Clean, professional look — not flashy. Inspires confidence in data accuracy.
- **Fast**: No heavy animations. Transitions should feel instant.

---

## 2. Color Palette

### Primary Palette: Teal

Teal conveys trust, stability, and freshness — appropriate for a financial tool.

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#00796B` | AppBar, primary buttons, key balance figures |
| `primaryLight` | `#B2DFDB` | Light backgrounds, avatars, chip fills |
| `primaryDark` | `#004D40` | Summary card background, pressed states |
| `onPrimary` | `#FFFFFF` | Text on primary backgrounds |

### Semantic Colors

| Token | Hex | Usage |
|---|---|---|
| `debtRed` | `#C62828` | Debt amounts in transaction history |
| `paymentGreen` | `#2E7D32` | Payment amounts, "Cleared" status |
| `warningAmber` | `#F57F17` | Overdue indicator (future) |
| `textPrimary` | `#212121` | Main body text |
| `textSecondary` | `#757575` | Subtitles, hints, helper text |
| `divider` | `#EEEEEE` | List separators |
| `background` | `#F5F5F5` | Screen background |
| `surface` | `#FFFFFF` | Cards, sheets, dialogs |
| `error` | `#D32F2F` | Inline validation errors |

---

## 3. Typography

We use the system default sans-serif font (Roboto on Android) via Flutter's Material Design 3 defaults.

| Style Name | Font Size | Weight | Usage |
|---|---|---|---|
| `displayLarge` | 32sp | Bold (700) | Large balance figure on dashboard card |
| `headlineMedium` | 22sp | SemiBold (600) | Screen titles, customer name in detail view |
| `titleMedium` | 16sp | SemiBold (600) | List tile primary text (customer name) |
| `bodyMedium` | 14sp | Regular (400) | List tile secondary text, descriptions |
| `bodySmall` | 12sp | Regular (400) | Timestamps, hint text |
| `labelLarge` | 14sp | Medium (500) | Button text |

---

## 4. Spacing System

We use a base-8 spacing system:

| Token | Value | Usage |
|---|---|---|
| `xs` | 4px | Tight internal padding (icon margins) |
| `sm` | 8px | Small gaps between related elements |
| `md` | 16px | Standard padding for screens and cards |
| `lg` | 24px | Between major sections |
| `xl` | 32px | Large gaps, top-of-page padding |

---

## 5. Component Guidelines

### 5.1 AppBar
- Background: `primary` (teal)
- Title text: White, centered, bold
- Icons: White
- No elevation shadow (flat design, uses color for separation)

### 5.2 Cards
- Background: `surface` (white)
- Border radius: `12px`
- Elevation: `2`
- Padding: `16px` all sides

### 5.3 Summary Card (Dashboard)
- Background: `primaryDark`
- Text: White
- Border radius: `16px`
- Contains: Label + large balance figure

### 5.4 Buttons

| Type | Style |
|---|---|
| Primary action (e.g., "Save") | `ElevatedButton`, `primary` background, full width |
| Secondary action (e.g., "Cancel") | `TextButton`, `primary` color text |
| Destructive action (e.g., "Delete") | `TextButton`, `error` color text |
| FAB (Add Customer) | `FloatingActionButton`, `primary` background, `+` icon |

### 5.5 List Tiles (Customer)
- Leading: `CircleAvatar` with first letter of customer name, `primaryLight` background
- Title: Customer name, `titleMedium` style
- Trailing: Balance in `debtRed` if > 0, "Cleared ✓" in `paymentGreen` if = 0
- `onTap`: Navigates to customer detail screen

### 5.6 Transaction List Tiles
- Debt entries: Amount prefixed with `+` in `debtRed`
- Payment entries: Amount prefixed with `-` in `paymentGreen`
- Secondary text: Description + date
- No onTap action in Phase 1 (transactions are not editable)

### 5.7 Form Fields
- Style: `OutlineInputBorder`
- Border radius: `8px`
- Error state: `error` color border + inline error text below field
- Currency fields: Keyboard type set to `numberWithOptions(decimal: true)`

### 5.8 Empty States
- Centered illustration (icon or SVG)
- Short, friendly headline text
- Subtext explaining the next action
- Example: "No customers yet. Tap **+** to add your first customer."

---

## 6. Iconography

Use Material Icons (built into Flutter). Avoid custom icons in Phase 1.

| Action | Icon |
|---|---|
| Add customer | `Icons.person_add` |
| Record debt | `Icons.add_shopping_cart` |
| Record payment | `Icons.payments` |
| Search | `Icons.search` |
| Edit | `Icons.edit` |
| Delete | `Icons.delete_outline` |
| Back | `Icons.arrow_back` |
| Cleared / success | `Icons.check_circle` |

---

## 7. Screen Layout Rules

- **Minimum touch target**: 48x48 dp (Material standard).
- **Safe area**: Always use `SafeArea` widget to avoid notch/gesture bar overlap.
- **Keyboard avoidance**: Wrap forms in `SingleChildScrollView` to prevent input field hiding.
- **Loading states**: Show a `CircularProgressIndicator` centered on the screen, not inside buttons.
- **Snackbars**: Use for non-critical feedback (success, info). Duration: 3 seconds.
- **Dialogs**: Use only for destructive confirmations (delete). Do not use for info or success.
