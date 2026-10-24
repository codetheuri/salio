package dataimport

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/phone"
	"salio/server-v2/internal/rbac"
)

// ErrTargetNotEmpty refuses an import into a database that already holds shops.
var ErrTargetNotEmpty = errors.New("the target database already contains businesses")

// Options controls one import run.
type Options struct {
	// Force imports into a non-empty target. Off by default because running the
	// import twice is the most likely operator mistake, and the second run would
	// not fail cleanly — every insert would collide on a primary key partway
	// through, leaving the target half-written.
	Force bool

	// Now fixes the clock, so a test can decide which invites are still live.
	// Zero means time.Now().
	Now time.Time
}

// Report is what an import did.
type Report struct {
	Businesses   int
	Users        int
	Invites      int
	Customers    int
	Transactions int
	SuperAdmins  int

	// PhonesKept counts numbers imported as v1 had them, not in the one
	// stored form (B15): unreadable as a phone number, or the same number as
	// another login or another customer of the shop in a different form.
	// They are for support to look at (docs/09), not for the import to merge.
	PhonesKept int

	// Sealed is the change_seq every device's cursor is now measured against.
	// See Importer.seal.
	Sealed int64
}

// Importer writes into the v2 schema.
type Importer struct {
	db *gorm.DB

	// Logins already given each number in this run: phones are unique across
	// every shop.
	logins map[string]bool
}

func NewImporter(db *gorm.DB) *Importer { return &Importer{db: db} }

// Run imports everything, one business at a time.
//
// # Why per business, and inside a tenant-declaring transaction
//
// The v2 tables are under row-level security keyed on app.tenant_id, and
// migration 00005 makes even a DELETE require it. An importer that reached for
// the platform-admin read door would find its inserts refused by WITH CHECK —
// correctly. Declaring the tenant per business instead means this tool is
// structurally incapable of writing one shop's rows into another's, which for a
// one-shot script handling every customer ledger the product has is worth more
// than the speed of a single bulk COPY.
//
// It also makes the unit of failure a business rather than the whole import: if
// one shop's data is malformed, the shops already committed stay committed and
// the operator is told exactly where to look.
//
// # Ordering, and why the historical interleaving is not reproduced
//
// v2 assigns change_seq from a trigger on insert, so insertion order becomes
// cursor order. v1's migration 006 went to some trouble to interleave customers
// and transactions by updated_at, because it was backfilling a live table whose
// clients already held cursors into it.
//
// Here, customers are inserted before transactions — they have to be, since
// transactions reference them — and that is also the better order. A device's
// first sync against v2 then receives every customer before any entry that
// refers to one, so it never holds an entry whose customer it has not seen. No
// client holds a v2 cursor yet, so there is no history to be faithful to.
func (i *Importer) Run(ctx context.Context, src *Source, opts Options) (*Report, error) {
	now := opts.Now
	if now.IsZero() {
		now = time.Now().UTC()
	}
	i.logins = map[string]bool{}

	if !opts.Force {
		var existing int64
		if err := tenant.Unscoped(i.db.WithContext(ctx)).Model(&domain.Business{}).
			Count(&existing).Error; err != nil {
			return nil, fmt.Errorf("checking the target: %w", err)
		}
		if existing > 0 {
			return nil, fmt.Errorf("%w: %d already present; pass -force only if you mean to add to them",
				ErrTargetNotEmpty, existing)
		}
	}

	report := &Report{}

	// Platform operators first and outside any tenant: super_admins belongs to no
	// business and carries no policy.
	admins, err := src.SuperAdmins(ctx)
	if err != nil {
		return nil, err
	}
	for _, a := range admins {
		row := domain.SuperAdmin{
			ID: a.ID, Name: a.Name, Email: a.Email, PasswordHash: a.PasswordHash,
			CreatedAt: a.CreatedAt, UpdatedAt: a.UpdatedAt,
		}
		if err := i.db.WithContext(ctx).Select("*").Create(&row).Error; err != nil {
			return nil, fmt.Errorf("importing super admin %s: %w", a.Email, err)
		}
		report.SuperAdmins++
	}

	// Before a single row is imported, so every imported row lands above the
	// boundary. See openCutoverBoundary.
	boundary, err := i.openCutoverBoundary(ctx, src)
	if err != nil {
		return nil, err
	}

	businesses, err := src.Businesses(ctx)
	if err != nil {
		return nil, err
	}

	for _, b := range businesses {
		if err := i.importBusiness(ctx, src, b, now, report); err != nil {
			return nil, fmt.Errorf("business %s (%s): %w", b.Name, b.ID, err)
		}
		report.Businesses++
	}

	if err := i.sealAt(ctx, boundary); err != nil {
		return nil, err
	}
	report.Sealed = boundary

	return report, nil
}

