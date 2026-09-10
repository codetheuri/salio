package ledger

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/authz"
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

func (h *Handler) ListForCustomer(ctx context.Context, in *ListForCustomerInput) (*ListOutput, error) {
	txs, err := h.service.ListForCustomer(ctx, in.CustomerID)
	if err != nil {
		return nil, h.mapError(err, "listing transactions")
	}
	resp := &ListOutput{}
	resp.Body.Success = true
	resp.Body.Data = txs
	return resp, nil
}

func (h *Handler) Create(ctx context.Context, in *CreateInput) (*TransactionOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.Create(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "recording the transaction")
	}
	resp := &TransactionOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Transaction recorded"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) Void(ctx context.Context, in *TransactionIDInput) (*MessageOutput, error) {
	if err := h.service.Void(ctx, in.TransactionID); err != nil {
		return nil, h.mapError(err, "voiding the transaction")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Transaction voided"
	return resp, nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrNotFound):
		return huma.Error404NotFound("Transaction not found")
	case errors.Is(err, ErrCustomerNotFound):
		return huma.Error404NotFound("Customer not found")
	case errors.Is(err, ErrExceedsBalance):
		return huma.Error409Conflict(err.Error())
	case errors.Is(err, ErrInvalidDate), errors.Is(err, ErrInvalidType), errors.Is(err, ErrNonPositiveAmount):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("ledger module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}
