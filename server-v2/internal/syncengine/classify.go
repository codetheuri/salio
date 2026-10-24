package syncengine

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/payment"
	"salio/server-v2/internal/sales"
	"salio/server-v2/internal/stock"
	"salio/server-v2/internal/supplier"
)

// classify decides whether an error is the record's fault — reported as a
// conflict, with the push carrying on — or something that has to abort it.
//
// Two kinds belong to the record. A rule from the module that owns it (a
// customer with a balance, a credit sale with no customer). And a constraint
// the database enforced — SQLSTATE class 23, integrity violations — which is
// how a duplicate phone number arrives. Everything else (a dropped connection,
// a serialisation failure) is not the record's fault, and reporting it as a
// conflict would tell the phone to give up on a record that would succeed on
// retry.
func classify(err error) (reason, detail string, ok bool) {
	switch {
	case errors.Is(err, customer.ErrHasBalance), errors.Is(err, supplier.ErrHasBalance):
		return ReasonHasBalance, err.Error(), true
	case errors.Is(err, sales.ErrCustomerNotFound):
		return ReasonUnknownCustomer, err.Error(), true
	case errors.Is(err, sales.ErrNotFound):
		return ReasonUnknownSale, err.Error(), true
	case errors.Is(err, supplier.ErrNotFound):
		return ReasonUnknownSupplier, err.Error(), true
	case errors.Is(err, payment.ErrDuplicateMpesaRef):
		return ReasonDuplicate, mpesaDuplicateDetail, true
	case isRuleError(err):
		return ReasonInvalid, err.Error(), true
	}

	var state interface{ SQLState() string }
	if errors.As(err, &state) && strings.HasPrefix(state.SQLState(), "23") {
		if state.SQLState() == "23505" {
			return ReasonDuplicate, duplicateDetail(err), true
		}
		return ReasonInvalid, "the record breaks a rule the database enforces: " + err.Error(), true
	}
	return "", "", false
}

// isRuleError: each module owns its list of rule errors, so a rule added there
// is reported as a conflict here without anyone remembering to add it twice.
func isRuleError(err error) bool {
	return ledger.IsRuleError(err) || sales.IsRuleError(err) || supplier.IsRuleError(err) ||
		errors.Is(err, ledger.ErrBelongsToSale) ||
		errors.Is(err, stock.ErrProductRequired) || errors.Is(err, stock.ErrProductTooLong) ||
		errors.Is(err, stock.ErrInvalidDate) || errors.Is(err, stock.ErrAlreadyOrdered) ||
		errors.Is(err, customer.ErrNegativeCreditLimit)
}

// duplicateDetail turns the commonest collision into words a shopkeeper can act
// on. The unique index name is the only reliable signal of which one it was.
func duplicateDetail(err error) string {
	if strings.Contains(err.Error(), "idx_customer_phone_unique") {
		return "another customer in this business already has this phone number; " +
			"they were probably added on two phones — keep one and delete the other"
	}
	if payment.IsDuplicateMpesaRef(err) {
		return mpesaDuplicateDetail
	}
	return "this record already exists"
}

const mpesaDuplicateDetail = "this M-Pesa code is already recorded on another payment; " +
	"it was probably entered on two phones — the money has been counted once"

// loadByIDs reads the rows a batch touches for one table, in one query.
func loadByIDs[T any](ctx context.Context, db *gorm.DB, businessID uuid.UUID, ids []uuid.UUID) (map[uuid.UUID]T, error) {
	found := make(map[uuid.UUID]T, len(ids))
	if len(ids) == 0 {
		return found, nil
	}
	var rows []T
	if err := db.WithContext(ctx).
		Where("business_id = ? AND id IN ?", businessID, ids).
		Find(&rows).Error; err != nil {
		return nil, fmt.Errorf("loading %T: %w", rows, err)
	}
	for _, r := range rows {
		found[idOf(any(r))] = r
	}
	return found, nil
}

func idOf(row any) uuid.UUID {
	switch r := row.(type) {
	case domain.Customer:
		return r.ID
	case domain.Transaction:
		return r.ID
	case domain.Sale:
		return r.ID
	case domain.StockRequest:
		return r.ID
	case domain.Supplier:
		return r.ID
	case domain.SupplierTransaction:
		return r.ID
	default:
		panic(fmt.Sprintf("syncengine: loadByIDs does not know how to key %T", row))
	}
}

// saleDifference names the first field a device tried to change on a recorded
// sale, or "". Sales are immutable, like ledger entries.
func saleDifference(in SyncSale, prior domain.Sale) string {
	switch {
	case in.ProductName != prior.ProductName:
		return "product_name"
	case in.Quantity != prior.Quantity:
		return "quantity"
	case in.Amount != prior.Amount:
		return "amount"
	case in.PaymentMethod != prior.PaymentMethod:
		return "payment_method"
	case !sameOptionalUUID(in.CustomerID, prior.CustomerID):
		return "customer_id"
	case !sameDay(in.SaleDate, prior.SaleDate):
		return "sale_date"
	case !sameReference(in.PaymentMethod, in.Reference, prior.Reference):
		return "reference"
	case !sameOptionalDay(in.DueDate, prior.DueDate):
		return "due_date"
	default:
		return ""
	}
}

func sameOptionalUUID(a, b *uuid.UUID) bool {
	switch {
	case a == nil && b == nil:
		return true
	case a == nil || b == nil:
		return false
	default:
		return *a == *b
	}
}

func trimSpace(s string) string { return strings.TrimSpace(s) }
