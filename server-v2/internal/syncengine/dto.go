// Package syncengine is the offline-first synchronisation contract between a
// phone's SQLite database and the server.
//
// Named syncengine rather than sync so that files here — the concurrency tests
// especially — can use the standard library's sync package without an alias.
//
// # What changed from v1, and why
//
// v1 pulled rows WHERE updated_at > last_sync and handed the client the server's
// clock to store as the next watermark. In PostgreSQL NOW() is the transaction
// *start* time while rows become visible at *commit*, so a device pulling
// between those two instants saw nothing and still advanced its watermark past
// the pending row. That row then sat permanently below the watermark and was
// never returned again — which is why signing out appeared to fix it, logout
// being the only thing that cleared the value. Plan §5 has the full diagnosis.
//
// Five things replace it, and each closes a distinct failure:
//
//	server-issued cursor    a client advances only to what it actually received
//	paginated pull          a shop with 10k entries no longer pulls them at once
//	idempotent push         a retried timeout cannot record a debt twice
//	per-field merge         two people editing one customer no longer clobber
//	explicit conflicts      a discarded write is reported, not answered "200 OK"
package syncengine

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/quantity"
)

// SyncCustomer is a customer on the wire, in both directions.
// Only the identifier is required by the schema. Everything else a record needs
// is checked while applying it and reported as a conflict, because schema
// validation rejects the whole request: one field missing from one record out of
// two hundred would fail the batch with a 422 and the device would retry the
// same doomed payload forever. That is precisely the v1 behaviour this phase
// exists to remove, and it would be reintroduced by a struct tag.
type SyncCustomer struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID        uuid.UUID `json:"id" required:"true"`
	Name      string    `json:"name" required:"false"`
	Phone     *string   `json:"phone,omitempty"`
	Notes     *string   `json:"notes,omitempty"`
	CreatedBy uuid.UUID `json:"created_by" required:"false"`
	CreatedAt time.Time `json:"created_at" required:"false"`

	// UpdatedAt is when the device made this edit, and is what orders it against
	// competing edits. Bounded by the server on arrival, so a device with a fast
	// clock cannot claim priority indefinitely — see domain.FieldVersions.
	UpdatedAt time.Time `json:"updated_at" required:"false"`
	IsDeleted bool      `json:"is_deleted" required:"false" doc:"Omit for a live record."`

	// ChangedFields names what this device actually edited, and is what makes a
	// merge per-field rather than per-record. Sending the whole row without it
	// means "all of this is mine", which will overwrite another device's edit to
	// a field this one never touched.
	//
	// Absent or empty is treated as the whole record, which is exactly v1's
	// behaviour — so a client that has not been updated yet still works, and is
	// no worse off than it was.
	ChangedFields []string `json:"changed_fields,omitempty"`

	// CreditLimit is how much the customer may owe; null is no limit. Only an
	// owner may change it, and only a push that names "credit_limit" in
	// changed_fields does: a whole-record push leaves it alone, so a client
	// that does not know the field cannot wipe the owner's limits.
	CreditLimit *money.Amount `json:"credit_limit,omitempty" required:"false" doc:"Decimal string; null is no limit"`
}

// SyncTransaction is a ledger entry on the wire.
//
// Everything except IsDeleted is immutable once the server has the row: a
// mistake is corrected with an offsetting entry or a void, never by editing
// history. A push that alters an existing entry is reported as a conflict rather
// than silently dropped, which is what v1 did — its upsert merged only
// is_deleted and updated_at, so an edited amount was accepted with a 200 and
// discarded.
type SyncTransaction struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID              uuid.UUID              `json:"id" required:"true"`
	CustomerID      uuid.UUID              `json:"customer_id" required:"false"`
	UserID          uuid.UUID              `json:"user_id" required:"false"`
	Type            domain.TransactionType `json:"type" required:"false" doc:"debt or payment"`
	Amount          money.Amount           `json:"amount" required:"false" doc:"Decimal string, e.g. \"1500.50\""`
	Description     *string                `json:"description,omitempty"`
	TransactionDate time.Time              `json:"transaction_date" required:"false"`
	CreatedAt       time.Time              `json:"created_at" required:"false"`
	UpdatedAt       time.Time              `json:"updated_at" required:"false"`
	IsDeleted       bool                   `json:"is_deleted" required:"false" doc:"Omit for a live entry."`

	// SaleID marks the debt a credit sale created. Such debts belong to the
	// server: it creates each one from its sale, with id domain.SaleDebtID, and
	// ignores any a device pushes. A phone may create the same debt locally for
	// an immediate balance, but never needs to send it.
	SaleID *uuid.UUID `json:"sale_id,omitempty" required:"false"`

	// Payments: how the money came in. Required on a new payment; absent on a
	// debt. An M-Pesa code may be recorded on only one live payment.
	PaymentMethod *domain.PaymentMethod `json:"payment_method,omitempty" required:"false" doc:"Payments: cash, mpesa or bank"`
	Reference     *string               `json:"reference,omitempty" required:"false" doc:"M-Pesa code or bank reference"`

	// Debts: when the customer agreed to pay by.
	DueDate *time.Time `json:"due_date,omitempty" required:"false"`
}

