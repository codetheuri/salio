package app

// Package app is the application bootstrap layer.
// It owns the lifecycle of all components: database pool, repositories, handlers, HTTP server.
//
// Architecture:
//   main.go  →  app.New(cfg)  →  wires repos, handlers, router
//                              →  app.Run()  →  starts server, handles graceful shutdown

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	chiMiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"salio/server/internal/api"
	"salio/server/internal/config"
	"salio/server/internal/db"
	"salio/server/internal/middleware"
	"salio/server/internal/repository"
)

// App holds the fully wired application.
// All fields are private — external code only interacts via Run().
type App struct {
	cfg    *config.Config
	pool   *pgxpool.Pool
	server *http.Server
}

// New wires all components together and returns a ready-to-run App.
// Fails immediately if any component cannot be initialised (fail-fast pattern).
func New(cfg *config.Config) (*App, error) {
	// 1. Database connection pool
	pool, err := db.Connect(cfg.DSN())
	if err != nil {
		return nil, fmt.Errorf("database: %w", err)
	}
	slog.Info("Database connected", "host", cfg.DBHost, "db", cfg.DBName)

	// 2. Repositories — the ONLY layer that talks to the database
	authRepo := repository.NewAuthRepository(pool)
	customerRepo := repository.NewCustomerRepository(pool)
	transactionRepo := repository.NewTransactionRepository(pool)
	userRepo := repository.NewUserRepository(pool)
	syncRepo := repository.NewSyncRepository(pool)
	reportRepo := repository.NewReportRepository(pool)

	// 3. Handlers — the ONLY layer that talks to repositories
	//    Handlers receive interfaces, not concrete types → easily testable with mocks
	authHandler := api.NewAuthHandler(authRepo, cfg.JWTSecret, cfg.JWTExpiryHours)
	customerHandler := api.NewCustomerHandler(customerRepo, transactionRepo)
	transactionHandler := api.NewTransactionHandler(transactionRepo, customerRepo)
	userHandler := api.NewUserHandler(userRepo)
	syncHandler := api.NewSyncHandler(syncRepo)
	reportHandler := api.NewReportHandler(reportRepo)

	// 4. Router with all middleware and routes
	router := buildRouter(cfg, authHandler, customerHandler, transactionHandler, userHandler, syncHandler, reportHandler, pool)

	// 5. HTTP server with production-grade timeouts
	server := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	return &App{cfg: cfg, pool: pool, server: server}, nil
}

// Run starts the HTTP server and blocks until SIGINT or SIGTERM.
// It then gracefully drains in-flight requests before exiting.
func (a *App) Run() error {
	serverErrors := make(chan error, 1)
	go func() {
		slog.Info("Server listening", "addr", "http://localhost:"+a.cfg.Port)
		if err := a.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			serverErrors <- err
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serverErrors:
		return fmt.Errorf("server error: %w", err)

	case sig := <-quit:
		slog.Info("Shutdown signal received", "signal", sig.String())

		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()

		if err := a.server.Shutdown(ctx); err != nil {
			return fmt.Errorf("graceful shutdown failed: %w", err)
		}
		a.pool.Close()
		slog.Info("Server shut down cleanly")
		return nil
	}
}

