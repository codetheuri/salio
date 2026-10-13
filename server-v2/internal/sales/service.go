package sales

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

const dateLayout = "2006-01-02"

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Create records a sale. A request carrying an id the server already has
// returns that sale rather than recording a second one, so a client retrying
// after a timeout cannot sell the same bag twice.
func (s *Service) Create(ctx context.Context, userID uuid.UUID, in CreateInput) (*SaleView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	if in.Body.ID != nil {
		if existing, err := s.repo.GetByID(ctx, *in.Body.ID); err == nil {
			return s.withName(ctx, *existing)
		} else if !errors.Is(err, ErrNotFound) {
			return nil, err
		}
	}

	var date time.Time
	if in.Body.SaleDate != nil && *in.Body.SaleDate != "" {
		if date, err = time.Parse(dateLayout, *in.Body.SaleDate); err != nil {
			return nil, ErrInvalidDate
		}
	} else if date, err = s.repo.Today(ctx); err != nil {
		return nil, err
	}

	var due *time.Time
	if in.Body.DueDate != nil && *in.Body.DueDate != "" {
		parsed, err := time.Parse(dateLayout, *in.Body.DueDate)
		if err != nil {
			return nil, ErrInvalidDate
		}
		due = &parsed
	}

	sale := &domain.Sale{
		BusinessID:    businessID,
		CustomerID:    in.Body.CustomerID,
		UserID:        userID,
		ProductName:   in.Body.ProductName,
		Quantity:      in.Body.Quantity,
		Amount:        in.Body.Amount,
		PaymentMethod: in.Body.PaymentMethod,
		Notes:         trimmedOrNil(in.Body.Notes),
		SaleDate:      date,
		Reference:     in.Body.Reference,
		DueDate:       due,
	}
	if in.Body.ID != nil {
		sale.ID = *in.Body.ID
	}

	if err := s.repo.Create(ctx, sale); err != nil {
		return nil, err
	}
	return s.withName(ctx, *sale)
}

func (s *Service) Get(ctx context.Context, id uuid.UUID) (*SaleView, error) {
	sale, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	return s.withName(ctx, *sale)
}

func (s *Service) List(ctx context.Context, in ListInput) ([]SaleView, int64, error) {
	to, err := s.repo.Today(ctx)
	if err != nil {
		return nil, 0, err
	}
	from := to.AddDate(0, 0, -30)
	if in.From != "" {
		if from, err = time.Parse(dateLayout, in.From); err != nil {
			return nil, 0, ErrInvalidDate
		}
	}
	if in.To != "" {
		if to, err = time.Parse(dateLayout, in.To); err != nil {
			return nil, 0, ErrInvalidDate
		}
	}

	rows, total, err := s.repo.List(ctx, listFilter{
		from: from, to: to, customerID: in.CustomerID,
		limit: in.PerPage, offset: (in.Page - 1) * in.PerPage,
	})
	if err != nil {
		return nil, 0, err
	}

	var ids []uuid.UUID
	for _, r := range rows {
		if r.CustomerID != nil {
			ids = append(ids, *r.CustomerID)
		}
	}
	names, err := s.repo.CustomerNames(ctx, ids)
	if err != nil {
		return nil, 0, err
	}

	out := make([]SaleView, 0, len(rows))
	for _, r := range rows {
		out = append(out, view(r, nameFor(names, r.CustomerID)))
	}
	return out, total, nil
}

func (s *Service) Void(ctx context.Context, id uuid.UUID) error {
	return s.repo.Void(ctx, id)
}

func (s *Service) withName(ctx context.Context, sale domain.Sale) (*SaleView, error) {
	var ids []uuid.UUID
	if sale.CustomerID != nil {
		ids = append(ids, *sale.CustomerID)
	}
	names, err := s.repo.CustomerNames(ctx, ids)
	if err != nil {
		return nil, err
	}
	v := view(sale, nameFor(names, sale.CustomerID))
	return &v, nil
}

func nameFor(names map[uuid.UUID]string, id *uuid.UUID) *string {
	if id == nil {
		return nil
	}
	if n, ok := names[*id]; ok {
		return &n
	}
	return nil
}

func trimmedOrNil(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
