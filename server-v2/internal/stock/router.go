package stock

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
		OperationID: "create-stock-request", Method: http.MethodPost,
		Path: "/api/v1/stock-requests", Summary: "Note a product that has run out and needs ordering",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRequest), handler.CreateRequest)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-stock-requests", Method: http.MethodGet,
		Path: "/api/v1/stock-requests", Summary: "List stock requests; pending ones are the draft order",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRead), handler.ListRequests)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "update-stock-request", Method: http.MethodPut,
		Path: "/api/v1/stock-requests/{requestID}", Summary: "Edit a stock request that is not yet ordered",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRequest), handler.UpdateRequest)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "delete-stock-request", Method: http.MethodDelete,
		Path: "/api/v1/stock-requests/{requestID}", Summary: "Remove a stock request that is not yet ordered",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRequest), handler.DeleteRequest)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-purchase-order", Method: http.MethodPost,
		Path: "/api/v1/purchase-orders", Summary: "Place a purchase order, with a quantity for every product (owner only)",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermPurchaseOrdersManage), handler.CreateOrder)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-purchase-orders", Method: http.MethodGet,
		Path: "/api/v1/purchase-orders", Summary: "List purchase orders, newest first",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRead), handler.ListOrders)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-purchase-order", Method: http.MethodGet,
		Path: "/api/v1/purchase-orders/{orderID}", Summary: "View one purchase order",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRead), handler.GetOrder)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "purchase-order-pdf", Method: http.MethodGet,
		Path: "/api/v1/purchase-orders/{orderID}/pdf", Summary: "Download a purchase order as a PDF to send to the supplier",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermStockRead), handler.OrderPDF)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "cancel-purchase-order", Method: http.MethodPost,
		Path: "/api/v1/purchase-orders/{orderID}/cancel", Summary: "Cancel an order; its products return to the order list (owner only)",
		Tags: []string{"Stock & Orders"},
	}, rbac.PermPurchaseOrdersManage), handler.CancelOrder)
}
