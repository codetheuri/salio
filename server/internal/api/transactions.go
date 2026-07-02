package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"salio/server/internal/middleware"
	"salio/server/internal/models"
	"salio/server/internal/repository"
	"salio/server/pkg/validate"
)

// TransactionHandler handles all HTTP requests for transaction-related routes.
type TransactionHandler struct {
	transactions TransactionRepository
	customers    CustomerRepository
}

// NewTransactionHandler creates a new TransactionHandler.
func NewTransactionHandler(transactions TransactionRepository, customers CustomerRepository) *TransactionHandler {
	return &TransactionHandler{transactions: transactions, customers: customers}
}

// ListForCustomer handles GET /v1/customers/{customerID}/transactions
func (h *TransactionHandler) ListForCustomer(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	customerID, err := uuid.Parse(chi.URLParam(r, "customerID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid customer ID format")
		return
	}

	if _, err := h.customers.GetByID(r.Context(), businessID, customerID); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Customer not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to verify customer")
		return
	}

	transactions, err := h.transactions.ListForCustomer(r.Context(), businessID, customerID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve transactions")
		return
	}
	if transactions == nil {
		transactions = []models.Transaction{}
	}
	respond(w, http.StatusOK, transactions)
}

// Create handles POST /v1/transactions
func (h *TransactionHandler) Create(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	userID := middleware.GetUserID(r.Context())

	var input struct {
		CustomerID      string  `json:"customer_id"`
		Type            string  `json:"type"`
		Amount          float64 `json:"amount"`
		Description     *string `json:"description"`
		TransactionDate *string `json:"transaction_date"`
	}
	if !decode(w, r, &input) {
		return
	}

	// Field-level validation using the fluent validator
	v := validate.New().
		IsUUID("customer_id", input.CustomerID).
		OneOf("type", input.Type, "debt", "payment").
		GreaterThan("amount", input.Amount, 0)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}
	customerID, _ := uuid.Parse(input.CustomerID)  // safe: IsUUID already validated
	txType := models.TransactionType(input.Type)    // safe: OneOf already validated

	// Default transaction_date to today if omitted
	txDate := time.Now().UTC()
	if input.TransactionDate != nil && *input.TransactionDate != "" {
		parsed, err := time.Parse("2006-01-02", *input.TransactionDate)
		if err != nil {
			respondValidationError(w, map[string]string{"transaction_date": "Must be in YYYY-MM-DD format"})
			return
		}
		txDate = parsed
	}

	if _, err := h.customers.GetByID(r.Context(), businessID, customerID); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Customer not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to verify customer")
		return
	}

	// Business Rule: payment cannot exceed current balance
	if txType == models.TransactionTypePayment {
		balance, err := h.customers.GetBalance(r.Context(), businessID, customerID)
		if err != nil {
			respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to check customer balance")
			return
		}
		if input.Amount > balance {
			respondError(w, http.StatusConflict, ErrCodeConflict,
				"Payment amount exceeds the customer's current outstanding balance")
			return
		}
	}

	transaction, err := h.transactions.Create(r.Context(), repository.CreateTransactionInput{
		BusinessID:      businessID,
		CustomerID:      customerID,
		UserID:          userID,
		Type:            txType,
		Amount:          input.Amount,
		Description:     input.Description,
		TransactionDate: txDate,
	})
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to record transaction")
		return
	}
	respond(w, http.StatusCreated, transaction)
}

// VoidTransaction handles DELETE /v1/transactions/{transactionID} (owner only)
func (h *TransactionHandler) VoidTransaction(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	transactionID, err := uuid.Parse(chi.URLParam(r, "transactionID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid transaction ID format")
		return
	}

	if err := h.transactions.SoftDelete(r.Context(), businessID, transactionID); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Transaction not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to void transaction")
		return
	}
	respond(w, http.StatusOK, map[string]string{"message": "Transaction voided successfully"})
}
