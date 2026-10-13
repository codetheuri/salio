package sales_test

import (
	"errors"
	"testing"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
	"salio/server-v2/internal/sales"
)

func TestSale_PaidByMpesaKeepsItsCodeOnce(t *testing.T) {
	f := newFixture(t)
	in := input(nil, domain.PaymentMpesa, "DAP 50kg", "1", "3500.00")
	code := "rbx9k2m4p1"
	in.Body.Reference = &code

	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("sale: %v", err)
	}
	if v.Reference == nil || *v.Reference != "RBX9K2M4P1" {
		t.Fatalf("reference = %v, want RBX9K2M4P1", v.Reference)
	}
	if f.balance(t).String() != "0.00" {
		t.Fatalf("an M-Pesa sale changed a balance to %s", f.balance(t))
	}

	again := input(nil, domain.PaymentMpesa, "Duodip 20ml", "1", "3500.00")
	again.Body.Reference = &code
	if _, err := f.svc.Create(f.ctx, f.userID, again); !errors.Is(err, payment.ErrDuplicateMpesaRef) {
		t.Fatalf("a second sale on one code: got %v, want ErrDuplicateMpesaRef", err)
	}
}

func TestSale_ACreditSalesDueDateIsOnItsDebt(t *testing.T) {
	f := newFixture(t)
	in := input(&f.customer, domain.PaymentCredit, "DAP 50kg", "2", "7000.00")
	date, due := "2026-10-10", "2027-01-20"
	in.Body.SaleDate, in.Body.DueDate = &date, &due

	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("sale: %v", err)
	}
	var debt domain.Transaction
	if err := f.db.WithContext(f.ctx).First(&debt, "id = ?", *v.DebtTransactionID).Error; err != nil {
		t.Fatalf("loading the sale's debt: %v", err)
	}
	if debt.DueDate == nil || debt.DueDate.Format("2006-01-02") != due {
		t.Fatalf("the debt's due date = %v, want %s", debt.DueDate, due)
	}
}

func TestSale_RulesForReferencesAndDueDates(t *testing.T) {
	f := newFixture(t)

	cashWithDue := input(nil, domain.PaymentCash, "DAP 50kg", "1", "3500.00")
	due := "2099-01-01"
	cashWithDue.Body.DueDate = &due
	if _, err := f.svc.Create(f.ctx, f.userID, cashWithDue); !errors.Is(err, sales.ErrDueDateNotCredit) {
		t.Errorf("a cash sale with a due date: got %v", err)
	}

	creditWithRef := input(&f.customer, domain.PaymentCredit, "DAP 50kg", "1", "3500.00")
	ref := "SJK4X7Y2PQ"
	creditWithRef.Body.Reference = &ref
	if _, err := f.svc.Create(f.ctx, f.userID, creditWithRef); !errors.Is(err, sales.ErrCreditHasNoRef) {
		t.Errorf("a credit sale with an M-Pesa code: got %v", err)
	}

	bank := input(nil, domain.PaymentBank, "Knapsack sprayer", "1", "4200.00")
	bankRef := "FT23101400123"
	bank.Body.Reference = &bankRef
	if _, err := f.svc.Create(f.ctx, f.userID, bank); err != nil {
		t.Errorf("a bank sale: %v", err)
	}
}
