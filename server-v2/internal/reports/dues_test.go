package reports_test

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/reports"
)

func (f fixture) debtDue(t *testing.T, customerID uuid.UUID, amount string, on, due time.Time) {
	t.Helper()
	amt, _ := money.Parse(amount)
	d := domain.Transaction{CustomerID: customerID, UserID: f.usr, Type: domain.TypeDebt,
		Amount: amt, TransactionDate: on, DueDate: &due}
	if err := f.db.WithContext(f.ctx).Create(&d).Error; err != nil {
		t.Fatalf("debt: %v", err)
	}
}

func (f fixture) paid(t *testing.T, customerID uuid.UUID, amount string, on time.Time, method domain.PaymentMethod) {
	t.Helper()
	amt, _ := money.Parse(amount)
	p := domain.Transaction{CustomerID: customerID, UserID: f.usr, Type: domain.TypePayment,
		Amount: amt, TransactionDate: on, PaymentMethod: &method}
	if err := f.db.WithContext(f.ctx).Create(&p).Error; err != nil {
		t.Fatalf("payment: %v", err)
	}
}

func periodOf(days int) reports.PeriodInput {
	return reports.PeriodInput{From: daysAgo(days).Format("2006-01-02"), To: daysAgo(-1).Format("2006-01-02")}
}

// keepPDF checks a rendered PDF, and writes it to $SALIO_PDF_OUT when set, so
// a person can look at what the layout actually does.
func keepPDF(t *testing.T, name string, pdf []byte, err error) {
	t.Helper()
	if err != nil || !bytes.HasPrefix(pdf, []byte("%PDF")) {
		t.Fatalf("%s: %v", name, err)
	}
	if dir := os.Getenv("SALIO_PDF_OUT"); dir != "" {
		if err := os.WriteFile(filepath.Join(dir, name), pdf, 0o644); err != nil {
			t.Fatalf("writing %s: %v", name, err)
		}
	}
}

// Dates here sit well clear of today, so whether "today" is Nairobi's or UTC's
// cannot move a debt from one side of its due date to the other.

func TestDue_ListsWhoBrokeAPromiseAndWhoIsAboutTo(t *testing.T) {
	f := newFixture(t)
	late := f.newCustomer(t, "Late")
	soon := f.newCustomer(t, "Soon")
	later := f.newCustomer(t, "Later")
	settled := f.newCustomer(t, "Settled")
	noDate := f.newCustomer(t, "No date")

	f.debtDue(t, late, "1000.00", daysAgo(40), daysAgo(10))
	f.paid(t, late, "300.00", daysAgo(5), domain.PaymentCash) // FIFO: 700 of it still late
	f.debtDue(t, soon, "500.00", daysAgo(3), daysAgo(-3))
	f.debtDue(t, later, "800.00", daysAgo(3), daysAgo(-30))
	f.debtDue(t, settled, "400.00", daysAgo(40), daysAgo(10))
	f.paid(t, settled, "400.00", daysAgo(5), domain.PaymentMpesa)
	f.debt(t, noDate, "900.00", daysAgo(60))

	v, err := f.svc.Due(f.ctx, 7)
	if err != nil {
		t.Fatalf("due: %v", err)
	}
	if len(v.Rows) != 2 {
		t.Fatalf("rows = %+v, want Late and Soon only", v.Rows)
	}
	if v.Rows[0].Name != "Late" || v.Rows[0].Overdue.String() != "700.00" || v.Rows[0].DaysOverdue < 9 {
		t.Errorf("first row = %+v, want Late overdue 700.00 by ~10 days", v.Rows[0])
	}
	if v.Rows[1].Name != "Soon" || v.Rows[1].DueSoon.String() != "500.00" || v.Rows[1].Overdue != 0 {
		t.Errorf("second row = %+v, want Soon due 500.00, nothing overdue", v.Rows[1])
	}
	if v.Overdue.String() != "700.00" || v.DueSoon.String() != "500.00" {
		t.Errorf("totals overdue %s, due soon %s", v.Overdue, v.DueSoon)
	}
}

func TestAgeing_ShowsPastDueAndCreditLimits(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Kamau")
	limit, _ := money.Parse("1000.00")
	if err := f.db.WithContext(f.ctx).Model(&domain.Customer{}).Where("id = ?", c).
		Update("credit_limit", limit).Error; err != nil {
		t.Fatalf("limit: %v", err)
	}
	f.debtDue(t, c, "800.00", daysAgo(50), daysAgo(20))
	f.debtDue(t, c, "600.00", daysAgo(5), daysAgo(-25))

	v, err := f.svc.Ageing(f.ctx)
	if err != nil {
		t.Fatalf("ageing: %v", err)
	}
	if len(v.Rows) != 1 {
		t.Fatalf("rows = %d", len(v.Rows))
	}
	r := v.Rows[0]
	if r.Overdue.String() != "800.00" || r.NextDue == nil || !r.OverLimit || v.OverLimit != 1 {
		t.Fatalf("row = %+v; want 800.00 past due, a next due date, and over its 1000.00 limit", r)
	}
	pdf, _, err := reports.NewRepository(f.db).AgeingPDF(f.ctx, v)
	keepPDF(t, "ageing.pdf", pdf, err)
}

