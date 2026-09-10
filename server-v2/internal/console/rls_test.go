package console_test

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/codetheuri/tusk/v2/pkg/testdb"
	"github.com/jackc/pgx/v5"
	_ "github.com/jackc/pgx/v5/stdlib"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	gormlogger "gorm.io/gorm/logger"

	"salio/server-v2/internal/console"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/testsupport"
)

// These tests exist because the console's cross-tenant reads pass through two
// separate gates, and only one of them fails loudly.
//
// tenant.Unscoped answers the Go layer; forget it and every query errors at
// once. Row-level security is the other, and forgetting it is silent: the
// development database connects as `root`, a superuser, which PostgreSQL exempts
// from every policy without saying so. A console with no RLS exemption therefore
// works perfectly on this machine and shows a dashboard of zeroes in production.
//
// The only way to test the layer at all is to connect as a role that is not
// exempt, which is what these do.

const (
	rlsRole     = "salio_console_rls_test"
	rlsPassword = "rls-test"
)

// connectUnprivileged returns a connection as a role with no special powers,
// pointed at the same database the harness prepared.
func connectUnprivileged(t *testing.T, owner *gorm.DB) *gorm.DB {
	t.Helper()

	stmts := []string{
		fmt.Sprintf(`DO $$ BEGIN
			IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') THEN
				CREATE ROLE %s LOGIN PASSWORD '%s';
			END IF;
		END $$`, rlsRole, rlsRole, rlsPassword),
		fmt.Sprintf(`GRANT USAGE ON SCHEMA public TO %s`, rlsRole),
		fmt.Sprintf(`GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO %s`, rlsRole),
		fmt.Sprintf(`GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO %s`, rlsRole),
	}
	for _, s := range stmts {
		if err := owner.Exec(s).Error; err != nil {
			if testdb.Required() {
				t.Fatalf("could not prepare the unprivileged test role: %v", err)
			}
			t.Skipf("cannot create a test role on this database, skipping: %v", err)
		}
	}
	t.Cleanup(func() {
		owner.Exec(fmt.Sprintf("REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %s", rlsRole))
		owner.Exec(fmt.Sprintf("REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %s", rlsRole))
		owner.Exec(fmt.Sprintf("REVOKE ALL ON SCHEMA public FROM %s", rlsRole))
		owner.Exec(fmt.Sprintf("DROP ROLE IF EXISTS %s", rlsRole))
	})

	// testsupport.DSN, not testdb.DSN: the latter resolves to Tusk's own test
	// database, so this connection would land somewhere Salio's tables do not
	// exist and report it as a missing relation.
	cfg, err := pgx.ParseConfig(testsupport.DSN())
	if err != nil {
		t.Fatalf("parsing the test DSN: %v", err)
	}
	sslmode := "disable"
	if cfg.TLSConfig != nil {
		sslmode = "require"
	}

	sqlDB, err := sql.Open("pgx", fmt.Sprintf("host=%s port=%d dbname=%s user=%s password=%s sslmode=%s",
		cfg.Host, cfg.Port, cfg.Database, rlsRole, rlsPassword, sslmode))
	if err != nil {
		t.Fatalf("opening as %s: %v", rlsRole, err)
	}
	t.Cleanup(func() { _ = sqlDB.Close() })

	db, err := gorm.Open(postgres.New(postgres.Config{Conn: sqlDB}), &gorm.Config{
		Logger: gormlogger.Default.LogMode(gormlogger.Silent),
	})
	if err != nil {
		t.Fatalf("gorm open as %s: %v", rlsRole, err)
	}
	if err := tenant.Register(db); err != nil {
		t.Fatalf("registering tenant callbacks: %v", err)
	}

	// Guards the guard: if this role turned out to be exempt too, every
	// assertion below would pass while proving nothing at all.
	if err := tenant.VerifyEnforcement(db); err != nil {
		t.Fatalf("the test role is exempt from RLS, so these tests would prove nothing: %v", err)
	}
	return db
}

func TestRLS_ConsoleReadsEveryBusinessAsANonSuperuser(t *testing.T) {
	f := newFixture(t)
	customer := f.newCustomer(t, f.alpha, "Mama Mboga")
	f.entry(t, f.alpha, customer, domain.TypeDebt, "1000.00")

	restricted := connectUnprivileged(t, f.db)
	svc := console.NewService(console.NewRepository(restricted))

	summary, businesses, err := svc.Dashboard(context.Background())
	if err != nil {
		t.Fatalf("dashboard as an unprivileged role: %v", err)
	}

	// Without migration 00004 this is where the console fails, and it fails by
	// reading zero rather than by erroring — which is why it survived every
	// review of the query itself.
	if summary.TotalUsers != 2 {
		t.Errorf("users = %d, want 2 — row-level security hid them", summary.TotalUsers)
	}
	if summary.TotalCustomers != 1 {
		t.Errorf("customers = %d, want 1 — row-level security hid them", summary.TotalCustomers)
	}
	if got, want := summary.TotalDebt.String(), "1000.00"; got != want {
		t.Errorf("debt = %s, want %s — row-level security hid the transactions", got, want)
	}
	if len(businesses) != 2 {
		t.Errorf("businesses = %d, want 2", len(businesses))
	}
}

