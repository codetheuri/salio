package api

// This file defines repository interfaces consumed by the HTTP handlers.
//
// Go principle: "Accept interfaces, return structs."
// The interface is defined here (where it is USED), not in the repository package
// (where it is IMPLEMENTED). This means handlers never depend on concrete types —
// they depend on behaviour. You can swap the real Postgres implementation for a
// mock in tests without touching a single line of handler code.

import (
	"context"

	"github.com/google/uuid"
    "time"

	"salio/server/internal/models"
	"salio/server/internal/repository"
)

// AuthRepository defines all auth operations the handlers need.
// *repository.AuthRepository satisfies this interface automatically.
type AuthRepository interface {
	RegisterBusiness(ctx context.Context, input repository.RegisterBusinessInput) (*models.User, error)
	GetUserByPhone(ctx context.Context, phone string) (*models.User, error)
	CreateInviteCode(ctx context.Context, businessID uuid.UUID) (string, error)
	JoinBusiness(ctx context.Context, input repository.JoinBusinessInput) (*models.User, error)
}

// CustomerRepository defines all customer operations the handlers need.
// *repository.CustomerRepository satisfies this interface automatically.
type CustomerRepository interface {
	List(ctx context.Context, businessID uuid.UUID, search string) ([]models.Customer, error)
	GetByID(ctx context.Context, businessID, customerID uuid.UUID) (*models.Customer, error)
	Create(ctx context.Context, input repository.CreateCustomerInput) (*models.Customer, error)
	Update(ctx context.Context, businessID, customerID uuid.UUID, input repository.UpdateCustomerInput) (*models.Customer, error)
	SoftDelete(ctx context.Context, businessID, customerID uuid.UUID) error
	GetBalance(ctx context.Context, businessID, customerID uuid.UUID) (float64, error)
}

// TransactionRepository defines all transaction operations the handlers need.
// *repository.TransactionRepository satisfies this interface automatically.
type TransactionRepository interface {
	ListForCustomer(ctx context.Context, businessID, customerID uuid.UUID) ([]models.Transaction, error)
	Create(ctx context.Context, input repository.CreateTransactionInput) (*models.Transaction, error)
	SoftDelete(ctx context.Context, businessID, transactionID uuid.UUID) error
}

// UserRepository defines all user/staff/business management operations.
// *repository.UserRepository satisfies this interface automatically.
type UserRepository interface {
	GetUserByID(ctx context.Context, userID uuid.UUID) (*models.User, error)
	GetBusiness(ctx context.Context, businessID uuid.UUID) (*models.Business, error)
	UpdateUser(ctx context.Context, userID uuid.UUID, input repository.UpdateUserInput) (*models.User, error)
	UpdateBusiness(ctx context.Context, businessID uuid.UUID, input repository.UpdateBusinessInput) (*models.Business, error)
	ListStaff(ctx context.Context, businessID uuid.UUID) ([]models.User, error)
	DeactivateStaff(ctx context.Context, businessID, targetUserID uuid.UUID) error
}

// SyncRepository defines the operations for offline-first sync.
// *repository.SyncRepository satisfies this interface automatically.
type SyncRepository interface {
	Pull(ctx context.Context, businessID uuid.UUID, lastSync time.Time) (*models.SyncPayload, error)
	Push(ctx context.Context, businessID uuid.UUID, payload models.SyncPayload) error
}
