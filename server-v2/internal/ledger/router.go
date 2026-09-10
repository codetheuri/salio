package ledger

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
		OperationID: "list-customer-transactions",
		Method:      http.MethodGet,
		Path:        "/api/v1/customers/{customerID}/transactions",
		Summary:     "List a customer's ledger",
		Tags:        []string{"Transactions"},
	}, rbac.PermTransactionsRead), handler.ListForCustomer)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-transaction",
		Method:      http.MethodPost,
		Path:        "/api/v1/transactions",
		Summary:     "Record a debt or a payment",
		Tags:        []string{"Transactions"},
	}, rbac.PermTransactionsCreate), handler.Create)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "void-transaction",
		Method:      http.MethodDelete,
		Path:        "/api/v1/transactions/{transactionID}",
		Summary:     "Void a transaction (owner only)",
		Tags:        []string{"Transactions"},
	}, rbac.PermTransactionsVoid), handler.Void)
}
