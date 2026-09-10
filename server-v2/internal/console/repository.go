package console

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// ErrNotFound reports that a record does not exist.
var ErrNotFound = errors.New("console: not found")

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// readAll runs fn with both layers of tenant isolation deliberately open, and is
// the only place in Salio that does so.
//
// The console is the one component that reads across businesses: it reports on
// the whole platform for a super_admin who belongs to no business at all. Both
// protections therefore have to be answered, and they are separate mechanisms
// that fail in different ways:
//
//  1. The GORM callbacks (tenant.Unscoped, applied per statement inside fn).
//     Without it every query errors with "no tenant in context" — a loud,
//     immediate failure that shows up the first time anyone runs it.
//
//  2. PostgreSQL row-level security (app.platform_admin, set here). Without it
//     every query silently returns nothing. That failure is invisible in
//     development, where the connection is a superuser and exempt from policies,
//     and appears only in production as a dashboard reading zero.
//
// Migration 00004 opens that door on USING alone, and 00005 completes it. USING
// alone stops INSERT and UPDATE, which are constrained by WITH CHECK — but a
// DELETE has no WITH CHECK, so USING was the only thing governing it and the
// door permitted cross-tenant deletes. 00005 adds a RESTRICTIVE delete policy,
// ANDed with the permissive one, requiring a real tenant for any delete no
// matter what else is set. Only with both is this door actually read-only.
//
// SET LOCAL, hence the transaction: the flag reverts on commit, so it cannot
// survive on a pooled connection into the next request. Callers must not write
// through the tx they are handed — WITH CHECK would refuse it anyway, which is
// the point of relaxing only one half of the policy.
func (r *Repository) readAll(ctx context.Context, fn func(tx *gorm.DB) error) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return fmt.Errorf("console: opening platform read access: %w", err)
		}
		return fn(tx)
	})
}

// --- Super admin authentication ---

// FindAdminByEmail loads a super admin for the login form.
//
// super_admins is not a tenanted model and carries no policy, so this one needs
// neither of readAll's exemptions.
func (r *Repository) FindAdminByEmail(ctx context.Context, email string) (*domain.SuperAdmin, error) {
	var admin domain.SuperAdmin
	err := r.db.WithContext(ctx).Where("lower(email) = lower(?)", email).First(&admin).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("console: loading admin: %w", err)
	}
	return &admin, nil
}

// FindAdminByID resolves a session's subject back to the person holding it.
func (r *Repository) FindAdminByID(ctx context.Context, adminID uuid.UUID) (*domain.SuperAdmin, error) {
	var admin domain.SuperAdmin
	err := r.db.WithContext(ctx).Where("id = ?", adminID).First(&admin).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("console: loading admin: %w", err)
	}
	return &admin, nil
}

// CreateAdmin adds a platform operator. Called by cmd/createadmin, never over HTTP.
func (r *Repository) CreateAdmin(ctx context.Context, admin *domain.SuperAdmin) error {
	return r.db.WithContext(ctx).Create(admin).Error
}

// --- Dashboard ---

// Summary aggregates the whole platform.
//
// One round trip rather than seven: the numbers are shown together on one card
// grid, and running them as separate statements would let a business registered
// between two of them be counted by one and missed by another. Inside a single
// statement they are consistent with each other by construction.
func (r *Repository) Summary(ctx context.Context) (*Summary, error) {
	var s Summary

	err := r.readAll(ctx, func(tx *gorm.DB) error {
		return tenant.Unscoped(tx).Raw(`
			SELECT
				(SELECT COUNT(*) FROM businesses)                                  AS total_businesses,
				(SELECT COUNT(*) FROM users)                                       AS total_users,
				(SELECT COUNT(*) FROM users WHERE is_active = false)               AS inactive_users,
				(SELECT COUNT(*) FROM customers WHERE is_deleted = false)          AS total_customers,
				(SELECT COUNT(*) FROM transactions WHERE is_deleted = false)       AS total_transactions,
				COALESCE((SELECT SUM(amount) FROM transactions
					WHERE type = 'debt'    AND is_deleted = false), 0)             AS total_debt,
				COALESCE((SELECT SUM(amount) FROM transactions
					WHERE type = 'payment' AND is_deleted = false), 0)             AS total_payments,
				(SELECT COUNT(*) FROM businesses WHERE created_at >= date_trunc('day', NOW())) AS new_businesses_today,
				(SELECT COUNT(*) FROM transactions
					WHERE is_deleted = false AND created_at >= NOW() - INTERVAL '7 days')      AS transactions_7_days,
				(SELECT COUNT(DISTINCT business_id) FROM transactions
					WHERE created_at >= NOW() - INTERVAL '7 days')                 AS active_businesses_7_days
		`).Scan(&s).Error
	})
	if err != nil {
		return nil, fmt.Errorf("console: summarising the platform: %w", err)
	}

	// Derived here rather than in SQL so the two sides cannot disagree: it is the
	// same debt-minus-payments formula the mobile client and the reports module
	// use, and there is exactly one definition of a balance in this system.
	s.OutstandingBalance = s.TotalDebt - s.TotalPayments
	return &s, nil
}

