package business

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/middleware"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"golang.org/x/crypto/bcrypt"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/phone"
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
	ErrInvalidPhone     = phone.ErrInvalid
	ErrInvalidLogin     = errors.New("incorrect phone number or password")
	ErrAccountInactive  = errors.New("this account has been deactivated")
	ErrInviteUnusable   = errors.New("that invite code is invalid, already used, or expired")
	ErrCannotRemoveSelf = errors.New("you cannot remove your own account")
	ErrLastOwner        = errors.New("a business must keep at least one active owner")

	// Not 401: a client treats 401 as "your session ended" and signs out. A
	// mistyped current password is an input error on a session that is fine.
	ErrWrongPassword    = errors.New("the current password is not correct")
	ErrSamePassword     = errors.New("the new password must be different from the current one")
	ErrCannotResetSelf  = errors.New("to change your own password, use change password")
	ErrCannotResetOwner = errors.New("only a staff member's password can be reset; an owner changes their own")
	ErrResetInactive    = errors.New("that account is deactivated")
)

// Authenticated is what a successful sign-in produces.
type Authenticated struct {
	Token string
	User  domain.User

	// Permissions are what the user may do, as the routes check it (B5).
	Permissions []string
}

// Register creates a business and its first owner.
func (s *Service) Register(ctx context.Context, in RegisterBusinessInput) (*Authenticated, error) {
	phone, err := s.freePhone(ctx, in.Body.Phone)
	if err != nil {
		return nil, err
	}

	zone := domain.DefaultTimeZone
	if in.Body.TimeZone != "" {
		loc, err := domain.LoadTimeZone(in.Body.TimeZone)
		if err != nil {
			return nil, err
		}
		zone = loc.String()
	}

	hash, err := hashPassword(in.Body.Password)
	if err != nil {
		return nil, err
	}

	b := &domain.Business{Name: strings.TrimSpace(in.Body.BusinessName), TimeZone: zone}
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

	return s.issue(ctx, *u)
}

// Login exchanges a phone and password for a token.
func (s *Service) Login(ctx context.Context, in LoginInput) (*Authenticated, error) {
	u, err := s.findByPhone(ctx, in.Body.Phone)
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

	return s.issue(ctx, *u)
}

// Join adds a member of staff to a business using an invite code.
func (s *Service) Join(ctx context.Context, in JoinBusinessInput) (*Authenticated, error) {
	phone, err := s.freePhone(ctx, in.Body.Phone)
	if err != nil {
		return nil, err
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

	return s.issue(ctx, *u)
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
	d := businessDetails{
		name:    strings.TrimSpace(in.Body.Name),
		typ:     optional(in.Body.Type),
		phone:   optional(in.Body.Phone),
		email:   optional(in.Body.Email),
		address: optional(in.Body.Address),
	}
	if in.Body.TimeZone != "" {
		loc, err := domain.LoadTimeZone(in.Body.TimeZone)
		if err != nil {
			return nil, err
		}
		zone := loc.String()
		d.timeZone = &zone
	}
	return s.repo.UpdateBusiness(ctx, d)
}

// optional turns a blank field into "not set" rather than an empty string, so a
// letterhead never prints a label with nothing after it.
func optional(s string) *string {
	if t := strings.TrimSpace(s); t != "" {
		return &t
	}
	return nil
}

func (s *Service) Me(ctx context.Context, userID uuid.UUID) (*domain.User, error) {
	return s.repo.GetUser(ctx, userID)
}

func (s *Service) UpdateMe(ctx context.Context, userID uuid.UUID, name string) (*domain.User, error) {
	return s.repo.UpdateUserName(ctx, userID, strings.TrimSpace(name))
}

// ChangePassword replaces the caller's password, ends every other session, and
// returns a fresh token so the device making the change stays signed in.
func (s *Service) ChangePassword(ctx context.Context, userID uuid.UUID, current, next string) (*Authenticated, error) {
	u, err := s.repo.GetUser(ctx, userID)
	if err != nil {
		return nil, err
	}
	if bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(current)) != nil {
		return nil, ErrWrongPassword
	}
	if current == next {
		return nil, ErrSamePassword
	}
	hash, err := hashPassword(next)
	if err != nil {
		return nil, err
	}

	// Every session from before this instant ends — including a stolen phone's.
	// This device gets a new token, issued after the cut-off.
	now := time.Now().UTC()
	if err := s.repo.SetPassword(ctx, userID, hash, false, now); err != nil {
		return nil, err
	}
	u.MustChangePassword = false
	return s.issue(ctx, *u)
}

