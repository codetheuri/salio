package api

import (
	"log/slog"
	"net/http"

	"salio/server/internal/middleware"
	"salio/server/internal/repository"
)

type ReportHandler struct {
	repo *repository.ReportRepository
}

func NewReportHandler(repo *repository.ReportRepository) *ReportHandler {
	return &ReportHandler{repo: repo}
}

func (h *ReportHandler) GetSummary(w http.ResponseWriter, r *http.Request) {
	businessID := middleware.GetBusinessID(r.Context()).String()

	summary, err := h.repo.GetSummary(r.Context(), businessID)
	if err != nil {
		slog.Error("Database error in GetSummary", "error", err)
		respondError(w, http.StatusInternalServerError, ErrCodeInternal, "Failed to generate report summary")
		return
	}

	respond(w, http.StatusOK, summary)
}
