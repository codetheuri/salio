// Package payment holds the rules for how money moved — the method and the
// reference — shared by customer payments, sales and supplier payments, so the
// three cannot disagree about what a valid M-Pesa code looks like.
package payment

import (
	"errors"
	"regexp"
	"strings"

	"salio/server-v2/internal/domain"
)

var (
	ErrMethodRequired = errors.New(`a payment needs a payment_method: "cash", "mpesa" or "bank"`)
	ErrInvalidMethod  = errors.New(`payment_method must be "cash", "mpesa" or "bank"`)

	// ErrInvalidMpesaCode catches the typo before it becomes a dispute nobody
	// can settle: a code with a letter missing matches no SMS.
	ErrInvalidMpesaCode = errors.New("an M-Pesa code is 10 letters and digits, e.g. SJK4X7Y2PQ")

	ErrReferenceTooLong  = errors.New("the reference is longer than 30 characters")
	ErrCashHasNoRef      = errors.New("a cash payment has no reference; leave it out")
	ErrDuplicateMpesaRef = errors.New("this M-Pesa code is already recorded on another payment")
)

// MaxReferenceLength bounds a bank reference. M-Pesa codes are exactly 10.
const MaxReferenceLength = 30

var mpesaCode = regexp.MustCompile(`^[A-Z0-9]{10}$`)

// Reference validates and normalises the reference for a payment made by m.
//
// Blank means none. An M-Pesa code is upper-cased, as Safaricom prints it, so
// "sjk4x7y2pq" typed on a phone and "SJK4X7Y2PQ" pasted from the SMS are the
// same code to the duplicate check.
func Reference(m domain.PaymentMethod, ref *string) (*string, error) {
	if ref == nil {
		return nil, nil
	}
	r := strings.TrimSpace(*ref)
	if r == "" {
		return nil, nil
	}
	switch m {
	case domain.PaymentMpesa:
		r = strings.ToUpper(r)
		if !mpesaCode.MatchString(r) {
			return nil, ErrInvalidMpesaCode
		}
	case domain.PaymentBank:
		if len([]rune(r)) > MaxReferenceLength {
			return nil, ErrReferenceTooLong
		}
	default:
		return nil, ErrCashHasNoRef
	}
	return &r, nil
}

// Settlement checks the method and reference of money that actually moved — a
// payment in or out. Returns the normalised reference.
func Settlement(m *domain.PaymentMethod, ref *string) (*string, error) {
	if m == nil || *m == "" {
		return nil, ErrMethodRequired
	}
	if !m.Settles() {
		return nil, ErrInvalidMethod
	}
	return Reference(*m, ref)
}

// IsDuplicateMpesaRef reports whether err is one of the unique indexes that
// stop one M-Pesa code being recorded twice (migration 00008).
func IsDuplicateMpesaRef(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "idx_transactions_mpesa_ref") ||
		strings.Contains(msg, "idx_sales_mpesa_ref") ||
		strings.Contains(msg, "idx_supplier_tx_mpesa_ref")
}

// IsRuleError reports whether err is one of this package's rule violations —
// the record's fault, answered with a 422 or a sync conflict.
func IsRuleError(err error) bool {
	for _, rule := range []error{
		ErrMethodRequired, ErrInvalidMethod, ErrInvalidMpesaCode, ErrReferenceTooLong, ErrCashHasNoRef,
	} {
		if errors.Is(err, rule) {
			return true
		}
	}
	return false
}
