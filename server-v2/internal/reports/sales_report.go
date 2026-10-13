package reports

import (
	"context"
	"fmt"
	"time"

	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
)

// ProductSales is how one product sold over a period.
type ProductSales struct {
	ProductName string            `json:"product_name"`
	Quantity    quantity.Quantity `json:"quantity"`
	Amount      money.Amount      `json:"amount"`
	Count       int               `json:"count" doc:"Number of separate sales"`
}

// DailySales is one day of selling, by how it was paid.
type DailySales struct {
	Date   time.Time    `json:"date"`
	Count  int          `json:"count"`
	Total  money.Amount `json:"total"`
	Cash   money.Amount `json:"cash"`
	Mpesa  money.Amount `json:"mpesa"`
	Bank   money.Amount `json:"bank"`
	Credit money.Amount `json:"credit"`
}

// SalesReportView is a period of sales.
//
// Paid is everything settled on the spot — cash, M-Pesa and bank together —
// against Credit, which went onto customers' accounts. The three paid methods
// are also given apart, because cash-up counts the drawer and the M-Pesa
// statement separately.
type SalesReportView struct {
	Period      Period         `json:"period"`
	Count       int            `json:"count"`
	Total       money.Amount   `json:"total"`
	PaidTotal   money.Amount   `json:"paid_total"`
	PaidCount   int            `json:"paid_count"`
	CashTotal   money.Amount   `json:"cash_total"`
	MpesaTotal  money.Amount   `json:"mpesa_total"`
	BankTotal   money.Amount   `json:"bank_total"`
	CreditTotal money.Amount   `json:"credit_total"`
	CreditCount int            `json:"credit_count"`
	TopProducts []ProductSales `json:"top_products" doc:"The 10 best-selling products by value"`
	Daily       []DailySales   `json:"daily" doc:"One row per day, including days with no sales"`
}

// topProductLimit is what fits on a phone screen and the first page of a PDF.
const topProductLimit = 10

func (r *Repository) SalesReport(ctx context.Context, p Period) (*SalesReportView, error) {
	v := &SalesReportView{Period: p, TopProducts: []ProductSales{}, Daily: []DailySales{}}

	var totals struct {
		Count, PaidCount, CreditCount                        int
		Total, CashTotal, MpesaTotal, BankTotal, CreditTotal money.Amount
	}
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COUNT(*)                                                     AS count,
		       COUNT(*) FILTER (WHERE payment_method <> 'credit')           AS paid_count,
		       COUNT(*) FILTER (WHERE payment_method = 'credit')            AS credit_count,
		       COALESCE(SUM(amount), 0)                                     AS total,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'cash'), 0)   AS cash_total,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'mpesa'), 0)  AS mpesa_total,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'bank'), 0)   AS bank_total,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'credit'), 0) AS credit_total
		FROM sales
		WHERE business_id = ? AND is_deleted = false AND sale_date BETWEEN ? AND ?
	`, mustTenant(ctx), p.From, p.To).Scan(&totals).Error; err != nil {
		return nil, fmt.Errorf("sales totals: %w", err)
	}
	v.Count, v.PaidCount, v.CreditCount = totals.Count, totals.PaidCount, totals.CreditCount
	v.Total, v.CreditTotal = totals.Total, totals.CreditTotal
	v.CashTotal, v.MpesaTotal, v.BankTotal = totals.CashTotal, totals.MpesaTotal, totals.BankTotal
	v.PaidTotal = v.CashTotal + v.MpesaTotal + v.BankTotal

	// Grouped case- and space-insensitively: "DAP 50kg", "dap 50kg " and
	// "DAP 50KG" are the same bag, typed by three people. The display name is
	// the most-used spelling of each.
	if err := r.db.WithContext(ctx).Raw(`
		SELECT MODE() WITHIN GROUP (ORDER BY product_name) AS product_name,
		       SUM(quantity)            AS quantity,
		       SUM(amount)              AS amount,
		       COUNT(*)                 AS count
		FROM sales
		WHERE business_id = ? AND is_deleted = false AND sale_date BETWEEN ? AND ?
		GROUP BY lower(btrim(product_name))
		ORDER BY SUM(amount) DESC
		LIMIT ?
	`, mustTenant(ctx), p.From, p.To, topProductLimit).Scan(&v.TopProducts).Error; err != nil {
		return nil, fmt.Errorf("top products: %w", err)
	}

	var daily []DailySales
	if err := r.db.WithContext(ctx).Raw(`
		SELECT sale_date AS date, COUNT(*) AS count, SUM(amount) AS total,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'cash'), 0)   AS cash,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'mpesa'), 0)  AS mpesa,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'bank'), 0)   AS bank,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'credit'), 0) AS credit
		FROM sales
		WHERE business_id = ? AND is_deleted = false AND sale_date BETWEEN ? AND ?
		GROUP BY sale_date
	`, mustTenant(ctx), p.From, p.To).Scan(&daily).Error; err != nil {
		return nil, fmt.Errorf("daily sales: %w", err)
	}
	byDay := map[string]DailySales{}
	for _, d := range daily {
		byDay[dayKey(d.Date)] = d
	}
	for _, day := range p.days() {
		d, ok := byDay[dayKey(day)]
		if !ok {
			d = DailySales{}
		}
		d.Date = day
		v.Daily = append(v.Daily, d)
	}
	return v, nil
}
