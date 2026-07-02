# =============================================================
# Salio Server — Makefile
# Usage: make <target>
# =============================================================

# Load .env file to get DB variables for CLI commands.
# This makes all .env keys available as Make variables.
include .env
export

# Our own lean migration runner — only imports the Postgres driver.
# No external tool install needed. Version is pinned in go.mod.
MIGRATE := go run ./cmd/migrate
MIGRATIONS_DIR := ./migrations

# ---------------------------------------------------------------
# Server
# ---------------------------------------------------------------

## run: Start the API server in development mode
.PHONY: run
run:
	go run ./cmd/api/main.go

## build: Compile a production binary to ./bin/salio-server
.PHONY: build
build:
	@mkdir -p ./bin
	go build -ldflags="-s -w" -o ./bin/salio-server ./cmd/api/main.go
	@echo "✅ Binary built at ./bin/salio-server"

# ---------------------------------------------------------------
# Database Migrations
# These work exactly like: php artisan migrate
# ---------------------------------------------------------------

## migrate-up: Apply all pending migrations (equivalent to: php artisan migrate)
.PHONY: migrate-up
migrate-up:
	@echo "▶ Running migrations UP..."
	$(MIGRATE) up
	@echo "✅ All migrations applied."

## migrate-down: Roll back the last 1 migration (equivalent to: php artisan migrate:rollback)
.PHONY: migrate-down
migrate-down:
	@echo "▶ Rolling back 1 migration..."
	$(MIGRATE) down
	@echo "✅ Rollback complete."

## migrate-status: Show current migration version
.PHONY: migrate-status
migrate-status:
	$(MIGRATE) version

## migrate-create: Create a new up/down migration pair
## Usage: make migrate-create NAME=add_staff_table
.PHONY: migrate-create
migrate-create:
	@if [ -z "$(NAME)" ]; then \
		echo "❌ ERROR: NAME is required."; \
		echo "   Usage: make migrate-create NAME=your_migration_name"; \
		exit 1; \
	fi
	@NEXT=$$(ls $(MIGRATIONS_DIR)/*.up.sql 2>/dev/null | wc -l | tr -d ' '); \
	NUM=$$(printf "%03d" $$((NEXT + 1))); \
	touch $(MIGRATIONS_DIR)/$${NUM}_$(NAME).up.sql; \
	touch $(MIGRATIONS_DIR)/$${NUM}_$(NAME).down.sql; \
	echo "✅ Created: $${NUM}_$(NAME).up.sql and $${NUM}_$(NAME).down.sql"

# ---------------------------------------------------------------
# Code Quality (important for CI/CD pipelines)
# ---------------------------------------------------------------

## tidy: Clean up go.mod and go.sum
.PHONY: tidy
tidy:
	go mod tidy

## vet: Run Go's built-in static analysis tool
.PHONY: vet
vet:
	go vet ./...

## help: List all available make commands
.PHONY: help
help:
	@echo ""
	@echo "Salio Server — Available commands:"
	@echo ""
	@grep -E '^## ' Makefile | sed 's/## /  make /'
	@echo ""
