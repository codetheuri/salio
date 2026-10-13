package syncengine_test

import (
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/syncengine"
)

// Payment methods, due dates, credit limits and suppliers, through sync — the
// path the app actually writes by.

func mpesaPayment(t *testing.T, f *fixture, customerID uuid.UUID, amt, code string) syncengine.SyncTransaction {
	e := entry(t, f, customerID, domain.TypePayment, amt)
	m := domain.PaymentMpesa
	e.PaymentMethod, e.Reference = &m, &code
	return e
}

// --- M-Pesa codes ---

func TestPush_OneMpesaPaymentRecordedOnTwoPhonesIsCountedOnce(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Wanjiku")
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{entry(t, f, cid, domain.TypeDebt, "1000.00")}))

	// The customer pays 600 by M-Pesa; the owner and a member of staff both
	// record it while offline, with different ids, the code typed differently.
	staffCtx, _ := f.staff(t, "0712000077")
	first := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{mpesaPayment(t, f, cid, "600.00", "SJK4X7Y2PQ")}))
	second := pushAs(t, f, staffCtx, pushOf(nil, []syncengine.SyncTransaction{mpesaPayment(t, f, cid, "600.00", "sjk4x7y2pq")}))

	if first.AppliedTransactions != 1 {
		t.Fatalf("first push: %+v", first)
	}
	if second.AppliedTransactions != 0 || !hasConflict(second, syncengine.ReasonDuplicate) {
		t.Fatalf("second push of the same M-Pesa code: %+v, want one duplicate conflict", second)
	}
	if got := f.balance(t, cid); got != amount(t, "400.00") {
		t.Fatalf("balance = %s, want 400.00 — the payment must be counted once", got)
	}
}

func TestPush_ResendingAPaymentWithTheCodeInLowerCaseIsNotAnEdit(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Wanjiku")
	p := mpesaPayment(t, f, cid, "250.00", "qfk1a2b3c4")
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{p}))

	// The phone never heard back and pushes the same record again, exactly as
	// it stored it: lower case.
	again := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{p}))
	if len(again.Conflicts) != 0 {
		t.Fatalf("re-sending an unchanged payment raised %+v", again.Conflicts)
	}
}

func TestPush_APaymentNeedsAMethodAndADebtMustNotHaveOne(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Wanjiku")

	noMethod := entry(t, f, cid, domain.TypePayment, "100.00")
	noMethod.PaymentMethod = nil
	debtWithMethod := entry(t, f, cid, domain.TypeDebt, "100.00")
	cash := domain.PaymentCash
	debtWithMethod.PaymentMethod = &cash
	badCode := mpesaPayment(t, f, cid, "100.00", "SJK4X7")

	view := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{noMethod, debtWithMethod, badCode}))
	if view.AppliedTransactions != 0 || len(view.Conflicts) != 3 {
		t.Fatalf("view = %+v, want three invalid conflicts", view)
	}
	for _, c := range view.Conflicts {
		if c.Reason != syncengine.ReasonInvalid {
			t.Errorf("conflict %+v, want invalid", c)
		}
	}
}

// --- Due dates ---

func TestPush_ADueDateTravelsWithTheDebtAndCannotBeEditedLater(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Kamau")

	d := entry(t, f, cid, domain.TypeDebt, "3500.00")
	due := time.Now().UTC().AddDate(0, 2, 0) // after harvest
	d.DueDate = &due
	pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{d}))

	page := f.pull(t, 0, 100)
	if len(page.Transactions) != 1 || page.Transactions[0].DueDate == nil {
		t.Fatalf("pulled %+v, want the debt with its due date", page.Transactions)
	}

	later := due.AddDate(0, 1, 0)
	d.DueDate = &later
	view := pushAs(t, f, f.ctx, pushOf(nil, []syncengine.SyncTransaction{d}))
	if len(view.Conflicts) != 1 || view.Conflicts[0].Field != "due_date" || view.Conflicts[0].Reason != syncengine.ReasonImmutable {
		t.Fatalf("moving a recorded due date: %+v, want an immutable conflict on due_date", view.Conflicts)
	}
}

// --- Credit limits ---

func limitOf(t *testing.T, f *fixture, cid uuid.UUID) *money.Amount {
	t.Helper()
	return f.loadCustomer(t, cid).CreditLimit
}

