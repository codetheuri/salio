package reports

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// DailyCollection is one day's payments received, by how they arrived.
type DailyCollection struct {
	Date       time.Time    `json:"date"`
	Count      int          `json:"count"`
	Amount     money.Amount `json:"amount"`
	Cash       money.Amount `json:"cash"`
	Mpesa      money.Amount `json:"mpesa"`
	Bank       money.Amount `json:"bank"`
	Unrecorded money.Amount `json:"unrecorded" doc:"Payments recorded before the method was asked for"`
}

// StaffActivity is what one person recorded over a period.
type StaffActivity struct {
	UserID        uuid.UUID    `json:"user_id"`
	Name          string       `json:"name"`
	Role          domain.Role  `json:"role"`
	IsActive      bool         `json:"is_active"`
	DebtsCount    int          `json:"debts_count" doc:"Debts entered by hand; credit sales count as sales"`
	DebtsTotal    money.Amount `json:"debts_total"`
	PaymentsCount int          `json:"payments_count"`
	PaymentsTotal money.Amount `json:"payments_total"`
	SalesCount    int          `json:"sales_count"`
	SalesTotal    money.Amount `json:"sales_total"`
}

// CollectionsView is money coming in, and who did the work.
type CollectionsView struct {
	Period         Period       `json:"period"`
	TotalCollected money.Amount `json:"total_collected"`
	PaymentCount   int          `json:"payment_count"`

	// By method, for cash-up: the drawer should hold Cash, the M-Pesa
	// statement should show Mpesa. Unrecorded is payments from before the
	// method was asked for — unknown, deliberately not guessed as cash.
	Cash       money.Amount `json:"cash"`
	Mpesa      money.Amount `json:"mpesa"`
	Bank       money.Amount `json:"bank"`
	Unrecorded money.Amount `json:"unrecorded"`

	Daily []DailyCollection `json:"daily" doc:"One row per day, including days with nothing collected"`

	// The advance position now, not over the period: how much the shop is
	// holding for customers who paid ahead, and how many of them there are.
	AdvancesHeld      money.Amount `json:"advances_held"`
	CustomersInCredit int          `json:"customers_in_credit"`

	Staff []StaffActivity `json:"staff"`
}

func (r *Repository) Collections(ctx context.Context, p Period) (*CollectionsView, error) {
	businessID := mustTenant(ctx)
	v := &CollectionsView{Period: p, Daily: []DailyCollection{}, Staff: []StaffActivity{}}

	var daily []DailyCollection
	if err := r.db.WithContext(ctx).Raw(`
		SELECT transaction_date AS date, COUNT(*) AS count, SUM(amount) AS amount,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'cash'), 0)  AS cash,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'mpesa'), 0) AS mpesa,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method = 'bank'), 0)  AS bank,
		       COALESCE(SUM(amount) FILTER (WHERE payment_method IS NULL), 0)   AS unrecorded
		FROM transactions
		WHERE business_id = ? AND is_deleted = false AND type = 'payment'
		  AND transaction_date BETWEEN ? AND ?
		GROUP BY transaction_date
	`, businessID, p.From, p.To).Scan(&daily).Error; err != nil {
		return nil, fmt.Errorf("daily collections: %w", err)
	}
	byDay := map[string]DailyCollection{}
	for _, d := range daily {
		byDay[dayKey(d.Date)] = d
		v.TotalCollected += d.Amount
		v.PaymentCount += d.Count
		v.Cash += d.Cash
		v.Mpesa += d.Mpesa
		v.Bank += d.Bank
		v.Unrecorded += d.Unrecorded
	}
	for _, day := range p.days() {
		d := byDay[dayKey(day)]
		d.Date = day
		v.Daily = append(v.Daily, d)
	}

	var advances struct {
		Held     money.Amount
		InCredit int
	}
	if err := r.db.WithContext(ctx).Raw(`
		SELECT COALESCE(-SUM(balance) FILTER (WHERE balance < 0), 0) AS held,
		       COUNT(*) FILTER (WHERE balance < 0)                   AS in_credit
		FROM (
			SELECT SUM(CASE WHEN t.type = 'debt' THEN t.amount ELSE -t.amount END) AS balance
			FROM transactions t
			JOIN customers c ON c.id = t.customer_id AND c.business_id = ?
			WHERE t.business_id = ? AND t.is_deleted = false AND c.is_deleted = false
			GROUP BY t.customer_id
		) AS per_customer
	`, businessID, businessID).Scan(&advances).Error; err != nil {
		return nil, fmt.Errorf("advances held: %w", err)
	}
	v.AdvancesHeld, v.CustomersInCredit = advances.Held, advances.InCredit

	// Everyone in the business, including deactivated staff: someone who left
	// last week still recorded what they recorded, and the report for that
	// week has to say so.
	var users []domain.User
	if err := r.db.WithContext(ctx).Order("role, name").Find(&users).Error; err != nil {
		return nil, fmt.Errorf("loading staff: %w", err)
	}
	staff := map[uuid.UUID]*StaffActivity{}
	for _, u := range users {
		staff[u.ID] = &StaffActivity{UserID: u.ID, Name: u.Name, Role: u.Role, IsActive: u.IsActive}
	}

	var ledger []struct {
		UserID uuid.UUID
		Type   domain.TransactionType
		Count  int
		Total  money.Amount
	}
	// sale_id IS NULL: a credit sale's debt is already counted under sales, and
	// counting it again as a debt would double the work it shows.
	if err := r.db.WithContext(ctx).Raw(`
		SELECT user_id, type, COUNT(*) AS count, SUM(amount) AS total
		FROM transactions
		WHERE business_id = ? AND is_deleted = false AND sale_id IS NULL
		  AND transaction_date BETWEEN ? AND ?
		GROUP BY user_id, type
	`, businessID, p.From, p.To).Scan(&ledger).Error; err != nil {
		return nil, fmt.Errorf("staff ledger activity: %w", err)
	}
	for _, l := range ledger {
		s, ok := staff[l.UserID]
		if !ok {
			continue
		}
		if l.Type == domain.TypeDebt {
			s.DebtsCount, s.DebtsTotal = l.Count, l.Total
		} else {
			s.PaymentsCount, s.PaymentsTotal = l.Count, l.Total
		}
	}

	var sold []struct {
		UserID uuid.UUID
		Count  int
		Total  money.Amount
	}
	if err := r.db.WithContext(ctx).Raw(`
		SELECT user_id, COUNT(*) AS count, SUM(amount) AS total
		FROM sales
		WHERE business_id = ? AND is_deleted = false AND sale_date BETWEEN ? AND ?
		GROUP BY user_id
	`, businessID, p.From, p.To).Scan(&sold).Error; err != nil {
		return nil, fmt.Errorf("staff sales activity: %w", err)
	}
	for _, s := range sold {
		if a, ok := staff[s.UserID]; ok {
			a.SalesCount, a.SalesTotal = s.Count, s.Total
		}
	}

	for _, u := range users {
		v.Staff = append(v.Staff, *staff[u.ID])
	}
	// Most active first.
	sort.SliceStable(v.Staff, func(i, j int) bool {
		return v.Staff[i].PaymentsTotal+v.Staff[i].SalesTotal > v.Staff[j].PaymentsTotal+v.Staff[j].SalesTotal
	})
	return v, nil
}
