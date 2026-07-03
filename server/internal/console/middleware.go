package console

import (
	"context"
	"net/http"
)

type contextKey string

const contextKeyAdmin contextKey = "console_admin"
const sessionCookieName = "salio_console_session"

// RequireAuth is a middleware method on Handler that protects console routes.
// It reads the session cookie, validates it against the DB via the embedded repo,
// and injects the super admin into the request context.
// If the session is missing or invalid, it redirects to /console/login.
func (h *Handler) RequireAuth() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			cookie, err := r.Cookie(sessionCookieName)
			if err != nil {
				http.Redirect(w, r, "/console/login", http.StatusSeeOther)
				return
			}

			admin, err := h.repo.GetSessionWithAdmin(r.Context(), cookie.Value)
			if err != nil {
				// Clear the invalid cookie before redirecting
				http.SetCookie(w, &http.Cookie{
					Name:   sessionCookieName,
					Value:  "",
					MaxAge: -1,
					Path:   "/console",
				})
				http.Redirect(w, r, "/console/login", http.StatusSeeOther)
				return
			}

			// Inject the verified admin into context for downstream handlers
			ctx := context.WithValue(r.Context(), contextKeyAdmin, admin)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// SetSessionCookie writes the session ID as a secure HTTP-only cookie.
// HTTP-only prevents JavaScript access (XSS protection).
// SameSite=Lax prevents CSRF attacks.
func SetSessionCookie(w http.ResponseWriter, sessionID string, isProduction bool) {
	http.SetCookie(w, &http.Cookie{
		Name:     sessionCookieName,
		Value:    sessionID,
		Path:     "/console",
		MaxAge:   8 * 60 * 60, // 8 hours in seconds
		HttpOnly: true,         // Not readable by JavaScript
		Secure:   isProduction, // HTTPS only in production
		SameSite: http.SameSiteLaxMode,
	})
}

// ClearSessionCookie removes the session cookie on logout.
func ClearSessionCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:   sessionCookieName,
		Value:  "",
		Path:   "/console",
		MaxAge: -1,
	})
}
