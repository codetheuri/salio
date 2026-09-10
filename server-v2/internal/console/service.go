package console

import (
	"context"
	"errors"
	"fmt"

	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"salio/server-v2/internal/domain"
)

// ErrInvalidLogin is what a failed sign-in reports, whatever actually went
// wrong. Distinguishing "no such account" from "wrong password" turns the login
// form into a way to find out who operates the platform.
var ErrInvalidLogin = errors.New("incorrect email or password")

// recentBusinessCount is how many businesses the dashboard shows before sending
// the reader to the full list.
const recentBusinessCount = 10

// Page sizes offered by the per-page selector. A requested size outside this set
// falls back to defaultPageSize rather than being honoured — the parameter comes
// from a query string, and "?limit=1000000" should not be a way to ask the
// database for every row in the system.
var allowedPageSizes = map[int]bool{5: true, 10: true, 20: true, 50: true}

const defaultPageSize = 10

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Authenticate verifies an email and password.
func (s *Service) Authenticate(ctx context.Context, email, password string) (*domain.SuperAdmin, error) {
	admin, err := s.repo.FindAdminByEmail(ctx, email)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			// Hash regardless. Returning immediately for an unknown email makes
			// the two paths take measurably different times, which is enough to
			// enumerate accounts without ever guessing a password.
			_, _ = bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
			return nil, ErrInvalidLogin
		}
		return nil, err
	}

	if bcrypt.CompareHashAndPassword([]byte(admin.PasswordHash), []byte(password)) != nil {
		return nil, ErrInvalidLogin
	}
	return admin, nil
}

// Admin resolves the subject of a session.
//
// Called on every protected request, so that deleting a super_admin row ends
// their access at once. A session that outlives its subject would otherwise keep
// working until it expired on its own.
func (s *Service) Admin(ctx context.Context, adminID uuid.UUID) (*domain.SuperAdmin, error) {
	return s.repo.FindAdminByID(ctx, adminID)
}

// CreateAdmin registers a platform operator from the command line.
func (s *Service) CreateAdmin(ctx context.Context, name, email, password string) (*domain.SuperAdmin, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("console: hashing password: %w", err)
	}

	admin := &domain.SuperAdmin{Name: name, Email: email, PasswordHash: string(hash)}
	if err := s.repo.CreateAdmin(ctx, admin); err != nil {
		return nil, fmt.Errorf("console: creating admin: %w", err)
	}
	return admin, nil
}

// Dashboard is the landing page: platform totals and the newest businesses.
func (s *Service) Dashboard(ctx context.Context) (*Summary, []BusinessRow, error) {
	summary, err := s.repo.Summary(ctx)
	if err != nil {
		return nil, nil, err
	}
	businesses, _, err := s.repo.Businesses(ctx, recentBusinessCount, 0)
	if err != nil {
		return nil, nil, err
	}
	return summary, businesses, nil
}

// Businesses returns one page of the businesses list.
func (s *Service) Businesses(ctx context.Context, page, limit int) ([]BusinessRow, Pagination, error) {
	p := newPagination(page, limit)
	rows, total, err := s.repo.Businesses(ctx, p.Limit, p.offset())
	if err != nil {
		return nil, p, err
	}
	return rows, p.withTotal(total), nil
}

// Business returns one business, its ledger totals and its people.
func (s *Service) Business(ctx context.Context, businessID uuid.UUID) (*BusinessDetail, []UserRow, error) {
	return s.repo.Business(ctx, businessID)
}

// Users returns one page of the platform-wide user list.
func (s *Service) Users(ctx context.Context, page, limit int) ([]UserRow, Pagination, error) {
	p := newPagination(page, limit)
	rows, total, err := s.repo.Users(ctx, p.Limit, p.offset())
	if err != nil {
		return nil, p, err
	}
	return rows, p.withTotal(total), nil
}

// Pagination is everything the page templates need to draw their footer.
type Pagination struct {
	CurrentPage int
	TotalPages  int
	Limit       int
	Total       int64
	HasPrev     bool
	HasNext     bool
	PrevPage    int
	NextPage    int
}

func newPagination(page, limit int) Pagination {
	if page < 1 {
		page = 1
	}
	if !allowedPageSizes[limit] {
		limit = defaultPageSize
	}
	return Pagination{CurrentPage: page, Limit: limit, TotalPages: 1}
}

func (p Pagination) offset() int { return (p.CurrentPage - 1) * p.Limit }

func (p Pagination) withTotal(total int64) Pagination {
	p.Total = total

	p.TotalPages = int((total + int64(p.Limit) - 1) / int64(p.Limit))
	if p.TotalPages < 1 {
		p.TotalPages = 1
	}

	p.HasPrev = p.CurrentPage > 1
	p.HasNext = p.CurrentPage < p.TotalPages
	p.PrevPage = p.CurrentPage - 1
	p.NextPage = p.CurrentPage + 1
	return p
}

// PageSizes is the set the per-page selector offers, in order.
func PageSizes() []int { return []int{5, 10, 20, 50} }
