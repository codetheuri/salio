package business

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/middleware"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
)

// Service holds the rules that are not about storage and not about HTTP.
type Service struct {
	repo      *Repository
	jwtSecret string
	tokenTTL  time.Duration
}

// DefaultTokenTTL is deliberately long.
//
// Salio is offline-first: a shop in an area with no signal must keep working for
// days without reaching the server, and an expired token means a shopkeeper
// locked out of their own ledger with no way to sign in again. The cost is that
// deactivating a staff member does not take effect on their device until they
// next reach the server. Phase 6 closes that by re-checking is_active on sync,
// which is the moment a device is reachable anyway.
const DefaultTokenTTL = 30 * 24 * time.Hour

// InviteTTL is how long an invite code stays usable. Long enough to send by SMS
// and be typed in later that day, short enough that a leaked code expires.
const InviteTTL = 24 * time.Hour

func NewService(repo *Repository, jwtSecret string, tokenTTL time.Duration) *Service {
	if tokenTTL == 0 {
		tokenTTL = DefaultTokenTTL
	}
	return &Service{repo: repo, jwtSecret: jwtSecret, tokenTTL: tokenTTL}
}

// Common failures, distinguished so handlers can map them to status codes.
var (
	ErrPhoneTaken       = errors.New("that phone number is already registered")
	ErrInvalidLogin     = errors.New("incorrect phone number or password")
	ErrAccountInactive  = errors.New("this account has been deactivated")
	ErrInviteUnusable   = errors.New("that invite code is invalid, already used, or expired")
	ErrCannotRemoveSelf = errors.New("you cannot remove your own account")
	ErrLastOwner        = errors.New("a business must keep at least one active owner")
)

// Authenticated is what a successful sign-in produces.
type Authenticated struct {
	Token string
	User  domain.User
}

// Register creates a business and its first owner.
func (s *Service) Register(ctx context.Context, in RegisterBusinessInput) (*Authenticated, error) {
	phone := normalisePhone(in.Body.Phone)

	taken, err := s.repo.PhoneTaken(ctx, phone)
	if err != nil {
		return nil, fmt.Errorf("checking phone: %w", err)
	}
	if taken {
		return nil, ErrPhoneTaken
	}

	hash, err := hashPassword(in.Body.Password)
	if err != nil {
		return nil, err
	}

	b := &domain.Business{Name: strings.TrimSpace(in.Body.BusinessName)}
	if t := strings.TrimSpace(in.Body.BusinessType); t != "" {
		b.Type = &t
	}

	u := &domain.User{
		Name: strings.TrimSpace(in.Body.Name), Phone: phone,
		PasswordHash: hash, Role: domain.RoleOwner, IsActive: true,
	}

	if err := s.repo.CreateBusinessWithOwner(ctx, b, u, rbac.AssignRole); err != nil {
		return nil, fmt.Errorf("registering business: %w", err)
	}

	return s.issue(*u)
}

// Login exchanges a phone and password for a token.
func (s *Service) Login(ctx context.Context, in LoginInput) (*Authenticated, error) {
	u, err := s.repo.FindUserByPhone(ctx, normalisePhone(in.Body.Phone))
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			// Hash anyway. Returning immediately for an unknown phone makes the
			// two cases take measurably different times, which turns the login
			// endpoint into a way to enumerate who has an account.
			_, _ = bcrypt.GenerateFromPassword([]byte(in.Body.Password), bcrypt.DefaultCost)
			return nil, ErrInvalidLogin
		}
		return nil, err
	}

	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(in.Body.Password)) != nil {
		return nil, ErrInvalidLogin
	}

	// Checked after the password, so an attacker cannot learn which accounts
	// exist and are deactivated without also knowing the password.
	if !u.IsActive {
		return nil, ErrAccountInactive
	}

	return s.issue(*u)
}

// Join adds a member of staff to a business using an invite code.
func (s *Service) Join(ctx context.Context, in JoinBusinessInput) (*Authenticated, error) {
	phone := normalisePhone(in.Body.Phone)

	taken, err := s.repo.PhoneTaken(ctx, phone)
	if err != nil {
		return nil, fmt.Errorf("checking phone: %w", err)
	}
	if taken {
		return nil, ErrPhoneTaken
	}

	hash, err := hashPassword(in.Body.Password)
	if err != nil {
		return nil, err
	}

	u := &domain.User{
		Name: strings.TrimSpace(in.Body.Name), Phone: phone,
		PasswordHash: hash, Role: domain.RoleStaff, IsActive: true,
	}

	if _, err := s.repo.JoinBusiness(ctx, strings.ToUpper(strings.TrimSpace(in.Body.Code)), u, rbac.AssignRole); err != nil {
		if errors.Is(err, ErrNotFound) {
			return nil, ErrInviteUnusable
		}
		return nil, fmt.Errorf("joining business: %w", err)
	}

	return s.issue(*u)
}

