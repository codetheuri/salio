package rbac_test

import (
	"context"
	"slices"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/testsupport"
)

func TestSeed_IsIdempotent(t *testing.T) {
	db := testsupport.Connect(t)
	ctx := context.Background()

	for i := range 3 {
		if err := rbac.Seed(ctx, db); err != nil {
			t.Fatalf("seed %d: %v", i, err)
		}
	}

	var perms, roles, grants int64
	db.Model(&authz.PermissionRecord{}).Count(&perms)
	db.Model(&authz.Role{}).Count(&roles)
	db.Model(&authz.RolePermission{}).Count(&grants)

	if perms != int64(len(rbac.Permissions)) {
		t.Errorf("%d permissions, want %d", perms, len(rbac.Permissions))
	}
	if roles != 2 {
		t.Errorf("%d roles, want 2", roles)
	}
	want := int64(len(rbac.PermissionsFor(domain.RoleOwner)) + len(rbac.PermissionsFor(domain.RoleStaff)))
	if grants != want {
		t.Errorf("%d grants, want %d", grants, want)
	}
}

// TestStaffCannotDoOwnerOnlyThings pins the roles matrix. If someone widens a
// staff grant, this fails and they have to mean it.
func TestStaffCannotDoOwnerOnlyThings(t *testing.T) {
	staff := rbac.PermissionsFor(domain.RoleStaff)

	ownerOnly := []string{
		rbac.PermCustomersDelete,
		rbac.PermTransactionsVoid,
		rbac.PermStaffManage,
		rbac.PermBusinessUpdate,
	}
	for _, p := range ownerOnly {
		if slices.Contains(staff, p) {
			t.Errorf("staff have %q, which is owner-only", p)
		}
	}

	// And the things they must have, or the app is unusable for them.
	for _, p := range []string{
		rbac.PermCustomersCreate, rbac.PermTransactionsCreate,
		rbac.PermSyncPull, rbac.PermSyncPush,
	} {
		if !slices.Contains(staff, p) {
			t.Errorf("staff lack %q, which they need for day-to-day work", p)
		}
	}
}

// TestOwnerGetsEveryPermission: owners are defined as "everything", so a newly
// declared permission must reach them without anyone editing a second list.
func TestOwnerGetsEveryPermission(t *testing.T) {
	owner := rbac.PermissionsFor(domain.RoleOwner)
	if len(owner) != len(rbac.Permissions) {
		t.Fatalf("owner has %d permissions, want all %d", len(owner), len(rbac.Permissions))
	}
	for _, p := range rbac.Permissions {
		if !slices.Contains(owner, p.Name) {
			t.Errorf("owner is missing %q", p.Name)
		}
	}
}

// TestAssignRole_GrantsWhatTheRoleGrants goes through Tusk's own evaluator, so
// it verifies the wiring a request actually uses rather than the tables.
func TestAssignRole_GrantsWhatTheRoleGrants(t *testing.T) {
	db := testsupport.Connect(t)
	ctx := context.Background()

	if err := rbac.Seed(ctx, db); err != nil {
		t.Fatalf("seed: %v", err)
	}

	business := domain.Business{Name: "Test Shop"}
	if err := tenant.Unscoped(db.WithContext(ctx)).Create(&business).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	tctx := tenant.WithTenant(ctx, business.ID)

	owner := domain.User{Name: "O", Phone: "0711000001", PasswordHash: "x", Role: domain.RoleOwner}
	staff := domain.User{Name: "S", Phone: "0711000002", PasswordHash: "x", Role: domain.RoleStaff}
	for _, u := range []*domain.User{&owner, &staff} {
		if err := db.WithContext(tctx).Create(u).Error; err != nil {
			t.Fatalf("create user: %v", err)
		}
		if err := rbac.AssignRole(tctx, db, u.ID, u.Role); err != nil {
			t.Fatalf("assign role: %v", err)
		}
	}

	eval := authz.NewEvaluator(db)

	for _, c := range []struct {
		name string
		user domain.User
		perm string
		want bool
	}{
		{"owner may void", owner, rbac.PermTransactionsVoid, true},
		{"owner may manage staff", owner, rbac.PermStaffManage, true},
		{"staff may record a debt", staff, rbac.PermTransactionsCreate, true},
		{"staff may not void", staff, rbac.PermTransactionsVoid, false},
		{"staff may not delete a customer", staff, rbac.PermCustomersDelete, false},
		{"staff may not manage staff", staff, rbac.PermStaffManage, false},
	} {
		got, err := eval.UserHasPermission(ctx, c.user.ID, c.perm)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got != c.want {
			t.Errorf("%s: got %v, want %v", c.name, got, c.want)
		}
	}
}

// AssignRole must replace, not accumulate: demoting an owner has to remove what
// they had.
func TestAssignRole_ReplacesTheOldRole(t *testing.T) {
	db := testsupport.Connect(t)
	ctx := context.Background()

	if err := rbac.Seed(ctx, db); err != nil {
		t.Fatalf("seed: %v", err)
	}
	business := domain.Business{Name: "Shop"}
	if err := tenant.Unscoped(db.WithContext(ctx)).Create(&business).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	tctx := tenant.WithTenant(ctx, business.ID)

	u := domain.User{Name: "U", Phone: "0711000003", PasswordHash: "x", Role: domain.RoleOwner}
	if err := db.WithContext(tctx).Create(&u).Error; err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := rbac.AssignRole(tctx, db, u.ID, domain.RoleOwner); err != nil {
		t.Fatalf("assign owner: %v", err)
	}
	if err := rbac.AssignRole(tctx, db, u.ID, domain.RoleStaff); err != nil {
		t.Fatalf("demote to staff: %v", err)
	}

	var links int64
	db.Model(&authz.UserRole{}).Where("user_id = ?", u.ID).Count(&links)
	if links != 1 {
		t.Errorf("user holds %d roles, want exactly 1", links)
	}

	eval := authz.NewEvaluator(db)
	if ok, _ := eval.UserHasPermission(ctx, u.ID, rbac.PermStaffManage); ok {
		t.Error("a demoted owner kept staff.manage")
	}
}
