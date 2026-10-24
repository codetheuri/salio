package domain

import (
	"errors"
	"testing"
	"time"
)

func TestDateIn_IsTheShopsDateNotUTCs(t *testing.T) {
	// The concrete failure this exists to prevent: at 01:15 in Ruiru it is
	// 22:15 the previous day in UTC.
	at := time.Date(2026, 10, 12, 22, 15, 0, 0, time.UTC)

	got := DateIn(at, ZoneOrDefault(DefaultTimeZone))
	if want := time.Date(2026, 10, 13, 0, 0, 0, 0, time.UTC); !got.Equal(want) {
		t.Fatalf("DateIn(22:15 UTC on the 12th, Nairobi) = %s, want %s", got, want)
	}
	// Midnight UTC, the shape a DATE column and time.Parse("2006-01-02") use,
	// so comparing it with a stored date never shifts the day.
	if got.Location() != time.UTC {
		t.Fatalf("DateIn returned %s, want a midnight-UTC value", got)
	}
}

func TestDateIn_FollowsTheBusinessZone(t *testing.T) {
	// The same instant is three different days around the world — which is
	// why the zone belongs to the business, not the server.
	at := time.Date(2026, 10, 12, 23, 30, 0, 0, time.UTC)
	cases := map[string]int{
		"Africa/Nairobi":    13, // UTC+3
		"Africa/Lagos":      13, // UTC+1
		"Europe/London":     13, // UTC+1 in October (summer time)
		"America/Sao_Paulo": 12, // UTC-3
		"UTC":               12,
	}
	for zone, wantDay := range cases {
		loc, err := LoadTimeZone(zone)
		if err != nil {
			t.Fatalf("LoadTimeZone(%q): %v", zone, err)
		}
		if got := DateIn(at, loc).Day(); got != wantDay {
			t.Errorf("in %s, 23:30 UTC on the 12th is day %d, want %d", zone, got, wantDay)
		}
	}
}

func TestLoadTimeZone_RefusesWhatIsNotAnIANAName(t *testing.T) {
	for _, name := range []string{"", "  ", "Local", "EAT", "+03:00", "Africa/Narobi"} {
		if _, err := LoadTimeZone(name); !errors.Is(err, ErrInvalidTimeZone) {
			t.Errorf("LoadTimeZone(%q) = %v, want ErrInvalidTimeZone", name, err)
		}
	}
}

func TestZoneOrDefault_FallsBackToNairobi(t *testing.T) {
	if got := ZoneOrDefault("not a zone").String(); got != DefaultTimeZone {
		t.Fatalf("ZoneOrDefault(bad) = %s, want %s", got, DefaultTimeZone)
	}
}

// A due date is a calendar day; a record's date may be a moment (from a
// phone) or a day (from a form). "Due today" is never "due before it was
// recorded", in any zone, at any hour.
func TestDueBefore_ComparesDaysInTheShopsZone(t *testing.T) {
	nairobi, _ := time.LoadLocation("Africa/Nairobi")
	bogota, _ := time.LoadLocation("America/Bogota") // UTC-5
	day := func(y int, m time.Month, d int) time.Time { return time.Date(y, m, d, 0, 0, 0, 0, time.UTC) }

	cases := []struct {
		name string
		due  time.Time
		at   time.Time
		loc  *time.Location
		want bool
	}{
		{"due today, recorded mid-morning", day(2026, 10, 24), time.Date(2026, 10, 24, 10, 15, 0, 0, nairobi), nairobi, false},
		{"due today, recorded at 01:00 (the day before in UTC)", day(2026, 10, 25), time.Date(2026, 10, 25, 1, 0, 0, 0, nairobi), nairobi, false},
		{"due today, late evening west of UTC (tomorrow in UTC)", day(2026, 10, 24), time.Date(2026, 10, 24, 21, 0, 0, 0, bogota), bogota, false},
		{"due yesterday", day(2026, 10, 23), time.Date(2026, 10, 24, 10, 15, 0, 0, nairobi), nairobi, true},
		{"a day from a form, due that day", day(2026, 10, 24), day(2026, 10, 24), bogota, false},
		{"a day from a form, due the day before", day(2026, 10, 23), day(2026, 10, 24), nairobi, true},
	}
	for _, c := range cases {
		if got := DueBefore(c.due, c.at, c.loc); got != c.want {
			t.Errorf("%s: DueBefore = %v, want %v", c.name, got, c.want)
		}
	}
}
