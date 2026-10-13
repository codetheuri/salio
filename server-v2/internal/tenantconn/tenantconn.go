// Package tenantconn makes PostgreSQL's row-level security apply to every
// request, without any repository having to know.
//
// # The problem
//
// RLS policies read the tenant from a connection setting, app.tenant_id. GORM
// draws a connection from the pool per statement, so a setting made by one
// statement is not seen by the next, and nothing in the request path made one
// at all. Run as the unprivileged role production must use, registration
// failed with "new row violates row-level security policy" — every earlier run
// had used a superuser, which PostgreSQL silently exempts from every policy. The
// third layer of tenant isolation had never been switched on.
//
// # The fix
//
// One connection per authenticated request. Middleware takes it from the pool,
// declares the request's tenant on it, and hands it back afterwards with the
// tenant cleared. A Pool installed in GORM routes every statement whose context
// carries that connection onto it — including transactions, which therefore
// see the tenant too. Repositories are unchanged: 111 call sites do not each
// get a chance to be forgotten.
//
// A statement that loses its context (context.Background) goes to the shared
// pool, where no tenant is declared, and RLS shows it nothing. That is the safe
// direction to fail in.
package tenantconn

import (
	"context"
	"database/sql"
	"database/sql/driver"
	"errors"
	"fmt"
	"net/http"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"
)

type connKey struct{}

// Pool is a gorm.ConnPool that sends a request's statements down the
// request's own connection, and everything else to the shared pool.
type Pool struct {
	db *sql.DB
}

func (p *Pool) pick(ctx context.Context) interface {
	PrepareContext(context.Context, string) (*sql.Stmt, error)
	ExecContext(context.Context, string, ...any) (sql.Result, error)
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
	QueryRowContext(context.Context, string, ...any) *sql.Row
	BeginTx(context.Context, *sql.TxOptions) (*sql.Tx, error)
} {
	if ctx != nil {
		if c, ok := ctx.Value(connKey{}).(*sql.Conn); ok {
			return c
		}
	}
	return p.db
}

func (p *Pool) PrepareContext(ctx context.Context, q string) (*sql.Stmt, error) {
	return p.pick(ctx).PrepareContext(ctx, q)
}

func (p *Pool) ExecContext(ctx context.Context, q string, args ...any) (sql.Result, error) {
	return p.pick(ctx).ExecContext(ctx, q, args...)
}

func (p *Pool) QueryContext(ctx context.Context, q string, args ...any) (*sql.Rows, error) {
	return p.pick(ctx).QueryContext(ctx, q, args...)
}

func (p *Pool) QueryRowContext(ctx context.Context, q string, args ...any) *sql.Row {
	return p.pick(ctx).QueryRowContext(ctx, q, args...)
}

// BeginTx starts a transaction on the request's connection when there is one,
// so a repository's Transaction(...) inherits the declared tenant.
func (p *Pool) BeginTx(ctx context.Context, opts *sql.TxOptions) (*sql.Tx, error) {
	return p.pick(ctx).BeginTx(ctx, opts)
}

// GetDBConn keeps gorm.DB.DB() working: migrations and health checks still
// need the *sql.DB underneath.
func (p *Pool) GetDBConn() (*sql.DB, error) { return p.db, nil }

// Install puts a Pool under db. Call once, at start-up, before serving.
func Install(db *gorm.DB) (*Pool, error) {
	sqlDB, err := db.DB()
	if err != nil {
		return nil, fmt.Errorf("tenantconn: no *sql.DB under gorm: %w", err)
	}
	pool := &Pool{db: sqlDB}
	db.Config.ConnPool = pool
	db.Statement.ConnPool = pool
	return pool, nil
}

// Middleware gives each request that carries a tenant its own connection with
// the tenant declared. Register it after the tenant middleware, which is what
// puts the tenant in the context, and before any route.
func Middleware(api huma.API, pool *Pool, log logger.Logger) func(huma.Context, func(huma.Context)) {
	return func(ctx huma.Context, next func(huma.Context)) {
		id, err := tenant.MustFromContext(ctx.Context())
		if err != nil {
			next(ctx) // no tenant: sign-in, registration, public routes
			return
		}

		reqCtx := ctx.Context()
		conn, err := Acquire(reqCtx, pool, id.String())
		if err != nil {
			log.Error("tenantconn: acquiring a connection", err)
			huma.WriteErr(api, ctx, http.StatusServiceUnavailable, "The service is busy. Please try again.")
			return
		}
		defer Release(conn, log)

		next(huma.WithContext(ctx, context.WithValue(reqCtx, connKey{}, conn)))
	}
}

// WithConn returns ctx carrying a tenant-declared connection, for work outside
// an HTTP request (tests, jobs). The caller must Release it.
func WithConn(ctx context.Context, pool *Pool, tenantID string) (context.Context, *sql.Conn, error) {
	conn, err := Acquire(ctx, pool, tenantID)
	if err != nil {
		return nil, nil, err
	}
	return context.WithValue(ctx, connKey{}, conn), conn, nil
}

// Acquire takes a connection from the pool and declares the tenant on it.
//
// Session-level (is_local = false) rather than SET LOCAL, because the request
// runs many statements and several transactions on this connection, and all of
// them must see the tenant. That makes Release responsible for clearing it.
func Acquire(ctx context.Context, pool *Pool, tenantID string) (*sql.Conn, error) {
	conn, err := pool.db.Conn(ctx)
	if err != nil {
		return nil, err
	}
	if _, err := conn.ExecContext(ctx, "SELECT set_config('app.tenant_id', $1, false)", tenantID); err != nil {
		discard(conn)
		return nil, fmt.Errorf("declaring the tenant: %w", err)
	}
	return conn, nil
}

// Release clears the tenant and returns the connection to the pool.
//
// If the clearing fails, the connection is destroyed instead of returned: a
// pooled connection still declaring one shop's tenant would hand that shop's
// rows to whichever request drew it next. Cleared with a fresh context because
// the request's may already be cancelled — a client hanging up must not stop
// the cleanup.
func Release(conn *sql.Conn, log logger.Logger) {
	ctx := context.Background()
	if _, err := conn.ExecContext(ctx, "SELECT set_config('app.tenant_id', '', false)"); err != nil {
		log.Warn("tenantconn: could not clear the tenant; discarding the connection", "error", err.Error())
		discard(conn)
		return
	}
	_ = conn.Close()
}

// discard closes the underlying connection rather than returning it to the
// pool: returning driver.ErrBadConn from Raw tells database/sql it is unusable.
func discard(conn *sql.Conn) {
	_ = conn.Raw(func(any) error { return driver.ErrBadConn })
	_ = conn.Close()
}

// ErrNoConn is returned by FromContext when the context carries no connection.
var ErrNoConn = errors.New("tenantconn: no request connection in context")

// FromContext reports the request's connection, if any — for tests that need
// to assert the plumbing, not for application code.
func FromContext(ctx context.Context) (*sql.Conn, error) {
	if c, ok := ctx.Value(connKey{}).(*sql.Conn); ok {
		return c, nil
	}
	return nil, ErrNoConn
}
