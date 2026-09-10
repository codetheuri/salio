// Package testsupport wires Tusk's test harness to Salio's schema.
package testsupport

import (
	"os"
	"strings"
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
	return testdb.ConnectWith(t, testdb.Options{
		Migrator:   database.Migrator(),
		DefaultDSN: defaultDSN,
	})
}
