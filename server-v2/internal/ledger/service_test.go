package ledger_test

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"

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

func cash() *domain.PaymentMethod {
	m := domain.PaymentCash
	return &m
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
	in.Body.Description = "test entry"

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
	debt.Body.Description = "test entry"
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("debt: %v", err)
	}

	var payment ledger.CreateInput
	payment.Body.CustomerID, payment.Body.Type, payment.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "400")
	payment.Body.PaymentMethod = cash()
	payment.Body.Description = "test entry"
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

// TestCreate_APaymentLargerThanTheBalanceBecomesAnAdvance is the rule as the
// shops asked for it: a deposit or a pre-payment is a real thing that happens at
// the counter, and the ledger has to be able to record it. The surplus sits on
// the account as a negative balance and is used up by the next debts.
func TestCreate_APaymentLargerThanTheBalanceBecomesAnAdvance(t *testing.T) {
	f := newFixture(t)

	var debt ledger.CreateInput
	debt.Body.CustomerID, debt.Body.Type, debt.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "500")
	debt.Body.Description = "2 bags maize flour"
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("debt: %v", err)
	}

	var payment ledger.CreateInput
	payment.Body.CustomerID, payment.Body.Type, payment.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "800")
	payment.Body.PaymentMethod = cash()
	payment.Body.Description = "cash, includes deposit for next week"
	if _, err := f.svc.Create(f.ctx, f.userID, payment); err != nil {
		t.Fatalf("a payment above the balance was refused: %v", err)
	}

	if got := balanceOf(t, f); got.String() != "-300.00" {
		t.Fatalf("balance = %s, want -300.00: the 300 surplus is an advance held for the customer", got)
	}
}

// TestCreate_ConcurrentWritesAllLand is the race the customer row lock guards
// now that there is no ceiling to protect: every write must land, none may be
// lost, and the total must be exact.
func TestCreate_ConcurrentWritesAllLand(t *testing.T) {
	f := newFixture(t)

	var debt ledger.CreateInput
	debt.Body.CustomerID, debt.Body.Type, debt.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "1000")
	debt.Body.Description = "opening debt"
	if _, err := f.svc.Create(f.ctx, f.userID, debt); err != nil {
		t.Fatalf("seed debt: %v", err)
	}

	const attempts = 10
	var wg sync.WaitGroup
	results := make([]error, attempts)
	for i := range attempts {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var in ledger.CreateInput
			in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypePayment, mustParse(t, "150")
			in.Body.PaymentMethod = cash()
			in.Body.Description = "instalment"
			_, results[i] = f.svc.Create(f.ctx, f.userID, in)
		}(i)
	}
	wg.Wait()

	for i, err := range results {
		if err != nil {
			t.Errorf("payment %d failed: %v", i, err)
		}
	}
	// 1000 owed, 1500 paid: 500 held as an advance, to the cent.
	if got := balanceOf(t, f); got.String() != "-500.00" {
		t.Fatalf("balance = %s, want -500.00", got)
	}
}

func TestCreate_RequiresADescription(t *testing.T) {
	f := newFixture(t)

	for _, desc := range []string{"", "   "} {
		var in ledger.CreateInput
		in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "100")
		in.Body.Description = desc
		if _, err := f.svc.Create(f.ctx, f.userID, in); !errors.Is(err, ledger.ErrDescriptionRequired) {
			t.Errorf("description %q: got %v, want ErrDescriptionRequired", desc, err)
		}
	}
}

func TestGet_ReturnsOneTransactionIncludingAVoidedOne(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type, in.Body.Amount = f.customerID, domain.TypeDebt, mustParse(t, "250")
	in.Body.Description = "1 Duodip 20ml"
	created, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	got, err := f.svc.Get(f.ctx, created.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Description == nil || *got.Description != "1 Duodip 20ml" || got.Amount.String() != "250.00" {
		t.Fatalf("got %+v", got)
	}

	if err := f.svc.Void(f.ctx, created.ID); err != nil {
		t.Fatalf("void: %v", err)
	}
	// Someone asking "what happened to that 250?" must be told it was voided,
	// not that it never existed.
	voided, err := f.svc.Get(f.ctx, created.ID)
	if err != nil {
		t.Fatalf("get after void: %v", err)
	}
	if !voided.IsDeleted {
		t.Fatal("a voided transaction was returned as live")
	}

	if _, err := f.svc.Get(f.ctx, uuid.New()); !errors.Is(err, ledger.ErrNotFound) {
		t.Fatalf("unknown id: got %v, want ErrNotFound", err)
	}
}

func balanceOf(t *testing.T, f fixture) money.Amount {
	t.Helper()
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
	return total
}

func TestCreate_RejectsANonPositiveAmount(t *testing.T) {
	f := newFixture(t)

	for _, amt := range []string{"0", "-10"} {
		var in ledger.CreateInput
		in.Body.CustomerID, in.Body.Type = f.customerID, domain.TypeDebt
		in.Body.Amount = mustParse(t, amt)
		in.Body.Description = "test entry"
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
	in.Body.Description = "test entry"
	if _, err := f.svc.Create(f.ctx, f.userID, in); !errors.Is(err, ledger.ErrInvalidType) {
		t.Fatalf("got %v, want ErrInvalidType", err)
	}
}

func TestCreate_RejectsAnUnknownCustomer(t *testing.T) {
	f := newFixture(t)

	var in ledger.CreateInput
	in.Body.CustomerID, in.Body.Type = uuid.New(), domain.TypeDebt
	in.Body.Amount = mustParse(t, "100")
	in.Body.Description = "test entry"
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
	in.Body.Description = "test entry"
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
	in.Body.Description = "test entry"
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
	in.Body.Description = "test entry"
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

func TestCreate_AnUndatedEntryTakesTheBusinessesOwnDate(t *testing.T) {
	f := newFixture(t)

	// UTC+14: its calendar date is never UTC's, so an entry dated by the
	// server's clock instead of the business's would fail here at any hour.
	const zone = "Pacific/Kiritimati"
	if err := f.db.WithContext(f.ctx).Model(&domain.Business{}).
		Where("1 = 1").Update("time_zone", zone).Error; err != nil {
		t.Fatalf("set zone: %v", err)
	}
	loc, _ := domain.LoadTimeZone(zone)
	before := domain.DateIn(time.Now(), loc)

	var in ledger.CreateInput
	in.Body.CustomerID = f.customerID
	in.Body.Type = domain.TypeDebt
	in.Body.Amount = mustParse(t, "100")
	in.Body.Description = "undated entry"
	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	after := domain.DateIn(time.Now(), loc)
	got := v.TransactionDate
	if !got.Equal(before) && !got.Equal(after) {
		t.Fatalf("transaction_date = %s, want %s (today in %s); UTC's today is %s",
			got.Format(time.DateOnly), before.Format(time.DateOnly), zone, time.Now().UTC().Format(time.DateOnly))
	}
}
