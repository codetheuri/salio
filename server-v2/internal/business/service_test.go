package business_test

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/golang-jwt/jwt/v5"
	"gorm.io/gorm"

	"salio/server-v2/internal/business"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/testsupport"
)

const testSecret = "test-secret-at-least-32-characters-long"

func newService(t *testing.T) (*business.Service, *gorm.DB) {
	t.Helper()
	db := testsupport.Connect(t)
	if err := rbac.Seed(context.Background(), db); err != nil {
		t.Fatalf("seed rbac: %v", err)
	}
	return business.NewService(business.NewRepository(db), testSecret, time.Hour), db
}

func register(t *testing.T, s *business.Service, phone string) *business.Authenticated {
	t.Helper()
	var in business.RegisterBusinessInput
	in.Body.BusinessName = "Test Shop"
	in.Body.Name = "Owner"
	in.Body.Phone = phone
	in.Body.Password = "correct horse battery staple"

	auth, err := s.Register(context.Background(), in)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	return auth
}

func TestRegister_IssuesATokenCarryingTheTenant(t *testing.T) {
	s, _ := newService(t)
	auth := register(t, s, "0711000100")

	type claims struct {
		UserID   string `json:"user_id"`
		TenantID string `json:"tenant_id"`
		jwt.RegisteredClaims
	}
	var tc claims
	tok, err := jwt.ParseWithClaims(auth.Token, &tc, func(*jwt.Token) (any, error) {
		return []byte(testSecret), nil
	})
	if err != nil || !tok.Valid {
		t.Fatalf("token did not parse: %v", err)
	}
	if tc.TenantID != auth.User.BusinessID.String() {
		t.Errorf("tenant_id claim = %s, want %s", tc.TenantID, auth.User.BusinessID)
	}
}

func TestRegister_RejectsADuplicatePhone(t *testing.T) {
	s, _ := newService(t)
	register(t, s, "0711000101")

	var in business.RegisterBusinessInput
	in.Body.BusinessName = "Another Shop"
	in.Body.Name = "Someone Else"
	in.Body.Phone = "0711000101"
	in.Body.Password = "another password entirely"

	_, err := s.Register(context.Background(), in)
	if !errors.Is(err, business.ErrPhoneTaken) {
		t.Fatalf("got %v, want ErrPhoneTaken", err)
	}
}

func TestLogin_Succeeds(t *testing.T) {
	s, _ := newService(t)
	register(t, s, "0711000102")

	var in business.LoginInput
	in.Body.Phone = "0711 000 102" // spaced, as a user would type it
	in.Body.Password = "correct horse battery staple"

	auth, err := s.Login(context.Background(), in)
	if err != nil {
		t.Fatalf("login: %v", err)
	}
	if auth.User.Phone != "0711000102" {
		t.Errorf("got phone %q", auth.User.Phone)
	}
}

func TestLogin_RejectsWrongPassword(t *testing.T) {
	s, _ := newService(t)
	register(t, s, "0711000103")

	var in business.LoginInput
	in.Body.Phone = "0711000103"
	in.Body.Password = "wrong"

	if _, err := s.Login(context.Background(), in); !errors.Is(err, business.ErrInvalidLogin) {
		t.Fatalf("got %v, want ErrInvalidLogin", err)
	}
}

// TestLogin_UnknownPhoneAndWrongPasswordLookTheSame is the timing-safety
// property: both must fail with the same error, so the endpoint cannot be used
// to enumerate registered phone numbers.
func TestLogin_UnknownPhoneAndWrongPasswordLookTheSame(t *testing.T) {
	s, _ := newService(t)
	register(t, s, "0711000104")

	var wrongPassword business.LoginInput
	wrongPassword.Body.Phone = "0711000104"
	wrongPassword.Body.Password = "wrong"
	_, err1 := s.Login(context.Background(), wrongPassword)

	var unknownPhone business.LoginInput
	unknownPhone.Body.Phone = "0799999999"
	unknownPhone.Body.Password = "wrong"
	_, err2 := s.Login(context.Background(), unknownPhone)

	if !errors.Is(err1, business.ErrInvalidLogin) || !errors.Is(err2, business.ErrInvalidLogin) {
		t.Fatalf("got %v / %v, want ErrInvalidLogin for both", err1, err2)
	}
}

