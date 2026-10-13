package supplier

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// SupplierView is a supplier with what the shop owes them.
type SupplierView struct {
	ID    uuid.UUID `json:"id"`
	Name  string    `json:"name"`
	Phone *string   `json:"phone,omitempty"`
	Notes *string   `json:"notes,omitempty"`

	// Balance is what the shop owes this supplier. Negative means the supplier
	// holds a prepayment from the shop.
	Balance   money.Amount `json:"balance"`
	CreatedBy uuid.UUID    `json:"created_by"`
	CreatedAt time.Time    `json:"created_at"`
	UpdatedAt time.Time    `json:"updated_at"`
}

func view(s domain.Supplier, balance money.Amount) SupplierView {
	return SupplierView{
		ID: s.ID, Name: s.Name, Phone: s.Phone, Notes: s.Notes, Balance: balance,
		CreatedBy: s.CreatedBy, CreatedAt: s.CreatedAt, UpdatedAt: s.UpdatedAt,
	}
}

// EntryView is a bill or payment as returned to a client.
type EntryView struct {
	ID              uuid.UUID                `json:"id"`
	SupplierID      uuid.UUID                `json:"supplier_id"`
	UserID          uuid.UUID                `json:"user_id"`
	Type            domain.SupplierEntryType `json:"type"`
	Amount          money.Amount             `json:"amount"`
	Description     string                   `json:"description"`
	TransactionDate time.Time                `json:"transaction_date"`
	DueDate         *time.Time               `json:"due_date,omitempty"`
	PaymentMethod   *domain.PaymentMethod    `json:"payment_method,omitempty"`
	Reference       *string                  `json:"reference,omitempty"`
	PurchaseOrderID *uuid.UUID               `json:"purchase_order_id,omitempty"`
	CreatedAt       time.Time                `json:"created_at"`
	IsDeleted       bool                     `json:"is_deleted"`
}

func entryView(t domain.SupplierTransaction) EntryView {
	return EntryView{
		ID: t.ID, SupplierID: t.SupplierID, UserID: t.UserID, Type: t.Type, Amount: t.Amount,
		Description: t.Description, TransactionDate: t.TransactionDate, DueDate: t.DueDate,
		PaymentMethod: t.PaymentMethod, Reference: t.Reference, PurchaseOrderID: t.PurchaseOrderID,
		CreatedAt: t.CreatedAt, IsDeleted: t.IsDeleted,
	}
}

// --- Requests ---

type ListInput struct {
	Search string `query:"search" doc:"Filter by name, case-insensitive"`
}

type SupplierBody struct {
	Name  string  `json:"name" required:"true" minLength:"1" maxLength:"255" doc:"e.g. \"Elgon Kenya — Ruiru depot\""`
	Phone *string `json:"phone,omitempty" maxLength:"50"`
	Notes *string `json:"notes,omitempty" maxLength:"1000"`
}

type CreateInput struct {
	Body struct {
		// ID is optional. The phone generates one for everything it creates,
		// and sending it makes a retried request find what it already made.
		ID *uuid.UUID `json:"id,omitempty"`
		SupplierBody
	}
}

type UpdateInput struct {
	SupplierID uuid.UUID `path:"supplierID"`
	Body       SupplierBody
}

type SupplierIDInput struct {
	SupplierID uuid.UUID `path:"supplierID"`
}

type CreateEntryInput struct {
	Body struct {
		ID              *uuid.UUID               `json:"id,omitempty"`
		SupplierID      uuid.UUID                `json:"supplier_id" required:"true"`
		Type            domain.SupplierEntryType `json:"type" required:"true" enum:"bill,payment" doc:"bill: goods received on credit. payment: the shop paying."`
		Amount          money.Amount             `json:"amount" required:"true" doc:"Decimal string, e.g. \"45000.00\""`
		Description     string                   `json:"description" required:"true" minLength:"1" maxLength:"500" doc:"e.g. \"Invoice 4471: 20 x DAP 50kg\""`
		TransactionDate *string                  `json:"transaction_date,omitempty" doc:"YYYY-MM-DD; defaults to today"`
		DueDate         *string                  `json:"due_date,omitempty" doc:"Bills only: YYYY-MM-DD it must be paid by"`
		PaymentMethod   *domain.PaymentMethod    `json:"payment_method,omitempty" enum:"cash,mpesa,bank" doc:"Required for a payment"`
		Reference       *string                  `json:"reference,omitempty" maxLength:"30" doc:"M-Pesa code or bank reference"`
		PurchaseOrderID *uuid.UUID               `json:"purchase_order_id,omitempty" doc:"Bills only: the order this delivery was for"`
	}
}

type EntryIDInput struct {
	EntryID uuid.UUID `path:"entryID"`
}

// --- Responses ---

type ListOutput struct {
	Body struct {
		Success bool           `json:"success"`
		Data    []SupplierView `json:"data"`
	}
}

type SupplierOutput struct {
	Body struct {
		Success bool         `json:"success"`
		Message string       `json:"message"`
		Data    SupplierView `json:"data"`
	}
}

type EntriesOutput struct {
	Body struct {
		Success bool        `json:"success"`
		Data    []EntryView `json:"data"`
	}
}

type EntryOutput struct {
	Body struct {
		Success bool      `json:"success"`
		Message string    `json:"message"`
		Data    EntryView `json:"data"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
