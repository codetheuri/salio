package sales

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"

	"salio/server-v2/internal/payment"
)

type Handler struct {
	service *Service
	log     logger.Logger
}

func NewHandler(service *Service, log logger.Logger) *Handler {
	return &Handler{service: service, log: log}
}

func (h *Handler) Create(ctx context.Context, in *CreateInput) (*SaleOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.Create(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "recording the sale")
	}
	resp := &SaleOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Sale recorded"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) Get(ctx context.Context, in *SaleIDInput) (*SaleOutput, error) {
	v, err := h.service.Get(ctx, in.SaleID)
	if err != nil {
		return nil, h.mapError(err, "loading the sale")
	}
	resp := &SaleOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Sale found"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) List(ctx context.Context, in *ListInput) (*ListOutput, error) {
	rows, total, err := h.service.List(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "listing sales")
	}
	resp := &ListOutput{}
	resp.Body.Success = true
	resp.Body.Data = rows
	resp.Body.Total = total
	resp.Body.Page = in.Page
	resp.Body.PerPage = in.PerPage
	return resp, nil
}

func (h *Handler) Void(ctx context.Context, in *SaleIDInput) (*MessageOutput, error) {
	if err := h.service.Void(ctx, in.SaleID); err != nil {
		return nil, h.mapError(err, "voiding the sale")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Sale voided"
	return resp, nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrNotFound):
		return huma.Error404NotFound("Sale not found")
	case errors.Is(err, ErrCustomerNotFound):
		return huma.Error404NotFound("Customer not found")
	case errors.Is(err, payment.ErrDuplicateMpesaRef):
		return huma.Error409Conflict(err.Error())
	case IsRuleError(err):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("sales module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}
