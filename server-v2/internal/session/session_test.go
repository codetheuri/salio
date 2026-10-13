package session_test

import (
	"net/http"
	"testing"
	"time"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/session"
)

func TestCheck(t *testing.T) {
	changed := time.Date(2026, 10, 13, 12, 0, 0, 500_000_000, time.UTC) // 12:00:00.5
	cases := []struct {
		name     string
		user     domain.User
		issued   time.Time
		op       string
		wantOK   bool
		wantCode int
	}{
		{"an active account, never signed out", domain.User{IsActive: true}, changed, "list-customers", true, 0},
		{"a deactivated account", domain.User{IsActive: false}, changed, "list-customers", false, http.StatusUnauthorized},
		{"a token from before a password change", domain.User{IsActive: true, SessionsValidAfter: &changed},
			changed.Add(-2 * time.Second), "list-customers", false, http.StatusUnauthorized},
		// The token handed to the person changing the password is issued in
		// the same second, and JWT iat has one-second resolution.
		{"a token from the same second as the change", domain.User{IsActive: true, SessionsValidAfter: &changed},
			changed.Truncate(time.Second), "list-customers", true, 0},
		{"must change password: other work", domain.User{IsActive: true, MustChangePassword: true},
			changed, "list-customers", false, http.StatusForbidden},
		{"must change password: changing it", domain.User{IsActive: true, MustChangePassword: true},
			changed, "change-my-password", true, 0},
		{"must change password: own profile", domain.User{IsActive: true, MustChangePassword: true},
			changed, "get-me", true, 0},
		{"deactivation wins over everything", domain.User{IsActive: false, MustChangePassword: true},
			changed, "change-my-password", false, http.StatusUnauthorized},
	}
	for _, c := range cases {
		ok, code, _ := session.Check(c.user, c.issued, c.op)
		if ok != c.wantOK || code != c.wantCode {
			t.Errorf("%s: got (%v, %d), want (%v, %d)", c.name, ok, code, c.wantOK, c.wantCode)
		}
	}
}
