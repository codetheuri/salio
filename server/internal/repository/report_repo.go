package repository

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type ReportSummary struct {
	TotalOutstandingDebt    float64 `json:"total_outstanding_debt"`
	HighestDebtCustomerName string  `json:"highest_debt_customer_name"`
	HighestDebtAmount       float64 `json:"highest_debt_amount"`
	OverstayedDebtCount     int     `json:"overstayed_debt_count"`
	TotalCustomers          int     `json:"total_customers"`
}

type ReportRepository struct {
	pool *pgxpool.Pool
}

func NewReportRepository(pool *pgxpool.Pool) *ReportRepository {
	return &ReportRepository{pool: pool}
}

func (r *ReportRepository) GetSummary(ctx context.Context, businessID string) (*ReportSummary, error) {
	summary := &ReportSummary{}

	// Query 1: Total Customers
	err := r.pool.QueryRow(ctx, `
		SELECT COUNT(id) FROM customers WHERE business_id = $1 AND is_deleted = false
	`, businessID).Scan(&summary.TotalCustomers)
	if err != nil {
		return nil, err
	}

	// Query 2: Total Outstanding Debt (Sum of all debt - Sum of all payments)
	err = r.pool.QueryRow(ctx, `
		SELECT COALESCE(SUM(
			CASE WHEN type = 'debt' THEN amount ELSE -amount END
		), 0)
		FROM transactions 
		WHERE business_id = $1 AND is_deleted = false
	`, businessID).Scan(&summary.TotalOutstandingDebt)
	if err != nil {
		return nil, err
	}

	// Query 3: Highest Debt Customer
	err = r.pool.QueryRow(ctx, `
		SELECT c.name, 
			COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END), 0) as balance
		FROM customers c
		JOIN transactions t ON c.id = t.customer_id
		WHERE c.business_id = $1 AND c.is_deleted = false AND t.is_deleted = false
		GROUP BY c.id, c.name
		HAVING COALESCE(SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END), 0) > 0
		ORDER BY balance DESC 
		LIMIT 1
	`, businessID).Scan(&summary.HighestDebtCustomerName, &summary.HighestDebtAmount)
	
	if err != nil && err.Error() != "no rows in result set" {
		return nil, err
	}
	if summary.HighestDebtCustomerName == "" {
		summary.HighestDebtCustomerName = "N/A"
	}

	// Query 4: Overstayed Debt Count (> 30 days)
	// We count customers whose balance > 0 AND whose LAST transaction was > 30 days ago
	thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
	err = r.pool.QueryRow(ctx, `
		WITH customer_balances AS (
			SELECT customer_id, 
				COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0) as balance,
				MAX(created_at) as last_tx_date
			FROM transactions
			WHERE business_id = $1 AND is_deleted = false
			GROUP BY customer_id
		)
		SELECT COUNT(*)
		FROM customer_balances cb
		JOIN customers c ON c.id = cb.customer_id
		WHERE c.is_deleted = false 
		  AND cb.balance > 0 
		  AND cb.last_tx_date < $2
	`, businessID, thirtyDaysAgo).Scan(&summary.OverstayedDebtCount)
	if err != nil {
		return nil, err
	}

	return summary, nil
}
