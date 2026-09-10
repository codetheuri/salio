package customer_test

import (
	"context"
	"errors"
	"testing"

	tuskquery "github.com/codetheuri/tusk/v2/pkg/query"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/testsupport"
)

func newService(t *testing.T) (*customer.Service, *gorm.DB, uuid.UUID, uuid.UUID) {
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

	return customer.NewService(customer.NewRepository(db)), db, b.ID, u.ID
}

func TestCreate_ThenGet_ReturnsAZeroBalance(t *testing.T) {
	svc, _, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	var in customer.CreateInput
	in.Body.Name = "Wanjiku"

	created, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if created.Balance != 0 {
		t.Errorf("new customer balance = %s, want 0", created.Balance)
	}

	got, err := svc.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Name != "Wanjiku" {
		t.Errorf("got name %q", got.Name)
	}
}

// TestCreate_RejectsADuplicatePhoneWithinOneBusiness pins the partial unique
// index: two customers with no phone must be fine (walk-ins), but two sharing a
// real number within one business must not.
func TestCreate_RejectsADuplicatePhoneWithinOneBusiness(t *testing.T) {
	svc, _, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	phone := "0711222333"
	var first customer.CreateInput
	first.Body.Name, first.Body.Phone = "First", &phone
	if _, err := svc.Create(ctx, userID, first); err != nil {
		t.Fatalf("first create: %v", err)
	}

	var second customer.CreateInput
	second.Body.Name, second.Body.Phone = "Second", &phone
	if _, err := svc.Create(ctx, userID, second); !errors.Is(err, customer.ErrPhoneTaken) {
		t.Fatalf("got %v, want ErrPhoneTaken", err)
	}

	// Two walk-ins with no phone at all must both succeed.
	var walkin1, walkin2 customer.CreateInput
	walkin1.Body.Name, walkin2.Body.Name = "Walkin A", "Walkin B"
	if _, err := svc.Create(ctx, userID, walkin1); err != nil {
		t.Fatalf("walk-in 1: %v", err)
	}
	if _, err := svc.Create(ctx, userID, walkin2); err != nil {
		t.Fatalf("walk-in 2: %v", err)
	}
}

// TestCreate_SamePhoneAllowedAcrossDifferentBusinesses: the unique index is
// scoped to (business_id, phone), not phone alone.
func TestCreate_SamePhoneAllowedAcrossDifferentBusinesses(t *testing.T) {
	svcA, db, businessA, userA := newService(t)
	ctxA := tenant.WithTenant(context.Background(), businessA)

	businessB := &domain.Business{Name: "Other Shop"}
	if err := tenant.Unscoped(db.WithContext(context.Background())).Create(businessB).Error; err != nil {
		t.Fatalf("create second business: %v", err)
	}
	ctxB := tenant.WithTenant(context.Background(), businessB.ID)
	userB := &domain.User{Name: "Owner B", Phone: uuid.New().String()[:12], PasswordHash: "x", Role: domain.RoleOwner}
	if err := db.WithContext(ctxB).Create(userB).Error; err != nil {
		t.Fatalf("create second user: %v", err)
	}

	phone := "0700111222"
	var inA customer.CreateInput
	inA.Body.Name, inA.Body.Phone = "Customer A", &phone
	if _, err := svcA.Create(ctxA, userA, inA); err != nil {
		t.Fatalf("create in business A: %v", err)
	}

	svcB := customer.NewService(customer.NewRepository(db))
	var inB customer.CreateInput
	inB.Body.Name, inB.Body.Phone = "Customer B", &phone
	if _, err := svcB.Create(ctxB, userB.ID, inB); err != nil {
		t.Fatalf("same phone in business B should be allowed: %v", err)
	}
}

func TestList_IsIsolatedBetweenTenants(t *testing.T) {
	svcA, db, businessA, userA := newService(t)
	ctxA := tenant.WithTenant(context.Background(), businessA)

	var in customer.CreateInput
	in.Body.Name = "Alpha's customer"
	if _, err := svcA.Create(ctxA, userA, in); err != nil {
		t.Fatalf("create: %v", err)
	}

	businessB := &domain.Business{Name: "Beta"}
	if err := tenant.Unscoped(db.WithContext(context.Background())).Create(businessB).Error; err != nil {
		t.Fatalf("create business B: %v", err)
	}
	ctxB := tenant.WithTenant(context.Background(), businessB.ID)

	views, _, err := svcA.List(ctxB, tuskquery.NewDefaultQuery())
	if err != nil {
		t.Fatalf("list as B: %v", err)
	}
	if len(views) != 0 {
		t.Errorf("business B saw %d customers, want 0 (Alpha's customer leaked)", len(views))
	}
}

