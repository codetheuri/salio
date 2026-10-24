package sales

import (
	"encoding/json"
	"os"
	"testing"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/quantity"
)

// The phone makes a credit sale's debt itself, offline, so the customer's
// balance moves at once. It must make the same row the server will: the same
// id and the same words. testdata/shared/sale_debt.json pins both sides.
func TestSharedVectors_SaleDebt(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/sale_debt.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		IDs []struct {
			Sale string `json:"sale"`
			Debt string `json:"debt"`
		} `json:"ids"`
		Descriptions []struct {
			Product  string `json:"product"`
			Quantity string `json:"quantity"`
			Want     string `json:"want"`
		} `json:"descriptions"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	if len(v.IDs) == 0 || len(v.Descriptions) == 0 {
		t.Fatal("no vectors read")
	}
	for _, c := range v.IDs {
		if got := domain.SaleDebtID(uuid.MustParse(c.Sale)).String(); got != c.Debt {
			t.Errorf("SaleDebtID(%s) = %s, want %s", c.Sale, got, c.Debt)
		}
	}
	for _, c := range v.Descriptions {
		q, err := quantity.Parse(c.Quantity)
		if err != nil {
			t.Fatalf("%q: %v", c.Quantity, err)
		}
		s := domain.Sale{ProductName: c.Product, Quantity: q}
		// As Record does it: Validate trims the name first.
		_ = Validate(&s)
		if got := DebtDescription(&s); got != c.Want {
			t.Errorf("DebtDescription(%q, %s) = %q, want %q", c.Product, c.Quantity, got, c.Want)
		}
	}
}
