package reports_test

import (
	"context"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/reports"
	"salio/server-v2/internal/testsupport"
)

type fixture struct {
	svc *reports.Service
	db  *gorm.DB
	ctx context.Context
	biz uuid.UUID
	usr uuid.UUID
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

	return fixture{
		svc: reports.NewService(reports.NewRepository(db)),
		db:  db, ctx: ctx, biz: b.ID, usr: u.ID,
	}
}

func (f fixture) newCustomer(t *testing.T, name string) uuid.UUID {
	t.Helper()
	c := &domain.Customer{Name: name, CreatedBy: f.usr}
	if err := f.db.WithContext(f.ctx).Create(c).Error; err != nil {
		t.Fatalf("create customer %s: %v", name, err)
	}
	return c.ID
}

// debt inserts a transaction with an explicit created_at, bypassing the
// service layer: the overdue tests need to backdate activity, which no
// legitimate write path allows or should allow.
func (f fixture) debt(t *testing.T, customerID uuid.UUID, amount string, createdAt time.Time) {
	t.Helper()
	amt, err := money.Parse(amount)
	if err != nil {
		t.Fatalf("parse amount: %v", err)
	}
	tx := domain.Transaction{
		CustomerID: customerID, UserID: f.usr, Type: domain.TypeDebt,
		Amount: amt, TransactionDate: createdAt,
	}
	if err := f.db.WithContext(f.ctx).Create(&tx).Error; err != nil {
		t.Fatalf("seed debt: %v", err)
	}
	if err := f.db.WithContext(f.ctx).Model(&domain.Transaction{}).
		Where("id = ?", tx.ID).Update("created_at", createdAt).Error; err != nil {
		t.Fatalf("backdate: %v", err)
	}
}

func (f fixture) payment(t *testing.T, customerID uuid.UUID, amount string, createdAt time.Time) {
	t.Helper()
	amt, err := money.Parse(amount)
	if err != nil {
		t.Fatalf("parse amount: %v", err)
	}
	tx := domain.Transaction{
		CustomerID: customerID, UserID: f.usr, Type: domain.TypePayment,
		Amount: amt, TransactionDate: createdAt,
	}
	if err := f.db.WithContext(f.ctx).Create(&tx).Error; err != nil {
		t.Fatalf("seed payment: %v", err)
	}
	if err := f.db.WithContext(f.ctx).Model(&domain.Transaction{}).
		Where("id = ?", tx.ID).Update("created_at", createdAt).Error; err != nil {
		t.Fatalf("backdate: %v", err)
	}
}

func TestSummary_TotalsAreCorrect(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	a := f.newCustomer(t, "Alice")
	b := f.newCustomer(t, "Bob")
	f.debt(t, a, "1000", now)
	f.debt(t, b, "500", now)
	f.payment(t, a, "300", now)

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	if summary.TotalCustomers != 2 {
		t.Errorf("total customers = %d, want 2", summary.TotalCustomers)
	}
	// (1000 - 300) + 500 = 1200
	if summary.TotalOutstandingDebt.String() != "1200.00" {
		t.Errorf("total outstanding = %s, want 1200.00", summary.TotalOutstandingDebt)
	}
	if summary.TotalCollected30Days.String() != "300.00" {
		t.Errorf("total collected = %s, want 300.00", summary.TotalCollected30Days)
	}
}

// TestSummary_CollectedOnlyCountsTheLast30Days pins the window: an old payment
// must not inflate a number that is meant to describe recent activity.
func TestSummary_CollectedOnlyCountsTheLast30Days(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	c := f.newCustomer(t, "Customer")
	f.debt(t, c, "2000", now.Add(-60*24*time.Hour))
	f.payment(t, c, "500", now.Add(-40*24*time.Hour)) // outside the window
	f.payment(t, c, "200", now.Add(-1*time.Hour))     // inside it

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	if summary.TotalCollected30Days.String() != "200.00" {
		t.Errorf("collected(30d) = %s, want 200.00 (the 500 payment is 40 days old)", summary.TotalCollected30Days)
	}
}

func TestSummary_TopDebtorsAreRankedByBalanceDescending(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	small := f.newCustomer(t, "Small Debtor")
	big := f.newCustomer(t, "Big Debtor")
	settled := f.newCustomer(t, "Settled Customer")

	f.debt(t, small, "100", now)
	f.debt(t, big, "5000", now)
	f.debt(t, settled, "300", now)
	f.payment(t, settled, "300", now) // balance zero — must not appear

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	if len(summary.TopDebtors) != 2 {
		t.Fatalf("got %d top debtors, want 2 (settled customer excluded)", len(summary.TopDebtors))
	}
	if summary.TopDebtors[0].Name != "Big Debtor" || summary.TopDebtors[0].Balance.String() != "5000.00" {
		t.Errorf("first place = %+v, want Big Debtor at 5000.00", summary.TopDebtors[0])
	}
	if summary.TopDebtors[1].Name != "Small Debtor" {
		t.Errorf("second place = %+v, want Small Debtor", summary.TopDebtors[1])
	}
}

