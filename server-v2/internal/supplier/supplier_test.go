package supplier_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/payment"
	"salio/server-v2/internal/supplier"
	"salio/server-v2/internal/testsupport"
)

type fixture struct {
	db     *gorm.DB
	svc    *supplier.Service
	ctx    context.Context
	biz    uuid.UUID
	userID uuid.UUID
}

func business(t *testing.T, db *gorm.DB, name string) (context.Context, uuid.UUID, uuid.UUID) {
	t.Helper()
	b := &domain.Business{Name: name}
	if err := tenant.Unscoped(db).Create(b).Error; err != nil {
		t.Fatalf("business: %v", err)
	}
	ctx := tenant.WithTenant(context.Background(), b.ID)
	u := &domain.User{Name: "Owner", Phone: uuid.New().String()[:12], PasswordHash: "x", Role: domain.RoleOwner, IsActive: true}
	if err := db.WithContext(ctx).Create(u).Error; err != nil {
		t.Fatalf("user: %v", err)
	}
	return ctx, b.ID, u.ID
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	db := testsupport.Connect(t)
	ctx, biz, userID := business(t, db, "Test Agrovet")
	return fixture{db: db, svc: supplier.NewService(supplier.NewRepository(db)), ctx: ctx, biz: biz, userID: userID}
}

func (f fixture) addSupplier(t *testing.T, name string) uuid.UUID {
	t.Helper()
	var in supplier.CreateInput
	in.Body.Name = name
	v, err := f.svc.Create(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("supplier: %v", err)
	}
	return v.ID
}

func entry(supplierID uuid.UUID, typ domain.SupplierEntryType, amount string) supplier.CreateEntryInput {
	var in supplier.CreateEntryInput
	in.Body.SupplierID, in.Body.Type = supplierID, typ
	in.Body.Amount, _ = money.Parse(amount)
	in.Body.Description = "Invoice 4471"
	if typ == domain.SupplierPayment {
		m := domain.PaymentCash
		in.Body.PaymentMethod = &m
		in.Body.Description = "Part payment"
	}
	return in
}

func TestSupplier_BillsAddAndPaymentsSubtract(t *testing.T) {
	f := newFixture(t)
	sid := f.addSupplier(t, "Elgon Kenya")

	bill := entry(sid, domain.SupplierBill, "45000.00")
	due := "2026-11-30"
	bill.Body.DueDate = &due
	if _, err := f.svc.RecordEntry(f.ctx, f.userID, bill); err != nil {
		t.Fatalf("bill: %v", err)
	}
	if _, err := f.svc.RecordEntry(f.ctx, f.userID, entry(sid, domain.SupplierPayment, "20000.00")); err != nil {
		t.Fatalf("payment: %v", err)
	}

	v, err := f.svc.Get(f.ctx, sid)
	if err != nil {
		t.Fatalf("get: %v", err)
	}
	if v.Balance.String() != "25000.00" {
		t.Fatalf("owed = %s, want 25000.00", v.Balance)
	}
	entries, err := f.svc.Entries(f.ctx, sid)
	if err != nil || len(entries) != 2 {
		t.Fatalf("entries = %d, %v; want 2", len(entries), err)
	}
}

func TestSupplier_CannotBeDeletedWhileEitherSideIsOwed(t *testing.T) {
	f := newFixture(t)
	sid := f.addSupplier(t, "Elgon Kenya")
	b, err := f.svc.RecordEntry(f.ctx, f.userID, entry(sid, domain.SupplierBill, "1000.00"))
	if err != nil {
		t.Fatalf("bill: %v", err)
	}
	if err := f.svc.Delete(f.ctx, sid); !errors.Is(err, supplier.ErrHasBalance) {
		t.Fatalf("delete while owing: got %v, want ErrHasBalance", err)
	}
	if err := f.svc.VoidEntry(f.ctx, b.ID); err != nil {
		t.Fatalf("void: %v", err)
	}
	if err := f.svc.Delete(f.ctx, sid); err != nil {
		t.Fatalf("delete at zero: %v", err)
	}
}

