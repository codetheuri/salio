.PHONY: db-roles docker-build docker-up docker-down import-v1 import-v1-dry import-v1-verify sync-gc sync-gc-dry create-admin dev run build test test-unit test-integration test-db-setup coverage vet migrate-up migrate-down migrate-reset migrate-status clean help

include .env
export

# ==============================================================================
# Development commands

## dev: apply migrations, then run with hot-reloading using Air
## (migrations first: the API connects as the app role, which cannot change the schema)
dev: migrate-up
	@echo "Starting hot-reload server..."
	@go run github.com/air-verse/air@latest

## run: apply migrations, then run the application without hot-reloading
run: migrate-up
	go run ./cmd/api

## build: build the production binary
build:
	@echo "Building production binary..."
	go build -o ./bin/api ./cmd/api
	@echo "Built ./bin/api successfully!"

## test: run all tests (integration tests skip if no database is reachable)
test:
	go test -race ./...

## test-unit: run only tests that need no database
test-unit:
	go test -race -short ./internal/money/...

## test-integration: run all tests and FAIL if the test database is unreachable
## Requires PostgreSQL. Override the target with TEST_DATABASE_URL.
test-integration:
	REQUIRE_DB_TESTS=1 go test -race -count=1 ./...

## test-db-setup: create the local test database (one-off)
test-db-setup:
	@psql "$${TEST_ADMIN_URL:-postgres://root:root@127.0.0.1:5434/postgres}" \
		-c "CREATE DATABASE salio_v2_test" 2>/dev/null && echo "Created salio_v2_test" \
		|| echo "salio_v2_test already exists (or psql is unavailable)"

## coverage: run tests and generate coverage report
coverage:
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

## vet: run static analysis
vet:
	go vet ./...

# ==============================================================================
# Database Migrations
#
# Salio's own schema — separate from Tusk's. Permissions and roles are not
# migrated data; they are seeded from pkg/rbac on every server start, so there
# is no auth-sync command here the way Tusk's own CLI has one.

## db-roles: create the owner and app database roles (once; needs DB_ADMIN_URL, a superuser)
db-roles:
	psql "$(DB_ADMIN_URL)" -v db_name="$(DB_NAME)" \
		-v owner_role="$(MIGRATION_DB_USER)" -v owner_password="$(MIGRATION_DB_PASS)" \
		-v app_role="$(DB_USER)" -v app_password="$(DB_PASS)" \
		-f deploy/postgres/roles.sql

## migrate-up: apply all pending database migrations (as MIGRATION_DB_USER when set)
migrate-up:
	go run ./cmd/migrate up

## migrate-down: revert the last database migration
migrate-down:
	go run ./cmd/migrate down

## migrate-reset: revert every migration, dropping the schema
migrate-reset:
	go run ./cmd/migrate reset

## migrate-status: check the status of database migrations
migrate-status:
	go run ./cmd/migrate status

# ==============================================================================
# Utilities

## create-admin: register a console super admin (password via SALIO_ADMIN_PASSWORD or stdin)
create-admin:
	go run ./cmd/createadmin -name "$(NAME)" -email "$(EMAIL)"

## import-v1: copy a v1 database into the v2 schema, then verify balances (SOURCE=<dsn>)
import-v1:
	go run ./cmd/importv1 -source "$(SOURCE)"

## import-v1-dry: report what import-v1 would copy, writing nothing (SOURCE=<dsn>)
import-v1-dry:
	go run ./cmd/importv1 -source "$(SOURCE)" -dry-run

## import-v1-verify: re-check an import that has already run (SOURCE=<dsn>)
import-v1-verify:
	go run ./cmd/importv1 -source "$(SOURCE)" -verify-only

## sync-gc: collect sync tombstones older than AGE (default 90 days)
sync-gc:
	go run ./cmd/syncgc -age $(or $(AGE),2160h)

## sync-gc-dry: report what sync-gc would collect, deleting nothing
sync-gc-dry:
	go run ./cmd/syncgc -age $(or $(AGE),2160h) -dry-run

# ==============================================================================
# Containers (see deploy/compose.yaml and docs/09-operations.md)

## docker-build: build the production image
docker-build:
	docker build -t salio-api:local .

## docker-up: start database, migration, API and sweep (needs deploy/.env)
docker-up:
	docker compose -f deploy/compose.yaml up -d --build

## docker-down: stop the stack (data is kept in the pgdata volume)
docker-down:
	docker compose -f deploy/compose.yaml down

## clean: remove binary and temporary files
clean:
	rm -rf ./tmp ./bin build-errors.log coverage.out coverage.html

## help: print this help message
help:
	@echo "Usage:"
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' |  sed -e 's/^/ /'