// --- Businesses ---

// businessSelect is shared by the list and the single-business lookup so the two
// pages can never disagree about what a staff count or a customer count means.
//
// The owner is picked with a LATERAL join rather than an inner join on
// role = 'owner'. v1 used the latter, which has two faults: a business with two
// owners appeared twice in the list, and a business whose only owner had been
// deactivated vanished from the console entirely — precisely the business an
// operator is most likely to be looking for.
const businessSelect = `
	SELECT
		b.id, b.name, b.type, b.created_at,
		COALESCE(owner.name, '')  AS owner_name,
		COALESCE(owner.phone, '') AS owner_phone,
		(SELECT COUNT(*) FROM users u
			WHERE u.business_id = b.id AND u.role = 'staff')                  AS staff_count,
		(SELECT COUNT(*) FROM customers c
			WHERE c.business_id = b.id AND c.is_deleted = false)              AS customer_count,
		COALESCE((SELECT SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END)
			FROM transactions t
			WHERE t.business_id = b.id AND t.is_deleted = false), 0)          AS outstanding_balance
	FROM businesses b
	LEFT JOIN LATERAL (
		SELECT u.name, u.phone FROM users u
		WHERE u.business_id = b.id AND u.role = 'owner'
		ORDER BY u.is_active DESC, u.created_at ASC
		LIMIT 1
	) owner ON true
`

// Businesses returns one page of businesses, newest first.
func (r *Repository) Businesses(ctx context.Context, limit, offset int) ([]BusinessRow, int64, error) {
	var (
		rows  []BusinessRow
		total int64
	)

	err := r.readAll(ctx, func(tx *gorm.DB) error {
		if err := tenant.Unscoped(tx).Raw(businessSelect+`
			ORDER BY b.created_at DESC LIMIT ? OFFSET ?
		`, limit, offset).Scan(&rows).Error; err != nil {
			return err
		}
		// tenant.Unscoped is called again rather than reusing the value above.
		// Its return shares one gorm.Statement with the receiver, so a second
		// query built on the first inherits the first's clauses and model — a
		// trap that has already produced one silently wrong write in this
		// codebase. Fresh per statement, every time.
		return tenant.Unscoped(tx).Raw(`SELECT COUNT(*) FROM businesses`).Scan(&total).Error
	})
	if err != nil {
		return nil, 0, fmt.Errorf("console: listing businesses: %w", err)
	}
	return rows, total, nil
}

