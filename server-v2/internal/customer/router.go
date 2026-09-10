package customer

import (
	"net/http"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"

	"salio/server-v2/internal/rbac"
)

func RegisterRoutes(api huma.API, db *gorm.DB, log logger.Logger) {
	service := NewService(NewRepository(db))
	handler := NewHandler(service, log)
	guard := authz.NewGuard(api, db)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-customers",
		Method:      http.MethodGet,
		Path:        "/api/v1/customers",
		Summary:     "List customers",
		Tags:        []string{"Customers"},
	}, rbac.PermCustomersRead), handler.List)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-customer",
		Method:      http.MethodGet,
		Path:        "/api/v1/customers/{customerID}",
		Summary:     "Get a customer, with balance",
		Tags:        []string{"Customers"},
	}, rbac.PermCustomersRead), handler.Get)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-customer",
		Method:      http.MethodPost,
		Path:        "/api/v1/customers",
		Summary:     "Add a customer",
		Tags:        []string{"Customers"},
	}, rbac.PermCustomersCreate), handler.Create)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "update-customer",
		Method:      http.MethodPut,
		Path:        "/api/v1/customers/{customerID}",
		Summary:     "Edit a customer",
		Tags:        []string{"Customers"},
	}, rbac.PermCustomersUpdate), handler.Update)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "delete-customer",
		Method:      http.MethodDelete,
		Path:        "/api/v1/customers/{customerID}",
		Summary:     "Delete a customer (owner only, requires a zero balance)",
		Tags:        []string{"Customers"},
	}, rbac.PermCustomersDelete), handler.Delete)
}
