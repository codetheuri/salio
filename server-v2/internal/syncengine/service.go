package syncengine

import (
	"context"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
)

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

func (s *Service) Pull(ctx context.Context, cursor int64, limit int) (*PullView, error) {
	return s.repo.Pull(ctx, cursor, limit)
}

// Push applies a batch of offline changes and reports precisely what it did.
//
// Nothing here aborts the batch. A device that has been offline for a week is
// pushing a fortnight of a shop's work, and one bad record in it — an entry for
// a customer that was deleted, an amount that arrives as zero — must not cost
// the other ninety-nine. v1 returned 500 for any single failure, so the client
// retried the same doomed batch forever and the good records never landed.
// Everything acceptable is applied; the rest is reported.
func (s *Service) Push(ctx context.Context, in PushInput) (*PushView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	body := in.Body
	now := time.Now().UTC()

	return s.repo.Push(ctx, body.OperationID, func(tx *gorm.DB) (*PushView, error) {
		view := &PushView{
			OperationID: body.OperationID,
			Conflicts:   []SyncConflict{},
			ServerTime:  now,
		}

		// Customers first, so a ledger entry created against a customer in the
		// same batch finds it. A device offline all week has both.
		if err := s.applyCustomers(ctx, tx, businessID, body.Customers, now, view); err != nil {
			return nil, err
		}
		if err := s.applyTransactions(ctx, tx, businessID, body.Transactions, view); err != nil {
			return nil, err
		}
		return view, nil
	})
}

func (s *Service) applyCustomers(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, incoming []SyncCustomer, now time.Time, view *PushView) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, c := range incoming {
		ids = append(ids, c.ID)
	}
	existing, err := LoadCustomers(ctx, tx, businessID, ids)
	if err != nil {
		return err
	}

	for _, c := range incoming {
		if reason, field, detail := validateCustomer(c); reason != "" {
			view.Conflicts = append(view.Conflicts, SyncConflict{
				Table: "customers", ID: c.ID, Field: field, Reason: reason, Detail: detail,
			})
			continue
		}

		// Bounded to the server's clock before it is compared to anything. A
		// device whose clock is days fast would otherwise win every conflict it
		// ever entered, for as long as the clock stayed wrong.
		at := domain.ClampToServer(c.UpdatedAt, now)

		prior, known := existing[c.ID]
		if !known {
			if err := InsertCustomer(ctx, tx, businessID, c, at); err != nil {
				return err
			}
			view.AppliedCustomers++
			continue
		}

		merged := mergeCustomer(c, &prior, at)
		view.Conflicts = append(view.Conflicts, merged.Conflicts...)
		if len(merged.Columns) == 0 {
			continue
		}
		if err := UpdateCustomer(ctx, tx, businessID, c.ID, merged.Columns, merged.Fields, at); err != nil {
			return err
		}
		view.AppliedCustomers++
	}
	return nil
}

func (s *Service) applyTransactions(ctx context.Context, tx *gorm.DB, businessID uuid.UUID, incoming []SyncTransaction, view *PushView) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	customerIDs := make([]uuid.UUID, 0, len(incoming))
	for _, t := range incoming {
		ids = append(ids, t.ID)
		customerIDs = append(customerIDs, t.CustomerID)
	}

	existing, err := LoadTransactions(ctx, tx, businessID, ids)
	if err != nil {
		return err
	}
	// Read after applyCustomers has run, so a customer created earlier in this
	// same batch counts as present.
	customers, err := CustomerIDsIn(ctx, tx, businessID, customerIDs)
	if err != nil {
		return err
	}

	for _, t := range incoming {
		prior, known := existing[t.ID]
		if known {
			applyVoid, conflicts := mergeTransaction(t, &prior)
			view.Conflicts = append(view.Conflicts, conflicts...)
			if applyVoid {
				if err := VoidTransaction(ctx, tx, businessID, t.ID); err != nil {
					return err
				}
				view.AppliedTransactions++
			}
			continue
		}

		if reason, detail := validateTransaction(t); reason != "" {
			view.Conflicts = append(view.Conflicts, SyncConflict{
				Table: "transactions", ID: t.ID, Reason: reason, Detail: detail,
			})
			continue
		}

		// Refused rather than allowed to fail on the foreign key, so one entry
		// for a missing customer is reported as one conflict instead of
		// aborting the transaction the rest of the batch is being written in.
		if !customers[t.CustomerID] {
			view.Conflicts = append(view.Conflicts, SyncConflict{
				Table: "transactions", ID: t.ID, Field: "customer_id", Reason: ReasonUnknownCustomer,
				Detail: fmt.Sprintf("customer %s does not belong to this business", t.CustomerID),
			})
			continue
		}

		if err := InsertTransaction(ctx, tx, businessID, t); err != nil {
			return err
		}
		view.AppliedTransactions++
	}
	return nil
}

// validateCustomer checks what the schema deliberately does not.
//
// These would all be refused by a NOT NULL constraint, but as an aborted
// statement that takes every other record in the batch with it. Checked here,
// one malformed record costs one line of the conflict report.
func validateCustomer(c SyncCustomer) (reason, field, detail string) {
	switch {
	case c.Name == "":
		return ReasonInvalid, "name", "a customer must have a name"
	case c.CreatedBy == uuid.Nil:
		return ReasonInvalid, "created_by", "created_by must name the user who added this customer"
	default:
		return "", "", ""
	}
}

// validateTransaction checks what the database cannot express as clearly.
//
// The CHECK constraints in migration 00001 would refuse these too, but as an
// aborted statement that takes the whole batch with it. Checked here, a bad
// record becomes one line in the conflict report.
func validateTransaction(t SyncTransaction) (reason, detail string) {
	switch {
	case t.CustomerID == uuid.Nil:
		return ReasonInvalid, "customer_id is required"
	case t.UserID == uuid.Nil:
		return ReasonInvalid, "user_id is required"
	case !t.Type.Valid():
		return ReasonInvalid, fmt.Sprintf("%q is not a transaction type", t.Type)
	case !t.Amount.IsPositive():
		// Direction lives in Type; a negative debt is a payment wearing the
		// wrong label and would corrupt every report that groups by type.
		return ReasonInvalid, "amount must be greater than zero"
	case t.TransactionDate.IsZero():
		return ReasonInvalid, "transaction_date is required"
	default:
		return "", ""
	}
}
