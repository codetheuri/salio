package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"salio/server/internal/models"
)

// DefaultPullLimit caps how many rows of each kind a single pull returns.
//
// Before cursors existed, a pull returned every row a business had ever created
// in one response. That is survivable for a new shop and not for an established
// one on a slow connection, and there was no way to resume a failed attempt.
const DefaultPullLimit = 500

// MaxPullLimit bounds what a client may request.
const MaxPullLimit = 2000

// SyncRepository handles the core offline-first synchronization logic.
type SyncRepository struct {
	db *pgxpool.Pool
}

// NewSyncRepository creates a new SyncRepository.
func NewSyncRepository(db *pgxpool.Pool) *SyncRepository {
	return &SyncRepository{db: db}
}

const customerColumns = `id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted, change_seq`
const transactionColumns = `id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted, change_seq`

// seqRow pairs a decoded record with the sequence value that ordered it.
type customerRow struct {
	customer models.Customer
	seq      int64
}

type transactionRow struct {
	transaction models.Transaction
	seq         int64
}

// PullByCursor returns changes after the supplied cursor, in sequence order.
//
// The cursor is a server-issued sequence value, not a timestamp. That difference
// is the entire fix: a client advances its cursor only as far as the highest
// value actually delivered to it, so it can never step over a row it has not
// seen. A wall-clock watermark could — and did — advance past rows belonging to
// a transaction that had started but not yet committed, hiding them forever.
func (r *SyncRepository) PullByCursor(ctx context.Context, businessID uuid.UUID, cursor int64, limit int) (*models.SyncPayload, error) {
	if limit <= 0 {
		limit = DefaultPullLimit
	}
	if limit > MaxPullLimit {
		limit = MaxPullLimit
	}

	// Fetch one row beyond the limit as a lookahead: its presence is what tells
	// us more remains, without needing a second COUNT query.
	custRows, err := r.fetchCustomers(ctx, businessID, cursor, limit+1)
	if err != nil {
		return nil, err
	}
	txRows, err := r.fetchTransactions(ctx, businessID, cursor, limit+1)
	if err != nil {
		return nil, err
	}

	custTruncated := len(custRows) > limit
	txTruncated := len(txRows) > limit
	if custTruncated {
		custRows = custRows[:limit]
	}
	if txTruncated {
		txRows = txRows[:limit]
	}

	// Both tables draw from one sequence, so the two result sets interleave. If
	// either was truncated, the cursor may only advance to a point both sets have
	// covered — otherwise the next pull would ask for rows above a boundary that
	// the other table never reached, and everything between would be skipped.
	//
	// Example: customers deliver up to seq 900 (truncated), transactions only to
	// 480 (exhausted). Advancing to 900 would lose every transaction in 481..900.
	boundary := int64(-1)
	if custTruncated {
		boundary = custRows[len(custRows)-1].seq
	}
	if txTruncated {
		last := txRows[len(txRows)-1].seq
		if boundary < 0 || last < boundary {
			boundary = last
		}
	}

	hasMore := custTruncated || txTruncated
	if hasMore {
		custRows = trimCustomersTo(custRows, boundary)
		txRows = trimTransactionsTo(txRows, boundary)
	}

	payload := &models.SyncPayload{
		Customers:    make([]models.Customer, 0, len(custRows)),
		Transactions: make([]models.Transaction, 0, len(txRows)),
		ServerTime:   time.Now().UTC(),
		NextCursor:   cursor,
		HasMore:      hasMore,
	}

	for _, row := range custRows {
		payload.Customers = append(payload.Customers, row.customer)
		if row.seq > payload.NextCursor {
			payload.NextCursor = row.seq
		}
	}
	for _, row := range txRows {
		payload.Transactions = append(payload.Transactions, row.transaction)
		if row.seq > payload.NextCursor {
			payload.NextCursor = row.seq
		}
	}

	return payload, nil
}

// Pull is the legacy timestamp-based path, retained so app versions already in
// the field keep working through the rollout.
//
// It carries the defect described in migration 006 and must not be used by new
// clients. It is deliberately left byte-for-byte compatible — including its lack
// of pagination — so that upgrading the server changes nothing for an old app.
func (r *SyncRepository) Pull(ctx context.Context, businessID uuid.UUID, lastSync time.Time) (*models.SyncPayload, error) {
	payload := &models.SyncPayload{
		Customers:    []models.Customer{},
		Transactions: []models.Transaction{},
		ServerTime:   time.Now().UTC(),
	}

	custRows, err := r.db.Query(ctx,
		`SELECT `+customerColumns+`
		 FROM customers
		 WHERE business_id = $1 AND updated_at > $2`,
		businessID, lastSync,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to pull customers: %w", err)
	}
	defer custRows.Close()

	for custRows.Next() {
		var c models.Customer
		var seq int64
		if err := custRows.Scan(&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes, &c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted, &seq); err != nil {
			return nil, fmt.Errorf("failed to scan customer: %w", err)
		}
		payload.Customers = append(payload.Customers, c)
		if seq > payload.NextCursor {
			payload.NextCursor = seq
		}
	}
	if err := custRows.Err(); err != nil {
		return nil, fmt.Errorf("failed to read customers: %w", err)
	}

	txRows, err := r.db.Query(ctx,
		`SELECT `+transactionColumns+`
		 FROM transactions
		 WHERE business_id = $1 AND updated_at > $2`,
		businessID, lastSync,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to pull transactions: %w", err)
	}
	defer txRows.Close()

	for txRows.Next() {
		var t models.Transaction
		var seq int64
		if err := txRows.Scan(&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type, &t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted, &seq); err != nil {
			return nil, fmt.Errorf("failed to scan transaction: %w", err)
		}
		payload.Transactions = append(payload.Transactions, t)
		if seq > payload.NextCursor {
			payload.NextCursor = seq
		}
	}
	if err := txRows.Err(); err != nil {
		return nil, fmt.Errorf("failed to read transactions: %w", err)
	}

	return payload, nil
}

