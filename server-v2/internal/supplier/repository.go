package supplier

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/shopclock"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// List returns active suppliers, by name. A shop buys from a handful of
// suppliers, not thousands, so the list is not paginated.
func (r *Repository) List(ctx context.Context, search string) ([]domain.Supplier, error) {
	q := r.db.WithContext(ctx).Where("is_deleted = false")
	if s := strings.TrimSpace(search); s != "" {
		// Escaped: an unescaped "%" or "_" typed into the search box would
		// otherwise act as a wildcard.
		q = q.Where(`name ILIKE ? ESCAPE '\'`, "%"+likeEscaper.Replace(s)+"%")
	}
	var rows []domain.Supplier
	err := q.Order("name").Find(&rows).Error
	return rows, err
}

var likeEscaper = strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)

func (r *Repository) Get(ctx context.Context, id uuid.UUID) (*domain.Supplier, error) {
	var s domain.Supplier
	err := r.db.WithContext(ctx).Where("is_deleted = false").First(&s, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// GetAny returns a supplier whether or not it is deleted — for an idempotent
// create, which must find what a retried request already made.
func (r *Repository) GetAny(ctx context.Context, id uuid.UUID) (*domain.Supplier, error) {
	var s domain.Supplier
	err := r.db.WithContext(ctx).First(&s, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

func (r *Repository) Create(ctx context.Context, s *domain.Supplier) error {
	if err := r.db.WithContext(ctx).Create(s).Error; err != nil {
		return fmt.Errorf("creating supplier: %w", err)
	}
	return nil
}

func (r *Repository) Update(ctx context.Context, s *domain.Supplier) error {
	res := r.db.WithContext(ctx).Model(&domain.Supplier{}).
		Where("id = ? AND is_deleted = false", s.ID).
		Updates(map[string]any{"name": s.Name, "phone": s.Phone, "notes": s.Notes})
	if res.Error != nil {
		return fmt.Errorf("updating supplier: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) Delete(ctx context.Context, id uuid.UUID) error {
	return DeleteIfSettled(ctx, r.db, id)
}

func (r *Repository) Balance(ctx context.Context, id uuid.UUID) (money.Amount, error) {
	return balanceOf(ctx, r.db, id)
}

// Balances computes several suppliers' balances in one query. A supplier with
// no entries is absent, which the caller reads as zero.
func (r *Repository) Balances(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]money.Amount, error) {
	out := map[uuid.UUID]money.Amount{}
	if len(ids) == 0 {
		return out, nil
	}
	var rows []struct {
		SupplierID uuid.UUID
		Balance    money.Amount
	}
	if err := r.db.WithContext(ctx).Model(&domain.SupplierTransaction{}).
		Select("supplier_id, "+balanceSQL+" AS balance").
		Where("supplier_id IN ? AND is_deleted = false", ids).
		Group("supplier_id").
		Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("computing supplier balances: %w", err)
	}
	for _, row := range rows {
		out[row.SupplierID] = row.Balance
	}
	return out, nil
}

func (r *Repository) RecordEntry(ctx context.Context, t *domain.SupplierTransaction) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return Record(ctx, tx, t)
	})
}

// GetEntry returns a bill or payment, voided or not: someone asking what
// happened to a payment needs to see that it was voided.
func (r *Repository) GetEntry(ctx context.Context, id uuid.UUID) (*domain.SupplierTransaction, error) {
	var t domain.SupplierTransaction
	err := r.db.WithContext(ctx).First(&t, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrEntryNotFound
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// Entries lists a supplier's live bills and payments, newest first.
func (r *Repository) Entries(ctx context.Context, supplierID uuid.UUID) ([]domain.SupplierTransaction, error) {
	var rows []domain.SupplierTransaction
	err := r.db.WithContext(ctx).
		Where("supplier_id = ? AND is_deleted = false", supplierID).
		Order("transaction_date DESC, created_at DESC").
		Find(&rows).Error
	return rows, err
}

func (r *Repository) VoidEntry(ctx context.Context, id uuid.UUID) error {
	return Void(ctx, r.db, id)
}

// Today is the business's current calendar date, in its own time zone.
func (r *Repository) Today(ctx context.Context) (time.Time, error) {
	return shopclock.Today(ctx, r.db)
}
