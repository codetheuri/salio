package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"salio/server/internal/middleware"
	"salio/server/internal/models"
	"salio/server/internal/repository"
	"salio/server/pkg/validate"
)

// CustomerHandler handles all HTTP requests for /v1/customers/*.
type CustomerHandler struct {
	customers    CustomerRepository
	transactions TransactionRepository
}

// NewCustomerHandler creates a new CustomerHandler.
func NewCustomerHandler(customers CustomerRepository, transactions TransactionRepository) *CustomerHandler {
	return &CustomerHandler{customers: customers, transactions: transactions}
}

// List handles GET /v1/customers?search=
// Returns all active customers, optionally filtered by name (case-insensitive).
func (h *CustomerHandler) List(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	search := strings.TrimSpace(r.URL.Query().Get("search"))

	customers, err := h.customers.List(r.Context(), businessID, search)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve customers")
		return
	}
	if customers == nil {
		customers = []models.Customer{}
	}
	respond(w, http.StatusOK, customers)
}

// Create handles POST /v1/customers
func (h *CustomerHandler) Create(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	userID := middleware.GetUserID(r.Context())

	var input struct {
		Name  string  `json:"name"`
		Phone *string `json:"phone"`
		Notes *string `json:"notes"`
	}
	if !decode(w, r, &input) {
		return
	}

	v := validate.New().Required("name", input.Name)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}
	name := strings.TrimSpace(input.Name)

	customer, err := h.customers.Create(r.Context(), repository.CreateCustomerInput{
		BusinessID: businessID,
		CreatedBy:  userID,
		Name:       name,
		Phone:      input.Phone,
		Notes:      input.Notes,
	})
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to create customer")
		return
	}
	respond(w, http.StatusCreated, customer)
}

// GetByID handles GET /v1/customers/{customerID}
func (h *CustomerHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	customerID, err := uuid.Parse(chi.URLParam(r, "customerID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid customer ID format")
		return
	}

	customer, err := h.customers.GetByID(r.Context(), businessID, customerID)
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Customer not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve customer")
		return
	}

	balance, err := h.customers.GetBalance(r.Context(), businessID, customerID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to calculate customer balance")
		return
	}

	respond(w, http.StatusOK, map[string]any{"customer": customer, "balance": balance})
}

// Update handles PUT /v1/customers/{customerID}
func (h *CustomerHandler) Update(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	customerID, err := uuid.Parse(chi.URLParam(r, "customerID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid customer ID format")
		return
	}

	var input struct {
		Name  string  `json:"name"`
		Phone *string `json:"phone"`
		Notes *string `json:"notes"`
	}
	if !decode(w, r, &input) {
		return
	}

	name := strings.TrimSpace(input.Name)
	if name == "" {
		respondValidationError(w, map[string]string{"name": "Customer name cannot be blank"})
		return
	}

	customer, err := h.customers.Update(r.Context(), businessID, customerID, repository.UpdateCustomerInput{
		Name:  name,
		Phone: input.Phone,
		Notes: input.Notes,
	})
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Customer not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to update customer")
		return
	}
	respond(w, http.StatusOK, customer)
}

// Delete handles DELETE /v1/customers/{customerID} (owner only)
func (h *CustomerHandler) Delete(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	customerID, err := uuid.Parse(chi.URLParam(r, "customerID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid customer ID format")
		return
	}

	// Business Rule: cannot delete a customer with an outstanding balance
	balance, err := h.customers.GetBalance(r.Context(), businessID, customerID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to check customer balance")
		return
	}
	if balance != 0 {
		respondError(w, http.StatusConflict, ErrCodeConflict,
			"Cannot delete a customer with a non-zero balance. Record a payment to clear the balance first.")
		return
	}

	if err := h.customers.SoftDelete(r.Context(), businessID, customerID); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Customer not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to delete customer")
		return
	}
	respond(w, http.StatusOK, map[string]string{"message": "Customer deleted successfully"})
}
