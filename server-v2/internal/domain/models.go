// Package domain holds Salio's core entities.
//
// One package for all of them, rather than one per module, because they
// reference each other constantly — a transaction names a customer and a user,
// a customer names its creator — and splitting them would mean either import
// cycles or a layer of duplicate types that exists only to break them.
//
// # Invariants these types encode
//
// Every model except Business and SuperAdmin implements tenant.Tenanted, so
// GORM scopes every query by business_id whether or not the caller remembers to.
// Salio has already leaked across businesses once by relying on hand-written
// filters, which is why this is structural rather than a convention.
//
// Transactions are immutable: a mistake is corrected with an offsetting entry or
// a void, never by editing a row. Nothing is hard-deleted either — IsDeleted
// tombstones let deletions propagate through sync, where a physically removed
// row would simply be resurrected by the next device that syncs.
package domain

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/codetheuri/tusk/v2/pkg/id"

	"salio/server-v2/internal/money"
)

// Role names the two things a person can be within a business.
type Role string

const (
	// RoleStaff does all day-to-day work: adding customers, recording debts and
	// payments.
	RoleStaff Role = "staff"

	// RoleOwner additionally deletes customers, voids transactions, manages
	// staff, and edits business details.
	RoleOwner Role = "owner"
)

func (r Role) Valid() bool { return r == RoleStaff || r == RoleOwner }

// TransactionType is the direction of a ledger entry.
type TransactionType string

const (
	// TypeDebt increases what a customer owes.
	TypeDebt TransactionType = "debt"

	// TypePayment reduces it.
	TypePayment TransactionType = "payment"
)

func (t TransactionType) Valid() bool { return t == TypeDebt || t == TypePayment }

