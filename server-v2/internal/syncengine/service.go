package syncengine

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/customer"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/ledger"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/phone"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/sales"
	"salio/server-v2/internal/stock"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// Pull returns a page of changes. Supplier records are included only for a user
// who may read them — staff phones never receive what the shop owes suppliers.
func (s *Service) Pull(ctx context.Context, cursor int64, limit int) (*PullView, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, errors.New("sync pull without an authenticated user")
	}
	includeSuppliers, err := s.repo.CanReadSuppliers(ctx, sub.UserID)
	if err != nil {
		return nil, fmt.Errorf("checking supplier access: %w", err)
	}
	return s.repo.Pull(ctx, cursor, limit, includeSuppliers)
}

// Push applies a batch of offline changes and reports precisely what it did.
//
// # One bad record never costs the batch
//
// A phone that has been offline for a week is pushing a week of a shop's work,
// and one bad record in it — an entry for a deleted customer, two phones adding
// the same customer by phone number — must not lose the other ninety-nine.
//
// That needs more than checking records up front. PostgreSQL refuses every
// statement in a transaction after one has failed, so a single unique-index
// violation used to abort the whole push and the phone retried the same doomed
// batch forever. Each record is therefore written inside its own savepoint: a
// constraint violation rolls back that one record and becomes a conflict, and
// the push carries on. Any other database error still aborts — that is a
// problem with the database, not with the record.
//
// # The same rules as everywhere else
//
// The app writes almost everything through here rather than through the REST
// routes, so the rules have to be the same rules, run by the same code: owner-
// only actions checked against the same permissions the routes use, a customer
// deleted only at a zero balance, a description on every new entry. Each comes
// from the module that owns it (customer, ledger, sales, stock), not from a
// second copy written here.
func (s *Service) Push(ctx context.Context, in PushInput) (*PushView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, errors.New("sync push without an authenticated user")
	}

	body := in.Body
	now := time.Now().UTC()

	view, err := s.repo.Push(ctx, body.OperationID, func(tx *gorm.DB) (*PushView, error) {
		p := &push{
			ctx: ctx, tx: tx, businessID: businessID, userID: sub.UserID, now: now,
			view: &PushView{
				OperationID: body.OperationID,
				Conflicts:   []SyncConflict{},
				ServerTime:  now,
			},
			evaluator: authz.NewEvaluator(tx),
			granted:   map[string]bool{},
		}
		if err := p.loadMembers(); err != nil {
			return nil, err
		}

		// The order matters, and each step depends on the one before.
		steps := []func() error{
			func() error { return p.applyCustomers(body.Customers) },
			func() error { return p.applySuppliers(body.Suppliers) },
			func() error { return p.applySales(body.Sales) },
			func() error { return p.applyTransactions(body.Transactions) },
			func() error { return p.applySupplierTransactions(body.SupplierTransactions) },
			func() error { return p.applyStockRequests(body.StockRequests) },
			// Last, so a batch that settles a balance and deletes the customer
			// or supplier in the same push sees the settled balance.
			p.applyCustomerDeletions,
			p.applySupplierDeletions,
		}
		for _, step := range steps {
			if err := step(); err != nil {
				return nil, err
			}
		}
		return p.view, nil
	})
	if err != nil {
		return nil, err
	}

	// After the commit, and on a replay too: the copies are what the server
	// holds now (B2).
	includeSuppliers, err := s.repo.CanReadSuppliers(ctx, sub.UserID)
	if err != nil {
		return nil, fmt.Errorf("checking supplier access: %w", err)
	}
	if view.Current, err = s.repo.CurrentCopies(ctx, view.Conflicts, includeSuppliers); err != nil {
		return nil, err
	}
	return view, nil
}

// push carries one push through its steps.
type push struct {
	ctx        context.Context
	tx         *gorm.DB
	businessID uuid.UUID
	userID     uuid.UUID
	now        time.Time
	view       *PushView

	// members are the business's users. A record's user_id is kept only when it
	// names one of them; otherwise it is attributed to whoever is pushing.
	// Accepting any id that happened to satisfy the foreign key would let a
	// record be attributed to somebody in another shop.
	members map[uuid.UUID]bool

	evaluator *authz.Evaluator
	granted   map[string]bool
	checked   []string

	pendingDeletions         []uuid.UUID
	pendingSupplierDeletions []uuid.UUID
}

