package dataimport_test

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	_ "github.com/jackc/pgx/v5/stdlib"
	"gorm.io/gorm"

	"salio/server-v2/internal/dataimport"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/syncengine"
	"salio/server-v2/internal/testsupport"
)

// v1SourceDB is the throwaway database the v1 schema is built in.
//
// A separate database rather than a separate schema: the two versions use the
// same table names, which is the whole reason this tool exists.
const v1SourceDB = "salio_v1_source_test"

// v1MigrationsDir is read from the sibling v1 server rather than copied here.
//
// A copy would drift, and a test that imports from a schema slightly unlike
// production is worse than no test — it would report a clean migration of a
// database that does not exist. If v1 adds a column, this test starts exercising
// it the same day.
const v1MigrationsDir = "../../../server/migrations"

// openV1Source builds an empty v1 database and returns a connection to it.
func openV1Source(t *testing.T) *sql.DB {
	t.Helper()

	cfg, err := pgx.ParseConfig(testsupport.DSN())
	if err != nil {
		t.Fatalf("parsing the test DSN: %v", err)
	}
	sslmode := "disable"
	if cfg.TLSConfig != nil {
		sslmode = "require"
	}
	dsnFor := func(dbname string) string {
		return fmt.Sprintf("host=%s port=%d dbname=%s user=%s password=%s sslmode=%s",
			cfg.Host, cfg.Port, dbname, cfg.User, cfg.Password, sslmode)
	}

	admin, err := sql.Open("pgx", dsnFor("postgres"))
	if err != nil {
		t.Fatalf("connecting to postgres: %v", err)
	}
	defer admin.Close()
	// CREATE DATABASE cannot run inside a transaction and errors if it exists,
	// so the error is inspected rather than required to be nil.
	if _, err := admin.Exec("CREATE DATABASE " + v1SourceDB); err != nil {
		if _, probe := admin.Query("SELECT 1 FROM pg_database WHERE datname = $1", v1SourceDB); probe != nil {
			t.Skipf("cannot create the v1 source database: %v", err)
		}
	}

	src, err := sql.Open("pgx", dsnFor(v1SourceDB))
	if err != nil {
		t.Fatalf("connecting to %s: %v", v1SourceDB, err)
	}
	t.Cleanup(func() { _ = src.Close() })

	// A clean slate, since the database survives between runs.
	if _, err := src.Exec(`DROP SCHEMA public CASCADE; CREATE SCHEMA public`); err != nil {
		t.Fatalf("resetting the v1 schema: %v", err)
	}

	files, err := filepath.Glob(filepath.Join(v1MigrationsDir, "*.up.sql"))
	if err != nil || len(files) == 0 {
		t.Fatalf("no v1 migrations found at %s — this test imports from the real v1 schema, "+
			"not a copy, so it cannot run without them (err: %v)", v1MigrationsDir, err)
	}
	sort.Strings(files)
	for _, f := range files {
		body, err := os.ReadFile(f)
		if err != nil {
			t.Fatalf("reading %s: %v", f, err)
		}
		if _, err := src.Exec(string(body)); err != nil {
			t.Fatalf("applying %s: %v", filepath.Base(f), err)
		}
	}
	return src
}

// v1Fixture is a plausible small platform in the v1 schema: two shops, staff who
// have come and gone, walk-in customers with no phone, voided entries, and
// amounts whose cents matter.
type v1Fixture struct {
	src *sql.DB

	alphaID, betaID       uuid.UUID
	alphaOwner, alphaHelp uuid.UUID
	betaOwner             uuid.UUID

	// mamaMboga carries the balance the whole migration is judged on.
	mamaMboga, walkIn, removed uuid.UUID
	juma                       uuid.UUID
}

