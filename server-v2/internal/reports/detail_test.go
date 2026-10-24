package reports_test

import (
	"bytes"
	"testing"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
	"salio/server-v2/internal/reports"
	"salio/server-v2/internal/sales"
)

func daysAgo(n int) time.Time {
	now := time.Now().UTC()
	return time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.UTC).AddDate(0, 0, -n)
}

func (f fixture) sale(t *testing.T, customerID *uuid.UUID, method domain.PaymentMethod, product, qty, amount string, on time.Time) {
	t.Helper()
	q, err := quantity.Parse(qty)
	if err != nil {
		t.Fatalf("quantity: %v", err)
	}
	amt, err := money.Parse(amount)
	if err != nil {
		t.Fatalf("amount: %v", err)
	}
	s := &domain.Sale{
		BusinessID: f.biz, CustomerID: customerID, UserID: f.usr, ProductName: product,
		Quantity: q, Amount: amt, PaymentMethod: method, SaleDate: on,
	}
	if err := f.db.WithContext(f.ctx).Transaction(func(tx *gorm.DB) error {
		return sales.Record(f.ctx, tx, s)
	}); err != nil {
		t.Fatalf("recording sale: %v", err)
	}
}

// --- dashboard ---

func TestSummary_KeepsAdvancesSeparateFromWhatIsOwed(t *testing.T) {
	f := newFixture(t)
	owes := f.newCustomer(t, "Owes")
	ahead := f.newCustomer(t, "Paid ahead")
	f.debt(t, owes, "1000.00", daysAgo(1))
	f.payment(t, ahead, "300.00", daysAgo(1))

	s, err := f.svc.Summary(f.ctx)
	if err != nil {
		t.Fatalf("summary: %v", err)
	}
	// Before advances existed this was one net sum, and would read 700 — which
	// is neither what customers owe nor what the shop owes back.
	if s.TotalOutstandingDebt.String() != "1000.00" {
		t.Errorf("outstanding = %s, want 1000.00", s.TotalOutstandingDebt)
	}
	if s.TotalAdvancesHeld.String() != "300.00" || s.CustomersInCredit != 1 {
		t.Errorf("advances = %s held by %d, want 300.00 by 1", s.TotalAdvancesHeld, s.CustomersInCredit)
	}
}

// --- statement ---

func TestStatement_CarriesTheOpeningBalanceAndRunsTheBalance(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Mama Mboga")
	f.debt(t, c, "1000.00", daysAgo(40))  // before the period: the opening balance
	f.debt(t, c, "500.00", daysAgo(10))   // in the period
	f.payment(t, c, "300.00", daysAgo(5)) // in the period

	v, err := f.svc.Statement(f.ctx, c, reports.PeriodInput{
		From: daysAgo(30).Format("2006-01-02"), To: daysAgo(0).Format("2006-01-02"),
	})
	if err != nil {
		t.Fatalf("statement: %v", err)
	}
	if v.OpeningBalance.String() != "1000.00" {
		t.Errorf("opening = %s, want 1000.00: a statement must not restart from zero", v.OpeningBalance)
	}
	if len(v.Lines) != 2 {
		t.Fatalf("lines = %d, want 2", len(v.Lines))
	}
	if v.Lines[0].Balance.String() != "1500.00" || v.Lines[1].Balance.String() != "1200.00" {
		t.Errorf("running balances = %s, %s; want 1500.00, 1200.00", v.Lines[0].Balance, v.Lines[1].Balance)
	}
	if v.ClosingBalance.String() != "1200.00" || v.Standing != "owes" {
		t.Errorf("closing = %s (%s), want 1200.00 (owes)", v.ClosingBalance, v.Standing)
	}
}

func TestStatement_SaysAdvanceInWordsForANegativeBalance(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Paid ahead")
	f.debt(t, c, "200.00", daysAgo(3))
	f.payment(t, c, "500.00", daysAgo(2))

	v, err := f.svc.Statement(f.ctx, c, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("statement: %v", err)
	}
	if v.ClosingBalance.String() != "-300.00" || v.Standing != "advance" {
		t.Fatalf("closing = %s (%s), want -300.00 (advance)", v.ClosingBalance, v.Standing)
	}
}

