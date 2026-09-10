package ledger_test

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/testsupport"
)

// fixture bundles what nearly every test needs: a service, the raw db (for
// assertions the service does not expose), a tenant-scoped context, a seeded
// customer, and the user recording the transactions.
//
// userID matters specifically because transactions.user_id carries a real
// foreign key — a random UUID passed as the acting user fails at the database,
// not at any layer this package is responsible for testing.
type fixture struct {
	svc        *ledger.Service
	db         *gorm.DB
	ctx        context.Context
	customerID uuid.UUID
	userID     uuid.UUID
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	db := testsupport.Connect(t)

	b := &domain.Business{Name: "Test Shop"}
	if err := tenant.Unscoped(db.WithContext(context.Background())).Create(b).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	ctx := tenant.WithTenant(context.Background(), b.ID)

	u := &domain.User{Name: "Owner", Phone: uuid.New().String()[:12], PasswordHash: "x", Role: domain.RoleOwner}
	if err := db.WithContext(ctx).Create(u).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	c := &domain.Customer{Name: "Customer", CreatedBy: u.ID}
	if err := db.WithContext(ctx).Create(c).Error; err != nil {
		t.Fatalf("create customer: %v", err)
	}

	return fixture{
		svc: ledger.NewService(ledger.NewRepository(db)),
		db:  db, ctx: ctx, customerID: c.ID, userID: u.ID,
	}
}

func mustParse(t *testing.T, s string) money.Amount {
	t.Helper()
	a, err := money.Parse(s)
	if err != nil {
		t.Fatalf("parse %q: %v", s, err)
	}
	return a
}

func TestCreate_ADebtIncreasesTheBalance(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID = f.customerID
	in.Body.Type = domain.TypeDebt
	in.Body.Amount = mustParse(t, "1500.50")

	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if v.Amount.String() != "1500.50" {
		t.Errorf("got amount %s", v.Amount)
	}

	var balance money.Amount
	f.db.WithContext(f.ctx).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ?", f.customerID).Scan(&balance)
	if balance.String() != "1500.50" {
		t.Errorf("balance = %s, want 1500.50", balance)
	}
}

func TestCreate_APaymentReducesTheBalance(t *testing.T) {
	f := newFixture(t)

	var debt ledger.CreateInput
	debt.Body.CustomerID, debt.Body.Type, debt.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "1000")
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("debt: %v", err)
	}

	var payment ledger.CreateInput
	payment.Body.CustomerID, payment.Body.Type, payment.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "400")
	if _, err := f.svc.Create(f.ctx, f.userID, payment); err != nil {
		t.Fatalf("payment: %v", err)
	}

	txs, err := f.svc.ListForCustomer(f.ctx, f.customerID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(txs) != 2 {
		t.Fatalf("got %d transactions, want 2", len(txs))
	}
}

// TestCreate_RejectsAPaymentExceedingTheBalance is the rule carried over from
// v1: a customer cannot be paid into credit through this endpoint.
func TestCreate_RejectsAPaymentExceedingTheBalance(t *testing.T) {
	f := newFixture(t)

	var debt ledger.CreateInput
	debt.Body.CustomerID, debt.Body.Type, debt.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "500")
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("debt: %v", err)
	}

	var payment ledger.CreateInput
	payment.Body.CustomerID, payment.Body.Type, payment.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "500.01")
	if _, err := f.svc.Create(f.ctx, f.userID, payment); !errors.Is(err, ledger.ErrExceedsBalance) {
		t.Fatalf("got %v, want ErrExceedsBalance", err)
	}

	// Exactly the balance must be allowed — the boundary itself is not an error.
	var exact ledger.CreateInput
	exact.Body.CustomerID, exact.Body.Type, exact.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "500")
	if _, err := f.svc.Create(f.ctx, f.userID, exact); err != nil {
		t.Fatalf("payment equal to balance should succeed: %v", err)
	}
}

// TestCreate_ConcurrentPaymentsCannotTogetherExceedTheBalance is the race the
// row lock in Repository.Create exists to close. Without it, two goroutines can
// each read the same starting balance, each individually pass the check, and
// together take the customer negative.
func TestCreate_ConcurrentPaymentsCannotTogetherExceedTheBalance(t *testing.T) {
	f := newFixture(t)

	var debt ledger.CreateInput
	debt.Body.CustomerID, debt.Body.Type, debt.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "1000")
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("seed debt: %v", err)
	}

	// Ten payments of 150 against a balance of 1000. At most 6 can succeed
	// (900), a 7th would reach 1050 and must be refused, regardless of ordering.
	const attempts = 10
	var wg sync.WaitGroup
	results := make([]error, attempts)
	for i := range attempts {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var in ledger.CreateInput
			in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "150")
			_, results[i] = f.svc.Create(f.ctx, f.userID, in)
		}(i)
	}
	wg.Wait()

	succeeded := 0
	for _, err := range results {
		if err == nil {
			succeeded++
		} else if !errors.Is(err, ledger.ErrExceedsBalance) {
			t.Errorf("unexpected error: %v", err)
		}
	}
	if succeeded != 6 {
		t.Errorf("%d of %d concurrent payments succeeded, want exactly 6", succeeded, attempts)
	}

	txs, err := f.svc.ListForCustomer(f.ctx, f.customerID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	var total money.Amount
	for _, tx := range txs {
		if tx.Type == domain.TypeDebt {
			total += tx.Amount
		} else {
			total -= tx.Amount
		}
	}
	if total.Minor() < 0 {
		t.Fatalf("balance went negative: %s", total)
	}
}