func seedV1(t *testing.T, src *sql.DB) *v1Fixture {
	t.Helper()
	f := &v1Fixture{src: src}
	ctx := context.Background()

	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := src.ExecContext(ctx, q, args...); err != nil {
			t.Fatalf("seeding v1 (%.60s): %v", q, err)
		}
	}

	f.alphaID, f.betaID = id.New(), id.New()
	exec(`INSERT INTO businesses (id, name, type) VALUES ($1,'Alpha Agrovet','agrovet'), ($2,'Beta Kiosk',NULL)`,
		f.alphaID, f.betaID)

	f.alphaOwner, f.alphaHelp, f.betaOwner = id.New(), id.New(), id.New()
	exec(`INSERT INTO users (id, business_id, name, phone, password_hash, role, is_active) VALUES
		($1,$2,'Wanjiku','0712000001','hash-a','owner',TRUE),
		($3,$2,'Kimani','0712000002','hash-b','staff',FALSE),
		($4,$5,'Otieno','0712000003','hash-c','owner',TRUE)`,
		f.alphaOwner, f.alphaID, f.alphaHelp, f.betaOwner, f.betaID)

	f.mamaMboga, f.walkIn, f.removed, f.juma = id.New(), id.New(), id.New(), id.New()
	exec(`INSERT INTO customers (id, business_id, name, phone, notes, created_by, is_deleted) VALUES
		($1,$2,'Mama Mboga','0722111222','Pays Fridays',$3,FALSE),
		($4,$2,'Walk-in',NULL,NULL,$3,FALSE),
		($5,$2,'Left the area','0722999999',NULL,$3,TRUE),
		($6,$7,'Juma','0733000111',NULL,$8,FALSE)`,
		f.mamaMboga, f.alphaID, f.alphaOwner, f.walkIn, f.removed, f.juma, f.betaID, f.betaOwner)

	// A ledger with cents that do not survive a float round trip, a payment, and
	// a voided entry that must stay voided and must not count.
	exec(`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, is_deleted) VALUES
		($1,$2,$3,$4,'debt',   1500.50,'2026-08-01',FALSE),
		($5,$2,$3,$4,'debt',      0.10,'2026-08-02',FALSE),
		($6,$2,$3,$4,'payment',  300.25,'2026-08-03',FALSE),
		($7,$2,$3,$4,'debt',    999.99,'2026-08-04',TRUE),
		($8,$2,$9,$4,'debt',     45.00,'2026-08-05',FALSE)`,
		id.New(), f.alphaID, f.mamaMboga, f.alphaOwner,
		id.New(), id.New(), id.New(), id.New(), f.walkIn)

	// A tombstoned customer keeps her history: dropping either would change what
	// a device that has not synced yet believes.
	exec(`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, is_deleted) VALUES
		($1,$2,$3,$4,'debt',200.00,'2026-07-01',FALSE)`,
		id.New(), f.alphaID, f.removed, f.alphaOwner)

	exec(`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, is_deleted) VALUES
		($1,$2,$3,$4,'debt',9999.00,'2026-08-06',FALSE)`,
		id.New(), f.betaID, f.juma, f.betaOwner)

	// Three invites: one live, one already used, one expired. Only the live one
	// is worth carrying — someone was sent that code and will type it in later.
	exec(`INSERT INTO business_invites (business_id, code, expires_at, used_at) VALUES
		($1,'LIVE01',NOW() + INTERVAL '12 hours',NULL),
		($1,'USED01',NOW() + INTERVAL '12 hours',NOW()),
		($1,'GONE01',NOW() - INTERVAL '1 hour',NULL)`, f.alphaID)

	exec(`INSERT INTO super_admins (id, name, email, password_hash) VALUES ($1,'Operator','ops@salio.co.ke','hash-admin')`, id.New())

	return f
}

// runImport does what cmd/importv1 does, against test databases.
func runImport(t *testing.T, src *sql.DB, target *gorm.DB) *dataimport.Report {
	t.Helper()
	ctx := context.Background()

	if err := rbac.Seed(ctx, target); err != nil {
		t.Fatalf("seeding permissions: %v", err)
	}
	report, err := dataimport.NewImporter(target).
		Run(ctx, dataimport.NewSource(src), dataimport.Options{})
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	return report
}

