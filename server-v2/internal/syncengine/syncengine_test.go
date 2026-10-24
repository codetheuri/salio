package syncengine_test

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/syncengine"
	"salio/server-v2/internal/testsupport"
)

type fixture struct {
	db  *gorm.DB
	svc *syncengine.Service
	ctx context.Context // carries the tenant, as a real request would

	businessID uuid.UUID
	userID     uuid.UUID
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	db := testsupport.Connect(t)

	// Real roles and permissions, read from the same tables the REST routes
	// check — sync enforces owner-only actions through them, so a fixture
	// without them would be testing a system that does not exist.
	if err := rbac.Seed(context.Background(), db); err != nil {
		t.Fatalf("seeding permissions: %v", err)
	}

	businessID, userID := seedBusiness(t, db, "Alpha Agrovet", "0712000001")
	return &fixture{
		db:         db,
		svc:        syncengine.NewService(syncengine.NewRepository(db)),
		ctx:        signedIn(businessID, userID),
		businessID: businessID,
		userID:     userID,
	}
}

// signedIn is the context a real request carries: the business from the
// token's tenant claim, and the user who is pushing.
func signedIn(businessID, userID uuid.UUID) context.Context {
	return authz.WithSubject(tenant.WithTenant(context.Background(), businessID), authz.Subject{UserID: userID})
}

// staff adds a member of staff to the fixture's business and returns a context
// signed in as them.
func (f *fixture) staff(t *testing.T, phone string) (context.Context, uuid.UUID) {
	t.Helper()
	u := domain.User{
		ID: id.New(), BusinessID: f.businessID, Name: "Staff", Phone: phone,
		PasswordHash: "x", Role: domain.RoleStaff, IsActive: true,
	}
	if err := tenant.Unscoped(f.db).Create(&u).Error; err != nil {
		t.Fatalf("creating staff: %v", err)
	}
	if err := rbac.AssignRole(context.Background(), f.db, u.ID, domain.RoleStaff); err != nil {
		t.Fatalf("assigning staff role: %v", err)
	}
	return signedIn(f.businessID, u.ID), u.ID
}

func desc(s string) *string { return &s }

// seedBusiness creates a business and its owner. tenant.Unscoped is called fresh
// per statement — its return shares one gorm.Statement with the receiver, so
// reusing it makes a second Create inherit the first's model.
func seedBusiness(t *testing.T, db *gorm.DB, name, phone string) (businessID, userID uuid.UUID) {
	t.Helper()

	b := domain.Business{ID: id.New(), Name: name}
	if err := tenant.Unscoped(db).Create(&b).Error; err != nil {
		t.Fatalf("creating business: %v", err)
	}
	u := domain.User{
		ID: id.New(), BusinessID: b.ID, Name: "Owner", Phone: phone,
		PasswordHash: "x", Role: domain.RoleOwner, IsActive: true,
	}
	if err := tenant.Unscoped(db).Create(&u).Error; err != nil {
		t.Fatalf("creating owner: %v", err)
	}
	if err := rbac.AssignRole(context.Background(), db, u.ID, domain.RoleOwner); err != nil {
		t.Fatalf("assigning owner role: %v", err)
	}
	return b.ID, u.ID
}

func (f *fixture) customer(t *testing.T, name string) uuid.UUID {
	t.Helper()
	c := domain.Customer{ID: id.New(), BusinessID: f.businessID, Name: name, CreatedBy: f.userID}
	if err := tenant.Unscoped(f.db).Create(&c).Error; err != nil {
		t.Fatalf("creating customer: %v", err)
	}
	return c.ID
}

func (f *fixture) push(t *testing.T, customers []syncengine.SyncCustomer, txs []syncengine.SyncTransaction) *syncengine.PushView {
	t.Helper()
	return f.pushAs(t, id.New(), customers, txs)
}

func (f *fixture) pushAs(t *testing.T, op uuid.UUID, customers []syncengine.SyncCustomer, txs []syncengine.SyncTransaction) *syncengine.PushView {
	t.Helper()

	var in syncengine.PushInput
	in.Body.OperationID = op
	in.Body.Customers = customers
	in.Body.Transactions = txs

	view, err := f.svc.Push(f.ctx, in)
	if err != nil {
		t.Fatalf("push: %v", err)
	}
	return view
}

