package ledger

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// TransactionView is a transaction as returned to a client.
type TransactionView struct {
	ID              uuid.UUID              `json:"id"`
	CustomerID      uuid.UUID              `json:"customer_id"`
	UserID          uuid.UUID              `json:"user_id"`
	Type            domain.TransactionType `json:"type"`
	Amount          money.Amount           `json:"amount"`
	Description     *string                `json:"description,omitempty"`
	TransactionDate time.Time              `json:"transaction_date"`
	CreatedAt       time.Time              `json:"created_at"`
	IsDeleted       bool                   `json:"is_deleted"`

	// SaleID is set when this debt came from a credit sale. Such a debt can
	// only be voided by voiding the sale.
	SaleID *uuid.UUID `json:"sale_id,omitempty"`

	// How a payment arrived. Absent on debts, and on payments recorded before
	// the method was asked for.
	PaymentMethod *domain.PaymentMethod `json:"payment_method,omitempty"`
	Reference     *string               `json:"reference,omitempty" doc:"M-Pesa code or bank reference"`

	// When a debt was agreed to be paid by.
	DueDate *time.Time `json:"due_date,omitempty"`
}

func view(t domain.Transaction) TransactionView {
	return TransactionView{
		ID: t.ID, CustomerID: t.CustomerID, UserID: t.UserID,
		Type: t.Type, Amount: t.Amount, Description: t.Description,
		TransactionDate: t.TransactionDate, CreatedAt: t.CreatedAt, IsDeleted: t.IsDeleted,
		SaleID: t.SaleID, PaymentMethod: t.PaymentMethod, Reference: t.Reference, DueDate: t.DueDate,
	}
}

func views(ts []domain.Transaction) []TransactionView {
	out := make([]TransactionView, 0, len(ts))
	for _, t := range ts {
		out = append(out, view(t))
	}
	return out
}

// --- Requests ---

type ListForCustomerInput struct {
	CustomerID uuid.UUID `path:"customerID"`
}

type CreateInput struct {
	Body struct {
		CustomerID uuid.UUID `json:"customer_id" required:"true"`
		// Type and Amount are validated by hand in the service rather than by
		// Huma struct tags: money.Amount unmarshals from a decimal string (see
		// pkg money), so a schema-level "minimum" constraint cannot see its
		// value the way it can a bare number.
		Type            domain.TransactionType `json:"type" required:"true" doc:"debt or payment"`
		Amount          money.Amount           `json:"amount" required:"true" doc:"Decimal string, e.g. \"1500.50\""`
		Description     string                 `json:"description" required:"true" minLength:"1" maxLength:"500" doc:"What the debt or payment was for"`
		TransactionDate *string                `json:"transaction_date,omitempty" doc:"YYYY-MM-DD; defaults to today"`

		PaymentMethod *domain.PaymentMethod `json:"payment_method,omitempty" enum:"cash,mpesa,bank" doc:"Required for a payment; not allowed on a debt"`
		Reference     *string               `json:"reference,omitempty" maxLength:"30" doc:"Payments by M-Pesa or bank: the M-Pesa code (e.g. SJK4X7Y2PQ) or bank reference"`
		DueDate       *string               `json:"due_date,omitempty" doc:"Debts only: YYYY-MM-DD the customer agreed to pay by"`
	}
}

type TransactionIDInput struct {
	TransactionID uuid.UUID `path:"transactionID"`
}

// --- Responses ---

type ListOutput struct {
	Body struct {
		Success bool              `json:"success"`
		Data    []TransactionView `json:"data"`
	}
}

type TransactionOutput struct {
	Body struct {
		Success bool            `json:"success"`
		Message string          `json:"message"`
		Data    TransactionView `json:"data"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