// Business is the tenant. Every other record belongs to exactly one.
type Business struct {
	ID        uuid.UUID `json:"id"        gorm:"type:uuid;primaryKey"`
	Name      string    `json:"name"      gorm:"size:255;not null"`
	Type      *string   `json:"type,omitempty" gorm:"size:100"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (Business) TableName() string { return "businesses" }

// TenantColumn scopes a Business by its own identifier.
//
// The effect is that an authenticated request can only ever read the business it
// belongs to — the lookup is scoped even when a handler passes an ID from
// elsewhere. Registration, which creates a business before any tenant exists to
// scope by, is the one caller that must say tenant.Unscoped explicitly.
func (Business) TenantColumn() string { return "id" }

func (b *Business) BeforeCreate(*gorm.DB) error {
	if id.IsZero(b.ID) {
		b.ID = id.New()
	}
	return nil
}

// User is an owner or a member of staff.
//
// Deliberately no email and no username: a shopkeeper signs in with the phone
// number they already know. Phone is globally unique because login takes a phone
// and a password with no business selector, so two businesses sharing a number
// would make the credential ambiguous.
type User struct {
	ID           uuid.UUID `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID   uuid.UUID `json:"business_id" gorm:"type:uuid;not null;index"`
	Name         string    `json:"name"        gorm:"size:255;not null"`
	Phone        string    `json:"phone"       gorm:"size:50;not null;uniqueIndex"`
	PasswordHash string    `json:"-"           gorm:"size:255;not null"`
	Role         Role      `json:"role"        gorm:"size:20;not null"`

	// IsActive rather than deletion: transactions reference users, so a row can
	// never actually go away without taking ledger history with it.
	IsActive bool `json:"is_active" gorm:"not null;default:true"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func (User) TableName() string    { return "users" }
func (User) TenantColumn() string { return "business_id" }

func (u *User) BeforeCreate(*gorm.DB) error {
	if id.IsZero(u.ID) {
		u.ID = id.New()
	}
	return nil
}

// IsOwner reports whether the user may perform owner-only actions.
func (u *User) IsOwner() bool { return u.Role == RoleOwner }

// BusinessInvite is a short-lived code linking new staff to a business.
type BusinessInvite struct {
	ID         uuid.UUID  `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID uuid.UUID  `json:"business_id" gorm:"type:uuid;not null"`
	Code       string     `json:"code"        gorm:"size:10;not null;uniqueIndex"`
	ExpiresAt  time.Time  `json:"expires_at"  gorm:"not null"`
	UsedAt     *time.Time `json:"used_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
}

func (BusinessInvite) TableName() string    { return "business_invites" }
func (BusinessInvite) TenantColumn() string { return "business_id" }

func (i *BusinessInvite) BeforeCreate(*gorm.DB) error {
	if id.IsZero(i.ID) {
		i.ID = id.New()
	}
	return nil
}

// Usable reports whether the invite can still be redeemed at the given time.
func (i *BusinessInvite) Usable(now time.Time) bool {
	return i.UsedAt == nil && now.Before(i.ExpiresAt)
}

// Customer owes money to a business. Customers never sign in.
type Customer struct {
	ID         uuid.UUID `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID uuid.UUID `json:"business_id" gorm:"type:uuid;not null;index"`
	Name       string    `json:"name"        gorm:"size:255;not null"`
	Phone      *string   `json:"phone,omitempty" gorm:"size:50"`
	Notes      *string   `json:"notes,omitempty"`
	CreatedBy  uuid.UUID `json:"created_by"  gorm:"type:uuid;not null"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	IsDeleted  bool      `json:"is_deleted"  gorm:"not null;default:false"`

	// FieldVersions records when each field last accepted a write, so two
	// offline devices editing different fields of this customer do not overwrite
	// one another. Never sent to clients: it is merge bookkeeping, not data
	// anyone using the app has a use for.
	FieldVersions FieldVersions `json:"-" gorm:"type:jsonb;not null;default:'{}'"`

	// ChangeSeq is assigned by a database trigger, never by this process. It
	// orders changes for sync across both synced tables from one sequence.
	ChangeSeq int64 `json:"-" gorm:"->"`
}

func (Customer) TableName() string    { return "customers" }
func (Customer) TenantColumn() string { return "business_id" }

func (c *Customer) BeforeCreate(*gorm.DB) error {
	if id.IsZero(c.ID) {
		c.ID = id.New()
	}
	return nil
}

// Transaction is one immutable ledger entry.
//
// Amount is always positive; direction lives in Type. Storing a signed amount
// would allow a "debt of -500", which is a payment wearing the wrong label and
// would quietly corrupt every report that groups by type.
type Transaction struct {
	ID         uuid.UUID `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID uuid.UUID `json:"business_id" gorm:"type:uuid;not null;index"`
	CustomerID uuid.UUID `json:"customer_id" gorm:"type:uuid;not null;index"`

	// UserID is who recorded the entry, kept for accountability. It is never
	// used to scope a query — that is BusinessID's job.
	UserID uuid.UUID `json:"user_id" gorm:"type:uuid;not null"`

	Type            TransactionType `json:"type"        gorm:"size:10;not null"`
	Amount          money.Amount    `json:"amount"      gorm:"type:numeric(12,2);not null"`
	Description     *string         `json:"description,omitempty"`
	TransactionDate time.Time       `json:"transaction_date" gorm:"type:date;not null"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
	IsDeleted       bool            `json:"is_deleted"  gorm:"not null;default:false"`

	ChangeSeq int64 `json:"-" gorm:"->"`
}

func (Transaction) TableName() string    { return "transactions" }
func (Transaction) TenantColumn() string { return "business_id" }

func (t *Transaction) BeforeCreate(*gorm.DB) error {
	if id.IsZero(t.ID) {
		t.ID = id.New()
	}
	return nil
}

// Signed returns the entry's effect on a customer's balance: a debt adds, a
// payment subtracts.
//
// Balances are always derived from these, never stored. A stored balance is a
// second source of truth that drifts the first time a write half-succeeds, and
// in an offline-first system writes half-succeed regularly.
func (t *Transaction) Signed() money.Amount {
	if t.Type == TypePayment {
		return -t.Amount
	}
	return t.Amount
}

// SuperAdmin operates the Salio platform.
//
// Not tenanted, and deliberately not a User: super admins belong to no business,
// sign in with an email rather than a phone, and hold a cookie session rather
// than a JWT. Keeping the two identity worlds in separate tables is what stops a
// bug in one from granting access through the other.
type SuperAdmin struct {
	ID           uuid.UUID `json:"id"    gorm:"type:uuid;primaryKey"`
	Name         string    `json:"name"  gorm:"size:255;not null"`
	Email        string    `json:"email" gorm:"size:255;not null;uniqueIndex"`
	PasswordHash string    `json:"-"     gorm:"size:255;not null"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

func (SuperAdmin) TableName() string { return "super_admins" }

func (s *SuperAdmin) BeforeCreate(*gorm.DB) error {
	if id.IsZero(s.ID) {
		s.ID = id.New()
	}
	return nil
}

// FieldVersions records when each field of a record last accepted a write.
//
// It exists so that two people editing different fields of the same customer
// while offline do not overwrite each other. Whole-record last-write-wins gives
// the whole row to whoever pushes second; per-field merge gives each field to
// whoever changed it most recently, and only that field.
//
// # Whose clock
//
// The times here come from the device that made the edit, and that is a
// deliberate exception to "the server clock is authoritative" — a rule aimed at
// sync *state*, which is why the pull cursor is server-issued. Ordering two
// edits is a different problem: what matters is when each person actually typed
// the change, and only their device knows that. Server receipt time would be
// worse, not better, because it would let a device that had been offline for two
// days overwrite an edit made this morning simply by reconnecting after it.
//
// The risk that buys is a device whose clock runs fast winning every conflict
// forever. ClampToServer bounds it: a timestamp from the future is treated as
// now, so a wrong clock can win the edits it is racing and not all future ones.
type FieldVersions map[string]time.Time

// ClockSkewTolerance is how far ahead of the server a device's clock may be
// before its timestamps are treated as the present moment.
//
// Generous, because the cost of being wrong in each direction is not the same.
// Clamping a device that is genuinely a few minutes fast loses nothing — its
// edit still wins anything older. Failing to clamp one that is a day fast hands
// it every conflict for a day.
const ClockSkewTolerance = 5 * time.Minute

// ClampToServer bounds a device-supplied time to the present.
func ClampToServer(deviceTime, serverNow time.Time) time.Time {
	if deviceTime.After(serverNow.Add(ClockSkewTolerance)) {
		return serverNow
	}
	return deviceTime
}

// VersionOf reports when a field last accepted a write, falling back to the
// record's own updated_at.
//
// The fallback is what makes this safe to add to a table full of existing rows,
// and safe alongside edits made through the API, which stamp updated_at without
// knowing about any of this. With no recorded version the comparison is exactly
// whole-record last-write-wins — the previous behaviour — so per-field merge is
// never *less* strict than what it replaces.
func (fv FieldVersions) VersionOf(field string, updatedAt time.Time) time.Time {
	if at, ok := fv[field]; ok {
		return at
	}
	return updatedAt
}

// Value implements driver.Valuer. A nil map is stored as an empty object rather
// than NULL, so the column can stay NOT NULL and no reader has to handle both.
func (fv FieldVersions) Value() (driver.Value, error) {
	if fv == nil {
		return []byte("{}"), nil
	}
	return json.Marshal(fv)
}

// Scan implements sql.Scanner.
func (fv *FieldVersions) Scan(src any) error {
	if src == nil {
		*fv = FieldVersions{}
		return nil
	}

	var raw []byte
	switch v := src.(type) {
	case []byte:
		raw = v
	case string:
		raw = []byte(v)
	default:
		return fmt.Errorf("domain: cannot scan %T into FieldVersions", src)
	}

	parsed := FieldVersions{}
	if err := json.Unmarshal(raw, &parsed); err != nil {
		return fmt.Errorf("domain: decoding field_versions: %w", err)
	}
	*fv = parsed
	return nil
}

func (FieldVersions) GormDataType() string { return "jsonb" }

// StampFieldVersions returns the JSON to merge into a row's field_versions when
// the named fields are written at a given time.
//
// Returned as JSON for `field_versions = field_versions || ?::jsonb` rather than
// applied to a loaded map: jsonb concatenation merges server-side in one
// statement, so two writers touching different fields cannot lose each other's
// keys in the gap between a read and a write.
func StampFieldVersions(fields []string, at time.Time) ([]byte, error) {
	stamp := make(FieldVersions, len(fields))
	for _, f := range fields {
		stamp[f] = at.UTC()
	}
	return json.Marshal(stamp)
}

// SyncOperation records the outcome of one push, so a retry is answered rather
// than re-applied.
//
// A client that times out cannot tell a request that never arrived from one that
// succeeded with a lost response, and retries either way. Without this, the retry
// of a batch containing a 500-shilling debt records it twice.
type SyncOperation struct {
	BusinessID  uuid.UUID `gorm:"type:uuid;primaryKey"`
	OperationID uuid.UUID `gorm:"type:uuid;primaryKey"`
	Result      []byte    `gorm:"type:jsonb;not null"`
	CreatedAt   time.Time `gorm:"not null"`
}

func (SyncOperation) TableName() string    { return "sync_operations" }
func (SyncOperation) TenantColumn() string { return "business_id" }

// TombstoneHorizon is the highest change_seq whose deleted rows have been
// collected. A cursor at or below it belongs to a device that has been offline
// longer than tombstones are kept, and must resync from scratch rather than be
// told about deletions that no longer exist to tell it about.
type TombstoneHorizon struct {
	OnlyRow   bool       `gorm:"column:only_row;primaryKey"`
	ChangeSeq int64      `gorm:"not null"`
	PurgedAt  *time.Time `gorm:""`
}

func (TombstoneHorizon) TableName() string { return "sync_tombstone_horizon" }
