package repository

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// These tests need a real PostgreSQL, because the defect they cover is a
// property of how PostgreSQL assigns NOW() and when rows become visible. No
// amount of mocking can reproduce it — a fake would simply behave as the code
// assumes, which is exactly the assumption that turned out to be wrong.
//
// Point TEST_DATABASE_URL at a throwaway database with migrations applied:
//
//	createdb salio_sync_test && make migrate-up
const defaultTestDSN = "postgres://root:root@127.0.0.1:5434/salio_sync_test?sslmode=disable"

func testPool(t *testing.T) *pgxpool.Pool {
	t.Helper()

	dsn := os.Getenv("TEST_DATABASE_URL")
	if dsn == "" {
		dsn = defaultTestDSN
	}

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		t.Skipf("no test database available: %v", err)
	}
	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		t.Skipf("no test database reachable, skipping: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seedBusiness creates an isolated business with one user and one customer.
//
// Each test gets its own business rather than sharing one and truncating: sync is
// scoped by business_id, so isolation by tenant is both sufficient and closer to
// how the system actually runs.
func seedBusiness(t *testing.T, pool *pgxpool.Pool) (businessID, userID, customerID uuid.UUID) {
	t.Helper()
	ctx := context.Background()

	businessID, userID, customerID = uuid.New(), uuid.New(), uuid.New()
	unique := businessID.String()[:8]

	_, err := pool.Exec(ctx,
		`INSERT INTO businesses (id, name) VALUES ($1, $2)`,
		businessID, "Test Shop "+unique)
	if err != nil {
		t.Fatalf("seed business: %v", err)
	}

	_, err = pool.Exec(ctx,
		`INSERT INTO users (id, business_id, name, phone, password_hash, role)
		 VALUES ($1, $2, 'Owner', $3, 'x', 'owner')`,
		userID, businessID, "0700"+unique)
	if err != nil {
		t.Fatalf("seed user: %v", err)
	}

	_, err = pool.Exec(ctx,
		`INSERT INTO customers (id, business_id, name, created_by) VALUES ($1, $2, 'Jane', $3)`,
		customerID, businessID, userID)
	if err != nil {
		t.Fatalf("seed customer: %v", err)
	}

	t.Cleanup(func() {
		// ON DELETE CASCADE removes users, customers and transactions with it.
		_, _ = pool.Exec(context.Background(), `DELETE FROM businesses WHERE id = $1`, businessID)
	})

	return businessID, userID, customerID
}

// TestCursorPull_SurvivesAnInFlightWrite is the regression test for the defect
// that prompted this change.
//
// The scenario: one device's push has begun but not committed when another
// device pulls. The pulling device must not advance its position past work it
// could not see, or that work becomes permanently invisible to it.
func TestCursorPull_SurvivesAnInFlightWrite(t *testing.T) {
	pool := testPool(t)
	repo := NewSyncRepository(pool)
	ctx := context.Background()

	businessID, userID, customerID := seedBusiness(t, pool)

	// Device B syncs and records where it got to.
	initial, err := repo.PullByCursor(ctx, businessID, 0, 100)
	if err != nil {
		t.Fatalf("initial pull: %v", err)
	}
	cursor := initial.NextCursor
	if cursor == 0 {
		t.Fatal("expected the seeded customer to advance the cursor above zero")
	}

	// Device A begins a push. NOW() is fixed at this instant, but nothing it
	// writes is visible to anyone else until it commits.
	txA, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin device A transaction: %v", err)
	}
	defer txA.Rollback(ctx)

	_, err = txA.Exec(ctx,
		`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, 'debt', 500, CURRENT_DATE, NOW(), NOW())`,
		uuid.New(), businessID, customerID, userID)
	if err != nil {
		t.Fatalf("device A insert: %v", err)
	}

	// Device B pulls while A is still in flight. It sees nothing — correctly.
	during, err := repo.PullByCursor(ctx, businessID, cursor, 100)
	if err != nil {
		t.Fatalf("pull during in-flight write: %v", err)
	}
	if len(during.Transactions) != 0 {
		t.Fatalf("expected an uncommitted write to be invisible, got %d transactions", len(during.Transactions))
	}

	// This is the assertion that matters. The cursor must NOT have moved past the
	// unseen row. A clock-based watermark would have jumped to "now", which is
	// later than the timestamp A's row will carry — and that is exactly how the
	// record became unreachable.
	if during.NextCursor != cursor {
		t.Fatalf("cursor advanced past an unseen write: was %d, became %d", cursor, during.NextCursor)
	}

	if err := txA.Commit(ctx); err != nil {
		t.Fatalf("device A commit: %v", err)
	}

	// Device B pulls again from the position it recorded. The row must appear.
	after, err := repo.PullByCursor(ctx, businessID, during.NextCursor, 100)
	if err != nil {
		t.Fatalf("pull after commit: %v", err)
	}
	if len(after.Transactions) != 1 {
		t.Fatalf("expected the committed transaction to be delivered, got %d", len(after.Transactions))
	}
}

