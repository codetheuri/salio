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

// UserRepository handles profile management, business updates, and staff operations.
// Auth operations (login, register, invite) live in AuthRepository.
// This separation keeps each repository focused on one domain.
type UserRepository struct {
	db *pgxpool.Pool
}

// NewUserRepository creates a new UserRepository.
func NewUserRepository(db *pgxpool.Pool) *UserRepository {
	return &UserRepository{db: db}
}

// GetUserByID fetches a single user by their ID.
// Used by /v1/users/me to return the authenticated user's profile.
func (r *UserRepository) GetUserByID(ctx context.Context, userID uuid.UUID) (*models.User, error) {
	var u models.User
	err := r.db.QueryRow(ctx,
		`SELECT id, business_id, name, phone, role, created_at, updated_at
		 FROM users
		 WHERE id = $1 AND is_active = TRUE`,
		userID,
	).Scan(&u.ID, &u.BusinessID, &u.Name, &u.Phone, &u.Role, &u.CreatedAt, &u.UpdatedAt)

	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get user by id: %w", err)
	}
	return &u, nil
}

// GetBusiness fetches the Business record for a given business ID.
// Used by /v1/users/me to return both user + business data in one response.
func (r *UserRepository) GetBusiness(ctx context.Context, businessID uuid.UUID) (*models.Business, error) {
	var b models.Business
	err := r.db.QueryRow(ctx,
		`SELECT id, name, type, created_at, updated_at
		 FROM businesses
		 WHERE id = $1`,
		businessID,
	).Scan(&b.ID, &b.Name, &b.Type, &b.CreatedAt, &b.UpdatedAt)

	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to get business: %w", err)
	}
	return &b, nil
}

// UpdateUserInput holds fields the user can update on their own profile.
type UpdateUserInput struct {
	Name string
}

// UpdateUser updates the authenticated user's own profile.
func (r *UserRepository) UpdateUser(ctx context.Context, userID uuid.UUID, input UpdateUserInput) (*models.User, error) {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		`UPDATE users SET name = $1, updated_at = $2 WHERE id = $3`,
		input.Name, now, userID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to update user: %w", err)
	}
	return r.GetUserByID(ctx, userID)
}

// UpdateBusinessInput holds fields the owner can change about the Business.
type UpdateBusinessInput struct {
	Name string
	Type *string
}

// UpdateBusiness updates the Business name and type. Only owners should call this.
// Role enforcement is done at the handler layer via RequireRole("owner").
func (r *UserRepository) UpdateBusiness(ctx context.Context, businessID uuid.UUID, input UpdateBusinessInput) (*models.Business, error) {
	now := time.Now().UTC()
	_, err := r.db.Exec(ctx,
		`UPDATE businesses SET name = $1, type = $2, updated_at = $3 WHERE id = $4`,
		input.Name, input.Type, now, businessID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to update business: %w", err)
	}
	return r.GetBusiness(ctx, businessID)
}

// ListStaff returns all active users belonging to a business.
// Used by the owner to see their team in the Settings screen.
func (r *UserRepository) ListStaff(ctx context.Context, businessID uuid.UUID) ([]models.User, error) {
	rows, err := r.db.Query(ctx,
		`SELECT id, business_id, name, phone, role, created_at, updated_at
		 FROM users
		 WHERE business_id = $1 AND is_active = TRUE
		 ORDER BY role DESC, name ASC`, // owners first, then staff alphabetically
		businessID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to list staff: %w", err)
	}
	defer rows.Close()

	var users []models.User
	for rows.Next() {
		var u models.User
		if err := rows.Scan(&u.ID, &u.BusinessID, &u.Name, &u.Phone, &u.Role, &u.CreatedAt, &u.UpdatedAt); err != nil {
			return nil, fmt.Errorf("failed to scan user row: %w", err)
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating user rows: %w", err)
	}
	return users, nil
}

// DeactivateStaff sets is_active = FALSE for a staff member.
// This prevents them from logging in again without deleting their data.
// Business rule: an owner cannot deactivate themselves.
func (r *UserRepository) DeactivateStaff(ctx context.Context, businessID, targetUserID uuid.UUID) error {
	result, err := r.db.Exec(ctx,
		`UPDATE users SET is_active = FALSE, updated_at = NOW()
		 WHERE id = $1 AND business_id = $2 AND role = 'staff'`,
		targetUserID, businessID,
	)
	if err != nil {
		return fmt.Errorf("failed to deactivate staff: %w", err)
	}
	// If 0 rows affected: either the user doesn't exist, belongs to another business,
	// or is an owner (protected by the role = 'staff' clause).
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