func (f *fixture) pull(t *testing.T, cursor int64, limit int) *syncengine.PullView {
	t.Helper()
	view, err := f.svc.Pull(f.ctx, cursor, limit)
	if err != nil {
		t.Fatalf("pull: %v", err)
	}
	return view
}

func (f *fixture) loadCustomer(t *testing.T, cid uuid.UUID) domain.Customer {
	t.Helper()
	var c domain.Customer
	if err := tenant.Unscoped(f.db).First(&c, "id = ?", cid).Error; err != nil {
		t.Fatalf("loading customer: %v", err)
	}
	return c
}

func amount(t *testing.T, s string) money.Amount {
	t.Helper()
	a, err := money.Parse(s)
	if err != nil {
		t.Fatalf("parsing %q: %v", s, err)
	}
	return a
}

// ---------------------------------------------------------------------------
// The defect this whole phase exists for
// ---------------------------------------------------------------------------

// TestPull_DoesNotLoseAWriteCommittedAfterAConcurrentPull reproduces the
// original bug and proves the cursor closes it.
//
// v1 pulled WHERE updated_at > last_sync and stored the server clock as the next
// watermark. NOW() is the transaction *start* time, but rows appear at *commit*.
// A device pulling in between saw nothing, advanced its watermark past the
// pending row's timestamp, and never saw that row again — the records were not
// delayed, they were permanently invisible.
//
// Here the write is left uncommitted across a pull, exactly as in the diagnosis,
// and the assertion is that the very next pull with the returned cursor delivers
// it.
func TestPull_DoesNotLoseAWriteCommittedAfterAConcurrentPull(t *testing.T) {
	f := newFixture(t)
	f.customer(t, "Already here")

	first := f.pull(t, 0, 100)
	cursor := first.NextCursor

	// A write that has started but not committed. Its change_seq is allocated
	// now; the row becomes visible only when this returns.
	started := make(chan struct{})
	release := make(chan struct{})
	done := make(chan error, 1)

	go func() {
		done <- f.db.Transaction(func(tx *gorm.DB) error {
			c := domain.Customer{ID: id.New(), BusinessID: f.businessID, Name: "In flight", CreatedBy: f.userID}
			if err := tenant.Unscoped(tx).Create(&c).Error; err != nil {
				return err
			}
			close(started)
			<-release // hold the transaction open across the pull below
			return nil
		})
	}()

	<-started

	// The pull that used to poison the watermark. It sees nothing, because the
	// write has not committed.
	during := f.pull(t, cursor, 100)
	if len(during.Customers) != 0 {
		t.Fatalf("the pull saw %d customers; the write should not be visible yet", len(during.Customers))
	}

	// The cursor must not have moved past a row it did not deliver. This single
	// assertion is the fix: a clock-based watermark would have jumped to "now",
	// which is later than the pending row's timestamp.
	if during.NextCursor != cursor {
		t.Fatalf("the cursor advanced from %d to %d without delivering anything", cursor, during.NextCursor)
	}

	close(release)
	if err := <-done; err != nil {
		t.Fatalf("the in-flight write failed: %v", err)
	}

	after := f.pull(t, during.NextCursor, 100)
	if len(after.Customers) != 1 || after.Customers[0].Name != "In flight" {
		t.Fatalf("the committed write was not delivered: got %d customers", len(after.Customers))
	}
}

func TestPull_AdvancesOnlyAsFarAsItDelivered(t *testing.T) {
	f := newFixture(t)
	f.customer(t, "One")
	f.customer(t, "Two")

	view := f.pull(t, 0, 100)
	if len(view.Customers) != 2 {
		t.Fatalf("got %d customers, want 2", len(view.Customers))
	}

	var highest int64
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Select("MAX(change_seq)").Scan(&highest).Error; err != nil {
		t.Fatalf("reading the sequence: %v", err)
	}
	if view.NextCursor != highest {
		t.Fatalf("cursor = %d, want %d — the highest value actually delivered", view.NextCursor, highest)
	}

	// A pull that has nothing left must leave the cursor where it is, not
	// advance it to the present.
	empty := f.pull(t, view.NextCursor, 100)
	if empty.NextCursor != view.NextCursor {
		t.Fatalf("an empty pull moved the cursor from %d to %d", view.NextCursor, empty.NextCursor)
	}
	if empty.HasMore {
		t.Error("an empty pull reported more to come")
	}
}

