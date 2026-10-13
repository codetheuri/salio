package customer

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// CustomerView is a customer as returned to a client, with its balance attached.
//
// The balance is not a field on domain.Customer — it is never stored, always
// derived from summing the ledger — so it is computed at the edge, once, for
// whichever customers are actually being returned, rather than being a property
// the domain type pretends to always have.
type CustomerView struct {
	ID      uuid.UUID    `json:"id"`
	Name    string       `json:"name"`
	Phone   *string      `json:"phone,omitempty"`
	Notes   *string      `json:"notes,omitempty"`
	Balance money.Amount `json:"balance"`

	// CreditLimit is how much this customer may owe; absent means no limit.
	// AvailableCredit is the limit less the balance — negative when they are
	// over it — and OverLimit says so plainly. The server never refuses a debt
	// over the limit (see migration 00008); the app warns at the counter.
	CreditLimit     *money.Amount `json:"credit_limit,omitempty"`
	AvailableCredit *money.Amount `json:"available_credit,omitempty"`
	OverLimit       bool          `json:"over_limit"`

	CreatedBy uuid.UUID `json:"created_by"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func view(c domain.Customer, balance money.Amount) CustomerView {
	v := CustomerView{
		ID: c.ID, Name: c.Name, Phone: c.Phone, Notes: c.Notes,
		Balance: balance, CreditLimit: c.CreditLimit, CreatedBy: c.CreatedBy,
		CreatedAt: c.CreatedAt, UpdatedAt: c.UpdatedAt,
	}
	if c.CreditLimit != nil {
		available := *c.CreditLimit - balance
		v.AvailableCredit = &available
		v.OverLimit = balance > *c.CreditLimit
	}
	return v
}

// --- Requests ---

type ListInput struct {
	Search  string `query:"search" doc:"Filter by name, case-insensitive"`
	Page    int    `query:"page" minimum:"1"`
	PerPage int    `query:"per_page" minimum:"1" maximum:"100"`
}

type CreateInput struct {
	Body struct {
		Name  string  `json:"name" required:"true" minLength:"1" maxLength:"255"`
		Phone *string `json:"phone,omitempty" maxLength:"50"`
		Notes *string `json:"notes,omitempty"`
	}
}

type UpdateInput struct {
	CustomerID uuid.UUID `path:"customerID"`
	Body       struct {
		Name  string  `json:"name" required:"true" minLength:"1" maxLength:"255"`
		Phone *string `json:"phone,omitempty" maxLength:"50"`
		Notes *string `json:"notes,omitempty"`
	}
}

type SetCreditLimitInput struct {
	CustomerID uuid.UUID `path:"customerID"`
	Body       struct {
		CreditLimit *money.Amount `json:"credit_limit" required:"true" nullable:"true" doc:"Decimal string, e.g. \"5000.00\"; null removes the limit"`
	}
}

type CustomerIDInput struct {
	CustomerID uuid.UUID `path:"customerID"`
}

// --- Responses ---

type ListOutput struct {
	Body struct {
		Success bool           `json:"success"`
		Data    []CustomerView `json:"data"`
		Meta    struct {
			Page       int   `json:"page"`
			PerPage    int   `json:"per_page"`
			Total      int64 `json:"total"`
			TotalPages int   `json:"total_pages"`
		} `json:"meta"`
	}
}

type CustomerOutput struct {
	Body struct {
		Success bool         `json:"success"`
		Message string       `json:"message"`
		Data    CustomerView `json:"data"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
