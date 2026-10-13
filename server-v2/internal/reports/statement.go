package reports

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
)

// StatementLine is one entry on a customer statement.
type StatementLine struct {
	TransactionID uuid.UUID              `json:"transaction_id"`
	Date          time.Time              `json:"date"`
	Type          domain.TransactionType `json:"type"`
	Description   string                 `json:"description"`
	Debit         money.Amount           `json:"debit" doc:"Added to what the customer owes (a debt)"`
	Credit        money.Amount           `json:"credit" doc:"Taken off what the customer owes (a payment)"`
	Balance       money.Amount           `json:"balance" doc:"Running balance after this entry; negative means an advance"`
}

// StatementView is one customer's account over a period — what a shop hands a
// customer who asks "how much do I owe, and for what?"
type StatementView struct {
	CustomerID     uuid.UUID       `json:"customer_id"`
	CustomerName   string          `json:"customer_name"`
	CustomerPhone  *string         `json:"customer_phone,omitempty"`
	Period         Period          `json:"period"`
	OpeningBalance money.Amount    `json:"opening_balance" doc:"Balance carried in from before the period"`
	Lines          []StatementLine `json:"lines"`
	TotalDebits    money.Amount    `json:"total_debits"`
	TotalCredits   money.Amount    `json:"total_credits"`
	ClosingBalance money.Amount    `json:"closing_balance"`

	// Standing reads the closing balance in words, because "-300.00" means
	// nothing to most customers: "owes", "advance" or "settled".
	Standing string `json:"standing" enum:"owes,advance,settled"`
}

// Statement builds a customer's statement.
//
// The opening balance is everything before the period, so a statement for
// October still starts from what was owed at the end of September rather than
// from zero. Voided entries are left out: a statement is what the customer
// actually owes, not a log of the shop's corrections.
func (r *Repository) Statement(ctx context.Context, customerID uuid.UUID, p Period) (*StatementView, error) {
	var c domain.Customer
	err := r.db.WithContext(ctx).First(&c, "id = ?", customerID).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrCustomerNotFound
	}
	if err != nil {
		return nil, err
	}

	v := &StatementView{
		CustomerID: c.ID, CustomerName: c.Name, CustomerPhone: c.Phone,
		Period: p, Lines: []StatementLine{},
	}

	if err := r.db.WithContext(ctx).Model(&domain.Transaction{}).
		Select("COALESCE(SUM(CASE WHEN type = 'debt' THEN amount ELSE -amount END), 0)").
		Where("customer_id = ? AND is_deleted = false AND transaction_date < ?", customerID, p.From).
		Scan(&v.OpeningBalance).Error; err != nil {
		return nil, fmt.Errorf("opening balance: %w", err)
	}

	var txs []domain.Transaction
	if err := r.db.WithContext(ctx).
		Where("customer_id = ? AND is_deleted = false AND transaction_date BETWEEN ? AND ?",
			customerID, p.From, p.To).
		Order("transaction_date, created_at").
		Find(&txs).Error; err != nil {
		return nil, fmt.Errorf("statement entries: %w", err)
	}

	running := v.OpeningBalance
	for _, t := range txs {
		line := StatementLine{
			TransactionID: t.ID, Date: t.TransactionDate, Type: t.Type,
			Description: deref(t.Description),
		}
		if t.Type == domain.TypeDebt {
			line.Debit = t.Amount
			v.TotalDebits += t.Amount
		} else {
			line.Credit = t.Amount
			v.TotalCredits += t.Amount
		}
		running += t.Signed()
		line.Balance = running
		v.Lines = append(v.Lines, line)
	}
	v.ClosingBalance = running
	v.Standing = standing(running)
	return v, nil
}

func standing(balance money.Amount) string {
	switch {
	case balance > 0:
		return "owes"
	case balance < 0:
		return "advance"
	default:
		return "settled"
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// tenantID is used by queries that state the business explicitly on a joined
// table, which the automatic scoping does not reach.
func tenantID(ctx context.Context) (uuid.UUID, error) { return tenant.MustFromContext(ctx) }
