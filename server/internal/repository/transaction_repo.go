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

// TransactionRepository handles all DB operations for the transactions table.
// Transactions are append-only and immutable — we never UPDATE an amount.
// Mistakes are corrected by adding a new offsetting transaction.
type TransactionRepository struct {
	db *pgxpool.Pool
}

// NewTransactionRepository creates a new TransactionRepository.
func NewTransactionRepository(db *pgxpool.Pool) *TransactionRepository {
	return &TransactionRepository{db: db}
}

// ListForCustomer returns all active transactions for a specific customer,
// ordered newest-first. The business_id check enforces multi-tenancy.
func (r *TransactionRepository) ListForCustomer(ctx context.Context, businessID, customerID uuid.UUID) ([]models.Transaction, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted
		 FROM transactions
		 WHERE customer_id = $1 AND business_id = $2 AND is_deleted = FALSE
		 ORDER BY transaction_date DESC, created_at DESC`,
		customerID, businessID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to list transactions: %w", err)
	}
	defer rows.Close()

	var transactions []models.Transaction
	for rows.Next() {
		var t models.Transaction
		if err := rows.Scan(
			&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type,
			&t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted,
		); err != nil {
			return nil, fmt.Errorf("failed to scan transaction row: %w", err)
		}
		transactions = append(transactions, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating transaction rows: %w", err)
	}

	return transactions, nil
}

// CreateTransactionInput holds the validated data for recording a new debt or payment.
type CreateTransactionInput struct {
	BusinessID      uuid.UUID
	CustomerID      uuid.UUID
	UserID          uuid.UUID // The staff member recording this (from JWT)
	Type            models.TransactionType
	Amount          float64
	Description     *string
	TransactionDate time.Time
}

// Create inserts a new transaction. This is an append-only operation.
// The customer's balance is always derived from the sum of transactions
// and is NEVER stored directly — this prevents sync conflicts.
func (r *TransactionRepository) Create(ctx context.Context, input CreateTransactionInput) (*models.Transaction, error) {
	id := uuid.New()
	now := time.Now().UTC()

	_, err := r.db.Exec(ctx,
		`INSERT INTO transactions (id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
		id, input.BusinessID, input.CustomerID, input.UserID,
		input.Type, input.Amount, input.Description, input.TransactionDate.Format("2006-01-02"), now, now,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create transaction: %w", err)
	}

	return &models.Transaction{
		ID:              id,
		BusinessID:      input.BusinessID,
		CustomerID:      input.CustomerID,
		UserID:          input.UserID,
		Type:            input.Type,
		Amount:          input.Amount,
		Description:     input.Description,
		TransactionDate: input.TransactionDate,
		CreatedAt:       now,
		UpdatedAt:       now,
	}, nil
}

// GetByID fetches a single transaction, scoped to the business.
func (r *TransactionRepository) GetByID(ctx context.Context, businessID, transactionID uuid.UUID) (*models.Transaction, error) {
	var t models.Transaction
	err := r.db.QueryRow(ctx,
		`SELECT id, business_id, customer_id, user_id, type, amount, description, transaction_date, created_at, updated_at, is_deleted
		 FROM transactions
		 WHERE id = $1 AND business_id = $2`,
		transactionID, businessID,
	).Scan(&t.ID, &t.BusinessID, &t.CustomerID, &t.UserID, &t.Type,
		&t.Amount, &t.Description, &t.TransactionDate, &t.CreatedAt, &t.UpdatedAt, &t.IsDeleted)

	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get transaction by id: %w", err)
	}
	return &t, nil
}

// SoftDelete marks a transaction as deleted. Only an owner should be able to do this.
// The handler layer enforces the role check via middleware.RequireRole("owner").
func (r *TransactionRepository) SoftDelete(ctx context.Context, businessID, transactionID uuid.UUID) error {
	result, err := r.db.Exec(ctx,
		`UPDATE transactions SET is_deleted = TRUE, updated_at = NOW()
		 WHERE id = $1 AND business_id = $2`,
		transactionID, businessID,
	)
	if err != nil {
		return fmt.Errorf("failed to soft delete transaction: %w", err)
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
