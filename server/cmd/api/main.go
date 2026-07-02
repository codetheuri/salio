package main

// main.go is intentionally minimal.
// Its only job is to: load config → boot the app → handle fatal startup errors.
// All wiring, routing, and lifecycle management lives in internal/app/app.go.

import (
	"log/slog"
	"os"

	"salio/server/internal/app"
	"salio/server/internal/config"
)

func main() {
	// 1. Load and validate all configuration from environment variables
	cfg, err := config.Load()
	if err != nil {
		slog.Error("Startup failed: configuration error", "error", err)
		os.Exit(1)
	}

	// 2. Configure structured logging based on environment
	// Development: human-readable text  |  Production: JSON for log aggregators
	var logHandler slog.Handler
	if cfg.IsProduction() {
		logHandler = slog.NewJSONHandler(os.Stdout, nil)
	} else {
		logHandler = slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelDebug})
	}
	slog.SetDefault(slog.New(logHandler))

	slog.Info("Starting Salio API", "env", cfg.AppEnv, "port", cfg.Port)

	// 3. Boot the application (connects to DB, wires all components)
	application, err := app.New(cfg)
	if err != nil {
		slog.Error("Startup failed: application error", "error", err)
		os.Exit(1)
	}

	// 4. Run — blocks until SIGINT or SIGTERM, then shuts down gracefully
	if err := application.Run(); err != nil {
		slog.Error("Server exited with error", "error", err)
		os.Exit(1)
	}
}
