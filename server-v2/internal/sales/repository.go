package sales

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/shopclock"
)

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) Create(ctx context.Context, s *domain.Sale) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		return Record(ctx, tx, s)
	})
}

// GetByID returns a sale, voided or not — someone asking what happened to a
// sale needs to see that it was voided.
func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Sale, error) {
	var s domain.Sale
	err := r.db.WithContext(ctx).First(&s, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

type listFilter struct {
	from, to   time.Time
	customerID uuid.UUID
	limit      int
	offset     int
}

func (r *Repository) List(ctx context.Context, f listFilter) ([]domain.Sale, int64, error) {
	q := r.db.WithContext(ctx).Model(&domain.Sale{}).
		Where("is_deleted = false AND sale_date BETWEEN ? AND ?", f.from, f.to)
	if f.customerID != uuid.Nil {
		q = q.Where("customer_id = ?", f.customerID)
	}

	var total int64
	if err := q.Count(&total).Error; err != nil {
		return nil, 0, err
	}

	var rows []domain.Sale
	err := q.Order("sale_date DESC, created_at DESC").
		Limit(f.limit).Offset(f.offset).
		Find(&rows).Error
	return rows, total, err
}

// CustomerNames looks up names for the customers on a page of sales, in one
// query, tenant-scoped by the model's callbacks.
func (r *Repository) CustomerNames(ctx context.Context, ids []uuid.UUID) (map[uuid.UUID]string, error) {
	names := map[uuid.UUID]string{}
	if len(ids) == 0 {
		return names, nil
	}
	var rows []domain.Customer
	if err := r.db.WithContext(ctx).Select("id", "name").
		Where("id IN ?", ids).Find(&rows).Error; err != nil {
		return nil, err
	}
	for _, c := range rows {
		names[c.ID] = c.Name
	}
	return names, nil
}

func (r *Repository) Void(ctx context.Context, id uuid.UUID) error {
	return Void(ctx, r.db, id)
}

// Today is the business's current calendar date, in its own time zone.
func (r *Repository) Today(ctx context.Context) (time.Time, error) {
	return shopclock.Today(ctx, r.db)
}
