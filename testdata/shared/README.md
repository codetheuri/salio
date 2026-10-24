# Shared test vectors

Test cases written as data, read by both the Go tests (server-v2) and the
Dart tests (mobile-v2). A rule that the phone repeats from the server is
pinned here, so changing it on one side only fails CI on that side
(docs/10, §4.4).

| File | Go test | Dart test |
|---|---|---|
| `role_permissions.json` | `server-v2/internal/rbac/shared_vectors_test.go` | `mobile-v2/test/permissions_test.dart` |
| `money.json` | `server-v2/internal/money/shared_vectors_test.go` | `mobile-v2/test/money_test.dart` |
| `quantity.json` | `server-v2/internal/quantity/shared_vectors_test.go` | `mobile-v2/test/quantity_test.dart` |
| `phone.json` | `server-v2/internal/phone/phone_test.go` and `migration_test.go` (the SQL of migration 00010 too) | `mobile-v2/test/phone_test.dart` |
| `dues.json` | `server-v2/internal/reports/shared_vectors_test.go` | `mobile-v2/test/dues_test.dart` |
| `payment_reference.json` | `server-v2/internal/payment/shared_vectors_test.go` | `mobile-v2/test/payment_reference_test.dart` |

Add a file here, and a test on both sides, for every rule the app repeats.

The money vectors found a real bug on their first run: server-v2's
`money.Parse("-")` returned 0 instead of an error, because the empty check ran
before the sign was removed.

The quantity vectors found the same bug in `quantity.Parse` on theirs
(2026-10-24): a lone sign, `-` or `+`, was read as zero.