// TestPull_PaginationLosesNothingAcrossTheTwoTables is the subtle one.
//
// Customers and transactions draw from one sequence, so their pages interleave.
// If a page is filled by one table while the other is exhausted, advancing the
// cursor to the fuller table's last value would skip everything the other table
// writes below it. The page has to be cut back to a point both have covered.
func TestPull_PaginationLosesNothingAcrossTheTwoTables(t *testing.T) {
	f := newFixture(t)

	// Interleaved deliberately: customer, transaction, customer, transaction…
	// so that any boundary chosen from one table alone falls in the middle of
	// the other's rows.
	wantCustomers := map[uuid.UUID]bool{}
	wantTransactions := map[uuid.UUID]bool{}
	for i := 0; i < 12; i++ {
		cid := f.customer(t, fmt.Sprintf("Customer %02d", i))
		wantCustomers[cid] = true

		tr := domain.Transaction{
			ID: id.New(), BusinessID: f.businessID, CustomerID: cid, UserID: f.userID,
			Type: domain.TypeDebt, Amount: amount(t, "100.00"), Description: desc("test entry"), TransactionDate: time.Now().UTC(),
		}
		if err := tenant.Unscoped(f.db).Create(&tr).Error; err != nil {
			t.Fatalf("creating transaction: %v", err)
		}
		wantTransactions[tr.ID] = true
	}

	gotCustomers := map[uuid.UUID]bool{}
	gotTransactions := map[uuid.UUID]bool{}

	cursor := int64(0)
	for page := 0; page < 50; page++ {
		view := f.pull(t, cursor, 3) // small pages, so truncation happens often
		for _, c := range view.Customers {
			if gotCustomers[c.ID] {
				t.Fatalf("customer %s was delivered on two pages", c.ID)
			}
			gotCustomers[c.ID] = true
		}
		for _, tr := range view.Transactions {
			if gotTransactions[tr.ID] {
				t.Fatalf("transaction %s was delivered on two pages", tr.ID)
			}
			gotTransactions[tr.ID] = true
		}
		if view.NextCursor <= cursor && view.HasMore {
			t.Fatalf("has_more with no cursor progress at %d — a client would loop forever", cursor)
		}
		cursor = view.NextCursor
		if !view.HasMore {
			break
		}
	}

	if len(gotCustomers) != len(wantCustomers) {
		t.Errorf("received %d of %d customers", len(gotCustomers), len(wantCustomers))
	}
	if len(gotTransactions) != len(wantTransactions) {
		t.Errorf("received %d of %d transactions", len(gotTransactions), len(wantTransactions))
	}
}

func TestPull_DeliversOnlyTheCallersBusiness(t *testing.T) {
	f := newFixture(t)
	f.customer(t, "Ours")

	otherID, otherUser := seedBusiness(t, f.db, "Beta Kiosk", "0712000002")
	other := domain.Customer{ID: id.New(), BusinessID: otherID, Name: "Theirs", CreatedBy: otherUser}
	if err := tenant.Unscoped(f.db).Create(&other).Error; err != nil {
		t.Fatalf("creating the other business's customer: %v", err)
	}

	// The sequence is global, so the other shop's row sits in the same cursor
	// space as ours. Nothing but the business filter keeps it out — and a leak
	// here writes another shop's book into this phone's database permanently.
	view := f.pull(t, 0, 100)
	for _, c := range view.Customers {
		if c.Name == "Theirs" {
			t.Fatal("a pull delivered another business's customer")
		}
	}
	if len(view.Customers) != 1 {
		t.Fatalf("got %d customers, want 1", len(view.Customers))
	}
}

// ---------------------------------------------------------------------------
// Idempotent push
// ---------------------------------------------------------------------------