func TestStatement_UnknownCustomerIsNotFound(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.Statement(f.ctx, uuid.New(), reports.PeriodInput{}); err != reports.ErrCustomerNotFound {
		t.Fatalf("got %v, want ErrCustomerNotFound", err)
	}
}

func TestPeriod_RefusesABackwardsOrOverlongRange(t *testing.T) {
	f := newFixture(t)
	if _, err := f.svc.SalesReport(f.ctx, reports.PeriodInput{From: "2026-10-10", To: "2026-10-01"}); err != reports.ErrPeriodBackwards {
		t.Errorf("backwards: got %v", err)
	}
	if _, err := f.svc.SalesReport(f.ctx, reports.PeriodInput{From: "2024-01-01", To: "2026-01-01"}); err != reports.ErrPeriodTooLong {
		t.Errorf("two years: got %v", err)
	}
}

// --- ageing ---

// TestAgeing_PaymentsClearTheOldestDebtFirst is the reason ageing uses FIFO.
// A customer who pays a little every week must still show the debt they keep
// not quite clearing as old; applied to the newest debt instead, payments would
// make every account look current forever.
func TestAgeing_PaymentsClearTheOldestDebtFirst(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Slow payer")
	f.debt(t, c, "1000.00", daysAgo(120)) // old
	f.debt(t, c, "500.00", daysAgo(10))   // recent
	f.payment(t, c, "600.00", daysAgo(5)) // clears 600 of the OLD debt

	v, err := f.svc.Ageing(f.ctx)
	if err != nil {
		t.Fatalf("ageing: %v", err)
	}
	if len(v.Rows) != 1 {
		t.Fatalf("rows = %d, want 1", len(v.Rows))
	}
	row := v.Rows[0]
	if row.Over90.String() != "400.00" {
		t.Errorf("over 90 = %s, want 400.00 — the rest of the old debt", row.Over90)
	}
	if row.Current.String() != "500.00" {
		t.Errorf("0-30 = %s, want 500.00 — the recent debt, untouched", row.Current)
	}
	if row.Total.String() != "900.00" {
		t.Errorf("total = %s, want 900.00", row.Total)
	}
	if row.DaysOldest < 119 {
		t.Errorf("oldest unpaid is %d days old, want about 120", row.DaysOldest)
	}
}

func TestAgeing_AnAdvanceClearsTheNextDebtAndSettledCustomersAreLeftOut(t *testing.T) {
	f := newFixture(t)
	ahead := f.newCustomer(t, "Paid ahead")
	f.payment(t, ahead, "500.00", daysAgo(60)) // advance
	f.debt(t, ahead, "300.00", daysAgo(50))    // fully covered by it

	settled := f.newCustomer(t, "Settled")
	f.debt(t, settled, "200.00", daysAgo(100))
	f.payment(t, settled, "200.00", daysAgo(99))

	v, err := f.svc.Ageing(f.ctx)
	if err != nil {
		t.Fatalf("ageing: %v", err)
	}
	if len(v.Rows) != 0 || v.Total != 0 {
		t.Fatalf("rows = %+v, want none — nobody here owes anything", v.Rows)
	}
}

// --- sales report ---

