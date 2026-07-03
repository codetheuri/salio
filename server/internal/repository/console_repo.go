package repository

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"salio/server/internal/models"
)

// ConsoleRepository handles all database operations for the Salio admin console.
// It operates on super_admins and console_sessions, plus read-only queries
// across all business data for the dashboard summary.
type ConsoleRepository struct {
	db *pgxpool.Pool
}

// NewConsoleRepository creates a new ConsoleRepository.
func NewConsoleRepository(db *pgxpool.Pool) *ConsoleRepository {
	return &ConsoleRepository{db: db}
}

// --- Super Admin Auth ---

// CreateSuperAdmin creates the first (and usually only) super admin account.
// In production, this is called once via a CLI command or setup script — not via HTTP.
func (r *ConsoleRepository) CreateSuperAdmin(ctx context.Context, name, email, password string) (*models.SuperAdmin, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	admin := &models.SuperAdmin{}
	err = r.db.QueryRow(ctx,
		`INSERT INTO super_admins (name, email, password_hash, created_at, updated_at)
		 VALUES ($1, $2, $3, NOW(), NOW())
		 RETURNING id, name, email, created_at, updated_at`,
		name, email, string(hash),
	).Scan(&admin.ID, &admin.Name, &admin.Email, &admin.CreatedAt, &admin.UpdatedAt)
	if err != nil {
		if strings.Contains(err.Error(), "unique") {
			return nil, fmt.Errorf("email already registered")
		}
		return nil, fmt.Errorf("failed to create super admin: %w", err)
	}
	return admin, nil
}

// GetSuperAdminByEmail fetches a super admin by email for login.
func (r *ConsoleRepository) GetSuperAdminByEmail(ctx context.Context, email string) (*models.SuperAdmin, error) {
	admin := &models.SuperAdmin{}
	err := r.db.QueryRow(ctx,
		`SELECT id, name, email, password_hash, created_at, updated_at
		 FROM super_admins WHERE email = $1`,
		email,
	).Scan(&admin.ID, &admin.Name, &admin.Email, &admin.PasswordHash, &admin.CreatedAt, &admin.UpdatedAt)
	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query super admin: %w", err)
	}
	return admin, nil
}

// VerifySuperAdminPassword checks a plaintext password against the stored bcrypt hash.
func VerifySuperAdminPassword(hash, plaintext string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plaintext)) == nil
}

// --- Session Management ---

// CreateSession stores a new session for a super admin and returns the session ID.
// The session ID is stored in an HTTP-only cookie in the browser.
func (r *ConsoleRepository) CreateSession(ctx context.Context, adminID string, duration time.Duration) (*models.ConsoleSession, error) {
	session := &models.ConsoleSession{}
	expiresAt := time.Now().Add(duration)

	err := r.db.QueryRow(ctx,
		`INSERT INTO console_sessions (admin_id, expires_at, created_at)
		 VALUES ($1, $2, NOW())
		 RETURNING id, admin_id, expires_at, created_at`,
		adminID, expiresAt,
	).Scan(&session.ID, &session.AdminID, &session.ExpiresAt, &session.CreatedAt)
	if err != nil {
		return nil, fmt.Errorf("failed to create session: %w", err)
	}
	return session, nil
}

// GetSessionWithAdmin validates a session ID and returns the session + admin.
// Returns ErrNotFound if expired or non-existent.
func (r *ConsoleRepository) GetSessionWithAdmin(ctx context.Context, sessionID string) (*models.SuperAdmin, error) {
	admin := &models.SuperAdmin{}
	err := r.db.QueryRow(ctx,
		`SELECT sa.id, sa.name, sa.email, sa.created_at, sa.updated_at
		 FROM console_sessions cs
		 JOIN super_admins sa ON sa.id = cs.admin_id
		 WHERE cs.id = $1 AND cs.expires_at > NOW()`,
		sessionID,
	).Scan(&admin.ID, &admin.Name, &admin.Email, &admin.CreatedAt, &admin.UpdatedAt)
	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to validate session: %w", err)
	}
	return admin, nil
}