func TestPush_OnlyAnOwnerCanChangeACreditLimit(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Wanjiku")
	staffCtx, _ := f.staff(t, "0712000078")

	limit := amount(t, "5000.00")
	set := syncengine.SyncCustomer{
		ID: cid, Name: "Wanjiku", CreatedBy: f.userID, UpdatedAt: time.Now().UTC(),
		CreditLimit: &limit, ChangedFields: []string{"credit_limit"},
	}
	if v := pushAs(t, f, f.ctx, pushOf([]syncengine.SyncCustomer{set}, nil)); len(v.Conflicts) != 0 {
		t.Fatalf("owner setting a limit: %+v", v.Conflicts)
	}
	if got := limitOf(t, f, cid); got == nil || *got != limit {
		t.Fatalf("limit = %v, want 5000.00", got)
	}

	// Staff raise it and fix the name in the same edit: the name lands, the
	// limit is refused, and says so.
	raised := amount(t, "20000.00")
	edit := syncengine.SyncCustomer{
		ID: cid, Name: "Wanjiku Njeri", CreatedBy: f.userID, UpdatedAt: time.Now().UTC().Add(time.Second),
		CreditLimit: &raised, ChangedFields: []string{"name", "credit_limit"},
	}
	view := pushAs(t, f, staffCtx, pushOf([]syncengine.SyncCustomer{edit}, nil))
	if len(view.Conflicts) != 1 || view.Conflicts[0].Field != "credit_limit" || view.Conflicts[0].Reason != syncengine.ReasonForbidden {
		t.Fatalf("staff raising a limit: %+v, want one forbidden conflict on credit_limit", view.Conflicts)
	}
	c := f.loadCustomer(t, cid)
	if c.Name != "Wanjiku Njeri" || c.CreditLimit == nil || *c.CreditLimit != limit {
		t.Fatalf("customer = %q limit %v; want the name changed and the limit untouched", c.Name, c.CreditLimit)
	}

	// Staff pushing back the limit they pulled is not a change, and not an error.
	same := edit
	same.CreditLimit, same.UpdatedAt = &limit, time.Now().UTC().Add(2*time.Second)
	if v := pushAs(t, f, staffCtx, pushOf([]syncengine.SyncCustomer{same}, nil)); len(v.Conflicts) != 0 {
		t.Fatalf("staff re-sending the stored limit: %+v, want no conflicts", v.Conflicts)
	}
}

func TestPush_AWholeRecordPushNeverWipesACreditLimit(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Wanjiku")
	limit := amount(t, "5000.00")
	pushAs(t, f, f.ctx, pushOf([]syncengine.SyncCustomer{{
		ID: cid, Name: "Wanjiku", CreatedBy: f.userID, UpdatedAt: time.Now().UTC(),
		CreditLimit: &limit, ChangedFields: []string{"credit_limit"},
	}}, nil))

	// A client that does not know the field: no changed_fields, no limit.
	pushAs(t, f, f.ctx, pushOf([]syncengine.SyncCustomer{{
		ID: cid, Name: "Wanjiku N.", CreatedBy: f.userID, UpdatedAt: time.Now().UTC().Add(time.Second),
	}}, nil))

	if got := limitOf(t, f, cid); got == nil || *got != limit {
		t.Fatalf("limit after a whole-record push = %v, want 5000.00 kept", got)
	}
}

// --- Suppliers ---

func supplierBill(supplierID uuid.UUID, amt money.Amount) syncengine.SyncSupplierTransaction {
	return syncengine.SyncSupplierTransaction{
		ID: id.New(), SupplierID: supplierID, Type: domain.SupplierBill, Amount: amt,
		Description: "Invoice 4471: 10 x DAP 50kg", TransactionDate: time.Now().UTC(),
	}
}

func supplierBalance(t *testing.T, f *fixture, supplierID uuid.UUID) money.Amount {
	t.Helper()
	var b money.Amount
	if err := tenant.Unscoped(f.db).Model(&domain.SupplierTransaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'bill' THEN amount ELSE -amount END), 0)").
		Where("supplier_id = ? AND is_deleted = false", supplierID).Scan(&b).Error; err != nil {
		t.Fatalf("supplier balance: %v", err)
	}
	return b
}

