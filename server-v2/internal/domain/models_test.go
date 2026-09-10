package domain_test

import (
	"context"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/testsupport"
)

// These check the models against the real migrated schema. GORM builds SQL from
// struct tags at run time, so a column that does not exist, a type that does not
// match, or a missing NOT NULL compiles and vets cleanly and fails only when a
// query runs.

func TestSchema_MatchesTheModels(t *testing.T) {
	db := testsupport.Connect(t)
	ctx := context.Background()

	business := domain.Business{Name: "Mama Njeri Agrovet"}
	if err := tenant.Unscoped(db.WithContext(ctx)).Create(&business).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	if id.IsZero(business.ID) {
		t.Fatal("BeforeCreate did not assign an ID")
	}

	// From here on the request acts as that business, exactly as a handler would.
	ctx = tenant.WithTenant(ctx, business.ID)
	tdb := db.WithContext(ctx)

	user := domain.User{
		Name: "Njeri", Phone: "0700000001",
		PasswordHash: "x", Role: domain.RoleOwner,
	}
	if err := tdb.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	if user.BusinessID != business.ID {
		t.Errorf("the tenant callback did not stamp business_id: got %s", user.BusinessID)
	}

	customer := domain.Customer{Name: "Wanjiku", CreatedBy: user.ID}
	if err := tdb.Create(&customer).Error; err != nil {
		t.Fatalf("create customer: %v", err)
	}

	amount, _ := money.Parse("1500.50")
	tx := domain.Transaction{
		CustomerID: customer.ID, UserID: user.ID,
		Type: domain.TypeDebt, Amount: amount,
		TransactionDate: time.Now(),
	}
	if err := tdb.Create(&tx).Error; err != nil {
		t.Fatalf("create transaction: %v", err)
	}

	var stored domain.Transaction
	if err := tdb.First(&stored, "id = ?", tx.ID).Error; err != nil {
		t.Fatalf("read back: %v", err)
	}
	if stored.Amount != amount {
		t.Errorf("amount round-tripped as %s, want %s", stored.Amount, amount)
	}

	// The trigger, not this process, assigns change_seq.
	if stored.ChangeSeq == 0 {
		t.Error("change_seq was not assigned by the database trigger")
	}
}

// TestBalance_IsExactOverManyRows is the money bug the v1 backend has, expressed
// as the query the product actually runs.
func TestBalance_IsExactOverManyRows(t *testing.T) {
	db := testsupport.Connect(t)
	ctx := context.Background()

	business := domain.Business{Name: "Kiosk"}
	if err := tenant.Unscoped(db.WithContext(ctx)).Create(&business).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	ctx = tenant.WithTenant(ctx, business.ID)
	tdb := db.WithContext(ctx)

	user := domain.User{Name: "O", Phone: "0700000002", PasswordHash: "x", Role: domain.RoleOwner}
	if err := tdb.Create(&user).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	customer := domain.Customer{Name: "C", CreatedBy: user.ID}
	if err := tdb.Create(&customer).Error; err != nil {
		t.Fatalf("create customer: %v", err)
	}

	// 300 debts of 0.10 and 100 payments of 0.07: values with no exact binary
	// representation, in the quantity a real shop accumulates.
	tenCents, _ := money.Parse("0.10")
	sevenCents, _ := money.Parse("0.07")
	for i := range 300 {
		typ, amt := domain.TypeDebt, tenCents
		if i%3 == 0 {
			typ, amt = domain.TypePayment, sevenCents
		}
		err := tdb.Create(&domain.Transaction{
			CustomerID: customer.ID, UserID: user.ID,
			Type: typ, Amount: amt, TransactionDate: time.Now(),
		}).Error
		if err != nil {
			t.Fatalf("create transaction %d: %v", i, err)
		}
	}

	var balance money.Amount
	err := tdb.Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ? AND is_deleted = false", customer.ID).
		Scan(&balance).Error
	if err != nil {
		t.Fatalf("balance query: %v", err)
	}

	// 200 debts x 0.10 = 20.00; 100 payments x 0.07 = 7.00; balance 13.00.
	if balance.String() != "13.00" {
		t.Errorf("balance = %s, want 13.00", balance)
	}
}

// TestTenancy_ScopesEveryDomainQuery: one business must never see another's
// rows, without any handler writing a filter.
func TestTenancy_ScopesEveryDomainQuery(t *testing.T) {
	db := testsupport.Connect(t)
	root := context.Background()

	mkBusiness := func(name, phone string) (domain.Business, domain.User) {
		t.Helper()
		b := domain.Business{Name: name}
		if err := tenant.Unscoped(db.WithContext(root)).Create(&b).Error; err != nil {
			t.Fatalf("create business %s: %v", name, err)
		}
		ctx := tenant.WithTenant(root, b.ID)
		u := domain.User{Name: name + " owner", Phone: phone, PasswordHash: "x", Role: domain.RoleOwner}
		if err := db.WithContext(ctx).Create(&u).Error; err != nil {
			t.Fatalf("create user for %s: %v", name, err)
		}
		c := domain.Customer{Name: name + " customer", CreatedBy: u.ID}
		if err := db.WithContext(ctx).Create(&c).Error; err != nil {
			t.Fatalf("create customer for %s: %v", name, err)
		}
		return b, u
	}

	alpha, _ := mkBusiness("Alpha", "0700000010")
	beta, betaUser := mkBusiness("Beta", "0700000011")

	alphaCtx := db.WithContext(tenant.WithTenant(root, alpha.ID))

	var customers []domain.Customer
	if err := alphaCtx.Find(&customers).Error; err != nil {
		t.Fatalf("list customers: %v", err)
	}
	if len(customers) != 1 || customers[0].BusinessID != alpha.ID {
		t.Errorf("Alpha saw %d customers, want only its own", len(customers))
	}

	var users []domain.User
	if err := alphaCtx.Find(&users).Error; err != nil {
		t.Fatalf("list users: %v", err)
	}
	if len(users) != 1 {
		t.Errorf("Alpha saw %d users, want 1 — this is the leak feedback.txt reports", len(users))
	}

	// Beta's own record, fetched by ID, as Alpha.
	var stolen domain.User
	if err := alphaCtx.First(&stolen, "id = ?", betaUser.ID).Error; err == nil {
		t.Error("Alpha read a Beta user by ID")
	}

	// And the business row itself, which is scoped by its own id.
	var otherBusiness domain.Business
	if err := alphaCtx.First(&otherBusiness, "id = ?", beta.ID).Error; err == nil {
		t.Error("Alpha read Beta's business record")
	}
}
