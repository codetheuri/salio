package syncengine_test

import (
	"context"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
	"salio/server-v2/internal/stock"
	"salio/server-v2/internal/syncengine"
)

// These cover the gap found in the October audit: the app writes through sync,
// and sync enforced none of the rules the REST routes did.

func pushAs(t *testing.T, f *fixture, ctx context.Context, in syncengine.PushInput) *syncengine.PushView {
	t.Helper()
	if in.Body.OperationID == uuid.Nil {
		in.Body.OperationID = id.New()
	}
	view, err := f.svc.Push(ctx, in)
	if err != nil {
		t.Fatalf("push: %v", err)
	}
	return view
}

func (f *fixture) balance(t *testing.T, customerID uuid.UUID) money.Amount {
	t.Helper()
	var b money.Amount
	if err := tenant.Unscoped(f.db).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ? AND is_deleted = false", customerID).
		Scan(&b).Error; err != nil {
		t.Fatalf("balance: %v", err)
	}
	return b
}

func entry(t *testing.T, f *fixture, customerID uuid.UUID, typ domain.TransactionType, amt string) syncengine.SyncTransaction {
	e := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: customerID, UserID: f.userID, Type: typ,
		Amount: amount(t, amt), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	if typ == domain.TypePayment {
		cash := domain.PaymentCash
		e.PaymentMethod = &cash
	}
	return e
}

func hasConflict(view *syncengine.PushView, reason string) bool {
	for _, c := range view.Conflicts {
		if c.Reason == reason {
			return true
		}
	}
	return false
}

// --- 1. a duplicate phone no longer costs the batch ---

func TestPush_ADuplicatePhoneIsOneConflictNotAFailedBatch(t *testing.T) {
	f := newFixture(t)
	phone := "0722000000"
	now := time.Now().UTC()

	// Two phones, both offline, both add the same walk-in customer. Before the
	// fix, the unique index aborted the whole push — and the valid third
	// customer in the batch was lost with it, every retry, forever.
	var in syncengine.PushInput
	in.Body.Customers = []syncengine.SyncCustomer{
		{ID: id.New(), Name: "Juma (phone A)", Phone: &phone, CreatedBy: f.userID, CreatedAt: now, UpdatedAt: now},
		{ID: id.New(), Name: "Juma (phone B)", Phone: &phone, CreatedBy: f.userID, CreatedAt: now, UpdatedAt: now},
		{ID: id.New(), Name: "Unrelated", CreatedBy: f.userID, CreatedAt: now, UpdatedAt: now},
	}
	view := pushAs(t, f, f.ctx, in)

	if view.AppliedCustomers != 2 {
		t.Errorf("applied %d customers, want 2 — the duplicate must cost only itself", view.AppliedCustomers)
	}
	if !hasConflict(view, syncengine.ReasonDuplicate) {
		t.Fatalf("conflicts = %+v, want a duplicate", view.Conflicts)
	}
}

// --- 2 & 3. owner-only actions stay owner-only ---

func TestPush_StaffCannotVoidAnEntry(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	debt := entry(t, f, cid, domain.TypeDebt, "500.00")
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{debt}))

	staffCtx, _ := f.staff(t, "0712000050")
	voided := debt
	voided.IsDeleted = true
	view := pushAs(t, f, staffCtx, pushOf(nil, []syncengine.SyncTransaction{voided}))

	if !hasConflict(view, syncengine.ReasonForbidden) {
		t.Fatalf("conflicts = %+v, want forbidden — staff voided an entry through sync", view.Conflicts)
	}
	if got := f.balance(t, cid); got.String() != "500.00" {
		t.Fatalf("balance = %s, want 500.00: the void must not have applied", got)
	}

	// The owner can.
	view = pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{voided}))
	if view.AppliedTransactions != 1 || f.balance(t, cid) != 0 {
		t.Fatalf("the owner's void did not apply: %+v", view)
	}
}

func TestPush_StaffCannotDeleteACustomer(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	staffCtx, _ := f.staff(t, "0712000051")
	view := pushAs(t, f, staffCtx, pushOf([]syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", CreatedBy: f.userID, IsDeleted: true,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"is_deleted"},
	}}, nil))

	if !hasConflict(view, syncengine.ReasonForbidden) {
		t.Fatalf("conflicts = %+v, want forbidden", view.Conflicts)
	}
	if f.loadCustomer(t, cid).IsDeleted {
		t.Fatal("staff deleted a customer through sync")
	}
}

// --- 4. a customer with a balance cannot be deleted ---