func TestPush_AnOwnerRecordsASupplierItsBillAndAPaymentOffline(t *testing.T) {
	f := newFixture(t)
	sid := id.New()
	bill := supplierBill(sid, amount(t, "45000.00"))
	mpesa := domain.PaymentMpesa
	code := "rbx9k2m4p1"
	pay := syncengine.SyncSupplierTransaction{
		ID: id.New(), SupplierID: sid, Type: domain.SupplierPayment, Amount: amount(t, "20000.00"),
		Description: "Part payment", TransactionDate: time.Now().UTC(),
		PaymentMethod: &mpesa, Reference: &code,
	}

	var in syncengine.PushInput
	in.Body.Suppliers = []syncengine.SyncSupplier{{ID: sid, Name: "Elgon Kenya", CreatedBy: f.userID}}
	in.Body.SupplierTransactions = []syncengine.SyncSupplierTransaction{bill, pay}
	view := pushAs(t, f, f.ctx, in)

	if view.AppliedSuppliers != 1 || view.AppliedSupplierTransactions != 2 || len(view.Conflicts) != 0 {
		t.Fatalf("view = %+v", view)
	}
	if got := supplierBalance(t, f, sid); got != amount(t, "25000.00") {
		t.Fatalf("owed to supplier = %s, want 25000.00", got)
	}

	// Deleting a supplier the shop still owes is refused, like a customer.
	in = syncengine.PushInput{}
	in.Body.Suppliers = []syncengine.SyncSupplier{{ID: sid, Name: "Elgon Kenya", CreatedBy: f.userID, IsDeleted: true}}
	if v := pushAs(t, f, f.ctx, in); !hasConflict(v, syncengine.ReasonHasBalance) {
		t.Fatalf("deleting a supplier still owed 25000: %+v, want has_balance", v.Conflicts)
	}
}

func TestSync_StaffNeitherReceiveNorWriteSupplierRecords(t *testing.T) {
	f := newFixture(t)
	sid := id.New()
	var in syncengine.PushInput
	in.Body.Suppliers = []syncengine.SyncSupplier{{ID: sid, Name: "Elgon Kenya", CreatedBy: f.userID}}
	in.Body.SupplierTransactions = []syncengine.SyncSupplierTransaction{supplierBill(sid, amount(t, "45000.00"))}
	pushAs(t, f, f.ctx, in)

	staffCtx, _ := f.staff(t, "0712000079")
	page, err := f.svc.Pull(staffCtx, 0, 100)
	if err != nil {
		t.Fatalf("staff pull: %v", err)
	}
	if len(page.Suppliers) != 0 || len(page.SupplierTransactions) != 0 {
		t.Fatalf("a staff phone received %d suppliers and %d supplier entries, want none",
			len(page.Suppliers), len(page.SupplierTransactions))
	}
	if owner := f.pull(t, 0, 100); len(owner.Suppliers) != 1 || len(owner.SupplierTransactions) != 1 {
		t.Fatalf("the owner received %d suppliers and %d entries, want 1 and 1",
			len(owner.Suppliers), len(owner.SupplierTransactions))
	}

	// And a staff phone's supplier writes are refused one by one.
	var staffIn syncengine.PushInput
	staffIn.Body.SupplierTransactions = []syncengine.SyncSupplierTransaction{supplierBill(sid, amount(t, "1.00"))}
	staffIn.Body.Transactions = []syncengine.SyncTransaction{entry(t, f, f.customer(t, "Wanjiku"), domain.TypeDebt, "50.00")}
	view := pushAs(t, f, staffCtx, staffIn)
	if !hasConflict(view, syncengine.ReasonForbidden) || view.AppliedTransactions != 1 {
		t.Fatalf("staff push: %+v, want the supplier bill forbidden and the debt applied", view)
	}
}

func TestPush_ABillForAnUnknownSupplierIsOneConflict(t *testing.T) {
	f := newFixture(t)
	var in syncengine.PushInput
	in.Body.SupplierTransactions = []syncengine.SyncSupplierTransaction{supplierBill(id.New(), amount(t, "100.00"))}
	view := pushAs(t, f, f.ctx, in)
	if !hasConflict(view, syncengine.ReasonUnknownSupplier) {
		t.Fatalf("view = %+v, want unknown_supplier", view)
	}
}