// canonicalOrKept returns a number's stored form (B15) unless it is
// unreadable or already taken in seen, when it is kept as v1 had it.
func canonicalOrKept(raw string, seen map[string]bool, report *Report) string {
	number, err := phone.Normalize(raw)
	if err != nil || seen[number] {
		report.PhonesKept++
		return raw
	}
	seen[number] = true
	return number
}

func (i *Importer) importBusiness(ctx context.Context, src *Source, b V1Business, now time.Time, report *Report) error {
	users, err := src.Users(ctx, b.ID)
	if err != nil {
		return err
	}
	invites, err := src.RedeemableInvites(ctx, b.ID, now)
	if err != nil {
		return err
	}
	customers, err := src.Customers(ctx, b.ID)
	if err != nil {
		return err
	}
	transactions, err := src.Transactions(ctx, b.ID)
	if err != nil {
		return err
	}

	bctx := tenant.WithTenant(ctx, b.ID)
	return tenant.Transaction(bctx, i.db, func(tx *gorm.DB) error {
		// businesses carries no policy — registration has to create one before
		// any tenant exists to declare — so this insert says Unscoped explicitly
		// rather than relying on the model's TenantColumn of "id" matching.
		row := domain.Business{ID: b.ID, Name: b.Name, Type: b.Type,
			CreatedAt: b.CreatedAt, UpdatedAt: b.UpdatedAt}
		if err := tenant.Unscoped(tx).Create(&row).Error; err != nil {
			return fmt.Errorf("inserting the business: %w", err)
		}

		for _, u := range users {
			role := domain.Role(u.Role)
			if !role.Valid() {
				// Refused rather than defaulted. Guessing that an unrecognised
				// role means "staff" could silently take an owner's ability to
				// manage their own shop; guessing "owner" would hand it out.
				return fmt.Errorf("user %s has role %q, which is neither owner nor staff", u.ID, u.Role)
			}

			userRow := domain.User{
				ID: u.ID, BusinessID: b.ID, Name: u.Name, Phone: canonicalOrKept(u.Phone, i.logins, report),
				PasswordHash: u.PasswordHash, Role: role, IsActive: u.IsActive,
				CreatedAt: u.CreatedAt, UpdatedAt: u.UpdatedAt,
			}
			if err := tx.Select("*").Create(&userRow).Error; err != nil {
				return fmt.Errorf("inserting user %s: %w", u.Phone, err)
			}

			// is_active is written again, explicitly, when it is false.
			//
			// GORM omits a zero-valued field whose column carries a default, and
			// users.is_active defaults to true — Select("*") does not override
			// that, because the skip happens while building the values rather
			// than while choosing the columns. Left alone, the migration would
			// silently reactivate every member of staff someone had deliberately
			// removed, handing back access to a shop's ledger at cutover. A test
			// caught it; two statements is a small price for not shipping it.
			if !u.IsActive {
				if err := tx.Model(&domain.User{}).Where("id = ?", u.ID).
					Update("is_active", false).Error; err != nil {
					return fmt.Errorf("deactivating user %s: %w", u.Phone, err)
				}
			}

			// Through rbac.AssignRole rather than by writing user_roles directly,
			// so the RBAC tables are populated by the same code the running
			// server uses. A hand-written insert here would be a second
			// definition of what a role means, free to drift from the first.
			if err := rbac.AssignRole(ctx, tx, u.ID, role); err != nil {
				return fmt.Errorf("assigning %s to %s: %w", role, u.Phone, err)
			}
			report.Users++
		}

		for _, in := range invites {
			inviteRow := domain.BusinessInvite{
				ID: id.New(), BusinessID: b.ID, Code: in.Code,
				ExpiresAt: in.ExpiresAt, CreatedAt: in.CreatedAt,
			}
			if err := tx.Create(&inviteRow).Error; err != nil {
				return fmt.Errorf("inserting invite %s: %w", in.Code, err)
			}
			report.Invites++
		}

		numbers := map[string]bool{} // a customer's number is unique within the shop
		for _, c := range customers {
			number := c.Phone
			if number != nil && strings.TrimSpace(*number) != "" {
				kept := canonicalOrKept(*number, numbers, report)
				number = &kept
			}
			custRow := domain.Customer{
				ID: c.ID, BusinessID: b.ID, Name: c.Name, Phone: number, Notes: c.Notes,
				CreatedBy: c.CreatedBy, CreatedAt: c.CreatedAt, UpdatedAt: c.UpdatedAt,
				IsDeleted: c.IsDeleted,
			}
			// FieldVersions is left empty: an absent version falls back to
			// updated_at, which is the ordering these rows already carry, so a
			// merge behaves exactly as v1's did until someone edits a field.
			if err := tx.Select("*").Omit("change_seq").Create(&custRow).Error; err != nil {
				return fmt.Errorf("inserting customer %s: %w", c.ID, err)
			}
			report.Customers++
		}

		for _, t := range transactions {
			amount, err := money.Parse(t.Amount)
			if err != nil {
				return fmt.Errorf("transaction %s has an unreadable amount %q: %w", t.ID, t.Amount, err)
			}

			txType := domain.TransactionType(t.Type)
			if !txType.Valid() {
				return fmt.Errorf("transaction %s has type %q, which is neither debt nor payment", t.ID, t.Type)
			}

			txRow := domain.Transaction{
				ID: t.ID, BusinessID: b.ID, CustomerID: t.CustomerID, UserID: t.UserID,
				Type: txType, Amount: amount, Description: t.Description,
				TransactionDate: t.TransactionDate, CreatedAt: t.CreatedAt,
				UpdatedAt: t.UpdatedAt, IsDeleted: t.IsDeleted,
			}
			// change_seq is omitted explicitly: the trigger assigns it, and
			// Select("*") would otherwise try to write the zero from the struct.
			if err := tx.Select("*").Omit("change_seq").Create(&txRow).Error; err != nil {
				return fmt.Errorf("inserting transaction %s: %w", t.ID, err)
			}
			report.Transactions++
		}

		return nil
	})
}