// TestPush_RetryingAnOperationDoesNotRecordTheDebtTwice is the reason
// operation ids exist. A push that times out has an unknown outcome and the
// client retries; without this, the retry records the debt again and a customer
// is told they owe double.
func TestPush_RetryingAnOperationDoesNotRecordTheDebtTwice(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	op := id.New()
	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}

	first := f.pushAs(t, op, nil, []syncengine.SyncTransaction{entry})
	if first.AppliedTransactions != 1 || first.Replayed {
		t.Fatalf("first push: applied=%d replayed=%v, want 1 and false", first.AppliedTransactions, first.Replayed)
	}

	second := f.pushAs(t, op, nil, []syncengine.SyncTransaction{entry})
	if !second.Replayed {
		t.Error("the retry was not reported as a replay")
	}
	if second.AppliedTransactions != 1 {
		t.Errorf("the replay reported %d applied, want the original 1", second.AppliedTransactions)
	}

	var total money.Amount
	if err := tenant.Unscoped(f.db).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(amount), 0)").
		Where("business_id = ? AND is_deleted = false", f.businessID).
		Scan(&total).Error; err != nil {
		t.Fatalf("summing: %v", err)
	}
	if got, want := total.String(), "500.00"; got != want {
		t.Fatalf("ledger total = %s, want %s — the retry applied the batch twice", got, want)
	}
}

func TestPush_ConcurrentRetriesOfOneOperationApplyItOnce(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	op := id.New()
	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}

	// A flaky connection retries before the first attempt has answered. The
	// advisory lock serialises them; the claim makes the loser replay.
	const attempts = 6
	var wg sync.WaitGroup
	results := make([]*syncengine.PushView, attempts)
	errs := make([]error, attempts)

	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			var in syncengine.PushInput
			in.Body.OperationID = op
			in.Body.Transactions = []syncengine.SyncTransaction{entry}
			results[i], errs[i] = f.svc.Push(f.ctx, in)
		}(i)
	}
	wg.Wait()

	applied := 0
	for i, err := range errs {
		if err != nil {
			t.Fatalf("attempt %d failed: %v", i, err)
		}
		if !results[i].Replayed {
			applied++
		}
	}
	if applied != 1 {
		t.Fatalf("%d attempts did real work, want exactly 1", applied)
	}

	var count int64
	if err := tenant.Unscoped(f.db).Model(&domain.Transaction{}).
		Where("business_id = ?", f.businessID).Count(&count).Error; err != nil {
		t.Fatalf("counting: %v", err)
	}
	if count != 1 {
		t.Fatalf("%d transactions recorded, want 1", count)
	}
}

// ---------------------------------------------------------------------------
// Per-field merge
// ---------------------------------------------------------------------------

// TestPush_TwoDevicesEditingDifferentFieldsBothKeepTheirEdit is the headline.
//
// Whole-record last-write-wins gave the row to whoever pushed second, and the
// other person's correction disappeared with a "Sync successful".
func TestPush_TwoDevicesEditingDifferentFieldsBothKeepTheirEdit(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	base := f.loadCustomer(t, cid)

	phone := "+254722111222"
	notes := "Pays on Fridays"

	// Device A fixes the phone number.
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: base.Name, Phone: &phone, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"phone"},
	}}, nil)

	// Device B, which never saw that, adds a note a moment later.
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: base.Name, Notes: &notes, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(time.Second), ChangedFields: []string{"notes"},
	}}, nil)

	got := f.loadCustomer(t, cid)
	if got.Phone == nil || *got.Phone != phone {
		t.Errorf("phone = %v, want %q — device B's push overwrote a field it never edited", got.Phone, phone)
	}
	if got.Notes == nil || *got.Notes != notes {
		t.Errorf("notes = %v, want %q", got.Notes, notes)
	}
}

func TestPush_AStaleFieldWriteIsRejectedAndReported(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	recent := "+254722999999"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &recent, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"phone"},
	}}, nil)

	// A device that has been offline for an hour pushes an older edit to the
	// same field. It must lose, and must be told that it lost.
	stale := "+254700000000"
	view := f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &stale, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(-time.Hour), ChangedFields: []string{"phone"},
	}}, nil)

	if got := f.loadCustomer(t, cid); got.Phone == nil || *got.Phone != recent {
		t.Errorf("phone = %v, want the newer %q", got.Phone, recent)
	}

	if len(view.Conflicts) != 1 {
		t.Fatalf("got %d conflicts, want 1 — v1 answered this case with \"Sync successful\"", len(view.Conflicts))
	}
	c := view.Conflicts[0]
	if c.Reason != syncengine.ReasonStaleWrite || c.Field != "phone" {
		t.Errorf("conflict = %+v, want a stale_write on phone", c)
	}
}