// SyncSale is a sale on the wire.
//
// Immutable once the server has it, like a ledger entry: only is_deleted may
// change, and only for someone holding sales.void. Voiding a credit sale voids
// its debt too.
type SyncSale struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID            uuid.UUID            `json:"id" required:"true"`
	CustomerID    *uuid.UUID           `json:"customer_id,omitempty" required:"false"`
	UserID        uuid.UUID            `json:"user_id" required:"false"`
	ProductName   string               `json:"product_name" required:"false"`
	Quantity      quantity.Quantity    `json:"quantity" required:"false"`
	Amount        money.Amount         `json:"amount" required:"false" doc:"Decimal string, e.g. \"3500.00\""`
	PaymentMethod domain.PaymentMethod `json:"payment_method" required:"false" doc:"cash, mpesa, bank or credit"`
	Reference     *string              `json:"reference,omitempty" required:"false" doc:"M-Pesa code or bank reference"`
	DueDate       *time.Time           `json:"due_date,omitempty" required:"false" doc:"Credit sales: when it is to be paid by"`
	Notes         *string              `json:"notes,omitempty" required:"false"`
	SaleDate      time.Time            `json:"sale_date" required:"false"`
	CreatedAt     time.Time            `json:"created_at" required:"false"`
	UpdatedAt     time.Time            `json:"updated_at" required:"false"`
	IsDeleted     bool                 `json:"is_deleted" required:"false"`
}

// SyncStockRequest is a stock request on the wire.
//
// Editable while it is pending. Once on a purchase order it is frozen, and
// PurchaseOrderID — which says so — is set only by the server and ignored when
// a device sends it.
type SyncStockRequest struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID              uuid.UUID  `json:"id" required:"true"`
	UserID          uuid.UUID  `json:"user_id" required:"false"`
	ProductName     string     `json:"product_name" required:"false"`
	NeededOn        time.Time  `json:"needed_on" required:"false"`
	Notes           *string    `json:"notes,omitempty" required:"false"`
	PurchaseOrderID *uuid.UUID `json:"purchase_order_id,omitempty" required:"false" doc:"Set by the server; ignored on push"`
	CreatedAt       time.Time  `json:"created_at" required:"false"`
	UpdatedAt       time.Time  `json:"updated_at" required:"false"`
	IsDeleted       bool       `json:"is_deleted" required:"false"`
}

// SyncSupplier is a supplier on the wire. Edited rarely and by the owner, so
// the whole record follows the latest write rather than merging per field.
type SyncSupplier struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID        uuid.UUID `json:"id" required:"true"`
	Name      string    `json:"name" required:"false"`
	Phone     *string   `json:"phone,omitempty" required:"false"`
	Notes     *string   `json:"notes,omitempty" required:"false"`
	CreatedBy uuid.UUID `json:"created_by" required:"false"`
	CreatedAt time.Time `json:"created_at" required:"false"`
	UpdatedAt time.Time `json:"updated_at" required:"false"`
	IsDeleted bool      `json:"is_deleted" required:"false"`
}