// TestImport_EveryCustomerBalanceIsIdenticalAfterwards is the check the plan
// names as the one that decides whether cutover may happen.
//
// Row counts can match while the ledger is wrong: a transaction imported with
// the wrong sign, or attached to the wrong customer, leaves every count intact
// and changes what a real person is told they owe. Only the balances catch that.
func TestImport_EveryCustomerBalanceIsIdenticalAfterwards(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)

	runImport(t, src, target)

	discrepancies, err := dataimport.Verify(context.Background(), dataimport.NewSource(src), target)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if len(discrepancies) != 0 {
		for _, d := range discrepancies {
			t.Errorf("discrepancy: %s", d)
		}
		t.FailNow()
	}

	// Stated explicitly as well as compared, so the test says what the right
	// answer is rather than only that both sides agree.
	// 1500.50 + 0.10 - 300.25 = 1200.35, and the 999.99 void does not count.
	var balance string
	if err := target.Raw(`
		SELECT COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)::text
		FROM transactions WHERE customer_id = ? AND is_deleted = false`, f.mamaMboga).
		Scan(&balance).Error; err != nil {
		t.Fatalf("reading the balance: %v", err)
	}
	if balance != "1200.35" {
		t.Fatalf("Mama Mboga's balance = %s, want 1200.35", balance)
	}
}

// TestVerify_ActuallyReportsABalanceThatDoesNotMatch guards the guard.
//
// A verifier that cannot fail is worse than none: it turns "cutover is safe" into
// a sentence with no content. One entry's amount is altered after the import, and
// the check must notice.
func TestVerify_ActuallyReportsABalanceThatDoesNotMatch(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// A single cent, on one entry, in one shop — the smallest wrong answer this
	// tool could produce.
	if err := target.Exec(`
		UPDATE transactions SET amount = amount + 0.01
		WHERE customer_id = ? AND is_deleted = false AND amount = 1500.50`, f.mamaMboga).Error; err != nil {
		t.Fatalf("corrupting the target: %v", err)
	}

	discrepancies, err := dataimport.Verify(context.Background(), dataimport.NewSource(src), target)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if len(discrepancies) != 1 || discrepancies[0].Kind != dataimport.KindBalance {
		t.Fatalf("discrepancies = %v, want exactly one balance mismatch", discrepancies)
	}
}

func TestVerify_ReportsAMissingCustomer(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// Tombstoned rather than deleted, because a foreign key holds the row: from
	// the verifier's side an active customer has vanished either way.
	if err := target.Exec(`UPDATE customers SET is_deleted = true WHERE id = ?`, f.walkIn).Error; err != nil {
		t.Fatalf("hiding a customer: %v", err)
	}

	discrepancies, err := dataimport.Verify(context.Background(), dataimport.NewSource(src), target)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}

	var missing int
	for _, d := range discrepancies {
		if d.Kind == dataimport.KindMissing {
			missing++
		}
	}
	if missing != 1 {
		t.Fatalf("discrepancies = %v, want one missing_customer", discrepancies)
	}
}

func TestImport_PreservesTombstonesRatherThanDroppingThem(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// A tombstone is what tells a device that has not synced that the row is
	// gone. Dropping them at cutover would have every phone push its deleted
	// customers straight back in.
	var removed domain.Customer
	if err := tenant.Unscoped(target).First(&removed, "id = ?", f.removed).Error; err != nil {
		t.Fatalf("the deleted customer was not imported: %v", err)
	}
	if !removed.IsDeleted {
		t.Error("a tombstoned customer came across as active")
	}

	var voided int64
	tenant.Unscoped(target).Model(&domain.Transaction{}).Where("is_deleted").Count(&voided)
	if voided != 1 {
		t.Errorf("%d voided transactions, want 1", voided)
	}
}

func TestImport_DerivesRBACRolesFromTheV1RoleColumn(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// v1 has no RBAC tables at all, so these rows exist only because the import
	// ran them through rbac.AssignRole — the same call the running server uses,
	// rather than a second definition of what a role means.
	for _, tc := range []struct {
		name   string
		userID uuid.UUID
		role   string
	}{
		{"the owner", f.alphaOwner, "owner"},
		{"the deactivated staff member", f.alphaHelp, "staff"},
		{"the other shop's owner", f.betaOwner, "owner"},
	} {
		var count int64
		if err := target.Model(&authz.UserRole{}).
			Joins("JOIN roles ON roles.id = user_roles.role_id").
			Where("user_roles.user_id = ? AND roles.name = ?", tc.userID, tc.role).
			Count(&count).Error; err != nil {
			t.Fatalf("checking roles: %v", err)
		}
		if count != 1 {
			t.Errorf("%s has %d %q grants, want 1", tc.name, count, tc.role)
		}
	}

	// Deactivated staff keep their account and their role. The row cannot be
	// deleted — transactions reference it — and is_active is what withdraws
	// access.
	var kimani domain.User
	if err := tenant.Unscoped(target).First(&kimani, "id = ?", f.alphaHelp).Error; err != nil {
		t.Fatalf("loading the deactivated user: %v", err)
	}
	if kimani.IsActive {
		t.Error("a deactivated staff member came across as active")
	}
}

