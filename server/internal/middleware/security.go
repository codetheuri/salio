package middleware

import (
	"net/http"
	"time"
)

// SecurityHeaders adds security-hardening HTTP headers to every response.
// These protect against common web vulnerabilities even for API-only servers.
func SecurityHeaders() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := w.Header()

			// Prevent browsers from MIME-sniffing the content type
			h.Set("X-Content-Type-Options", "nosniff")

			// Do not allow this API to be embedded in iframes (clickjacking)
			h.Set("X-Frame-Options", "DENY")

			// Enforce HTTPS for 1 year when accessed over TLS (behind Nginx)
			h.Set("Strict-Transport-Security", "max-age=31536000; includeSubDomains")

			// Disable legacy XSS auditor (modern browsers ignore it, old ones break on it)
			h.Set("X-XSS-Protection", "0")

			// Strict Content Security Policy — this is an API, not a web page
			h.Set("Content-Security-Policy", "default-src 'none'")

			// Do not send referrer information
			h.Set("Referrer-Policy", "no-referrer")

			// Remove the server identifier (don't leak tech stack)
			h.Set("Server", "")

			next.ServeHTTP(w, r)
		})
	}
}

// RequestTimeout wraps each request in a context with a hard deadline.
// If a handler takes longer than the timeout, the request is cancelled and
// the client receives a 503. Prevents slow clients from holding DB connections.
func RequestTimeout(timeout time.Duration) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			// Chi's built-in Timeout middleware handles this cleanly
			// We expose our own wrapper so the timeout is in our config, not hardcoded.
			http.TimeoutHandler(next, timeout, `{"success":false,"error":{"code":"TIMEOUT","message":"Request timed out. Please try again."}}`).ServeHTTP(w, r)
		})
	}
}
