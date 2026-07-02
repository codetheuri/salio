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

// UserHandler handles profile, business settings, and staff management endpoints.
type UserHandler struct {
	users UserRepository
}

// NewUserHandler creates a new UserHandler.
func NewUserHandler(users UserRepository) *UserHandler {
	return &UserHandler{users: users}
}

// Me handles GET /v1/users/me
// Returns the full profile of the currently authenticated user + their business.
// Flutter calls this on first login to populate the Settings screen with real data.
func (h *UserHandler) Me(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())
	businessID := middleware.GetBusinessID(r.Context())

	user, err := h.users.GetUserByID(r.Context(), userID)
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "User account not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve user profile")
		return
	}

	business, err := h.users.GetBusiness(r.Context(), businessID)
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Business not found")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve business details")
		return
	}

	respond(w, http.StatusOK, map[string]any{
		"user":     user,
		"business": business,
	})
}

// UpdateMe handles PUT /v1/users/me
// Allows any authenticated user to update their own display name.
func (h *UserHandler) UpdateMe(w http.ResponseWriter, r *http.Request) {
	userID := middleware.GetUserID(r.Context())

	var input struct {
		Name string `json:"name"`
	}
	if !decode(w, r, &input) {
		return
	}

	v := validate.New().Required("name", input.Name)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}

	user, err := h.users.UpdateUser(r.Context(), userID, repository.UpdateUserInput{
		Name: strings.TrimSpace(input.Name),
	})
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to update profile")
		return
	}

	respond(w, http.StatusOK, user)
}

// UpdateBusiness handles PUT /v1/business (owner only)
// Allows the owner to rename their shop or update its type.
// The RequireRole("owner") middleware enforces the role restriction.
func (h *UserHandler) UpdateBusiness(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())

	var input struct {
		Name string  `json:"name"`
		Type *string `json:"type"`
	}
	if !decode(w, r, &input) {
		return
	}

	v := validate.New().Required("name", input.Name)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}

	business, err := h.users.UpdateBusiness(r.Context(), businessID, repository.UpdateBusinessInput{
		Name: strings.TrimSpace(input.Name),
		Type: input.Type,
	})
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to update business")
		return
	}

	respond(w, http.StatusOK, business)
}

// ListStaff handles GET /v1/staff (owner only — but staff can see read-only per PRD)
// Returns all active users in the authenticated user's business.
func (h *UserHandler) ListStaff(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())

	staff, err := h.users.ListStaff(r.Context(), businessID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to retrieve staff list")
		return
	}
	if staff == nil {
		staff = []models.User{}
	}

	respond(w, http.StatusOK, staff)
}

// DeactivateStaff handles DELETE /v1/staff/{userID} (owner only)
// Deactivates a staff member — they can no longer log in.
// Their transaction history is preserved (soft deactivation, not deletion).
// Business rule: an owner cannot deactivate themselves (enforced in the repository).
func (h *UserHandler) DeactivateStaff(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())
	callerID := middleware.GetUserID(r.Context())

	targetID, err := uuid.Parse(chi.URLParam(r, "userID"))
	if err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid user ID format")
		return
	}

	// Prevent an owner from accidentally removing themselves
	if targetID == callerID {
		respondError(w, http.StatusConflict, ErrCodeConflict, "You cannot remove yourself from the business")
		return
	}

	if err := h.users.DeactivateStaff(r.Context(), businessID, targetID); err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			respondError(w, http.StatusNotFound, ErrCodeNotFound, "Staff member not found or is not a staff account")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to remove staff member")
		return
	}

	respond(w, http.StatusOK, map[string]string{
		"message": "Staff member deactivated. They will no longer be able to log in.",
	})
}
