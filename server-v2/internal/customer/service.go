package customer

import (
	"context"
	"errors"
	"strings"

	"github.com/codetheuri/tusk/v2/pkg/query"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// ErrHasBalance blocks deleting a customer who still owes money or is owed a
// refund. A shopkeeper deletes a customer to tidy up, not to forgive a debt —
// forgiving one is a payment, an explicit act that belongs in the ledger, not a
// side effect of a delete button.
var ErrHasBalance = errors.New("cannot delete a customer with a non-zero balance: clear what they owe, or return the advance you hold for them, first")

// ErrNegativeCreditLimit refuses a limit below zero. Zero itself is allowed: it
// means "no credit for this customer", which is a real decision a shop makes.
var ErrNegativeCreditLimit = errors.New("a credit limit cannot be negative")

// ValidateCreditLimit checks a limit, whichever path sets it.
func ValidateCreditLimit(limit *money.Amount) error {
	if limit != nil && *limit < 0 {
		return ErrNegativeCreditLimit
	}
	return nil
}

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// List returns a page of customers with each one's balance attached.
//
// Balances are fetched with one query per page rather than one per customer:
// a page is at most MaxPerPage rows, and N+1 queries here would mean the list
// endpoint's cost scales with page size instead of staying constant.
func (s *Service) List(ctx context.Context, q query.Query) ([]CustomerView, query.Meta, error) {
	customers, meta, err := s.repo.List(ctx, q)
	if err != nil {
		return nil, query.Meta{}, err
	}
	if len(customers) == 0 {
		return []CustomerView{}, meta, nil
	}

	ids := make([]uuid.UUID, len(customers))
	for i, c := range customers {
		ids[i] = c.ID
	}
	balances, err := s.repo.BalancesFor(ctx, ids)
	if err != nil {
		return nil, query.Meta{}, err
	}

	views := make([]CustomerView, len(customers))
	for i, c := range customers {
		views[i] = view(c, balances[c.ID])
	}
	return views, meta, nil
}

func (s *Service) Get(ctx context.Context, id uuid.UUID) (*CustomerView, error) {
	c, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	balance, err := s.repo.Balance(ctx, id)
	if err != nil {
		return nil, err
	}
	v := view(*c, balance)
	return &v, nil
}

func (s *Service) Create(ctx context.Context, createdBy uuid.UUID, in CreateInput) (*CustomerView, error) {
	c := &domain.Customer{
		Name:      strings.TrimSpace(in.Body.Name),
		Phone:     normalisedOrNil(in.Body.Phone),
		Notes:     in.Body.Notes,
		CreatedBy: createdBy,
	}
	if err := s.repo.Create(ctx, c); err != nil {
		return nil, err
	}
	v := view(*c, 0)
	return &v, nil
}

func (s *Service) Update(ctx context.Context, id uuid.UUID, in UpdateInput) (*CustomerView, error) {
	c, err := s.repo.Update(ctx, id, strings.TrimSpace(in.Body.Name), normalisedOrNil(in.Body.Phone), in.Body.Notes)
	if err != nil {
		return nil, err
	}
	balance, err := s.repo.Balance(ctx, id)
	if err != nil {
		return nil, err
	}
	v := view(*c, balance)
	return &v, nil
}

// SetCreditLimit sets or (with nil) removes a customer's credit limit.
func (s *Service) SetCreditLimit(ctx context.Context, id uuid.UUID, limit *money.Amount) (*CustomerView, error) {
	if err := ValidateCreditLimit(limit); err != nil {
		return nil, err
	}
	c, err := s.repo.SetCreditLimit(ctx, id, limit)
	if err != nil {
		return nil, err
	}
	balance, err := s.repo.Balance(ctx, id)
	if err != nil {
		return nil, err
	}
	v := view(*c, balance)
	return &v, nil
}

// Delete removes a customer, refusing while they carry a balance.
func (s *Service) Delete(ctx context.Context, id uuid.UUID) error {
	return s.repo.Delete(ctx, id)
}

// normalisedOrNil returns nil for an empty or whitespace-only phone, so
// "walk-in customer, no phone" and "phone field left blank" both mean the same
// thing to the partial unique index — which only applies to non-empty values.
func normalisedOrNil(phone *string) *string {
	if phone == nil {
		return nil
	}
	trimmed := strings.TrimSpace(*phone)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}
