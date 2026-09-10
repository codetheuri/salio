// Command migrate applies Salio's database migrations.
package main

import (
	"database/sql"
	"fmt"
	"log"
	"os"

	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/codetheuri/tusk/v2/config"

	"salio/server-v2/database"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: migrate <up|down|reset|status>")
		os.Exit(1)
	}

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatalf("failed to load configuration: %v", err)
	}

	db, err := sql.Open("pgx", cfg.DbURL)
	if err != nil {
		log.Fatalf("failed to open the database: %v", err)
	}
	defer db.Close()

	// sql.Open does not connect; without this an unreachable database surfaces
	// as a confusing migration error rather than a clear one.
	if err := db.Ping(); err != nil {
		log.Fatalf("database is unreachable: %v", err)
	}

	switch cmd := os.Args[1]; cmd {
	case "up":
		err = database.Up(db)
	case "down":
		err = database.Down(db)
	case "reset":
		err = database.Reset(db)
	case "status":
		err = database.Status(db)
	default:
		log.Fatalf("unknown command %q: expected up, down, reset or status", cmd)
	}

	if err != nil {
		log.Fatalf("migration failed: %v", err)
	}
	log.Printf("migration %q completed successfully.", os.Args[1])
}
