package payment_test

import (
	"errors"
	"testing"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
)

func ptr[T any](v T) *T { return &v }

func TestReference_NormalisesAnMpesaCode(t *testing.T) {
	got, err := payment.Reference(domain.PaymentMpesa, ptr("  sjk4x7y2pq "))
	if err != nil || got == nil || *got != "SJK4X7Y2PQ" {
		t.Fatalf("got %v, %v; want SJK4X7Y2PQ", got, err)
	}
}

func TestReference_RefusesWhatCannotBeAnMpesaCode(t *testing.T) {
	for _, code := range []string{"SJK4X7Y2P", "SJK4X7Y2PQR", "SJK4X7-2PQ", "SJK 4X7Y2P"} {
		if _, err := payment.Reference(domain.PaymentMpesa, ptr(code)); !errors.Is(err, payment.ErrInvalidMpesaCode) {
			t.Errorf("Reference(mpesa, %q) = %v, want ErrInvalidMpesaCode", code, err)
		}
	}
}

func TestReference_BlankIsNone(t *testing.T) {
	for _, m := range []domain.PaymentMethod{domain.PaymentCash, domain.PaymentMpesa, domain.PaymentBank} {
		if got, err := payment.Reference(m, ptr("   ")); err != nil || got != nil {
			t.Errorf("Reference(%s, blank) = %v, %v; want nil, nil", m, got, err)
		}
	}
}

func TestReference_CashHasNone(t *testing.T) {
	if _, err := payment.Reference(domain.PaymentCash, ptr("ABC")); !errors.Is(err, payment.ErrCashHasNoRef) {
		t.Fatalf("got %v, want ErrCashHasNoRef", err)
	}
}

func TestSettlement_NeedsAMethodThatMovedMoney(t *testing.T) {
	if _, err := payment.Settlement(nil, nil); !errors.Is(err, payment.ErrMethodRequired) {
		t.Errorf("no method: got %v, want ErrMethodRequired", err)
	}
	credit := domain.PaymentCredit
	if _, err := payment.Settlement(&credit, nil); !errors.Is(err, payment.ErrInvalidMethod) {
		t.Errorf("credit: got %v, want ErrInvalidMethod — a payment is money that moved", err)
	}
	bank := domain.PaymentBank
	if got, err := payment.Settlement(&bank, ptr("FT2310ABC")); err != nil || *got != "FT2310ABC" {
		t.Errorf("bank: got %v, %v", got, err)
	}
}
