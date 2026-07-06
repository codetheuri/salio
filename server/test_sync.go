package main

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"

	"salio/server/internal/models"
	"salio/server/internal/repository"
)

func main() {
	dbURL := "postgres://root:root@127.0.0.1:5434/salio_db?sslmode=disable"
	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("failed to connect to db: %v", err)
	}
	defer pool.Close()

	syncRepo := repository.NewSyncRepository(pool)

	businessID := uuid.MustParse("d567c945-816d-4de0-ba18-e37de9f8d10b") // Use a real business ID if possible, or we will just test syntax.
	// Actually, let's create a business first
	_, _ = pool.Exec(context.Background(), `INSERT INTO businesses (id, name) VALUES ($1, 'Test Biz') ON CONFLICT DO NOTHING`, businessID)
	userID := uuid.New()
	_, _ = pool.Exec(context.Background(), `INSERT INTO users (id, business_id, name, phone, password_hash, role) VALUES ($1, $2, 'U', '123', 'hash', 'owner') ON CONFLICT DO NOTHING`, userID, businessID)

	custID := uuid.New()
	payload := models.SyncPayload{
		Customers: []models.Customer{
			{
				ID:         custID,
				BusinessID: businessID,
				Name:       "John",
				CreatedBy:  userID,
				CreatedAt:  time.Now(),
				IsDeleted:  false,
			},
		},
		Transactions: []models.Transaction{
			{
				ID:              uuid.New(),
				BusinessID:      businessID,
				CustomerID:      custID,
				UserID:          userID,
				Type:            models.TransactionTypeDebt,
				Amount:          100.0,
				TransactionDate: time.Now(),
				CreatedAt:       time.Now(),
				IsDeleted:       false,
			},
		},
	}

	err = syncRepo.Push(context.Background(), businessID, payload)
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
	} else {
		fmt.Printf("SUCCESS\n")
	}
}
