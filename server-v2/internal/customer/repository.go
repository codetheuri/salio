package customer

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/query"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

var ErrNotFound = errors.New("customer not found")

// ErrPhoneTaken means another customer of the same business already has this
// phone number. Enforced by a partial unique index (migration 00001), so this
// error is reached only by translating that constraint violation — the
// database is still the actual source of truth, which matters because it is
// also what closes the race between two concurrent creates.
var ErrPhoneTaken = errors.New("a customer with this phone number already exists")

// queryConfig whitelists what List may search and sort by. AllowedSearches and
// AllowedSorts are consulted by column name, never by whatever a client sends
// directly — the whitelist is what makes exposing pkg/query to a request safe.
var queryConfig = query.Config{
	DefaultSort:     "-created_at",
	DefaultPerPage:  50,
	MaxPerPage:      200,
	AllowedSearches: []string{"customers.name", "customers.phone"},
	AllowedSorts:    map[string]string{"name": "customers.name", "created_at": "customers.created_at"},
}

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// List returns a page of active customers. Scoping to the caller's business and
// excluding soft-deleted rows both happen here, in the query itself — not as
// something the caller has to remember to add on top.
func (r *Repository) List(ctx context.Context, q query.Query) ([]domain.Customer, query.Meta, error) {
	base := r.db.WithContext(ctx).Where("is_deleted = false")
	return query.Paginate[domain.Customer](ctx, base, q, queryConfig)
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Customer, error) {
	var c domain.Customer
	err := r.db.WithContext(ctx).
		Where("is_deleted = false").
		First(&c, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &c, err
}

func (r *Repository) Create(ctx context.Context, c *domain.Customer) error {
	if err := r.db.WithContext(ctx).Create(c).Error; err != nil {
		if isUniqueViolation(err) {
			return ErrPhoneTaken
		}
		return fmt.Errorf("creating customer: %w", err)
	}
	return nil
}

func (r *Repository) Update(ctx context.Context, id uuid.UUID, name string, phone, notes *string) (*domain.Customer, error) {
	// The field versions have to move with the values.
	//
	// Sync merges a customer field by field, comparing each incoming field
	// against when that field last accepted a write. An edit made here that did
	// not record itself would leave those versions behind the data, and a stale
	// edit arriving from a device that has been offline would then be judged
	// newer than this one and overwrite it. See domain.FieldVersions.
	stamp, err := domain.StampFieldVersions([]string{"name", "phone", "notes"}, time.Now().UTC())
	if err != nil {
		return nil, fmt.Errorf("stamping field versions: %w", err)
	}

	res := r.db.WithContext(ctx).
		Model(&domain.Customer{}).
		Where("id = ? AND is_deleted = false", id).
		Updates(map[string]any{
			"name": name, "phone": phone, "notes": notes,
			// Concatenated in SQL rather than read, merged in Go and written
			// back: jsonb || jsonb merges server-side in one statement, so two
			// writers touching different fields cannot lose each other's keys.
			"field_versions": gorm.Expr("field_versions || ?::jsonb", stamp),
		})
	if res.Error != nil {
		if isUniqueViolation(res.Error) {
			return nil, ErrPhoneTaken
		}
		return nil, fmt.Errorf("updating customer: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return nil, ErrNotFound
	}
	return r.GetByID(ctx, id)
}

func (r *Repository) SoftDelete(ctx context.Context, id uuid.UUID) error {
	stamp, err := domain.StampFieldVersions([]string{"is_deleted"}, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("stamping field versions: %w", err)
	}

	res := r.db.WithContext(ctx).
		Model(&domain.Customer{}).
		Where("id = ? AND is_deleted = false", id).
		Updates(map[string]any{
			"is_deleted":     true,
			"field_versions": gorm.Expr("field_versions || ?::jsonb", stamp),
		})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

// Balance sums the ledger for one customer: debts add, payments subtract. It is
// computed here, on every read, rather than stored — see domain.Transaction.Signed
// for why a stored balance is a second source of truth that drifts.
func (r *Repository) Balance(ctx context.Context, customerID uuid.UUID) (money.Amount, error) {
	var balance money.Amount
	err := r.db.WithContext(ctx).
		Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ? AND is_deleted = false", customerID).
		Scan(&balance).Error
	return balance, err
}

// BalancesFor computes balances for several customers in one query, keyed by
// customer ID. Customers with no transactions at all are simply absent from the
// map — the caller reads them as the zero Amount, which is correct.
func (r *Repository) BalancesFor(ctx context.Context, customerIDs []uuid.UUID) (map[uuid.UUID]money.Amount, error) {
	if len(customerIDs) == 0 {
		return map[uuid.UUID]money.Amount{}, nil
	}

	var rows []struct {
		CustomerID uuid.UUID
		Balance    money.Amount
	}
	err := r.db.WithContext(ctx).
		Model(&domain.Transaction{}).
		Select("customer_id, COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0) AS balance").
		Where("customer_id IN ? AND is_deleted = false", customerIDs).
		Group("customer_id").
		Scan(&rows).Error
	if err != nil {
		return nil, fmt.Errorf("computing balances: %w", err)
	}

	balances := make(map[uuid.UUID]money.Amount, len(rows))
	for _, r := range rows {
		balances[r.CustomerID] = r.Balance
	}
	return balances, nil
}

// isUniqueViolation checks for Postgres SQLSTATE 23505 without importing the
// pgx error type — GORM wraps the underlying driver error, and matching the
// code rather than a message string survives translation and driver changes.
func isUniqueViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	if errors.As(err, &pgErr) {
		return pgErr.SQLState() == "23505"
	}
	return false
}
