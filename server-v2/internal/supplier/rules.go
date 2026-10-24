// Package supplier records who the shop buys from and what it owes them: the
// customer ledger turned around. A bill is goods received on credit, a payment
// is the shop paying it, and the balance is always derived from the two.
package supplier

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/payment"
	"salio/server-v2/internal/phone"
)

// The rules every supplier write obeys, whichever path it arrives by. Plain
// functions over a *gorm.DB, so the REST handlers and the sync engine run the
// same code inside their own transactions.

var (
	ErrNotFound      = errors.New("supplier not found")
	ErrEntryNotFound = errors.New("supplier entry not found")
	ErrNameRequired  = errors.New("a supplier needs a name")
	ErrNameTooLong   = errors.New("the supplier name is longer than 255 characters")

	// ErrHasBalance mirrors customer.ErrHasBalance: deleting a supplier is
	// tidying up, not settling a debt. Either side being owed money keeps them.
	ErrHasBalance = errors.New("cannot delete a supplier with a non-zero balance: settle what the shop owes them, or the prepayment they hold, first")

	ErrInvalidType         = errors.New(`type must be "bill" or "payment"`)
	ErrNonPositiveAmount   = errors.New("amount must be greater than zero")
	ErrDescriptionRequired = errors.New("a description is required, saying what the bill or payment was for")
	ErrDescriptionTooLong  = errors.New("the description is longer than 500 characters")
	ErrInvalidDate         = errors.New("dates must be in YYYY-MM-DD format")
	ErrMethodOnBill        = errors.New("a bill has no payment method or reference; those belong on the payment")
	ErrDueDateOnPayment    = errors.New("a payment has no due date; only a bill can fall due")
	ErrDueBeforeDate       = errors.New("the due date is before the date of the bill")
	ErrOrderOnPayment      = errors.New("only a bill can be linked to a purchase order")
	ErrOrderNotFound       = errors.New("purchase order not found")
	ErrOrderCancelled      = errors.New("that purchase order was cancelled")
)

const maxDescriptionLength = 500

// ValidateSupplier checks a supplier and trims its text.
func ValidateSupplier(s *domain.Supplier) error {
	s.Name = strings.TrimSpace(s.Name)
	s.Notes = blankToNil(s.Notes)
	number, err := phone.Optional(s.Phone)
	if err != nil {
		return err
	}
	s.Phone = number
	switch {
	case s.Name == "":
		return ErrNameRequired
	case len([]rune(s.Name)) > 255:
		return ErrNameTooLong
	}
	return nil
}

// ValidateEntry checks a new bill or payment and normalises its reference.
func ValidateEntry(t *domain.SupplierTransaction) error {
	t.Description = strings.TrimSpace(t.Description)
	switch {
	case !t.Type.Valid():
		return ErrInvalidType
	case !t.Amount.IsPositive():
		return ErrNonPositiveAmount
	case t.Description == "":
		return ErrDescriptionRequired
	case len([]rune(t.Description)) > maxDescriptionLength:
		return ErrDescriptionTooLong
	case t.TransactionDate.IsZero():
		return ErrInvalidDate
	}

	if t.Type == domain.SupplierPayment {
		ref, err := payment.Settlement(t.PaymentMethod, t.Reference)
		if err != nil {
			return err
		}
		t.Reference = ref
		switch {
		case t.DueDate != nil:
			return ErrDueDateOnPayment
		case t.PurchaseOrderID != nil:
			return ErrOrderOnPayment
		}
		return nil
	}

	if t.PaymentMethod != nil || t.Reference != nil {
		return ErrMethodOnBill
	}
	if t.DueDate != nil && t.DueDate.Before(t.TransactionDate) {
		return ErrDueBeforeDate
	}
	return nil
}

// IsRuleError reports whether err is a rule a supplier write broke — a 422 from
// the routes, a conflict from sync. One list for both.
func IsRuleError(err error) bool {
	for _, rule := range []error{
		ErrNameRequired, ErrNameTooLong, ErrInvalidType, ErrNonPositiveAmount,
		ErrDescriptionRequired, ErrDescriptionTooLong, ErrInvalidDate, ErrMethodOnBill,
		ErrDueDateOnPayment, ErrDueBeforeDate, ErrOrderOnPayment, ErrOrderNotFound, ErrOrderCancelled,
		phone.ErrInvalid,
	} {
		if errors.Is(err, rule) {
			return true
		}
	}
	return payment.IsRuleError(err)
}

