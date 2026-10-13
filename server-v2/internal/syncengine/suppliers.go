package syncengine

import (
	"errors"

	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/supplier"
)

// --- suppliers ---

// applySuppliers adds and edits suppliers. Every supplier change needs
// suppliers.manage — by default an owner — so a staff phone's push is refused
// record by record, with the rest of its batch unaffected.
func (p *push) applySuppliers(incoming []SyncSupplier) error {
	if len(incoming) == 0 {
		return nil
	}
	if ok, err := p.can(rbac.PermSuppliersManage); err != nil {
		return err
	} else if !ok {
		for _, s := range incoming {
			p.forbidden("suppliers", s.ID, "manage suppliers")
		}
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, s := range incoming {
		ids = append(ids, s.ID)
	}
	existing, err := loadByIDs[domain.Supplier](p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}

	for _, in := range incoming {
		prior, known := existing[in.ID]
		if !known {
			sup := &domain.Supplier{
				ID: in.ID, BusinessID: p.businessID, Name: in.Name, Phone: in.Phone, Notes: in.Notes,
				CreatedBy: p.attribute(in.CreatedBy),
			}
			if err := supplier.ValidateSupplier(sup); err != nil {
				p.conflict("suppliers", in.ID, "", ReasonInvalid, err.Error())
				continue
			}
			if handled, err := p.try("suppliers", in.ID, func(tx *gorm.DB) error {
				return tx.WithContext(p.ctx).Create(sup).Error
			}); err != nil {
				return err
			} else if handled {
				continue
			}
			p.view.AppliedSuppliers++
			// Added and deleted while offline: the delete goes through the
			// same zero-balance check as any other.
			if in.IsDeleted {
				p.pendingSupplierDeletions = append(p.pendingSupplierDeletions, in.ID)
			}
			continue
		}

		// Deletion is one-way, and applied at the end with its balance check.
		if in.IsDeleted && !prior.IsDeleted {
			p.pendingSupplierDeletions = append(p.pendingSupplierDeletions, in.ID)
		}

		edited := domain.Supplier{ID: in.ID, Name: in.Name, Phone: in.Phone, Notes: in.Notes}
		if err := supplier.ValidateSupplier(&edited); err != nil {
			p.conflict("suppliers", in.ID, "", ReasonInvalid, err.Error())
			continue
		}
		if edited.Name == prior.Name && sameOptionalString(edited.Phone, prior.Phone) &&
			sameOptionalString(edited.Notes, prior.Notes) {
			continue
		}
		// Whole-record last write wins: a supplier is edited rarely, by one
		// person, so per-field merge would be machinery with nothing to merge.
		if at := domain.ClampToServer(in.UpdatedAt, p.now); !at.After(prior.UpdatedAt) {
			p.conflict("suppliers", in.ID, "", ReasonStaleWrite, "a newer edit to this supplier is already recorded")
			continue
		}
		if handled, err := p.try("suppliers", in.ID, func(tx *gorm.DB) error {
			return tx.WithContext(p.ctx).Model(&domain.Supplier{}).
				Where("id = ? AND business_id = ? AND is_deleted = false", in.ID, p.businessID).
				Updates(map[string]any{"name": edited.Name, "phone": edited.Phone, "notes": edited.Notes}).Error
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedSuppliers++
	}
	return nil
}

func (p *push) applySupplierDeletions() error {
	for _, id := range p.pendingSupplierDeletions {
		if handled, err := p.try("suppliers", id, func(tx *gorm.DB) error {
			err := supplier.DeleteIfSettled(p.ctx, tx, id)
			if errors.Is(err, supplier.ErrNotFound) {
				return nil // already deleted
			}
			return err
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedSuppliers++
	}
	return nil
}

// --- supplier bills and payments ---

func (p *push) applySupplierTransactions(incoming []SyncSupplierTransaction) error {
	if len(incoming) == 0 {
		return nil
	}

	ids := make([]uuid.UUID, 0, len(incoming))
	for _, t := range incoming {
		ids = append(ids, t.ID)
	}
	existing, err := loadByIDs[domain.SupplierTransaction](p.ctx, p.tx, p.businessID, ids)
	if err != nil {
		return err
	}

	for _, in := range incoming {
		if prior, known := existing[in.ID]; known {
			if field := supplierEntryDifference(in, prior); field != "" {
				p.conflict("supplier_transactions", in.ID, field, ReasonImmutable,
					"a recorded bill or payment cannot be edited; void it and record it again")
			}
			switch {
			case in.IsDeleted && !prior.IsDeleted:
				if err := p.voidSupplierEntry(in.ID); err != nil {
					return err
				}
			case !in.IsDeleted && prior.IsDeleted:
				p.conflict("supplier_transactions", in.ID, "", ReasonAlreadyVoided, "this entry was voided on another device")
			}
			continue
		}

		if ok, err := p.can(rbac.PermSuppliersManage); err != nil {
			return err
		} else if !ok {
			p.forbidden("supplier_transactions", in.ID, "record supplier bills and payments")
			continue
		}

		entry := &domain.SupplierTransaction{
			ID: in.ID, BusinessID: p.businessID, SupplierID: in.SupplierID,
			UserID: p.attribute(in.UserID), Type: in.Type, Amount: in.Amount,
			Description: in.Description, TransactionDate: in.TransactionDate, DueDate: in.DueDate,
			PaymentMethod: in.PaymentMethod, Reference: in.Reference, PurchaseOrderID: in.PurchaseOrderID,
		}
		if handled, err := p.try("supplier_transactions", in.ID, func(tx *gorm.DB) error {
			return supplier.Record(p.ctx, tx, entry)
		}); err != nil {
			return err
		} else if handled {
			continue
		}
		p.view.AppliedSupplierTransactions++

		if in.IsDeleted {
			if err := p.voidSupplierEntry(in.ID); err != nil {
				return err
			}
		}
	}
	return nil
}

func (p *push) voidSupplierEntry(id uuid.UUID) error {
	if ok, err := p.can(rbac.PermSuppliersVoid); err != nil {
		return err
	} else if !ok {
		p.forbidden("supplier_transactions", id, "void a supplier bill or payment")
		return nil
	}
	if handled, err := p.try("supplier_transactions", id, func(tx *gorm.DB) error {
		return supplier.Void(p.ctx, tx, id)
	}); err != nil || handled {
		return err
	}
	p.view.AppliedSupplierTransactions++
	return nil
}

// supplierEntryDifference names the first field a device tried to change on a
// recorded bill or payment, or "".
func supplierEntryDifference(in SyncSupplierTransaction, prior domain.SupplierTransaction) string {
	switch {
	case in.SupplierID != prior.SupplierID:
		return "supplier_id"
	case in.Type != prior.Type:
		return "type"
	case in.Amount != prior.Amount:
		return "amount"
	case trimSpace(in.Description) != prior.Description:
		return "description"
	case !sameDay(in.TransactionDate, prior.TransactionDate):
		return "transaction_date"
	case !sameOptionalDay(in.DueDate, prior.DueDate):
		return "due_date"
	case !sameOptionalMethod(in.PaymentMethod, prior.PaymentMethod):
		return "payment_method"
	case !sameReference(methodOf(in.PaymentMethod), in.Reference, prior.Reference):
		return "reference"
	case !sameOptionalUUID(in.PurchaseOrderID, prior.PurchaseOrderID):
		return "purchase_order_id"
	default:
		return ""
	}
}
