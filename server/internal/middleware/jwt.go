package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// contextKey is an unexported type to prevent key collisions in request context.
type contextKey string

const (
	ContextKeyUserID     contextKey = "user_id"
	ContextKeyBusinessID contextKey = "business_id"
	ContextKeyRole       contextKey = "role"
)

// Claims defines the payload we embed inside our JWTs.
// It must match what the auth repository creates during login.
type Claims struct {
	UserID     uuid.UUID `json:"user_id"`
	BusinessID uuid.UUID `json:"business_id"`
	Role       string    `json:"role"`
	jwt.RegisteredClaims
}

// Authenticate is a Chi middleware that validates the JWT on every protected route.
// It extracts the Bearer token from the Authorization header, verifies it,
// and injects the user's identity into the request context for downstream handlers.
func Authenticate(jwtSecret string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := r.Header.Get("Authorization")
			if authHeader == "" {
				writeAuthError(w, http.StatusUnauthorized, "Authorization header is required")
				return
			}

			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
				writeAuthError(w, http.StatusUnauthorized, "Invalid authorization format. Expected: Bearer <token>")
				return
			}

			tokenString := parts[1]
			claims := &Claims{}

			token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
				// Ensure the signing method is what we expect (HMAC)
				if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
					return nil, jwt.ErrSignatureInvalid
				}
				return []byte(jwtSecret), nil
			})

			if err != nil || !token.Valid {
				writeAuthError(w, http.StatusUnauthorized, "Invalid or expired token. Please log in again.")
				return
			}

			// Inject verified identity into context so handlers can use it
			ctx := context.WithValue(r.Context(), ContextKeyUserID, claims.UserID)
			ctx = context.WithValue(ctx, ContextKeyBusinessID, claims.BusinessID)
			ctx = context.WithValue(ctx, ContextKeyRole, claims.Role)

			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// RequireRole returns a middleware that blocks access unless the user's role
// matches one of the allowed roles. Must be used AFTER Authenticate.
func RequireRole(allowedRoles ...string) func(http.Handler) http.Handler {
	allowedSet := make(map[string]bool, len(allowedRoles))
	for _, r := range allowedRoles {
		allowedSet[r] = true
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			role, ok := r.Context().Value(ContextKeyRole).(string)
			if !ok || !allowedSet[role] {
				writeAuthError(w, http.StatusForbidden, "Forbidden: you do not have permission to perform this action")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// GetUserID is a helper for handlers to safely extract the user ID from context.
func GetUserID(ctx context.Context) uuid.UUID {
	id, _ := ctx.Value(ContextKeyUserID).(uuid.UUID)
	return id
}

// GetBusinessID is a helper for handlers to safely extract the business ID from context.
func GetBusinessID(ctx context.Context) uuid.UUID {
	id, _ := ctx.Value(ContextKeyBusinessID).(uuid.UUID)
	return id
}

// writeAuthError writes a structured error response matching the API envelope.
// Defined here to avoid an import cycle with the api package.
func writeAuthError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	code := "UNAUTHORIZED"
	if status == http.StatusForbidden {
		code = "FORBIDDEN"
	}
	_ = json.NewEncoder(w).Encode(map[string]any{
		"success": false,
		"error": map[string]string{
			"code":    code,
			"message": message,
		},
	})
}