// openCutoverBoundary advances v2's sequence past anything v1 ever issued, and
// returns the boundary — which must happen before any row is imported.
//
// # The cutover hazard that has nothing to do with row data
//
// A phone holding v1 cursor 40,000, pointed at a v2 database whose sequence has
// reached 900, asks for changes above 40,000 and is told — correctly, and
// forever — that there are none. Its ledger silently stops updating.
//
// The fix reuses the tombstone horizon, which already means "a cursor at or below
// this is too old to honour; resync from zero". Set it above every v1 cursor and
// every device trips it exactly once, with no coordinated client change needed.
//
// # Why the ordering matters, and the loop it avoids
//
// The horizon must sit *below* the imported rows and *above* every v1 cursor, and
// those two demands only fit if the imported rows are above the old cursors too.
// Hence the sequence is advanced first: the boundary is fixed, the import lands
// entirely above it, and the cursor a fresh sync hands back is therefore above it
// as well.
//
// Setting the horizon above the imported rows instead — the obvious way round —
// puts a freshly-synced device *below* the horizon, so its next pull is told to
// resync again, and again. A test caught it: a resync loop with no way out but a
// new build.
func (i *Importer) openCutoverBoundary(ctx context.Context, src *Source) (int64, error) {
	v1Seq, err := src.HighestChangeSeq(ctx)
	if err != nil {
		return 0, err
	}

	var v2Seq int64
	if err := i.db.WithContext(ctx).Raw(`SELECT last_value FROM sync_change_seq`).
		Scan(&v2Seq).Error; err != nil {
		return 0, fmt.Errorf("reading the v2 sequence: %w", err)
	}

	boundary := v1Seq
	if v2Seq > boundary {
		boundary = v2Seq
	}
	// A margin, so a cursor equal to the highest value v1 ever handed out is
	// comfortably below the boundary rather than exactly on it.
	boundary += 1000

	if err := i.db.WithContext(ctx).Exec(`SELECT setval('sync_change_seq', ?)`, boundary).Error; err != nil {
		return 0, fmt.Errorf("advancing the v2 sequence: %w", err)
	}
	return boundary, nil
}

// sealAt records the boundary as the tombstone horizon, once the import is above it.
func (i *Importer) sealAt(ctx context.Context, boundary int64) error {
	// Upsert, and an error when it touches nothing: a horizon that silently
	// stayed at zero would leave every device in the field pointing at a cursor
	// this database will never reach.
	res := i.db.WithContext(ctx).Exec(`
		INSERT INTO sync_tombstone_horizon (only_row, change_seq, purged_at)
		VALUES (true, ?, NOW())
		ON CONFLICT (only_row) DO UPDATE
		SET change_seq = GREATEST(sync_tombstone_horizon.change_seq, EXCLUDED.change_seq),
		    purged_at  = NOW()
	`, boundary)
	if res.Error != nil {
		return fmt.Errorf("setting the cutover horizon: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return fmt.Errorf("setting the cutover horizon to %d affected no rows", boundary)
	}
	return nil
}
