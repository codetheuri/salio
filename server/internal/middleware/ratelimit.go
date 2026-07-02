package middleware

import (
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// RateLimiter implements per-IP token bucket rate limiting.
// Token bucket: each IP gets a budget of tokens that refills at a steady rate.
// A burst allows a small spike above the steady rate (e.g. app startup loading many resources).
// This protects against brute-force attacks (login) and denial-of-service.
type RateLimiter struct {
	mu       sync.Mutex
	limiters map[string]*ipEntry
	rps      rate.Limit // steady refill rate (requests per second)
	burst    int        // max tokens accumulated at once
}

type ipEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

// NewRateLimiter creates a RateLimiter and starts a background cleanup goroutine
// to prevent memory leaks from accumulating millions of stale IP entries.
func NewRateLimiter(rps float64, burst int) *RateLimiter {
	rl := &RateLimiter{
		limiters: make(map[string]*ipEntry),
		rps:      rate.Limit(rps),
		burst:    burst,
	}
	go rl.cleanup()
	return rl
}

// Middleware returns a Chi-compatible middleware function.
func (rl *RateLimiter) Middleware() func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := extractIP(r)
			limiter := rl.getLimiter(ip)

			if !limiter.Allow() {
				slog.Warn("Rate limit exceeded", "ip", ip, "path", r.URL.Path)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				// Inline JSON — cannot import api package (would be a circular import)
				_ = json.NewEncoder(w).Encode(map[string]any{
					"success": false,
					"error": map[string]string{
						"code":    "RATE_LIMIT_EXCEEDED",
						"message": "Too many requests. Please slow down and try again.",
					},
				})
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func (rl *RateLimiter) getLimiter(ip string) *rate.Limiter {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	if entry, exists := rl.limiters[ip]; exists {
		entry.lastSeen = time.Now()
		return entry.limiter
	}

	l := rate.NewLimiter(rl.rps, rl.burst)
	rl.limiters[ip] = &ipEntry{limiter: l, lastSeen: time.Now()}
	return l
}

// cleanup removes IP entries that haven't been seen for 10 minutes.
// Runs every 5 minutes in the background for the application's lifetime.
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		for ip, entry := range rl.limiters {
			if time.Since(entry.lastSeen) > 10*time.Minute {
				delete(rl.limiters, ip)
			}
		}
		rl.mu.Unlock()
	}
}

// extractIP gets the real client IP, respecting X-Real-IP set by Nginx.
func extractIP(r *http.Request) string {
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return ip
	}
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return ip
}
