package customer_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

func TestCreditLimit_ShowsWhatIsLeftAndWhenItIsExceeded(t *testing.T) {
	svc, db, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	var in customer.CreateInput
	in.Body.Name = "Wanjiku"
	c, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if c.CreditLimit != nil || c.AvailableCredit != nil || c.OverLimit {
		t.Fatalf("a new customer has a limit: %+v", c)
	}

	limit, _ := money.Parse("5000.00")
	v, err := svc.SetCreditLimit(ctx, c.ID, &limit)
	if err != nil {
		t.Fatalf("set limit: %v", err)
	}
	if v.AvailableCredit == nil || v.AvailableCredit.String() != "5000.00" {
		t.Fatalf("available = %v, want 5000.00", v.AvailableCredit)
	}

	// The limit warns; it never stops a debt being recorded.
	amt, _ := money.Parse("6200.00")
	debt := domain.Transaction{CustomerID: c.ID, UserID: userID, Type: domain.TypeDebt, Amount: amt, TransactionDate: time.Now()}
	if err := db.WithContext(ctx).Create(&debt).Error; err != nil {
		t.Fatalf("debt over the limit: %v", err)
	}
	got, err := svc.Get(ctx, c.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if !got.OverLimit || got.AvailableCredit.String() != "-1200.00" {
		t.Fatalf("over_limit = %v, available = %s; want true and -1200.00", got.OverLimit, got.AvailableCredit)
	}

	// Removing the limit.
	cleared, err := svc.SetCreditLimit(ctx, c.ID, nil)
	if err != nil {
		t.Fatalf("clear limit: %v", err)
	}
	if cleared.CreditLimit != nil || cleared.OverLimit {
		t.Fatalf("after clearing: %+v", cleared)
	}
}

func TestCreditLimit_CannotBeNegative(t *testing.T) {
	svc, _, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)
	var in customer.CreateInput
	in.Body.Name = "Wanjiku"
	c, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	negative, _ := money.Parse("-1.00")
	if _, err := svc.SetCreditLimit(ctx, c.ID, &negative); !errors.Is(err, customer.ErrNegativeCreditLimit) {
		t.Fatalf("got %v, want ErrNegativeCreditLimit", err)
	}
	zero := money.Amount(0)
	if _, err := svc.SetCreditLimit(ctx, c.ID, &zero); err != nil {
		t.Fatalf("a zero limit — no credit for this customer — is a real choice: %v", err)
	}
}