func TestLogin_RejectsADeactivatedAccount(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0711000105")

	// A second owner so deactivating the first is legal.
	tctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)
	second := domain.User{
		BusinessID: owner.User.BusinessID, Name: "Second Owner",
		Phone: "0711000106", PasswordHash: owner.User.PasswordHash, Role: domain.RoleOwner, IsActive: true,
	}
	if err := db.WithContext(tctx).Create(&second).Error; err != nil {
		t.Fatalf("seed second owner: %v", err)
	}
	if err := rbac.AssignRole(tctx, db, second.ID, domain.RoleOwner); err != nil {
		t.Fatalf("assign role: %v", err)
	}

	if err := s.DeactivateStaff(tctx, second.ID, owner.User.ID); err != nil {
		t.Fatalf("deactivate: %v", err)
	}

	var in business.LoginInput
	in.Body.Phone = "0711000105"
	in.Body.Password = "correct horse battery staple"
	if _, err := s.Login(context.Background(), in); !errors.Is(err, business.ErrAccountInactive) {
		t.Fatalf("got %v, want ErrAccountInactive", err)
	}
}

func TestJoin_AddsStaffToTheInvitingBusiness(t *testing.T) {
	s, _ := newService(t)
	owner := register(t, s, "0711000107")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	invite, err := s.CreateInvite(ctx)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}

	var in business.JoinBusinessInput
	in.Body.Code = invite.Code
	in.Body.Name = "New Staff"
	in.Body.Phone = "0711000108"
	in.Body.Password = "yet another password"

	auth, err := s.Join(context.Background(), in)
	if err != nil {
		t.Fatalf("join: %v", err)
	}
	if auth.User.BusinessID != owner.User.BusinessID {
		t.Errorf("joined business %s, want %s", auth.User.BusinessID, owner.User.BusinessID)
	}
	if auth.User.Role != domain.RoleStaff {
		t.Errorf("got role %q, want staff", auth.User.Role)
	}
}

func TestJoin_RejectsAnAlreadyUsedCode(t *testing.T) {
	s, _ := newService(t)
	owner := register(t, s, "0711000109")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	invite, err := s.CreateInvite(ctx)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}

	first := func(phone string) error {
		var in business.JoinBusinessInput
		in.Body.Code, in.Body.Name, in.Body.Phone, in.Body.Password = invite.Code, "N", phone, "password number one"
		_, err := s.Join(context.Background(), in)
		return err
	}
	if err := first("0711000110"); err != nil {
		t.Fatalf("first join: %v", err)
	}
	if err := first("0711000111"); !errors.Is(err, business.ErrInviteUnusable) {
		t.Fatalf("second join with the same code: got %v, want ErrInviteUnusable", err)
	}
}

// TestJoin_ConcurrentClaimsOnlyOneWins is the property CreateBusinessWithOwner's
// conditional UPDATE exists for: two people racing the same code, only one seat.
func TestJoin_ConcurrentClaimsOnlyOneWins(t *testing.T) {
	s, _ := newService(t)
	owner := register(t, s, "0711000112")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	invite, err := s.CreateInvite(ctx)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}

	const attempts = 8
	var wg sync.WaitGroup
	results := make([]error, attempts)
	for i := range attempts {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var in business.JoinBusinessInput
			in.Body.Code = invite.Code
			in.Body.Name = "Racer"
			in.Body.Phone = "071120000" + string(rune('0'+i))
			in.Body.Password = "racer password here"
			_, results[i] = s.Join(context.Background(), in)
		}(i)
	}
	wg.Wait()

	succeeded := 0
	for _, err := range results {
		if err == nil {
			succeeded++
		} else if !errors.Is(err, business.ErrInviteUnusable) {
			t.Errorf("unexpected error: %v", err)
		}
	}
	if succeeded != 1 {
		t.Errorf("%d of %d concurrent joins succeeded, want exactly 1", succeeded, attempts)
	}
}

func TestJoin_RejectsAnExpiredCode(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0711000120")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	invite, err := s.CreateInvite(ctx)
	if err != nil {
		t.Fatalf("create invite: %v", err)
	}
	if err := db.WithContext(ctx).Model(&domain.BusinessInvite{}).
		Where("code = ?", invite.Code).
		Update("expires_at", time.Now().Add(-time.Minute)).Error; err != nil {
		t.Fatalf("expire invite: %v", err)
	}

	var in business.JoinBusinessInput
	in.Body.Code, in.Body.Name, in.Body.Phone, in.Body.Password =
		invite.Code, "N", "0711000121", "some password value"

	if _, err := s.Join(context.Background(), in); !errors.Is(err, business.ErrInviteUnusable) {
		t.Fatalf("got %v, want ErrInviteUnusable", err)
	}
}

