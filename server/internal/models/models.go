package models

import (
	"time"

	"github.com/google/uuid"
)

// Business represents the central retail shop account in Salio.
// Every user, customer, and transaction belongs to one Business.
type Business struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	Type      *string   `json:"type,omitempty"` // nullable
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// User represents a staff member or owner who logs into the app.
type User struct {
	ID           uuid.UUID `json:"id"`
	BusinessID   uuid.UUID `json:"business_id"`
	Name         string    `json:"name"`
	Phone        string    `json:"phone"`
	PasswordHash string    `json:"-"` // NEVER serialise the hash to JSON
	Role         string    `json:"role"` // "owner" or "staff"
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// Customer represents a buyer who owes money to a Business.
// Customers do NOT have login access to the app.
type Customer struct {
	ID          uuid.UUID  `json:"id"`
	BusinessID  uuid.UUID  `json:"business_id"`
	Name        string     `json:"name"`
	Phone       *string    `json:"phone,omitempty"`
	Notes       *string    `json:"notes,omitempty"`
	CreatedBy   uuid.UUID  `json:"created_by"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
	IsDeleted   bool       `json:"is_deleted"`
}

// TransactionType defines the allowed transaction kinds
type TransactionType string

const (
	TransactionTypeDebt    TransactionType = "debt"
	TransactionTypePayment TransactionType = "payment"
)

// Transaction represents a single financial event (a debt or payment).
// Transactions are immutable — mistakes are corrected by creating new offsetting entries.
type Transaction struct {
	ID              uuid.UUID       `json:"id"`
	BusinessID      uuid.UUID       `json:"business_id"`
	CustomerID      uuid.UUID       `json:"customer_id"`
	UserID          uuid.UUID       `json:"user_id"`
	Type            TransactionType `json:"type"`
	Amount          float64         `json:"amount"`
	Description     *string         `json:"description,omitempty"`
	TransactionDate time.Time       `json:"transaction_date"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
	IsDeleted       bool            `json:"is_deleted"`
}

// BusinessInvite stores a short-lived invite code linking new staff to a Business.
type BusinessInvite struct {
	ID         int       `json:"id"`
	BusinessID uuid.UUID `json:"business_id"`
	Code       string    `json:"code"` // e.g. "X7K9P2"
	ExpiresAt  time.Time `json:"expires_at"`
	UsedAt     *time.Time `json:"used_at,omitempty"`
	CreatedAt  time.Time `json:"created_at"`
}

// SyncPayload represents the payload exchanged between the mobile app and server during a sync cycle.
type SyncPayload struct {
	Customers    []Customer    `json:"customers"`
	Transactions []Transaction `json:"transactions"`
	ServerTime   time.Time     `json:"server_time,omitempty"`
}
