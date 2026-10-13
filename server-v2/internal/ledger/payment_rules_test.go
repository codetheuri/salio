package ledger_test

import (
	"errors"
	"testing"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/payment"
)

func mpesa(f fixture, t *testing.T, amount, code string) ledger.CreateInput {
	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, amount)
	in.Body.Description = "paid by M-Pesa"
	m := domain.PaymentMpesa
	in.Body.PaymentMethod, in.Body.Reference = &m, &code
	return in
}

func TestPayment_AnMpesaCodeIsStoredInCapitalsAndRecordedOnce(t *testing.T) {
	f := newFixture(t)

	v, err := f.svc.Create(f.ctx, f.userID, mpesa(f, t, "500", " sjk4x7y2pq "))
	if err != nil {
		t.Fatalf("payment: %v", err)
	}
	if v.Reference == nil || *v.Reference != "SJK4X7Y2PQ" || v.PaymentMethod == nil || *v.PaymentMethod != domain.PaymentMpesa {
		t.Fatalf("recorded %v / %v, want mpesa SJK4X7Y2PQ", v.PaymentMethod, v.Reference)
	}

	// The same M-Pesa payment entered a second time — the dispute this exists
	// to settle, and the double credit it exists to prevent.
	if _, err := f.svc.Create(f.ctx, f.userID, mpesa(f, t, "500", "SJK4X7Y2PQ")); !errors.Is(err, payment.ErrDuplicateMpesaRef) {
		t.Fatalf("second entry of one code: got %v, want ErrDuplicateMpesaRef", err)
	}

	// Voiding the first frees the code, so a mistaken entry can be corrected.
	if err := f.svc.Void(f.ctx, v.ID); err != nil {
		t.Fatalf("void: %v", err)
	}
	if _, err := f.svc.Create(f.ctx, f.userID, mpesa(f, t, "450", "SJK4X7Y2PQ")); err != nil {
		t.Fatalf("re-entering the code after a void: %v", err)
	}
}

func TestPayment_RulesForMethodsAndDueDates(t *testing.T) {
	f := newFixture(t)
	cases := []struct {
		name  string
		build func() ledger.CreateInput
		want  error
	}{
		{"a payment without a method", func() ledger.CreateInput {
			in := mpesa(f, t, "100", "SJK4X7Y2PQ")
			in.Body.PaymentMethod, in.Body.Reference = nil, nil
			return in
		}, payment.ErrMethodRequired},
		{"a mistyped M-Pesa code", func() ledger.CreateInput {
			return mpesa(f, t, "100", "SJK4X7Y2P")
		}, payment.ErrInvalidMpesaCode},
		{"a debt with a method", func() ledger.CreateInput {
			in := mpesa(f, t, "100", "SJK4X7Y2PQ")
			in.Body.Type = domain.TypeDebt
			return in
		}, ledger.ErrMethodOnDebt},
		{"a payment with a due date", func() ledger.CreateInput {
			in := mpesa(f, t, "100", "SJK4X7Y2PQ")
			due := "2099-01-01"
			in.Body.DueDate = &due
			return in
		}, ledger.ErrDueDateOnPayment},
		{"a debt due before it was incurred", func() ledger.CreateInput {
			var in ledger.CreateInput
			in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "100")
			in.Body.Description = "seed"
			date, due := "2026-10-10", "2026-10-01"
			in.Body.TransactionDate, in.Body.DueDate = &date, &due
			return in
		}, ledger.ErrDueBeforeDate},
	}
	for _, c := range cases {
		if _, err := f.svc.Create(f.ctx, f.userID, c.build()); !errors.Is(err, c.want) {
			t.Errorf("%s: got %v, want %v", c.name, err, c.want)
		}
	}
}

func TestDebt_KeepsItsDueDate(t *testing.T) {
	f := newFixture(t)
	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "3500")
	in.Body.Description = "DAP 50kg, to pay after harvest"
	date, due := "2026-10-10", "2026-12-15"
	in.Body.TransactionDate, in.Body.DueDate = &date, &due

	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("debt: %v", err)
	}
	got, err := f.svc.Get(f.ctx, v.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.DueDate == nil || got.DueDate.Format("2006-01-02") != due {
		t.Fatalf("due date = %v, want %s", got.DueDate, due)
	}
}