func TestDeactivateStaff_CannotRemoveSelf(t *testing.T) {
	s, _ := newService(t)
	owner := register(t, s, "0711000122")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	err := s.DeactivateStaff(ctx, owner.User.ID, owner.User.ID)
	if !errors.Is(err, business.ErrCannotRemoveSelf) {
		t.Fatalf("got %v, want ErrCannotRemoveSelf", err)
	}
}

// TestDeactivateStaff_CannotRemoveTheLastOwner is the rule that stops a business
// from being left with nobody able to manage it.
func TestDeactivateStaff_CannotRemoveTheLastOwner(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0711000123")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	staff := domain.User{
		BusinessID: owner.User.BusinessID, Name: "Staff",
		Phone: "0711000124", PasswordHash: owner.User.PasswordHash, Role: domain.RoleStaff, IsActive: true,
	}
	if err := db.WithContext(ctx).Create(&staff).Error; err != nil {
		t.Fatalf("seed staff: %v", err)
	}

	err := s.DeactivateStaff(ctx, staff.ID, owner.User.ID)
	if !errors.Is(err, business.ErrLastOwner) {
		t.Fatalf("got %v, want ErrLastOwner", err)
	}
}

func TestDeactivateStaff_AllowsRemovingAnOwnerWhenAnotherRemains(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0711000125")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	second := domain.User{
		BusinessID: owner.User.BusinessID, Name: "Second",
		Phone: "0711000126", PasswordHash: owner.User.PasswordHash, Role: domain.RoleOwner, IsActive: true,
	}
	if err := db.WithContext(ctx).Create(&second).Error; err != nil {
		t.Fatalf("seed second owner: %v", err)
	}

	if err := s.DeactivateStaff(ctx, second.ID, owner.User.ID); err != nil {
		t.Fatalf("deactivate: %v", err)
	}

	u, err := s.Me(ctx, owner.User.ID)
	if err != nil {
		t.Fatalf("me: %v", err)
	}
	if u.IsActive {
		t.Error("the owner was not deactivated")
	}
}

// TestBusiness_IsIsolatedBetweenTenants exercises the whole module the way a
// handler would: through context, never through a hand-written filter.
func TestBusiness_IsIsolatedBetweenTenants(t *testing.T) {
	s, _ := newService(t)
	alpha := register(t, s, "0711000130")
	beta := register(t, s, "0711000131")

	alphaCtx := tenant.WithTenant(context.Background(), alpha.User.BusinessID)
	staff, err := s.ListStaff(alphaCtx)
	if err != nil {
		t.Fatalf("list staff: %v", err)
	}
	if len(staff) != 1 || staff[0].ID != alpha.User.ID {
		t.Errorf("Alpha's staff list leaked Beta's data: %+v", staff)
	}
	_ = beta
}

func TestTimeZone_DefaultsToNairobiAndCanBeSetAtSignup(t *testing.T) {
	s, _ := newService(t)

	plain := register(t, s, "0711000140")
	b, err := s.GetBusiness(tenant.WithTenant(context.Background(), plain.User.BusinessID))
	if err != nil {
		t.Fatalf("get business: %v", err)
	}
	if b.TimeZone != domain.DefaultTimeZone {
		t.Errorf("time_zone = %q, want %q", b.TimeZone, domain.DefaultTimeZone)
	}

	var in business.RegisterBusinessInput
	in.Body.BusinessName = "Lagos Shop"
	in.Body.Name = "Owner"
	in.Body.Phone = "0711000141"
	in.Body.Password = "correct horse battery staple"
	in.Body.TimeZone = "Africa/Lagos"
	auth, err := s.Register(context.Background(), in)
	if err != nil {
		t.Fatalf("register: %v", err)
	}
	b, err = s.GetBusiness(tenant.WithTenant(context.Background(), auth.User.BusinessID))
	if err != nil {
		t.Fatalf("get business: %v", err)
	}
	if b.TimeZone != "Africa/Lagos" {
		t.Errorf("time_zone = %q, want Africa/Lagos", b.TimeZone)
	}
}

