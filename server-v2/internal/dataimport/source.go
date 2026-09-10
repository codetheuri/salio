// Package dataimport moves a live v1 Salio database into the v2 schema.
//
// It is deliberately one-way and read-only on the source. The v1 server keeps
// running and serving real shops throughout, and stays available read-only for a
// rollback window afterwards — so nothing here may write to it, and nothing here
// may depend on it being quiescent beyond the moment the snapshot is taken.
//
// # What actually differs between the schemas
//
// Very little, which is the point: the v2 core tables were written to hold the
// same rows. The transforms that do exist:
//
//	business_invites.id     SERIAL in v1, UUID in v2 — new identifiers, and only
//	                        for invites still redeemable; a used or expired code
//	                        is noise, not data.
//	permissions/roles/…     v1 has no RBAC tables. Roles are derived from
//	                        users.role through rbac.AssignRole, so the two stay
//	                        consistent by construction rather than by copying.
//	customers.field_versions  new, and correctly left empty: an absent version
//	                        falls back to updated_at, which is exactly the
//	                        ordering v1 rows already carry.
//	change_seq              reassigned by v2's trigger on insert, never copied.
//	                        See Importer.Run for the ordering that implies.
//	console_sessions        not migrated. v1 stored the raw cookie value as the
//	                        primary key; v2 stores only a SHA-256 digest, and
//	                        importing sessions would mean handling those raw
//	                        tokens for no better reason than saving four people
//	                        one sign-in.
package dataimport

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/google/uuid"
)

// Source is a read-only handle on a v1 database.
type Source struct {
	db *sql.DB
}

// NewSource wraps an already-open connection to the v1 database.
//
// Takes a *sql.DB rather than a DSN so the caller owns the connection, and so a
// test can hand over a database it prepared itself.
func NewSource(db *sql.DB) *Source { return &Source{db: db} }

// V1Business, V1User and the rest are the source rows.
//
// Declared here rather than reused from internal/domain on purpose. These
// describe a schema that is not ours to change and that will stop existing after
// cutover; binding them to the live models would mean every future change to a
// domain type silently altered how a historical import reads.
type V1Business struct {
	ID        uuid.UUID
	Name      string
	Type      *string
	CreatedAt time.Time
	UpdatedAt time.Time
}

