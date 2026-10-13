package ledger

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

// dateLayout is the only format a transaction_date is accepted in — plain
// calendar dates, no time-of-day and no zone. What matters for a debt or a
// payment is which day it happened on, not the instant it was typed into a
// phone.
const dateLayout = "2006-01-02"

// ErrInvalidDate is returned for a transaction_date that does not parse.
var ErrInvalidDate = fmt.Errorf("transaction_date must be in YYYY-MM-DD format")

// ErrInvalidType is returned for anything other than "debt" or "payment".
var ErrInvalidType = fmt.Errorf("type must be \"debt\" or \"payment\"")

// ErrNonPositiveAmount is returned for an amount that is zero or negative. A
// transaction always moves money in the direction its Type says; there is no
// such thing as a negative debt, that is a payment wearing the wrong label.
var ErrNonPositiveAmount = fmt.Errorf("amount must be greater than zero")

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) ListForCustomer(ctx context.Context, customerID uuid.UUID) ([]TransactionView, error) {
	txs, err := s.repo.ListForCustomer(ctx, customerID)
	if err != nil {
		return nil, err
	}
	return views(txs), nil
}

// Create validates and records one ledger entry.
func (s *Service) Create(ctx context.Context, userID uuid.UUID, in CreateInput) (*TransactionView, error) {
	var date time.Time
	if in.Body.TransactionDate != nil && *in.Body.TransactionDate != "" {
		parsed, err := time.Parse(dateLayout, *in.Body.TransactionDate)
		if err != nil {
			return nil, ErrInvalidDate
		}
		date = parsed
	} else {
		today, err := s.repo.Today(ctx)
		if err != nil {
			return nil, err
		}
		date = today
	}

	var due *time.Time
	if in.Body.DueDate != nil && *in.Body.DueDate != "" {
		parsed, err := time.Parse(dateLayout, *in.Body.DueDate)
		if err != nil {
			return nil, ErrInvalidDate
		}
		due = &parsed
	}

	description := strings.TrimSpace(in.Body.Description)
	t := &domain.Transaction{
		CustomerID:      in.Body.CustomerID,
		UserID:          userID,
		Type:            in.Body.Type,
		Amount:          in.Body.Amount,
		Description:     &description,
		TransactionDate: date,
		PaymentMethod:   in.Body.PaymentMethod,
		Reference:       in.Body.Reference,
		DueDate:         due,
	}
	if err := ValidateEntry(t); err != nil {
		return nil, err
	}
	if err := s.repo.Create(ctx, t); err != nil {
		return nil, err
	}
	v := view(*t)
	return &v, nil
}

// Get returns one transaction.
func (s *Service) Get(ctx context.Context, id uuid.UUID) (*TransactionView, error) {
	t, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, err
	}
	v := view(*t)
	return &v, nil
}

func (s *Service) Void(ctx context.Context, id uuid.UUID) error {
	return s.repo.Void(ctx, id)
}
