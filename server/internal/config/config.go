package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"

	"github.com/joho/godotenv"
)

// Config holds all validated, typed configuration for the server.
// Loaded once at startup and passed to every component that needs it.
// Fail-fast: all missing/invalid values are reported at startup, not mid-request.
type Config struct {
	// Server
	Port   string
	AppEnv string // "development" or "production"

	// Database — separate fields for easy rotation and debugging
	DBHost     string
	DBPort     string
	DBName     string
	DBUser     string
	DBPassword string
	DBSSLMode  string

	// JWT
	JWTSecret      string
	JWTExpiryHours int

	// Security & Middleware
	CORSAllowedOrigins []string // e.g. ["https://app.salio.co.ke"] or ["*"] for dev
	RateLimitRPS       float64  // max requests per second per IP (steady rate)
	RateLimitBurst     int      // burst allowance above RPS (e.g. app startup spike)
	RequestTimeoutSecs int      // per-request deadline in seconds
}

// DSN builds the PostgreSQL connection string from individual fields.
func (c *Config) DSN() string {
	return fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s password=%s sslmode=%s",
		c.DBHost, c.DBPort, c.DBName, c.DBUser, c.DBPassword, c.DBSSLMode,
	)
}

// IsProduction returns true when running in a production environment.
func (c *Config) IsProduction() bool {
	return c.AppEnv == "production"
}

// Load reads and validates all environment variables.
// Loads .env if present (local dev). In production, env vars come from the platform.
func Load() (*Config, error) {
	_ = godotenv.Load() // Silently ignore missing .env in production

	cfg := &Config{
		Port:   getEnv("PORT", "8080"),
		AppEnv: getEnv("APP_ENV", "development"),

		DBHost:     getEnv("DB_HOST", "127.0.0.1"),
		DBPort:     getEnv("DB_PORT", "5432"),
		DBName:     os.Getenv("DB_NAME"),
		DBUser:     os.Getenv("DB_USER"),
		DBPassword: os.Getenv("DB_PASSWORD"),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),

		JWTSecret: os.Getenv("JWT_SECRET"),

		CORSAllowedOrigins: parseCORSOrigins(getEnv("CORS_ALLOWED_ORIGINS", "*")),
		RateLimitBurst:     mustParseInt(getEnv("RATE_LIMIT_BURST", "20")),
		RequestTimeoutSecs: mustParseInt(getEnv("REQUEST_TIMEOUT_SECS", "30")),
	}

	// Collect ALL validation errors and report them together
	var errs []string
	if cfg.DBName == "" {
		errs = append(errs, "DB_NAME is required")
	}
	if cfg.DBUser == "" {
		errs = append(errs, "DB_USER is required")
	}
	if cfg.DBPassword == "" {
		errs = append(errs, "DB_PASSWORD is required")
	}
	if cfg.JWTSecret == "" {
		errs = append(errs, "JWT_SECRET is required")
	}
	if len(cfg.JWTSecret) < 32 {
		errs = append(errs, "JWT_SECRET must be at least 32 characters for security")
	}
	if len(errs) > 0 {
		msg := "Configuration errors:\n"
		for _, e := range errs {
			msg += "  - " + e + "\n"
		}
		return nil, errors.New(msg)
	}

	expiryHours, err := strconv.Atoi(getEnv("JWT_EXPIRY_HOURS", "720"))
	if err != nil || expiryHours <= 0 {
		return nil, fmt.Errorf("JWT_EXPIRY_HOURS must be a positive integer")
	}
	cfg.JWTExpiryHours = expiryHours

	rps, err := strconv.ParseFloat(getEnv("RATE_LIMIT_RPS", "10"), 64)
	if err != nil || rps <= 0 {
		return nil, fmt.Errorf("RATE_LIMIT_RPS must be a positive number")
	}
	cfg.RateLimitRPS = rps

	return cfg, nil
}

// parseCORSOrigins splits a comma-separated CORS_ALLOWED_ORIGINS value.
// Example: "https://app.salio.co.ke,https://admin.salio.co.ke"
func parseCORSOrigins(raw string) []string {
	parts := strings.Split(raw, ",")
	var origins []string
	for _, p := range parts {
		if trimmed := strings.TrimSpace(p); trimmed != "" {
			origins = append(origins, trimmed)
		}
	}
	if len(origins) == 0 {
		return []string{"*"}
	}
	return origins
}

// getEnv reads an env variable, falling back to a default if unset or empty.
func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists && value != "" {
		return value
	}
	return defaultValue
}

// mustParseInt parses a string integer, returning 0 on failure.
func mustParseInt(s string) int {
	n, _ := strconv.Atoi(s)
	return n
}
