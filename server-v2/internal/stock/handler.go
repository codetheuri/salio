package stock

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

// PDFOutput is a downloadable document.
type PDFOutput struct {
	ContentType        string `header:"Content-Type"`
	ContentDisposition string `header:"Content-Disposition"`
	Body               []byte
}

func (h *Handler) CreateRequest(ctx context.Context, in *CreateRequestInput) (*RequestOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.CreateRequest(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "noting the stock request")
	}
	resp := &RequestOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Added to the order list"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) ListRequests(ctx context.Context, in *ListRequestsInput) (*RequestListOutput, error) {
	rows, err := h.service.ListRequests(ctx, in.Status)
	if err != nil {
		return nil, h.mapError(err, "listing stock requests")
	}
	resp := &RequestListOutput{}
	resp.Body.Success = true
	resp.Body.Data = rows
	return resp, nil
}

func (h *Handler) UpdateRequest(ctx context.Context, in *UpdateRequestInput) (*RequestOutput, error) {
	v, err := h.service.UpdateRequest(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "updating the stock request")
	}
	resp := &RequestOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Stock request updated"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) DeleteRequest(ctx context.Context, in *RequestIDInput) (*MessageOutput, error) {
	if err := h.service.DeleteRequest(ctx, in.RequestID); err != nil {
		return nil, h.mapError(err, "removing the stock request")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Removed from the order list"
	return resp, nil
}

func (h *Handler) CreateOrder(ctx context.Context, in *CreateOrderInput) (*OrderOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	v, err := h.service.CreateOrder(ctx, sub.UserID, *in)
	if err != nil {
		return nil, h.mapError(err, "placing the purchase order")
	}
	resp := &OrderOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Purchase order " + v.Reference + " created"
	resp.Body.Data = *v
	return resp, nil
}

func (h *Handler) ListOrders(ctx context.Context, in *ListOrdersInput) (*OrderListOutput, error) {
	rows, err := h.service.ListOrders(ctx, in.Status)
	if err != nil {
		return nil, h.mapError(err, "listing purchase orders")
	}
	resp := &OrderListOutput{}
	resp.Body.Success = true
	resp.Body.Data = rows
	return resp, nil
}

func (h *Handler) GetOrder(ctx context.Context, in *OrderIDInput) (*OrderOutput, error) {
	o, err := h.service.GetOrder(ctx, in.OrderID)
	if err != nil {
		return nil, h.mapError(err, "loading the purchase order")
	}
	resp := &OrderOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Purchase order found"
	resp.Body.Data = orderView(*o)
	return resp, nil
}

func (h *Handler) CancelOrder(ctx context.Context, in *OrderIDInput) (*MessageOutput, error) {
	if err := h.service.CancelOrder(ctx, in.OrderID); err != nil {
		return nil, h.mapError(err, "cancelling the purchase order")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Purchase order cancelled; its products are back on the order list"
	return resp, nil
}

func (h *Handler) OrderPDF(ctx context.Context, in *OrderIDInput) (*PDFOutput, error) {
	data, filename, err := h.service.OrderPDF(ctx, in.OrderID)
	if err != nil {
		return nil, h.mapError(err, "rendering the purchase order")
	}
	return &PDFOutput{
		ContentType:        "application/pdf",
		ContentDisposition: `attachment; filename="` + filename + `"`,
		Body:               data,
	}, nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrRequestNotFound), errors.Is(err, ErrOrderNotFound):
		return huma.Error404NotFound(err.Error())
	case errors.Is(err, ErrAlreadyOrdered), errors.Is(err, ErrRequestUnavailable),
		errors.Is(err, ErrOrderNotActive):
		return huma.Error409Conflict(err.Error())
	case errors.Is(err, ErrProductRequired), errors.Is(err, ErrProductTooLong),
		errors.Is(err, ErrInvalidDate), errors.Is(err, ErrSupplierRequired),
		errors.Is(err, ErrNoLines), errors.Is(err, ErrQuantityRequired),
		errors.Is(err, ErrLineNeedsProduct), errors.Is(err, ErrDuplicateRequest):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("stock module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}
