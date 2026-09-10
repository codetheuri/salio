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
)

// SyncCustomer is a customer on the wire, in both directions.
// Only the identifier is required by the schema. Everything else a record needs
// is checked while applying it and reported as a conflict, because schema
// validation rejects the whole request: one field missing from one record out of
// two hundred would fail the batch with a 422 and the device would retry the
// same doomed payload forever. That is precisely the v1 behaviour this phase
// exists to remove, and it would be reintroduced by a struct tag.
type SyncCustomer struct {
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
	// non-positive amount, an unrecognised type.
	ReasonInvalid = "invalid"
)

// SyncConflict is one record, or one field, the server did not accept.
//
// v1 answered every push with {"message":"Sync successful"} whatever happened,
// so a discarded edit was indistinguishable from an applied one. Anything not
// applied appears here.
type SyncConflict struct {
	Table  string    `json:"table" doc:"customers or transactions"`
	ID     uuid.UUID `json:"id"`
	Field  string    `json:"field,omitempty" doc:"set when only one field was rejected"`
	Reason string    `json:"reason"`
	Detail string    `json:"detail,omitempty"`
}

// PullView is one page of changes.
type PullView struct {
	Customers    []SyncCustomer    `json:"customers"`
	Transactions []SyncTransaction `json:"transactions"`

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

// PushView reports what a push did.
type PushView struct {
	OperationID uuid.UUID `json:"operation_id"`

	AppliedCustomers    int `json:"applied_customers"`
	AppliedTransactions int `json:"applied_transactions"`

	// Conflicts is never null, always a list. A client checking length should
	// not have to handle both.
	Conflicts []SyncConflict `json:"conflicts"`

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
		// OperationID names this attempt and must be reused across its retries.
		// Required: without it a retry cannot be told from a new batch, and the
		// only safe reading of an unnamed batch is that it is new.
		OperationID uuid.UUID `json:"operation_id" required:"true" doc:"Client-generated UUID, identical across retries of this batch."`

		Customers    []SyncCustomer    `json:"customers,omitempty"`
		Transactions []SyncTransaction `json:"transactions,omitempty"`
	}
}

type PushOutput struct {
	Body struct {
		Success bool     `json:"success"`
		Data    PushView `json:"data"`
	}
}
