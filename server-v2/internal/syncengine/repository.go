package syncengine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
)

// Page sizes for a pull.
//
// Before pagination existed, a pull returned every row a business had ever
// created in one response, with no way to resume a failed attempt. A shop with
// ten thousand entries on a 2G connection could not sync at all.
const (
	DefaultPullLimit = 500
	MaxPullLimit     = 2000
)

// OperationRetention is how long a push outcome is remembered for replay.
//
// It only has to outlast a client's retry schedule. A "retry" arriving a week
// later is a new intention, not the same one — and keeping every push forever
// would make this table the largest in the database.
const OperationRetention = 7 * 24 * time.Hour

// ErrResyncRequired reports a cursor older than tombstones are kept for.
var ErrResyncRequired = errors.New("cursor is older than the tombstone horizon; a full resync is required")

type Repository struct {
	db *gorm.DB
}

func NewRepository(db *gorm.DB) *Repository { return &Repository{db: db} }

// --- Pull ---

// Pull returns one page of changes after the cursor, in sequence order.
//
// The cursor is a server-issued sequence value, never a clock. A client advances
// it only as far as the highest value actually delivered, so it cannot step over
// a row belonging to a transaction that had started but not yet committed — the
// defect that made records permanently invisible in v1 (plan §5).
//
// includeSuppliers says whether the caller may read supplier records. When not,
// those tables are not read at all, so they neither appear on the page nor
// constrain how far the cursor advances.
func (r *Repository) Pull(ctx context.Context, cursor int64, limit int, includeSuppliers bool) (*PullView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	if limit <= 0 {
		limit = DefaultPullLimit
	}
	if limit > MaxPullLimit {
		limit = MaxPullLimit
	}

	// Checked before reading anything. A device this far behind is going to be
	// told to start over, and the page it would otherwise be sent is misleading:
	// it would be missing exactly the deletions that have been collected.
	horizon, err := r.horizon(ctx)
	if err != nil {
		return nil, err
	}
	if cursor > 0 && cursor <= horizon {
		return &PullView{
			Customers: []SyncCustomer{}, Transactions: []SyncTransaction{},
			Sales: []SyncSale{}, StockRequests: []SyncStockRequest{},
			Suppliers: []SyncSupplier{}, SupplierTransactions: []SyncSupplierTransaction{},
			NextCursor: 0, ResyncRequired: true, ServerTime: time.Now().UTC(),
		}, nil
	}

	// One row beyond the limit, as a lookahead: its presence is what says more
	// remains, without a second counting query.
	customers, err := fetchAfter[domain.Customer](ctx, r.db, businessID, cursor, limit+1)
	if err != nil {
		return nil, fmt.Errorf("pulling customers: %w", err)
	}
	transactions, err := fetchAfter[domain.Transaction](ctx, r.db, businessID, cursor, limit+1)
	if err != nil {
		return nil, fmt.Errorf("pulling transactions: %w", err)
	}
	sales, err := fetchAfter[domain.Sale](ctx, r.db, businessID, cursor, limit+1)
	if err != nil {
		return nil, fmt.Errorf("pulling sales: %w", err)
	}
	requests, err := fetchAfter[domain.StockRequest](ctx, r.db, businessID, cursor, limit+1)
	if err != nil {
		return nil, fmt.Errorf("pulling stock requests: %w", err)
	}
	var suppliers []domain.Supplier
	var supplierTxs []domain.SupplierTransaction
	if includeSuppliers {
		if suppliers, err = fetchAfter[domain.Supplier](ctx, r.db, businessID, cursor, limit+1); err != nil {
			return nil, fmt.Errorf("pulling suppliers: %w", err)
		}
		if supplierTxs, err = fetchAfter[domain.SupplierTransaction](ctx, r.db, businessID, cursor, limit+1); err != nil {
			return nil, fmt.Errorf("pulling supplier entries: %w", err)
		}
	}

	// Every table draws from one sequence, so their pages interleave. When any
	// table fills its page, the cursor may advance only to a point *every*
	// table has covered — the lowest last-value among the truncated tables.
	//
	// Say customers fill their page up to seq 900 while transactions are
	// exhausted at 480. Advancing to 900 would lose every transaction later
	// written between 481 and 900: the next pull asks for > 900 and never looks
	// below it again. So everything is cut back to the lowest such boundary,
	// and the rest comes on the next page. With four tables the rule is the
	// same; there are just more candidates for the lowest.
	boundary, hasMore := int64(-1), false
	consider := func(truncated bool, last int64) {
		if !truncated {
			return
		}
		hasMore = true
		if boundary < 0 || last < boundary {
			boundary = last
		}
	}
	customers, cTrunc := capAt(customers, limit)
	transactions, tTrunc := capAt(transactions, limit)
	sales, sTrunc := capAt(sales, limit)
	requests, rTrunc := capAt(requests, limit)
	suppliers, supTrunc := capAt(suppliers, limit)
	supplierTxs, stTrunc := capAt(supplierTxs, limit)
	if cTrunc {
		consider(true, customers[len(customers)-1].ChangeSeq)
	}
	if tTrunc {
		consider(true, transactions[len(transactions)-1].ChangeSeq)
	}
	if sTrunc {
		consider(true, sales[len(sales)-1].ChangeSeq)
	}
	if rTrunc {
		consider(true, requests[len(requests)-1].ChangeSeq)
	}
	if supTrunc {
		consider(true, suppliers[len(suppliers)-1].ChangeSeq)
	}
	if stTrunc {
		consider(true, supplierTxs[len(supplierTxs)-1].ChangeSeq)
	}

	if hasMore {
		customers = trimTo(customers, boundary, func(c domain.Customer) int64 { return c.ChangeSeq })
		transactions = trimTo(transactions, boundary, func(t domain.Transaction) int64 { return t.ChangeSeq })
		sales = trimTo(sales, boundary, func(s domain.Sale) int64 { return s.ChangeSeq })
		requests = trimTo(requests, boundary, func(r domain.StockRequest) int64 { return r.ChangeSeq })
		suppliers = trimTo(suppliers, boundary, func(s domain.Supplier) int64 { return s.ChangeSeq })
		supplierTxs = trimTo(supplierTxs, boundary, func(t domain.SupplierTransaction) int64 { return t.ChangeSeq })
	}

	view := &PullView{
		Customers:     make([]SyncCustomer, 0, len(customers)),
		Transactions:  make([]SyncTransaction, 0, len(transactions)),
		Sales:         make([]SyncSale, 0, len(sales)),
		StockRequests: make([]SyncStockRequest, 0, len(requests)),
		Suppliers:     make([]SyncSupplier, 0, len(suppliers)),

		SupplierTransactions: make([]SyncSupplierTransaction, 0, len(supplierTxs)),

		NextCursor: cursor,
		HasMore:    hasMore,
		ServerTime: time.Now().UTC(),
	}
	advance := func(seq int64) {
		if seq > view.NextCursor {
			view.NextCursor = seq
		}
	}
	for _, c := range customers {
		view.Customers = append(view.Customers, customerView(c))
		advance(c.ChangeSeq)
	}
	for _, t := range transactions {
		view.Transactions = append(view.Transactions, transactionView(t))
		advance(t.ChangeSeq)
	}
	for _, sl := range sales {
		view.Sales = append(view.Sales, saleView(sl))
		advance(sl.ChangeSeq)
	}
	for _, rq := range requests {
		view.StockRequests = append(view.StockRequests, stockRequestView(rq))
		advance(rq.ChangeSeq)
	}
	for _, sp := range suppliers {
		view.Suppliers = append(view.Suppliers, supplierView(sp))
		advance(sp.ChangeSeq)
	}
	for _, st := range supplierTxs {
		view.SupplierTransactions = append(view.SupplierTransactions, supplierTransactionView(st))
		advance(st.ChangeSeq)
	}
	return view, nil
}

