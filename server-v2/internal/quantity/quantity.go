// Package quantity is an exact count of goods, to three decimal places.
//
// Separate from money.Amount on purpose, though the two are built alike. They
// mean different things, they have different precision — a shop sells half a
// kilo of sugar, but nobody prices anything in thousandths of a shilling — and
// keeping them distinct types makes it a compile error to add a quantity to an
// amount.
//
// Exact for the same reason money is: a quantity multiplied by a price becomes a
// debt, and a float that rounds 0.1 + 0.2 is the wrong foundation for that.
package quantity

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
	"math"
	"strconv"
	"strings"

	"github.com/danielgtaylor/huma/v2"
)

// scale is thousandths: 1.5 is stored as 1500.
const scale = 1000

// Quantity is a count of goods in thousandths.
type Quantity int64

// FromUnits returns a whole-number quantity.
func FromUnits(n int64) Quantity { return Quantity(n * scale) }

func (q Quantity) IsPositive() bool { return q > 0 }

// String renders the shortest exact form: "2", "0.5", "1.25". A sale of two
// bags should read "2", not "2.000" — the trailing zeros are noise on a receipt.
func (q Quantity) String() string {
	neg := q < 0
	n := int64(q)
	if neg {
		n = -n
	}

	s := strconv.FormatInt(n/scale, 10)
	if frac := n % scale; frac != 0 {
		s += "." + strings.TrimRight(fmt.Sprintf("%03d", frac), "0")
	}
	if neg {
		return "-" + s
	}
	return s
}

// Parse reads a decimal with at most three places.
func Parse(s string) (Quantity, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0, fmt.Errorf("quantity: empty")
	}

	neg := false
	switch s[0] {
	case '-':
		neg, s = true, s[1:]
	case '+':
		s = s[1:]
	}
	if s == "" {
		return 0, fmt.Errorf("quantity: a sign with no number")
	}

	whole, frac, hasFrac := strings.Cut(s, ".")
	if whole == "" {
		whole = "0"
	}
	// Checked character by character before ParseInt, which would otherwise
	// accept its own leading sign and let "--5" through as 5.
	if !isDigits(whole) || (hasFrac && !isDigits(frac)) {
		return 0, fmt.Errorf("quantity: %q is not a valid number", s)
	}
	if hasFrac && len(frac) > 3 {
		return 0, fmt.Errorf("quantity: %q has more than three decimal places", s)
	}

	units, err := strconv.ParseInt(whole, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("quantity: %q is not a valid number", s)
	}

	var thousandths int64
	if hasFrac {
		frac += strings.Repeat("0", 3-len(frac))
		if thousandths, err = strconv.ParseInt(frac, 10, 64); err != nil {
			return 0, fmt.Errorf("quantity: %q is not a valid number", s)
		}
	}

	if units > (math.MaxInt64-thousandths)/scale {
		return 0, fmt.Errorf("quantity: %q is out of range", s)
	}
	total := units*scale + thousandths
	if neg {
		total = -total
	}
	return Quantity(total), nil
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

// MarshalJSON writes a string, matching money.Amount, so a client handles both
// the same way and never routes either through a float.
func (q Quantity) MarshalJSON() ([]byte, error) { return json.Marshal(q.String()) }

// UnmarshalJSON accepts a string or a bare number.
//
// A bare number is tolerated because a quantity of 2 is the commonest input
// there is, and a client sending {"quantity": 2} is not wrong in any way that
// matters. It goes through json.Number, so it is never a float either.
func (q *Quantity) UnmarshalJSON(data []byte) error {
	var s string
	if err := json.Unmarshal(data, &s); err != nil {
		var n json.Number
		if err := json.Unmarshal(data, &n); err != nil {
			return fmt.Errorf("quantity: expected a number or a decimal string, got %s", data)
		}
		s = n.String()
	}
	parsed, err := Parse(s)
	if err != nil {
		return err
	}
	*q = parsed
	return nil
}

// Scan reads NUMERIC as the exact text PostgreSQL sends. A float64 is refused:
// by the time a value arrives as one, its precision is already gone.
func (q *Quantity) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*q = 0
		return nil
	case int64:
		*q = Quantity(v * scale)
		return nil
	case []byte:
		return q.parseInto(string(v))
	case string:
		return q.parseInto(v)
	default:
		return fmt.Errorf("quantity: cannot scan %T into a Quantity", src)
	}
}

func (q *Quantity) parseInto(s string) error {
	parsed, err := Parse(s)
	if err != nil {
		return err
	}
	*q = parsed
	return nil
}

func (q Quantity) Value() (driver.Value, error) { return q.String(), nil }

func (Quantity) GormDataType() string { return "numeric(12,3)" }

// Schema declares the wire form to Huma.
//
// Without it Huma describes the type by its Go kind — an integer — and rejects
// "1.5" before a handler ever runs. money.Amount hit exactly this in Phase 5;
// it was invisible to every unit test and found only by a real HTTP request.
// Accepts either a number or a numeric string, matching UnmarshalJSON.
func (Quantity) Schema(r huma.Registry) *huma.Schema {
	return &huma.Schema{
		OneOf: []*huma.Schema{
			{Type: huma.TypeString, Pattern: `^[0-9]+(\.[0-9]{1,3})?$`},
			{Type: huma.TypeNumber},
		},
		Examples:    []any{"2", "0.5"},
		Description: "A count of goods, up to three decimal places.",
	}
}
