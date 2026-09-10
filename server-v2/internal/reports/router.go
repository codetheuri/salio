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
}