type V1User struct {
	ID           uuid.UUID
	BusinessID   uuid.UUID
	Name         string
	Phone        string
	PasswordHash string
	Role         string
	IsActive     bool
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

type V1Invite struct {
	BusinessID uuid.UUID
	Code       string
	ExpiresAt  time.Time
	CreatedAt  time.Time
}

type V1Customer struct {
	ID         uuid.UUID
	BusinessID uuid.UUID
	Name       string
	Phone      *string
	Notes      *string
	CreatedBy  uuid.UUID
	CreatedAt  time.Time
	UpdatedAt  time.Time
	IsDeleted  bool
}

type V1Transaction struct {
	ID         uuid.UUID
	BusinessID uuid.UUID
	CustomerID uuid.UUID
	UserID     uuid.UUID
	Type       string

	// Amount is carried as the exact decimal text Postgres stores.
	//
	// Never as a float64. A balance is the sum of these, the whole product is a
	// record of who owes what, and a migration that rounds one entry by a cent
	// has silently changed a real debt. The verifier compares balances exactly,
	// which is only meaningful if nothing along the way was approximate.
	Amount string

	Description     *string
	TransactionDate time.Time
	CreatedAt       time.Time
	UpdatedAt       time.Time
	IsDeleted       bool
}

type V1SuperAdmin struct {
	ID           uuid.UUID
	Name         string
	Email        string
	PasswordHash string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

// Businesses lists every business, oldest first.
func (s *Source) Businesses(ctx context.Context) ([]V1Business, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, type, created_at, updated_at
		FROM businesses ORDER BY created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("reading businesses: %w", err)
	}
	defer rows.Close()

	var out []V1Business
	for rows.Next() {
		var b V1Business
		if err := rows.Scan(&b.ID, &b.Name, &b.Type, &b.CreatedAt, &b.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scanning business: %w", err)
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (s *Source) Users(ctx context.Context, businessID uuid.UUID) ([]V1User, error) {
	// Owners first, then by creation. The order matters: customers.created_by
	// references users, and importing the owner first means the row most likely
	// to be referenced is already present.
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, business_id, name, phone, password_hash, role, is_active, created_at, updated_at
		FROM users WHERE business_id = $1
		ORDER BY CASE role WHEN 'owner' THEN 0 ELSE 1 END, created_at, id`, businessID)
	if err != nil {
		return nil, fmt.Errorf("reading users: %w", err)
	}
	defer rows.Close()

	var out []V1User
	for rows.Next() {
		var u V1User
		if err := rows.Scan(&u.ID, &u.BusinessID, &u.Name, &u.Phone, &u.PasswordHash,
			&u.Role, &u.IsActive, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scanning user: %w", err)
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// RedeemableInvites returns only codes that could still be used.
//
// A used or expired invite carries no information anyone will act on, and its
// v1 identifier is a SERIAL that cannot be carried across anyway. Migrating one
// that is still live matters: someone was sent that code this morning and will
// type it in this afternoon.
func (s *Source) RedeemableInvites(ctx context.Context, businessID uuid.UUID, now time.Time) ([]V1Invite, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT business_id, code, expires_at, created_at
		FROM business_invites
		WHERE business_id = $1 AND used_at IS NULL AND expires_at > $2
		ORDER BY created_at, code`, businessID, now)
	if err != nil {
		return nil, fmt.Errorf("reading invites: %w", err)
	}
	defer rows.Close()

	var out []V1Invite
	for rows.Next() {
		var i V1Invite
		if err := rows.Scan(&i.BusinessID, &i.Code, &i.ExpiresAt, &i.CreatedAt); err != nil {
			return nil, fmt.Errorf("scanning invite: %w", err)
		}
		out = append(out, i)
	}
	return out, rows.Err()
}

// Customers returns every customer, tombstones included.
//
// Deleted rows are carried over deliberately. A tombstone is what tells a device
// that has not synced yet that the row is gone; dropping them at cutover would
// have every phone push its deleted customers straight back.
func (s *Source) Customers(ctx context.Context, businessID uuid.UUID) ([]V1Customer, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted
		FROM customers WHERE business_id = $1 ORDER BY created_at, id`, businessID)
	if err != nil {
		return nil, fmt.Errorf("reading customers: %w", err)
	}
	defer rows.Close()

	var out []V1Customer
	for rows.Next() {
		var c V1Customer
		if err := rows.Scan(&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes,
			&c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted); err != nil {
			return nil, fmt.Errorf("scanning customer: %w", err)
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Source) Transactions(ctx context.Context, businessID uuid.UUID) ([]V1Transaction, error) {
	// amount::text, so Postgres formats the NUMERIC and nothing in the driver or
	// in Go gets an opportunity to make it a float.
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, business_id, customer_id, user_id, type, amount::text, description,
		       transaction_date, created_at, updated_at, is_deleted
		FROM transactions WHERE business_id = $1 ORDER BY created_at, id`, businessID)
	if err != nil {
		return nil, fmt.Errorf("reading transactions: %w", err)
	}
	defer rows.Close()

	var out []V1Transaction
	for rows.Next() {
		var t V1Transaction
		if err := rows.Scan(&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type,
			&t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt,
			&t.IsDeleted); err != nil {
			return nil, fmt.Errorf("scanning transaction: %w", err)
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Source) SuperAdmins(ctx context.Context) ([]V1SuperAdmin, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, email, password_hash, created_at, updated_at
		FROM super_admins ORDER BY created_at, id`)
	if err != nil {
		return nil, fmt.Errorf("reading super admins: %w", err)
	}
	defer rows.Close()

	var out []V1SuperAdmin
	for rows.Next() {
		var a V1SuperAdmin
		if err := rows.Scan(&a.ID, &a.Name, &a.Email, &a.PasswordHash, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, fmt.Errorf("scanning super admin: %w", err)
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// HighestChangeSeq reports how far v1's sync sequence has advanced.
//
// Needed because devices in the field hold cursors from it. v2's sequence starts
// at 1, so without knowing this a phone holding cursor 40,000 would point at a
// server whose sequence had reached 900 and would never be sent anything again.
// Importer.seal uses it. Zero if v1 never ran migration 006.
func (s *Source) HighestChangeSeq(ctx context.Context) (int64, error) {
	var seq *int64
	err := s.db.QueryRowContext(ctx, `
		SELECT GREATEST(
			(SELECT COALESCE(MAX(change_seq), 0) FROM customers),
			(SELECT COALESCE(MAX(change_seq), 0) FROM transactions)
		)`).Scan(&seq)
	if err != nil {
		// The column only exists if v1 ran migration 006. Treated as zero rather
		// than as a failure: importing from a v1 that predates the cursor hotfix
		// is a legitimate case, and every device it serves holds a timestamp
		// rather than a cursor.
		return 0, nil
	}
	if seq == nil {
		return 0, nil
	}
	return *seq, nil
}

// Counts is what the verifier compares against.
type Counts struct {
	Businesses   int64
	Users        int64
	Customers    int64
	Transactions int64
	SuperAdmins  int64
}

func (s *Source) Counts(ctx context.Context) (*Counts, error) {
	var c Counts
	err := s.db.QueryRowContext(ctx, `
		SELECT (SELECT COUNT(*) FROM businesses),
		       (SELECT COUNT(*) FROM users),
		       (SELECT COUNT(*) FROM customers),
		       (SELECT COUNT(*) FROM transactions),
		       (SELECT COUNT(*) FROM super_admins)
	`).Scan(&c.Businesses, &c.Users, &c.Customers, &c.Transactions, &c.SuperAdmins)
	if err != nil {
		return nil, fmt.Errorf("counting source rows: %w", err)
	}
	return &c, nil
}

// Balances returns every active customer's balance, keyed by customer.
//
// This is the number the whole migration is judged on. Same formula on both
// sides — SUM(debt) - SUM(payment) over rows that are not tombstoned — because a
// balance is derived, never stored, and the two sides must derive it identically
// or the comparison proves nothing.
func (s *Source) Balances(ctx context.Context) (map[uuid.UUID]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT c.id,
		       COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END), 0)::text
		FROM customers c
		LEFT JOIN transactions t ON t.customer_id = c.id AND t.is_deleted = false
		WHERE c.is_deleted = false
		GROUP BY c.id`)
	if err != nil {
		return nil, fmt.Errorf("computing source balances: %w", err)
	}
	defer rows.Close()

	out := map[uuid.UUID]string{}
	for rows.Next() {
		var id uuid.UUID
		var balance string
		if err := rows.Scan(&id, &balance); err != nil {
			return nil, fmt.Errorf("scanning balance: %w", err)
		}
		out[id] = balance
	}
	return out, rows.Err()
}
