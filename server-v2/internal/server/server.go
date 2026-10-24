// Package server assembles the Salio API: database, middleware in the order it
// must run, and every module's routes.
//
// It lives here rather than in cmd/api so that a test can build exactly the
// server production runs — the same middleware, in the same order — and drive
// it over HTTP. internal/server's own tests do that as an unprivileged database
// role, which is the only way to know row-level security actually works.
package server

import (
	"context"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/config"
	"github.com/codetheuri/tusk/v2/pkg/app"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	tuskmw "github.com/codetheuri/tusk/v2/pkg/middleware"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/danielgtaylor/huma/v2"

	"salio/server-v2/database"
	"salio/server-v2/internal/appupdate"
	"salio/server-v2/internal/business"
	"salio/server-v2/internal/console"
	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/reports"
	"salio/server-v2/internal/sales"
	"salio/server-v2/internal/session"
	"salio/server-v2/internal/stock"
	"salio/server-v2/internal/supplier"
	"salio/server-v2/internal/syncengine"
	"salio/server-v2/internal/tenantconn"
)

// Options are the choices that differ between environments.
type Options struct {
	// MigrateOnBoot applies pending migrations at start-up. Convenient in
	// development; off in production, where the application's database role
	// cannot change the schema — migrations run separately, as the owner role
	// (make migrate-up), so a compromised API cannot drop a table.
	MigrateOnBoot bool

	// RequireRLS refuses to start when the database role is exempt from row-
	// level security (a superuser, or BYPASSRLS). On in production: that
	// exemption is silent, and it turns the database's tenant isolation off.
	RequireRLS bool

	// ReleasesDir holds the published app: the APKs and latest.json, copied
	// there by mobile-v2/scripts/release.sh. Missing or empty means no
	// release yet (the version endpoint answers 404). Read-only to the API.
	ReleasesDir string
}

// Build returns a ready-to-run application.
func Build(cfg *config.Config, log logger.Logger, opts Options) (*app.App, error) {
	application, err := app.New(app.Options{
		Config:      cfg,
		Logger:      log,
		Title:       "Salio API",
		Version:     cfg.AppVersion,
		Description: "Offline-first debt and credit tracking for small retailers.",
		Contact: &huma.Contact{
			Name:  "Salio Support",
			Email: "theurij113@gmail.com",
		},
		Tags: []*huma.Tag{
			{Name: "Authentication", Description: "Register a business, sign in, join with an invite"},
			{Name: "Business", Description: "Business details and staff invites"},
			{Name: "Users", Description: "Your own profile and password, and staff management"},
			{Name: "Sync", Description: "Offline-first cursor sync for the mobile client"},
			{Name: "Customers", Description: "The people who owe the shop money"},
			{Name: "Transactions", Description: "Debts (with optional due date) and payments (cash, M-Pesa or bank); a payment above the balance becomes an advance"},
			{Name: "Sales", Description: "What was sold, in cash or on a customer's account"},
			{Name: "Stock & Orders", Description: "Products that ran out, and purchase orders to restock them"},
			{Name: "Suppliers", Description: "Who the shop buys from, and what it owes them (owner only)"},
			{Name: "Reports", Description: "Dashboard, statements, debt ageing, sales and collections, with PDFs"},
			{Name: "Mobile App", Description: "The latest Android release, for the in-app updater"},
		},
	})
	if err != nil {
		return nil, fmt.Errorf("application setup: %w", err)
	}
	db := application.DB()

	// Checked first, before anything is served or written.
	if err := tenant.VerifyEnforcement(db); err != nil {
		if opts.RequireRLS {
			return nil, fmt.Errorf("row-level security is not enforced for this database role: %w", err)
		}
		log.Warn("Row-level security is not enforced for this database role (allowed outside production)",
			"detail", err.Error())
	}

	if opts.MigrateOnBoot {
		sqlDB, err := db.DB()
		if err != nil {
			return nil, fmt.Errorf("getting the sql.DB: %w", err)
		}
		if err := database.Migrator().Up(sqlDB); err != nil {
			return nil, fmt.Errorf("migrating: %w", err)
		}
	}

	// Idempotent: makes the database match pkg/rbac on every boot, so a
	// permission added in code reaches a running system without a manual step.
	if err := rbac.Seed(context.Background(), db); err != nil {
		return nil, fmt.Errorf("seeding permissions: %w", err)
	}

	// Every request's statements go down that request's own connection once
	// tenantconn's middleware has declared the tenant on it. Installed before
	// any route exists.
	pool, err := tenantconn.Install(db)
	if err != nil {
		return nil, err
	}

	// Middleware order matters, and each needs the one before:
	//   1. authentication (registered by app.New) — who is calling
	//   2. tenant         — which business, from the token's claim only
	//   3. tenantconn     — declares that business to PostgreSQL for RLS
	//   4. session        — is that session still allowed (account active,
	//                       not signed out by a password change, no pending
	//                       forced password change)
	// All four must be registered before the first route: Huma fixes an
	// operation's middleware when the operation is registered.
	api := application.API()
	api.UseMiddleware(tenant.HumaMiddleware(api, tuskmw.HumaTenantResolver(cfg.JWTSecret)))
	api.UseMiddleware(tenantconn.Middleware(api, pool, log))
	api.UseMiddleware(session.Guard(api, db, cfg.JWTSecret, log))

	business.RegisterRoutes(api, db, cfg.JWTSecret, 30*24*time.Hour, log)
	customer.RegisterRoutes(api, db, log)
	ledger.RegisterRoutes(api, db, log)
	reports.RegisterRoutes(api, db, log)
	sales.RegisterRoutes(api, db, log)
	stock.RegisterRoutes(api, db, log)
	supplier.RegisterRoutes(api, db, log)
	syncengine.RegisterRoutes(api, db, log)

	// Public: the app checks for and downloads updates before it signs in.
	appupdate.RegisterRoutes(api, application.Router(), appupdate.NewStore(opts.ReleasesDir), log)

	// The admin console is server-rendered HTML on the same router, not part of
	// the API: cookie sessions, form posts, and a super_admin who belongs to no
	// business. Mounted on Router() rather than API() so none of it appears in
	// the OpenAPI document the mobile client reads.
	if err := console.Mount(application.Router(), console.Options{
		DB:     db,
		Logger: log,
		Secure: cfg.IsProduction(),
		Reload: !cfg.IsProduction(),
	}); err != nil {
		return nil, fmt.Errorf("console setup: %w", err)
	}

	return application, nil
}
