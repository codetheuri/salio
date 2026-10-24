package money

import (
	"encoding/json"
	"os"
	"testing"
)

// The phone parses and writes money itself (docs/10, D7). Both sides read
// these cases, so the two can never disagree on what "1500.5" means.
func TestMoneyMatchesSharedVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/money.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var vectors struct {
		Parse []struct {
			Text  string `json:"text"`
			Cents int64  `json:"cents"`
		} `json:"parse"`
		Invalid []string `json:"invalid"`
		Wire    []struct {
			Cents int64  `json:"cents"`
			Text  string `json:"text"`
		} `json:"wire"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatalf("parsing the shared vectors: %v", err)
	}

	for _, c := range vectors.Parse {
		got, err := Parse(c.Text)
		if err != nil || int64(got) != c.Cents {
			t.Errorf("Parse(%q) = %d, %v; want %d", c.Text, got, err, c.Cents)
		}
	}
	for _, text := range vectors.Invalid {
		if got, err := Parse(text); err == nil {
			t.Errorf("Parse(%q) = %d; want an error", text, got)
		}
	}
	for _, c := range vectors.Wire {
		if got := Amount(c.Cents).String(); got != c.Text {
			t.Errorf("Amount(%d).String() = %q; want %q", c.Cents, got, c.Text)
		}
	}
}
