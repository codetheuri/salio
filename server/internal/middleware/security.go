package middleware

import (
	"net/http"
	"strings"
	"time"
)

// SecurityHeaders adds security-hardening HTTP headers to every response.
// Headers are tuned differently for API routes vs console (HTML) routes.
func SecurityHeaders() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()

			// Common headers — applied to ALL routes
			h.Set("X-Content-Type-Options", "nosniff")
			h.Set("X-Frame-Options", "DENY")
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
			h.Set("X-XSS-Protection", "0")
			h.Set("Referrer-Policy", "no-referrer")
			h.Set("Server", "") // Hide tech stack

			// Content-Security-Policy is tuned per route type:
			//   - API routes: strict "default-src 'none'" — pure JSON, no resources needed
			//   - Console/static routes: allow same-origin CSS and images for the web UI
			if isConsoleRoute(r.URL.Path) {
				h.Set("Content-Security-Policy",
					"default-src 'none'; "+
						"style-src 'self'; "+   // Allow CSS from /static/css/
						"img-src 'self' data:; "+ // Allow images from /static/
						"font-src 'self'; "+
						"form-action 'self'",    // Forms can only POST to same origin
				)
			} else {
				// Strict API CSP — no resources, no scripts, nothing
				h.Set("Content-Security-Policy", "default-src 'none'")
			}

			next.ServeHTTP(w, r)
		})
	}
}

// isConsoleRoute returns true for paths that serve HTML pages and static assets.
func isConsoleRoute(path string) bool {
	return strings.HasPrefix(path, "/console") ||
		strings.HasPrefix(path, "/static")
}

// RequestTimeout wraps each request in a context with a hard deadline.
// If a handler takes longer than the timeout, the request is cancelled and
// the client receives a 503. Prevents slow clients from holding DB connections.
func RequestTimeout(timeout time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.TimeoutHandler(next, timeout, `{"success":false,"error":{"code":"TIMEOUT","message":"Request timed out. Please try again."}}`).ServeHTTP(w, r)
		})
	}
}