// TestSummary_OverdueDebtorsRespectTheThirtyDayBoundary is the actionable list
// the dashboard exists to surface: balance > 0 and nothing has happened on the
// account in 30 days.
func TestSummary_OverdueDebtorsRespectTheThirtyDayBoundary(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	stale := f.newCustomer(t, "Gone Quiet")
	fresh := f.newCustomer(t, "Active")
	noDebt := f.newCustomer(t, "No Debt")

	f.debt(t, stale, "800", now.Add(-45*24*time.Hour)) // last activity 45 days ago
	f.debt(t, fresh, "800", now.Add(-2*24*time.Hour))  // last activity 2 days ago
	f.debt(t, noDebt, "100", now.Add(-90*24*time.Hour))
	f.payment(t, noDebt, "100", now.Add(-90*24*time.Hour)) // settled long ago, irrelevant

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	if len(summary.OverdueDebtors) != 1 || summary.OverdueDebtors[0].Name != "Gone Quiet" {
		t.Fatalf("overdue debtors = %+v, want only Gone Quiet", summary.OverdueDebtors)
	}
	if summary.OverdueDebtors[0].DaysSinceLast < 44 {
		t.Errorf("days since last = %d, want >= 44", summary.OverdueDebtors[0].DaysSinceLast)
	}
	if summary.OverdueDebtorCount != 1 {
		t.Errorf("overdue count = %d, want 1", summary.OverdueDebtorCount)
	}
}

// TestSummary_LastActivityMovesOnAnyTransaction: a payment made yesterday on an
// old debt must reset the staleness clock — the customer clearly has not been
// forgotten, they were just heard from most recently as a payment, not a debt.
func TestSummary_LastActivityMovesOnAnyTransaction(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	c := f.newCustomer(t, "Recently Active")
	f.debt(t, c, "1000", now.Add(-90*24*time.Hour))
	f.payment(t, c, "200", now.Add(-1*24*time.Hour)) // paid down yesterday

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	for _, d := range summary.OverdueDebtors {
		if d.Name == "Recently Active" {
			t.Errorf("customer with activity yesterday was listed as overdue: %+v", d)
		}
	}
}

// TestSummary_IsIsolatedBetweenTenants is the highest-risk case in this module:
// every query joins transactions to customers, and the automatic tenant
// callback only patches the base table of a query, not a join partner. A
// missing filter on the customers side would leak balances across businesses.
func TestSummary_IsIsolatedBetweenTenants(t *testing.T) {
	f := newFixture(t)
	now := time.Now()

	c := f.newCustomer(t, "Alpha's Customer")
	f.debt(t, c, "9999", now)

	businessB := &domain.Business{Name: "Beta"}
	if err := tenant.Unscoped(f.db.WithContext(context.Background())).Create(businessB).Error; err != nil {
		t.Fatalf("create business B: %v", err)
	}
	ctxB := tenant.WithTenant(context.Background(), businessB.ID)
	svcB := reports.NewService(reports.NewRepository(f.db))

	summary, err := svcB.Summary(ctxB)
	if err != nil {
		t.Fatalf("summary as B: %v", err)
	}
	if summary.TotalCustomers != 0 {
		t.Errorf("business B sees %d customers, want 0", summary.TotalCustomers)
	}
	if summary.TotalOutstandingDebt != 0 {
		t.Errorf("business B sees outstanding debt %s, want 0 — Alpha's 9999 leaked", summary.TotalOutstandingDebt)
	}
	if len(summary.TopDebtors) != 0 || len(summary.OverdueDebtors) != 0 {
		t.Errorf("business B's debtor lists are not empty: top=%v overdue=%v", summary.TopDebtors, summary.OverdueDebtors)
	}
}

func TestSummary_EmptyBusinessReturnsZeroesNotErrors(t *testing.T) {
	f := newFixture(t)

	summary, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	if summary.TotalCustomers != 0 || summary.TotalOutstandingDebt != 0 {
		t.Errorf("got %+v, want all zero for an empty business", summary)
	}
	if summary.TopDebtors == nil || summary.OverdueDebtors == nil {
		t.Error("lists should be empty slices, not nil, so they serialise as [] rather than null")
	}
}
