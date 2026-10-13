// Command api is the Salio v2 HTTP server.
package main

import (
	"context"
	"time"

	"github.com/codetheuri/tusk/v2/config"
	"github.com/codetheuri/tusk/v2/pkg/app"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	tuskmw "github.com/codetheuri/tusk/v2/pkg/middleware"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/danielgtaylor/huma/v2"

	"salio/server-v2/database"
	"salio/server-v2/internal/business"
	"salio/server-v2/internal/console"
	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/reports"
	"salio/server-v2/internal/sales"
	"salio/server-v2/internal/stock"
	"salio/server-v2/internal/supplier"
	"salio/server-v2/internal/syncengine"
)

func main() {
	log := logger.NewTextLogger("info")

	cfg, err := config.LoadConfig()
	if err != nil {
		log.Fatal("Failed to load configuration", err)
	}
	log = logger.New(cfg.IsProduction(), cfg.LOG_LEVEL)

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
			{Name: "Users", Description: "Your own profile, and staff management"},
			{Name: "Sync", Description: "Offline-first cursor sync for the mobile client"},
			{Name: "Customers", Description: "The people who owe the shop money"},
			{Name: "Transactions", Description: "Debts (with optional due date) and payments (cash, M-Pesa or bank); a payment above the balance becomes an advance"},
			{Name: "Sales", Description: "What was sold, in cash or on a customer's account"},
			{Name: "Stock & Orders", Description: "Products that ran out, and purchase orders to restock them"},
			{Name: "Suppliers", Description: "Who the shop buys from, and what it owes them (owner only)"},
			{Name: "Reports", Description: "Dashboard, statements, debt ageing, sales and collections, with PDFs"},
		},
	})
	if err != nil {
		log.Fatal("Application setup failed", err)
	}

	// Salio's own schema, run through the same migrator Tusk's CLI uses.
	// database.Migrator() is Salio's; application.DB() opens no schema of its
	// own, so this is the only place the tables actually get created.
	sqlDB, err := application.DB().DB()
	if err != nil {
		log.Fatal("Failed to get the underlying sql.DB", err)
	}
	if err := database.Migrator().Up(sqlDB); err != nil {
		log.Fatal("Migration failed", err)
	}

	// Idempotent: makes the database match pkg/rbac on every boot, so a
	// permission added in code reaches a running system without a manual step.
	if err := rbac.Seed(context.Background(), application.DB()); err != nil {
		log.Fatal("Failed to seed permissions", err)
	}

	// Every business.* endpoint reads its tenant from the JWT's tenant_id claim,
	// never from anything a caller supplies. This has to be registered before
	// business.RegisterRoutes runs any handler — pkg/app wires authentication,
	// not tenancy, since most applications built on Tusk have none.
	application.API().UseMiddleware(tenant.HumaMiddleware(
		application.API(),
		tuskmw.HumaTenantResolver(cfg.JWTSecret),
	))

	business.RegisterRoutes(application.API(), application.DB(), cfg.JWTSecret, 30*24*time.Hour, log)
	customer.RegisterRoutes(application.API(), application.DB(), log)
	ledger.RegisterRoutes(application.API(), application.DB(), log)
	reports.RegisterRoutes(application.API(), application.DB(), log)
	sales.RegisterRoutes(application.API(), application.DB(), log)
	stock.RegisterRoutes(application.API(), application.DB(), log)
	supplier.RegisterRoutes(application.API(), application.DB(), log)
	syncengine.RegisterRoutes(application.API(), application.DB(), log)

	// The admin console is server-rendered HTML on the same router, not part of
	// the API: cookie sessions, form posts, and a super_admin who belongs to no
	// business. Mounted on Router() rather than API() so none of it appears in
	// the OpenAPI document the mobile client reads.
	if err := console.Mount(application.Router(), console.Options{
		DB:     application.DB(),
		Logger: log,
		Secure: cfg.IsProduction(),
		Reload: !cfg.IsProduction(),
	}); err != nil {
		log.Fatal("Console setup failed", err)
	}

	// Says out loud whether the third tenancy layer is actually doing anything.
	// PostgreSQL exempts superusers and BYPASSRLS roles from every policy in
	// silence, so a system can hold correct policies and no protection at all.
	// A warning rather than a fatal: development connects as a superuser by
	// design, and refusing to start would make the check something to remove.
	if err := tenant.VerifyEnforcement(application.DB()); err != nil {
		log.Warn("Row-level security is not enforced for this database role", "detail", err.Error())
	}

	if err := application.Run(); err != nil {
		log.Fatal("Server exited with error", err)
	}
}
