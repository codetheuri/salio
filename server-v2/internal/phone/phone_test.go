package phone

import (
	"encoding/json"
	"os"
	"testing"
)

type vectors struct {
	Normalize []struct {
		Text string `json:"text"`
		E164 string `json:"e164"`
	} `json:"normalize"`
	Invalid []string `json:"invalid"`
}

func load(t *testing.T) vectors {
	t.Helper()
	raw, err := os.ReadFile("../../../testdata/shared/phone.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var v vectors
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatalf("parsing the shared vectors: %v", err)
	}
	return v
}

// The app normalises numbers itself, offline. Both sides read these cases.
func TestNormalizeMatchesSharedVectors(t *testing.T) {
	v := load(t)
	for _, c := range v.Normalize {
		if got, err := Normalize(c.Text); err != nil || got != c.E164 {
			t.Errorf("Normalize(%q) = %q, %v; want %q", c.Text, got, err, c.E164)
		}
	}
	for _, text := range v.Invalid {
		if got, err := Normalize(text); err == nil {
			t.Errorf("Normalize(%q) = %q; want ErrInvalid", text, got)
		}
	}
}

func TestOptional(t *testing.T) {
	blank := "  "
	if got, err := Optional(&blank); got != nil || err != nil {
		t.Errorf("Optional(blank) = %v, %v; want nil, nil", got, err)
	}
	if got, err := Optional(nil); got != nil || err != nil {
		t.Errorf("Optional(nil) = %v, %v; want nil, nil", got, err)
	}
	bad := "abc"
	if _, err := Optional(&bad); err == nil {
		t.Error("Optional(abc) accepted")
	}
}