// ResetStaffPassword gives a staff member a temporary password, ends their
// sessions, and makes them choose their own at the next sign-in.
//
// For the person who has forgotten theirs and has no other way back in: there
// is no email, and an SMS reset needs an SMS provider. The owner reads the
// temporary password to them in person. It is shown once and only its hash is
// stored.
//
// Staff only. Letting one owner reset another's password would let either
// co-owner lock the other out of their own business.
func (s *Service) ResetStaffPassword(ctx context.Context, actorID, targetID uuid.UUID) (string, error) {
	if actorID == targetID {
		return "", ErrCannotResetSelf
	}
	target, err := s.repo.GetUser(ctx, targetID)
	if err != nil {
		return "", err
	}
	switch {
	case target.Role != domain.RoleStaff:
		return "", ErrCannotResetOwner
	case !target.IsActive:
		return "", ErrResetInactive
	}

	temporary, err := temporaryPassword()
	if err != nil {
		return "", err
	}
	hash, err := hashPassword(temporary)
	if err != nil {
		return "", err
	}
	if err := s.repo.SetPassword(ctx, targetID, hash, true, time.Now().UTC()); err != nil {
		return "", err
	}
	return temporary, nil
}

// temporaryAlphabet leaves out characters that are confused when read aloud or
// copied by hand: 0/O, 1/I/L.
const temporaryAlphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"

// temporaryPassword is 10 characters from a 31-letter alphabet: about 50 bits,
// from crypto/rand. Short enough to read out over a counter, and it only has to
// survive until its owner replaces it at the next sign-in.
func temporaryPassword() (string, error) {
	b := make([]byte, 10)
	for i := range b {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(temporaryAlphabet))))
		if err != nil {
			return "", fmt.Errorf("generating a temporary password: %w", err)
		}
		b[i] = temporaryAlphabet[n.Int64()]
	}
	return string(b), nil
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
func (s *Service) issue(ctx context.Context, u domain.User) (*Authenticated, error) {
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
	permissions, err := s.repo.PermissionsOf(ctx, u.ID)
	if err != nil {
		return nil, err
	}
	return &Authenticated{Token: signed, User: u, Permissions: permissions}, nil
}

// Permissions lists what a user may do (B5).
func (s *Service) Permissions(ctx context.Context, userID uuid.UUID) ([]string, error) {
	return s.repo.PermissionsOf(ctx, userID)
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

// freePhone returns a new login's phone in its one stored form, or why it
// cannot be used.
func (s *Service) freePhone(ctx context.Context, raw string) (string, error) {
	canonical, err := phone.Normalize(raw)
	if err != nil {
		return "", ErrInvalidPhone
	}
	// Also in the old form: a login the conversion had to leave alone
	// (migration 00010) still holds its number.
	for _, p := range []string{canonical, legacyForm(raw)} {
		taken, err := s.repo.PhoneTaken(ctx, p)
		if err != nil {
			return "", fmt.Errorf("checking phone: %w", err)
		}
		if taken {
			return "", ErrPhoneTaken
		}
	}
	return canonical, nil
}

// findByPhone finds a login by its number however it is typed: 0712…,
// +254712… and 712… are one account (B15).
func (s *Service) findByPhone(ctx context.Context, raw string) (*domain.User, error) {
	if canonical, err := phone.Normalize(raw); err == nil {
		u, err := s.repo.FindUserByPhone(ctx, canonical)
		if !errors.Is(err, ErrNotFound) {
			return u, err
		}
	}
	// A login the conversion left in its old form, because another account
	// had the same number in a different form.
	return s.repo.FindUserByPhone(ctx, legacyForm(raw))
}

// legacyForm is how numbers were stored before B15: trimmed, without spaces,
// dashes or brackets, and otherwise as typed.
func legacyForm(p string) string {
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
