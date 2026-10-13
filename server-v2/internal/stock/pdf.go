package stock

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/letterhead"
	"salio/server-v2/internal/pdfdoc"
)

// OrderPDF renders a purchase order for sending to the supplier.
//
// No prices: a shop ordering stock usually does not know the supplier's price
// until the invoice comes back, and a PO with guessed prices invites an
// argument. Quantities and product names are what the supplier needs to pack.
func (s *Service) OrderPDF(ctx context.Context, id uuid.UUID) ([]byte, string, error) {
	order, err := s.repo.GetOrder(ctx, id)
	if err != nil {
		return nil, "", err
	}
	lh, err := letterhead.Load(ctx, s.repo.db)
	if err != nil {
		return nil, "", err
	}

	fields := []pdfdoc.Field{
		{Label: "Order no.", Value: order.Reference()},
		{Label: "Date", Value: pdfdoc.Date(order.OrderedOn)},
	}
	if order.Status == domain.OrderStatusCancelled {
		// Stated in the reference block, on every page, so a cancelled order
		// that gets forwarded by mistake cannot be packed as if it were live.
		fields = append(fields, pdfdoc.Field{Label: "Status", Value: "CANCELLED"})
	}
	doc := pdfdoc.New(lh, "Purchase Order", fields)

	party := []pdfdoc.Field{{Label: "Supplier", Value: order.SupplierName}}
	if order.SupplierPhone != nil {
		party = append(party, pdfdoc.Field{Label: "Supplier tel.", Value: *order.SupplierPhone})
	}
	if name := s.userName(ctx, order.CreatedBy); name != "" {
		party = append(party, pdfdoc.Field{Label: "Ordered by", Value: name})
	}
	party = append(party, pdfdoc.Field{Label: "Products", Value: fmt.Sprint(len(order.Lines))})
	doc.Fields(party)

	doc.Heading("Products ordered")
	rows := make([][]string, 0, len(order.Lines))
	for i, l := range order.Lines {
		rows = append(rows, []string{fmt.Sprint(i + 1), l.ProductName, l.Quantity.String()})
	}
	doc.Table([]pdfdoc.Column{
		{Header: "#", Width: 0.08, Align: pdfdoc.Center},
		{Header: "Product", Width: 0.72, Align: pdfdoc.Left},
		{Header: "Quantity", Width: 0.20, Align: pdfdoc.Right},
	}, rows)

	if order.Notes != nil {
		doc.Heading("Notes")
		doc.Paragraph(*order.Notes)
	}
	doc.Paragraph("Please confirm availability and delivery date. Quote the order number above on your delivery note and invoice.")
	doc.Signature("Ordered by (signature)", "Received by (signature & date)")

	out, err := doc.Bytes()
	if err != nil {
		return nil, "", err
	}
	return out, order.Reference() + ".pdf", nil
}

func (s *Service) userName(ctx context.Context, id uuid.UUID) string {
	var u domain.User
	if err := s.repo.db.WithContext(ctx).Select("name").First(&u, "id = ?", id).Error; err != nil {
		return ""
	}
	return u.Name
}