func TestSalesReport_GroupsProductsRegardlessOfHowTheyWereTyped(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Mama Mboga")
	f.sale(t, nil, domain.PaymentCash, "DAP 50kg", "2", "7000.00", daysAgo(1))
	f.sale(t, &c, domain.PaymentCredit, "dap 50kg ", "1", "3500.00", daysAgo(1))
	f.sale(t, nil, domain.PaymentCash, "Duodip 20ml", "0.5", "225.00", daysAgo(2))

	v, err := f.svc.SalesReport(f.ctx, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("sales report: %v", err)
	}
	if v.Count != 3 || v.Total.String() != "10725.00" {
		t.Errorf("count/total = %d/%s, want 3/10725.00", v.Count, v.Total)
	}
	if v.CashTotal.String() != "7225.00" || v.CreditTotal.String() != "3500.00" {
		t.Errorf("cash/credit = %s/%s", v.CashTotal, v.CreditTotal)
	}
	if len(v.TopProducts) != 2 {
		t.Fatalf("products = %+v, want DAP grouped as one", v.TopProducts)
	}
	if top := v.TopProducts[0]; top.Quantity.String() != "3" || top.Amount.String() != "10500.00" || top.Count != 2 {
		t.Errorf("top product = %+v, want 3 units, 10500.00, 2 sales", top)
	}
	// One row per day of the default 30-day window, quiet days included.
	if len(v.Daily) != 31 {
		t.Errorf("daily rows = %d, want 31 including days with no sales", len(v.Daily))
	}
}

// --- collections and staff ---

func TestCollections_CountsCreditSaleDebtsAsSalesNotTwice(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Mama Mboga")
	f.sale(t, &c, domain.PaymentCredit, "DAP 50kg", "1", "3500.00", daysAgo(3))
	f.debt(t, c, "200.00", daysAgo(3))
	f.payment(t, c, "1000.00", daysAgo(1))

	v, err := f.svc.Collections(f.ctx, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("collections: %v", err)
	}
	if v.TotalCollected.String() != "1000.00" || v.PaymentCount != 1 {
		t.Errorf("collected = %s over %d, want 1000.00 over 1", v.TotalCollected, v.PaymentCount)
	}
	if len(v.Staff) != 1 {
		t.Fatalf("staff = %+v", v.Staff)
	}
	s := v.Staff[0]
	if s.SalesCount != 1 || s.SalesTotal.String() != "3500.00" {
		t.Errorf("sales = %d/%s, want 1/3500.00", s.SalesCount, s.SalesTotal)
	}
	if s.DebtsCount != 1 || s.DebtsTotal.String() != "200.00" {
		t.Errorf("debts = %d/%s, want only the hand-entered 1/200.00", s.DebtsCount, s.DebtsTotal)
	}
}

// --- PDFs ---

func TestReportPDFs_AllRender(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Mama Mboga")
	f.debt(t, c, "1500.50", daysAgo(100))
	f.payment(t, c, "300.25", daysAgo(5))
	f.sale(t, &c, domain.PaymentCredit, "DAP 50kg", "1", "3500.00", daysAgo(2))

	repo := reports.NewRepository(f.db)
	stmt, err := f.svc.Statement(f.ctx, c, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("statement: %v", err)
	}
	ageing, err := f.svc.Ageing(f.ctx)
	if err != nil {
		t.Fatalf("ageing: %v", err)
	}
	sales, err := f.svc.SalesReport(f.ctx, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("sales: %v", err)
	}
	coll, err := f.svc.Collections(f.ctx, reports.PeriodInput{})
	if err != nil {
		t.Fatalf("collections: %v", err)
	}
	payables, err := f.svc.Payables(f.ctx, 7)
	if err != nil {
		t.Fatalf("payables: %v", err)
	}

	for name, render := range map[string]func() ([]byte, string, error){
		"statement":   func() ([]byte, string, error) { return repo.StatementPDF(f.ctx, stmt) },
		"ageing":      func() ([]byte, string, error) { return repo.AgeingPDF(f.ctx, ageing) },
		"sales":       func() ([]byte, string, error) { return repo.SalesPDF(f.ctx, sales) },
		"collections": func() ([]byte, string, error) { return repo.CollectionsPDF(f.ctx, coll) },
		"payables":    func() ([]byte, string, error) { return repo.PayablesPDF(f.ctx, payables) },
	} {
		out, filename, err := render()
		if err != nil {
			t.Errorf("%s: %v", name, err)
			continue
		}
		if !bytes.HasPrefix(out, []byte("%PDF-")) || filename == "" {
			t.Errorf("%s: not a PDF, or no filename (%q)", name, filename)
		}
	}
}
