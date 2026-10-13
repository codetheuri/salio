package quantity

import (
	"encoding/json"
	"testing"
)

func TestParseAndString_RoundTrip(t *testing.T) {
	for in, want := range map[string]string{
		"2": "2", "2.000": "2", "0.5": "0.5", "1.25": "1.25", "0.001": "0.001",
		"10.10": "10.1", "+3": "3", " 4 ": "4",
	} {
		q, err := Parse(in)
		if err != nil {
			t.Fatalf("Parse(%q): %v", in, err)
		}
		if q.String() != want {
			t.Errorf("Parse(%q).String() = %q, want %q", in, q.String(), want)
		}
	}
}

func TestParse_RefusesWhatIsNotAQuantity(t *testing.T) {
	// "--5" is the case strconv.ParseInt would let through on its own, since
	// it accepts its own leading sign after ours was already stripped.
	for _, in := range []string{"", "abc", "1.2345", "--5", "1..2", "1.2.3", ".", "1e3"} {
		if _, err := Parse(in); err == nil {
			t.Errorf("Parse(%q) succeeded, want an error", in)
		}
	}
}

func TestJSON_AcceptsBothStringAndBareNumber(t *testing.T) {
	for _, raw := range []string{`"1.5"`, `1.5`, `2`} {
		var q Quantity
		if err := json.Unmarshal([]byte(raw), &q); err != nil {
			t.Fatalf("unmarshal %s: %v", raw, err)
		}
	}

	out, err := json.Marshal(FromUnits(2))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(out) != `"2"` {
		t.Fatalf("marshalled %s, want a string so no client parses it as a float", out)
	}
}

func TestScan_ReadsPostgresNumericTextAndRefusesFloats(t *testing.T) {
	var q Quantity
	if err := q.Scan([]byte("2.500")); err != nil || q.String() != "2.5" {
		t.Fatalf("Scan(2.500) = %v, %v", q, err)
	}
	if err := q.Scan(float64(1.5)); err == nil {
		t.Fatal("a float64 was accepted; its precision is already gone by then")
	}
}
