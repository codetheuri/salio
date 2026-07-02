package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"salio/server/internal/middleware"
	"salio/server/internal/models"
	"salio/server/internal/repository"
	"salio/server/pkg/validate"
)

// AuthHandler handles all HTTP requests for the /v1/auth/* routes.
type AuthHandler struct {
	repo           AuthRepository // depends on interface, not concrete type
	jwtSecret      string
	jwtExpiryHours int
}

// NewAuthHandler creates a new AuthHandler.
func NewAuthHandler(repo AuthRepository, jwtSecret string, jwtExpiryHours int) *AuthHandler {
	return &AuthHandler{repo: repo, jwtSecret: jwtSecret, jwtExpiryHours: jwtExpiryHours}
}

// RegisterBusiness handles POST /v1/auth/register-business
func (h *AuthHandler) RegisterBusiness(w http.ResponseWriter, r *http.Request) {
	var input struct {
		BusinessName string `json:"business_name"`
		OwnerName    string `json:"owner_name"`
		Phone        string `json:"phone"`
		Password     string `json:"password"`
	}
	if !decode(w, r, &input) {
		return
	}

	// Field-level validation using the fluent validator
	v := validate.New().
		Required("business_name", input.BusinessName).
		Required("owner_name", input.OwnerName).
		Required("phone", input.Phone).
		MinLen("password", input.Password, 4)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}

	user, err := h.repo.RegisterBusiness(r.Context(), repository.RegisterBusinessInput{
		BusinessName: input.BusinessName,
		OwnerName:    input.OwnerName,
		Phone:        input.Phone,
		Password:     input.Password,
	})
	if err != nil {
		if errors.Is(err, repository.ErrPhoneAlreadyExists) {
			respondError(w, http.StatusConflict, ErrCodeConflict, "This phone number is already registered to another account")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to create account. Please try again.")
		return
	}

	token, err := h.generateToken(user)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Account created but failed to generate token")
		return
	}

	respond(w, http.StatusCreated, map[string]any{"token": token, "user": user})
}

// Login handles POST /v1/auth/login
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var input struct {
		Phone    string `json:"phone"`
		Password string `json:"password"`
	}
	if !decode(w, r, &input) {
		return
	}

	v := validate.New().
		Required("phone", input.Phone).
		Required("password", input.Password)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}

	user, err := h.repo.GetUserByPhone(r.Context(), input.Phone)
	if err != nil {
		// Generic message — never reveal whether a phone exists
		respondError(w, http.StatusUnauthorized, ErrCodeUnauthorized, "Invalid phone number or password")
		return
	}
	if !repository.VerifyPassword(user.PasswordHash, input.Password) {
		respondError(w, http.StatusUnauthorized, ErrCodeUnauthorized, "Invalid phone number or password")
		return
	}

	token, err := h.generateToken(user)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to generate token")
		return
	}

	respond(w, http.StatusOK, map[string]any{"token": token, "user": user})
}

// GenerateInvite handles POST /v1/auth/invite (owner only)
func (h *AuthHandler) GenerateInvite(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context())

	code, err := h.repo.CreateInviteCode(r.Context(), businessID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to generate invite code")
		return
	}

	respond(w, http.StatusCreated, map[string]string{
		"invite_code": code,
		"expires_in":  "24 hours",
		"note":        "Share this code with your staff member. It can only be used once.",
	})
}

// JoinBusiness handles POST /v1/auth/join
func (h *AuthHandler) JoinBusiness(w http.ResponseWriter, r *http.Request) {
	var input struct {
		InviteCode string `json:"invite_code"`
		Name       string `json:"name"`
		Phone      string `json:"phone"`
		Password   string `json:"password"`
	}
	if !decode(w, r, &input) {
		return
	}

	v := validate.New().
		Required("invite_code", input.InviteCode).
		Required("name", input.Name).
		Required("phone", input.Phone).
		MinLen("password", input.Password, 4)
	if v.HasErrors() {
		respondValidationError(w, v.Errors())
		return
	}

	user, err := h.repo.JoinBusiness(r.Context(), repository.JoinBusinessInput{
		InviteCode: input.InviteCode,
		StaffName:  input.Name,
		Phone:      input.Phone,
		Password:   input.Password,
	})
	if err != nil {
		if errors.Is(err, repository.ErrInvalidInviteCode) {
			respondError(w, http.StatusBadRequest, ErrCodeValidation, "The invite code is invalid or has already expired")
			return
		}
		if errors.Is(err, repository.ErrPhoneAlreadyExists) {
			respondError(w, http.StatusConflict, ErrCodeConflict, "This phone number is already registered to another account")
			return
		}
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to join business. Please try again.")
		return
	}

	token, err := h.generateToken(user)
	if err != nil {
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Account created but failed to generate token")
		return
	}

	respond(w, http.StatusCreated, map[string]any{"token": token, "user": user})
}

// generateToken creates a signed JWT for the given user.
func (h *AuthHandler) generateToken(user *models.User) (string, error) {
	expiry := time.Now().Add(time.Duration(h.jwtExpiryHours) * time.Hour)
	claims := middleware.Claims{
		UserID:     user.ID,
		BusinessID: user.BusinessID,
		Role:       user.Role,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expiry),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Subject:   user.ID.String(),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(h.jwtSecret))
}
