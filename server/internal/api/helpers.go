package api

// This file defines the single, canonical response envelope for every API response.
// Every endpoint returns one of these two shapes — no exceptions.
//
// Success:
//   {"success": true, "data": { ... }}
//
// Error:
//   {"success": false, "error": {"code": "VALIDATION_ERROR", "message": "...", "details": {...}}}
//
// This contract lets the Flutter app (and any future client) handle responses
// generically without per-endpoint parsing logic.

import (
	"encoding/json"
	"log/slog"
	"net/http"
)

// --- Response Envelope ---

// response is the standard wrapper for ALL API responses.
type response struct {
	Success bool   `json:"success"`
	Data    any    `json:"data,omitempty"`
	Error   *apiError `json:"error,omitempty"`
}

// apiError is the structured error object inside a failed response.
type apiError struct {
	// Code is a machine-readable constant (never changes, safe for Flutter to switch on)
	Code    string            `json:"code"`
	// Message is a human-readable sentence shown to the developer or end user
	Message string            `json:"message"`
	// Details holds field-level validation errors, e.g. {"name": "cannot be blank"}
	Details map[string]string `json:"details,omitempty"`
}

// --- Error Code Constants ---
// Use these constants in handlers — never hardcode raw strings.

const (
	ErrCodeValidation   = "VALIDATION_ERROR"
	ErrCodeNotFound     = "NOT_FOUND"
	ErrCodeUnauthorized = "UNAUTHORIZED"
	ErrCodeForbidden    = "FORBIDDEN"
	ErrCodeConflict     = "BUSINESS_RULE_VIOLATION"
	ErrCodeInternal     = "INTERNAL_ERROR"
)

// --- Response Helpers ---

// respond sends a successful JSON response wrapped in the standard envelope.
func respond(w http.ResponseWriter, statusCode int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(response{Success: true, Data: data}); err != nil {
		slog.Error("Failed to encode response", "error", err)
	}
}

// respondError sends a structured error response.
// Use the ErrCode* constants for the code parameter.
func respondError(w http.ResponseWriter, statusCode int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(response{
		Success: false,
		Error:   &apiError{Code: code, Message: message},
	}); err != nil {
		slog.Error("Failed to encode error response", "error", err)
	}
}

// respondValidationError sends a 400 with field-level validation details.
// Example: respondValidationError(w, map[string]string{"name": "cannot be blank"})
func respondValidationError(w http.ResponseWriter, details map[string]string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusBadRequest)
	if err := json.NewEncoder(w).Encode(response{
		Success: false,
		Error: &apiError{
			Code:    ErrCodeValidation,
			Message: "The request contains invalid data. Check the 'details' field.",
			Details: details,
		},
	}); err != nil {
		slog.Error("Failed to encode validation error response", "error", err)
	}
}

// --- Request Helpers ---

// decode parses and validates the JSON request body.
// Returns false and writes an error response automatically on failure.
func decode(w http.ResponseWriter, r *http.Request, target any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1_048_576) // 1MB max body
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(target); err != nil {
		respondError(w, http.StatusBadRequest, ErrCodeValidation, "Invalid JSON body: "+err.Error())
		return false
	}
	return true
}