// capAt shortens a lookahead fetch to the page size and reports whether it had
// to — which is what says this table has more beyond the page.
func capAt[T any](rows []T, limit int) ([]T, bool) {
	if len(rows) > limit {
		return rows[:limit], true
	}
	return rows, false
}

// fetchAfter reads one table's changes above a cursor.
//
// business_id is stated even though the tenant callbacks would add it. This is a
// sync query: if it is ever wrong it hands one shop's ledger to another shop's
// phone, permanently, because the client writes what it receives straight into
// its own database. Worth the redundancy.
func fetchAfter[T any](ctx context.Context, db *gorm.DB, businessID uuid.UUID, cursor int64, limit int) ([]T, error) {
	var rows []T
	err := db.WithContext(ctx).
		Where("business_id = ? AND change_seq > ?", businessID, cursor).
		Order("change_seq").
		Limit(limit).
		Find(&rows).Error
	return rows, err
}

// trimTo drops everything above the boundary. The rows are already ordered by
// sequence, so the first one over it ends the page.
func trimTo[T any](rows []T, boundary int64, seq func(T) int64) []T {
	for i, row := range rows {
		if seq(row) > boundary {
			return rows[:i]
		}
	}
	return rows
}

func (r *Repository) horizon(ctx context.Context) (int64, error) {
	var h domain.TombstoneHorizon
	err := r.db.WithContext(ctx).First(&h).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		// Nothing has been collected, so no cursor can be too old. Treated as
		// zero rather than as an error: a missing horizon row must not stop
		// every device in the field from syncing.
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("reading the tombstone horizon: %w", err)
	}
	return h.ChangeSeq, nil
}