// Record inserts a bill or payment. db should already be a transaction.
//
// The supplier row is locked, as ledger.Create locks the customer: deletion is
// allowed only at a zero balance, and an entry landing between that check and
// the delete would leave a deleted supplier still owed money.
func Record(ctx context.Context, db *gorm.DB, t *domain.SupplierTransaction) error {
	if err := ValidateEntry(t); err != nil {
		return err
	}

	var s domain.Supplier
	err := db.WithContext(ctx).Clauses(clause.Locking{Strength: "UPDATE"}).
		Where("is_deleted = false").
		First(&s, "id = ?", t.SupplierID).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("locking supplier: %w", err)
	}

	if t.PurchaseOrderID != nil {
		// Checked here, through the tenant-scoped read, rather than left to the
		// foreign key: a foreign-key check does not go through row-level
		// security, so another shop's order id would satisfy it.
		var o domain.PurchaseOrder
		err := db.WithContext(ctx).Select("id", "status").First(&o, "id = ?", *t.PurchaseOrderID).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrOrderNotFound
		}
		if err != nil {
			return fmt.Errorf("checking purchase order: %w", err)
		}
		if o.Status == domain.OrderStatusCancelled {
			return ErrOrderCancelled
		}
	}

	if err := db.WithContext(ctx).Create(t).Error; err != nil {
		if payment.IsDuplicateMpesaRef(err) {
			return payment.ErrDuplicateMpesaRef
		}
		return fmt.Errorf("recording supplier entry: %w", err)
	}
	return nil
}

// Void voids a bill or payment. One already voided, or not this business's, is
// not found.
func Void(ctx context.Context, db *gorm.DB, id uuid.UUID) error {
	res := db.WithContext(ctx).Model(&domain.SupplierTransaction{}).
		Where("id = ? AND is_deleted = false", id).
		Update("is_deleted", true)
	if res.Error != nil {
		return fmt.Errorf("voiding supplier entry: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return ErrEntryNotFound
	}
	return nil
}

// DeleteIfSettled soft-deletes a supplier at a balance of exactly zero, under a
// lock on the supplier row — see customer.DeleteIfSettled, which this mirrors.
func DeleteIfSettled(ctx context.Context, db *gorm.DB, id uuid.UUID) error {
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		var s domain.Supplier
		err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("is_deleted = false").
			First(&s, "id = ?", id).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("locking supplier: %w", err)
		}

		balance, err := balanceOf(ctx, tx, id)
		if err != nil {
			return err
		}
		if balance != 0 {
			return ErrHasBalance
		}
		return tx.Model(&domain.Supplier{}).Where("id = ?", id).Update("is_deleted", true).Error
	})
}

// balanceSQL is what the shop owes: bills add, payments subtract.
const balanceSQL = "COALESCE(SUM(CASE WHEN type = 'bill' THEN amount ELSE -amount END), 0)"

func balanceOf(ctx context.Context, db *gorm.DB, supplierID uuid.UUID) (money.Amount, error) {
	var balance money.Amount
	err := db.WithContext(ctx).Model(&domain.SupplierTransaction{}).
		Select(balanceSQL).
		Where("supplier_id = ? AND is_deleted = false", supplierID).
		Scan(&balance).Error
	if err != nil {
		return 0, fmt.Errorf("computing supplier balance: %w", err)
	}
	return balance, nil
}

func blankToNil(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}

// parseDate reads an optional YYYY-MM-DD.
func parseDate(s *string) (*time.Time, error) {
	if s == nil || strings.TrimSpace(*s) == "" {
		return nil, nil
	}
	t, err := time.Parse("2006-01-02", strings.TrimSpace(*s))
	if err != nil {
		return nil, ErrInvalidDate
	}
	return &t, nil
}
