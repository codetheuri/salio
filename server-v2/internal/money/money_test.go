package money_test

import (
	"encoding/json"
	"regexp"
	"testing"

	"github.com/danielgtaylor/huma/v2"

	"salio/server-v2/internal/money"
)

func TestParseAndString_RoundTrip(t *testing.T) {
	cases := []struct {
		in    string
		minor int64
		out   string
	}{
		{"0", 0, "0.00"},
		{"1500", 150000, "1500.00"},
		{"1500.5", 150050, "1500.50"},
		{"1500.50", 150050, "1500.50"},
		{"0.07", 7, "0.07"},
		{"0.1", 10, "0.10"},
		{".5", 50, "0.50"},
		{"-250.25", -25025, "-250.25"},
		{"9999999999.99", 999999999999, "9999999999.99"},
	}

	for _, c := range cases {
		got, err := money.Parse(c.in)
		if err != nil {
			t.Errorf("Parse(%q): %v", c.in, err)
			continue
		}
		if got.Minor() != c.minor {
			t.Errorf("Parse(%q) = %d cents, want %d", c.in, got.Minor(), c.minor)
		}
		if got.String() != c.out {
			t.Errorf("Parse(%q).String() = %q, want %q", c.in, got.String(), c.out)
		}
	}
}

func TestParse_Rejects(t *testing.T) {
	// "1.005" is the important one: a third decimal place cannot be represented,
	// and rounding it away silently would store an amount the user did not enter.
	for _, in := range []string{"", "abc", "1.005", "1.2.3", "1,500", "--5", "1e3"} {
		if got, err := money.Parse(in); err == nil {
			t.Errorf("Parse(%q) = %v, want an error", in, got)
		}
	}
}

// TestSum_IsExact is the whole reason this type exists. The same additions in
// float64 do not produce 0.30 or 100.00.
func TestSum_IsExact(t *testing.T) {
	a, _ := money.Parse("0.10")
	b, _ := money.Parse("0.20")
	if sum := a + b; sum.String() != "0.30" {
		t.Errorf("0.10 + 0.20 = %s, want 0.30", sum)
	}

	// A thousand ten-cent debts.
	var total money.Amount
	ten, _ := money.Parse("0.10")
	for range 1000 {
		total += ten
	}
	if total.String() != "100.00" {
		t.Errorf("1000 x 0.10 = %s, want 100.00", total)
	}

	// And the balance formula the whole product rests on.
	debt, _ := money.Parse("1500.55")
	paid, _ := money.Parse("1200.35")
	if bal := debt - paid; bal.String() != "300.20" {
		t.Errorf("balance = %s, want 300.20", bal)
	}
}

func TestJSON_IsAStringNotAFloat(t *testing.T) {
	amount, _ := money.Parse("1500.50")

	encoded, err := json.Marshal(map[string]any{"amount": amount})
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(encoded) != `{"amount":"1500.50"}` {
		t.Errorf("got %s, want a quoted decimal string", encoded)
	}

	var back struct {
		Amount money.Amount `json:"amount"`
	}
	if err := json.Unmarshal(encoded, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if back.Amount != amount {
		t.Errorf("round trip gave %s, want %s", back.Amount, amount)
	}
}

// TestJSON_AcceptsABareNumber keeps older clients working, without routing the
// value through a float.
func TestJSON_AcceptsABareNumber(t *testing.T) {
	var v struct {
		Amount money.Amount `json:"amount"`
	}
	if err := json.Unmarshal([]byte(`{"amount":1500.50}`), &v); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if v.Amount.String() != "1500.50" {
		t.Errorf("got %s, want 1500.50", v.Amount)
	}
}

func TestScan_HandlesWhatTheDriverReturns(t *testing.T) {
	for _, src := range []any{"1500.50", []byte("1500.50")} {
		var a money.Amount
		if err := a.Scan(src); err != nil {
			t.Errorf("Scan(%T): %v", src, err)
			continue
		}
		if a.String() != "1500.50" {
			t.Errorf("Scan(%T) = %s, want 1500.50", src, a)
		}
	}

	var zero money.Amount
	if err := zero.Scan(nil); err != nil || zero != 0 {
		t.Errorf("Scan(nil) = %v, %v", zero, err)
	}

	// A float has already lost precision by the time it reaches Scan, so it is
	// refused rather than silently accepted.
	var f money.Amount
	if err := f.Scan(1500.50); err == nil {
		t.Error("Scan(float64) should be refused")
	}
}

func TestValue_IsExactText(t *testing.T) {
	a, _ := money.Parse("0.07")
	v, err := a.Value()
	if err != nil {
		t.Fatalf("Value: %v", err)
	}
	if v != "0.07" {
		t.Errorf("Value() = %v, want \"0.07\"", v)
	}
}

// TestSchema_DeclaresAStringNotAnInteger is the regression test for a defect
// that unit tests calling the service layer directly cannot see: Huma
// generates request-body validation from a type's Go kind unless told
// otherwise, and Amount's underlying kind is int64. Without Schema()
// implementing huma.SchemaProvider, a real HTTP request carrying the
// documented decimal string is rejected by Huma itself — "expected integer" —
// before UnmarshalJSON or any handler code ever runs.
func TestSchema_DeclaresAStringNotAnInteger(t *testing.T) {
	var a money.Amount
	provider, ok := any(a).(huma.SchemaProvider)
	if !ok {
		t.Fatal("money.Amount does not implement huma.SchemaProvider")
	}

	schema := provider.Schema(huma.NewMapRegistry("#/components/schemas/", huma.DefaultSchemaNamer))
	if schema.Type != huma.TypeString {
		t.Errorf("schema type = %q, want %q", schema.Type, huma.TypeString)
	}

	re, err := regexp.Compile(schema.Pattern)
	if err != nil {
		t.Fatalf("schema pattern does not compile: %v", err)
	}
	for _, valid := range []string{"0.00", "1500.50", "-250.25", "1000"} {
		if !re.MatchString(valid) {
			t.Errorf("pattern rejects a value MarshalJSON can produce: %q", valid)
		}
	}
}

func TestFormatted_SeparatesThousandsWithoutRounding(t *testing.T) {
	for in, want := range map[string]string{
		"0.00": "0.00", "5.00": "5.00", "999.99": "999.99", "1000.00": "1,000.00",
		"1234567.50": "1,234,567.50", "-2500.10": "-2,500.10",
	} {
		a, err := money.Parse(in)
		if err != nil {
			t.Fatalf("Parse(%q): %v", in, err)
		}
		if got := a.Formatted(); got != want {
			t.Errorf("Formatted(%s) = %q, want %q", in, got, want)
		}
	}
}
