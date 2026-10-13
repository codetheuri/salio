package stock

import (
	"context"
	"errors"
	"fmt"
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

// --- Stock requests ---

func (r *Repository) CreateRequest(ctx context.Context, req *domain.StockRequest) error {
	return r.db.WithContext(ctx).Create(req).Error
}

func (r *Repository) GetRequest(ctx context.Context, id uuid.UUID) (*domain.StockRequest, error) {
	var req domain.StockRequest
	err := r.db.WithContext(ctx).Where("is_deleted = false").First(&req, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrRequestNotFound
	}
	if err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *Repository) ListRequests(ctx context.Context, status string) ([]domain.StockRequest, error) {
	q := r.db.WithContext(ctx).Where("is_deleted = false")
	switch status {
	case "pending":
		q = q.Where("purchase_order_id IS NULL")
	case "ordered":
		q = q.Where("purchase_order_id IS NOT NULL")
	}

	var rows []domain.StockRequest
	// Oldest need first: the product that ran out longest ago is the one the
	// shop has been losing sales on the longest.
	err := q.Order("needed_on ASC, created_at ASC").Find(&rows).Error
	return rows, err
}

func (r *Repository) UpdateRequest(ctx context.Context, req *domain.StockRequest) error {
	return r.db.WithContext(ctx).Model(req).
		Select("product_name", "needed_on", "notes").
		Updates(req).Error
}

func (r *Repository) DeleteRequest(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Model(&domain.StockRequest{}).
		Where("id = ? AND is_deleted = false AND purchase_order_id IS NULL", id).
		Update("is_deleted", true).Error
}

// --- Purchase orders ---

// CreateOrder writes an order, its lines, and marks its requests as ordered —
// all in one transaction, so an order can never exist while the requests it
// was made from still show as pending, or the reverse.
//
// The order number is the business's previous highest plus one, taken under a
// per-business advisory lock. Two owners placing orders at the same moment
// would otherwise both read the same maximum and collide on the unique
// constraint; with the lock, one simply waits a few milliseconds.
func (r *Repository) CreateOrder(ctx context.Context, o *domain.PurchaseOrder, requestIDs []uuid.UUID) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtext('purchase_order:' || ?::text)::bigint)`,
			o.BusinessID.String()).Error; err != nil {
			return fmt.Errorf("locking order numbers: %w", err)
		}

		if len(requestIDs) > 0 {
			// Every request must exist, belong to this business, and still be
			// pending — checked inside the transaction, after the lock, so two
			// orders cannot both claim the same request.
			var available int64
			if err := tx.Model(&domain.StockRequest{}).
				Where("id IN ? AND is_deleted = false AND purchase_order_id IS NULL", requestIDs).
				Count(&available).Error; err != nil {
				return fmt.Errorf("checking requests: %w", err)
			}
			if int(available) != len(requestIDs) {
				return ErrRequestUnavailable
			}
		}

		var highest int
		if err := tx.Model(&domain.PurchaseOrder{}).
			Select("COALESCE(MAX(order_number), 0)").
			Scan(&highest).Error; err != nil {
			return fmt.Errorf("numbering the order: %w", err)
		}
		o.OrderNumber = highest + 1

		lines := o.Lines
		o.Lines = nil // written explicitly below, with their business id
		if err := tx.Create(o).Error; err != nil {
			return fmt.Errorf("creating the order: %w", err)
		}
		for i := range lines {
			lines[i].PurchaseOrderID = o.ID
			lines[i].BusinessID = o.BusinessID
		}
		if err := tx.Create(&lines).Error; err != nil {
			return fmt.Errorf("creating order lines: %w", err)
		}
		o.Lines = lines

		if len(requestIDs) > 0 {
			// Through Model/Update so updated_at and change_seq move, and every
			// device learns the request is now on an order.
			if err := tx.Model(&domain.StockRequest{}).
				Where("id IN ?", requestIDs).
				Update("purchase_order_id", o.ID).Error; err != nil {
				return fmt.Errorf("marking requests ordered: %w", err)
			}
		}
		return nil
	})
}

func (r *Repository) GetOrder(ctx context.Context, id uuid.UUID) (*domain.PurchaseOrder, error) {
	var o domain.PurchaseOrder
	err := r.db.WithContext(ctx).
		Preload("Lines", func(db *gorm.DB) *gorm.DB { return db.Order("position") }).
		First(&o, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrOrderNotFound
	}
	if err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *Repository) ListOrders(ctx context.Context, status string) ([]domain.PurchaseOrder, error) {
	q := r.db.WithContext(ctx).
		Preload("Lines", func(db *gorm.DB) *gorm.DB { return db.Order("position") })
	if status == string(domain.OrderStatusOrdered) || status == string(domain.OrderStatusCancelled) {
		q = q.Where("status = ?", status)
	}
	var rows []domain.PurchaseOrder
	err := q.Order("order_number DESC").Find(&rows).Error
	return rows, err
}

// CancelOrder marks an order cancelled and puts its requests back in the draft.
// The order and its lines are kept: a cancelled order is still a record of what
// was once asked for, and its number is never reused.
func (r *Repository) CancelOrder(ctx context.Context, id uuid.UUID) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Model(&domain.PurchaseOrder{}).
			Where("id = ? AND status = ?", id, domain.OrderStatusOrdered).
			Update("status", domain.OrderStatusCancelled)
		if res.Error != nil {
			return fmt.Errorf("cancelling the order: %w", res.Error)
		}
		if res.RowsAffected == 0 {
			var exists int64
			tx.Model(&domain.PurchaseOrder{}).Where("id = ?", id).Count(&exists)
			if exists == 0 {
				return ErrOrderNotFound
			}
			return ErrOrderNotActive
		}
		return tx.Model(&domain.StockRequest{}).
			Where("purchase_order_id = ?", id).
			Update("purchase_order_id", nil).Error
	})
}

// Today is the business's current calendar date, in its own time zone.
func (r *Repository) Today(ctx context.Context) (time.Time, error) {
	return shopclock.Today(ctx, r.db)
}