func TestPush_ACustomerWhoOwesCannotBeDeleted(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{
		entry(t, f, cid, domain.TypeDebt, "500.00"),
	}))

	view := pushAs(t, f, f.ctx, pushOf([]syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", CreatedBy: f.userID, IsDeleted: true,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"is_deleted"},
	}}, nil))

	if !hasConflict(view, syncengine.ReasonHasBalance) {
		t.Fatalf("conflicts = %+v, want has_balance", view.Conflicts)
	}
	if f.loadCustomer(t, cid).IsDeleted {
		t.Fatal("a customer owing 500 was deleted through sync")
	}
}

func TestPush_ACustomerHoldingAnAdvanceCannotBeDeletedEither(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Deposit Customer")
	// An advance is the shop's money owed back to the customer. Deleting the
	// account would make the shop forget it.
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{
		entry(t, f, cid, domain.TypePayment, "300.00"),
	}))

	view := pushAs(t, f, f.ctx, pushOf([]syncengine.SyncCustomer{{
		ID: cid, Name: "Deposit Customer", CreatedBy: f.userID, IsDeleted: true,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"is_deleted"},
	}}, nil))
	if !hasConflict(view, syncengine.ReasonHasBalance) {
		t.Fatalf("conflicts = %+v, want has_balance for a customer holding a 300 advance", view.Conflicts)
	}
}

func TestPush_SettlingAndDeletingInOneBatchWorks(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{
		entry(t, f, cid, domain.TypeDebt, "500.00"),
	}))

	// Offline, the owner records the final payment and then deletes the
	// customer. Deletions apply last in a push, so the batch sees the settled
	// balance — applying them in arrival order would refuse this.
	view := pushAs(t, f, f.ctx, pushOf(
		[]syncengine.SyncCustomer{{
			ID: cid, Name: "Mama Mboga", CreatedBy: f.userID, IsDeleted: true,
			UpdatedAt: time.Now().UTC(), ChangedFields: []string{"is_deleted"},
		}},
		[]syncengine.SyncTransaction{entry(t, f, cid, domain.TypePayment, "500.00")},
	))

	if len(view.Conflicts) != 0 {
		t.Fatalf("conflicts = %+v", view.Conflicts)
	}
	if !f.loadCustomer(t, cid).IsDeleted {
		t.Fatal("the settled customer was not deleted")
	}
}

// --- 5. advances and descriptions ---

func TestPush_APaymentAboveTheBalanceBecomesAnAdvance(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	view := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{
		entry(t, f, cid, domain.TypeDebt, "500.00"),
		entry(t, f, cid, domain.TypePayment, "800.00"),
	}))
	if len(view.Conflicts) != 0 || view.AppliedTransactions != 2 {
		t.Fatalf("view = %+v", view)
	}
	if got := f.balance(t, cid); got.String() != "-300.00" {
		t.Fatalf("balance = %s, want -300.00", got)
	}
}

func TestPush_ANewEntryWithoutADescriptionIsRefused(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	bare := entry(t, f, cid, domain.TypeDebt, "500.00")
	bare.Description = nil
	blank := entry(t, f, cid, domain.TypeDebt, "200.00")
	blank.Description = desc("   ")
	good := entry(t, f, cid, domain.TypeDebt, "100.00")

	view := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{bare, blank, good}))
	if view.AppliedTransactions != 1 {
		t.Fatalf("applied %d, want only the described entry", view.AppliedTransactions)
	}
	if got := f.balance(t, cid); got.String() != "100.00" {
		t.Fatalf("balance = %s, want 100.00", got)
	}
}

func TestPush_ARecordAttributedToSomeoneOutsideTheBusinessIsCreditedToThePusher(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	_, outsider := seedBusiness(t, f.db, "Beta Kiosk", "0712000099")

	e := entry(t, f, cid, domain.TypeDebt, "100.00")
	e.UserID = outsider
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{e}))

	var stored domain.Transaction
	if err := tenant.Unscoped(f.db).First(&stored, "id = ?", e.ID).Error; err != nil {
		t.Fatalf("loading: %v", err)
	}
	if stored.UserID != f.userID {
		t.Fatalf("entry credited to %s, want the pushing owner %s", stored.UserID, f.userID)
	}
}

// --- 6. sales ---

func sale(t *testing.T, f *fixture, customerID *uuid.UUID, method domain.PaymentMethod, product, qty, amt string) syncengine.SyncSale {
	q, err := quantity.Parse(qty)
	if err != nil {
		t.Fatalf("quantity: %v", err)
	}
	return syncengine.SyncSale{
		ID: id.New(), CustomerID: customerID, UserID: f.userID, ProductName: product,
		Quantity: q, Amount: amount(t, amt), PaymentMethod: method,
		SaleDate: time.Now().UTC(), CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}
}

