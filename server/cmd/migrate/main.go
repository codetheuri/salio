package main

// This is Salio's own migration runner.
// It only imports the ONE driver we need (postgres) — not the 20+ drivers
// that come with the universal golang-migrate CLI tool.
//
// Run with: go run ./cmd/migrate [up|down|version|create]
// Or via Makefile: make migrate-up

import (
	"flag"
	"fmt"
	"log/slog"
	"os"

	"github.com/golang-migrate/migrate/v4"
	// Only the two imports we actually need — postgres driver + file source
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/joho/godotenv"
)

func main() {
	// Load .env for local development (silently ignored in production)
	_ = godotenv.Load()

	// Build DSN from individual env vars (same as config.go)
	dsn := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=%s",
		mustGetEnv("DB_USER"),
		mustGetEnv("DB_PASSWORD"),
		getEnv("DB_HOST", "127.0.0.1"),
		getEnv("DB_PORT", "5432"),
		mustGetEnv("DB_NAME"),
		getEnv("DB_SSLMODE", "disable"),
	)

	migrationsPath := "file://migrations"

	// Parse the subcommand: up, down, version, steps
	flag.Parse()
	command := flag.Arg(0)

	m, err := migrate.New(migrationsPath, dsn)
	if err != nil {
		slog.Error("Failed to initialise migrations", "error", err)
		os.Exit(1)
	}
	defer m.Close()

	switch command {
	case "up":
		slog.Info("Running all pending migrations...")
		if err := m.Up(); err != nil && err != migrate.ErrNoChange {
			slog.Error("Migration UP failed", "error", err)
			os.Exit(1)
		}
		version, _, _ := m.Version()
		slog.Info("Migrations applied successfully", "version", version)

	case "down":
		slog.Info("Rolling back 1 migration...")
		if err := m.Steps(-1); err != nil {
			slog.Error("Migration DOWN failed", "error", err)
			os.Exit(1)
		}
		version, _, _ := m.Version()
		slog.Info("Rollback complete", "version", version)

	case "version":
		version, dirty, err := m.Version()
		if err != nil && err != migrate.ErrNilVersion {
			slog.Error("Failed to get version", "error", err)
			os.Exit(1)
		}
		slog.Info("Current migration version", "version", version, "dirty", dirty)

	default:
		fmt.Println("Salio Migration Runner")
		fmt.Println("Usage: go run ./cmd/migrate [command]")
		fmt.Println("")
		fmt.Println("Commands:")
		fmt.Println("  up       Apply all pending migrations")
		fmt.Println("  down     Roll back the last migration")
		fmt.Println("  version  Show current migration version")
		os.Exit(0)
	}
}

func mustGetEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		slog.Error("Required environment variable is not set", "key", key)
		os.Exit(1)
	}
	return v
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}
