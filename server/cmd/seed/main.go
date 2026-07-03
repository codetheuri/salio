// cmd/seed/main.go
// One-time setup: creates the first super admin account for the Salio Console.
//
// Usage:
//   go run ./cmd/seed -name="Your Name" -email="you@example.com" -password="yourpassword"
//
// Run this ONCE after first deployment. Store the credentials securely.

package main

import (
	"context"
	"flag"
	"fmt"
	"log/slog"
	"os"

	"salio/server/internal/config"
	"salio/server/internal/db"
	"salio/server/internal/repository"
)

func main() {
	name     := flag.String("name", "", "Super admin full name (required)")
	email    := flag.String("email", "", "Super admin email address (required)")
	password := flag.String("password", "", "Super admin password, min 8 chars (required)")
	flag.Parse()

	// Validate flags
	if *name == "" || *email == "" || *password == "" {
		fmt.Println("Usage: go run ./cmd/seed -name='Your Name' -email='you@example.com' -password='yourpassword'")
		os.Exit(1)
	}
	if len(*password) < 4 {
		fmt.Println("Error: password must be at least 4 characters.")
		os.Exit(1)
	}

	// Load config (reads .env)
	cfg, err := config.Load()
	if err != nil {
		slog.Error("Config error", "error", err)
		os.Exit(1)
	}

	// Connect to DB
	pool, err := db.Connect(cfg.DSN())
	if err != nil {
		slog.Error("Database connection failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	// Create the super admin
	repo := repository.NewConsoleRepository(pool)
	admin, err := repo.CreateSuperAdmin(context.Background(), *name, *email, *password)
	if err != nil {
		slog.Error("Failed to create super admin", "error", err)
		os.Exit(1)
	}

	fmt.Println("✅ Super admin created successfully!")
	fmt.Printf("   Name:  %s\n", admin.Name)
	fmt.Printf("   Email: %s\n", admin.Email)
	fmt.Printf("   ID:    %s\n", admin.ID)
	fmt.Println()
	fmt.Println("You can now log in at: http://localhost:8080/console")
}
