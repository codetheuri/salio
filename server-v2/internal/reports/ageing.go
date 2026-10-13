package reports

import (
	"context"
	"sort"
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/money"
)

// AgeingRow is one customer's unpaid debt, split by how long it has been owed.
type AgeingRow struct {
	CustomerID   uuid.UUID    `json:"customer_id"`
	Name         string       `json:"name"`
	Phone        *string      `json:"phone,omitempty"`
	Current      money.Amount `json:"days_0_30"`
	Days31To60   money.Amount `json:"days_31_60"`
	Days61To90   money.Amount `json:"days_61_90"`
	Over90       money.Amount `json:"days_over_90"`
	Total        money.Amount `json:"total"`
	OldestUnpaid time.Time    `json:"oldest_unpaid" doc:"Date of the oldest debt not yet paid off"`
	DaysOldest   int          `json:"days_oldest"`

	// Overdue is the part past an agreed due date — a promise broken, where
	// the age columns only say how long. NextDue is the next date one falls
	// due. Debts recorded without a due date count in neither.
	Overdue money.Amount `json:"overdue"`
	NextDue *time.Time   `json:"next_due,omitempty"`

	// CreditLimit is the customer's limit, if the owner set one.
	CreditLimit *money.Amount `json:"credit_limit,omitempty"`
	OverLimit   bool          `json:"over_limit"`
}

// AgeingView is the whole book of unpaid debt, by age.
type AgeingView struct {
	AsOf       time.Time    `json:"as_of"`
	Rows       []AgeingRow  `json:"rows"`
	Current    money.Amount `json:"days_0_30"`
	Days31To60 money.Amount `json:"days_31_60"`
	Days61To90 money.Amount `json:"days_61_90"`
	Over90     money.Amount `json:"days_over_90"`
	Total      money.Amount `json:"total"`
	Overdue    money.Amount `json:"overdue"`
	OverLimit  int          `json:"customers_over_limit"`
}

// Ageing splits every customer's unpaid debt by how long it has been owed.
//
// Payments are applied to the oldest debt first (see fifo), so a debt from
// March that is still partly unpaid in October shows as over 90 days — exactly
// what the shop needs to see. Customers whose balance is zero or in credit owe
// nothing and do not appear.
func (r *Repository) Ageing(ctx context.Context) (*AgeingView, error) {
	accounts, err := r.customerAccounts(ctx)
	if err != nil {
		return nil, err
	}
	asOf, err := r.Today(ctx)
	if err != nil {
		return nil, err
	}

	v := &AgeingView{AsOf: asOf, Rows: []AgeingRow{}}
	for _, acct := range accounts {
		open := fifo(acct.lines)
		if len(open) == 0 {
			continue
		}
		a := AgeingRow{
			CustomerID: acct.id, Name: acct.name, Phone: acct.phone,
			OldestUnpaid: open[0].date, DaysOldest: daysBetween(open[0].date, asOf),
			CreditLimit: acct.creditLimit,
		}
		for _, d := range open {
			switch age := daysBetween(d.date, asOf); {
			case age <= 30:
				a.Current += d.amount
			case age <= 60:
				a.Days31To60 += d.amount
			case age <= 90:
				a.Days61To90 += d.amount
			default:
				a.Over90 += d.amount
			}
		}
		due := summariseDue(open, asOf, 0)
		a.Total, a.Overdue, a.NextDue = due.total, due.overdue, due.nextDue
		a.OverLimit = acct.creditLimit != nil && a.Total > *acct.creditLimit

		v.Rows = append(v.Rows, a)
		v.Current += a.Current
		v.Days31To60 += a.Days31To60
		v.Days61To90 += a.Days61To90
		v.Over90 += a.Over90
		v.Total += a.Total
		v.Overdue += a.Overdue
		if a.OverLimit {
			v.OverLimit++
		}
	}

	// Worst first: the most money owed for the longest at the top.
	sort.Slice(v.Rows, func(i, j int) bool {
		if v.Rows[i].Over90 != v.Rows[j].Over90 {
			return v.Rows[i].Over90 > v.Rows[j].Over90
		}
		return v.Rows[i].Total > v.Rows[j].Total
	})
	return v, nil
}

func daysBetween(from, to time.Time) int {
	f := time.Date(from.Year(), from.Month(), from.Day(), 0, 0, 0, 0, time.UTC)
	return int(to.Sub(f).Hours() / 24)
}
