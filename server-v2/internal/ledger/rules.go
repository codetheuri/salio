package ledger

import (
	"errors"
	"strings"
	"time"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
)

// The rules every ledger write obeys, whichever path it arrives by.
//
// They live here, as plain functions, so the REST handlers and the sync engine
// call the same code. They were not shared at first, and drifted: the REST
// routes refused what sync accepted — staff voiding entries, deleting customers
// with money owing — because the app writes almost everything through sync and
// the rules had only ever been written into the routes it does not use.

// ErrDescriptionRequired refuses an entry with nothing saying what it was for.
//
// A bare "500" on a customer's account is the paper-notebook problem this app
// replaces: a month later nobody can say what it was, and the customer disputes
// it. Required on every new entry. Entries recorded before the rule existed are
// left alone — the rule governs writing, not history.
var ErrDescriptionRequired = errors.New("a description is required, saying what the debt or payment was for")

// MaxDescriptionLength bounds what a description can hold. Long enough for
// "3 bags DAP 50kg and 1 Duodip 20ml, to be paid after harvest".
const MaxDescriptionLength = 500

// ErrDescriptionTooLong refuses a description over MaxDescriptionLength.
var ErrDescriptionTooLong = errors.New("the description is longer than 500 characters")

var (
	// ErrMethodOnDebt: a debt is money not yet paid, so nothing paid it.
	ErrMethodOnDebt = errors.New("a debt has no payment method or reference; those belong on the payment")

	// ErrDueDateOnPayment: a payment is never "due".
	ErrDueDateOnPayment = errors.New("a payment has no due date; only a debt can fall due")

	// ErrDueBeforeDate: a debt cannot fall due before it was incurred.
	ErrDueBeforeDate = errors.New("the due date is before the date of the debt")
)

// ValidateEntry checks a new ledger entry, and normalises its reference — an
// M-Pesa code is stored upper-case, so the duplicate check sees one code
// however it was typed.
func ValidateEntry(t *domain.Transaction, loc *time.Location) error {
	if !t.Type.Valid() {
		return ErrInvalidType
	}
	if !t.Amount.IsPositive() {
		return ErrNonPositiveAmount
	}
	if t.Description == nil || strings.TrimSpace(*t.Description) == "" {
		return ErrDescriptionRequired
	}
	if len([]rune(*t.Description)) > MaxDescriptionLength {
		return ErrDescriptionTooLong
	}
	if t.TransactionDate.IsZero() {
		return ErrInvalidDate
	}

	if t.Type == domain.TypePayment {
		ref, err := payment.Settlement(t.PaymentMethod, t.Reference)
		if err != nil {
			return err
		}
		t.Reference = ref
		if t.DueDate != nil {
			return ErrDueDateOnPayment
		}
		return nil
	}

	// A debt.
	if t.PaymentMethod != nil || t.Reference != nil {
		return ErrMethodOnDebt
	}
	if t.DueDate != nil && domain.DueBefore(*t.DueDate, t.TransactionDate, loc) {
		return ErrDueBeforeDate
	}
	return nil
}

// CheckVoidable refuses voiding an entry that cannot be voided on its own.
//
// Who may void at all is a permission (transactions.void), checked by the
// caller. This is what may be voided: not the debt a credit sale created, which
// only goes when its sale does.
func CheckVoidable(t *domain.Transaction) error {
	if t.SaleID != nil {
		return ErrBelongsToSale
	}
	return nil
}

// IsRuleError reports whether err is a rule a new entry broke — answered with a
// 422 by the routes and reported as a conflict by sync. One list, so the two
// cannot drift apart again.
func IsRuleError(err error) bool {
	for _, rule := range []error{
		ErrInvalidType, ErrNonPositiveAmount, ErrDescriptionRequired, ErrDescriptionTooLong,
		ErrInvalidDate, ErrMethodOnDebt, ErrDueDateOnPayment, ErrDueBeforeDate,
	} {
		if errors.Is(err, rule) {
			return true
		}
	}
	return payment.IsRuleError(err)
}
