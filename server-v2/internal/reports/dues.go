package reports

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/money"
)

// --- First in, first out ---

// ledgerLine is one entry of a running account, from whichever side: a debt or
// a supplier bill is a charge, a payment is not.
type ledgerLine struct {
	charge bool
	amount money.Amount
	date   time.Time
	due    *time.Time
}

// openItem is the unpaid part of one charge.
type openItem struct {
	date   time.Time
	due    *time.Time
	amount money.Amount
}

// fifo works out which charges are still unpaid, applying every payment to the
// oldest charge first. lines must be in date order.
//
// The standard method, and the only one that answers "how long has this been
// owed" honestly: applied any other way, someone who pays a little every week
// never looks overdue, however old the debt they keep not quite clearing.
//
// A payment with nothing left to clear is an advance; it waits and clears the
// next charge. What remains open is what is owed, oldest first.
func fifo(lines []ledgerLine) []openItem {
	var open []openItem
	var advance money.Amount
	for _, l := range lines {
		if l.charge {
			amt := l.amount
			if advance > 0 {
				used := min(advance, amt)
				advance -= used
				amt -= used
			}
			if amt > 0 {
				open = append(open, openItem{date: l.date, due: l.due, amount: amt})
			}
			continue
		}
		pay := l.amount
		for pay > 0 && len(open) > 0 {
			used := min(pay, open[0].amount)
			open[0].amount -= used
			pay -= used
			if open[0].amount == 0 {
				open = open[1:]
			}
		}
		advance += pay
	}
	return open
}

// dueSummary is what the due dates on one account's open items add up to.
type dueSummary struct {
	total       money.Amount
	overdue     money.Amount // past its due date
	dueSoon     money.Amount // due today or within the window
	earliestDue *time.Time   // the earliest due date among open items
	nextDue     *time.Time   // the earliest due date not yet passed
}

// summariseDue reads the due dates of an account's open items as of a day.
// Items with no due date count towards the total only: nothing was agreed, so
// nothing is late.
func summariseDue(open []openItem, asOf time.Time, withinDays int) dueSummary {
	var s dueSummary
	horizon := asOf.AddDate(0, 0, withinDays)
	for _, o := range open {
		s.total += o.amount
		if o.due == nil {
			continue
		}
		due := *o.due
		if s.earliestDue == nil || due.Before(*s.earliestDue) {
			s.earliestDue = &due
		}
		switch {
		case due.Before(asOf):
			s.overdue += o.amount
		default:
			if !due.After(horizon) {
				s.dueSoon += o.amount
			}
			if s.nextDue == nil || due.Before(*s.nextDue) {
				s.nextDue = &due
			}
		}
	}
	return s
}

// --- Customers: who to remind ---

// DueRow is one customer with money overdue or falling due soon.
type DueRow struct {
	CustomerID  uuid.UUID    `json:"customer_id"`
	Name        string       `json:"name"`
	Phone       *string      `json:"phone,omitempty"`
	Overdue     money.Amount `json:"overdue" doc:"Owed and past the agreed due date"`
	DueSoon     money.Amount `json:"due_soon" doc:"Falling due today or within the window"`
	TotalOwed   money.Amount `json:"total_owed"`
	EarliestDue *time.Time   `json:"earliest_due,omitempty" doc:"The oldest due date still unpaid"`
	DaysOverdue int          `json:"days_overdue" doc:"Days since the earliest missed due date; 0 when nothing is overdue"`
}

// DueView is the reminder list.
type DueView struct {
	AsOf       time.Time    `json:"as_of"`
	WithinDays int          `json:"within_days"`
	Rows       []DueRow     `json:"rows"`
	Overdue    money.Amount `json:"overdue"`
	DueSoon    money.Amount `json:"due_soon"`
}

type DueInput struct {
	WithinDays int `query:"within_days" default:"7" minimum:"0" maximum:"90" doc:"Include debts falling due within this many days"`
}

