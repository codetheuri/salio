package models

import "time"

// SuperAdmin represents a Salio platform operator who can access the admin console.
// This is completely separate from business Users — they have different auth,
// different tables, and different permissions.
type SuperAdmin struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"` // Never expose this
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// ConsoleSession tracks an active login session for a super admin.
// The session ID is stored in an HTTP-only cookie on the browser.
type ConsoleSession struct {
	ID        string    `json:"id"`
	AdminID   string    `json:"admin_id"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

// ConsoleSummary holds the aggregated platform statistics shown on the dashboard.
// It is calculated fresh on each page load (can add caching later if needed).
type ConsoleSummary struct {
	TotalBusinesses    int     `json:"total_businesses"`
	TotalUsers         int     `json:"total_users"`
	TotalCustomers     int     `json:"total_customers"`
	TotalTransactions  int     `json:"total_transactions"`
	TotalDebtAmount    float64 `json:"total_debt_amount"`
	TotalPaymentAmount float64 `json:"total_payment_amount"`
	OutstandingBalance float64 `json:"outstanding_balance"`
	NewBusinessesToday int     `json:"new_businesses_today"`
}

// BusinessRow is a flattened view of a business for the console table,
// including the owner's name (joined from users table).
type BusinessRow struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Type         *string   `json:"type"`
	OwnerName    string    `json:"owner_name"`
	OwnerPhone   string    `json:"owner_phone"`
	StaffCount   int       `json:"staff_count"`
	CustomerCount int      `json:"customer_count"`
	CreatedAt    time.Time `json:"created_at"`
}

// UserRow is a flattened view of a user/staff for the console table,
// including the business name (joined from businesses table).
type UserRow struct {
	ID           string    `json:"id"`
	Name         string    `json:"name"`
	Phone        string    `json:"phone"`
	Role         string    `json:"role"`
	BusinessID   string    `json:"business_id"`
	BusinessName string    `json:"business_name"`
	CreatedAt    time.Time `json:"created_at"`
}

// BusinessDetails extends BusinessRow with financial statistics for the business details page.
type BusinessDetails struct {
	BusinessRow
	TotalDebtAmount    float64   `json:"total_debt_amount"`
	TotalPaymentAmount float64   `json:"total_payment_amount"`
	OutstandingBalance float64   `json:"outstanding_balance"`
	TotalTransactions  int       `json:"total_transactions"`
	LastSyncedAt       time.Time `json:"last_synced_at"`
}
