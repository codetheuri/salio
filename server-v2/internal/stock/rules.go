// Package stock tracks products that have run out, and the purchase orders
// placed with suppliers to restock them.
//
// A stock request ("Duodip 20ml, out since Tuesday") is noted the moment
// somebody notices an empty shelf, often with no signal, so requests sync like
// debts do. Requests not yet ordered are the shop's draft order. A purchase
// order is placed from them online, once quantities and a supplier are known;
// the server numbers it and renders it as a PDF to send.
package stock

import (
	"errors"
	"strings"

	"salio/server-v2/internal/domain"
)

var (
	ErrRequestNotFound    = errors.New("stock request not found")
	ErrOrderNotFound      = errors.New("purchase order not found")
	ErrProductRequired    = errors.New("a product name is required")
	ErrProductTooLong     = errors.New("the product name is longer than 255 characters")
	ErrInvalidDate        = errors.New("dates must be in YYYY-MM-DD format")
	ErrAlreadyOrdered     = errors.New("this product is already on a purchase order; cancel the order to change it")
	ErrSupplierRequired   = errors.New("a supplier name is required")
	ErrNoLines            = errors.New("a purchase order needs at least one product")
	ErrQuantityRequired   = errors.New("every product on the order needs a quantity greater than zero")
	ErrLineNeedsProduct   = errors.New("each line needs either a stock_request_id or a product_name")
	ErrDuplicateRequest   = errors.New("the same stock request appears twice on this order")
	ErrRequestUnavailable = errors.New("a stock request on this order does not exist, was deleted, or is already ordered")
	ErrOrderNotActive     = errors.New("this purchase order is already cancelled")
)

// ValidateRequest checks a stock request on its own terms. Shared by the REST
// handlers and the sync engine, so both paths enforce the same thing.
func ValidateRequest(r *domain.StockRequest) error {
	r.ProductName = strings.TrimSpace(r.ProductName)
	switch {
	case r.ProductName == "":
		return ErrProductRequired
	case len([]rune(r.ProductName)) > 255:
		return ErrProductTooLong
	case r.NeededOn.IsZero():
		return ErrInvalidDate
	}
	return nil
}

// CheckEditable refuses changing a request that is already on an order.
//
// What was sent to a supplier is what the order says. Editing or deleting a
// request underneath it would leave the shop's record of the order disagreeing
// with the document the supplier is holding.
func CheckEditable(r *domain.StockRequest) error {
	if r.PurchaseOrderID != nil {
		return ErrAlreadyOrdered
	}
	return nil
}