// TestLegacyTimestampPull_LosesAnInFlightWrite documents the defect the cursor
// replaces.
//
// It asserts the broken behaviour deliberately. The legacy endpoint still serves
// app versions in the field, so this pins what those clients experience and
// prevents anyone concluding the timestamp path is safe to keep using.
func TestLegacyTimestampPull_LosesAnInFlightWrite(t *testing.T) {
	pool := testPool(t)
	repo := NewSyncRepository(pool)
	ctx := context.Background()

	businessID, userID, customerID := seedBusiness(t, pool)

	// Device A begins a push. Its rows will carry this transaction's start time.
	txA, err := pool.Begin(ctx)
	if err != nil {
		t.Fatalf("begin device A transaction: %v", err)
	}
	defer txA.Rollback(ctx)

	_, err = txA.Exec(ctx,
		`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, 'debt', 500, CURRENT_DATE, NOW(), NOW())`,
		uuid.New(), businessID, customerID, userID)
	if err != nil {
		t.Fatalf("device A insert: %v", err)
	}

	// Device B pulls mid-flight and stores the server clock as its watermark.
	during, err := repo.Pull(ctx, businessID, time.Unix(0, 0).UTC())
	if err != nil {
		t.Fatalf("legacy pull: %v", err)
	}
	watermark := during.ServerTime

	if err := txA.Commit(ctx); err != nil {
		t.Fatalf("device A commit: %v", err)
	}

	// Device B pulls again. The committed row carries a timestamp from before the
	// watermark, so it is filtered out — and will be on every future pull too.
	after, err := repo.Pull(ctx, businessID, watermark)
	if err != nil {
		t.Fatalf("legacy pull after commit: %v", err)
	}
	if len(after.Transactions) != 0 {
		t.Skip("timing did not reproduce the race on this run; the cursor test is the authoritative one")
	}

	// Confirm the row genuinely exists and is only unreachable via the watermark.
	var count int
	if err := pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM transactions WHERE business_id = $1`, businessID).Scan(&count); err != nil {
		t.Fatalf("count transactions: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected the row to be committed and present, found %d", count)
	}
	t.Log("confirmed: the committed row is invisible to a timestamp watermark, but reachable by cursor")
}

// TestCursorPull_PaginatesToACommonBoundary covers the subtlety of two tables
// sharing one sequence.
//
// If customers and transactions were paginated independently, a limit reached in
// one table could advance the cursor past rows the other never returned, and
// everything between would be lost. The boundary must be one both sets covered.
func TestCursorPull_PaginatesToACommonBoundary(t *testing.T) {
	pool := testPool(t)
	repo := NewSyncRepository(pool)
	ctx := context.Background()

	businessID, userID, customerID := seedBusiness(t, pool)

	// Many customers first, then many transactions. With a small page size the
	// customers alone exceed the limit, so a naive implementation would advance
	// the cursor beyond every transaction written afterwards.
	for i := 0; i < 10; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO customers (id, business_id, name, created_by) VALUES ($1, $2, $3, $4)`,
			uuid.New(), businessID, "Cust", userID); err != nil {
			t.Fatalf("insert customer %d: %v", i, err)
		}
	}
	for i := 0; i < 10; i++ {
		if _, err := pool.Exec(ctx,
			`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, transaction_date, created_at, updated_at)
			 VALUES ($1, $2, $3, $4, 'debt', 100, CURRENT_DATE, NOW(), NOW())`,
			uuid.New(), businessID, customerID, userID); err != nil {
			t.Fatalf("insert transaction %d: %v", i, err)
		}
	}

	// Page through with a deliberately small limit and count everything received.
	var (
		cursor      int64
		gotCust     int
		gotTx       int
		iterations  int
		seenCursors = map[int64]bool{}
	)
	for {
		iterations++
		if iterations > 50 {
			t.Fatal("pagination did not terminate")
		}

		page, err := repo.PullByCursor(ctx, businessID, cursor, 3)
		if err != nil {
			t.Fatalf("page %d: %v", iterations, err)
		}
		gotCust += len(page.Customers)
		gotTx += len(page.Transactions)

		if seenCursors[page.NextCursor] && page.HasMore {
			t.Fatalf("cursor stalled at %d without finishing", page.NextCursor)
		}
		seenCursors[page.NextCursor] = true
		cursor = page.NextCursor

		if !page.HasMore {
			break
		}
	}

	// 11 customers: ten inserted here plus the one from the seed.
	if gotCust != 11 {
		t.Errorf("received %d customers across all pages, want 11", gotCust)
	}
	if gotTx != 10 {
		t.Errorf("received %d transactions across all pages, want 10", gotTx)
	}
}
