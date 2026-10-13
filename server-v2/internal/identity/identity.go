// Package identity is the one place allowed to read users and invites before a
// tenant is known.
//
// Signing in finds a user by phone across every business; registering checks a
// phone is free everywhere; joining finds which business an invite code belongs
// to. Row-level security would show all three nothing, because no tenant can be
// declared yet. Migration 00009 adds a door for exactly these reads: a SELECT-
// only policy on users and business_invites that opens for a transaction
// setting app.identity_lookup. It cannot write, and it is opened here and
// nowhere else — grep for this package and the list of callers is complete.
package identity

import (
	"context"
	"fmt"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"gorm.io/gorm"
)

// Lookup runs fn in a transaction where users and invites are readable across
// businesses. fn receives a *gorm.DB already marked tenant.Unscoped, since the
// GORM tenant callbacks would otherwise refuse a read with no tenant; call
// tenant.Unscoped(tx) again before each further statement, as everywhere else.
func Lookup(ctx context.Context, db *gorm.DB, fn func(tx *gorm.DB) error) error {
	return db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := Open(tx); err != nil {
			return err
		}
		return fn(tenant.Unscoped(tx))
	})
}

// Open opens the door for the rest of the current transaction (SET LOCAL), for
// a caller that has to combine the lookup with writes in one transaction.
// Close it again as soon as the lookup is done.
func Open(tx *gorm.DB) error {
	if err := tx.Exec("SELECT set_config('app.identity_lookup', 'on', true)").Error; err != nil {
		return fmt.Errorf("identity: opening the lookup: %w", err)
	}
	return nil
}

// Close shuts the door before the transaction goes on to write, so nothing
// after the lookup runs with more access than it needs.
func Close(tx *gorm.DB) error {
	if err := tx.Exec("SELECT set_config('app.identity_lookup', 'off', true)").Error; err != nil {
		return fmt.Errorf("identity: closing the lookup: %w", err)
	}
	return nil
}

// DeclareTenant declares a tenant for the rest of the current transaction — for
// the moments a request creates or joins a business and so only learns its
// tenant part-way through.
func DeclareTenant(tx *gorm.DB, businessID string) error {
	if err := tx.Exec("SELECT set_config('app.tenant_id', ?, true)", businessID).Error; err != nil {
		return fmt.Errorf("identity: declaring the tenant: %w", err)
	}
	return nil
}
