package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Connect establishes a PostgreSQL connection pool using the DSN from config.
// We use pgxpool because the server handles many concurrent HTTP requests.
// The pool manages multiple underlying connections efficiently.
//
// The caller is responsible for calling pool.Close() when the application shuts down.
func Connect(dsn string) (*pgxpool.Pool, error) {
	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to create database pool: %w", err)
	}

	// Ping verifies the database is actually reachable before the server starts.
	// This gives a clear startup error instead of a confusing runtime failure.
	if err := pool.Ping(context.Background()); err != nil {
		pool.Close()
		return nil, fmt.Errorf("database unreachable (check DB_HOST, DB_PORT, DB_USER, DB_PASSWORD): %w", err)
	}

	return pool, nil
}
