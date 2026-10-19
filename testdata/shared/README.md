# Shared test vectors

Test cases written as data, read by both the Go tests (server-v2) and the
Dart tests (mobile-v2). A rule that the phone repeats from the server is
pinned here, so changing it on one side only fails CI on that side
(docs/10, §4.4).

| File | Go test | Dart test |
|---|---|---|
| `role_permissions.json` | `server-v2/internal/rbac/shared_vectors_test.go` | `mobile-v2/test/permissions_test.dart` |
| `money.json` | `server-v2/internal/money/shared_vectors_test.go` | `mobile-v2/test/money_test.dart` |

Add a file here, and a test on both sides, for every rule the app repeats.

The money vectors found a real bug on their first run: server-v2's
`money.Parse("-")` returned 0 instead of an error, because the empty check ran
before the sign was removed.
