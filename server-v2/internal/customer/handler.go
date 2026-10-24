package customer

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/query"
	"github.com/danielgtaylor/huma/v2"

	"salio/server-v2/internal/phone"
)

type Handler struct {
	service *Service
	log     logger.Logger
}

func NewHandler(service *Service, log logger.Logger) *Handler {
	return &Handler{service: service, log: log}
}

func (h *Handler) List(ctx context.Context, in *ListInput) (*ListOutput, error) {
	q := query.Query{Page: in.Page, PerPage: in.PerPage, Search: in.Search}

	views, meta, err := h.service.List(ctx, q)
	if err != nil {
		return nil, h.mapError(err, "listing customers")
	}

	resp := &ListOutput{}
	resp.Body.Success = true
	resp.Body.Data = views
	resp.Body.Meta.Page = meta.Page
	resp.Body.Meta.PerPage = meta.PerPage
	resp.Body.Meta.Total = meta.Total
	resp.Body.Meta.TotalPages = meta.TotalPages
	return resp, nil
}

func (h *Handler) Get(ctx context.Context, in *CustomerIDInput) (*CustomerOutput, error) {
	v, err := h.service.Get(ctx, in.CustomerID)
	if err != nil {
		return nil, h.mapError(err, "loading the customer")
	}
	return output(*v, ""), nil
}

func (h *Handler) Create(ctx context.Context, in *CreateInput) (*CustomerOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.Create(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "creating the customer")
	}
	return output(*v, "Customer created"), nil
}

func (h *Handler) Update(ctx context.Context, in *UpdateInput) (*CustomerOutput, error) {
	v, err := h.service.Update(ctx, in.CustomerID, *in)
	if err != nil {
		return nil, h.mapError(err, "updating the customer")
	}
	return output(*v, "Customer updated"), nil
}

func (h *Handler) SetCreditLimit(ctx context.Context, in *SetCreditLimitInput) (*CustomerOutput, error) {
	v, err := h.service.SetCreditLimit(ctx, in.CustomerID, in.Body.CreditLimit)
	if err != nil {
		return nil, h.mapError(err, "setting the credit limit")
	}
	message := "Credit limit set"
	if in.Body.CreditLimit == nil {
		message = "Credit limit removed"
	}
	return output(*v, message), nil
}

func (h *Handler) Delete(ctx context.Context, in *CustomerIDInput) (*MessageOutput, error) {
	if err := h.service.Delete(ctx, in.CustomerID); err != nil {
		return nil, h.mapError(err, "deleting the customer")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Customer deleted"
	return resp, nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrNotFound):
		return huma.Error404NotFound("Customer not found")
	case errors.Is(err, ErrPhoneTaken):
		return huma.Error409Conflict(err.Error())
	case errors.Is(err, ErrHasBalance):
		return huma.Error409Conflict(err.Error())
	case errors.Is(err, ErrNegativeCreditLimit):
		return huma.Error422UnprocessableEntity(err.Error())
	case errors.Is(err, phone.ErrInvalid):
		return huma.Error422UnprocessableEntity(err.Error(),
			&huma.ErrorDetail{Location: "body.phone", Message: err.Error()})
	default:
		h.log.Error("customer module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}

func output(v CustomerView, message string) *CustomerOutput {
	resp := &CustomerOutput{}
	resp.Body.Success = true
	resp.Body.Message = message
	resp.Body.Data = v
	return resp
}
