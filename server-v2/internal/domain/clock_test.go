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
