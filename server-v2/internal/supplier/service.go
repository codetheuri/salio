package supplier

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// List returns suppliers with their balances, in two queries for any number.
func (s *Service) List(ctx context.Context, search string) ([]SupplierView, error) {
	rows, err := s.repo.List(ctx, search)
	if err != nil {
		return nil, err
	}
	ids := make([]uuid.UUID, len(rows))
	for i, r := range rows {
		ids[i] = r.ID
	}
	balances, err := s.repo.Balances(ctx, ids)
	if err != nil {
		return nil, err
	}
	out := make([]SupplierView, 0, len(rows))
	for _, r := range rows {
		out = append(out, view(r, balances[r.ID]))
	}
	return out, nil
}

func (s *Service) Get(ctx context.Context, id uuid.UUID) (*SupplierView, error) {
	sup, err := s.repo.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.withBalance(ctx, *sup)
}

// Create adds a supplier. A request carrying an id the server already has
// returns that supplier, so a retried request cannot add the same one twice.
func (s *Service) Create(ctx context.Context, userID uuid.UUID, in CreateInput) (*SupplierView, error) {
	if in.Body.ID != nil {
		if existing, err := s.repo.GetAny(ctx, *in.Body.ID); err == nil {
			return s.withBalance(ctx, *existing)
		} else if !errors.Is(err, ErrNotFound) {
			return nil, err
		}
	}
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	sup := &domain.Supplier{
		BusinessID: businessID, Name: in.Body.Name, Phone: in.Body.Phone, Notes: in.Body.Notes,
		CreatedBy: userID,
	}
	if in.Body.ID != nil {
		sup.ID = *in.Body.ID
	}
	if err := ValidateSupplier(sup); err != nil {
		return nil, err
	}
	if err := s.repo.Create(ctx, sup); err != nil {
		return nil, err
	}
	v := view(*sup, 0)
	return &v, nil
}

func (s *Service) Update(ctx context.Context, in UpdateInput) (*SupplierView, error) {
	sup := &domain.Supplier{ID: in.SupplierID, Name: in.Body.Name, Phone: in.Body.Phone, Notes: in.Body.Notes}
	if err := ValidateSupplier(sup); err != nil {
		return nil, err
	}
	if err := s.repo.Update(ctx, sup); err != nil {
		return nil, err
	}
	return s.Get(ctx, in.SupplierID)
}

func (s *Service) Delete(ctx context.Context, id uuid.UUID) error {
	return s.repo.Delete(ctx, id)
}

// Entries lists a supplier's bills and payments.
func (s *Service) Entries(ctx context.Context, supplierID uuid.UUID) ([]EntryView, error) {
	if _, err := s.repo.Get(ctx, supplierID); err != nil {
		return nil, err
	}
	rows, err := s.repo.Entries(ctx, supplierID)
	if err != nil {
		return nil, err
	}
	out := make([]EntryView, 0, len(rows))
	for _, r := range rows {
		out = append(out, entryView(r))
	}
	return out, nil
}

// RecordEntry records a bill or a payment. Idempotent on a client-sent id.
func (s *Service) RecordEntry(ctx context.Context, userID uuid.UUID, in CreateEntryInput) (*EntryView, error) {
	if in.Body.ID != nil {
		if existing, err := s.repo.GetEntry(ctx, *in.Body.ID); err == nil {
			v := entryView(*existing)
			return &v, nil
		} else if !errors.Is(err, ErrEntryNotFound) {
			return nil, err
		}
	}
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	date, err := parseDate(in.Body.TransactionDate)
	if err != nil {
		return nil, err
	}
	if date == nil {
		today, err := s.repo.Today(ctx)
		if err != nil {
			return nil, err
		}
		date = &today
	}
	due, err := parseDate(in.Body.DueDate)
	if err != nil {
		return nil, err
	}

	t := &domain.SupplierTransaction{
		BusinessID: businessID, SupplierID: in.Body.SupplierID, UserID: userID,
		Type: in.Body.Type, Amount: in.Body.Amount, Description: in.Body.Description,
		TransactionDate: *date, DueDate: due,
		PaymentMethod: in.Body.PaymentMethod, Reference: in.Body.Reference,
		PurchaseOrderID: in.Body.PurchaseOrderID,
	}
	if in.Body.ID != nil {
		t.ID = *in.Body.ID
	}
	if err := s.repo.RecordEntry(ctx, t); err != nil {
		return nil, err
	}
	v := entryView(*t)
	return &v, nil
}

func (s *Service) GetEntry(ctx context.Context, id uuid.UUID) (*EntryView, error) {
	t, err := s.repo.GetEntry(ctx, id)
	if err != nil {
		return nil, err
	}
	v := entryView(*t)
	return &v, nil
}

func (s *Service) VoidEntry(ctx context.Context, id uuid.UUID) error {
	return s.repo.VoidEntry(ctx, id)
}

func (s *Service) withBalance(ctx context.Context, sup domain.Supplier) (*SupplierView, error) {
	balance, err := s.repo.Balance(ctx, sup.ID)
	if err != nil {
		return nil, err
	}
	v := view(sup, balance)
	return &v, nil
}
