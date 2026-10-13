package reports

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

const dateLayout = "2006-01-02"

// MaxPeriodDays bounds a report's date range. A year covers every real question
// a shop asks of its books — this month, last quarter, this year — and bounds how
// much work a single request can ask of the database.
const MaxPeriodDays = 366

var (
	ErrInvalidDate      = errors.New("dates must be in YYYY-MM-DD format")
	ErrPeriodBackwards  = errors.New("the start date is after the end date")
	ErrPeriodTooLong    = errors.New("a report covers at most 366 days; choose a shorter period")
	ErrCustomerNotFound = errors.New("customer not found")
)

// PeriodInput is the date range every period report takes.
type PeriodInput struct {
	From string `query:"from" doc:"YYYY-MM-DD, inclusive. Defaults to 30 days before 'to'."`
	To   string `query:"to" doc:"YYYY-MM-DD, inclusive. Defaults to today."`
}

// Period is a resolved, validated date range, both ends inclusive.
type Period struct {
	From time.Time `json:"from"`
	To   time.Time `json:"to"`
}

// resolve turns query strings into a period ending today by default — the
// business's today, which the caller supplies — and starting defaultDays
// before its end.
func (in PeriodInput) resolve(today time.Time, defaultDays int) (Period, error) {
	to := today
	if in.To != "" {
		t, err := time.Parse(dateLayout, in.To)
		if err != nil {
			return Period{}, ErrInvalidDate
		}
		to = t
	}
	from := to.AddDate(0, 0, -defaultDays)
	if in.From != "" {
		f, err := time.Parse(dateLayout, in.From)
		if err != nil {
			return Period{}, ErrInvalidDate
		}
		from = f
	}
	if from.After(to) {
		return Period{}, ErrPeriodBackwards
	}
	if to.Sub(from) > MaxPeriodDays*24*time.Hour {
		return Period{}, ErrPeriodTooLong
	}
	return Period{From: from, To: to}, nil
}

// days lists every date in the period, so a daily series has a row for a quiet
// day instead of skipping it. A chart with gaps reads as "no data", not "no
// sales", and those mean different things to a shopkeeper.
func (p Period) days() []time.Time {
	var out []time.Time
	for d := p.From; !d.After(p.To); d = d.AddDate(0, 0, 1) {
		out = append(out, d)
	}
	return out
}

func dayKey(t time.Time) string { return t.UTC().Format(dateLayout) }

// mustTenant returns the caller's business. Every report runs behind the auth
// and tenant middleware, so a missing tenant is a wiring bug; it resolves to the
// nil UUID, which matches no rows, rather than panicking in a request.
func mustTenant(ctx context.Context) uuid.UUID {
	id, err := tenantID(ctx)
	if err != nil {
		return uuid.Nil
	}
	return id
}