func TestList_SearchFiltersByName(t *testing.T) {
	svc, _, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	for _, name := range []string{"Wanjiku Njoroge", "John Otieno", "Wanjiru Kamau"} {
		var in customer.CreateInput
		in.Body.Name = name
		if _, err := svc.Create(ctx, userID, in); err != nil {
			t.Fatalf("create %s: %v", name, err)
		}
	}

	q := tuskquery.NewDefaultQuery()
	q.Search = "wanj"
	views, meta, err := svc.List(ctx, q)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if meta.Total != 2 {
		t.Errorf("total = %d, want 2", meta.Total)
	}
	if len(views) != 2 {
		t.Fatalf("got %d results, want 2", len(views))
	}
	for _, v := range views {
		if v.Name != "Wanjiku Njoroge" && v.Name != "Wanjiru Kamau" {
			t.Errorf("unexpected match %q", v.Name)
		}
	}
}

// TestList_ExcludesSoftDeletedCustomers is the tombstone contract: a deleted
// customer must vanish from every read, without ever being physically removed.
func TestList_ExcludesSoftDeletedCustomers(t *testing.T) {
	svc, _, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	var in customer.CreateInput
	in.Body.Name = "Gone Soon"
	created, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if err := svc.Delete(ctx, created.ID); err != nil {
		t.Fatalf("delete: %v", err)
	}

	views, _, err := svc.List(ctx, tuskquery.NewDefaultQuery())
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(views) != 0 {
		t.Errorf("deleted customer still appears in the list")
	}

	if _, err := svc.Get(ctx, created.ID); !errors.Is(err, customer.ErrNotFound) {
		t.Errorf("Get on a deleted customer = %v, want ErrNotFound", err)
	}
}

// TestDelete_RefusesANonZeroBalance is the rule that stops a delete button from
// quietly forgiving a debt.
func TestDelete_RefusesANonZeroBalance(t *testing.T) {
	svc, db, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	var in customer.CreateInput
	in.Body.Name = "Owes Money"
	created, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	amount, _ := money.Parse("500")
	tx := domain.Transaction{
		CustomerID: created.ID, UserID: userID,
		Type: domain.TypeDebt, Amount: amount,
	}
	if err := db.WithContext(ctx).Create(&tx).Error; err != nil {
		t.Fatalf("seed debt: %v", err)
	}

	if err := svc.Delete(ctx, created.ID); !errors.Is(err, customer.ErrHasBalance) {
		t.Fatalf("got %v, want ErrHasBalance", err)
	}

	// Settled to zero: now it must succeed.
	tx2 := domain.Transaction{
		CustomerID: created.ID, UserID: userID,
		Type: domain.TypePayment, Amount: amount,
	}
	if err := db.WithContext(ctx).Create(&tx2).Error; err != nil {
		t.Fatalf("seed payment: %v", err)
	}
	if err := svc.Delete(ctx, created.ID); err != nil {
		t.Fatalf("delete after settling: %v", err)
	}
}

// TestList_BalancesMatchPerCustomerLookup guards the batch BalancesFor query
// against drifting from the single-customer Balance query it exists to avoid
// repeating N times.
func TestList_BalancesMatchPerCustomerLookup(t *testing.T) {
	svc, db, businessID, userID := newService(t)
	ctx := tenant.WithTenant(context.Background(), businessID)

	var in customer.CreateInput
	in.Body.Name = "Has Debt"
	created, err := svc.Create(ctx, userID, in)
	if err != nil {
		t.Fatalf("create: %v", err)
	}

	amount, _ := money.Parse("1234.56")
	if err := db.WithContext(ctx).Create(&domain.Transaction{
		CustomerID: created.ID, UserID: userID, Type: domain.TypeDebt, Amount: amount,
	}).Error; err != nil {
		t.Fatalf("seed debt: %v", err)
	}

	views, _, err := svc.List(ctx, tuskquery.NewDefaultQuery())
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(views) != 1 || views[0].Balance.String() != "1234.56" {
		t.Fatalf("list balance = %+v, want 1234.56", views)
	}

	single, err := svc.Get(ctx, created.ID)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if single.Balance != views[0].Balance {
		t.Errorf("Get balance %s disagrees with List balance %s", single.Balance, views[0].Balance)
	}
}
