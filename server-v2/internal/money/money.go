// Package money represents currency amounts exactly.
//
// Salio's v1 backend carried amounts as float64. That is wrong for a ledger, and
// not in a theoretical way: a balance here is SUM(debt) - SUM(payment) over every
// row a customer has, and binary floating point cannot represent most two-decimal
// values. 0.1 + 0.2 is 0.30000000000000004; accumulate that over a few hundred
// entries and a shopkeeper's balance disagrees with their paper notebook by a
// shilling. In a product whose entire purpose is being trusted more than the
// notebook, that is the worst possible bug.
//
// The database column was already exact — NUMERIC(12,2) — so the error entered
// only when Go read it. Amount holds minor units (cents) in an int64, which is
// exact for every value the column can hold, and converts at the edges.
//
// int64 rather than a decimal library: Salio deals in one currency with two
// decimal places, addition and subtraction only. A general decimal type would
// bring arbitrary precision and rounding modes to a problem that has neither.
package money

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
)

// minorUnits is the number of minor units in one major unit. KES, like most
// currencies, has 100 cents to the shilling.
const minorUnits = 100

// Amount is a monetary value in minor units.
type Amount int64

// FromMinor builds an Amount from cents.
func FromMinor(n int64) Amount { return Amount(n) }

// Minor returns the value in cents.
func (a Amount) Minor() int64 { return int64(a) }

// IsPositive reports whether the amount is greater than zero. Every transaction
// amount must be: direction is carried by the transaction's type, not its sign.
func (a Amount) IsPositive() bool { return a > 0 }

// String renders the amount with two decimal places and no currency symbol,
// which is also the form PostgreSQL parses into NUMERIC.
func (a Amount) String() string {
	neg := a < 0
	n := int64(a)
	if neg {
		n = -n
	}
	s := fmt.Sprintf("%d.%02d", n/minorUnits, n%minorUnits)
	if neg {
		return "-" + s
	}
	return s
}

// Parse reads a decimal string such as "1500" or "1500.50".
//
// It parses the digits itself rather than going through a float. strconv.ParseFloat
// would reintroduce exactly the imprecision this type exists to avoid — the
// string "0.07" does not survive the round trip.
func Parse(s string) (Amount, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("money: empty amount")
	}

	neg := false
	switch s[0] {
	case '-':
		neg, s = true, s[1:]
	case '+':
		s = s[1:]
	}
	// A sign on its own. Checked again because the check above ran before the
	// sign came off: without it, "-" read as zero.
	if s == "" {
		return 0, fmt.Errorf("money: a sign with no amount")
	}

	whole, frac, hasFrac := strings.Cut(s, ".")
	if whole == "" {
		whole = "0"
	}

	// Digits only. strconv.ParseInt accepts its own leading sign, so without this
	// "--5" would parse as -5 and then be negated back to a positive 5.
	if !isDigits(whole) || (hasFrac && !isDigits(frac)) {
		return 0, fmt.Errorf("money: %q is not a valid amount", s)
	}

	major, err := strconv.ParseInt(whole, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("money: %q is not a valid amount", s)
	}

	var minor int64
	if hasFrac {
		// Pad or reject rather than round: "1.5" means 1.50, but "1.005" is a
		// precision this currency cannot hold, and silently discarding the digit
		// would make the stored amount differ from the one submitted.
		switch len(frac) {
		case 1:
			frac += "0"
		case 2:
		default:
			return 0, fmt.Errorf("money: %q has more than two decimal places", s)
		}
		if minor, err = strconv.ParseInt(frac, 10, 64); err != nil {
			return 0, fmt.Errorf("money: %q is not a valid amount", s)
		}
	}

	if major > (math.MaxInt64-minor)/minorUnits {
		return 0, fmt.Errorf("money: %q is out of range", s)
	}

	total := major*minorUnits + minor
	if neg {
		total = -total
	}
	return Amount(total), nil
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// MarshalJSON renders the amount as a JSON string.
//
// A string, not a number: JSON numbers are IEEE-754 doubles in most parsers,
// including Dart's, so emitting 1500.50 as a bare number hands the client back
// the imprecision this package removes.
func (a Amount) MarshalJSON() ([]byte, error) {
	return json.Marshal(a.String())
}

// UnmarshalJSON accepts a string, and a number for tolerance with clients that
// have not been updated yet.
func (a *Amount) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err == nil {
		parsed, err := Parse(s)
		if err != nil {
			return err
		}
		*a = parsed
		return nil
	}

	// A bare JSON number. Re-rendered through its decimal text rather than read
	// as a float, so the value the client actually wrote is what gets stored.
	var raw json.Number
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("money: expected a decimal string, got %s", data)
	}
	parsed, err := Parse(raw.String())
	if err != nil {
		return err
	}
	*a = parsed
	return nil
}

// Scan reads a NUMERIC column.
//
// The driver may hand back a string, bytes, or an integer depending on the
// column and the query; all three arrive here as decimal text and are parsed the
// same way. A float64 case is deliberately absent — accepting one would mean the
// value had already lost precision before this package saw it, and failing
// loudly is better than storing a number that is quietly wrong.
func (a *Amount) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*a = 0
		return nil
	case int64:
		*a = Amount(v * minorUnits)
		return nil
	case []byte:
		return a.parseInto(string(v))
	case string:
		return a.parseInto(v)
	default:
		return fmt.Errorf("money: cannot scan %T into an Amount", src)
	}
}

func (a *Amount) parseInto(s string) error {
	parsed, err := Parse(s)
	if err != nil {
		return err
	}
	*a = parsed
	return nil
}

// Value writes the amount as decimal text for PostgreSQL to parse into NUMERIC.
func (a Amount) Value() (driver.Value, error) { return a.String(), nil }

// GormDataType tells GORM's migrator the column type, so a model-driven schema
// matches the hand-written one.
func (Amount) GormDataType() string { return "numeric(12,2)" }

// Schema implements huma.SchemaProvider, so a field of type Amount is
// documented and validated as a decimal string — matching what MarshalJSON
// actually produces and UnmarshalJSON actually accepts.
//
// Without this, Huma's reflection-based schema builder falls back to the
// underlying Go kind of Amount, which is int64, and generates {"type":
// "integer"}. Every request carrying an amount as the documented decimal
// string — "1500.50" — would then be rejected by Huma's own request
// validation, "expected integer", before the handler or UnmarshalJSON ever
// saw it. json.Marshaler and json.Unmarshaler control encoding; they say
// nothing about the schema Huma validates against, so the two must agree
// explicitly.
func (Amount) Schema(r huma.Registry) *huma.Schema {
	return &huma.Schema{
		Type:        huma.TypeString,
		Pattern:     `^-?[0-9]+(\.[0-9]{1,2})?$`,
		Examples:    []any{"1500.50"},
		Description: "A decimal amount with at most two decimal places, as a string.",
	}
}

// Formatted renders an amount for people to read: thousands separated, two
// decimal places, "-" for a negative. 1234567.5 becomes "1,234,567.50".
//
// Works from String's exact decimal text rather than converting to a float,
// so formatting can never round a value it is only meant to display.
func (a Amount) Formatted() string {
	s := a.String()

	neg := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")
	whole, frac, _ := strings.Cut(s, ".")

	var b strings.Builder
	for i, digit := range whole {
		if i > 0 && (len(whole)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(digit)
	}
	out := b.String() + "." + frac
	if neg {
		return "-" + out
	}
	return out
}
