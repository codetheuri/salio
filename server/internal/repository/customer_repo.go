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

// CustomerRepository handles all database operations for the customers table.
// Every method MUST scope its query to a business_id — this is what enforces
// multi-tenancy. A user from Business A can never read or write Business B's customers.
type CustomerRepository struct {
	db *pgxpool.Pool
}

// NewCustomerRepository creates a new CustomerRepository.
func NewCustomerRepository(db *pgxpool.Pool) *CustomerRepository {
	return &CustomerRepository{db: db}
}

// List returns all active customers for a given business.
// If search is non-empty, filters by customer name (case-insensitive).
func (r *CustomerRepository) List(ctx context.Context, businessID uuid.UUID, search string) ([]models.Customer, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted
		 FROM customers
		 WHERE business_id = $1 AND is_deleted = FALSE
		   AND ($2 = '' OR name ILIKE '%' || $2 || '%')
		 ORDER BY name ASC`,
		businessID, search,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to list customers: %w", err)
	}
	defer rows.Close()

	var customers []models.Customer
	for rows.Next() {
		var c models.Customer
		if err := rows.Scan(
			&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes,
			&c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted,
		); err != nil {
			return nil, fmt.Errorf("failed to scan customer row: %w", err)
		}
		customers = append(customers, c)
	}
	// rows.Err() catches errors that occurred during iteration
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating customer rows: %w", err)
	}

	return customers, nil
}

// GetByID fetches a single customer, ensuring it belongs to the given business.
func (r *CustomerRepository) GetByID(ctx context.Context, businessID, customerID uuid.UUID) (*models.Customer, error) {
	var c models.Customer
	err := r.db.QueryRow(ctx,
		`SELECT id, business_id, name, phone, notes, created_by, created_at, updated_at, is_deleted
		 FROM customers
		 WHERE id = $1 AND business_id = $2 AND is_deleted = FALSE`,
		customerID, businessID,
	).Scan(&c.ID, &c.BusinessID, &c.Name, &c.Phone, &c.Notes,
		&c.CreatedBy, &c.CreatedAt, &c.UpdatedAt, &c.IsDeleted)

	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get customer by id: %w", err)
	}
	return &c, nil
}

// CreateInput holds the validated data needed to create a new customer.
type CreateCustomerInput struct {
	BusinessID uuid.UUID
	CreatedBy  uuid.UUID // The user_id from the JWT token
	Name       string
	Phone      *string
	Notes      *string
}

// Create inserts a new customer into the database.
func (r *CustomerRepository) Create(ctx context.Context, input CreateCustomerInput) (*models.Customer, error) {
	id := uuid.New()
	now := time.Now().UTC()

	_, err := r.db.Exec(ctx,
		`INSERT INTO customers (id, business_id, name, phone, notes, created_by, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		id, input.BusinessID, input.Name, input.Phone, input.Notes, input.CreatedBy, now, now,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create customer: %w", err)
	}

	return &models.Customer{
		ID:         id,
		BusinessID: input.BusinessID,
		Name:       input.Name,
		Phone:      input.Phone,
		Notes:      input.Notes,
		CreatedBy:  input.CreatedBy,
		CreatedAt:  now,
		UpdatedAt:  now,
	}, nil
}

// UpdateInput holds the fields that can be changed on an existing customer.
type UpdateCustomerInput struct {
	Name  string
	Phone *string
	Notes *string
}

// Update modifies the name, phone, and notes of a customer.
// The business_id check ensures a user cannot modify another business's customer.
func (r *CustomerRepository) Update(ctx context.Context, businessID, customerID uuid.UUID, input UpdateCustomerInput) (*models.Customer, error) {
	now := time.Now().UTC()

	_, err := r.db.Exec(ctx,
		`UPDATE customers
		 SET name = $1, phone = $2, notes = $3, updated_at = $4
		 WHERE id = $5 AND business_id = $6 AND is_deleted = FALSE`,
		input.Name, input.Phone, input.Notes, now, customerID, businessID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to update customer: %w", err)
	}

	// Return the updated record by fetching it
	return r.GetByID(ctx, businessID, customerID)
}

// SoftDelete marks a customer as deleted without removing the row.
// This preserves transaction history and allows for sync/audit trails.
// Business rule: cannot delete if balance != 0 (enforced at the handler level).
func (r *CustomerRepository) SoftDelete(ctx context.Context, businessID, customerID uuid.UUID) error {
	result, err := r.db.Exec(ctx,
		`UPDATE customers SET is_deleted = TRUE, updated_at = NOW()
		 WHERE id = $1 AND business_id = $2 AND is_deleted = FALSE`,
		customerID, businessID,
	)
	if err != nil {
		return fmt.Errorf("failed to soft delete customer: %w", err)
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// GetBalance calculates the current outstanding balance for a customer.
// Balance = SUM(debt) - SUM(payment). We never store the balance — always calculate.
func (r *CustomerRepository) GetBalance(ctx context.Context, businessID, customerID uuid.UUID) (float64, error) {
	var balance float64
	err := r.db.QueryRow(ctx,
		`SELECT COALESCE(
			SUM(CASE WHEN type = 'debt'    THEN amount ELSE 0 END) -
			SUM(CASE WHEN type = 'payment' THEN amount ELSE 0 END),
		0)
		 FROM transactions
		 WHERE customer_id = $1 AND business_id = $2 AND is_deleted = FALSE`,
		customerID, businessID,
	).Scan(&balance)

	if err != nil {
		return 0, fmt.Errorf("failed to calculate customer balance: %w", err)
	}
	return balance, nil
}
