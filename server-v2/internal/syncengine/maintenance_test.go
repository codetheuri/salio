package syncengine_test

import (
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/syncengine"
)

// backdate ages a row past the retention window. updated_at is written directly
// because GORM stamps it on every write, so there is no ordinary way to produce
// a row that was last touched three months ago.
func (f *fixture) backdate(t *testing.T, table string, rowID uuid.UUID, age time.Duration) {
	t.Helper()
	err := f.db.Exec("UPDATE "+table+" SET updated_at = ? WHERE id = ?",
		time.Now().UTC().Add(-age), rowID).Error
	if err != nil {
		t.Fatalf("backdating %s: %v", table, err)
	}
}

func TestPurge_CollectsStaleTombstonesAndLeavesLiveRows(t *testing.T) {
	f := newFixture(t)

	stale := f.customer(t, "Long gone")
	recent := f.customer(t, "Recently removed")
	live := f.customer(t, "Still trading")

	for _, cid := range []uuid.UUID{stale, recent} {
		if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
			Where("id = ?", cid).Update("is_deleted", true).Error; err != nil {
			t.Fatalf("deleting: %v", err)
		}
	}
	f.backdate(t, "customers", stale, 200*24*time.Hour)

	report, err := syncengine.NewMaintenance(f.db).
		PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge)
	if err != nil {
		t.Fatalf("purge: %v", err)
	}
	if report.Customers != 1 {
		t.Errorf("collected %d customers, want 1", report.Customers)
	}

	for _, tc := range []struct {
		name string
		id   uuid.UUID
		want bool
	}{
		{"the stale tombstone", stale, false},
		{"the recent tombstone", recent, true},
		{"the live customer", live, true},
	} {
		var count int64
		tenant.Unscoped(f.db).Model(&domain.Customer{}).Where("id = ?", tc.id).Count(&count)
		if (count == 1) != tc.want {
			t.Errorf("%s: present=%v, want %v", tc.name, count == 1, tc.want)
		}
	}
}

// TestPurge_TellsAnOldCursorToResyncRatherThanLyingToIt is the other half of the
// same mechanism. Collecting a tombstone is only safe because any cursor that
// could have missed the deletion is refused afterwards — a device sent a page
// that silently omitted deletions would keep rows the shop deleted, and push
// them back.
func TestPurge_TellsAnOldCursorToResyncRatherThanLyingToIt(t *testing.T) {
	f := newFixture(t)

	cid := f.customer(t, "Removed while a device was away")
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Where("id = ?", cid).Update("is_deleted", true).Error; err != nil {
		t.Fatalf("deleting: %v", err)
	}

	// The cursor a long-absent device still holds: from before the deletion.
	var deletedSeq int64
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Select("change_seq").Where("id = ?", cid).Scan(&deletedSeq).Error; err != nil {
		t.Fatalf("reading the sequence: %v", err)
	}
	oldCursor := deletedSeq - 1

	f.backdate(t, "customers", cid, 200*24*time.Hour)
	if _, err := syncengine.NewMaintenance(f.db).PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge); err != nil {
		t.Fatalf("purge: %v", err)
	}

	view := f.pull(t, oldCursor, 100)
	if !view.ResyncRequired {
		t.Fatal("a cursor from before a collected deletion was honoured; that device would keep the deleted row")
	}
	if view.NextCursor != 0 {
		t.Errorf("next_cursor = %d, want 0 so the client starts over", view.NextCursor)
	}
	if len(view.Customers) != 0 || len(view.Transactions) != 0 {
		t.Error("a resync response carried records; the client is meant to discard everything first")
	}
}

func TestPurge_LeavesACurrentCursorAlone(t *testing.T) {
	f := newFixture(t)

	stale := f.customer(t, "Long gone")
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Where("id = ?", stale).Update("is_deleted", true).Error; err != nil {
		t.Fatalf("deleting: %v", err)
	}
	f.backdate(t, "customers", stale, 200*24*time.Hour)

	if _, err := syncengine.NewMaintenance(f.db).PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge); err != nil {
		t.Fatalf("purge: %v", err)
	}

	// A device that has synced since is above the horizon and must not be sent
	// back to zero — a full resync of a busy shop over 2G is expensive.
	f.customer(t, "Added after the sweep")
	current := f.pull(t, 0, 100)
	again := f.pull(t, current.NextCursor, 100)
	if again.ResyncRequired {
		t.Fatal("an up-to-date cursor was told to resync")
	}
}

func TestPurge_RaisesTheHorizonAndNeverLowersIt(t *testing.T) {
	f := newFixture(t)

	cid := f.customer(t, "Gone")
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Where("id = ?", cid).Update("is_deleted", true).Error; err != nil {
		t.Fatalf("deleting: %v", err)
	}
	f.backdate(t, "customers", cid, 200*24*time.Hour)

	m := syncengine.NewMaintenance(f.db)
	first, err := m.PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge)
	if err != nil {
		t.Fatalf("purge: %v", err)
	}
	if first.Horizon == 0 {
		t.Fatal("the horizon did not move")
	}

	// A second sweep finds nothing. The horizon must hold: devices have already
	// been judged against it, and lowering it would start honouring cursors that
	// were refused a moment ago.
	if _, err := m.PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge); err != nil {
		t.Fatalf("second purge: %v", err)
	}

	var h domain.TombstoneHorizon
	if err := f.db.First(&h).Error; err != nil {
		t.Fatalf("reading the horizon: %v", err)
	}
	if h.ChangeSeq != first.Horizon {
		t.Fatalf("horizon = %d after an empty sweep, want it held at %d", h.ChangeSeq, first.Horizon)
	}
}