// SyncSupplierTransaction is a supplier bill or payment on the wire. Immutable
// once recorded, like a ledger entry: only a void is accepted afterwards.
type SyncSupplierTransaction struct {
	_ struct{} `additionalProperties:"true"` // B14: see PushInput

	ID              uuid.UUID                `json:"id" required:"true"`
	SupplierID      uuid.UUID                `json:"supplier_id" required:"false"`
	UserID          uuid.UUID                `json:"user_id" required:"false"`
	Type            domain.SupplierEntryType `json:"type" required:"false" doc:"bill or payment"`
	Amount          money.Amount             `json:"amount" required:"false"`
	Description     string                   `json:"description" required:"false"`
	TransactionDate time.Time                `json:"transaction_date" required:"false"`
	DueDate         *time.Time               `json:"due_date,omitempty" required:"false"`
	PaymentMethod   *domain.PaymentMethod    `json:"payment_method,omitempty" required:"false"`
	Reference       *string                  `json:"reference,omitempty" required:"false"`
	PurchaseOrderID *uuid.UUID               `json:"purchase_order_id,omitempty" required:"false"`
	CreatedAt       time.Time                `json:"created_at" required:"false"`
	UpdatedAt       time.Time                `json:"updated_at" required:"false"`
	IsDeleted       bool                     `json:"is_deleted" required:"false"`
}

// Conflict reasons. Strings rather than numbers so a log line or a bug report
// from the field is readable without a lookup table.
const (
	// ReasonStaleWrite: a newer write to that same field already won.
	ReasonStaleWrite = "stale_write"

	// ReasonImmutable: an attempt to change a recorded ledger entry.
	ReasonImmutable = "immutable"

	// ReasonAlreadyVoided: pushing a live version of an entry the server has
	// already voided. Not an error the person needs to fix — the next pull tells
	// the device — but reported so the client can reconcile instead of guessing.
	ReasonAlreadyVoided = "already_voided"

	// ReasonUnknownCustomer: an entry pointing at a customer this business does
	// not have. Usually a device that never successfully pushed the customer.
	ReasonUnknownCustomer = "unknown_customer"

	// ReasonInvalid: the record could not be accepted on its own terms — a
	// non-positive amount, an unrecognised type, a missing description.
	ReasonInvalid = "invalid"

	// ReasonForbidden: the change needs a permission this user does not hold —
	// staff voiding an entry or deleting a customer, which only an owner may do.
	ReasonForbidden = "forbidden"

	// ReasonHasBalance: deleting a customer who owes money, or who holds an
	// advance. Settle the balance to zero first.
	ReasonHasBalance = "has_balance"

	// ReasonDuplicate: the record collides with one that already exists — most
	// often a customer added on two phones with the same phone number.
	ReasonDuplicate = "duplicate"

	// ReasonAlreadyOrdered: changing a stock request that is already on a
	// purchase order.
	ReasonAlreadyOrdered = "already_ordered"

	// ReasonUnknownSale: voiding a sale this business does not have.
	ReasonUnknownSale = "unknown_sale"

	// ReasonUnknownSupplier: a bill or payment for a supplier this business
	// does not have.
	ReasonUnknownSupplier = "unknown_supplier"
)

// SyncConflict is one record, or one field, the server did not accept.
//
// v1 answered every push with {"message":"Sync successful"} whatever happened,
// so a discarded edit was indistinguishable from an applied one. Anything not
// applied appears here.
type SyncConflict struct {
	Table  string    `json:"table" doc:"customers, transactions, sales, stock_requests, suppliers or supplier_transactions"`
	ID     uuid.UUID `json:"id"`
	Field  string    `json:"field,omitempty" doc:"set when only one field was rejected"`
	Reason string    `json:"reason"`
	Detail string    `json:"detail,omitempty"`
}

// PullView is one page of changes.
type PullView struct {
	Customers     []SyncCustomer     `json:"customers"`
	Transactions  []SyncTransaction  `json:"transactions"`
	Sales         []SyncSale         `json:"sales"`
	StockRequests []SyncStockRequest `json:"stock_requests"`

	// Suppliers and what the shop owes them reach only devices whose user holds
	// suppliers.read — by default, owners. For anyone else both are always
	// empty. A user whose role changes should resync from zero.
	Suppliers            []SyncSupplier            `json:"suppliers"`
	SupplierTransactions []SyncSupplierTransaction `json:"supplier_transactions"`

	// NextCursor is what to send on the next pull. It advances only as far as
	// the highest change actually included above — never to "now" — which is the
	// property the timestamp watermark lacked.
	NextCursor int64 `json:"next_cursor"`

	// HasMore means another page is waiting. Pull again immediately with
	// NextCursor rather than waiting for the next sync.
	HasMore bool `json:"has_more"`

	// ResyncRequired means the cursor is older than the server keeps tombstones
	// for, so the deletions this device missed can no longer be described to it.
	// The client must discard its local copy and pull again from zero; carrying
	// on would resurrect rows that were deleted while it was away.
	ResyncRequired bool `json:"resync_required"`

	ServerTime time.Time `json:"server_time"`
}