func TestImport_CarriesOnlyInvitesSomeoneCouldStillRedeem(t *testing.T) {
	src := openV1Source(t)
	seedV1(t, src)
	target := testsupport.Connect(t)
	report := runImport(t, src, target)

	if report.Invites != 1 {
		t.Fatalf("imported %d invites, want 1 — used and expired codes are noise", report.Invites)
	}

	var codes []string
	if err := tenant.Unscoped(target).Model(&domain.BusinessInvite{}).Pluck("code", &codes).Error; err != nil {
		t.Fatalf("reading invites: %v", err)
	}
	if len(codes) != 1 || codes[0] != "LIVE01" {
		t.Fatalf("codes = %v, want [LIVE01]", codes)
	}

	// v1's invite id is a SERIAL, so the imported row must have been given a new
	// UUID rather than carrying anything across.
	var invite domain.BusinessInvite
	if err := tenant.Unscoped(target).First(&invite, "code = ?", "LIVE01").Error; err != nil {
		t.Fatalf("loading the invite: %v", err)
	}
	if invite.ID == uuid.Nil {
		t.Error("the imported invite has no identifier")
	}
}

func TestImport_KeepsTheTwoBusinessesApart(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// The import declares a tenant per business, which is what makes it
	// structurally unable to write one shop's rows into another's. Worth
	// asserting on the outcome and not only on the mechanism.
	for _, tc := range []struct {
		business uuid.UUID
		want     int64
	}{
		{f.alphaID, 3},
		{f.betaID, 1},
	} {
		var count int64
		tenant.Unscoped(target).Model(&domain.Customer{}).
			Where("business_id = ?", tc.business).Count(&count)
		if count != tc.want {
			t.Errorf("business %s has %d customers, want %d", tc.business, count, tc.want)
		}
	}

	var crossed int64
	tenant.Unscoped(target).Model(&domain.Transaction{}).
		Joins("JOIN customers ON customers.id = transactions.customer_id").
		Where("customers.business_id <> transactions.business_id").Count(&crossed)
	if crossed != 0 {
		t.Fatalf("%d transactions point at another business's customer", crossed)
	}
}

// TestImport_MakesEveryExistingCursorResyncOnce covers the cutover hazard that
// has nothing to do with row data.
//
// A phone holding v1 cursor 40,000, pointed at a v2 database whose sequence has
// reached 900, asks for changes above 40,000 and is told — correctly, and
// forever — that there are none. Its ledger silently stops updating. The import
// advances the sequence past anything v1 issued and sets the tombstone horizon to
// match, so every existing cursor trips the resync it already knows how to ask
// for.
func TestImport_MakesEveryExistingCursorResyncOnce(t *testing.T) {
	src := openV1Source(t)
	f := seedV1(t, src)
	target := testsupport.Connect(t)
	report := runImport(t, src, target)

	v1Seq, err := dataimport.NewSource(src).HighestChangeSeq(context.Background())
	if err != nil {
		t.Fatalf("reading the v1 sequence: %v", err)
	}
	if report.Sealed <= v1Seq {
		t.Fatalf("horizon %d is not above v1's highest cursor %d", report.Sealed, v1Seq)
	}

	svc := syncengine.NewService(syncengine.NewRepository(target))
	ctx := tenant.WithTenant(context.Background(), f.alphaID)

	// A device arriving with a cursor from v1 — including one far higher than
	// anything this database has issued.
	for _, cursor := range []int64{1, v1Seq, report.Sealed} {
		view, err := svc.Pull(ctx, cursor, 500)
		if err != nil {
			t.Fatalf("pull at cursor %d: %v", cursor, err)
		}
		if !view.ResyncRequired {
			t.Errorf("a device at cursor %d was not told to resync", cursor)
		}
		if view.NextCursor != 0 {
			t.Errorf("cursor %d: next_cursor = %d, want 0", cursor, view.NextCursor)
		}
	}

	// A first sync — cursor 0 — must still work, and must deliver the shop's book.
	fresh, err := svc.Pull(ctx, 0, 500)
	if err != nil {
		t.Fatalf("first pull: %v", err)
	}
	if fresh.ResyncRequired {
		t.Fatal("a device starting from zero was told to resync, which it is already doing")
	}
	if len(fresh.Customers) != 3 {
		t.Errorf("a fresh sync received %d customers, want 3", len(fresh.Customers))
	}

	// And a write made after cutover has to land above the horizon, or it would
	// be unreachable by the cursor the resync just handed out.
	newID := id.New()
	if err := tenant.Unscoped(target).Create(&domain.Customer{
		ID: newID, BusinessID: f.alphaID, Name: "Signed up after cutover", CreatedBy: f.alphaOwner,
	}).Error; err != nil {
		t.Fatalf("creating a post-cutover customer: %v", err)
	}
	after, err := svc.Pull(ctx, fresh.NextCursor, 500)
	if err != nil {
		t.Fatalf("pull after cutover: %v", err)
	}
	if len(after.Customers) != 1 || after.Customers[0].ID != newID {
		t.Fatalf("a post-cutover write was not delivered: %+v", after.Customers)
	}
}