// --- Push ---

// pushWork is what the service asks the repository to apply, once it has decided.
type pushWork func(tx *gorm.DB) (*PushView, error)

// Push runs one push attempt under the guarantees the engine promises.
//
// Three things happen here that the merge rules do not care about but the
// correctness of the whole depends on:
//
//  1. A per-business advisory lock, held for the transaction. change_seq values
//     are allocated when a row is written but become visible at commit, so two
//     overlapping pushes can commit in the opposite order to their allocation —
//     leaving a lower sequence value appearing after a cursor has already passed
//     a higher one, which loses it. The lock makes allocation order and commit
//     order agree. Scoped to one business, so unrelated shops never contend.
//
//  2. The operation is claimed before any work. A duplicate arriving while the
//     first is still running blocks on the lock above, then finds the claim and
//     replays instead of applying the batch a second time.
//
//  3. The whole outcome is stored, not a flag. A retry is answered with exactly
//     what the first attempt returned, conflict reports included, so a client
//     cannot see a batch succeed and then see it report differently.
func (r *Repository) Push(ctx context.Context, operationID uuid.UUID, work pushWork) (*PushView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	var out *PushView
	err = r.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Exec(`SELECT pg_advisory_xact_lock(hashtext(?)::bigint)`, businessID.String()).Error; err != nil {
			return fmt.Errorf("acquiring the sync lock: %w", err)
		}

		claimed, stored, err := claimOperation(ctx, tx, businessID, operationID)
		if err != nil {
			return err
		}
		if !claimed {
			stored.Replayed = true
			// Timestamped now rather than replayed from the record: a client
			// uses this to judge its own clock, and the answer to "what time is
			// it" should not be an hour old because the first attempt was.
			stored.ServerTime = time.Now().UTC()
			out = stored
			return nil
		}

		result, err := work(tx)
		if err != nil {
			return err
		}

		// Recorded in the same transaction as the work. A crash between the two
		// would otherwise leave a batch applied and unclaimed, and the retry
		// would apply it again — which is the entire failure this exists to
		// prevent.
		encoded, err := json.Marshal(result)
		if err != nil {
			return fmt.Errorf("recording the push outcome: %w", err)
		}
		if err := tx.Model(&domain.SyncOperation{}).
			Where("business_id = ? AND operation_id = ?", businessID, operationID).
			Update("result", encoded).Error; err != nil {
			return fmt.Errorf("recording the push outcome: %w", err)
		}

		out = result
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// claimOperation reserves an operation id, or returns what it produced before.
func claimOperation(ctx context.Context, tx *gorm.DB, businessID, operationID uuid.UUID) (claimed bool, stored *PushView, err error) {
	op := domain.SyncOperation{
		BusinessID: businessID, OperationID: operationID,
		Result: []byte("null"), CreatedAt: time.Now().UTC(),
	}

	res := tx.WithContext(ctx).Clauses(clause.OnConflict{DoNothing: true}).Create(&op)
	if res.Error != nil {
		return false, nil, fmt.Errorf("claiming the operation: %w", res.Error)
	}
	if res.RowsAffected == 1 {
		return true, nil, nil
	}

	var existing domain.SyncOperation
	if err := tx.WithContext(ctx).
		Where("business_id = ? AND operation_id = ?", businessID, operationID).
		First(&existing).Error; err != nil {
		return false, nil, fmt.Errorf("reading the recorded outcome: %w", err)
	}

	var view PushView
	if err := json.Unmarshal(existing.Result, &view); err != nil {
		return false, nil, fmt.Errorf("decoding the recorded outcome: %w", err)
	}
	return false, &view, nil
}

// --- Statements used while applying a push ---

// LoadCustomers reads the rows a batch touches, in one query.
//
// One query rather than one per record: a batch of 200 customers from a device
// that has been offline for a fortnight would otherwise be 200 round trips
// inside a transaction holding an exclusive lock on the business.
func LoadCustomers(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, ids []uuid.UUID) (map[uuid.UUID]domain.Customer, error) {
	found := map[uuid.UUID]domain.Customer{}
	if len(ids) == 0 {
		return found, nil
	}

	var rows []domain.Customer
	if err := tx.WithContext(ctx).
		Where("business_id = ? AND id IN ?", businessID, ids).
		Find(&rows).Error; err != nil {
		return nil, fmt.Errorf("loading customers: %w", err)
	}
	for _, c := range rows {
		found[c.ID] = c
	}
	return found, nil
}

func LoadTransactions(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, ids []uuid.UUID) (map[uuid.UUID]domain.Transaction, error) {
	found := map[uuid.UUID]domain.Transaction{}
	if len(ids) == 0 {
		return found, nil
	}

	var rows []domain.Transaction
	if err := tx.WithContext(ctx).
		Where("business_id = ? AND id IN ?", businessID, ids).
		Find(&rows).Error; err != nil {
		return nil, fmt.Errorf("loading transactions: %w", err)
	}
	for _, t := range rows {
		found[t.ID] = t
	}
	return found, nil
}

// InsertCustomer creates a customer a device made while offline.
//
// business_id comes from the caller's token, never from the payload. A device
// that sent someone else's business id would otherwise write into their shop.
func InsertCustomer(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, in SyncCustomer, at time.Time) error {
	stamp, err := domain.StampFieldVersions(append(slices.Clone(customerFields), "credit_limit"), at)
	if err != nil {
		return err
	}

	c := domain.Customer{
		ID: in.ID, BusinessID: businessID, Name: in.Name, Phone: in.Phone, Notes: in.Notes,
		CreatedBy: in.CreatedBy, CreatedAt: in.CreatedAt, IsDeleted: in.IsDeleted,
		CreditLimit: in.CreditLimit,
	}
	if err := json.Unmarshal(stamp, &c.FieldVersions); err != nil {
		return err
	}
	if err := tx.WithContext(ctx).Create(&c).Error; err != nil {
		return fmt.Errorf("inserting customer %s: %w", in.ID, err)
	}
	return nil
}

// UpdateCustomer applies the columns a merge decided on, and stamps their
// versions in the same statement.
func UpdateCustomer(ctx context.Context, tx *gorm.DB, businessID, id uuid.UUID, columns map[string]any, fields []string, at time.Time) error {
	if len(columns) == 0 {
		return nil
	}

	stamp, err := domain.StampFieldVersions(fields, at)
	if err != nil {
		return err
	}

	values := make(map[string]any, len(columns)+1)
	for k, v := range columns {
		values[k] = v
	}
	// jsonb concatenation, so a field this push did not touch keeps whatever
	// version another writer gave it. A read-modify-write in Go would drop the
	// other writer's key.
	values["field_versions"] = gorm.Expr("field_versions || ?::jsonb", stamp)

	if err := tx.WithContext(ctx).
		Model(&domain.Customer{}).
		Where("id = ? AND business_id = ?", id, businessID).
		Updates(values).Error; err != nil {
		return fmt.Errorf("updating customer %s: %w", id, err)
	}
	return nil
}

// VoidTransaction is the only change an existing entry accepts.
//
// Written through GORM's Model/Update so updated_at is stamped by the field-name
// convention rather than by hand. The v1 defect this replaces was a soft-delete
// that set is_deleted without touching updated_at, which put every voided entry
// outside the push window forever.
func VoidTransaction(ctx context.Context, tx *gorm.DB, businessID, id uuid.UUID) error {
	if err := tx.WithContext(ctx).
		Model(&domain.Transaction{}).
		Where("id = ? AND business_id = ?", id, businessID).
		Update("is_deleted", true).Error; err != nil {
		return fmt.Errorf("voiding transaction %s: %w", id, err)
	}
	return nil
}

// CustomerIDsIn reports which of the given customers exist for this business and
// are not deleted — used to refuse ledger entries pointing at a customer this
// shop does not have.
func CustomerIDsIn(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, ids []uuid.UUID) (map[uuid.UUID]bool, error) {
	present := map[uuid.UUID]bool{}
	if len(ids) == 0 {
		return present, nil
	}

	var found []uuid.UUID
	if err := tx.WithContext(ctx).
		Model(&domain.Customer{}).
		Where("business_id = ? AND id IN ?", businessID, ids).
		Pluck("id", &found).Error; err != nil {
		return nil, fmt.Errorf("checking customers: %w", err)
	}
	for _, id := range found {
		present[id] = true
	}
	return present, nil
}

// --- Views ---

func customerView(c domain.Customer) SyncCustomer {
	return SyncCustomer{
		ID: c.ID, Name: c.Name, Phone: c.Phone, Notes: c.Notes,
		CreatedBy: c.CreatedBy, CreatedAt: c.CreatedAt, UpdatedAt: c.UpdatedAt,
		IsDeleted: c.IsDeleted, CreditLimit: c.CreditLimit,
	}
}

func transactionView(t domain.Transaction) SyncTransaction {
	return SyncTransaction{
		ID: t.ID, CustomerID: t.CustomerID, UserID: t.UserID, Type: t.Type,
		Amount: t.Amount, Description: t.Description, TransactionDate: t.TransactionDate,
		CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt, IsDeleted: t.IsDeleted,
		SaleID: t.SaleID, PaymentMethod: t.PaymentMethod, Reference: t.Reference, DueDate: t.DueDate,
	}
}

func saleView(s domain.Sale) SyncSale {
	return SyncSale{
		ID: s.ID, CustomerID: s.CustomerID, UserID: s.UserID, ProductName: s.ProductName,
		Quantity: s.Quantity, Amount: s.Amount, PaymentMethod: s.PaymentMethod, Notes: s.Notes,
		SaleDate: s.SaleDate, Reference: s.Reference, DueDate: s.DueDate,
		CreatedAt: s.CreatedAt, UpdatedAt: s.UpdatedAt, IsDeleted: s.IsDeleted,
	}
}

func stockRequestView(r domain.StockRequest) SyncStockRequest {
	return SyncStockRequest{
		ID: r.ID, UserID: r.UserID, ProductName: r.ProductName, NeededOn: r.NeededOn,
		Notes: r.Notes, PurchaseOrderID: r.PurchaseOrderID,
		CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, IsDeleted: r.IsDeleted,
	}
}

func supplierView(s domain.Supplier) SyncSupplier {
	return SyncSupplier{
		ID: s.ID, Name: s.Name, Phone: s.Phone, Notes: s.Notes, CreatedBy: s.CreatedBy,
		CreatedAt: s.CreatedAt, UpdatedAt: s.UpdatedAt, IsDeleted: s.IsDeleted,
	}
}

func supplierTransactionView(t domain.SupplierTransaction) SyncSupplierTransaction {
	return SyncSupplierTransaction{
		ID: t.ID, SupplierID: t.SupplierID, UserID: t.UserID, Type: t.Type, Amount: t.Amount,
		Description: t.Description, TransactionDate: t.TransactionDate, DueDate: t.DueDate,
		PaymentMethod: t.PaymentMethod, Reference: t.Reference, PurchaseOrderID: t.PurchaseOrderID,
		CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt, IsDeleted: t.IsDeleted,
	}
}

// CanReadSuppliers reports whether a user may receive supplier records.
func (r *Repository) CanReadSuppliers(ctx context.Context, userID uuid.UUID) (bool, error) {
	return authz.NewEvaluator(r.db).UserHasPermission(ctx, userID, rbac.PermSuppliersRead)
}