func TestCollections_SplitByHowTheMoneyCame(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Wanjiku")
	f.debt(t, c, "5000.00", daysAgo(10))
	f.paid(t, c, "1000.00", daysAgo(3), domain.PaymentCash)
	f.paid(t, c, "1500.00", daysAgo(3), domain.PaymentMpesa)
	f.paid(t, c, "700.00", daysAgo(2), domain.PaymentBank)
	f.payment(t, c, "200.00", daysAgo(2)) // from before methods were recorded

	v, err := f.svc.Collections(f.ctx, periodOf(10))
	if err != nil {
		t.Fatalf("collections: %v", err)
	}
	if v.Cash.String() != "1000.00" || v.Mpesa.String() != "1500.00" || v.Bank.String() != "700.00" ||
		v.Unrecorded.String() != "200.00" || v.TotalCollected.String() != "3400.00" {
		t.Fatalf("cash %s, mpesa %s, bank %s, unrecorded %s, total %s",
			v.Cash, v.Mpesa, v.Bank, v.Unrecorded, v.TotalCollected)
	}
	pdf, _, err := reports.NewRepository(f.db).CollectionsPDF(f.ctx, v)
	keepPDF(t, "collections.pdf", pdf, err)
}

func TestSalesReport_SplitsPaidSalesByMethod(t *testing.T) {
	f := newFixture(t)
	c := f.newCustomer(t, "Wanjiku")
	f.sale(t, nil, domain.PaymentCash, "DAP 50kg", "1", "3500.00", daysAgo(2))
	f.sale(t, nil, domain.PaymentMpesa, "Duodip 20ml", "2", "900.00", daysAgo(2))
	f.sale(t, nil, domain.PaymentBank, "Sprayer", "1", "4200.00", daysAgo(1))
	f.sale(t, &c, domain.PaymentCredit, "DAP 50kg", "1", "3500.00", daysAgo(1))

	v, err := f.svc.SalesReport(f.ctx, periodOf(10))
	if err != nil {
		t.Fatalf("sales: %v", err)
	}
	if v.CashTotal.String() != "3500.00" || v.MpesaTotal.String() != "900.00" || v.BankTotal.String() != "4200.00" ||
		v.PaidTotal.String() != "8600.00" || v.PaidCount != 3 || v.CreditTotal.String() != "3500.00" {
		t.Fatalf("report = %+v", v)
	}
	pdf, _, err := reports.NewRepository(f.db).SalesPDF(f.ctx, v)
	keepPDF(t, "sales.pdf", pdf, err)
}

func TestPayables_WhatTheShopOwesAndWhenItIsDue(t *testing.T) {
	f := newFixture(t)
	supplier := func(name string) uuid.UUID {
		s := domain.Supplier{Name: name, CreatedBy: f.usr}
		if err := f.db.WithContext(f.ctx).Create(&s).Error; err != nil {
			t.Fatalf("supplier: %v", err)
		}
		return s.ID
	}
	entry := func(sid uuid.UUID, typ domain.SupplierEntryType, amount string, on time.Time, due *time.Time) {
		amt, _ := money.Parse(amount)
		e := domain.SupplierTransaction{SupplierID: sid, UserID: f.usr, Type: typ, Amount: amt,
			Description: "x", TransactionDate: on, DueDate: due}
		if typ == domain.SupplierPayment {
			m := domain.PaymentMpesa
			e.PaymentMethod = &m
		}
		if err := f.db.WithContext(f.ctx).Create(&e).Error; err != nil {
			t.Fatalf("entry: %v", err)
		}
	}
	due := func(n int) *time.Time { d := daysAgo(n); return &d }

	elgon := supplier("Elgon Kenya")
	entry(elgon, domain.SupplierBill, "45000.00", daysAgo(40), due(10))
	entry(elgon, domain.SupplierPayment, "20000.00", daysAgo(5), nil)
	twiga := supplier("Twiga Foods")
	entry(twiga, domain.SupplierBill, "8000.00", daysAgo(2), due(-4))
	prepaid := supplier("Prepaid")
	entry(prepaid, domain.SupplierPayment, "3000.00", daysAgo(2), nil)

	v, err := f.svc.Payables(f.ctx, 7)
	if err != nil {
		t.Fatalf("payables: %v", err)
	}
	if len(v.Rows) != 2 || v.Rows[0].Name != "Elgon Kenya" {
		t.Fatalf("rows = %+v, want Elgon (overdue) first, then Twiga", v.Rows)
	}
	if v.Rows[0].Overdue.String() != "25000.00" || v.Rows[1].DueSoon.String() != "8000.00" {
		t.Errorf("elgon overdue %s, twiga due soon %s", v.Rows[0].Overdue, v.Rows[1].DueSoon)
	}
	if v.Owed.String() != "33000.00" || v.PrepaymentsHeld.String() != "3000.00" {
		t.Errorf("owed %s, prepayments %s; want 33000.00 and 3000.00 kept apart", v.Owed, v.PrepaymentsHeld)
	}
}
