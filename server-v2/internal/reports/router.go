package reports

import (
	"net/http"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"

	"salio/server-v2/internal/rbac"
)

func RegisterRoutes(api huma.API, db *gorm.DB, log logger.Logger) {
	handler := NewHandler(NewService(NewRepository(db)), log)
	guard := authz.NewGuard(api, db)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-summary",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/summary",
		Summary:     "Business dashboard: totals, top debtors, overdue debtors",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Summary)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-customer-statement",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/customers/{customerID}/statement",
		Summary:     "One customer's statement: opening balance, every entry, running balance",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Statement)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-customer-statement-pdf",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/customers/{customerID}/statement/pdf",
		Summary:     "The customer statement as a PDF to hand or send to the customer",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.StatementPDF)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-ageing",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/ageing",
		Summary:     "Unpaid debt by age: 0-30, 31-60, 61-90, over 90 days, per customer",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Ageing)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-due",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/due",
		Summary:     "Who to remind: customers past an agreed due date, or falling due soon",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Due)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-payables",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/payables",
		Summary:     "What the shop owes its suppliers, and what falls due soon (owner only)",
		Tags:        []string{"Reports"},
	}, rbac.PermSuppliersRead), handler.Payables)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-ageing-pdf",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/ageing/pdf",
		Summary:     "The debt ageing report as a PDF",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.AgeingPDF)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-sales",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/sales",
		Summary:     "Sales over a period: totals, cash vs credit, best sellers, day by day",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Sales)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-sales-pdf",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/sales/pdf",
		Summary:     "The sales report as a PDF",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.SalesPDF)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-collections",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/collections",
		Summary:     "Payments collected, advances held, and what each member of staff recorded",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.Collections)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "reports-collections-pdf",
		Method:      http.MethodGet,
		Path:        "/api/v1/reports/collections/pdf",
		Summary:     "The collections and staff activity report as a PDF",
		Tags:        []string{"Reports"},
	}, rbac.PermReportsRead), handler.CollectionsPDF)
}
