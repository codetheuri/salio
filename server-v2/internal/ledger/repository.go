package ledger

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
	"salio/server-v2/internal/shopclock"
)

var ErrNotFound = errors.New("transaction not found")

// ErrCustomerNotFound distinguishes a bad customer_id from a bad transaction_id
// — the caller-facing message differs, so the handler needs to tell them apart.
var ErrCustomerNotFound = errors.New("customer not found")

// ErrBelongsToSale refuses voiding the debt a credit sale created. Voiding it
// alone would leave a sale recorded as sold on credit with nothing owed for it;
// the sale is voided instead, which voids its debt with it.
var ErrBelongsToSale = errors.New("this debt came from a sale; void the sale instead")

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

func (r *Repository) ListForCustomer(ctx context.Context, customerID uuid.UUID) ([]domain.Transaction, error) {
	var txs []domain.Transaction
	err := r.db.WithContext(ctx).
		Where("customer_id = ? AND is_deleted = false", customerID).
		Order("transaction_date DESC, created_at DESC").
		Find(&txs).Error
	return txs, err
}

// Create records a debt or a payment.
//
// A payment larger than the balance is accepted: the difference is an advance,
// held on the customer's account as a negative balance and used up by the next
// debts. Shops take deposits and pre-payments routinely, and refusing them made
// the ledger unable to record what actually happened at the counter.
//
// The customer row is still locked for the duration. Its job is no longer a
// balance ceiling but serialising against deletion: a customer may only be
// deleted at a zero balance (see customer.DeleteIfSettled), and without the lock
// a debt recorded in the instant between that check and the delete would leave a
// deleted customer who still owes money.
func (r *Repository) Create(ctx context.Context, t *domain.Transaction) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var customer domain.Customer
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("is_deleted = false").
			First(&customer, "id = ?", t.CustomerID).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrCustomerNotFound
		}
		if err != nil {
			return fmt.Errorf("locking customer: %w", err)
		}

		if err := tx.Create(t).Error; err != nil {
			if payment.IsDuplicateMpesaRef(err) {
				return payment.ErrDuplicateMpesaRef
			}
			return fmt.Errorf("creating transaction: %w", err)
		}
		return nil
	})
}

// GetByID returns one transaction, voided or not.
//
// Voided entries are included on purpose: someone looking up an entry to ask
// "what happened to that 500?" needs to see that it was voided, not be told it
// never existed.
func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Transaction, error) {
	var t domain.Transaction
	err := r.db.WithContext(ctx).First(&t, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// Void soft-deletes a transaction. Refuses one that is already voided or does
// not exist — both look identical to the caller, same reasoning as
// customer.ErrNotFound: a 404 either way reveals nothing about which it was.
//
// updated_at is not set by hand here. domain.Transaction's UpdatedAt is a plain
// GORM-convention field, so GORM stamps it on every Update automatically. This
// is the structural fix for the v1 defect where a hand-written SQL UPDATE
// forgot to bump updated_at on soft-delete and voided transactions silently
// never reached sync: there is no SQL string here to forget a column in.
func (r *Repository) Void(ctx context.Context, id uuid.UUID) error {
	t, err := r.GetByID(ctx, id)
	if err != nil {
		return err
	}
	if err := CheckVoidable(t); err != nil {
		return err
	}

	res := r.db.WithContext(ctx).
		Model(&domain.Transaction{}).
		Where("id = ? AND is_deleted = false", id).
		Update("is_deleted", true)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

// Today is the business's current calendar date, in its own time zone.
func (r *Repository) Today(ctx context.Context) (time.Time, error) {
	return shopclock.Today(ctx, r.db)
}
