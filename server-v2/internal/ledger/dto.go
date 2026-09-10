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
}

func view(t domain.Transaction) TransactionView {
	return TransactionView{
		ID: t.ID, CustomerID: t.CustomerID, UserID: t.UserID,
		Type: t.Type, Amount: t.Amount, Description: t.Description,
		TransactionDate: t.TransactionDate, CreatedAt: t.CreatedAt, IsDeleted: t.IsDeleted,
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
		Description     *string                `json:"description,omitempty"`
		TransactionDate *string                `json:"transaction_date,omitempty" doc:"YYYY-MM-DD; defaults to today"`
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
