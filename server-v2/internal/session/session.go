// Package session decides, on every signed-in request, whether the session
// behind the token is still allowed — which a valid signature alone cannot say.
//
// Tokens live 30 days, on purpose: an offline shop must never be locked out of
// its own ledger. But a token cannot be recalled once issued, and until this
// existed nothing re-checked the account behind one. Two consequences, both
// confirmed on 2026-10-13:
//
//   - A deactivated member of staff kept full access — the app and sync — until
//     their token expired. Deactivation only stopped them signing in again.
//     (A comment promised sync would re-check is_active; it never did.)
//   - Changing a password ended no sessions, so it protected nothing: a phone
//     that had been stolen stayed signed in.
//
// The guard runs one primary-key read per request, on the request's own
// connection, scoped to the token's tenant like everything else.
package session

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	tuskmw "github.com/codetheuri/tusk/v2/pkg/middleware"
	"github.com/danielgtaylor/huma/v2"
	"github.com/golang-jwt/jwt/v5"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
)

// AllowedWhileChangingPassword are the operations open to a user who must
// choose a new password: seeing who they are, and choosing it. Anything more
// would let a temporary password — read out loud by an owner — do real work.
var AllowedWhileChangingPassword = map[string]bool{
	"get-me":             true,
	"change-my-password": true,
}

// Messages a client can show as they are. The app tells "sign in again" apart
// from other 401s by these, so they are part of the contract.
const (
	MsgDeactivated    = "This account has been deactivated. Ask the shop owner."
	MsgSessionEnded   = "You were signed out because the password was changed. Please sign in again."
	MsgMustChange     = "Choose a new password before continuing."
	MsgUnknownAccount = "This account no longer exists. Please sign in again."
)

// Guard returns Huma middleware enforcing the rules above. Register it after
// the authentication, tenant and tenantconn middleware.
func Guard(api huma.API, db *gorm.DB, jwtSecret string, log logger.Logger) func(huma.Context, func(huma.Context)) {
	return func(ctx huma.Context, next func(huma.Context)) {
		sub, ok := authz.SubjectFromContext(ctx.Context())
		if !ok {
			next(ctx) // anonymous: the route's own guard decides
			return
		}

		issuedAt, err := issuedAt(ctx.Header("Authorization"), jwtSecret)
		if err != nil {
			// Authentication already verified this token, so failing to read it
			// again means something is wrong here, not with the caller.
			log.Error("session: re-reading a verified token", err)
			huma.WriteErr(api, ctx, http.StatusUnauthorized, "Invalid or expired token")
			return
		}

		var u domain.User
		err = db.WithContext(ctx.Context()).
			Select("id", "business_id", "is_active", "sessions_valid_after", "must_change_password").
			First(&u, "id = ?", sub.UserID).Error
		switch {
		case errors.Is(err, gorm.ErrRecordNotFound):
			// Scoped to the token's tenant, so this is also what a token naming
			// a user of another business would get.
			huma.WriteErr(api, ctx, http.StatusUnauthorized, MsgUnknownAccount)
			return
		case err != nil:
			log.Error("session: loading the account", err)
			huma.WriteErr(api, ctx, http.StatusServiceUnavailable, "The service is busy. Please try again.")
			return
		}

		if verdict, status, msg := Check(u, issuedAt, ctx.Operation().OperationID); !verdict {
			huma.WriteErr(api, ctx, status, msg)
			return
		}
		next(ctx)
	}
}

// Check is the decision itself, separate from HTTP so it can be tested on its
// own. A token issued in the same second as a password change survives: JWT
// timestamps have one-second resolution, and the token issued to the person
// changing the password is issued in that same second.
func Check(u domain.User, issuedAt time.Time, operationID string) (ok bool, status int, message string) {
	switch {
	case !u.IsActive:
		return false, http.StatusUnauthorized, MsgDeactivated
	case u.SessionsValidAfter != nil && issuedAt.Before(u.SessionsValidAfter.Truncate(time.Second)):
		return false, http.StatusUnauthorized, MsgSessionEnded
	case u.MustChangePassword && !AllowedWhileChangingPassword[operationID]:
		return false, http.StatusForbidden, MsgMustChange
	}
	return true, 0, ""
}

// issuedAt reads the token's iat claim. Parsed with the same rule Tusk's
// authentication applies — HMAC only — so this can never accept a token that
// authentication would have refused.
func issuedAt(header, secret string) (time.Time, error) {
	raw, ok := strings.CutPrefix(header, "Bearer ")
	if !ok {
		raw, ok = strings.CutPrefix(header, "bearer ")
	}
	if !ok {
		return time.Time{}, errors.New("no bearer token")
	}
	claims := &tuskmw.Claims{}
	_, err := jwt.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, jwt.ErrSignatureInvalid
		}
		return []byte(secret), nil
	})
	if err != nil {
		return time.Time{}, err
	}
	if claims.IssuedAt == nil {
		// Every token Salio issues carries iat. One without it cannot be
		// placed before or after a password change, so it is not trusted.
		return time.Time{}, errors.New("token has no iat")
	}
	return claims.IssuedAt.Time, nil
}
