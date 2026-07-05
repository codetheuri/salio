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

// SyncRepository handles the core offline-first synchronization logic.
// It supports pushing local changes to the server and pulling remote changes.
type SyncRepository struct {
	db *pgxpool.Pool
}

// NewSyncRepository creates a new SyncRepository.
func NewSyncRepository(db *pgxpool.Pool) *SyncRepository {
	return &SyncRepository{db: db}
}

// Pull retrieves all customers and transactions for a business that have been
// updated AFTER the provided `lastSync` timestamp.
func (r *SyncRepository) Pull(ctx context.Context, businessID uuid.UUID, lastSync time.Time) (*models.SyncPayload, error) {
	payload := &models.SyncPayload{
		Customers:    []models.Customer{},
		Transactions: []models.Transaction{},
		ServerTime:   time.Now().UTC(),
	}

	// 1. Pull Customers
	custRows, err := r.db.Query(ctx,
		`SELECT id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted
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
		if err := custRows.Scan(&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes, &c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted); err != nil {
			return nil, fmt.Errorf("failed to scan customer: %w", err)
		}
		payload.Customers = append(payload.Customers, c)
	}

	// 2. Pull Transactions
	// Uses updated_at to ensure soft-deletes (voids) are synced down to the mobile app.
	txRows, err := r.db.Query(ctx,
		`SELECT id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted
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
		if err := txRows.Scan(&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type, &t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted); err != nil {
			return nil, fmt.Errorf("failed to scan transaction: %w", err)
		}
		payload.Transactions = append(payload.Transactions, t)
	}

	return payload, nil
}

// Push processes an incoming payload from the mobile app.
// It uses "Upsert" (Insert on conflict Update) with a Last-Write-Wins strategy.
func (r *SyncRepository) Push(ctx context.Context, businessID uuid.UUID, payload models.SyncPayload) error {
	// Start a transaction so either everything syncs or nothing does
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	// 1. Upsert Customers
	// We use the Server's authoritative clock (NOW()) for updated_at so that subsequent Pulls
	// from other devices correctly detect the change, regardless of device clock drift.
	customerSQL := `
		INSERT INTO customers (id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted)
		VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), $9)
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
			c.ID, businessID, c.Name, c.Phone, c.Notes, c.CreatedBy, c.CreatedAt, c.UpdatedAt, c.IsDeleted,
		)
		if err != nil {
			return fmt.Errorf("failed to upsert customer %s: %w", c.ID, err)
		}
	}

	// 2. Upsert Transactions
	transactionSQL := `
		INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW(), $11)
		ON CONFLICT (id) DO UPDATE SET
			is_deleted = EXCLUDED.is_deleted,
			updated_at = NOW()
		WHERE transactions.business_id = EXCLUDED.business_id
	`
	for _, t := range payload.Transactions {
		_, err := tx.Exec(ctx, transactionSQL,
			t.ID, businessID, t.CustomerID, t.UserID, t.Type, t.Amount, t.Description, t.TransactionDate, t.CreatedAt, t.UpdatedAt, t.IsDeleted,
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
