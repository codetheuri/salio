package syncengine

import (
	"context"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
)

// DefaultMaxOfflineAge is how long a device may be away and still be trusted to
// have a usable cursor.
//
// It is the same number as the tombstone retention, and has to be: a tombstone
// may only be collected once no cursor that could have missed it is still being
// honoured. Ninety days is chosen against the product — a shop whose phone has
// not reached the internet in three months is starting again in every practical
// sense, and its local copy is a worse record than the server's.
const DefaultMaxOfflineAge = 90 * 24 * time.Hour

// Maintenance holds the periodic jobs the sync engine needs.
//
// Deliberately not started by cmd/api. These delete rows, and a timer inside the
// API process that quietly removes ledger history is not something to have
// running by default in a system whose whole purpose is not losing records. They
// are invoked by cmd/syncgc, on purpose, by someone who meant it.
type Maintenance struct {
	db *gorm.DB
}

func NewMaintenance(db *gorm.DB) *Maintenance { return &Maintenance{db: db} }

// PurgeReport says what a sweep did.
type PurgeReport struct {
	Businesses    int
	Customers     int64
	Transactions  int64
	Sales         int64
	StockRequests int64
	Suppliers     int64
	SupplierTxs   int64
	Operations    int64
	Horizon       int64
}

// PurgeTombstones collects deleted rows that no valid cursor can still need.
//
// Deleted rows are kept so the deletion can reach every device — a row removed
// while a device still holds it is resurrected by that device's next push. That
// is why nothing in Salio is hard-deleted, and it is also why tombstones would
// otherwise accumulate for the life of the product.
//
// The rule that ends it: past DefaultMaxOfflineAge a cursor is refused and the
// device is told to resync from zero, discarding its local copy. Once no cursor
// old enough to have missed a deletion is still honoured, the tombstone has done
// its job. This is the plan's max-offline-age policy, and the two halves are one
// mechanism — collecting tombstones without raising the horizon would resurrect
// rows, and raising the horizon without collecting them would keep them forever.
//
// The horizon is raised *before* anything is deleted. A device pulling between
// the two steps then gets told to resync — a wasted download — where the other
// order would hand it a page that silently omitted the deletions it needed. The
// conservative failure is the cheap one.
func (m *Maintenance) PurgeTombstones(ctx context.Context, olderThan time.Duration) (*PurgeReport, error) {
	if olderThan <= 0 {
		olderThan = DefaultMaxOfflineAge
	}
	cutoff := time.Now().UTC().Add(-olderThan)

	report := &PurgeReport{}

	// One cross-business read, through the same door the console uses. Read-only
	// by construction: migration 00005 makes every DELETE require a real tenant,
	// so the deletions below cannot take this shortcut even by mistake.
	var businesses []uuid.UUID
	var horizon int64
	if err := m.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec("SELECT set_config('app.platform_admin', 'on', true)").Error; err != nil {
			return err
		}
		if err := tenant.Unscoped(tx).Model(&domain.Business{}).Pluck("id", &businesses).Error; err != nil {
			return fmt.Errorf("listing businesses: %w", err)
		}
		// The highest sequence value about to disappear. Any cursor at or below
		// it belongs to a device that has been away longer than the retention.
		return tenant.Unscoped(tx).Raw(`
			SELECT COALESCE(MAX(change_seq), 0) FROM (
				SELECT change_seq FROM customers      WHERE is_deleted AND updated_at < ?
				UNION ALL
				SELECT change_seq FROM transactions   WHERE is_deleted AND updated_at < ?
				UNION ALL
				SELECT change_seq FROM sales          WHERE is_deleted AND updated_at < ?
				UNION ALL
				SELECT change_seq FROM stock_requests WHERE is_deleted AND updated_at < ?
				UNION ALL
				SELECT change_seq FROM suppliers      WHERE is_deleted AND updated_at < ?
				UNION ALL
				SELECT change_seq FROM supplier_transactions WHERE is_deleted AND updated_at < ?
			) AS doomed
		`, cutoff, cutoff, cutoff, cutoff, cutoff, cutoff).Scan(&horizon).Error
	}); err != nil {
		return nil, err
	}

	if horizon > 0 {
		if err := m.raiseHorizon(ctx, horizon); err != nil {
			return nil, err
		}
	}

	for _, businessID := range businesses {
		// Per business, declaring the tenant, because that is what the
		// restrictive DELETE policy requires — and requiring it is the point:
		// no maintenance job gets to delete across every shop at once.
		bctx := tenant.WithTenant(ctx, businessID)
		err := tenant.Transaction(bctx, m.db, func(tx *gorm.DB) error {
			// Children before parents. A transaction points at its customer
			// and possibly its sale, and a sale at its customer, so deleting a
			// parent first is exactly what the foreign keys refuse. (An earlier
			// version deleted customers first, with a comment claiming the
			// opposite; any deleted customer with history made the whole sweep
			// fail for that shop. It went unnoticed because the tests only ever
			// purged customers with no entries.)
			//
			// Each parent is also guarded by NOT EXISTS: a deleted customer
			// whose entries are still live — settled to zero, then deleted —
			// keeps its row, because that history needs a customer to belong
			// to. Kept rows only cost a little space; the horizon is raised
			// over them all the same, which is the safe direction.
			txs := tx.Where("business_id = ? AND is_deleted AND updated_at < ?", businessID, cutoff).
				Delete(&domain.Transaction{})
			if txs.Error != nil {
				return fmt.Errorf("purging transactions: %w", txs.Error)
			}
			report.Transactions += txs.RowsAffected

			sls := tx.Where(`business_id = ? AND is_deleted AND updated_at < ?
				AND NOT EXISTS (SELECT 1 FROM transactions t WHERE t.sale_id = sales.id)`, businessID, cutoff).
				Delete(&domain.Sale{})
			if sls.Error != nil {
				return fmt.Errorf("purging sales: %w", sls.Error)
			}
			report.Sales += sls.RowsAffected

			cust := tx.Where(`business_id = ? AND is_deleted AND updated_at < ?
				AND NOT EXISTS (SELECT 1 FROM transactions t WHERE t.customer_id = customers.id)
				AND NOT EXISTS (SELECT 1 FROM sales s WHERE s.customer_id = customers.id)`, businessID, cutoff).
				Delete(&domain.Customer{})
			if cust.Error != nil {
				return fmt.Errorf("purging customers: %w", cust.Error)
			}
			report.Customers += cust.RowsAffected

			reqs := tx.Where(`business_id = ? AND is_deleted AND updated_at < ?
				AND NOT EXISTS (SELECT 1 FROM purchase_order_lines l WHERE l.stock_request_id = stock_requests.id)`,
				businessID, cutoff).
				Delete(&domain.StockRequest{})
			if reqs.Error != nil {
				return fmt.Errorf("purging stock requests: %w", reqs.Error)
			}
			report.StockRequests += reqs.RowsAffected

			// The supplier ledger, children first, the same way round.
			stx := tx.Where("business_id = ? AND is_deleted AND updated_at < ?", businessID, cutoff).
				Delete(&domain.SupplierTransaction{})
			if stx.Error != nil {
				return fmt.Errorf("purging supplier entries: %w", stx.Error)
			}
			report.SupplierTxs += stx.RowsAffected

			sups := tx.Where(`business_id = ? AND is_deleted AND updated_at < ?
				AND NOT EXISTS (SELECT 1 FROM supplier_transactions t WHERE t.supplier_id = suppliers.id)`,
				businessID, cutoff).
				Delete(&domain.Supplier{})
			if sups.Error != nil {
				return fmt.Errorf("purging suppliers: %w", sups.Error)
			}
			report.Suppliers += sups.RowsAffected

			ops := tx.Where("business_id = ? AND created_at < ?", businessID, time.Now().UTC().Add(-OperationRetention)).
				Delete(&domain.SyncOperation{})
			if ops.Error != nil {
				return fmt.Errorf("purging push records: %w", ops.Error)
			}
			report.Operations += ops.RowsAffected
			return nil
		})
		if err != nil {
			return nil, fmt.Errorf("business %s: %w", businessID, err)
		}
		report.Businesses++
	}

	report.Horizon = horizon
	return report, nil
}

