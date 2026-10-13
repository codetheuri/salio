package stock_test

import (
	"bytes"
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/quantity"
	"salio/server-v2/internal/stock"
	"salio/server-v2/internal/testsupport"
)

type fixture struct {
	db     *gorm.DB
	svc    *stock.Service
	ctx    context.Context
	userID uuid.UUID
}

func newFixture(t *testing.T) fixture {
	t.Helper()
	db := testsupport.Connect(t)
	b := &domain.Business{Name: "Wanjiku Agrovet"}
	if err := tenant.Unscoped(db).Create(b).Error; err != nil {
		t.Fatalf("business: %v", err)
	}
	ctx := tenant.WithTenant(context.Background(), b.ID)
	u := &domain.User{Name: "Wanjiku", Phone: uuid.New().String()[:12], PasswordHash: "x", Role: domain.RoleOwner, IsActive: true}
	if err := db.WithContext(ctx).Create(u).Error; err != nil {
		t.Fatalf("user: %v", err)
	}
	return fixture{db: db, svc: stock.NewService(stock.NewRepository(db)), ctx: ctx, userID: u.ID}
}

func (f fixture) request(t *testing.T, product string) uuid.UUID {
	t.Helper()
	var in stock.CreateRequestInput
	in.Body.ProductName = product
	v, err := f.svc.CreateRequest(f.ctx, f.userID, in)
	if err != nil {
		t.Fatalf("request %s: %v", product, err)
	}
	return v.ID
}

func orderOf(lines ...stock.OrderLineInput) stock.CreateOrderInput {
	var in stock.CreateOrderInput
	in.Body.SupplierName = "Twiga Agro Distributors"
	in.Body.Lines = lines
	return in
}

func line(id uuid.UUID, qty int64) stock.OrderLineInput {
	return stock.OrderLineInput{StockRequestID: &id, Quantity: quantity.FromUnits(qty)}
}

func TestOrder_MovesRequestsOffTheDraftAndNumbersInSequence(t *testing.T) {
	f := newFixture(t)
	duodip := f.request(t, "Duodip 20ml")
	dap := f.request(t, "DAP 50kg")

	first, err := f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(duodip, 12)))
	if err != nil {
		t.Fatalf("first order: %v", err)
	}
	if first.Reference != "PO-0001" || first.Lines[0].ProductName != "Duodip 20ml" {
		t.Fatalf("first = %+v", first)
	}

	pending, err := f.svc.ListRequests(f.ctx, "pending")
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(pending) != 1 || pending[0].ID != dap {
		t.Fatalf("pending = %+v, want only DAP left on the draft", pending)
	}

	// An extra product typed at order time, not noted as a request first.
	extra := "Maize seed 2kg"
	second, err := f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(dap, 5),
		stock.OrderLineInput{ProductName: &extra, Quantity: quantity.FromUnits(10)}))
	if err != nil {
		t.Fatalf("second order: %v", err)
	}
	if second.Reference != "PO-0002" || len(second.Lines) != 2 {
		t.Fatalf("second = %+v", second)
	}
}

func TestOrder_EveryLineNeedsAQuantity(t *testing.T) {
	f := newFixture(t)
	id := f.request(t, "Duodip 20ml")
	if _, err := f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(id, 0))); !errors.Is(err, stock.ErrQuantityRequired) {
		t.Fatalf("got %v, want ErrQuantityRequired — \"send us some Duodip\" is not an order", err)
	}
}

func TestOrder_AnOrderedRequestIsFrozenUntilTheOrderIsCancelled(t *testing.T) {
	f := newFixture(t)
	id := f.request(t, "Duodip 20ml")
	order, err := f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(id, 12)))
	if err != nil {
		t.Fatalf("order: %v", err)
	}

	var edit stock.UpdateRequestInput
	edit.RequestID = id
	edit.Body.ProductName = "Something else"
	if _, err := f.svc.UpdateRequest(f.ctx, edit); !errors.Is(err, stock.ErrAlreadyOrdered) {
		t.Fatalf("edit: got %v, want ErrAlreadyOrdered", err)
	}
	if err := f.svc.DeleteRequest(f.ctx, id); !errors.Is(err, stock.ErrAlreadyOrdered) {
		t.Fatalf("delete: got %v, want ErrAlreadyOrdered", err)
	}

	if err := f.svc.CancelOrder(f.ctx, order.ID); err != nil {
		t.Fatalf("cancel: %v", err)
	}
	if _, err := f.svc.UpdateRequest(f.ctx, edit); err != nil {
		t.Fatalf("after cancelling, the request should be editable again: %v", err)
	}
	if err := f.svc.CancelOrder(f.ctx, order.ID); !errors.Is(err, stock.ErrOrderNotActive) {
		t.Fatalf("second cancel: got %v", err)
	}
}

func TestOrder_TwoOrdersCannotBothClaimOneRequest(t *testing.T) {
	f := newFixture(t)
	id := f.request(t, "Duodip 20ml")

	const attempts = 5
	var wg sync.WaitGroup
	errs := make([]error, attempts)
	for i := range attempts {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, errs[i] = f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(id, 1)))
		}(i)
	}
	wg.Wait()

	won := 0
	for _, err := range errs {
		if err == nil {
			won++
		} else if !errors.Is(err, stock.ErrRequestUnavailable) {
			t.Errorf("unexpected error: %v", err)
		}
	}
	if won != 1 {
		t.Fatalf("%d orders claimed the same request, want exactly 1", won)
	}
}

func TestOrderPDF_Renders(t *testing.T) {
	f := newFixture(t)
	id := f.request(t, "Duodip 20ml")
	order, err := f.svc.CreateOrder(f.ctx, f.userID, orderOf(line(id, 12)))
	if err != nil {
		t.Fatalf("order: %v", err)
	}
	out, name, err := f.svc.OrderPDF(f.ctx, order.ID)
	if err != nil {
		t.Fatalf("pdf: %v", err)
	}
	if !bytes.HasPrefix(out, []byte("%PDF-")) || name != "PO-0001.pdf" {
		t.Fatalf("not a PDF, or filename %q", name)
	}
}