func TestPurge_CollectsPushRecordsOnceTheyCannotAnswerARetry(t *testing.T) {
	f := newFixture(t)
	cid := f.customer(t, "Mama Mboga")

	op := id.New()
	f.pushAs(t, op, nil, []syncengine.SyncTransaction{{
		ID: id.New(), CustomerID: cid, UserID: f.userID,
		Type: domain.TypeDebt, Amount: amount(t, "500.00"), Description: desc("test entry"),
		TransactionDate: time.Now().UTC(), CreatedAt: time.Now().UTC(),
	}})

	if err := f.db.Exec("UPDATE sync_operations SET created_at = ? WHERE operation_id = ?",
		time.Now().UTC().Add(-30*24*time.Hour), op).Error; err != nil {
		t.Fatalf("ageing the record: %v", err)
	}

	if _, err := syncengine.NewMaintenance(f.db).PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge); err != nil {
		t.Fatalf("purge: %v", err)
	}

	var count int64
	tenant.Unscoped(f.db).Model(&domain.SyncOperation{}).Where("operation_id = ?", op).Count(&count)
	if count != 0 {
		t.Fatal("a month-old push record survived; nothing is retrying that far back")
	}
}

// TestPurge_ADeletedCustomerWithHistoryDoesNotFailTheSweep is the regression
// for a latent bug. The sweep used to delete customers before transactions, so a
// deleted customer with any entries hit the foreign key and failed the whole
// sweep for that shop — unnoticed, because earlier tests only ever purged
// customers with no entries.
func TestPurge_ADeletedCustomerWithHistoryDoesNotFailTheSweep(t *testing.T) {
	f := newFixture(t)

	settled := f.customer(t, "Paid up and deleted")
	f.push(t, nil, []syncengine.SyncTransaction{
		{ID: id.New(), CustomerID: settled, UserID: f.userID, Type: domain.TypeDebt,
			Amount: amount(t, "500.00"), Description: desc("seed"), TransactionDate: time.Now().UTC()},
		{ID: id.New(), CustomerID: settled, UserID: f.userID, Type: domain.TypePayment,
			Amount: amount(t, "500.00"), Description: desc("seed"), TransactionDate: time.Now().UTC(),
			PaymentMethod: &cashMethod},
	})
	if got := f.balance(t, settled); got != 0 {
		t.Fatalf("setup: balance = %s, want a settled customer", got)
	}
	if err := tenant.Unscoped(f.db).Model(&domain.Customer{}).
		Where("id = ?", settled).Update("is_deleted", true).Error; err != nil {
		t.Fatalf("deleting: %v", err)
	}
	f.backdate(t, "customers", settled, 200*24*time.Hour)

	if _, err := syncengine.NewMaintenance(f.db).PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge); err != nil {
		t.Fatalf("the sweep failed on a deleted customer with history: %v", err)
	}

	// Kept, not purged: its entries still belong to it.
	var count int64
	tenant.Unscoped(f.db).Model(&domain.Customer{}).Where("id = ?", settled).Count(&count)
	if count != 1 {
		t.Fatal("a customer whose entries are still live was purged out from under them")
	}
}

var cashMethod = domain.PaymentCash

// TestPurge_CollectsDeletedSupplierRecordsChildrenFirst: the supplier ledger
// gets the same sweep as the customer one, in the same order — entries before
// the supplier they point at — and a deleted supplier with live entries stays.
func TestPurge_CollectsDeletedSupplierRecordsChildrenFirst(t *testing.T) {
	f := newFixture(t)
	gone, kept := id.New(), id.New()
	voided := id.New()

	var in syncengine.PushInput
	in.Body.Suppliers = []syncengine.SyncSupplier{
		{ID: gone, Name: "Closed down", CreatedBy: f.userID},
		{ID: kept, Name: "Still owed", CreatedBy: f.userID},
	}
	in.Body.SupplierTransactions = []syncengine.SyncSupplierTransaction{
		{ID: voided, SupplierID: gone, Type: domain.SupplierBill, Amount: amount(t, "100.00"),
			Description: "entered by mistake", TransactionDate: time.Now().UTC(), IsDeleted: true},
		{ID: id.New(), SupplierID: kept, Type: domain.SupplierBill, Amount: amount(t, "100.00"),
			Description: "real bill", TransactionDate: time.Now().UTC()},
	}
	if v := pushAs(t, f, f.ctx, in); len(v.Conflicts) != 0 {
		t.Fatalf("setup push: %+v", v.Conflicts)
	}
	for _, sid := range []uuid.UUID{gone, kept} {
		if err := tenant.Unscoped(f.db).Model(&domain.Supplier{}).Where("id = ?", sid).
			Update("is_deleted", true).Error; err != nil {
			t.Fatalf("deleting: %v", err)
		}
		f.backdate(t, "suppliers", sid, 200*24*time.Hour)
	}
	f.backdate(t, "supplier_transactions", voided, 200*24*time.Hour)

	report, err := syncengine.NewMaintenance(f.db).PurgeTombstones(f.ctx, syncengine.DefaultMaxOfflineAge)
	if err != nil {
		t.Fatalf("purge: %v", err)
	}
	if report.SupplierTxs != 1 || report.Suppliers != 1 {
		t.Fatalf("purged %d entries and %d suppliers, want 1 and 1", report.SupplierTxs, report.Suppliers)
	}
	var left []uuid.UUID
	tenant.Unscoped(f.db).Model(&domain.Supplier{}).Pluck("id", &left)
	if len(left) != 1 || left[0] != kept {
		t.Fatalf("suppliers left = %v, want only the one whose bill is still live", left)
	}
	if report.Horizon == 0 {
		t.Fatal("tombstones were collected but the horizon did not move")
	}
}