// buildRouter assembles the Chi router with all middleware layers and routes.
// Middleware order matters — it runs top-to-bottom on every request.
func buildRouter(
	cfg *config.Config,
	authH *api.AuthHandler,
	customerH *api.CustomerHandler,
	transactionH *api.TransactionHandler,
	userH *api.UserHandler,
	syncH *api.SyncHandler,
	reportH *api.ReportHandler,
	pool *pgxpool.Pool,
) *chi.Mux {
	r := chi.NewRouter()

	// Stateful rate limiter — created once and shared across all requests
	rateLimiter := middleware.NewRateLimiter(cfg.RateLimitRPS, cfg.RateLimitBurst)

	// ── Global Middleware (every request passes through all of these) ────────────
	r.Use(middleware.CORS(cfg.CORSAllowedOrigins))                              // Must be first — handles CORS preflight OPTIONS
	r.Use(chiMiddleware.RequestID)                                               // Unique X-Request-ID for distributed tracing
	r.Use(chiMiddleware.RealIP)                                                  // Unwrap X-Forwarded-For from Nginx proxy
	r.Use(middleware.SecurityHeaders())                                          // HSTS, CSP, X-Frame-Options, etc.
	r.Use(chiMiddleware.Logger)                                                  // Structured HTTP access log
	r.Use(chiMiddleware.Recoverer)                                               // Panic → 500 instead of process crash
	r.Use(rateLimiter.Middleware())                                              // Per-IP token bucket rate limiting
	r.Use(middleware.RequestTimeout(time.Duration(cfg.RequestTimeoutSecs) * time.Second)) // Request deadline
	r.Use(chiMiddleware.Heartbeat("/ping"))                                      // /ping → 200 for load balancer checks

	// ── System Routes ────────────────────────────────────────────────────────────
	r.Get("/health", healthHandler(pool))

	// ── Public Routes (no JWT) ───────────────────────────────────────────────────
	r.Route("/v1/auth", func(r chi.Router) {
		r.Post("/register-business", authH.RegisterBusiness)
		r.Post("/login", authH.Login)
		r.Post("/join", authH.JoinBusiness)
	})

	// ── Protected Routes (JWT required) ─────────────────────────────────────────
	r.Group(func(r chi.Router) {
		r.Use(middleware.Authenticate(cfg.JWTSecret))

		// Auth — Owner only
		r.With(middleware.RequireRole("owner")).
			Post("/v1/auth/invite", authH.GenerateInvite)

		// Customers — owner or staff
		r.Route("/v1/customers", func(r chi.Router) {
			r.Get("/", customerH.List)
			r.Post("/", customerH.Create)
			r.Get("/{customerID}", customerH.GetByID)
			r.Put("/{customerID}", customerH.Update)
			r.With(middleware.RequireRole("owner")).Delete("/{customerID}", customerH.Delete)
			r.Get("/{customerID}/transactions", transactionH.ListForCustomer)
		})

		// Transactions
		r.Post("/v1/transactions", transactionH.Create)
		r.With(middleware.RequireRole("owner")).
			Delete("/v1/transactions/{transactionID}", transactionH.VoidTransaction)

		// Profile — any authenticated user
		r.Get("/v1/users/me", userH.Me)
		r.Put("/v1/users/me", userH.UpdateMe)

		// Business settings — owner only
		r.With(middleware.RequireRole("owner")).
			Put("/v1/business", userH.UpdateBusiness)

		// Staff management — list is owner+staff (read-only per PRD), remove is owner-only
		r.Get("/v1/staff", userH.ListStaff)
		r.With(middleware.RequireRole("owner")).
			Delete("/v1/staff/{userID}", userH.DeactivateStaff)

		// Sync — Mobile app background synchronization
		r.Get("/v1/sync/pull", syncH.Pull)
		r.Post("/v1/sync/push", syncH.Push)

		// Reports - Live analytics
		r.Get("/v1/reports/summary", reportH.GetSummary)
	})

	return r
}

// healthHandler returns a live health check including database connectivity status.
func healthHandler(pool *pgxpool.Pool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		dbStatus := "ok"
		if err := pool.Ping(ctx); err != nil {
			slog.Error("Health check: DB ping failed", "error", err)
			dbStatus = "unreachable"
		}

		httpStatus := http.StatusOK
		appStatus := "ok"
		if dbStatus != "ok" {
			httpStatus = http.StatusServiceUnavailable
			appStatus = "degraded"
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(httpStatus)
		fmt.Fprintf(w, `{"status":"%s","db":"%s","timestamp":"%s"}`,
			appStatus, dbStatus, time.Now().UTC().Format(time.RFC3339))
	}
}