func TestImport_RefusesToRunTwiceUnlessTold(t *testing.T) {
	src := openV1Source(t)
	seedV1(t, src)
	target := testsupport.Connect(t)
	runImport(t, src, target)

	// Running the import twice is the likeliest operator mistake, and it would
	// not fail cleanly: every insert would collide on a primary key partway
	// through, leaving the target half-written.
	_, err := dataimport.NewImporter(target).
		Run(context.Background(), dataimport.NewSource(src), dataimport.Options{})
	if err == nil {
		t.Fatal("a second import was allowed into a populated target")
	}
	if !errorContains(err, "already contains businesses") {
		t.Fatalf("error = %v, want it to name the reason", err)
	}
}

func TestImport_CopiesAnEmptyPlatformWithoutComplaint(t *testing.T) {
	src := openV1Source(t)
	target := testsupport.Connect(t)

	// A brand-new v1 install, or a rehearsal against an empty snapshot. The
	// rehearsal is the point: an operator should be able to practise the cutover.
	report := runImport(t, src, target)
	if report.Businesses != 0 || report.Customers != 0 {
		t.Fatalf("report = %+v, want zeroes", report)
	}

	discrepancies, err := dataimport.Verify(context.Background(), dataimport.NewSource(src), target)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if len(discrepancies) != 0 {
		t.Fatalf("discrepancies on an empty import: %v", discrepancies)
	}
}

func TestImport_LeavesTheV1DatabaseUntouched(t *testing.T) {
	src := openV1Source(t)
	seedV1(t, src)
	target := testsupport.Connect(t)

	before := snapshotV1(t, src)
	runImport(t, src, target)
	after := snapshotV1(t, src)

	// The v1 server keeps serving real shops throughout the cutover, and stays
	// available read-only for a rollback window afterwards. A migration tool that
	// wrote to it would remove the ability to roll back at all.
	if before != after {
		t.Fatalf("the v1 database changed during the import:\n before %s\n after  %s", before, after)
	}
}

func snapshotV1(t *testing.T, src *sql.DB) string {
	t.Helper()
	var out string
	err := src.QueryRow(`
		SELECT (SELECT COUNT(*) FROM businesses) || '/' ||
		       (SELECT COUNT(*) FROM users) || '/' ||
		       (SELECT COUNT(*) FROM customers) || '/' ||
		       (SELECT COUNT(*) FROM transactions) || '/' ||
		       (SELECT COUNT(*) FROM business_invites) || '/' ||
		       (SELECT COUNT(*) FROM super_admins) || '/' ||
		       COALESCE((SELECT SUM(amount)::text FROM transactions), '0')
	`).Scan(&out)
	if err != nil {
		t.Fatalf("snapshotting v1: %v", err)
	}
	return out
}

func errorContains(err error, want string) bool {
	return err != nil && len(want) > 0 && contains(err.Error(), want)
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}
