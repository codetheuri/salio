// Command api is the Salio v2 HTTP server. Assembly lives in internal/server;
// this only reads the environment and runs it.
package main

import (
	"os"
	"strconv"

	"github.com/codetheuri/tusk/v2/config"
	"github.com/codetheuri/tusk/v2/pkg/logger"

	"salio/server-v2/internal/server"
)

func main() {
	log := logger.NewTextLogger("info")

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatal("Failed to load configuration", err)
	}
	log = logger.New(cfg.IsProduction(), cfg.LOG_LEVEL)

	application, err := server.Build(cfg, log, server.Options{
		// Production defaults: migrations run separately as the owner role,
		// and the API refuses a database role that bypasses row-level
		// security. Development defaults to the opposite of both.
		MigrateOnBoot: envBool("MIGRATE_ON_BOOT", !cfg.IsProduction()),
		RequireRLS:    envBool("REQUIRE_RLS", cfg.IsProduction()),
	})
	if err != nil {
		log.Fatal("Server setup failed", err)
	}

	if err := application.Run(); err != nil {
		log.Fatal("Server exited with error", err)
	}
}

func envBool(key string, fallback bool) bool {
	if v, err := strconv.ParseBool(os.Getenv(key)); err == nil {
		return v
	}
	return fallback
}
