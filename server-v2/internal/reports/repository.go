package reports

import (
	"context"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// overdueThreshold is how long a positive balance can sit untouched before it
// counts as overdue. Matches the threshold v1 used, carried forward rather than
// reconsidered — changing what "overdue" means is a product decision, not
// something to slip in while porting the query.
const overdueThreshold = 30 * 24 * time.Hour

// topDebtorLimit and overdueDebtorLimit cap the two lists at what fits on a
// dashboard glance. A shop with hundreds of debtors gets its worst cases, not a
// scroll — anyone needing the full list already has GET /customers, sorted.
const (
	topDebtorLimit     = 10
	overdueDebtorLimit = 10
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// Summary computes the whole dashboard in a handful of queries, each scoped to
// the caller's business.
//
// Every query here joins transactions to customers. That matters: Tusk's
// automatic tenant scoping patches the WHERE clause of a query's *base*
// table — the one passed to Model — not a table brought in with Joins. A query
// scoped only through the transactions side would trust customers.business_id
// implicitly via transactions.customer_id, which happens to hold today because
// nothing lets a transaction reference another business's customer, but is not
// something a report should depend on silently. Every query below states the
// business explicitly on both tables instead.
func (r *Repository) Summary(ctx context.Context) (*SummaryView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	var summary SummaryView

	if err := r.db.WithContext(ctx).Model(&domain.Customer{}).
		Where("is_deleted = false").
		Count(&summary.TotalCustomers).Error; err != nil {
		return nil, fmt.Errorf("counting customers: %w", err)
	}

	if err := r.db.WithContext(ctx).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("is_deleted = false").
		Scan(&summary.TotalOutstandingDebt).Error; err != nil {
		return nil, fmt.Errorf("summing outstanding debt: %w", err)
	}

	since := time.Now().Add(-30 * 24 * time.Hour)
	if err := r.db.WithContext(ctx).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("type = 'payment' AND is_deleted = false AND created_at >= ?", since).
		Scan(&summary.TotalCollected30Days).Error; err != nil {
		return nil, fmt.Errorf("summing recent payments: %w", err)
	}

	debtors, err := r.debtorsByBalance(ctx, businessID, topDebtorLimit)
	if err != nil {
		return nil, fmt.Errorf("ranking top debtors: %w", err)
	}
	summary.TopDebtors = debtors

	overdue, err := r.overdueDebtors(ctx, businessID, overdueDebtorLimit)
	if err != nil {
		return nil, fmt.Errorf("ranking overdue debtors: %w", err)
	}
	summary.OverdueDebtors = overdue
	summary.OverdueDebtorCount = len(overdue)
	if len(overdue) == overdueDebtorLimit {
		// The list was truncated for display, but the count on the summary card
		// should still be the real number, not the length of a capped list.
		count, err := r.overdueDebtorCount(ctx, businessID)
		if err != nil {
			return nil, fmt.Errorf("counting overdue debtors: %w", err)
		}
		summary.OverdueDebtorCount = count
	}

	return &summary, nil
}

// balanceQuery is the aggregate shared by every ranked list below: one row per
// customer with a positive balance, and when they were last touched.
func (r *Repository) balanceQuery(ctx context.Context, businessID uuid.UUID) *gorm.DB {
	return r.db.WithContext(ctx).
		Table("transactions").
		Joins("JOIN customers ON customers.id = transactions.customer_id AND customers.business_id = ?", businessID).
		Where("transactions.business_id = ? AND transactions.is_deleted = false AND customers.is_deleted = false", businessID).
		Group("customers.id, customers.name, customers.phone").
		Having("COALESCE(SUM(CASE WHEN transactions.type = 'debt' THEN transactions.amount ELSE -transactions.amount END), 0) > 0")
}

func (r *Repository) debtorsByBalance(ctx context.Context, businessID uuid.UUID, limit int) ([]DebtorView, error) {
	var rows []debtorRow
	err := r.balanceQuery(ctx, businessID).
		Select(`customers.id AS customer_id, customers.name, customers.phone,
			COALESCE(SUM(CASE WHEN transactions.type = 'debt' THEN transactions.amount ELSE -transactions.amount END), 0) AS balance,
			MAX(transactions.created_at) AS last_activity`).
		Order("balance DESC").
		Limit(limit).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	return toDebtorViews(rows), nil
}

func (r *Repository) overdueDebtors(ctx context.Context, businessID uuid.UUID, limit int) ([]DebtorView, error) {
	var rows []debtorRow
	err := r.balanceQuery(ctx, businessID).
		Select(`customers.id AS customer_id, customers.name, customers.phone,
			COALESCE(SUM(CASE WHEN transactions.type = 'debt' THEN transactions.amount ELSE -transactions.amount END), 0) AS balance,
			MAX(transactions.created_at) AS last_activity`).
		Having("MAX(transactions.created_at) < ?", time.Now().Add(-overdueThreshold)).
		Order("last_activity ASC").
		Limit(limit).
		Scan(&rows).Error
	if err != nil {
		return nil, err
	}
	return toDebtorViews(rows), nil
}

func (r *Repository) overdueDebtorCount(ctx context.Context, businessID uuid.UUID) (int, error) {
	// COUNT(*) over a GROUP BY is itself a set of rows, so this counts rows of
	// a subquery rather than asking Postgres to count groups directly.
	var n int64
	err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*) FROM (?) AS overdue
	`, r.balanceQuery(ctx, businessID).
		Select("customers.id").
		Having("MAX(transactions.created_at) < ?", time.Now().Add(-overdueThreshold)),
	).Scan(&n).Error
	return int(n), err
}

// debtorRow is the shape Scan reads a raw aggregate into, kept separate from
// DebtorView: the view adds DaysSinceLast, which is derived, not stored.
type debtorRow struct {
	CustomerID   uuid.UUID
	Name         string
	Phone        *string
	Balance      money.Amount
	LastActivity time.Time
}

func toDebtorViews(rows []debtorRow) []DebtorView {
	out := make([]DebtorView, 0, len(rows))
	now := time.Now()
	for _, r := range rows {
		out = append(out, DebtorView{
			CustomerID:    r.CustomerID,
			Name:          r.Name,
			Phone:         r.Phone,
			Balance:       r.Balance,
			LastActivity:  r.LastActivity,
			DaysSinceLast: int(now.Sub(r.LastActivity).Hours() / 24),
		})
	}
	return out
}
