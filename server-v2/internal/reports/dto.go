package reports

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/money"
)

// DebtorView is one row in an actionable list: a customer with an outstanding
// balance, and how long it has been since anything happened on their account.
type DebtorView struct {
	CustomerID    uuid.UUID    `json:"customer_id"`
	Name          string       `json:"name"`
	Phone         *string      `json:"phone,omitempty"`
	Balance       money.Amount `json:"balance"`
	LastActivity  time.Time    `json:"last_activity"`
	DaysSinceLast int          `json:"days_since_last_activity"`
}

// SummaryView is what an owner sees opening the dashboard: three numbers, and
// two short lists telling them what to actually do about it.
type SummaryView struct {
	TotalCustomers int64 `json:"total_customers"`

	// TotalOutstandingDebt is what customers owe the shop: the sum of every
	// positive balance. Advances are not netted against it.
	TotalOutstandingDebt money.Amount `json:"total_outstanding_debt"`

	// TotalAdvancesHeld is what the shop holds for customers who paid ahead:
	// the sum of every negative balance, as a positive number. It is the
	// shop's money only until those customers buy against it.
	TotalAdvancesHeld money.Amount `json:"total_advances_held"`
	CustomersInCredit int          `json:"customers_in_credit"`

	TotalCollected30Days money.Amount `json:"total_collected_last_30_days"`
	OverdueDebtorCount   int          `json:"overdue_debtor_count"`

	// TopDebtors ranks by balance regardless of recency — who to prioritise if
	// collecting were the only goal.
	TopDebtors []DebtorView `json:"top_debtors"`

	// OverdueDebtors ranks by staleness: a balance sitting untouched the
	// longest. This is the list an owner is most likely to have forgotten about
	// on their own — the point of putting it on the dashboard at all.
	OverdueDebtors []DebtorView `json:"overdue_debtors"`
}

type SummaryInput struct{}

type SummaryOutput struct {
	Body struct {
		Success bool        `json:"success"`
		Data    SummaryView `json:"data"`
	}
}
