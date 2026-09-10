package reports

import (
	"context"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
)

type Handler struct {
	service *Service
	log     logger.Logger
}

func NewHandler(service *Service, log logger.Logger) *Handler {
	return &Handler{service: service, log: log}
}

func (h *Handler) Summary(ctx context.Context, _ *SummaryInput) (*SummaryOutput, error) {
	summary, err := h.service.Summary(ctx)
	if err != nil {
		h.log.Error("reports module error building the summary", err)
		return nil, huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
	resp := &SummaryOutput{}
	resp.Body.Success = true
	resp.Body.Data = *summary
	return resp, nil
}