func TestPush_AnEditMadeThroughTheAPIBeatsAnOlderOfflineEdit(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	// The API path stamps field versions of its own. Without that, an edit made
	// in the app while online would leave the versions behind the data, and a
	// stale push would be judged newer than it and overwrite it.
	apiPhone := "+254733444555"
	stamp, err := domain.StampFieldVersions([]string{"phone"}, time.Now().UTC())
	if err != nil {
		t.Fatalf("stamping: %v", err)
	}
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Where("id = ?", cid).
		Updates(map[string]any{
			"phone":          apiPhone,
			"field_versions": gorm.Expr("field_versions || ?::jsonb", stamp),
		}).Error; err != nil {
		t.Fatalf("api edit: %v", err)
	}

	old := "+254700000000"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &old, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(-time.Hour), ChangedFields: []string{"phone"},
	}}, nil)

	if got := f.loadCustomer(t, cid); got.Phone == nil || *got.Phone != apiPhone {
		t.Fatalf("phone = %v, want %q — a stale offline edit overwrote an API edit", got.Phone, apiPhone)
	}
}

func TestPush_WithoutChangedFieldsFallsBackToWholeRecord(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	// An app version that predates per-field merge sends the whole row and no
	// declaration. It must keep working, with exactly the behaviour it had.
	phone := "+254722111222"
	view := f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Renamed", Phone: &phone, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC(),
	}}, nil)

	if len(view.Conflicts) != 0 {
		t.Fatalf("unexpected conflicts: %+v", view.Conflicts)
	}
	got := f.loadCustomer(t, cid)
	if got.Name != "Renamed" || got.Phone == nil || *got.Phone != phone {
		t.Fatalf("got name=%q phone=%v, want the whole record applied", got.Name, got.Phone)
	}
}

func TestPush_DeletionIsOneWayAndCannotBeUndone(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", CreatedBy: f.userID, IsDeleted: true,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"is_deleted"},
	}}, nil)

	if !f.loadCustomer(t, cid).IsDeleted {
		t.Fatal("the deletion was not applied")
	}

	// A device that has not heard about the deletion pushes its stale copy with
	// a later timestamp. Honouring it would resurrect the row on every device.
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", CreatedBy: f.userID, IsDeleted: false,
		UpdatedAt: time.Now().UTC().Add(time.Hour), ChangedFields: []string{"is_deleted"},
	}}, nil)

	if !f.loadCustomer(t, cid).IsDeleted {
		t.Fatal("a stale push resurrected a deleted customer")
	}
}

func TestPush_ClampsATimestampFromTheFuture(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	// A cheap Android with a clock set two days ahead. Left unbounded, its edits
	// would beat every other device's for the next two days.
	fast := "+254700000001"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &fast, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(48 * time.Hour), ChangedFields: []string{"phone"},
	}}, nil)

	correct := "+254722333444"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &correct, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(time.Second), ChangedFields: []string{"phone"},
	}}, nil)

	if got := f.loadCustomer(t, cid); got.Phone == nil || *got.Phone != correct {
		t.Fatalf("phone = %v, want %q — a device with a fast clock kept winning", got.Phone, correct)
	}
}

// ---------------------------------------------------------------------------
// Transactions are immutable
// ---------------------------------------------------------------------------

func TestPush_CannotEditARecordedEntryAndIsToldSo(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	f.push(t, nil, []syncengine.SyncTransaction{entry})

	edited := entry
	edited.Amount = amount(t, "50.00")
	view := f.push(t, nil, []syncengine.SyncTransaction{edited})

	// v1 accepted this with a 200 and discarded it: its upsert merged only
	// is_deleted and updated_at, so an edited amount vanished without a word.
	if len(view.Conflicts) != 1 || view.Conflicts[0].Reason != syncengine.ReasonImmutable {
		t.Fatalf("conflicts = %+v, want one immutable conflict", view.Conflicts)
	}
	if view.Conflicts[0].Field != "amount" {
		t.Errorf("conflict field = %q, want amount", view.Conflicts[0].Field)
	}

	var stored domain.Transaction
	if err := tenant.Unscoped(f.db).First(&stored, "id = ?", entry.ID).Error; err != nil {
		t.Fatalf("loading: %v", err)
	}
	if got, want := stored.Amount.String(), "500.00"; got != want {
		t.Fatalf("amount = %s, want the original %s", got, want)
	}
}