// ServerCopies are records as the server holds them, in the shape a pull
// sends. Lists are never null.
type ServerCopies struct {
	Customers            []SyncCustomer            `json:"customers"`
	Transactions         []SyncTransaction         `json:"transactions"`
	Sales                []SyncSale                `json:"sales"`
	StockRequests        []SyncStockRequest        `json:"stock_requests"`
	Suppliers            []SyncSupplier            `json:"suppliers"`
	SupplierTransactions []SyncSupplierTransaction `json:"supplier_transactions"`
}

// PushView reports what a push did.
type PushView struct {
	OperationID uuid.UUID `json:"operation_id"`

	AppliedCustomers     int `json:"applied_customers"`
	AppliedTransactions  int `json:"applied_transactions"`
	AppliedSales         int `json:"applied_sales"`
	AppliedStockRequests int `json:"applied_stock_requests"`

	AppliedSuppliers            int `json:"applied_suppliers"`
	AppliedSupplierTransactions int `json:"applied_supplier_transactions"`

	// Conflicts is never null, always a list. A client checking length should
	// not have to handle both.
	Conflicts []SyncConflict `json:"conflicts"`

	// Current is the server's copy, as it stands now, of every record named in
	// Conflicts (B2). Without it a refused change stayed on the phone for good:
	// the server's row had not changed, so no pull would ever correct it. The
	// client stores these as if pulled.
	//
	// Read when the answer is sent, not stored with the outcome, so a replayed
	// answer never hands back a copy older than one the phone has since
	// pulled. A record the server does not have, such as a refused new
	// customer, is absent. Supplier records appear only for a user who may
	// read them, as on a pull.
	Current ServerCopies `json:"current"`

	// Replayed means this operation_id had already been applied and the stored
	// result was returned. The client's retry worked; it just did no new work.
	Replayed bool `json:"replayed"`

	ServerTime time.Time `json:"server_time"`
}

// --- Requests and responses ---

type PullInput struct {
	Cursor int64 `query:"cursor" default:"0" minimum:"0" doc:"Server-issued cursor from the previous pull. 0 for a first sync."`
	Limit  int   `query:"limit" default:"500" minimum:"1" maximum:"2000" doc:"Maximum records of each kind per page."`
}

type PullOutput struct {
	Body struct {
		Success bool     `json:"success"`
		Data    PullView `json:"data"`
	}
}

type PushInput struct {
	Body struct {
		// Fields this server does not know are ignored rather than refused
		// (B14), here and in every record. Huma refuses them by default, and a
		// refusal fails the whole batch: a newer app talking to an older server
		// (after a rollback, or a staging app on production) could then never
		// sync, and would retry the same batch forever. Ignoring is safe
		// because an older server stores nothing of a field it does not know,
		// which is exactly what it did before the field existed. REST routes
		// stay strict, where a refused field is a typo caught early.
		_ struct{} `additionalProperties:"true"`

		// OperationID names this attempt and must be reused across its retries.
		// Required: without it a retry cannot be told from a new batch, and the
		// only safe reading of an unnamed batch is that it is new.
		OperationID uuid.UUID `json:"operation_id" required:"true" doc:"Client-generated UUID, identical across retries of this batch."`

		Customers     []SyncCustomer     `json:"customers,omitempty"`
		Transactions  []SyncTransaction  `json:"transactions,omitempty"`
		Sales         []SyncSale         `json:"sales,omitempty"`
		StockRequests []SyncStockRequest `json:"stock_requests,omitempty"`

		Suppliers            []SyncSupplier            `json:"suppliers,omitempty"`
		SupplierTransactions []SyncSupplierTransaction `json:"supplier_transactions,omitempty"`
	}
}

type PushOutput struct {
	Body struct {
		Success bool     `json:"success"`
		Data    PushView `json:"data"`
	}
}