type DueOutput struct {
	Body struct {
		Success bool    `json:"success"`
		Data    DueView `json:"data"`
	}
}

// Due lists customers who are overdue or about to be: who to remind today.
// Only debts that carry a due date can be late; the rest stay in the ageing
// report, which measures how long, not whether a promise was broken.
func (r *Repository) Due(ctx context.Context, withinDays int) (*DueView, error) {
	accounts, err := r.customerAccounts(ctx)
	if err != nil {
		return nil, err
	}
	asOf, err := r.Today(ctx)
	if err != nil {
		return nil, err
	}

	v := &DueView{AsOf: asOf, WithinDays: withinDays, Rows: []DueRow{}}
	for _, a := range accounts {
		s := summariseDue(fifo(a.lines), asOf, withinDays)
		if s.overdue == 0 && s.dueSoon == 0 {
			continue
		}
		row := DueRow{
			CustomerID: a.id, Name: a.name, Phone: a.phone,
			Overdue: s.overdue, DueSoon: s.dueSoon, TotalOwed: s.total, EarliestDue: s.earliestDue,
		}
		if s.overdue > 0 && s.earliestDue != nil {
			row.DaysOverdue = daysBetween(*s.earliestDue, asOf)
		}
		v.Rows = append(v.Rows, row)
		v.Overdue += s.overdue
		v.DueSoon += s.dueSoon
	}
	// Most overdue first, then whatever falls due soonest.
	sort.SliceStable(v.Rows, func(i, j int) bool {
		a, b := v.Rows[i], v.Rows[j]
		if a.DaysOverdue != b.DaysOverdue {
			return a.DaysOverdue > b.DaysOverdue
		}
		return a.Overdue+a.DueSoon > b.Overdue+b.DueSoon
	})
	return v, nil
}

// account is one customer's or supplier's ledger, in date order.
type account struct {
	id          uuid.UUID
	name        string
	phone       *string
	creditLimit *money.Amount
	lines       []ledgerLine
}

// customerAccounts loads every live customer's live ledger in one query.
func (r *Repository) customerAccounts(ctx context.Context) ([]account, error) {
	businessID, err := tenantID(ctx)
	if err != nil {
		return nil, err
	}
	var rows []struct {
		CustomerID  uuid.UUID
		Name        string
		Phone       *string
		CreditLimit *money.Amount
		Type        string
		Amount      money.Amount
		Date        time.Time
		DueDate     *time.Time
	}
	// Both sides of the join state the business: automatic scoping only
	// reaches the base table.
	if err := r.db.WithContext(ctx).Raw(`
		SELECT c.id AS customer_id, c.name, c.phone, c.credit_limit,
		       t.type, t.amount, t.transaction_date AS date, t.due_date
		FROM transactions t
		JOIN customers c ON c.id = t.customer_id AND c.business_id = ?
		WHERE t.business_id = ? AND t.is_deleted = false AND c.is_deleted = false
		ORDER BY c.id, t.transaction_date, t.created_at
	`, businessID, businessID).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("loading customer ledgers: %w", err)
	}

	var out []account
	for _, row := range rows {
		if len(out) == 0 || out[len(out)-1].id != row.CustomerID {
			out = append(out, account{id: row.CustomerID, name: row.Name, phone: row.Phone, creditLimit: row.CreditLimit})
		}
		a := &out[len(out)-1]
		a.lines = append(a.lines, ledgerLine{charge: row.Type == "debt", amount: row.Amount, date: row.Date, due: row.DueDate})
	}
	return out, nil
}

// --- Suppliers: what the shop has to pay ---

// PayableRow is what the shop owes one supplier.
type PayableRow struct {
	SupplierID uuid.UUID    `json:"supplier_id"`
	Name       string       `json:"name"`
	Phone      *string      `json:"phone,omitempty"`
	Owed       money.Amount `json:"owed"`
	Overdue    money.Amount `json:"overdue" doc:"Bills past their due date"`
	DueSoon    money.Amount `json:"due_soon" doc:"Bills due today or within the window"`
	NextDue    *time.Time   `json:"next_due,omitempty" doc:"The next due date not yet passed"`
	OldestBill time.Time    `json:"oldest_bill" doc:"Date of the oldest bill not fully paid"`
}

