package reports

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"github.com/google/uuid"
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

// --- inputs and outputs for the detailed reports ---

type StatementInput struct {
	CustomerID uuid.UUID `path:"customerID"`
	PeriodInput
}

type StatementOutput struct {
	Body struct {
		Success bool          `json:"success"`
		Data    StatementView `json:"data"`
	}
}

type AgeingOutput struct {
	Body struct {
		Success bool       `json:"success"`
		Data    AgeingView `json:"data"`
	}
}

type SalesReportOutput struct {
	Body struct {
		Success bool            `json:"success"`
		Data    SalesReportView `json:"data"`
	}
}

type CollectionsOutput struct {
	Body struct {
		Success bool            `json:"success"`
		Data    CollectionsView `json:"data"`
	}
}

// ReportPDFOutput is a downloadable report.
type ReportPDFOutput struct {
	ContentType        string `header:"Content-Type"`
	ContentDisposition string `header:"Content-Disposition"`
	Body               []byte
}

func pdfOutput(data []byte, filename string) *ReportPDFOutput {
	return &ReportPDFOutput{
		ContentType:        "application/pdf",
		ContentDisposition: `attachment; filename="` + filename + `"`,
		Body:               data,
	}
}

func (h *Handler) Statement(ctx context.Context, in *StatementInput) (*StatementOutput, error) {
	v, err := h.service.Statement(ctx, in.CustomerID, in.PeriodInput)
	if err != nil {
		return nil, h.mapError(err, "building the statement")
	}
	resp := &StatementOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) StatementPDF(ctx context.Context, in *StatementInput) (*ReportPDFOutput, error) {
	v, err := h.service.Statement(ctx, in.CustomerID, in.PeriodInput)
	if err != nil {
		return nil, h.mapError(err, "building the statement")
	}
	data, name, err := h.service.repo.StatementPDF(ctx, v)
	if err != nil {
		return nil, h.mapError(err, "rendering the statement")
	}
	return pdfOutput(data, name), nil
}

func (h *Handler) Ageing(ctx context.Context, _ *SummaryInput) (*AgeingOutput, error) {
	v, err := h.service.Ageing(ctx)
	if err != nil {
		return nil, h.mapError(err, "building the ageing report")
	}
	resp := &AgeingOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) Due(ctx context.Context, in *DueInput) (*DueOutput, error) {
	v, err := h.service.Due(ctx, in.WithinDays)
	if err != nil {
		return nil, h.mapError(err, "building the due list")
	}
	resp := &DueOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) Payables(ctx context.Context, in *DueInput) (*PayablesOutput, error) {
	v, err := h.service.Payables(ctx, in.WithinDays)
	if err != nil {
		return nil, h.mapError(err, "building the payables report")
	}
	resp := &PayablesOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) AgeingPDF(ctx context.Context, _ *SummaryInput) (*ReportPDFOutput, error) {
	v, err := h.service.Ageing(ctx)
	if err != nil {
		return nil, h.mapError(err, "building the ageing report")
	}
	data, name, err := h.service.repo.AgeingPDF(ctx, v)
	if err != nil {
		return nil, h.mapError(err, "rendering the ageing report")
	}
	return pdfOutput(data, name), nil
}

func (h *Handler) Sales(ctx context.Context, in *PeriodInput) (*SalesReportOutput, error) {
	v, err := h.service.SalesReport(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "building the sales report")
	}
	resp := &SalesReportOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) SalesPDF(ctx context.Context, in *PeriodInput) (*ReportPDFOutput, error) {
	v, err := h.service.SalesReport(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "building the sales report")
	}
	data, name, err := h.service.repo.SalesPDF(ctx, v)
	if err != nil {
		return nil, h.mapError(err, "rendering the sales report")
	}
	return pdfOutput(data, name), nil
}

func (h *Handler) Collections(ctx context.Context, in *PeriodInput) (*CollectionsOutput, error) {
	v, err := h.service.Collections(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "building the collections report")
	}
	resp := &CollectionsOutput{}
	resp.Body.Success, resp.Body.Data = true, *v
	return resp, nil
}

func (h *Handler) CollectionsPDF(ctx context.Context, in *PeriodInput) (*ReportPDFOutput, error) {
	v, err := h.service.Collections(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "building the collections report")
	}
	data, name, err := h.service.repo.CollectionsPDF(ctx, v)
	if err != nil {
		return nil, h.mapError(err, "rendering the collections report")
	}
	return pdfOutput(data, name), nil
}

func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrCustomerNotFound):
		return huma.Error404NotFound(err.Error())
	case errors.Is(err, ErrInvalidDate), errors.Is(err, ErrPeriodBackwards), errors.Is(err, ErrPeriodTooLong):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("reports module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}