// CreateInvite issues a code an owner can pass to a new member of staff.
func (s *Service) CreateInvite(ctx context.Context) (*domain.BusinessInvite, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	code, err := generateInviteCode()
	if err != nil {
		return nil, err
	}

	invite := &domain.BusinessInvite{
		BusinessID: businessID,
		Code:       code,
		ExpiresAt:  time.Now().Add(InviteTTL),
	}
	if err := s.repo.CreateInvite(ctx, invite); err != nil {
		return nil, fmt.Errorf("creating invite: %w", err)
	}
	return invite, nil
}

func (s *Service) GetBusiness(ctx context.Context) (*domain.Business, error) {
	return s.repo.GetBusiness(ctx)
}

func (s *Service) UpdateBusiness(ctx context.Context, in UpdateBusinessInput) (*domain.Business, error) {
	var typ *string
	if t := strings.TrimSpace(in.Body.Type); t != "" {
		typ = &t
	}
	return s.repo.UpdateBusiness(ctx, strings.TrimSpace(in.Body.Name), typ)
}

func (s *Service) Me(ctx context.Context, userID uuid.UUID) (*domain.User, error) {
	return s.repo.GetUser(ctx, userID)
}

func (s *Service) UpdateMe(ctx context.Context, userID uuid.UUID, name string) (*domain.User, error) {
	return s.repo.UpdateUserName(ctx, userID, strings.TrimSpace(name))
}

func (s *Service) ListStaff(ctx context.Context) ([]domain.User, error) {
	return s.repo.ListStaff(ctx)
}

// DeactivateStaff disables an account.
//
// Two rules that are not the database's to enforce: nobody removes themselves,
// and the last active owner cannot be removed. Without the second, a business
// can be left with no one able to manage it — recoverable only by hand, in a
// product whose users have no support channel.
func (s *Service) DeactivateStaff(ctx context.Context, actorID, targetID uuid.UUID) error {
	if actorID == targetID {
		return ErrCannotRemoveSelf
	}

	target, err := s.repo.GetUser(ctx, targetID)
	if err != nil {
		return err
	}

	if target.Role == domain.RoleOwner {
		owners, err := s.repo.CountOwners(ctx)
		if err != nil {
			return fmt.Errorf("counting owners: %w", err)
		}
		if owners <= 1 {
			return ErrLastOwner
		}
	}

	return s.repo.DeactivateStaff(ctx, targetID)
}

// issue signs a token carrying the identity and the tenant.
//
// TenantID is the whole reason a request is scoped at all: tenant.Middleware
// reads it from here into the request context, and the GORM callbacks read it
// from there. It comes from the database record, never from anything the caller
// sent.
func (s *Service) issue(u domain.User) (*Authenticated, error) {
	now := time.Now()
	claims := middleware.Claims{
		UserID:   u.ID,
		TenantID: u.BusinessID,
		Role:     string(u.Role),
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   u.ID.String(),
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.tokenTTL)),
		},
	}

	signed, err := jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString([]byte(s.jwtSecret))
	if err != nil {
		return nil, fmt.Errorf("signing token: %w", err)
	}
	return &Authenticated{Token: signed, User: u}, nil
}

func hashPassword(plain string) (string, error) {
	// bcrypt silently truncates at 72 bytes, so anything longer would make the
	// tail of a long passphrase meaningless. The DTO caps it at 72 to make that
	// a validation error the user can see rather than a silent surprise.
	hash, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hashing password: %w", err)
	}
	return string(hash), nil
}

// normalisePhone trims and strips separators so "0712 345 678" and "0712345678"
// are the same account. It deliberately does not rewrite country codes: guessing
// that +254712345678 and 0712345678 are one person is a product decision, and
// getting it wrong merges two shops' logins.
func normalisePhone(p string) string {
	var b strings.Builder
	for _, r := range strings.TrimSpace(p) {
		if r == ' ' || r == '-' || r == '(' || r == ')' {
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}

// inviteAlphabet omits characters that are misread when a code is written on
// paper and typed on a phone: no O or 0, no I, 1 or L.
const inviteAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

const inviteCodeLength = 6

func generateInviteCode() (string, error) {
	buf := make([]byte, inviteCodeLength)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generating invite code: %w", err)
	}

	out := make([]byte, inviteCodeLength)
	for i, b := range buf {
		// A slight modulo bias across a 31-character alphabet, which does not
		// matter: the code is single-use, expires in a day, and is scoped to one
		// business. Its job is to resist typos, not a sustained attack.
		out[i] = inviteAlphabet[int(b)%len(inviteAlphabet)]
	}
	return string(out), nil
}