// DeleteSession logs out the admin by removing their session.
func (r *ConsoleRepository) DeleteSession(ctx context.Context, sessionID string) error {
	_, err := r.db.Exec(ctx, `DELETE FROM console_sessions WHERE id = $1`, sessionID)
	return err
}

// --- Dashboard Data ---

// GetSummary returns aggregated platform-wide statistics for the console dashboard.
func (r *ConsoleRepository) GetSummary(ctx context.Context) (*models.ConsoleSummary, error) {
	summary := &models.ConsoleSummary{}

	err := r.db.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM businesses)                                              AS total_businesses,
			(SELECT COUNT(*) FROM users)                                                   AS total_users,
			(SELECT COUNT(*) FROM customers WHERE is_deleted = FALSE)                      AS total_customers,
			(SELECT COUNT(*) FROM transactions WHERE is_deleted = FALSE)                   AS total_transactions,
			COALESCE((SELECT SUM(amount) FROM transactions WHERE type='debt'    AND is_deleted=FALSE), 0) AS total_debt,
			COALESCE((SELECT SUM(amount) FROM transactions WHERE type='payment' AND is_deleted=FALSE), 0) AS total_payments,
			(SELECT COUNT(*) FROM businesses WHERE created_at::date = CURRENT_DATE)        AS new_today
	`).Scan(
		&summary.TotalBusinesses,
		&summary.TotalUsers,
		&summary.TotalCustomers,
		&summary.TotalTransactions,
		&summary.TotalDebtAmount,
		&summary.TotalPaymentAmount,
		&summary.NewBusinessesToday,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch summary: %w", err)
	}
	return summary, nil
}

// GetBusinesses returns a paginated, enriched list of all businesses.
func (r *ConsoleRepository) GetBusinesses(ctx context.Context, limit, offset int) ([]models.BusinessRow, error) {
	rows, err := r.db.Query(ctx, `
		SELECT
			b.id, b.name, b.type,
			owner.name  AS owner_name,
			owner.phone AS owner_phone,
			(SELECT COUNT(*) FROM users    u WHERE u.business_id = b.id AND u.role = 'staff') AS staff_count,
			(SELECT COUNT(*) FROM customers c WHERE c.business_id = b.id AND c.is_deleted = FALSE) AS customer_count,
			b.created_at
		FROM businesses b
		JOIN users owner ON owner.business_id = b.id AND owner.role = 'owner'
		ORDER BY b.created_at DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query businesses: %w", err)
	}
	defer rows.Close()

	var businesses []models.BusinessRow
	for rows.Next() {
		var biz models.BusinessRow
		if err := rows.Scan(
			&biz.ID, &biz.Name, &biz.Type,
			&biz.OwnerName, &biz.OwnerPhone,
			&biz.StaffCount, &biz.CustomerCount,
			&biz.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan business row: %w", err)
		}
		businesses = append(businesses, biz)
	}
	return businesses, rows.Err()
}

// CountBusinesses returns the total number of businesses (for pagination).
func (r *ConsoleRepository) CountBusinesses(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM businesses`).Scan(&count)
	return count, err
}

// GetUsers returns a paginated list of all users, including their business name.
func (r *ConsoleRepository) GetUsers(ctx context.Context, limit, offset int) ([]models.UserRow, error) {
	rows, err := r.db.Query(ctx, `
		SELECT
			u.id, u.name, u.phone, u.role, u.business_id,
			b.name AS business_name,
			u.created_at
		FROM users u
		JOIN businesses b ON u.business_id = b.id
		ORDER BY u.created_at DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("failed to query users: %w", err)
	}
	defer rows.Close()

	var users []models.UserRow
	for rows.Next() {
		var u models.UserRow
		if err := rows.Scan(
			&u.ID, &u.Name, &u.Phone, &u.Role, &u.BusinessID, &u.BusinessName, &u.CreatedAt,
		); err != nil {
			return nil, fmt.Errorf("failed to scan user: %w", err)
		}
		users = append(users, u)
	}
	return users, rows.Err()
}

// CountUsers returns the total number of users (for pagination).
func (r *ConsoleRepository) CountUsers(ctx context.Context) (int, error) {
	var count int
	err := r.db.QueryRow(ctx, `SELECT COUNT(*) FROM users`).Scan(&count)
	return count, err
}
