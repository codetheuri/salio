package sales_test

import (
	"context"
	"errors"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
	"salio/server-v2/internal/sales"
	"salio/server-v2/internal/testsupport"
)

type fixture struct {
	db       *gorm.DB
	svc      *sales.Service
	ctx      context.Context
	userID   uuid.UUID
	customer uuid.UUID
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	db := testsupport.Connect(t)

	b := &domain.Business{Name: "Test Shop"}
	if err := tenant.Unscoped(db).Create(b).Error; err != nil {
		t.Fatalf("business: %v", err)
	}
	ctx := tenant.WithTenant(context.Background(), b.ID)
	u := &domain.User{Name: "Owner", Phone: uuid.New().String()[:12], PasswordHash: "x", Role: domain.RoleOwner, IsActive: true}
	if err := db.WithContext(ctx).Create(u).Error; err != nil {
		t.Fatalf("user: %v", err)
	}
	c := &domain.Customer{Name: "Mama Mboga", CreatedBy: u.ID}
	if err := db.WithContext(ctx).Create(c).Error; err != nil {
		t.Fatalf("customer: %v", err)
	}
	return fixture{db: db, svc: sales.NewService(sales.NewRepository(db)), ctx: ctx, userID: u.ID, customer: c.ID}
}

func input(customer *uuid.UUID, method domain.PaymentMethod, product, qty, amount string) sales.CreateInput {
	var in sales.CreateInput
	in.Body.ProductName = product
	in.Body.Quantity, _ = quantity.Parse(qty)
	in.Body.Amount, _ = money.Parse(amount)
	in.Body.PaymentMethod = method
	in.Body.CustomerID = customer
	return in
}

func (f fixture) balance(t *testing.T) money.Amount {
	t.Helper()
	var b money.Amount
	if err := f.db.WithContext(f.ctx).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ? AND is_deleted = false", f.customer).Scan(&b).Error; err != nil {
		t.Fatalf("balance: %v", err)
	}
	return b
}

func TestCreate_ACreditSalePutsItsDebtOnTheAccount(t *testing.T) {
	f := newFixture(t)
	v, err := f.svc.Create(f.ctx, f.userID, input(&f.customer, domain.PaymentCredit, "DAP 50kg", "2", "7000.00"))
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if f.balance(t).String() != "7000.00" {
		t.Fatalf("balance = %s, want 7000.00", f.balance(t))
	}
	if v.DebtTransactionID == nil || *v.DebtTransactionID != domain.SaleDebtID(v.ID) {
		t.Fatalf("debt id = %v, want the one derived from the sale", v.DebtTransactionID)
	}
	if v.CustomerName == nil || *v.CustomerName != "Mama Mboga" {
		t.Errorf("customer name = %v", v.CustomerName)
	}
}

func TestCreate_ACashSaleTouchesNoBalanceAndNeedsNoCustomer(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.Create(f.ctx, f.userID, input(nil, domain.PaymentCash, "Duodip 20ml", "0.5", "225.00")); err != nil {
		t.Fatalf("create: %v", err)
	}
	if f.balance(t) != 0 {
		t.Fatal("a cash sale changed a customer's balance")
	}
}

func TestCreate_RefusesWhatCannotBeASale(t *testing.T) {
	f := newFixture(t)
	gone := uuid.New()
	for name, tc := range map[string]struct {
		in   sales.CreateInput
		want error
	}{
		"credit without a customer": {input(nil, domain.PaymentCredit, "DAP", "1", "100"), sales.ErrCreditNeedsCustomer},
		"no product":                {input(nil, domain.PaymentCash, "  ", "1", "100"), sales.ErrProductRequired},
		"zero quantity":             {input(nil, domain.PaymentCash, "DAP", "0", "100"), sales.ErrNonPositiveQuantity},
		"zero amount":               {input(nil, domain.PaymentCash, "DAP", "1", "0"), sales.ErrNonPositiveAmount},
		"unknown customer":          {input(&gone, domain.PaymentCredit, "DAP", "1", "100"), sales.ErrCustomerNotFound},
	} {
		if _, err := f.svc.Create(f.ctx, f.userID, tc.in); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", name, err, tc.want)
		}
	}
}

func TestCreate_ARetryWithTheSameIDDoesNotSellTwice(t *testing.T) {
	f := newFixture(t)
	in := input(&f.customer, domain.PaymentCredit, "DAP 50kg", "1", "3500.00")
	id := uuid.New()
	in.Body.ID = &id

	if _, err := f.svc.Create(f.ctx, f.userID, in); err != nil {
		t.Fatalf("first: %v", err)
	}
	if _, err := f.svc.Create(f.ctx, f.userID, in); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if f.balance(t).String() != "3500.00" {
		t.Fatalf("balance = %s after a retry, want 3500.00", f.balance(t))
	}
}

func TestVoid_TakesTheDebtWithIt(t *testing.T) {
	f := newFixture(t)
	v, err := f.svc.Create(f.ctx, f.userID, input(&f.customer, domain.PaymentCredit, "DAP 50kg", "1", "3500.00"))
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := f.svc.Void(f.ctx, v.ID); err != nil {
		t.Fatalf("void: %v", err)
	}
	if f.balance(t) != 0 {
		t.Fatalf("balance = %s after voiding, want 0", f.balance(t))
	}
	if err := f.svc.Void(f.ctx, v.ID); !errors.Is(err, sales.ErrNotFound) {
		t.Fatalf("second void: got %v, want ErrNotFound", err)
	}
}

func TestLedger_RefusesToVoidASalesDebtOnItsOwn(t *testing.T) {
	f := newFixture(t)
	v, err := f.svc.Create(f.ctx, f.userID, input(&f.customer, domain.PaymentCredit, "DAP 50kg", "1", "3500.00"))
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	// Voiding the debt alone would leave a credit sale with nothing owed for
	// it. The sale is voided instead.
	ledgerSvc := ledger.NewService(ledger.NewRepository(f.db))
	if err := ledgerSvc.Void(f.ctx, *v.DebtTransactionID); !errors.Is(err, ledger.ErrBelongsToSale) {
		t.Fatalf("got %v, want ErrBelongsToSale", err)
	}
}