func TestCreate_RejectsANonPositiveAmount(t *testing.T) {
	f := newFixture(t)

	for _, amt := range []string{"0", "-10"} {
		var in ledger.CreateInput
		in.Body.CustomerID, in.Body.Type = f.customerID, domain.TypeDebt
		in.Body.Amount = mustParse(t, amt)
		if _, err := f.svc.Create(f.ctx, f.userID, in); !errors.Is(err, ledger.ErrNonPositiveAmount) {
			t.Errorf("amount %q: got %v, want ErrNonPositiveAmount", amt, err)
		}
	}
}

func TestCreate_RejectsAnInvalidType(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = f.customerID, "refund"
	in.Body.Amount = mustParse(t, "100")
	if _, err := f.svc.Create(f.ctx, f.userID, in); !errors.Is(err, ledger.ErrInvalidType) {
		t.Fatalf("got %v, want ErrInvalidType", err)
	}
}

func TestCreate_RejectsAnUnknownCustomer(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = uuid.New(), domain.TypeDebt
	in.Body.Amount = mustParse(t, "100")
	if _, err := f.svc.Create(f.ctx, f.userID, in); !errors.Is(err, ledger.ErrCustomerNotFound) {
		t.Fatalf("got %v, want ErrCustomerNotFound", err)
	}
}

// TestVoid_ExcludesTheTransactionFromTheLedger checks both the tombstone
// contract and that GORM's convention stamps updated_at automatically — the
// structural fix for v1's hand-written UPDATE that forgot to.
func TestVoid_ExcludesTheTransactionFromTheLedger(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = f.customerID, domain.TypeDebt
	in.Body.Amount = mustParse(t, "500")
	created, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	var before domain.Transaction
	f.db.WithContext(f.ctx).First(&before, "id = ?", created.ID)

	if err := f.svc.Void(f.ctx, created.ID); err != nil {
		t.Fatalf("void: %v", err)
	}

	var after domain.Transaction
	if err := f.db.WithContext(f.ctx).Unscoped().First(&after, "id = ?", created.ID).Error; err != nil {
		t.Fatalf("read back: %v", err)
	}
	if !after.IsDeleted {
		t.Error("transaction was not marked deleted")
	}
	if !after.UpdatedAt.After(before.UpdatedAt) {
		t.Errorf("updated_at did not advance on void: before=%v after=%v", before.UpdatedAt, after.UpdatedAt)
	}

	txs, err := f.svc.ListForCustomer(f.ctx, f.customerID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(txs) != 0 {
		t.Error("voided transaction still appears in the ledger")
	}
}

func TestVoid_RefusesToVoidTwice(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = f.customerID, domain.TypeDebt
	in.Body.Amount = mustParse(t, "100")
	created, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	if err := f.svc.Void(f.ctx, created.ID); err != nil {
		t.Fatalf("first void: %v", err)
	}
	if err := f.svc.Void(f.ctx, created.ID); !errors.Is(err, ledger.ErrNotFound) {
		t.Fatalf("second void: got %v, want ErrNotFound", err)
	}
}

func TestListForCustomer_IsIsolatedBetweenTenants(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = f.customerID, domain.TypeDebt
	in.Body.Amount = mustParse(t, "100")
	if _, err := f.svc.Create(f.ctx, f.userID, in); err != nil {
		t.Fatalf("create: %v", err)
	}

	businessB := &domain.Business{Name: "Other"}
	if err := tenant.Unscoped(f.db.WithContext(context.Background())).Create(businessB).Error; err != nil {
		t.Fatalf("create business B: %v", err)
	}
	ctxB := tenant.WithTenant(context.Background(), businessB.ID)

	svcB := ledger.NewService(ledger.NewRepository(f.db))
	// f.customerID belongs to business A; from B's context it must not resolve
	// at all, not even to leak its transactions.
	txs, err := svcB.ListForCustomer(ctxB, f.customerID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(txs) != 0 {
		t.Errorf("business B saw %d of A's transactions", len(txs))
	}
}
