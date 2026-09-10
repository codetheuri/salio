package syncengine

import (
	"time"

	"salio/server-v2/internal/domain"
)

// customerFields are the fields a device may edit. Order is fixed so a merge
// produces the same conflicts in the same order every time, which matters
// because that list is stored and replayed for an idempotent retry.
var customerFields = []string{"name", "phone", "notes", "is_deleted"}

// customerMerge is the outcome of merging one incoming customer.
type customerMerge struct {
	// Columns to write. Empty means the push lost every field it contested and
	// there is nothing to do.
	Columns map[string]any

	// Fields whose versions to stamp — the same keys as Columns, named
	// separately because the stamp is written as one jsonb concatenation.
	Fields []string

	Conflicts []SyncConflict
}

// mergeCustomer decides, field by field, which side of a concurrent edit wins.
//
// The rule for each field is the same: the write with the later timestamp wins,
// where "later" is measured against when that *field* last accepted a write
// rather than when the record as a whole was last touched. That is the whole
// difference from v1. Two people editing one customer while offline — one fixes
// the phone number, the other adds a note — both keep their change, where
// before whoever pushed second overwrote the other silently.
//
// incomingAt has already been clamped to the server's clock by the caller.
func mergeCustomer(in SyncCustomer, existing *domain.Customer, incomingAt time.Time) customerMerge {
	out := customerMerge{Columns: map[string]any{}}

	changed := in.ChangedFields
	if len(changed) == 0 {
		// No declaration of what changed, so the only safe reading is that the
		// device believes it owns the whole record. This is what an app version
		// that predates per-field merge sends, and it degrades to exactly the
		// whole-record last-write-wins it used to get.
		changed = customerFields
	}

	for _, field := range changed {
		value, ok := incomingValue(in, field)
		if !ok {
			// A field name this server does not have. Ignored rather than
			// reported: a newer client sending a field an older server has not
			// heard of should not have its whole push start failing.
			continue
		}

		if field == "is_deleted" {
			// Deletion is one-way. A device that deleted a customer while
			// another device was still editing it must win, and a device that
			// has not yet heard about a deletion must not be able to bring the
			// row back by pushing its stale copy. Undeleting is not a feature of
			// the product, so nothing legitimate is being refused here.
			if in.IsDeleted && !existing.IsDeleted {
				out.Columns["is_deleted"] = true
				out.Fields = append(out.Fields, "is_deleted")
			}
			continue
		}

		if !incomingAt.After(existing.FieldVersions.VersionOf(field, existing.UpdatedAt)) {
			// Not an error, and not something the person needs to fix — but it
			// is a write that was discarded, and v1 answered exactly this case
			// with "Sync successful".
			out.Conflicts = append(out.Conflicts, SyncConflict{
				Table: "customers", ID: in.ID, Field: field, Reason: ReasonStaleWrite,
				Detail: "a newer edit to this field is already recorded",
			})
			continue
		}

		out.Columns[field] = value
		out.Fields = append(out.Fields, field)
	}

	return out
}

// incomingValue reads one field off the wire record by name.
func incomingValue(in SyncCustomer, field string) (any, bool) {
	switch field {
	case "name":
		return in.Name, true
	case "phone":
		return in.Phone, true
	case "notes":
		return in.Notes, true
	case "is_deleted":
		return in.IsDeleted, true
	default:
		return nil, false
	}
}

// mergeTransaction decides what to do with a ledger entry the server already has.
//
// Transactions are immutable — a mistake is corrected with an offsetting entry
// or a void, never by editing the row. So exactly one thing may change after the
// fact, and it is is_deleted going from false to true.
//
// Returns whether to apply the void, and any conflict to report.
func mergeTransaction(in SyncTransaction, existing *domain.Transaction) (applyVoid bool, conflicts []SyncConflict) {
	// Checked before the void, and reported even when a void is also being
	// applied: a device that changed an amount needs to hear that it was
	// refused, whether or not it also voided the entry.
	if changed := immutableDifference(in, existing); changed != "" {
		conflicts = append(conflicts, SyncConflict{
			Table: "transactions", ID: in.ID, Field: changed, Reason: ReasonImmutable,
			Detail: "a recorded entry cannot be edited; void it and record a correcting entry",
		})
	}

	switch {
	case in.IsDeleted && !existing.IsDeleted:
		return true, conflicts
	case !in.IsDeleted && existing.IsDeleted:
		conflicts = append(conflicts, SyncConflict{
			Table: "transactions", ID: in.ID, Reason: ReasonAlreadyVoided,
			Detail: "this entry was voided on another device",
		})
	}
	return false, conflicts
}

// immutableDifference names the first field that differs, or "".
//
// Compared field by field rather than by a whole-struct equality so the report
// can say *which* field the device tried to change. "amount" is a far more
// useful thing to find in a support log than "record differs".
func immutableDifference(in SyncTransaction, existing *domain.Transaction) string {
	switch {
	case in.CustomerID != existing.CustomerID:
		return "customer_id"
	case in.Type != existing.Type:
		return "type"
	case in.Amount != existing.Amount:
		return "amount"
	case !sameOptionalString(in.Description, existing.Description):
		return "description"
	// Compared as calendar days: the column is a DATE, so a client that sends
	// midnight in its own zone must not read as a different day than the one
	// stored. What a debt records is which day it happened on.
	case !sameDay(in.TransactionDate, existing.TransactionDate):
		return "transaction_date"
	default:
		return ""
	}
}

func sameOptionalString(a, b *string) bool {
	switch {
	case a == nil && b == nil:
		return true
	case a == nil || b == nil:
		return false
	default:
		return *a == *b
	}
}

func sameDay(a, b time.Time) bool {
	ay, am, ad := a.UTC().Date()
	by, bm, bd := b.UTC().Date()
	return ay == by && am == bm && ad == bd
}
