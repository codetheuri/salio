// Package rbac holds Salio's permission catalogue and the two roles that grant
// them.
//
// Tusk's convention is a permissions.go per module. Salio keeps the whole matrix
// in one place instead, because the product has exactly two fixed roles and the
// interesting question is always "what can staff do that owners can, and what
// can they not" — a question a reader can only answer by seeing the matrix
// whole. Scattered across five modules it becomes something you reconstruct by
// grepping. Modules import these constants; nothing here imports a module.
//
// The role names match domain.Role and the users.role column deliberately. That
// column stays the source of truth — it syncs to the phone and drives what the
// app shows — and user_roles is written from it in the same transaction, because
// Tusk's permission checks read user_roles. AssignRole is the only place that
// writes it, so the two cannot drift by accident.
package rbac

import (
	"context"
	"fmt"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
)

// Permission names. Constants rather than raw strings so a typo is a compile
// error rather than a silent denial that looks like a permissions bug.
const (
	PermCustomersRead   = "customers.read"
	PermCustomersCreate = "customers.create"
	PermCustomersUpdate = "customers.update"
	PermCustomersDelete = "customers.delete"

	PermTransactionsRead   = "transactions.read"
	PermTransactionsCreate = "transactions.create"
	PermTransactionsVoid   = "transactions.void"

	PermStaffRead   = "staff.read"
	PermStaffManage = "staff.manage"

	PermBusinessRead   = "business.read"
	PermBusinessUpdate = "business.update"

	PermReportsRead = "reports.read"

	PermSyncPull = "sync.pull"
	PermSyncPush = "sync.push"

	PermSalesRead   = "sales.read"
	PermSalesCreate = "sales.create"
	PermSalesVoid   = "sales.void"

	PermStockRead    = "stock.read"
	PermStockRequest = "stock.request"

	PermPurchaseOrdersManage = "purchase_orders.manage"

	PermCustomersCreditLimit = "customers.credit_limit"

	PermSuppliersRead   = "suppliers.read"
	PermSuppliersManage = "suppliers.manage"
	PermSuppliersVoid   = "suppliers.void"
)

// Permissions is the full catalogue, synchronised into the database by Seed.
var Permissions = []authz.Permission{
	{Name: PermCustomersRead, Description: "View customers and their balances"},
	{Name: PermCustomersCreate, Description: "Add a customer"},
	{Name: PermCustomersUpdate, Description: "Edit a customer's details"},
	{Name: PermCustomersDelete, Description: "Delete a customer"},

	{Name: PermTransactionsRead, Description: "View a customer's ledger"},
	{Name: PermTransactionsCreate, Description: "Record a debt or a payment"},
	{Name: PermTransactionsVoid, Description: "Void a transaction"},

	{Name: PermStaffRead, Description: "View the staff list"},
	{Name: PermStaffManage, Description: "Invite and deactivate staff"},

	{Name: PermBusinessRead, Description: "View business details"},
	{Name: PermBusinessUpdate, Description: "Edit business details"},

	{Name: PermReportsRead, Description: "View reports and summaries"},

	{Name: PermSyncPull, Description: "Download changes to a device"},
	{Name: PermSyncPush, Description: "Upload changes from a device"},

	{Name: PermSalesRead, Description: "View sales"},
	{Name: PermSalesCreate, Description: "Record a sale"},
	{Name: PermSalesVoid, Description: "Void a sale"},

	{Name: PermStockRead, Description: "View stock requests and purchase orders"},
	{Name: PermStockRequest, Description: "Note a product that needs ordering"},

	{Name: PermPurchaseOrdersManage, Description: "Place and cancel purchase orders"},

	{Name: PermCustomersCreditLimit, Description: "Set how much credit a customer may run up"},

	{Name: PermSuppliersRead, Description: "View suppliers and what the shop owes them"},
	{Name: PermSuppliersManage, Description: "Add suppliers and record bills and payments to them"},
	{Name: PermSuppliersVoid, Description: "Void a supplier bill or payment"},
}