func TestTimeZone_RefusesANameThatIsNotAZone(t *testing.T) {
	s, _ := newService(t)

	var in business.RegisterBusinessInput
	in.Body.BusinessName = "Shop"
	in.Body.Name = "Owner"
	in.Body.Phone = "0711000142"
	in.Body.Password = "correct horse battery staple"
	in.Body.TimeZone = "EAT"
	if _, err := s.Register(context.Background(), in); !errors.Is(err, domain.ErrInvalidTimeZone) {
		t.Fatalf("register with EAT: got %v, want ErrInvalidTimeZone", err)
	}

	ctx := tenant.WithTenant(context.Background(), register(t, s, "0711000143").User.BusinessID)
	var up business.UpdateBusinessInput
	up.Body.Name = "Shop"
	up.Body.TimeZone = "Local"
	if _, err := s.UpdateBusiness(ctx, up); !errors.Is(err, domain.ErrInvalidTimeZone) {
		t.Fatalf("update to Local: got %v, want ErrInvalidTimeZone", err)
	}
}

func TestTimeZone_AnUpdateThatLeavesItOutKeepsIt(t *testing.T) {
	s, _ := newService(t)
	ctx := tenant.WithTenant(context.Background(), register(t, s, "0711000144").User.BusinessID)

	var up business.UpdateBusinessInput
	up.Body.Name = "Shop"
	up.Body.TimeZone = "Africa/Lagos"
	if _, err := s.UpdateBusiness(ctx, up); err != nil {
		t.Fatalf("set zone: %v", err)
	}

	// An app version that predates the field saves the name without it. That
	// must not move the shop back to Nairobi.
	var rename business.UpdateBusinessInput
	rename.Body.Name = "Renamed Shop"
	b, err := s.UpdateBusiness(ctx, rename)
	if err != nil {
		t.Fatalf("rename: %v", err)
	}
	if b.TimeZone != "Africa/Lagos" {
		t.Fatalf("time_zone after an update without it = %q, want Africa/Lagos", b.TimeZone)
	}
}

func TestPasswords_TheRulesAroundChangingAndResetting(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0711000150")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	if _, err := s.ChangePassword(ctx, owner.User.ID, "not the password", "a new password"); !errors.Is(err, business.ErrWrongPassword) {
		t.Errorf("wrong current password: got %v", err)
	}
	if _, err := s.ChangePassword(ctx, owner.User.ID, "correct horse battery staple", "correct horse battery staple"); !errors.Is(err, business.ErrSamePassword) {
		t.Errorf("same password: got %v", err)
	}
	if _, err := s.ResetStaffPassword(ctx, owner.User.ID, owner.User.ID); !errors.Is(err, business.ErrCannotResetSelf) {
		t.Errorf("resetting your own: got %v", err)
	}

	// A second owner cannot be reset by the first: either could otherwise lock
	// the other out of their own business.
	coOwner := &domain.User{Name: "Co-owner", Phone: "0711000151", PasswordHash: "x", Role: domain.RoleOwner, IsActive: true}
	if err := db.WithContext(ctx).Create(coOwner).Error; err != nil {
		t.Fatalf("co-owner: %v", err)
	}
	if _, err := s.ResetStaffPassword(ctx, owner.User.ID, coOwner.ID); !errors.Is(err, business.ErrCannotResetOwner) {
		t.Errorf("resetting another owner: got %v", err)
	}

	staff := &domain.User{Name: "Staff", Phone: "0711000152", PasswordHash: "x", Role: domain.RoleStaff, IsActive: true}
	if err := db.WithContext(ctx).Create(staff).Error; err != nil {
		t.Fatalf("staff: %v", err)
	}
	temp, err := s.ResetStaffPassword(ctx, owner.User.ID, staff.ID)
	if err != nil || len(temp) != 10 || strings.ContainsAny(temp, "0O1IL") {
		t.Fatalf("temporary password %q, %v: want 10 characters without look-alikes", temp, err)
	}
	got, err := s.Me(ctx, staff.ID)
	if err != nil || !got.MustChangePassword || got.SessionsValidAfter == nil {
		t.Fatalf("after a reset: must_change=%v sessions_valid_after=%v, %v", got.MustChangePassword, got.SessionsValidAfter, err)
	}
	// The staff member signs in with it, then chooses their own.
	if _, err := s.ChangePassword(ctx, staff.ID, temp, "my own password"); err != nil {
		t.Fatalf("changing from the temporary password: %v", err)
	}
	if got, _ := s.Me(ctx, staff.ID); got.MustChangePassword {
		t.Fatal("must_change_password is still set after choosing a new one")
	}
}
