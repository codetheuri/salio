package business

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/identity"
)

// ErrNotFound is returned when a record does not exist, or exists in another
// business — the two are deliberately indistinguishable to a caller. Telling a
// client "that customer exists but is not yours" confirms the record's
// existence, which is itself a leak.
var ErrNotFound = errors.New("not found")

// Repository is the only layer that touches the database.
type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// ---------------------------------------------------------------------------
// Pre-tenant operations
// ---------------------------------------------------------------------------
//
// The three below run before a tenant exists to scope by, and each says
// tenant.Unscoped explicitly. That is the escape hatch working as intended:
// registration creates the tenant, and login has to find a user by phone across
// every business, because the sign-in form asks only for a phone and a password.
// Grep for Unscoped and this is the complete list.
//
// Unscoped only silences the GORM tenant callbacks. Row-level security still
// applies, so each of these also either declares the new tenant itself
// (registering, joining) or reads through the identity door (signing in,
// checking a phone) — see internal/identity.

// CreateBusinessWithOwner registers a shop and its first user atomically.
//
// One transaction because a business with no owner is unreachable — nobody can
// sign in to it, and nothing can ever be added — and an owner with no business
// violates a foreign key. Half of this succeeding is not a degraded state, it is
// a corrupt one.
func (r *Repository) CreateBusinessWithOwner(
	ctx context.Context,
	b *domain.Business,
	u *domain.User,
	assignRole func(ctx context.Context, tx *gorm.DB, userID uuid.UUID, role domain.Role) error,
) error {
	return r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		// tenant.Unscoped(tx) is called fresh before every statement, never
		// stored and reused. The *gorm.DB it returns carries GORM's "ready to
		// execute" marker (clone == 0), which means the NEXT chained call
		// mutates its Statement in place rather than cloning — reusing one such
		// value across two .Create calls would silently carry the first
		// statement's table and columns into the second.
		if err := tenant.Unscoped(tx).Create(b).Error; err != nil {
			return fmt.Errorf("creating business: %w", err)
		}
		// The business exists now, so the rest of this transaction can say
		// whose it is — which row-level security requires before the owner
		// can be written.
		if err := identity.DeclareTenant(tx, b.ID.String()); err != nil {
			return err
		}

		u.BusinessID = b.ID
		if err := tenant.Unscoped(tx).Create(u).Error; err != nil {
			return fmt.Errorf("creating owner: %w", err)
		}

		return assignRole(ctx, tx, u.ID, u.Role)
	})
}

// PermissionsOf lists a user's permissions, sorted, read from the same tables
// the routes' guard checks (Tusk's authz), so the app is told exactly what
// the server will allow. The authz tables carry no tenant, so this works
// before sign-in has one.
func (r *Repository) PermissionsOf(ctx context.Context, userID uuid.UUID) ([]string, error) {
	names := []string{}
	err := r.db.WithContext(ctx).Table("user_roles").
		Joins("JOIN role_permissions ON role_permissions.role_id = user_roles.role_id").
		Where("user_roles.user_id = ?", userID).
		Distinct().Order("role_permissions.permission_name").
		Pluck("role_permissions.permission_name", &names).Error
	if err != nil {
		return nil, fmt.Errorf("reading permissions: %w", err)
	}
	return names, nil
}

// FindUserByPhone locates a user for sign-in.
func (r *Repository) FindUserByPhone(ctx context.Context, phone string) (*domain.User, error) {
	var u domain.User
	err := identity.Lookup(ctx, r.db, func(tx *gorm.DB) error {
		return tx.Where("phone = ?", phone).First(&u).Error
	})
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// PhoneTaken reports whether a phone number is already in use anywhere.
//
// Checked across all businesses because the column is globally unique: without
// this, a duplicate surfaces as a constraint violation the client cannot act on.
func (r *Repository) PhoneTaken(ctx context.Context, phone string) (bool, error) {
	var n int64
	err := identity.Lookup(ctx, r.db, func(tx *gorm.DB) error {
		return tx.Model(&domain.User{}).Where("phone = ?", phone).Count(&n).Error
	})
	return n > 0, err
}

// JoinBusiness redeems an invite and creates the staff member it was issued for.
//
// The invite is claimed with a conditional UPDATE rather than a read followed by
// a write. Two people entering the same code at once would both pass a
// read-then-check, and both join; here the second one updates zero rows and is
// told the code is spent. The database decides, not the gap between two queries.
func (r *Repository) JoinBusiness(
	ctx context.Context,
	code string,
	u *domain.User,
	assignRole func(ctx context.Context, tx *gorm.DB, userID uuid.UUID, role domain.Role) error,
) (*domain.Business, error) {
	var b domain.Business

	err := r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		now := time.Now()

		// Which business is this code for? Read through the identity door,
		// which is then closed again before anything is written.
		var found domain.BusinessInvite
		if err := identity.Open(tx); err != nil {
			return err
		}
		err := tenant.Unscoped(tx).Select("id", "business_id").
			Where("code = ? AND used_at IS NULL AND expires_at > ?", code, now).
			First(&found).Error
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("finding invite: %w", err)
		}
		if err := identity.Close(tx); err != nil {
			return err
		}
		if err := identity.DeclareTenant(tx, found.BusinessID.String()); err != nil {
			return err
		}

		// Same reasoning as CreateBusinessWithOwner: a fresh tenant.Unscoped(tx)
		// before every statement, never reused across more than one. The claim
		// is still the conditional UPDATE: the read above only located the
		// business, and two people redeeming one code at once must still see
		// exactly one of them succeed.
		var invite domain.BusinessInvite
		claim := tenant.Unscoped(tx).Model(&invite).
			Clauses(clause.Returning{}). // so the claimed row comes back in the same round trip
			Where("code = ? AND used_at IS NULL AND expires_at > ?", code, now).
			Update("used_at", now)
		if claim.Error != nil {
			return fmt.Errorf("claiming invite: %w", claim.Error)
		}
		if claim.RowsAffected == 0 {
			return ErrNotFound
		}

		if err := tenant.Unscoped(tx).First(&b, "id = ?", invite.BusinessID).Error; err != nil {
			return fmt.Errorf("loading business: %w", err)
		}

		u.BusinessID = invite.BusinessID
		if err := tenant.Unscoped(tx).Create(u).Error; err != nil {
			return fmt.Errorf("creating staff member: %w", err)
		}

		return assignRole(ctx, tx, u.ID, u.Role)
	})
	if err != nil {
		return nil, err
	}
	return &b, nil
}

