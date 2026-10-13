package sales

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
)

// SaleView is a sale as returned to a client.
type SaleView struct {
	ID            uuid.UUID            `json:"id"`
	CustomerID    *uuid.UUID           `json:"customer_id,omitempty"`
	CustomerName  *string              `json:"customer_name,omitempty"`
	UserID        uuid.UUID            `json:"user_id"`
	ProductName   string               `json:"product_name"`
	Quantity      quantity.Quantity    `json:"quantity"`
	Amount        money.Amount         `json:"amount"`
	PaymentMethod domain.PaymentMethod `json:"payment_method"`
	Notes         *string              `json:"notes,omitempty"`
	SaleDate      time.Time            `json:"sale_date"`
	Reference     *string              `json:"reference,omitempty" doc:"M-Pesa code or bank reference"`
	DueDate       *time.Time           `json:"due_date,omitempty" doc:"Credit sales: when it is to be paid by"`
	CreatedAt     time.Time            `json:"created_at"`
	IsDeleted     bool                 `json:"is_deleted"`

	// DebtTransactionID is the debt this sale put on the customer's account,
	// for a credit sale. Its id is derived from the sale's — see
	// domain.SaleDebtID — so a phone can compute it without asking.
	DebtTransactionID *uuid.UUID `json:"debt_transaction_id,omitempty"`
}

func view(s domain.Sale, customerName *string) SaleView {
	v := SaleView{
		ID: s.ID, CustomerID: s.CustomerID, CustomerName: customerName, UserID: s.UserID,
		ProductName: s.ProductName, Quantity: s.Quantity, Amount: s.Amount,
		PaymentMethod: s.PaymentMethod, Notes: s.Notes, SaleDate: s.SaleDate,
		Reference: s.Reference, DueDate: s.DueDate,
		CreatedAt: s.CreatedAt, IsDeleted: s.IsDeleted,
	}
	if s.PaymentMethod == domain.PaymentCredit {
		debtID := domain.SaleDebtID(s.ID)
		v.DebtTransactionID = &debtID
	}
	return v
}

// --- Requests ---

type CreateInput struct {
	Body struct {
		// ID is optional. A client that already generated one — the phone does,
		// for everything it creates — sends it, so a retried request finds the
		// sale it already made instead of recording a second one.
		ID            *uuid.UUID           `json:"id,omitempty"`
		ProductName   string               `json:"product_name" required:"true" minLength:"1" maxLength:"255" doc:"As the shop names it, e.g. \"DAP 50kg\""`
		Quantity      quantity.Quantity    `json:"quantity" required:"true"`
		Amount        money.Amount         `json:"amount" required:"true" doc:"The sale total, decimal string, e.g. \"3500.00\""`
		PaymentMethod domain.PaymentMethod `json:"payment_method" required:"true" enum:"cash,mpesa,bank,credit" doc:"How it was paid; credit puts the amount on the customer's account"`
		Reference     *string              `json:"reference,omitempty" maxLength:"30" doc:"M-Pesa code or bank reference, for a sale paid that way"`
		DueDate       *string              `json:"due_date,omitempty" doc:"Credit sales only: YYYY-MM-DD the customer agreed to pay by"`
		CustomerID    *uuid.UUID           `json:"customer_id,omitempty" doc:"Required for credit, optional for cash"`
		Notes         *string              `json:"notes,omitempty" maxLength:"500"`
		SaleDate      *string              `json:"sale_date,omitempty" doc:"YYYY-MM-DD; defaults to today"`
	}
}

type ListInput struct {
	From       string    `query:"from" doc:"YYYY-MM-DD, inclusive. Defaults to 30 days ago."`
	To         string    `query:"to" doc:"YYYY-MM-DD, inclusive. Defaults to today."`
	CustomerID uuid.UUID `query:"customer_id" doc:"Only this customer's sales"`
	Page       int       `query:"page" default:"1" minimum:"1"`
	PerPage    int       `query:"per_page" default:"50" minimum:"1" maximum:"200"`
}

type SaleIDInput struct {
	SaleID uuid.UUID `path:"saleID"`
}

// --- Responses ---

type SaleOutput struct {
	Body struct {
		Success bool     `json:"success"`
		Message string   `json:"message"`
		Data    SaleView `json:"data"`
	}
}

type ListOutput struct {
	Body struct {
		Success bool       `json:"success"`
		Data    []SaleView `json:"data"`
		Total   int64      `json:"total"`
		Page    int        `json:"page"`
		PerPage int        `json:"per_page"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
