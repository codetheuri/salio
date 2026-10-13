package domain

import (
	"testing"

	"github.com/google/uuid"
)

// TestSaleDebtID_MatchesTheReferenceVectors pins SaleDebtID to values computed
// by an independent implementation — Python's uuid.uuid5(namespace, str(sale_id))
// — so this test fails if the namespace or the hashing ever changes. Either
// change would give every existing credit sale's debt a new identity, and
// phones would hold a second copy of each.
//
// The mobile app's tests should assert these same two pairs.
func TestSaleDebtID_MatchesTheReferenceVectors(t *testing.T) {
	vectors := map[string]string{
		"01923f6e-8a4b-7c2d-9e1f-0a1b2c3d4e5f": "488ab63a-eb38-5137-960a-4e0e8dc1bb75",
		"00000000-0000-0000-0000-000000000000": "57e61219-d830-5d54-85ae-725ce9574418",
	}
	for sale, want := range vectors {
		if got := SaleDebtID(uuid.MustParse(sale)).String(); got != want {
			t.Errorf("SaleDebtID(%s) = %s, want %s", sale, got, want)
		}
	}
}
