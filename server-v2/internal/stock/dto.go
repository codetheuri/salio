package stock

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/quantity"
)

// StockRequestView is a stock request as returned to a client.
type StockRequestView struct {
	ID              uuid.UUID  `json:"id"`
	ProductName     string     `json:"product_name"`
	NeededOn        time.Time  `json:"needed_on"`
	Notes           *string    `json:"notes,omitempty"`
	UserID          uuid.UUID  `json:"user_id"`
	Status          string     `json:"status" enum:"pending,ordered"`
	PurchaseOrderID *uuid.UUID `json:"purchase_order_id,omitempty"`
	CreatedAt       time.Time  `json:"created_at"`
}

func requestView(r domain.StockRequest) StockRequestView {
	status := "pending"
	if r.PurchaseOrderID != nil {
		status = "ordered"
	}
	return StockRequestView{
		ID: r.ID, ProductName: r.ProductName, NeededOn: r.NeededOn, Notes: r.Notes,
		UserID: r.UserID, Status: status, PurchaseOrderID: r.PurchaseOrderID, CreatedAt: r.CreatedAt,
	}
}

// PurchaseOrderLineView is one product on an order.
type PurchaseOrderLineView struct {
	ProductName    string            `json:"product_name"`
	Quantity       quantity.Quantity `json:"quantity"`
	StockRequestID *uuid.UUID        `json:"stock_request_id,omitempty"`
}

// PurchaseOrderView is an order as returned to a client.
type PurchaseOrderView struct {
	ID            uuid.UUID                  `json:"id"`
	Reference     string                     `json:"reference" doc:"Human-readable number, e.g. PO-0007"`
	OrderNumber   int                        `json:"order_number"`
	SupplierName  string                     `json:"supplier_name"`
	SupplierPhone *string                    `json:"supplier_phone,omitempty"`
	Notes         *string                    `json:"notes,omitempty"`
	Status        domain.PurchaseOrderStatus `json:"status"`
	OrderedOn     time.Time                  `json:"ordered_on"`
	CreatedBy     uuid.UUID                  `json:"created_by"`
	CreatedAt     time.Time                  `json:"created_at"`
	Lines         []PurchaseOrderLineView    `json:"lines"`
}

func orderView(o domain.PurchaseOrder) PurchaseOrderView {
	lines := make([]PurchaseOrderLineView, 0, len(o.Lines))
	for _, l := range o.Lines {
		lines = append(lines, PurchaseOrderLineView{
			ProductName: l.ProductName, Quantity: l.Quantity, StockRequestID: l.StockRequestID,
		})
	}
	return PurchaseOrderView{
		ID: o.ID, Reference: o.Reference(), OrderNumber: o.OrderNumber,
		SupplierName: o.SupplierName, SupplierPhone: o.SupplierPhone, Notes: o.Notes,
		Status: o.Status, OrderedOn: o.OrderedOn, CreatedBy: o.CreatedBy,
		CreatedAt: o.CreatedAt, Lines: lines,
	}
}

// --- Requests ---

type CreateRequestInput struct {
	Body struct {
		// ID is optional; a client that generated one sends it, so a retry finds
		// the request it already made.
		ID          *uuid.UUID `json:"id,omitempty"`
		ProductName string     `json:"product_name" required:"true" minLength:"1" maxLength:"255" doc:"e.g. \"Duodip 20ml\""`
		NeededOn    *string    `json:"needed_on,omitempty" doc:"YYYY-MM-DD the product ran out; defaults to today"`
		Notes       *string    `json:"notes,omitempty" maxLength:"500"`
	}
}

type UpdateRequestInput struct {
	RequestID uuid.UUID `path:"requestID"`
	Body      struct {
		ProductName string  `json:"product_name" required:"true" minLength:"1" maxLength:"255"`
		NeededOn    *string `json:"needed_on,omitempty" doc:"YYYY-MM-DD"`
		Notes       *string `json:"notes,omitempty" maxLength:"500"`
	}
}

type ListRequestsInput struct {
	Status string `query:"status" default:"pending" enum:"pending,ordered,all"`
}

type RequestIDInput struct {
	RequestID uuid.UUID `path:"requestID"`
}

type OrderLineInput struct {
	StockRequestID *uuid.UUID        `json:"stock_request_id,omitempty" doc:"A pending request to order"`
	ProductName    *string           `json:"product_name,omitempty" maxLength:"255" doc:"Or an extra product not noted as a request"`
	Quantity       quantity.Quantity `json:"quantity" required:"true" doc:"How many to order"`
}

type CreateOrderInput struct {
	Body struct {
		SupplierName  string           `json:"supplier_name" required:"true" minLength:"1" maxLength:"255"`
		SupplierPhone *string          `json:"supplier_phone,omitempty" maxLength:"50"`
		Notes         *string          `json:"notes,omitempty" maxLength:"1000"`
		OrderedOn     *string          `json:"ordered_on,omitempty" doc:"YYYY-MM-DD; defaults to today"`
		Lines         []OrderLineInput `json:"lines" required:"true" minItems:"1"`
	}
}

type ListOrdersInput struct {
	Status string `query:"status" default:"all" enum:"ordered,cancelled,all"`
}

type OrderIDInput struct {
	OrderID uuid.UUID `path:"orderID"`
}

// --- Responses ---

type RequestOutput struct {
	Body struct {
		Success bool             `json:"success"`
		Message string           `json:"message"`
		Data    StockRequestView `json:"data"`
	}
}

type RequestListOutput struct {
	Body struct {
		Success bool               `json:"success"`
		Data    []StockRequestView `json:"data"`
	}
}

type OrderOutput struct {
	Body struct {
		Success bool              `json:"success"`
		Message string            `json:"message"`
		Data    PurchaseOrderView `json:"data"`
	}
}

type OrderListOutput struct {
	Body struct {
		Success bool                `json:"success"`
		Data    []PurchaseOrderView `json:"data"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