func TestSupplier_AnMpesaPaymentCodeIsRecordedOnce(t *testing.T) {
	f := newFixture(t)
	sid := f.addSupplier(t, "Elgon Kenya")
	pay := entry(sid, domain.SupplierPayment, "5000.00")
	m, code := domain.PaymentMpesa, "SJK4X7Y2PQ"
	pay.Body.PaymentMethod, pay.Body.Reference = &m, &code
	if _, err := f.svc.RecordEntry(f.ctx, f.userID, pay); err != nil {
		t.Fatalf("payment: %v", err)
	}
	if _, err := f.svc.RecordEntry(f.ctx, f.userID, pay); !errors.Is(err, payment.ErrDuplicateMpesaRef) {
		t.Fatalf("second payment on one code: got %v", err)
	}
}

func TestSupplier_ABillCanOnlyPointAtThisShopsLiveOrder(t *testing.T) {
	f := newFixture(t)
	sid := f.addSupplier(t, "Elgon Kenya")

	order := func(ctx context.Context, userID uuid.UUID, status domain.PurchaseOrderStatus, n int) uuid.UUID {
		o := &domain.PurchaseOrder{ID: uuid.New(), CreatedBy: userID, OrderNumber: n, SupplierName: "Elgon",
			Status: status, OrderedOn: domain.DateIn(time.Now(), domain.ZoneOrDefault(""))}
		if err := f.db.WithContext(ctx).Create(o).Error; err != nil {
			t.Fatalf("order: %v", err)
		}
		return o.ID
	}
	live := order(f.ctx, f.userID, domain.OrderStatusOrdered, 1)
	cancelled := order(f.ctx, f.userID, domain.OrderStatusCancelled, 2)
	otherCtx, _, otherUser := business(t, f.db, "Another Shop")
	theirs := order(otherCtx, otherUser, domain.OrderStatusOrdered, 1)

	for name, c := range map[string]struct {
		order uuid.UUID
		want  error
	}{
		"this shop's live order": {live, nil},
		"a cancelled order":      {cancelled, supplier.ErrOrderCancelled},
		"another shop's order":   {theirs, supplier.ErrOrderNotFound},
	} {
		in := entry(sid, domain.SupplierBill, "100.00")
		in.Body.PurchaseOrderID = &c.order
		if _, err := f.svc.RecordEntry(f.ctx, f.userID, in); !errors.Is(err, c.want) {
			t.Errorf("%s: got %v, want %v", name, err, c.want)
		}
	}
}

func TestSupplier_RulesForBillsAndPayments(t *testing.T) {
	f := newFixture(t)
	sid := f.addSupplier(t, "Elgon Kenya")

	noMethod := entry(sid, domain.SupplierPayment, "100.00")
	noMethod.Body.PaymentMethod = nil
	billWithMethod := entry(sid, domain.SupplierBill, "100.00")
	m := domain.PaymentCash
	billWithMethod.Body.PaymentMethod = &m
	early := entry(sid, domain.SupplierBill, "100.00")
	date, due := "2026-10-10", "2026-10-01"
	early.Body.TransactionDate, early.Body.DueDate = &date, &due

	for name, c := range map[string]struct {
		in   supplier.CreateEntryInput
		want error
	}{
		"payment without a method": {noMethod, payment.ErrMethodRequired},
		"bill with a method":       {billWithMethod, supplier.ErrMethodOnBill},
		"bill due before its date": {early, supplier.ErrDueBeforeDate},
		"unknown supplier":         {entry(uuid.New(), domain.SupplierBill, "100.00"), supplier.ErrNotFound},
	} {
		if _, err := f.svc.RecordEntry(f.ctx, f.userID, c.in); !errors.Is(err, c.want) {
			t.Errorf("%s: got %v, want %v", name, err, c.want)
		}
	}
}