func (p *push) loadMembers() error {
	var ids []uuid.UUID
	if err := p.tx.WithContext(p.ctx).Model(&domain.User{}).
		Where("business_id = ?", p.businessID).Pluck("id", &ids).Error; err != nil {
		return fmt.Errorf("loading the business's users: %w", err)
	}
	p.members = make(map[uuid.UUID]bool, len(ids))
	for _, id := range ids {
		p.members[id] = true
	}
	return nil
}

// can reports whether the pushing user holds a permission — the same
// permissions the REST routes check, read from the same tables. Cached for the
// push, since a batch asks the same question many times.
func (p *push) can(permission string) (bool, error) {
	if slices.Contains(p.checked, permission) {
		return p.granted[permission], nil
	}
	ok, err := p.evaluator.UserHasPermission(p.ctx, p.userID, permission)
	if err != nil {
		return false, fmt.Errorf("checking %s: %w", permission, err)
	}
	p.checked = append(p.checked, permission)
	p.granted[permission] = ok
	return ok, nil
}

// attribute returns who a record is credited to.
func (p *push) attribute(claimed uuid.UUID) uuid.UUID {
	if p.members[claimed] {
		return claimed
	}
	return p.userID
}

func (p *push) conflict(table string, id uuid.UUID, field, reason, detail string) {
	p.view.Conflicts = append(p.view.Conflicts, SyncConflict{
		Table: table, ID: id, Field: field, Reason: reason, Detail: detail,
	})
}

func (p *push) forbidden(table string, id uuid.UUID, action string) {
	p.conflict(table, id, "", ReasonForbidden, "only an owner can "+action)
}

// try runs one record's writes in a savepoint.
//
// Returns handled=true when the record failed for a reason that belongs in the
// conflict report — a rule it broke, or a constraint it violated — having
// recorded that conflict. Any other error is returned for the caller to abort
// the push with.
func (p *push) try(table string, id uuid.UUID, fn func(tx *gorm.DB) error) (handled bool, err error) {
	err = p.tx.WithContext(p.ctx).Transaction(fn) // nested: a SAVEPOINT
	if err == nil {
		return false, nil
	}
	if reason, detail, ok := classify(err); ok {
		p.conflict(table, id, "", reason, detail)
		return true, nil
	}
	return false, err
}

// --- customers ---

