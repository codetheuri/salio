// Package sales records what a shop sells: the product, how many, for how much,
// and whether it was paid in cash or put on a customer's account.
package sales

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
)

// The rules every sale obeys, whichever path it arrives by. Plain functions over
// a *gorm.DB, so the REST handlers and the sync engine run the same code inside
// their own transactions — the lesson of the ledger, whose rules lived only in
// the REST path and so did not apply to the app at all.

var (
	ErrNotFound             = errors.New("sale not found")
	ErrProductRequired      = errors.New("a product name is required")
	ErrProductTooLong       = errors.New("the product name is longer than 255 characters")
	ErrNonPositiveQuantity  = errors.New("quantity must be greater than zero")
	ErrNonPositiveAmount    = errors.New("amount must be greater than zero")
	ErrInvalidPaymentMethod = errors.New(`payment_method must be "cash", "mpesa", "bank" or "credit"`)
	ErrDueDateNotCredit     = errors.New("only a credit sale has a due date")
	ErrCreditHasNoRef       = errors.New("a credit sale has no payment reference; record it on the payment when the customer pays")
	ErrDueBeforeDate        = errors.New("the due date is before the date of the sale")
	ErrCreditNeedsCustomer  = errors.New("a credit sale needs a customer, so somebody owes the money")
	ErrCustomerNotFound     = errors.New("customer not found")
	ErrInvalidDate          = errors.New("sale_date must be in YYYY-MM-DD format")
	ErrDebtMismatch         = errors.New("a debt already exists for this sale and does not match it")
)

// Validate checks a sale on its own terms, before anything touches the database.
func Validate(s *domain.Sale) error {
	s.ProductName = strings.TrimSpace(s.ProductName)
	switch {
	case s.ProductName == "":
		return ErrProductRequired
	case len([]rune(s.ProductName)) > 255:
		return ErrProductTooLong
	case !s.Quantity.IsPositive():
		return ErrNonPositiveQuantity
	case !s.Amount.IsPositive():
		return ErrNonPositiveAmount
	case !s.PaymentMethod.Valid():
		return ErrInvalidPaymentMethod
	case s.PaymentMethod == domain.PaymentCredit && s.CustomerID == nil:
		return ErrCreditNeedsCustomer
	case s.SaleDate.IsZero():
		return ErrInvalidDate
	}

	if s.PaymentMethod == domain.PaymentCredit {
		if s.Reference != nil && strings.TrimSpace(*s.Reference) != "" {
			return ErrCreditHasNoRef
		}
		s.Reference = nil
		if s.DueDate != nil && s.DueDate.Before(s.SaleDate) {
			return ErrDueBeforeDate
		}
		return nil
	}

	if s.DueDate != nil {
		return ErrDueDateNotCredit
	}
	ref, err := payment.Reference(s.PaymentMethod, s.Reference)
	if err != nil {
		return err
	}
	s.Reference = ref
	return nil
}

// IsRuleError reports whether err is a rule a sale broke — a 422 from the
// routes, a conflict from sync. One list for both.
func IsRuleError(err error) bool {
	for _, rule := range []error{
		ErrProductRequired, ErrProductTooLong, ErrNonPositiveQuantity, ErrNonPositiveAmount,
		ErrInvalidPaymentMethod, ErrCreditNeedsCustomer, ErrInvalidDate,
		ErrDueDateNotCredit, ErrDueBeforeDate, ErrCreditHasNoRef,
	} {
		if errors.Is(err, rule) {
			return true
		}
	}
	return payment.IsRuleError(err)
}

// DebtDescription is what a credit sale's debt says on the customer's account.
//
// Generated rather than typed, so a statement shows exactly what was bought —
// "Sale: DAP 50kg x 2" — and the phone and the server write the same words.
func DebtDescription(s *domain.Sale) string {
	return fmt.Sprintf("Sale: %s x %s", s.ProductName, s.Quantity)
}

// Record inserts a sale, and for a credit sale, the debt it puts on the
// customer's account. db should already be a transaction: the sale and its debt
// are written together or not at all.
//
// The debt's id is domain.SaleDebtID(sale.ID). A phone that recorded the sale
// offline may have created that same debt locally for an immediate balance; the
// server always creates its own from the sale, and a debt pushed by a phone is
// ignored by sync. One source of truth, so a sale can never put two debts on an
// account, or a debt that disagrees with the sale.
func Record(ctx context.Context, db *gorm.DB, s *domain.Sale) error {
	if err := Validate(s); err != nil {
		return err
	}

	if s.CustomerID != nil {
		// Locked, the same lock ledger.Create and customer.DeleteIfSettled
		// take: a credit sale landing in the instant a customer is being
		// deleted at a zero balance would otherwise leave a deleted customer
		// owing money.
		var c domain.Customer
		err := db.WithContext(ctx).Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("is_deleted = false").
			First(&c, "id = ?", *s.CustomerID).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrCustomerNotFound
		}
		if err != nil {
			return fmt.Errorf("checking customer: %w", err)
		}
	}

	if err := db.WithContext(ctx).Create(s).Error; err != nil {
		if payment.IsDuplicateMpesaRef(err) {
			return payment.ErrDuplicateMpesaRef
		}
		return fmt.Errorf("recording sale: %w", err)
	}

	if s.PaymentMethod != domain.PaymentCredit {
		return nil
	}

	description := DebtDescription(s)
	saleID := s.ID
	debt := domain.Transaction{
		ID:              domain.SaleDebtID(s.ID),
		BusinessID:      s.BusinessID,
		CustomerID:      *s.CustomerID,
		UserID:          s.UserID,
		Type:            domain.TypeDebt,
		Amount:          s.Amount,
		Description:     &description,
		TransactionDate: s.SaleDate,
		DueDate:         s.DueDate,
		SaleID:          &saleID,
	}
	if err := db.WithContext(ctx).Create(&debt).Error; err != nil {
		return fmt.Errorf("recording the sale's debt: %w", err)
	}
	return nil
}

// Void voids a sale, and the debt a credit sale created with it.
//
// Who may void is the sales.void permission, checked by the caller. Here: a
// sale that is already voided, or not this business's, is not found.
func Void(ctx context.Context, db *gorm.DB, saleID uuid.UUID) error {
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		res := tx.Model(&domain.Sale{}).
			Where("id = ? AND is_deleted = false", saleID).
			Update("is_deleted", true)
		if res.Error != nil {
			return fmt.Errorf("voiding sale: %w", res.Error)
		}
		if res.RowsAffected == 0 {
			return ErrNotFound
		}

		// Through Model/Update, so updated_at moves and the void reaches every
		// device. A void that does not bump the sync marker is the v1 defect
		// that kept voided entries off other phones entirely.
		if err := tx.Model(&domain.Transaction{}).
			Where("sale_id = ? AND is_deleted = false", saleID).
			Update("is_deleted", true).Error; err != nil {
			return fmt.Errorf("voiding the sale's debt: %w", err)
		}
		return nil
	})
}