// TestPush_AVoidSyncsAndMovesTheCursor covers the second v1 defect: the mobile
// soft-delete set is_deleted without bumping updated_at, so a voided entry fell
// outside every window and never reached the server or any other device.
func TestPush_AVoidSyncsAndMovesTheCursor(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	f.push(t, nil, []syncengine.SyncTransaction{entry})

	afterCreate := f.pull(t, 0, 100)

	voided := entry
	voided.IsDeleted = true
	view := f.push(t, nil, []syncengine.SyncTransaction{voided})
	if view.AppliedTransactions != 1 {
		t.Fatalf("the void was not applied: %+v", view)
	}

	// The void has to be reachable by a cursor, or another device never learns
	// the entry is gone and keeps counting it in the customer's balance.
	next := f.pull(t, afterCreate.NextCursor, 100)
	if len(next.Transactions) != 1 || !next.Transactions[0].IsDeleted {
		t.Fatalf("the void did not reach a pull: %+v", next.Transactions)
	}
}

func TestPush_PushingALiveCopyOfAVoidedEntryIsReported(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	f.push(t, nil, []syncengine.SyncTransaction{entry})

	voided := entry
	voided.IsDeleted = true
	f.push(t, nil, []syncengine.SyncTransaction{voided})

	// A device that has not pulled since still holds it as live.
	view := f.push(t, nil, []syncengine.SyncTransaction{entry})
	if len(view.Conflicts) != 1 || view.Conflicts[0].Reason != syncengine.ReasonAlreadyVoided {
		t.Fatalf("conflicts = %+v, want one already_voided", view.Conflicts)
	}

	var stored domain.Transaction
	if err := tenant.Unscoped(f.db).First(&stored, "id = ?", entry.ID).Error; err != nil {
		t.Fatalf("loading: %v", err)
	}
	if !stored.IsDeleted {
		t.Fatal("a stale push un-voided a transaction")
	}
}

// ---------------------------------------------------------------------------
// One bad record does not cost the batch
// ---------------------------------------------------------------------------

func TestPush_OneBadRecordDoesNotDiscardTheRest(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	good := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	orphan := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: id.New(), UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "100.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	zero := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "0.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}

	// v1 returned 500 for any one failure, so the client retried the same doomed
	// batch forever and the good records never landed.
	view := f.push(t, nil, []syncengine.SyncTransaction{good, orphan, zero})

	if view.AppliedTransactions != 1 {
		t.Errorf("applied = %d, want 1", view.AppliedTransactions)
	}
	if len(view.Conflicts) != 2 {
		t.Fatalf("conflicts = %+v, want 2", view.Conflicts)
	}

	reasons := map[string]bool{}
	for _, c := range view.Conflicts {
		reasons[c.Reason] = true
	}
	if !reasons[syncengine.ReasonUnknownCustomer] || !reasons[syncengine.ReasonInvalid] {
		t.Errorf("reasons = %v, want unknown_customer and invalid", reasons)
	}

	var count int64
	tenant.Unscoped(f.db).Model(&domain.Transaction{}).Where("business_id = ?", f.businessID).Count(&count)
	if count != 1 {
		t.Fatalf("%d transactions stored, want the 1 good one", count)
	}
}

func TestPush_CreatesACustomerAndItsEntriesInOneBatch(t *testing.T) {
	f := newFixture(t)

	// A device offline for a week has both the new customer and their debts.
	// Customers must be applied first or every entry is an orphan.
	cid := id.New()
	view := f.push(t,
		[]syncengine.SyncCustomer{{
			ID: cid, Name: "New Customer", CreatedBy: f.userID,
			CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
		}},
		[]syncengine.SyncTransaction{{
			ID: id.New(), CustomerID: cid, UserID: f.userID,
			Type: domain.TypeDebt, Amount: amount(t, "250.00"), Description: desc("test entry"),
			TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
		}})

	if view.AppliedCustomers != 1 || view.AppliedTransactions != 1 {
		t.Fatalf("applied %d customers and %d transactions, want 1 and 1 (conflicts: %+v)",
			view.AppliedCustomers, view.AppliedTransactions, view.Conflicts)
	}
}