// Business returns one business with its full detail, and its people.
func (r *Repository) Business(ctx context.Context, businessID uuid.UUID) (*BusinessDetail, []UserRow, error) {
	var (
		detail BusinessDetail
		users  []UserRow
		found  bool
	)

	err := r.readAll(ctx, func(tx *gorm.DB) error {
		res := tenant.Unscoped(tx).Raw(businessSelect+` WHERE b.id = ?`, businessID).Scan(&detail)
		if res.Error != nil {
			return res.Error
		}
		if res.RowsAffected == 0 {
			return nil // found stays false
		}
		found = true

		// Scanned into its own struct rather than into detail a second time.
		// GORM resets a struct destination before filling it, so a second Scan
		// onto the same value silently zeroes every column the second query does
		// not name — which had already emptied the customer count and the
		// balance the first query had just computed.
		var ledger struct {
			TotalTransactions int64
			TotalDebt         money.Amount
			TotalPayments     money.Amount
			LastActivityAt    *time.Time
		}
		if err := tenant.Unscoped(tx).Raw(`
			SELECT
				COUNT(*)                                                            AS total_transactions,
				COALESCE(SUM(CASE WHEN type = 'debt'    THEN amount ELSE 0 END), 0) AS total_debt,
				COALESCE(SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END), 0) AS total_payments,
				MAX(created_at)                                                     AS last_activity_at
			FROM transactions WHERE business_id = ? AND is_deleted = false
		`, businessID).Scan(&ledger).Error; err != nil {
			return err
		}
		detail.TotalTransactions = ledger.TotalTransactions
		detail.TotalDebt = ledger.TotalDebt
		detail.TotalPayments = ledger.TotalPayments
		detail.LastActivityAt = ledger.LastActivityAt

		return tenant.Unscoped(tx).Raw(`
			SELECT u.id, u.name, u.phone, u.role, u.is_active, u.business_id,
			       b.name AS business_name, u.created_at
			FROM users u
			JOIN businesses b ON b.id = u.business_id
			WHERE u.business_id = ?
			ORDER BY u.role ASC, u.created_at ASC
		`, businessID).Scan(&users).Error
	})
	if err != nil {
		return nil, nil, fmt.Errorf("console: loading business %s: %w", businessID, err)
	}
	if !found {
		return nil, nil, ErrNotFound
	}
	return &detail, users, nil
}

// --- Users ---

// Users returns one page of users across every business.
func (r *Repository) Users(ctx context.Context, limit, offset int) ([]UserRow, int64, error) {
	var (
		rows  []UserRow
		total int64
	)

	err := r.readAll(ctx, func(tx *gorm.DB) error {
		if err := tenant.Unscoped(tx).Raw(`
			SELECT u.id, u.name, u.phone, u.role, u.is_active, u.business_id,
			       b.name AS business_name, u.created_at
			FROM users u
			JOIN businesses b ON b.id = u.business_id
			ORDER BY u.created_at DESC
			LIMIT ? OFFSET ?
		`, limit, offset).Scan(&rows).Error; err != nil {
			return err
		}
		return tenant.Unscoped(tx).Raw(`SELECT COUNT(*) FROM users`).Scan(&total).Error
	})
	if err != nil {
		return nil, 0, fmt.Errorf("console: listing users: %w", err)
	}
	return rows, total, nil
}

// --- Row types ---

// Summary is the platform-wide dashboard.
type Summary struct {
	TotalBusinesses    int64
	TotalUsers         int64
	InactiveUsers      int64
	TotalCustomers     int64
	TotalTransactions  int64
	TotalDebt          money.Amount
	TotalPayments      money.Amount
	OutstandingBalance money.Amount

	NewBusinessesToday    int64
	Transactions7Days     int64 `gorm:"column:transactions_7_days"`
	ActiveBusinesses7Days int64 `gorm:"column:active_businesses_7_days"`
}

// BusinessRow is one line of the businesses list.
type BusinessRow struct {
	ID                 uuid.UUID
	Name               string
	Type               *string
	OwnerName          string
	OwnerPhone         string
	StaffCount         int64
	CustomerCount      int64
	OutstandingBalance money.Amount
	CreatedAt          time.Time
}

// BusinessDetail is BusinessRow plus the ledger totals for one business.
type BusinessDetail struct {
	// Tagged embedded, so GORM flattens these columns into this struct when it
	// scans rather than looking for a "business_row" column that does not exist.
	BusinessRow `gorm:"embedded"`

	TotalTransactions int64
	TotalDebt         money.Amount
	TotalPayments     money.Amount

	// LastActivityAt is nil for a business that has never recorded anything —
	// which is a meaningful state on this page, and the reason it is not a
	// zero time.Time pretending to be January year 1.
	LastActivityAt *time.Time
}

// UserRow is one line of the users list.
type UserRow struct {
	ID           uuid.UUID
	Name         string
	Phone        string
	Role         domain.Role
	IsActive     bool
	BusinessID   uuid.UUID
	BusinessName string
	CreatedAt    time.Time
}
