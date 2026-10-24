package quantity

import (
	"encoding/json"
	"os"
	"testing"
)

// The phone parses and writes quantities itself. Both sides read these
// cases, so the two can never disagree on what "1.5" bags means.
func TestQuantityMatchesSharedVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/quantity.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var vectors struct {
		Parse []struct {
			Text        string `json:"text"`
			Thousandths int64  `json:"thousandths"`
		} `json:"parse"`
		Invalid []string `json:"invalid"`
		Wire    []struct {
			Thousandths int64  `json:"thousandths"`
			Text        string `json:"text"`
		} `json:"wire"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatalf("parsing the shared vectors: %v", err)
	}

	for _, c := range vectors.Parse {
		got, err := Parse(c.Text)
		if err != nil || int64(got) != c.Thousandths {
			t.Errorf("Parse(%q) = %d, %v; want %d", c.Text, got, err, c.Thousandths)
		}
	}
	for _, text := range vectors.Invalid {
		if got, err := Parse(text); err == nil {
			t.Errorf("Parse(%q) = %d; want an error", text, got)
		}
	}
	for _, c := range vectors.Wire {
		if got := Quantity(c.Thousandths).String(); got != c.Text {
			t.Errorf("Quantity(%d).String() = %q; want %q", c.Thousandths, got, c.Text)
		}
	}
}
