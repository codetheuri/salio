package reports

import (
	"context"

	"github.com/google/uuid"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Summary(ctx context.Context) (*SummaryView, error) {
	return s.repo.Summary(ctx)
}

func (s *Service) Statement(ctx context.Context, customerID uuid.UUID, in PeriodInput) (*StatementView, error) {
	// A statement looks back further by default than the period reports: a
	// customer asking what they owe usually means "since we started", and a
	// quarter covers most running accounts while keeping the page count sane.
	p, err := s.period(ctx, in, 90)
	if err != nil {
		return nil, err
	}
	return s.repo.Statement(ctx, customerID, p)
}

func (s *Service) Ageing(ctx context.Context) (*AgeingView, error) {
	return s.repo.Ageing(ctx)
}

func (s *Service) SalesReport(ctx context.Context, in PeriodInput) (*SalesReportView, error) {
	p, err := s.period(ctx, in, 30)
	if err != nil {
		return nil, err
	}
	return s.repo.SalesReport(ctx, p)
}

func (s *Service) Collections(ctx context.Context, in PeriodInput) (*CollectionsView, error) {
	p, err := s.period(ctx, in, 30)
	if err != nil {
		return nil, err
	}
	return s.repo.Collections(ctx, p)
}

// Due is the reminder list: customers overdue, or falling due within the window.
func (s *Service) Due(ctx context.Context, withinDays int) (*DueView, error) {
	return s.repo.Due(ctx, withinDays)
}

// Payables is what the shop owes its suppliers, most urgent first.
func (s *Service) Payables(ctx context.Context, withinDays int) (*PayablesView, error) {
	return s.repo.Payables(ctx, withinDays)
}

// period resolves a report's dates against the business's own today.
func (s *Service) period(ctx context.Context, in PeriodInput, defaultDays int) (Period, error) {
	today, err := s.repo.Today(ctx)
	if err != nil {
		return Period{}, err
	}
	return in.resolve(today, defaultDays)
}
