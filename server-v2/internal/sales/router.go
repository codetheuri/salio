package sales

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
		OperationID: "record-sale",
		Method:      http.MethodPost,
		Path:        "/api/v1/sales",
		Summary:     "Record a sale, in cash or on a customer's account",
		Tags:        []string{"Sales"},
	}, rbac.PermSalesCreate), handler.Create)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-sales",
		Method:      http.MethodGet,
		Path:        "/api/v1/sales",
		Summary:     "List sales in a date range",
		Tags:        []string{"Sales"},
	}, rbac.PermSalesRead), handler.List)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-sale",
		Method:      http.MethodGet,
		Path:        "/api/v1/sales/{saleID}",
		Summary:     "View one sale",
		Tags:        []string{"Sales"},
	}, rbac.PermSalesRead), handler.Get)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "void-sale",
		Method:      http.MethodDelete,
		Path:        "/api/v1/sales/{saleID}",
		Summary:     "Void a sale, and its debt if sold on credit (owner only)",
		Tags:        []string{"Sales"},
	}, rbac.PermSalesVoid), handler.Void)
}
