package reports

import (
	"encoding/json"
	"os"
	"testing"
	"time"

	"salio/server-v2/internal/money"
)

// The phone works out dues itself, offline, for its filters and the Today
// list. Both sides read these cases, so "overdue" means the same on both.
func TestDuesMatchSharedVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/dues.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var vectors struct {
		Cases []struct {
			Name       string `json:"name"`
			AsOf       string `json:"as_of"`
			WithinDays int    `json:"within_days"`
			Lines      []struct {
				Type  string  `json:"type"`
				Cents int64   `json:"cents"`
				Date  string  `json:"date"`
				Due   *string `json:"due"`
			} `json:"lines"`
			Total       int64   `json:"total"`
			Overdue     int64   `json:"overdue"`
			DueSoon     int64   `json:"due_soon"`
			EarliestDue *string `json:"earliest_due"`
			NextDue     *string `json:"next_due"`
		} `json:"cases"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatalf("parsing the shared vectors: %v", err)
	}
	day := func(s string) time.Time {
		d, err := time.Parse(time.DateOnly, s)
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	dayOf := func(d *time.Time) *string {
		if d == nil {
			return nil
		}
		s := d.Format(time.DateOnly)
		return &s
	}
	same := func(a, b *string) bool { return (a == nil && b == nil) || (a != nil && b != nil && *a == *b) }

	for _, c := range vectors.Cases {
		var lines []ledgerLine
		for _, l := range c.Lines {
			line := ledgerLine{charge: l.Type == "debt", amount: money.Amount(l.Cents), date: day(l.Date)}
			if l.Due != nil {
				due := day(*l.Due)
				line.due = &due
			}
			lines = append(lines, line)
		}
		s := summariseDue(fifo(lines), day(c.AsOf), c.WithinDays)
		if int64(s.total) != c.Total || int64(s.overdue) != c.Overdue || int64(s.dueSoon) != c.DueSoon ||
			!same(dayOf(s.earliestDue), c.EarliestDue) || !same(dayOf(s.nextDue), c.NextDue) {
			t.Errorf("%s: got total %d overdue %d due soon %d earliest %v next %v",
				c.Name, s.total, s.overdue, s.dueSoon, dayOf(s.earliestDue), dayOf(s.nextDue))
		}
	}
}