func TestPush_ACreditSalePutsExactlyOneDebtOnTheAccount(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	s := sale(t, f, &cid, domain.PaymentCredit, "DAP 50kg", "2", "7000.00")

	// The phone recorded the sale offline and, for an immediate balance, the
	// debt too — with the id derived from the sale. It pushes both.
	phoneDebt := entry(t, f, cid, domain.TypeDebt, "7000.00")
	phoneDebt.ID = domain.SaleDebtID(s.ID)
	phoneDebt.SaleID = &s.ID

	var in syncengine.PushInput
	in.Body.Sales = []syncengine.SyncSale{s}
	in.Body.Transactions = []syncengine.SyncTransaction{phoneDebt}
	view := pushAs(t, f, f.ctx, in)

	if view.AppliedSales != 1 || len(view.Conflicts) != 0 {
		t.Fatalf("view = %+v", view)
	}
	if got := f.balance(t, cid); got.String() != "7000.00" {
		t.Fatalf("balance = %s, want 7000.00 — one debt, not two", got)
	}

	var debts []domain.Transaction
	tenant.Unscoped(f.db).Where("sale_id = ?", s.ID).Find(&debts)
	if len(debts) != 1 || debts[0].ID != domain.SaleDebtID(s.ID) {
		t.Fatalf("debts for the sale = %+v, want exactly one with the derived id", debts)
	}
	if debts[0].Description == nil || *debts[0].Description != "Sale: DAP 50kg x 2" {
		t.Fatalf("debt description = %v", debts[0].Description)
	}

	// A retry of the same sale changes nothing.
	pushAs(t, f, f.ctx, in)
	if got := f.balance(t, cid); got.String() != "7000.00" {
		t.Fatalf("after a retry, balance = %s", got)
	}
}

func TestPush_ACashSaleChangesNoBalance(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	var in syncengine.PushInput
	in.Body.Sales = []syncengine.SyncSale{
		sale(t, f, &cid, domain.PaymentCash, "Duodip 20ml", "1", "450.00"),
		sale(t, f, nil, domain.PaymentCash, "Maize seed 2kg", "0.5", "300.00"),
	}
	view := pushAs(t, f, f.ctx, in)
	if view.AppliedSales != 2 || f.balance(t, cid) != 0 {
		t.Fatalf("view = %+v, balance = %s", view, f.balance(t, cid))
	}
}

func TestPush_ACreditSaleWithoutACustomerIsOneConflict(t *testing.T) {
	f := newFixture(t)
	var in syncengine.PushInput
	in.Body.Sales = []syncengine.SyncSale{
		sale(t, f, nil, domain.PaymentCredit, "DAP 50kg", "1", "3500.00"),
		sale(t, f, nil, domain.PaymentCash, "DAP 50kg", "1", "3500.00"),
	}
	view := pushAs(t, f, f.ctx, in)
	if view.AppliedSales != 1 || !hasConflict(view, syncengine.ReasonInvalid) {
		t.Fatalf("view = %+v", view)
	}
}

func TestPush_VoidingACreditSaleVoidsItsDebtAndOnlyOwnersMay(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	s := sale(t, f, &cid, domain.PaymentCredit, "DAP 50kg", "1", "3500.00")
	var in syncengine.PushInput
	in.Body.Sales = []syncengine.SyncSale{s}
	pushAs(t, f, f.ctx, in)

	voided := s
	voided.IsDeleted = true
	in.Body.Sales = []syncengine.SyncSale{voided}

	staffCtx, _ := f.staff(t, "0712000052")
	if view := pushAs(t, f, staffCtx, in); !hasConflict(view, syncengine.ReasonForbidden) {
		t.Fatalf("staff voided a sale: %+v", view)
	}
	if got := f.balance(t, cid); got.String() != "3500.00" {
		t.Fatalf("balance = %s after a refused void", got)
	}

	pushAs(t, f, f.ctx, in)
	if got := f.balance(t, cid); got != 0 {
		t.Fatalf("balance = %s after the owner voided the sale, want 0 — its debt must go with it", got)
	}
}

