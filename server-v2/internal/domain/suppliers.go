package domain

import (
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/money"
)

// Supplier is someone the shop buys from — the distributor, the wholesaler, the
// agrovet depot.
type Supplier struct {
	ID         uuid.UUID `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID uuid.UUID `json:"business_id" gorm:"type:uuid;not null;index"`
	Name       string    `json:"name"        gorm:"size:255;not null"`
	Phone      *string   `json:"phone,omitempty" gorm:"size:50"`
	Notes      *string   `json:"notes,omitempty"`
	CreatedBy  uuid.UUID `json:"created_by"  gorm:"type:uuid;not null"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
	IsDeleted  bool      `json:"is_deleted"  gorm:"not null;default:false"`

	ChangeSeq int64 `json:"-" gorm:"->"`
}

func (Supplier) TableName() string    { return "suppliers" }
func (Supplier) TenantColumn() string { return "business_id" }

func (s *Supplier) BeforeCreate(*gorm.DB) error {
	if id.IsZero(s.ID) {
		s.ID = id.New()
	}
	return nil
}

// SupplierEntryType is which way money moves between the shop and a supplier.
type SupplierEntryType string

const (
	// SupplierBill is goods or services received on credit: the shop now owes.
	SupplierBill SupplierEntryType = "bill"

	// SupplierPayment is the shop paying a supplier.
	SupplierPayment SupplierEntryType = "payment"
)

func (t SupplierEntryType) Valid() bool { return t == SupplierBill || t == SupplierPayment }

// SupplierTransaction is one immutable entry in what the shop owes a supplier —
// the customer ledger turned around, under the same rules: amounts positive,
// direction in Type, corrections by voiding, balance always derived.
type SupplierTransaction struct {
	ID              uuid.UUID         `json:"id"          gorm:"type:uuid;primaryKey"`
	BusinessID      uuid.UUID         `json:"business_id" gorm:"type:uuid;not null;index"`
	SupplierID      uuid.UUID         `json:"supplier_id" gorm:"type:uuid;not null;index"`
	UserID          uuid.UUID         `json:"user_id"     gorm:"type:uuid;not null"`
	Type            SupplierEntryType `json:"type"        gorm:"size:10;not null"`
	Amount          money.Amount      `json:"amount"      gorm:"type:numeric(12,2);not null"`
	Description     string            `json:"description" gorm:"not null"`
	TransactionDate time.Time         `json:"transaction_date" gorm:"type:date;not null"`

	// DueDate is when a bill must be paid by. Bills only.
	DueDate *time.Time `json:"due_date,omitempty" gorm:"type:date"`

	// PaymentMethod and Reference say how a payment was made. Payments only,
	// and a payment must have a method.
	PaymentMethod *PaymentMethod `json:"payment_method,omitempty" gorm:"size:10"`
	Reference     *string        `json:"reference,omitempty"      gorm:"size:30"`

	// PurchaseOrderID is the order a bill is for, when there was one.
	PurchaseOrderID *uuid.UUID `json:"purchase_order_id,omitempty" gorm:"type:uuid"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
	IsDeleted bool      `json:"is_deleted" gorm:"not null;default:false"`

	ChangeSeq int64 `json:"-" gorm:"->"`
}

func (SupplierTransaction) TableName() string    { return "supplier_transactions" }
func (SupplierTransaction) TenantColumn() string { return "business_id" }

func (t *SupplierTransaction) BeforeCreate(*gorm.DB) error {
	if id.IsZero(t.ID) {
		t.ID = id.New()
	}
	return nil
}