func TestPush_StampsTheCallersBusinessNotThePayloads(t *testing.T) {
	f := newFixture(t)
	otherID, _ := seedBusiness(t, f.db, "Beta Kiosk", "0712000002")

	cid := id.New()
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Planted", CreatedBy: f.userID,
		CreatedAt: time.Now().UTC(), UpdatedAt: time.Now().UTC(),
	}}, nil)

	// The wire format carries no business_id at all, and this is why: it comes
	// from the token, so a crafted payload cannot write into another shop.
	got := f.loadCustomer(t, cid)
	if got.BusinessID != f.businessID {
		t.Fatalf("customer landed in business %s, want %s", got.BusinessID, f.businessID)
	}
	if got.BusinessID == otherID {
		t.Fatal("the payload chose the business")
	}
}

// ---------------------------------------------------------------------------
// B2: a conflict comes with the server's copy
// ---------------------------------------------------------------------------

// Without the copy, a phone that lost a field kept its own value for good: the
// server's row had not changed, so no pull would ever bring it back.
func TestPush_AConflictCarriesTheServersCurrentCopy(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	recent := "+254722999999"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &recent, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"phone"},
	}}, nil)

	stale := "+254700000000"
	view := f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &stale, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(-time.Hour), ChangedFields: []string{"phone"},
	}}, nil)

	if len(view.Current.Customers) != 1 {
		t.Fatalf("current customers = %+v, want the one that conflicted", view.Current.Customers)
	}
	got := view.Current.Customers[0]
	if got.ID != cid || got.Phone == nil || *got.Phone != recent {
		t.Errorf("copy = %+v, want the newer phone %q", got, recent)
	}
	if n := len(view.Current.Transactions) + len(view.Current.Sales) + len(view.Current.Suppliers); n != 0 {
		t.Errorf("%d unrelated copies returned", n)
	}
}

func TestPush_AVoidedEntryComesBackVoided(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")
	entry := syncengine.SyncTransaction{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}
	f.push(t, nil, []syncengine.SyncTransaction{entry})
	voided := entry
	voided.IsDeleted = true
	f.push(t, nil, []syncengine.SyncTransaction{voided})

	view := f.push(t, nil, []syncengine.SyncTransaction{entry})
	if len(view.Current.Transactions) != 1 || !view.Current.Transactions[0].IsDeleted {
		t.Fatalf("current = %+v, want the voided entry", view.Current.Transactions)
	}
}

func TestPush_ARefusedNewRecordHasNoCopy(t *testing.T) {
	f := newFixture(t)
	view := f.push(t, nil, []syncengine.SyncTransaction{{
		ID: id.New(), CustomerID: id.New(), UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("no such customer"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}})
	if len(view.Conflicts) != 1 || len(view.Current.Transactions) != 0 {
		t.Fatalf("conflicts %+v, current %+v: want one conflict and no copy", view.Conflicts, view.Current)
	}
}

// A replay is answered with the copy as it is now, not as it was when the
// first attempt ran. A phone that has pulled a newer copy in between must not
// be handed the older one.
func TestPush_AReplayCarriesTodaysCopyNotTheStoredOne(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	recent := "+254722999999"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &recent, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC(), ChangedFields: []string{"phone"},
	}}, nil)

	op := id.New()
	stale := "+254700000000"
	staleEdit := []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &stale, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(-time.Hour), ChangedFields: []string{"phone"},
	}}
	f.pushAs(t, op, staleEdit, nil)

	newest := "+254733111111"
	f.push(t, []syncengine.SyncCustomer{{
		ID: cid, Name: "Mama Mboga", Phone: &newest, CreatedBy: f.userID,
		UpdatedAt: time.Now().UTC().Add(time.Second), ChangedFields: []string{"phone"},
	}}, nil)

	replay := f.pushAs(t, op, staleEdit, nil)
	if !replay.Replayed || len(replay.Current.Customers) != 1 {
		t.Fatalf("replay = %+v", replay)
	}
	if p := replay.Current.Customers[0].Phone; p == nil || *p != newest {
		t.Errorf("replayed copy has phone %v, want today's %q", p, newest)
	}
}
