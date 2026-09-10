package dataimport

import (
	"context"
	"fmt"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/money"
)

// Discrepancy is one thing the import got wrong.
//
// Collected rather than returned as an error on the first one: an operator about
// to cut over needs the whole picture, and "17 balances differ, all in one
// business" is a diagnosis where "the first balance differs" is a guess.
type Discrepancy struct {
	Kind   string
	Detail string
}

func (d Discrepancy) String() string { return d.Kind + ": " + d.Detail }

// Discrepancy kinds.
const (
	KindRowCount = "row_count"
	KindBalance  = "balance"
	KindMissing  = "missing_customer"
	KindExtra    = "extra_customer"
)

// Verify compares the target against the source and reports every difference.
//
// The balance comparison is the one that decides whether cutover may proceed.
// Row counts can match while the ledger is wrong — a transaction imported with
// the wrong sign, or attached to the wrong customer, keeps every count intact and
// changes what a real person is told they owe. Balances are the only check that
// looks at the number the product exists to get right.
//
// Both sides derive the balance with the same formula over non-tombstoned rows,
// and compare the exact decimal text. Nothing is converted to a float on either
// side, so "equal" means equal and not equal to within a rounding error.
func Verify(ctx context.Context, src *Source, target *gorm.DB) ([]Discrepancy, error) {
	var found []Discrepancy

	sourceCounts, err := src.Counts(ctx)
	if err != nil {
		return nil, err
	}
	targetCounts, err := targetCountsOf(ctx, target)
	if err != nil {
		return nil, err
	}

	for _, c := range []struct {
		table       string
		from, to    int64
		explanation string
	}{
		{"businesses", sourceCounts.Businesses, targetCounts.Businesses, ""},
		{"users", sourceCounts.Users, targetCounts.Users, ""},
		{"customers", sourceCounts.Customers, targetCounts.Customers, ""},
		{"transactions", sourceCounts.Transactions, targetCounts.Transactions, ""},
		{"super_admins", sourceCounts.SuperAdmins, targetCounts.SuperAdmins, ""},
	} {
		if c.from != c.to {
			found = append(found, Discrepancy{
				Kind:   KindRowCount,
				Detail: fmt.Sprintf("%s: %d in v1, %d in v2", c.table, c.from, c.to),
			})
		}
	}

	sourceBalances, err := src.Balances(ctx)
	if err != nil {
		return nil, err
	}
	targetBalances, err := targetBalancesOf(ctx, target)
	if err != nil {
		return nil, err
	}

	for customerID, want := range sourceBalances {
		got, present := targetBalances[customerID]
		if !present {
			found = append(found, Discrepancy{
				Kind:   KindMissing,
				Detail: fmt.Sprintf("customer %s is in v1 but not v2", customerID),
			})
			continue
		}
		// Compared as money, not as text: Postgres may render the same value as
		// "0" on one side and "0.00" on the other depending on how the sum was
		// built, and that difference is formatting rather than a discrepancy.
		if !sameMoney(want, got) {
			found = append(found, Discrepancy{
				Kind:   KindBalance,
				Detail: fmt.Sprintf("customer %s: %s in v1, %s in v2", customerID, want, got),
			})
		}
	}
	for customerID := range targetBalances {
		if _, present := sourceBalances[customerID]; !present {
			found = append(found, Discrepancy{
				Kind:   KindExtra,
				Detail: fmt.Sprintf("customer %s is in v2 but not v1", customerID),
			})
		}
	}

	return found, nil
}

// targetCountsOf reads across every business, through the platform-admin door.
//
// The same read-only door the console uses, and for the same reason: this is a
// question about the whole platform, asked by something that belongs to no
// business. Migration 00005 makes it incapable of writing or deleting.
func targetCountsOf(ctx context.Context, target *gorm.DB) (*Counts, error) {
	var c Counts
	err := target.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}
		return tenant.Unscoped(tx).Raw(`
			SELECT (SELECT COUNT(*) FROM businesses),
			       (SELECT COUNT(*) FROM users),
			       (SELECT COUNT(*) FROM customers),
			       (SELECT COUNT(*) FROM transactions),
			       (SELECT COUNT(*) FROM super_admins)
		`).Row().Scan(&c.Businesses, &c.Users, &c.Customers, &c.Transactions, &c.SuperAdmins)
	})
	if err != nil {
		return nil, fmt.Errorf("counting target rows: %w", err)
	}
	return &c, nil
}

func targetBalancesOf(ctx context.Context, target *gorm.DB) (map[uuid.UUID]string, error) {
	out := map[uuid.UUID]string{}

	err := target.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}

		var rows []struct {
			ID      uuid.UUID
			Balance string
		}
		// Deliberately the same SQL shape as Source.Balances. If the two ever
		// diverge, this test stops comparing like with like and starts agreeing
		// with itself.
		if err := tenant.Unscoped(tx).Raw(`
			SELECT c.id,
			       COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END), 0)::text AS balance
			FROM customers c
			LEFT JOIN transactions t ON t.customer_id = c.id AND t.is_deleted = false
			WHERE c.is_deleted = false
			GROUP BY c.id
		`).Scan(&rows).Error; err != nil {
			return err
		}
		for _, r := range rows {
			out[r.ID] = r.Balance
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("computing target balances: %w", err)
	}
	return out, nil
}

// sameMoney compares two decimal strings by value.
func sameMoney(a, b string) bool {
	left, errA := parseAmount(a)
	right, errB := parseAmount(b)
	if errA != nil || errB != nil {
		// Unparseable on either side is a difference worth reporting, not one to
		// swallow as equal.
		return errA != nil && errB != nil && a == b
	}
	return left == right
}

func parseAmount(s string) (int64, error) {
	amount, err := money.Parse(s)
	if err != nil {
		return 0, err
	}
	return amount.Minor(), nil
}
