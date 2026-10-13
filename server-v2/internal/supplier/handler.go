package supplier

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

func (h *Handler) List(ctx context.Context, in *ListInput) (*ListOutput, error) {
	rows, err := h.service.List(ctx, in.Search)
	if err != nil {
		return nil, h.mapError(err, "listing suppliers")
	}
	resp := &ListOutput{}
	resp.Body.Success = true
	resp.Body.Data = rows
	return resp, nil
}

func (h *Handler) Get(ctx context.Context, in *SupplierIDInput) (*SupplierOutput, error) {
	v, err := h.service.Get(ctx, in.SupplierID)
	if err != nil {
		return nil, h.mapError(err, "loading the supplier")
	}
	return supplierOutput(*v, ""), nil
}

func (h *Handler) Create(ctx context.Context, in *CreateInput) (*SupplierOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.Create(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "adding the supplier")
	}
	return supplierOutput(*v, "Supplier added"), nil
}

func (h *Handler) Update(ctx context.Context, in *UpdateInput) (*SupplierOutput, error) {
	v, err := h.service.Update(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "updating the supplier")
	}
	return supplierOutput(*v, "Supplier updated"), nil
}

func (h *Handler) Delete(ctx context.Context, in *SupplierIDInput) (*MessageOutput, error) {
	if err := h.service.Delete(ctx, in.SupplierID); err != nil {
		return nil, h.mapError(err, "deleting the supplier")
	}
	return message("Supplier deleted"), nil
}

func (h *Handler) Entries(ctx context.Context, in *SupplierIDInput) (*EntriesOutput, error) {
	rows, err := h.service.Entries(ctx, in.SupplierID)
	if err != nil {
		return nil, h.mapError(err, "listing supplier entries")
	}
	resp := &EntriesOutput{}
	resp.Body.Success = true
	resp.Body.Data = rows
	return resp, nil
}

func (h *Handler) RecordEntry(ctx context.Context, in *CreateEntryInput) (*EntryOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.RecordEntry(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "recording the supplier entry")
	}
	msg := "Bill recorded"
	if v.Type == "payment" {
		msg = "Payment recorded"
	}
	return entryOutput(*v, msg), nil
}

func (h *Handler) GetEntry(ctx context.Context, in *EntryIDInput) (*EntryOutput, error) {
	v, err := h.service.GetEntry(ctx, in.EntryID)
	if err != nil {
		return nil, h.mapError(err, "loading the supplier entry")
	}
	return entryOutput(*v, ""), nil
}

func (h *Handler) VoidEntry(ctx context.Context, in *EntryIDInput) (*MessageOutput, error) {
	if err := h.service.VoidEntry(ctx, in.EntryID); err != nil {
		return nil, h.mapError(err, "voiding the supplier entry")
	}
	return message("Entry voided"), nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrNotFound), errors.Is(err, ErrEntryNotFound):
		return huma.Error404NotFound(err.Error())
	case errors.Is(err, ErrHasBalance), errors.Is(err, payment.ErrDuplicateMpesaRef):
		return huma.Error409Conflict(err.Error())
	case IsRuleError(err):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("supplier module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}

func supplierOutput(v SupplierView, msg string) *SupplierOutput {
	resp := &SupplierOutput{}
	resp.Body.Success = true
	resp.Body.Message = msg
	resp.Body.Data = v
	return resp
}

func entryOutput(v EntryView, msg string) *EntryOutput {
	resp := &EntryOutput{}
	resp.Body.Success = true
	resp.Body.Message = msg
	resp.Body.Data = v
	return resp
}

func message(msg string) *MessageOutput {
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = msg
	return resp
}
