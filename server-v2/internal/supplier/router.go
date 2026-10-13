package supplier

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
	tags := []string{"Suppliers"}

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-suppliers",
		Method:      http.MethodGet,
		Path:        "/api/v1/suppliers",
		Summary:     "List suppliers, with what the shop owes each",
		Tags:        tags,
	}, rbac.PermSuppliersRead), handler.List)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-supplier",
		Method:      http.MethodPost,
		Path:        "/api/v1/suppliers",
		Summary:     "Add a supplier",
		Tags:        tags,
	}, rbac.PermSuppliersManage), handler.Create)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-supplier",
		Method:      http.MethodGet,
		Path:        "/api/v1/suppliers/{supplierID}",
		Summary:     "Get a supplier, with balance",
		Tags:        tags,
	}, rbac.PermSuppliersRead), handler.Get)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "update-supplier",
		Method:      http.MethodPut,
		Path:        "/api/v1/suppliers/{supplierID}",
		Summary:     "Edit a supplier",
		Tags:        tags,
	}, rbac.PermSuppliersManage), handler.Update)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "delete-supplier",
		Method:      http.MethodDelete,
		Path:        "/api/v1/suppliers/{supplierID}",
		Summary:     "Delete a supplier (requires a zero balance)",
		Tags:        tags,
	}, rbac.PermSuppliersManage), handler.Delete)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-supplier-entries",
		Method:      http.MethodGet,
		Path:        "/api/v1/suppliers/{supplierID}/transactions",
		Summary:     "List a supplier's bills and payments",
		Tags:        tags,
	}, rbac.PermSuppliersRead), handler.Entries)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-supplier-entry",
		Method:      http.MethodPost,
		Path:        "/api/v1/supplier-transactions",
		Summary:     "Record a supplier bill (goods on credit) or a payment to a supplier",
		Tags:        tags,
	}, rbac.PermSuppliersManage), handler.RecordEntry)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-supplier-entry",
		Method:      http.MethodGet,
		Path:        "/api/v1/supplier-transactions/{entryID}",
		Summary:     "View one supplier bill or payment, including a voided one",
		Tags:        tags,
	}, rbac.PermSuppliersRead), handler.GetEntry)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "void-supplier-entry",
		Method:      http.MethodDelete,
		Path:        "/api/v1/supplier-transactions/{entryID}",
		Summary:     "Void a supplier bill or payment",
		Tags:        tags,
	}, rbac.PermSuppliersVoid), handler.VoidEntry)
}