// ---------------------------------------------------------------------------
// Tenant-scoped operations
// ---------------------------------------------------------------------------
//
// Everything below relies on the tenant in context. None of them filters by
// business_id by hand, and none of them needs to: the GORM callbacks add the
// predicate, and a missing tenant is an error rather than an unscoped read.

func (r *Repository) GetBusiness(ctx context.Context) (*domain.Business, error) {
	var b domain.Business
	// No WHERE: Business is scoped by its own id, so this returns exactly the
	// caller's business or nothing.
	err := r.db.WithContext(ctx).First(&b).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &b, err
}

type businessDetails struct {
	name                       string
	typ, phone, email, address *string
	timeZone                   *string // nil keeps the current zone
}

func (r *Repository) UpdateBusiness(ctx context.Context, d businessDetails) (*domain.Business, error) {
	b, err := r.GetBusiness(ctx)
	if err != nil {
		return nil, err
	}
	b.Name, b.Type = d.name, d.typ
	b.Phone, b.Email, b.Address = d.phone, d.email, d.address
	if d.timeZone != nil {
		b.TimeZone = *d.timeZone
	}
	if err := r.db.WithContext(ctx).Save(b).Error; err != nil {
		return nil, err
	}
	return b, nil
}

// SetPassword stores a new password hash and ends every session that began
// before validAfter (see internal/session).
func (r *Repository) SetPassword(ctx context.Context, userID uuid.UUID, hash string, mustChange bool, validAfter time.Time) error {
	res := r.db.WithContext(ctx).Model(&domain.User{}).
		Where("id = ?", userID).
		Updates(map[string]any{
			"password_hash":        hash,
			"must_change_password": mustChange, // in a map, so false is written, not skipped
			"sessions_valid_after": validAfter,
		})
	if res.Error != nil {
		return fmt.Errorf("setting password: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) GetUser(ctx context.Context, userID uuid.UUID) (*domain.User, error) {
	var u domain.User
	err := r.db.WithContext(ctx).First(&u, "id = ?", userID).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrNotFound
	}
	return &u, err
}

func (r *Repository) UpdateUserName(ctx context.Context, userID uuid.UUID, name string) (*domain.User, error) {
	res := r.db.WithContext(ctx).
		Model(&domain.User{}).
		Where("id = ?", userID).
		Update("name", name)
	if res.Error != nil {
		return nil, res.Error
	}
	if res.RowsAffected == 0 {
		return nil, ErrNotFound
	}
	return r.GetUser(ctx, userID)
}

func (r *Repository) ListStaff(ctx context.Context) ([]domain.User, error) {
	var users []domain.User
	err := r.db.WithContext(ctx).Order("created_at").Find(&users).Error
	return users, err
}

// DeactivateStaff disables an account without deleting it.
//
// Deletion is impossible: transactions reference users, so removing the row
// would take ledger history with it. is_active = false is the closest thing to
// removal that keeps the books intact.
func (r *Repository) DeactivateStaff(ctx context.Context, userID uuid.UUID) error {
	res := r.db.WithContext(ctx).
		Model(&domain.User{}).
		Where("id = ?", userID).
		Update("is_active", false)
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) CountOwners(ctx context.Context) (int64, error) {
	var n int64
	err := r.db.WithContext(ctx).
		Model(&domain.User{}).
		Where("role = ? AND is_active = true", domain.RoleOwner).
		Count(&n).Error
	return n, err
}

func (r *Repository) CreateInvite(ctx context.Context, invite *domain.BusinessInvite) error {
	return r.db.WithContext(ctx).Create(invite).Error
}
