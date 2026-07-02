package middleware

import (
	"net/http"
	"strings"

	"github.com/rs/cors"
)

// CORS returns a configured CORS middleware handler.
// CORS (Cross-Origin Resource Sharing) is needed for:
//   - Flutter Web clients running in a browser
//   - API testing tools like Swagger UI or Postman browser extension
//   - Future web dashboard
//
// For the mobile Flutter app, CORS is irrelevant (native apps don't have an origin).
// We configure it now so future web clients work without code changes.
func CORS(allowedOrigins []string) func(http.Handler) http.Handler {
	c := cors.New(cors.Options{
		AllowedOrigins: allowedOrigins,
		AllowedMethods: []string{
			http.MethodGet,
			http.MethodPost,
			http.MethodPut,
			http.MethodDelete,
			http.MethodOptions,
		},
		AllowedHeaders: []string{
			"Authorization",
			"Content-Type",
			"X-Request-ID",
		},
		ExposedHeaders: []string{
			"X-Request-ID", // Allow clients to read the request ID for debugging
		},
		// AllowCredentials must be FALSE when AllowedOrigins contains "*".
		// Set to true only if you add specific origins in CORS_ALLOWED_ORIGINS.
		AllowCredentials: !containsWildcard(allowedOrigins),
		MaxAge:           86400, // Cache preflight response for 24 hours
	})
	return c.Handler
}

func containsWildcard(origins []string) bool {
	for _, o := range origins {
		if strings.TrimSpace(o) == "*" {
			return true
		}
	}
	return false
}
