package syncengine

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
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
func (r *Repository) Pull(ctx context.Context, cursor int64, limit int) (*PullView, error) {
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

	custTruncated := len(customers) > limit
	txTruncated := len(transactions) > limit
	if custTruncated {
		customers = customers[:limit]
	}
	if txTruncated {
		transactions = transactions[:limit]
	}

	// Both tables draw from one sequence, so their pages interleave. When either
	// is truncated the cursor may advance only to a point *both* have covered.
	//
	// Say customers fill their page up to seq 900 while transactions are
	// exhausted at 480. Advancing to 900 would lose every transaction between
	// 481 and 900 that arrives later — the next pull would ask for > 900 and
	// never look below it again. So the page is cut back to the lower boundary
	// and the rest comes on the following page.
	boundary := int64(-1)
	if custTruncated {
		boundary = customers[len(customers)-1].ChangeSeq
	}
	if txTruncated {
		if last := transactions[len(transactions)-1].ChangeSeq; boundary < 0 || last < boundary {
			boundary = last
		}
	}

	hasMore := custTruncated || txTruncated
	if hasMore {
		customers = trimTo(customers, boundary, func(c domain.Customer) int64 { return c.ChangeSeq })
		transactions = trimTo(transactions, boundary, func(t domain.Transaction) int64 { return t.ChangeSeq })
	}

	view := &PullView{
		Customers:    make([]SyncCustomer, 0, len(customers)),
		Transactions: make([]SyncTransaction, 0, len(transactions)),
		NextCursor:   cursor,
		HasMore:      hasMore,
		ServerTime:   time.Now().UTC(),
	}
	for _, c := range customers {
		view.Customers = append(view.Customers, customerView(c))
		if c.ChangeSeq > view.NextCursor {
			view.NextCursor = c.ChangeSeq
		}
	}
	for _, t := range transactions {
		view.Transactions = append(view.Transactions, transactionView(t))
		if t.ChangeSeq > view.NextCursor {
			view.NextCursor = t.ChangeSeq
		}
	}
	return view, nil
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
	stamp, err := domain.StampFieldVersions(customerFields, at)
	if err != nil {
		return err
	}

	c := domain.Customer{
		ID: in.ID, BusinessID: businessID, Name: in.Name, Phone: in.Phone, Notes: in.Notes,
		CreatedBy: in.CreatedBy, CreatedAt: in.CreatedAt, IsDeleted: in.IsDeleted,
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

// InsertTransaction records a ledger entry made offline.
func InsertTransaction(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, in SyncTransaction) error {
	t := domain.Transaction{
		ID: in.ID, BusinessID: businessID, CustomerID: in.CustomerID, UserID: in.UserID,
		Type: in.Type, Amount: in.Amount, Description: in.Description,
		TransactionDate: in.TransactionDate, CreatedAt: in.CreatedAt, IsDeleted: in.IsDeleted,
	}
	if err := tx.WithContext(ctx).Create(&t).Error; err != nil {
		return fmt.Errorf("inserting transaction %s: %w", in.ID, err)
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
		IsDeleted: c.IsDeleted,
	}
}

func transactionView(t domain.Transaction) SyncTransaction {
	return SyncTransaction{
		ID: t.ID, CustomerID: t.CustomerID, UserID: t.UserID, Type: t.Type,
		Amount: t.Amount, Description: t.Description, TransactionDate: t.TransactionDate,
		CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt, IsDeleted: t.IsDeleted,
	}
}