// staffPermissions is everything a member of staff may do.
//
// Listed explicitly, while owners simply get the whole catalogue. The asymmetry
// is deliberate: a new permission added to the system should be owner-only until
// somebody decides otherwise, rather than silently granted to staff because it
// was added to a shared list.
var staffPermissions = []string{
	PermCustomersRead,
	PermCustomersCreate,
	PermCustomersUpdate,

	PermTransactionsRead,
	PermTransactionsCreate,

	// Read-only, per the roles matrix in docs/01-product-requirements.md: staff
	// see who they work with but cannot change the team.
	PermStaffRead,

	PermBusinessRead,
	PermReportsRead,

	PermSyncPull,
	PermSyncPush,

	// Staff sell and notice empty shelves; that is most of their day. Voiding a
	// sale reverses money, and placing an order commits the shop's money to a
	// supplier, so both stay with the owner.
	PermSalesRead,
	PermSalesCreate,
	PermStockRead,
	PermStockRequest,

	// Not granted, deliberately: credit limits, and everything about
	// suppliers. A credit limit is the owner's policy, and what the shop owes
	// its suppliers is the owner's business — staff phones do not even
	// receive supplier records through sync.
}

// PermissionsFor returns what a role grants.
func PermissionsFor(role domain.Role) []string {
	if role == domain.RoleOwner {
		names := make([]string, 0, len(Permissions))
		for _, p := range Permissions {
			names = append(names, p.Name)
		}
		return names
	}
	return staffPermissions
}

// Seed makes the database match this file.
//
// Idempotent, and safe to run on every start: it is the mechanism by which a
// permission added in code reaches a running system. Permissions removed from
// code are left in place rather than deleted, because a role still referencing
// one would otherwise lose a grant as a side effect of a rename.
func Seed(ctx context.Context, db *gorm.DB) error {
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		for _, p := range Permissions {
			rec := authz.PermissionRecord{Name: p.Name, Description: p.Description}
			err := tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "name"}},
				DoUpdates: clause.AssignmentColumns([]string{"description", "updated_at"}),
			}).Create(&rec).Error
			if err != nil {
				return fmt.Errorf("rbac: upserting permission %q: %w", p.Name, err)
			}
		}

		for _, role := range []domain.Role{domain.RoleOwner, domain.RoleStaff} {
			if err := seedRole(tx, role); err != nil {
				return err
			}
		}
		return nil
	})
}

func seedRole(tx *gorm.DB, role domain.Role) error {
	rec := authz.Role{ID: id.New(), Name: string(role), Description: descriptionFor(role)}
	err := tx.Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "name"}},
		DoUpdates: clause.AssignmentColumns([]string{"description", "updated_at"}),
	}).Create(&rec).Error
	if err != nil {
		return fmt.Errorf("rbac: upserting role %q: %w", role, err)
	}

	// Re-read: on conflict the insert kept the existing row, so rec.ID is the
	// one this process generated rather than the one in the table.
	var stored authz.Role
	if err := tx.Where("name = ?", string(role)).First(&stored).Error; err != nil {
		return fmt.Errorf("rbac: reading back role %q: %w", role, err)
	}

	// Replace the grants wholesale rather than adding to them, so a permission
	// removed from this file is actually revoked. Roles are defined in code; the
	// table is a projection of that, not a place to edit.
	if err := tx.Where("role_id = ?", stored.ID).Delete(&authz.RolePermission{}).Error; err != nil {
		return fmt.Errorf("rbac: clearing grants for %q: %w", role, err)
	}
	for _, name := range PermissionsFor(role) {
		link := authz.RolePermission{RoleID: stored.ID, PermissionName: name}
		if err := tx.Create(&link).Error; err != nil {
			return fmt.Errorf("rbac: granting %q to %q: %w", name, role, err)
		}
	}
	return nil
}

func descriptionFor(role domain.Role) string {
	if role == domain.RoleOwner {
		return "Runs the business: everything staff can do, plus deleting customers, voiding transactions, and managing staff"
	}
	return "Day-to-day work: customers, debts and payments"
}

// AssignRole points a user at exactly one role.
//
// Call it inside the same transaction that writes users.role. The two must move
// together: users.role is what the phone displays and syncs, user_roles is what
// permission checks read, and a user with one but not the other is either
// locked out of their own shop or holding access they should not have.
func AssignRole(ctx context.Context, tx *gorm.DB, userID uuid.UUID, role domain.Role) error {
	var stored authz.Role
	if err := tx.WithContext(ctx).Where("name = ?", string(role)).First(&stored).Error; err != nil {
		return fmt.Errorf("rbac: role %q is not seeded: %w", role, err)
	}

	if err := tx.WithContext(ctx).Where("user_id = ?", userID).Delete(&authz.UserRole{}).Error; err != nil {
		return fmt.Errorf("rbac: clearing roles for user: %w", err)
	}
	link := authz.UserRole{UserID: userID, RoleID: stored.ID}
	if err := tx.WithContext(ctx).Create(&link).Error; err != nil {
		return fmt.Errorf("rbac: assigning %q: %w", role, err)
	}
	return nil
}