func TestPush_ASalesDebtCannotBeVoidedOnItsOwn(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	s := sale(t, f, &cid, domain.PaymentCredit, "DAP 50kg", "1", "3500.00")
	var in syncengine.PushInput
	in.Body.Sales = []syncengine.SyncSale{s}
	pushAs(t, f, f.ctx, in)

	// A buggy client voids the debt by id without saying it came from a sale.
	debt := entry(t, f, cid, domain.TypeDebt, "3500.00")
	debt.ID = domain.SaleDebtID(s.ID)
	debt.Description = desc("Sale: DAP 50kg x 1")
	debt.IsDeleted = true
	view := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{debt}))

	if f.balance(t, cid).String() != "3500.00" {
		t.Fatal("a sale's debt was voided while the sale still stands")
	}
	if !hasConflict(view, syncengine.ReasonInvalid) {
		t.Fatalf("conflicts = %+v, want the refusal reported", view.Conflicts)
	}
}

// --- 7. stock requests ---

func TestPush_StockRequestsSyncAndFreezeOnceOrdered(t *testing.T) {
	f := newFixture(t)
	now := time.Now().UTC()
	req := syncengine.SyncStockRequest{
		ID: id.New(), UserID: f.userID, ProductName: "Duodip 20ml",
		NeededOn: now, CreatedAt: now, UpdatedAt: now,
	}
	var in syncengine.PushInput
	in.Body.StockRequests = []syncengine.SyncStockRequest{req}
	if view := pushAs(t, f, f.ctx, in); view.AppliedStockRequests != 1 {
		t.Fatalf("view = %+v", view)
	}

	// Editable while pending.
	edited := req
	edited.ProductName = "Duodip 50ml"
	edited.UpdatedAt = now.Add(time.Second)
	in.Body.StockRequests = []syncengine.SyncStockRequest{edited}
	if view := pushAs(t, f, f.ctx, in); view.AppliedStockRequests != 1 {
		t.Fatalf("edit while pending: %+v", view)
	}

	// Ordered on the server.
	svc := stock.NewService(stock.NewRepository(f.db))
	var order stock.CreateOrderInput
	order.Body.SupplierName = "Twiga Agro"
	order.Body.Lines = []stock.OrderLineInput{{StockRequestID: &req.ID, Quantity: quantity.FromUnits(12)}}
	if _, err := svc.CreateOrder(f.ctx, f.userID, order); err != nil {
		t.Fatalf("ordering: %v", err)
	}

	// Frozen now: what the supplier holds is what the record says.
	late := edited
	late.ProductName = "Something else"
	late.UpdatedAt = now.Add(time.Hour)
	in.Body.StockRequests = []syncengine.SyncStockRequest{late}
	if view := pushAs(t, f, f.ctx, in); !hasConflict(view, syncengine.ReasonAlreadyOrdered) {
		t.Fatalf("editing an ordered request: %+v", view)
	}
}

func TestPull_DeliversSalesAndStockRequestsAcrossPagesWithoutLosingAny(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	// Interleaved across all four tables, so any boundary chosen from one table
	// alone falls in the middle of the others' rows.
	want := map[uuid.UUID]bool{}
	for i := range 6 {
		s := sale(t, f, &cid, domain.PaymentCredit, "DAP 50kg", "1", "100.00")
		r := syncengine.SyncStockRequest{
			ID: id.New(), UserID: f.userID, ProductName: "Item",
			NeededOn: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
		}
		var in syncengine.PushInput
		in.Body.Sales = []syncengine.SyncSale{s}
		in.Body.StockRequests = []syncengine.SyncStockRequest{r}
		in.Body.Transactions = []syncengine.SyncTransaction{entry(t, f, cid, domain.TypePayment, "10.00")}
		pushAs(t, f, f.ctx, in)
		want[s.ID], want[r.ID] = true, true
		_ = i
	}

	got := map[uuid.UUID]bool{}
	cursor := int64(0)
	for range 100 {
		page := f.pull(t, cursor, 2)
		for _, s := range page.Sales {
			got[s.ID] = true
		}
		for _, r := range page.StockRequests {
			got[r.ID] = true
		}
		if page.HasMore && page.NextCursor <= cursor {
			t.Fatalf("has_more without progress at %d", cursor)
		}
		cursor = page.NextCursor
		if !page.HasMore {
			break
		}
	}
	for id := range want {
		if !got[id] {
			t.Fatalf("record %s never reached a pull", id)
		}
	}
}

// pushOf builds a push of customers and ledger entries.
func pushOf(customers []syncengine.SyncCustomer, txs []syncengine.SyncTransaction) syncengine.PushInput {
	var in syncengine.PushInput
	in.Body.Customers = customers
	in.Body.Transactions = txs
	return in
}