func TestRLS_TheConsoleDoorIsReadOnly(t *testing.T) {
	f := newFixture(t)
	restricted := connectUnprivileged(t, f.db)

	// The same transaction shape console.Repository.readAll uses, doing the one
	// thing it must never be able to do. Migration 00004 relaxes USING, which
	// governs reads, and deliberately leaves WITH CHECK exactly as it was — so
	// a bug or an attacker holding a console session still cannot plant a row in
	// somebody's business.
	err := restricted.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}
		return tenant.Unscoped(tx).Create(&domain.Customer{
			ID: id.New(), BusinessID: f.beta, Name: "Planted", CreatedBy: id.New(),
		}).Error
	})
	if err == nil {
		t.Fatal("a write went through the platform-admin flag; the exemption must cover reads only")
	}

	// Asserted on the message, not merely on err != nil. A missing GRANT would
	// also fail this write, and a test that accepted any error would keep
	// passing after someone widened WITH CHECK — the exact change it exists to
	// catch.
	if !strings.Contains(err.Error(), "row-level security policy") {
		t.Fatalf("the write failed for the wrong reason: %v", err)
	}
}

// TestRLS_TheConsoleDoorCannotDelete covers the half of "read-only" that USING
// and WITH CHECK do not give you.
//
// A DELETE has no WITH CHECK — USING alone decides which rows may be removed —
// so relaxing USING for the console also handed it every business's rows to
// delete. Verified against PostgreSQL directly before the fix: with
// app.platform_admin set, `DELETE FROM customers` reported `DELETE 1` on another
// business's row. Migration 00005 adds a RESTRICTIVE delete policy, which is
// ANDed rather than ORed with the permissive one, so a delete now needs a real
// tenant regardless of the flag.
func TestRLS_TheConsoleDoorCannotDelete(t *testing.T) {
	f := newFixture(t)
	f.newCustomer(t, f.beta, "Beta's customer")

	restricted := connectUnprivileged(t, f.db)

	err := restricted.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}
		res := tenant.Unscoped(tx).Where("business_id = ?", f.beta).Delete(&domain.Customer{})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 0 {
			return fmt.Errorf("deleted %d rows through the console door", res.RowsAffected)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("the platform-admin flag permitted a cross-tenant delete: %v", err)
	}

	// And the row is still there, which is the thing that actually matters.
	var count int64
	if err := restricted.Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}
		return tenant.Unscoped(tx).Model(&domain.Customer{}).
			Where("business_id = ?", f.beta).Count(&count).Error
	}); err != nil {
		t.Fatalf("counting: %v", err)
	}
	if count != 1 {
		t.Fatalf("%d customers left for Beta, want 1", count)
	}
}

// TestRLS_ATenantCanStillDeleteItsOwn guards the fix from overshooting: the
// restrictive policy must refuse the console, not ordinary tenant-scoped work.
func TestRLS_ATenantCanStillDeleteItsOwn(t *testing.T) {
	f := newFixture(t)
	f.newCustomer(t, f.alpha, "Alpha's customer")

	restricted := connectUnprivileged(t, f.db)

	ctx := tenant.WithTenant(context.Background(), f.alpha)
	if err := tenant.Transaction(ctx, restricted, func(tx *gorm.DB) error {
		res := tx.Where("business_id = ?", f.alpha).Delete(&domain.Customer{})
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected != 1 {
			return fmt.Errorf("deleted %d rows, want 1", res.RowsAffected)
		}
		return nil
	}); err != nil {
		t.Fatalf("a tenant could not delete its own row: %v", err)
	}
}

func TestRLS_TheFlagDoesNotSurviveTheTransaction(t *testing.T) {
	f := newFixture(t)
	restricted := connectUnprivileged(t, f.db)

	// SET LOCAL, so the flag reverts on commit. A plain SET would persist on the
	// pooled connection and hand the next request — belonging to one business —
	// a view of every business on the platform.
	if err := restricted.Transaction(func(tx *gorm.DB) error {
		return tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error
	}); err != nil {
		t.Fatalf("opening the flag: %v", err)
	}

	var count int64
	if err := tenant.Unscoped(restricted).Model(&domain.User{}).Count(&count).Error; err != nil {
		t.Fatalf("counting users: %v", err)
	}
	if count != 0 {
		t.Fatalf("a later query outside the transaction saw %d users; the flag leaked onto the connection", count)
	}
}

func TestRLS_AnOrdinaryTenantStillSeesOnlyItsOwn(t *testing.T) {
	f := newFixture(t)
	f.newCustomer(t, f.alpha, "Alpha's customer")
	f.newCustomer(t, f.beta, "Beta's customer")

	restricted := connectUnprivileged(t, f.db)

	// The API path, unchanged by migration 00004: declare a tenant, see that
	// tenant. The whole point of relaxing USING with an OR was that a request
	// which does not set app.platform_admin behaves exactly as it did before.
	ctx := tenant.WithTenant(context.Background(), f.alpha)
	err := tenant.Transaction(ctx, restricted, func(tx *gorm.DB) error {
		var names []string
		if err := tx.Model(&domain.Customer{}).Pluck("name", &names).Error; err != nil {
			return err
		}
		if len(names) != 1 || names[0] != "Alpha's customer" {
			t.Fatalf("a tenant-scoped read saw %v, want only Alpha's customer", names)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("tenant-scoped read: %v", err)
	}
}