// PayablesView is everything the shop owes its suppliers.
type PayablesView struct {
	AsOf       time.Time    `json:"as_of"`
	WithinDays int          `json:"within_days"`
	Rows       []PayableRow `json:"rows"`
	Owed       money.Amount `json:"owed"`
	Overdue    money.Amount `json:"overdue"`
	DueSoon    money.Amount `json:"due_soon"`

	// PrepaymentsHeld is money suppliers hold for the shop — paid ahead of
	// any bill. Kept apart from Owed for the same reason the dashboard keeps
	// customer advances apart: netting them hides both.
	PrepaymentsHeld money.Amount `json:"prepayments_held"`
}

type PayablesOutput struct {
	Body struct {
		Success bool         `json:"success"`
		Data    PayablesView `json:"data"`
	}
}

// Payables lists every supplier the shop owes, most urgent first.
func (r *Repository) Payables(ctx context.Context, withinDays int) (*PayablesView, error) {
	businessID, err := tenantID(ctx)
	if err != nil {
		return nil, err
	}
	asOf, err := r.Today(ctx)
	if err != nil {
		return nil, err
	}

	var rows []struct {
		SupplierID uuid.UUID
		Name       string
		Phone      *string
		Type       string
		Amount     money.Amount
		Date       time.Time
		DueDate    *time.Time
	}
	if err := r.db.WithContext(ctx).Raw(`
		SELECT s.id AS supplier_id, s.name, s.phone,
		       t.type, t.amount, t.transaction_date AS date, t.due_date
		FROM supplier_transactions t
		JOIN suppliers s ON s.id = t.supplier_id AND s.business_id = ?
		WHERE t.business_id = ? AND t.is_deleted = false AND s.is_deleted = false
		ORDER BY s.id, t.transaction_date, t.created_at
	`, businessID, businessID).Scan(&rows).Error; err != nil {
		return nil, fmt.Errorf("loading supplier ledgers: %w", err)
	}

	var accounts []account
	for _, row := range rows {
		if len(accounts) == 0 || accounts[len(accounts)-1].id != row.SupplierID {
			accounts = append(accounts, account{id: row.SupplierID, name: row.Name, phone: row.Phone})
		}
		a := &accounts[len(accounts)-1]
		a.lines = append(a.lines, ledgerLine{charge: row.Type == "bill", amount: row.Amount, date: row.Date, due: row.DueDate})
	}

	v := &PayablesView{AsOf: asOf, WithinDays: withinDays, Rows: []PayableRow{}}
	for _, a := range accounts {
		var balance money.Amount
		for _, l := range a.lines {
			if l.charge {
				balance += l.amount
			} else {
				balance -= l.amount
			}
		}
		if balance < 0 {
			v.PrepaymentsHeld -= balance
			continue
		}
		open := fifo(a.lines)
		if len(open) == 0 {
			continue
		}
		s := summariseDue(open, asOf, withinDays)
		v.Rows = append(v.Rows, PayableRow{
			SupplierID: a.id, Name: a.name, Phone: a.phone,
			Owed: s.total, Overdue: s.overdue, DueSoon: s.dueSoon, NextDue: s.nextDue,
			OldestBill: open[0].date,
		})
		v.Owed += s.total
		v.Overdue += s.overdue
		v.DueSoon += s.dueSoon
	}
	sort.SliceStable(v.Rows, func(i, j int) bool {
		a, b := v.Rows[i], v.Rows[j]
		if a.Overdue != b.Overdue {
			return a.Overdue > b.Overdue
		}
		if a.DueSoon != b.DueSoon {
			return a.DueSoon > b.DueSoon
		}
		return a.Owed > b.Owed
	})
	return v, nil
}
