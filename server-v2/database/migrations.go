// Package database embeds Salio's own migrations and runs them through Tusk's
// migrator.
//
// Salio's schema is its own. Tusk's built-in migrations create Tusk's identity
// tables — users with a NOT NULL email and username — which Salio users do not
// have; only the RBAC tables are shared, and those are restated in
// 00002_authz_and_console.sql. See that file for why they are copied rather than
// inherited.
package database

import (
	"database/sql"
	"embed"

	tuskdb "github.com/codetheuri/tusk/v2/database"
)

//go:embed migrations/*.sql
var migrations embed.FS

// Migrator returns a migrator over Salio's schema.
func Migrator() *tuskdb.Migrator {
	return tuskdb.NewMigrator(migrations, "migrations")
}

func Up(db *sql.DB) error     { return Migrator().Up(db) }
func Down(db *sql.DB) error   { return Migrator().Down(db) }
func Reset(db *sql.DB) error  { return Migrator().Reset(db) }
func Status(db *sql.DB) error { return Migrator().Status(db) }
