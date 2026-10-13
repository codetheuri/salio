// Package testsupport wires Tusk's test harness to Salio's schema.
package testsupport

import (
	"context"
	"database/sql"
	"os"
	"strings"
	"sync"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/testdb"
	"gorm.io/gorm"

	"salio/server-v2/database"
)

// defaultDSN points at a throwaway database. Tests truncate every table, so the
// name must never be one holding data anyone cares about.
const defaultDSN = "host=127.0.0.1 port=5434 user=root password=root dbname=salio_v2_test sslmode=disable TimeZone=UTC"

// DSN reports the connection string these tests actually use.
//
// It exists because testdb.DSN() does not know about Options.DefaultDSN — it
// resolves TEST_DATABASE_URL or falls back to *Tusk's* own test database. A
// Salio test that needs to open a second connection of its own (the row-level
// security tests do, as an unprivileged role) must build it from this rather
// than from testdb.DSN, or it silently connects to the wrong database and reads
// "relation does not exist" as if it were a bug in the query.
func DSN() string {
	if dsn := strings.TrimSpace(os.Getenv("TEST_DATABASE_URL")); dsn != "" {
		return dsn
	}
	return defaultDSN
}

// Connect returns a database with Salio's migrations applied, every table empty,
// and Tusk's tenant callbacks registered — the same configuration production
// runs, so a test that passes here is evidence about production.
func Connect(t *testing.T) *gorm.DB {
	t.Helper()
	migrateOnce.Do(func() { migrateErr = migrateLocked() })
	if migrateErr != nil {
		t.Fatalf("migrating the test database: %v", migrateErr)
	}
	return testdb.ConnectWith(t, testdb.Options{
		Migrator:   database.Migrator(),
		DefaultDSN: defaultDSN,
	})
}

var (
	migrateOnce sync.Once
	migrateErr  error
)

// migrateLocked applies pending migrations while holding a database-wide lock.
//
// go test runs packages as separate processes against this one database, and
// testdb.ConnectWith migrates *before* taking its own lock. The first run after
// a new migration therefore raced: two packages applied it at once and the
// loser failed with "column already exists". Migrating here first, under a
// lock, leaves ConnectWith's own migration step nothing to do.
func migrateLocked() error {
	db, err := sql.Open("pgx", DSN())
	if err != nil {
		return err
	}
	defer db.Close()

	ctx := context.Background()
	conn, err := db.Conn(ctx) // the lock belongs to a session, so hold one connection
	if err != nil {
		return err
	}
	defer conn.Close()

	if _, err := conn.ExecContext(ctx, `SELECT pg_advisory_lock(hashtext('salio:test-migrations'))`); err != nil {
		return err
	}
	defer conn.ExecContext(ctx, `SELECT pg_advisory_unlock(hashtext('salio:test-migrations'))`) //nolint:errcheck

	return database.Up(db)
}
