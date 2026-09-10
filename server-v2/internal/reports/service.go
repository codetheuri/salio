package reports

import "context"

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Summary(ctx context.Context) (*SummaryView, error) {
	return s.repo.Summary(ctx)
}
