package repository

import (
	"context"
	"crypto/rand"
	"fmt"
	"math/big"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"

	"salio/server/internal/models"
)

// AuthRepository handles all database operations for authentication:
// registering businesses, logging in users, and managing staff invites.
type AuthRepository struct {
	db *pgxpool.Pool
}

// NewAuthRepository creates a new AuthRepository.
func NewAuthRepository(db *pgxpool.Pool) *AuthRepository {
	return &AuthRepository{db: db}
}

// --- Registration ---

// RegisterBusinessInput holds the validated data for creating a new business + owner.
type RegisterBusinessInput struct {
	BusinessName string
	OwnerName    string
	Phone        string
	Password     string
}

// RegisterBusiness creates a new business and its owner user in a single atomic transaction.
// If any step fails, the entire operation is rolled back.
func (r *AuthRepository) RegisterBusiness(ctx context.Context, input RegisterBusinessInput) (*models.User, error) {
	// Hash the password before storing it — NEVER store plaintext passwords
	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	businessID := uuid.New()
	userID := uuid.New()
	now := time.Now().UTC()

	// Use a database transaction so business + user are created atomically
	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) // Rollback is a no-op if Commit is called first

	// 1. Create the Business
	_, err = tx.Exec(ctx,
		`INSERT INTO businesses (id, name, created_at, updated_at) VALUES ($1, $2, $3, $4)`,
		businessID, input.BusinessName, now, now,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create business: %w", err)
	}

	// 2. Create the Owner User
	_, err = tx.Exec(ctx,
		`INSERT INTO users (id, business_id, name, phone, password_hash, role, created_at, updated_at) 
		 VALUES ($1, $2, $3, $4, $5, 'owner', $6, $7)`,
		userID, businessID, input.OwnerName, input.Phone, string(hash), now, now,
	)
	if err != nil {
		// Check for unique constraint violation on phone
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") {
			return nil, ErrPhoneAlreadyExists
		}
		return nil, fmt.Errorf("failed to create owner user: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return &models.User{
		ID:         userID,
		BusinessID: businessID,
		Name:       input.OwnerName,
		Phone:      input.Phone,
		Role:       "owner",
		CreatedAt:  now,
		UpdatedAt:  now,
	}, nil
}

// --- Login ---

// GetUserByPhone fetches a user by their phone number.
// Returns ErrNotFound if no user exists with that phone OR if the account is deactivated.
// Deactivated staff get the same "user not found" response as unknown phones —
// this avoids revealing account status to an attacker.
func (r *AuthRepository) GetUserByPhone(ctx context.Context, phone string) (*models.User, error) {
	user := &models.User{}
	err := r.db.QueryRow(ctx,
		`SELECT id, business_id, name, phone, password_hash, role, created_at, updated_at 
		 FROM users WHERE phone = $1 AND is_active = TRUE`,
		phone,
	).Scan(&user.ID, &user.BusinessID, &user.Name, &user.Phone, &user.PasswordHash, &user.Role, &user.CreatedAt, &user.UpdatedAt)

	if err == pgx.ErrNoRows {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("failed to query user by phone: %w", err)
	}
	return user, nil
}

// VerifyPassword checks a plaintext password against the stored bcrypt hash.
func VerifyPassword(hash, plaintext string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(plaintext)) == nil
}

// --- Invite System ---

const inviteCodeLength = 6
const inviteCodeChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Exclude ambiguous chars: 0/O, 1/I

// CreateInviteCode generates a random invite code and stores it for the given business.
// Codes expire after 24 hours and can only be used once.
func (r *AuthRepository) CreateInviteCode(ctx context.Context, businessID uuid.UUID) (string, error) {
	code, err := generateRandomCode(inviteCodeLength, inviteCodeChars)
	if err != nil {
		return "", fmt.Errorf("failed to generate invite code: %w", err)
	}

	expiresAt := time.Now().UTC().Add(24 * time.Hour)

	_, err = r.db.Exec(ctx,
		`INSERT INTO business_invites (business_id, code, expires_at, created_at) VALUES ($1, $2, $3, NOW())`,
		businessID, code, expiresAt,
	)
	if err != nil {
		return "", fmt.Errorf("failed to store invite code: %w", err)
	}

	return code, nil
}

// JoinBusinessInput holds the validated data for a staff member joining via invite.
type JoinBusinessInput struct {
	InviteCode string
	StaffName  string
	Phone      string
	Password   string
}

// JoinBusiness validates the invite code and creates the new staff user.
func (r *AuthRepository) JoinBusiness(ctx context.Context, input JoinBusinessInput) (*models.User, error) {
	// 1. Look up and validate the invite code
	var invite models.BusinessInvite
	err := r.db.QueryRow(ctx,
		`SELECT id, business_id, code, expires_at, used_at FROM business_invites 
		 WHERE code = $1 AND used_at IS NULL AND expires_at > NOW()`,
		strings.ToUpper(input.InviteCode),
	).Scan(&invite.ID, &invite.BusinessID, &invite.Code, &invite.ExpiresAt, &invite.UsedAt)

	if err == pgx.ErrNoRows {
		return nil, ErrInvalidInviteCode
	}
	if err != nil {
		return nil, fmt.Errorf("failed to lookup invite code: %w", err)
	}

	// 2. Hash password and create the staff user
	hash, err := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
	if err != nil {
		return nil, fmt.Errorf("failed to hash password: %w", err)
	}

	tx, err := r.db.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	userID := uuid.New()
	now := time.Now().UTC()

	_, err = tx.Exec(ctx,
		`INSERT INTO users (id, business_id, name, phone, password_hash, role, created_at, updated_at)
		 VALUES ($1, $2, $3, $4, $5, 'staff', $6, $7)`,
		userID, invite.BusinessID, input.StaffName, input.Phone, string(hash), now, now,
	)
	if err != nil {
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") {
			return nil, ErrPhoneAlreadyExists
		}
		return nil, fmt.Errorf("failed to create staff user: %w", err)
	}

	// 3. Mark the invite code as used so it cannot be reused
	_, err = tx.Exec(ctx,
		`UPDATE business_invites SET used_at = NOW() WHERE id = $1`,
		invite.ID,
	)
	if err != nil {
		return nil, fmt.Errorf("failed to invalidate invite code: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, fmt.Errorf("failed to commit transaction: %w", err)
	}

	return &models.User{
		ID:         userID,
		BusinessID: invite.BusinessID,
		Name:       input.StaffName,
		Phone:      input.Phone,
		Role:       "staff",
		CreatedAt:  now,
		UpdatedAt:  now,
	}, nil
}

// --- Sentinel errors ---

// Sentinel errors allow callers to check the exact failure mode with errors.Is().
var (
	ErrNotFound         = fmt.Errorf("record not found")
	ErrPhoneAlreadyExists = fmt.Errorf("phone number is already registered")
	ErrInvalidInviteCode  = fmt.Errorf("invite code is invalid or has expired")
)

// generateRandomCode creates a cryptographically random string from a given charset.
func generateRandomCode(length int, charset string) (string, error) {
	result := make([]byte, length)
	for i := range result {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		result[i] = charset[n.Int64()]
	}
	return string(result), nil
}