func (r *SyncRepository) fetchCustomers(ctx context.Context, businessID uuid.UUID, cursor int64, limit int) ([]customerRow, error) {
	rows, err := r.db.Query(ctx,
		`SELECT `+customerColumns+`
		 FROM customers
		 WHERE business_id = $1 AND change_seq > $2
		 ORDER BY change_seq
		 LIMIT $3`,
		businessID, cursor, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to pull customers: %w", err)
	}
	defer rows.Close()

	var out []customerRow
	for rows.Next() {
		var row customerRow
		c := &row.customer
		if err := rows.Scan(&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes, &c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted, &row.seq); err != nil {
			return nil, fmt.Errorf("failed to scan customer: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func (r *SyncRepository) fetchTransactions(ctx context.Context, businessID uuid.UUID, cursor int64, limit int) ([]transactionRow, error) {
	rows, err := r.db.Query(ctx,
		`SELECT `+transactionColumns+`
		 FROM transactions
		 WHERE business_id = $1 AND change_seq > $2
		 ORDER BY change_seq
		 LIMIT $3`,
		businessID, cursor, limit,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to pull transactions: %w", err)
	}
	defer rows.Close()

	var out []transactionRow
	for rows.Next() {
		var row transactionRow
		t := &row.transaction
		if err := rows.Scan(&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type, &t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted, &row.seq); err != nil {
			return nil, fmt.Errorf("failed to scan transaction: %w", err)
		}
		out = append(out, row)
	}
	return out, rows.Err()
}

func trimCustomersTo(rows []customerRow, boundary int64) []customerRow {
	for i, row := range rows {
		if row.seq > boundary {
			return rows[:i]
		}
	}
	return rows
}

func trimTransactionsTo(rows []transactionRow, boundary int64) []transactionRow {
	for i, row := range rows {
		if row.seq > boundary {
			return rows[:i]
		}
	}
	return rows
}

// Push processes an incoming payload from the mobile app, upserting with a
// Last-Write-Wins strategy.
func (r *SyncRepository) Push(ctx context.Context, businessID uuid.UUID, payload models.SyncPayload) error {
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// Serialise pushes for this business.
	//
	// change_seq values are allocated when a row is written, but rows become
	// visible only at commit. Two overlapping pushes can therefore commit in the
	// opposite order to their allocation, leaving a lower sequence value
	// appearing *after* a higher one has already been delivered — and a cursor
	// that has passed the higher value would never come back for it.
	//
	// The lock removes that window by making allocation order and commit order
	// agree. It is scoped to one business and released automatically at commit,
	// so unrelated shops never contend, and a shop with four staff will not
	// notice it.
	if _, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext($1::text)::bigint)`, businessID.String()); err != nil {
		return fmt.Errorf("failed to acquire sync lock: %w", err)
	}

	// change_seq is assigned by a database trigger on every insert and update, so
	// it is deliberately absent here — no write path can forget to advance it.
	customerSQL := `
		INSERT INTO customers (id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $8)
		ON CONFLICT (id) DO UPDATE SET
			name = EXCLUDED.name,
			phone = EXCLUDED.phone,
			notes = EXCLUDED.notes,
			updated_at = NOW(),
			is_deleted = EXCLUDED.is_deleted
		WHERE customers.business_id = EXCLUDED.business_id
	`
	for _, c := range payload.Customers {
		_, err := tx.Exec(ctx, customerSQL,
			c.ID, businessID, c.Name, c.Phone, c.Notes, c.CreatedBy, c.CreatedAt, c.IsDeleted,
		)
		if err != nil {
			return fmt.Errorf("failed to upsert customer %s: %w", c.ID, err)
		}
	}

	transactionSQL := `
		INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), $10)
		ON CONFLICT (id) DO UPDATE SET
			is_deleted = EXCLUDED.is_deleted,
			updated_at = NOW()
		WHERE transactions.business_id = EXCLUDED.business_id
	`
	for _, t := range payload.Transactions {
		_, err := tx.Exec(ctx, transactionSQL,
			t.ID, businessID, t.CustomerID, t.UserID, t.Type, t.Amount, t.Description, t.TransactionDate, t.CreatedAt, t.IsDeleted,
		)
		if err != nil {
			return fmt.Errorf("failed to upsert transaction %s: %w", t.ID, err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("failed to commit sync transaction: %w", err)
	}

	return nil
}