// raiseHorizon moves the horizon forward, never back.
//
// GREATEST rather than an assignment: two sweeps running at once, or one run
// with a shorter retention than the last, must not lower a boundary that devices
// have already been judged against.
//
// An upsert rather than an update, because an UPDATE that matches nothing
// succeeds. The migration seeds the row, but a database restored without it — or
// truncated, which is what the test harness does — would leave every sweep
// deleting tombstones while the horizon silently stayed at zero. Devices would
// then keep being handed pages that omitted deletions they never received, and
// push those rows back. Failing to raise the horizon is the one direction of
// this mechanism that loses data, so it may not be allowed to fail quietly.
func (m *Maintenance) raiseHorizon(ctx context.Context, seq int64) error {
	res := m.db.WithContext(ctx).Exec(`
		INSERT INTO sync_tombstone_horizon (only_row, change_seq, purged_at)
		VALUES (true, ?, NOW())
		ON CONFLICT (only_row) DO UPDATE
		SET change_seq = GREATEST(sync_tombstone_horizon.change_seq, EXCLUDED.change_seq),
		    purged_at  = NOW()
	`, seq)
	if res.Error != nil {
		return fmt.Errorf("raising the tombstone horizon: %w", res.Error)
	}
	if res.RowsAffected == 0 {
		return fmt.Errorf("raising the tombstone horizon to %d affected no rows", seq)
	}
	return nil
}
