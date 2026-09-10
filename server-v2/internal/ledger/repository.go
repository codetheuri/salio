package ledger

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

var ErrNotFound = errors.New("transaction not found")

// ErrCustomerNotFound distinguishes a bad customer_id from a bad transaction_id
// — the caller-facing message differs, so the handler needs to tell them apart.
var ErrCustomerNotFound = errors.New("customer not found")

// ErrExceedsBalance means a payment is larger than what the customer currently
// owes. A ledger has no notion of a customer being in credit; a payment that
// size is very likely a typo, and rejecting it is cheaper than a phone call to
// undo an offsetting entry later.
var ErrExceedsBalance = errors.New("payment amount exceeds the customer's outstanding balance")

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
// Everything happens inside one transaction that holds a row lock on the
// customer for its duration. That lock is what makes the balance check
// meaningful: without it, two concurrent payments can each read the same
// starting balance, each see themselves as within it, and together take the
// customer negative — the classic read-then-write race, here on money instead
// of inventory. Debts have no upper bound to protect, but they share the lock
// anyway so every write against one customer serialises with every other,
// keeping the rule simple to reason about rather than correct only for one
// transaction type.
func (r *Repository) Create(ctx context.Context, t *domain.Transaction) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// SELECT ... FOR UPDATE. Ordinary reads are unaffected — only a second
		// writer touching the same customer waits, and only until this
		// transaction commits or rolls back.
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

		if t.Type == domain.TypePayment {
			var balance money.Amount
			err := tx.Model(&domain.Transaction{}).
				Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
				Where("customer_id = ? AND is_deleted = false", t.CustomerID).
				Scan(&balance).Error
			if err != nil {
				return fmt.Errorf("computing balance: %w", err)
			}
			if t.Amount.Minor() > balance.Minor() {
				return ErrExceedsBalance
			}
		}

		if err := tx.Create(t).Error; err != nil {
			return fmt.Errorf("creating transaction: %w", err)
		}
		return nil
	})
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*domain.Transaction, error) {
	var t domain.Transaction
	err := r.db.WithContext(ctx).First(&t, "id = ?", id).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &t, err
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
