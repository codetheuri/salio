package domain

import (
	"errors"
	"strings"
	"time"
	_ "time/tzdata" // the zone database, compiled in: minimal containers often lack /usr/share/zoneinfo
)

// DefaultTimeZone is the zone a business gets until it says otherwise — where
// Salio's shops are today.
//
// Each business carries its own zone (businesses.time_zone) because a calendar
// date — the day a debt was recorded, the date on a purchase order — is a fact
// about the shop's day, not the server's. Computed in UTC, three hours behind
// Kenya, anything recorded between midnight and three in the morning was dated
// the day before: a purchase order generated at 01:15 on the 13th read
// "12 Oct", in front of a supplier.
//
// Only *dates* depend on the zone. Instants — created_at, sync cursors, field
// versions — stay in UTC everywhere.
const DefaultTimeZone = "Africa/Nairobi"

// ErrInvalidTimeZone is returned for a zone name that is not in the IANA
// database, such as "EAT" or "+03:00".
var ErrInvalidTimeZone = errors.New(`time_zone must be an IANA zone name such as "Africa/Nairobi"`)

// LoadTimeZone resolves an IANA zone name.
//
// "Local" and the empty string are refused even though time.LoadLocation
// accepts them: both mean "whatever the server happens to be set to", which is
// exactly the dependence on the server's clock a per-business zone removes.
func LoadTimeZone(name string) (*time.Location, error) {
	name = strings.TrimSpace(name)
	if name == "" || name == "Local" {
		return nil, ErrInvalidTimeZone
	}
	loc, err := time.LoadLocation(name)
	if err != nil {
		return nil, ErrInvalidTimeZone
	}
	return loc, nil
}

// ZoneOrDefault resolves a stored zone, falling back to DefaultTimeZone.
//
// Every write path validates the name, so the fallback only covers a row
// written around the API; a wrong-by-three-hours date is a better outcome
// there than refusing to record a debt.
func ZoneOrDefault(name string) *time.Location {
	if loc, err := LoadTimeZone(name); err == nil {
		return loc
	}
	return defaultLocation
}

var defaultLocation = func() *time.Location {
	loc, err := time.LoadLocation(DefaultTimeZone)
	if err != nil {
		// Unreachable with time/tzdata compiled in; a fixed offset is the
		// right fallback for a zone with no daylight saving.
		return time.FixedZone("EAT", 3*60*60)
	}
	return loc
}()

// DateIn is the calendar date at instant t in loc, as a midnight-UTC value.
//
// Midnight UTC because that is how a DATE column round-trips through the driver
// and how time.Parse("2006-01-02") reads a date a client sends. Mixing the two
// representations is what makes a day appear to change when it is compared.
func DateIn(t time.Time, loc *time.Location) time.Time {
	y, m, d := t.In(loc).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}
