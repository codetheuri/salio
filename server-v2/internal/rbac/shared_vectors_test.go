package rbac

import (
	"encoding/json"
	"os"
	"slices"
	"testing"

	"salio/server-v2/internal/domain"
)

// The phone mirrors the role table until the server sends each user's
// permissions (docs/10, B5). Both sides compare against the same file, so a
// grant changed here and not in mobile-v2 fails one of the two test suites.
func TestPermissionsMatchSharedVectors(t *testing.T) {
	raw, err := os.ReadFile("../../../testdata/shared/role_permissions.json")
	if err != nil {
		t.Fatalf("reading the shared vectors: %v", err)
	}
	var vectors struct {
		Owner []string `json:"owner"`
		Staff []string `json:"staff"`
	}
	if err := json.Unmarshal(raw, &vectors); err != nil {
		t.Fatalf("parsing the shared vectors: %v", err)
	}

	for role, want := range map[domain.Role][]string{
		domain.RoleOwner: vectors.Owner,
		domain.RoleStaff: vectors.Staff,
	} {
		got := slices.Clone(PermissionsFor(role))
		slices.Sort(got)
		if !slices.Equal(got, want) {
			t.Errorf("%s: rbac grants %v,\nbut testdata/shared/role_permissions.json says %v", role, got, want)
		}
	}
}
