package payment_test

import (
	"encoding/json"
	"os"
	"testing"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/payment"
)

// The phone checks a reference as it is typed. Both sides read these cases.
func TestReferenceMatchesSharedVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/payment_reference.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var v struct {
		Valid []struct {
			Method string  `json:"method"`
			Text   string  `json:"text"`
			Stored *string `json:"stored"`
		} `json:"valid"`
		Invalid []struct {
			Method string `json:"method"`
			Text   string `json:"text"`
		} `json:"invalid"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	for _, c := range v.Valid {
		text := c.Text
		got, err := payment.Reference(domain.PaymentMethod(c.Method), &text)
		if err != nil || (got == nil) != (c.Stored == nil) || (got != nil && *got != *c.Stored) {
			t.Errorf("Reference(%s, %q) = %v, %v; want %v", c.Method, c.Text, got, err, c.Stored)
		}
	}
	for _, c := range v.Invalid {
		text := c.Text
		if got, err := payment.Reference(domain.PaymentMethod(c.Method), &text); err == nil {
			t.Errorf("Reference(%s, %q) = %v; want an error", c.Method, c.Text, got)
		}
	}
}
