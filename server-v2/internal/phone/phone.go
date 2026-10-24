// Package phone stores every phone number in one form (B15): E.164, read as
// Kenyan unless it says otherwise.
//
// Before this, "0712 345 678", "0712345678" and "+254712345678" were three
// different customers in one shop, and three different sign-ins. Picking
// customers from the phone's contacts makes every one of those forms common,
// because contacts store numbers however they were typed.
//
// The same rule runs in three places, which must agree: here (REST, sync, the
// v1 import), in the app (lib/core/phone), and in migration 00010's SQL
// function, which converted the numbers already stored.
// testdata/shared/phone.json pins all three to the same cases.
package phone

import (
	"errors"
	"strings"
)

// ErrInvalid is a number that cannot be read as a phone number.
var ErrInvalid = errors.New("not a phone number: use 07XX XXX XXX, 01XX XXX XXX or +country code")

// Normalize returns the E.164 form of a phone number.
//
// Kenyan numbers are recognised in every form people write them:
// 0712345678, 712345678, 254712345678, +254712345678 and 00254712345678
// all become +254712345678. A bare nine digits is Kenyan only when it starts
// with 7 or 1, the mobile ranges; anything else that short is too ambiguous
// to guess. Other countries need their code, with + or 00.
//
// Spaces, dashes, dots and brackets are ignored. Anything else, letters
// included, is ErrInvalid.
func Normalize(raw string) (string, error) {
	var b strings.Builder
	for i, r := range strings.TrimSpace(raw) {
		switch {
		case r >= '0' && r <= '9':
			b.WriteRune(r)
		case r == '+' && i == 0:
			b.WriteRune(r)
		case r == ' ' || r == '-' || r == '.' || r == '(' || r == ')':
		default:
			return "", ErrInvalid
		}
	}
	d := b.String()

	switch {
	case strings.HasPrefix(d, "+254"):
		return kenyan(d[4:])
	case strings.HasPrefix(d, "00254"):
		return kenyan(d[5:])
	case strings.HasPrefix(d, "254") && len(d) == 12:
		return kenyan(d[3:])
	case strings.HasPrefix(d, "0") && !strings.HasPrefix(d, "00"):
		return kenyan(d[1:])
	case len(d) == 9 && (d[0] == '7' || d[0] == '1'):
		return kenyan(d)
	case strings.HasPrefix(d, "+"):
		return international(d[1:])
	case strings.HasPrefix(d, "00"):
		return international(d[2:])
	}
	return "", ErrInvalid
}

// Optional normalises a number that may be absent: nil or blank is nil.
func Optional(raw *string) (*string, error) {
	if raw == nil || strings.TrimSpace(*raw) == "" {
		return nil, nil
	}
	n, err := Normalize(*raw)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// kenyan takes the nine digits after the country code or the leading 0.
func kenyan(n string) (string, error) {
	if len(n) != 9 || n[0] == '0' || !digits(n) {
		return "", ErrInvalid
	}
	return "+254" + n, nil
}

// international takes the digits after + or 00: a country code that does
// not start with 0, and E.164's 8 to 15 digits in all.
func international(n string) (string, error) {
	if len(n) < 8 || len(n) > 15 || n[0] == '0' || !digits(n) {
		return "", ErrInvalid
	}
	return "+" + n, nil
}

func digits(s string) bool {
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