func (p *push) applyCustomers(incoming []SyncCustomer) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, c := range incoming {
		ids = append(ids, c.ID)
	}
	existing, err := LoadCustomers(p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}

	for _, c := range incoming {
		prior, known := existing[c.ID]

		// One stored form for every number (B15), checked only when this
		// push sets the phone: an edit to the notes must not be refused over
		// a number stored in an older form.
		if c.Phone != nil && (!known || setsField(c, "phone")) {
			number, err := phone.Optional(c.Phone)
			if err != nil {
				p.conflict("customers", c.ID, "phone", ReasonInvalid, err.Error())
				if !known {
					continue
				}
				number = prior.Phone // the other fields still apply
			}
			c.Phone = number
		}

		if !known {
			if ok, err := p.can(rbac.PermCustomersCreate); err != nil {
				return err
			} else if !ok {
				p.forbidden("customers", c.ID, "add customers")
				continue
			}
			if reason, field, detail := validateCustomer(c); reason != "" {
				p.conflict("customers", c.ID, field, reason, detail)
				continue
			}

			// Created live; a delete pushed with it goes through the same
			// deletion step as any other, with its permission and balance check.
			live := c
			live.IsDeleted = false
			live.CreatedBy = p.attribute(c.CreatedBy)
			if live.CreditLimit != nil {
				// The customer is still added; only the limit waits for an
				// owner. Losing the whole customer over one field would lose
				// the debts recorded against them later in this batch.
				if ok, err := p.can(rbac.PermCustomersCreditLimit); err != nil {
					return err
				} else if !ok {
					live.CreditLimit = nil
					p.conflict("customers", c.ID, "credit_limit", ReasonForbidden, "only an owner can set a credit limit")
				}
			}
			at := domain.ClampToServer(c.UpdatedAt, p.now)
			if handled, err := p.try("customers", c.ID, func(tx *gorm.DB) error {
				return InsertCustomer(p.ctx, tx, p.businessID, live, at)
			}); err != nil {
				return err
			} else if handled {
				continue
			}
			p.view.AppliedCustomers++
			if c.IsDeleted {
				p.pendingDeletions = append(p.pendingDeletions, c.ID)
			}
			continue
		}

		// Bounded to the server's clock before it is compared to anything. A
		// device whose clock is days fast would otherwise win every conflict it
		// ever entered, for as long as the clock stayed wrong.
		at := domain.ClampToServer(c.UpdatedAt, p.now)
		merged := mergeCustomer(c, &prior, at)
		p.view.Conflicts = append(p.view.Conflicts, merged.Conflicts...)

		// A deletion is not a field edit: it needs its own permission and a
		// zero balance, so it is pulled out here and applied at the end.
		if _, deleting := merged.Columns["is_deleted"]; deleting {
			delete(merged.Columns, "is_deleted")
			merged.Fields = slices.DeleteFunc(merged.Fields, func(f string) bool { return f == "is_deleted" })
			p.pendingDeletions = append(p.pendingDeletions, c.ID)
		}
		if err := p.gateCreditLimit(c.ID, &merged, prior.CreditLimit); err != nil {
			return err
		}
		if len(merged.Columns) == 0 {
			continue
		}

		if ok, err := p.can(rbac.PermCustomersUpdate); err != nil {
			return err
		} else if !ok {
			p.forbidden("customers", c.ID, "edit customers")
			continue
		}
		if handled, err := p.try("customers", c.ID, func(tx *gorm.DB) error {
			return UpdateCustomer(p.ctx, tx, p.businessID, c.ID, merged.Columns, merged.Fields, at)
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedCustomers++
	}
	return nil
}

// gateCreditLimit keeps a credit limit change only for someone allowed to make
// it. Re-sending the limit already stored is not a change, so a staff phone
// pushing back the customer it pulled is never told off for it.
func (p *push) gateCreditLimit(id uuid.UUID, merged *customerMerge, current *money.Amount) error {
	value, present := merged.Columns["credit_limit"]
	if !present {
		return nil
	}
	drop := func() {
		delete(merged.Columns, "credit_limit")
		merged.Fields = slices.DeleteFunc(merged.Fields, func(f string) bool { return f == "credit_limit" })
	}
	incoming, _ := value.(*money.Amount)
	if sameOptionalAmount(incoming, current) {
		drop()
		return nil
	}
	if err := customer.ValidateCreditLimit(incoming); err != nil {
		drop()
		p.conflict("customers", id, "credit_limit", ReasonInvalid, err.Error())
		return nil
	}
	ok, err := p.can(rbac.PermCustomersCreditLimit)
	if err != nil {
		return err
	}
	if !ok {
		drop()
		p.conflict("customers", id, "credit_limit", ReasonForbidden, "only an owner can set a credit limit")
	}
	return nil
}

func sameOptionalAmount(a, b *money.Amount) bool {
	switch {
	case a == nil && b == nil:
		return true
	case a == nil || b == nil:
		return false
	default:
		return *a == *b
	}
}

func (p *push) applyCustomerDeletions() error {
	for _, id := range p.pendingDeletions {
		if ok, err := p.can(rbac.PermCustomersDelete); err != nil {
			return err
		} else if !ok {
			p.forbidden("customers", id, "delete customers")
			continue
		}
		if handled, err := p.try("customers", id, func(tx *gorm.DB) error {
			err := customer.DeleteIfSettled(p.ctx, tx, id)
			if errors.Is(err, customer.ErrNotFound) {
				return nil // already deleted: nothing left to do
			}
			return err
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedCustomers++
	}
	return nil
}

// --- sales ---

func (p *push) applySales(incoming []SyncSale) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, s := range incoming {
		ids = append(ids, s.ID)
	}
	existing, err := loadByIDs[domain.Sale](p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}

	for _, in := range incoming {
		if prior, known := existing[in.ID]; known {
			if err := p.mergeSale(in, prior); err != nil {
				return err
			}
			continue
		}

		if ok, err := p.can(rbac.PermSalesCreate); err != nil {
			return err
		} else if !ok {
			p.forbidden("sales", in.ID, "record sales")
			continue
		}

		sale := &domain.Sale{
			ID: in.ID, BusinessID: p.businessID, CustomerID: in.CustomerID,
			UserID: p.attribute(in.UserID), ProductName: in.ProductName,
			Quantity: in.Quantity, Amount: in.Amount, PaymentMethod: in.PaymentMethod,
			Notes: in.Notes, SaleDate: in.SaleDate, Reference: in.Reference, DueDate: in.DueDate,
		}
		if handled, err := p.try("sales", in.ID, func(tx *gorm.DB) error {
			return sales.Record(p.ctx, tx, sale)
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedSales++

		// Recorded and voided while offline: the void goes through the same
		// permission check as any other.
		if in.IsDeleted {
			if err := p.voidSale(in.ID); err != nil {
				return err
			}
		}
	}
	return nil
}

func (p *push) mergeSale(in SyncSale, prior domain.Sale) error {
	if field := saleDifference(in, prior); field != "" {
		p.conflict("sales", in.ID, field, ReasonImmutable,
			"a recorded sale cannot be edited; void it and record it again")
	}
	switch {
	case in.IsDeleted && !prior.IsDeleted:
		return p.voidSale(in.ID)
	case !in.IsDeleted && prior.IsDeleted:
		p.conflict("sales", in.ID, "", ReasonAlreadyVoided, "this sale was voided on another device")
	}
	return nil
}

func (p *push) voidSale(id uuid.UUID) error {
	if ok, err := p.can(rbac.PermSalesVoid); err != nil {
		return err
	} else if !ok {
		p.forbidden("sales", id, "void a sale")
		return nil
	}
	if handled, err := p.try("sales", id, func(tx *gorm.DB) error {
		return sales.Void(p.ctx, tx, id)
	}); err != nil || handled {
		return err
	}
	p.view.AppliedSales++
	return nil
}

// --- ledger entries ---

func (p *push) applyTransactions(incoming []SyncTransaction) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	customerIDs := make([]uuid.UUID, 0, len(incoming))
	for _, t := range incoming {
		ids = append(ids, t.ID)
		customerIDs = append(customerIDs, t.CustomerID)
	}
	existing, err := LoadTransactions(p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}
	// Read after customers and sales have been applied, so a customer created
	// earlier in this same batch counts as present.
	customers, err := CustomerIDsIn(p.ctx, p.tx, p.businessID, customerIDs)
	if err != nil {
		return err
	}

	for _, t := range incoming {
		// A credit sale's debt belongs to the server, which created it from the
		// sale in applySales. The phone's copy is ignored, so a sale can never
		// put two debts on an account or a debt that disagrees with the sale.
		if t.SaleID != nil {
			continue
		}

		if prior, known := existing[t.ID]; known {
			if err := p.mergeTransaction(t, prior); err != nil {
				return err
			}
			continue
		}

		if ok, err := p.can(rbac.PermTransactionsCreate); err != nil {
			return err
		} else if !ok {
			p.forbidden("transactions", t.ID, "record debts and payments")
			continue
		}

		entry := domain.Transaction{
			ID: t.ID, BusinessID: p.businessID, CustomerID: t.CustomerID,
			UserID: p.attribute(t.UserID), Type: t.Type, Amount: t.Amount,
			Description: trimmed(t.Description), TransactionDate: t.TransactionDate,
			CreatedAt: t.CreatedAt, PaymentMethod: t.PaymentMethod, Reference: t.Reference,
			DueDate: t.DueDate,
		}
		if err := ledger.ValidateEntry(&entry); err != nil {
			p.conflict("transactions", t.ID, "", ReasonInvalid, err.Error())
			continue
		}
		// Refused rather than left to fail on the foreign key, so the report
		// can say which customer was missing.
		if !customers[t.CustomerID] {
			p.conflict("transactions", t.ID, "customer_id", ReasonUnknownCustomer,
				fmt.Sprintf("customer %s does not belong to this business", t.CustomerID))
			continue
		}

		if handled, err := p.try("transactions", t.ID, func(tx *gorm.DB) error {
			return tx.WithContext(p.ctx).Create(&entry).Error
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedTransactions++

		if t.IsDeleted {
			if err := p.voidTransaction(entry); err != nil {
				return err
			}
		}
	}
	return nil
}

func (p *push) mergeTransaction(t SyncTransaction, prior domain.Transaction) error {
	applyVoid, conflicts := mergeTransaction(t, &prior)
	p.view.Conflicts = append(p.view.Conflicts, conflicts...)
	if !applyVoid {
		return nil
	}
	return p.voidTransaction(prior)
}

func (p *push) voidTransaction(t domain.Transaction) error {
	if err := ledger.CheckVoidable(&t); err != nil {
		p.conflict("transactions", t.ID, "", ReasonInvalid, err.Error())
		return nil
	}
	if ok, err := p.can(rbac.PermTransactionsVoid); err != nil {
		return err
	} else if !ok {
		p.forbidden("transactions", t.ID, "void a debt or payment")
		return nil
	}
	if handled, err := p.try("transactions", t.ID, func(tx *gorm.DB) error {
		return VoidTransaction(p.ctx, tx, p.businessID, t.ID)
	}); err != nil || handled {
		return err
	}
	p.view.AppliedTransactions++
	return nil
}

// --- stock requests ---

func (p *push) applyStockRequests(incoming []SyncStockRequest) error {
	if len(incoming) == 0 {
		return nil
	}
	if ok, err := p.can(rbac.PermStockRequest); err != nil {
		return err
	} else if !ok {
		for _, r := range incoming {
			p.forbidden("stock_requests", r.ID, "note stock to order")
		}
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, r := range incoming {
		ids = append(ids, r.ID)
	}
	existing, err := loadByIDs[domain.StockRequest](p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}

	for _, in := range incoming {
		at := domain.ClampToServer(in.UpdatedAt, p.now)

		prior, known := existing[in.ID]
		if !known {
			req := &domain.StockRequest{
				ID: in.ID, BusinessID: p.businessID, UserID: p.attribute(in.UserID),
				ProductName: in.ProductName, NeededOn: in.NeededOn, Notes: trimmed(in.Notes),
				IsDeleted: in.IsDeleted,
				// PurchaseOrderID is never taken from a device: only placing an
				// order on the server puts a request on one.
			}
			if err := stock.ValidateRequest(req); err != nil {
				p.conflict("stock_requests", in.ID, "", ReasonInvalid, err.Error())
				continue
			}
			if handled, err := p.try("stock_requests", in.ID, func(tx *gorm.DB) error {
				return tx.WithContext(p.ctx).Create(req).Error
			}); err != nil {
				return err
			} else if handled {
				continue
			}
			p.view.AppliedStockRequests++
			continue
		}

		if !stockRequestChanged(in, prior) {
			continue
		}
		if err := stock.CheckEditable(&prior); err != nil {
			p.conflict("stock_requests", in.ID, "", ReasonAlreadyOrdered, err.Error())
			continue
		}
		// One person edits a stock note at a time in practice, so the whole
		// record follows the latest write rather than merging field by field.
		if !at.After(prior.UpdatedAt) {
			p.conflict("stock_requests", in.ID, "", ReasonStaleWrite,
				"a newer edit to this stock request is already recorded")
			continue
		}

		updated := prior
		updated.ProductName, updated.NeededOn, updated.Notes = in.ProductName, in.NeededOn, trimmed(in.Notes)
		updated.IsDeleted = in.IsDeleted || prior.IsDeleted // deletion is one-way
		if err := stock.ValidateRequest(&updated); err != nil {
			p.conflict("stock_requests", in.ID, "", ReasonInvalid, err.Error())
			continue
		}
		if handled, err := p.try("stock_requests", in.ID, func(tx *gorm.DB) error {
			return tx.WithContext(p.ctx).Model(&domain.StockRequest{}).
				Where("id = ? AND business_id = ?", in.ID, p.businessID).
				Updates(map[string]any{
					"product_name": updated.ProductName, "needed_on": updated.NeededOn,
					"notes": updated.Notes, "is_deleted": updated.IsDeleted,
				}).Error
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedStockRequests++
	}
	return nil
}

func stockRequestChanged(in SyncStockRequest, prior domain.StockRequest) bool {
	return in.ProductName != prior.ProductName ||
		!sameDay(in.NeededOn, prior.NeededOn) ||
		!sameOptionalString(trimmed(in.Notes), prior.Notes) ||
		in.IsDeleted != prior.IsDeleted
}

// --- shared ---

// setsField reports whether a customer push changes a field: named in
// changed_fields, or a whole-record push, which changes them all.
func setsField(c SyncCustomer, field string) bool {
	return len(c.ChangedFields) == 0 || slices.Contains(c.ChangedFields, field)
}

// validateCustomer checks what the schema deliberately does not.
func validateCustomer(c SyncCustomer) (reason, field, detail string) {
	switch {
	case c.Name == "":
		return ReasonInvalid, "name", "a customer must have a name"
	case c.CreatedBy == uuid.Nil:
		return ReasonInvalid, "created_by", "created_by must name the user who added this customer"
	case customer.ValidateCreditLimit(c.CreditLimit) != nil:
		return ReasonInvalid, "credit_limit", customer.ErrNegativeCreditLimit.Error()
	default:
		return "", "", ""
	}
}

func trimmed(s *string) *string {
	if s == nil {
		return nil
	}
	t := trimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
