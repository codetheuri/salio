package reports

import (
	"context"
	"fmt"
	"strings"

	"salio/server-v2/internal/letterhead"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/pdfdoc"
)

func periodLabel(p Period) string {
	return pdfdoc.Date(p.From) + " – " + pdfdoc.Date(p.To)
}

func kes(a money.Amount) string { return pdfdoc.KES(a.Formatted()) }

// blankIfZero keeps a column of mostly-empty debit/credit cells readable: a
// statement where every row shows "0.00" in the column that does not apply is
// harder to scan than one where that cell is simply empty.
func blankIfZero(a money.Amount) string {
	if a == 0 {
		return ""
	}
	return a.Formatted()
}

// StatementPDF renders a statement for handing to the customer.
func (r *Repository) StatementPDF(ctx context.Context, v *StatementView) ([]byte, string, error) {
	lh, err := letterhead.Load(ctx, r.db)
	if err != nil {
		return nil, "", err
	}
	doc := pdfdoc.New(lh, "Customer Statement", []pdfdoc.Field{
		{Label: "Period", Value: periodLabel(v.Period)},
		{Label: "Customer", Value: v.CustomerName},
	})

	party := []pdfdoc.Field{{Label: "Customer", Value: v.CustomerName}}
	if v.CustomerPhone != nil {
		party = append(party, pdfdoc.Field{Label: "Phone", Value: *v.CustomerPhone})
	}
	party = append(party,
		pdfdoc.Field{Label: "Opening balance", Value: kes(v.OpeningBalance)},
		pdfdoc.Field{Label: "Closing balance", Value: kes(v.ClosingBalance)},
	)
	doc.Fields(party)

	doc.Heading("Account activity")
	rows := [][]string{{"", "Balance brought forward", "", "", v.OpeningBalance.Formatted()}}
	for _, l := range v.Lines {
		rows = append(rows, []string{
			pdfdoc.Date(l.Date), l.Description, blankIfZero(l.Debit), blankIfZero(l.Credit), l.Balance.Formatted(),
		})
	}
	rows = append(rows, []string{"TOTAL", "", v.TotalDebits.Formatted(), v.TotalCredits.Formatted(), v.ClosingBalance.Formatted()})
	doc.Table([]pdfdoc.Column{
		{Header: "Date", Width: 0.15, Align: pdfdoc.Left},
		{Header: "Description", Width: 0.40, Align: pdfdoc.Left},
		{Header: "Debt (KES)", Width: 0.15, Align: pdfdoc.Right},
		{Header: "Paid (KES)", Width: 0.15, Align: pdfdoc.Right},
		{Header: "Balance (KES)", Width: 0.15, Align: pdfdoc.Right},
	}, rows)

	// The closing line in words, because a negative number confuses customers.
	switch v.Standing {
	case "owes":
		doc.Heading("Amount due: " + kes(v.ClosingBalance))
	case "advance":
		doc.Heading("Advance held for you: " + kes(-v.ClosingBalance))
		doc.Paragraph("You have paid ahead. This amount will be set against your next purchases.")
	default:
		doc.Heading("Your account is fully settled. Thank you.")
	}
	doc.Paragraph("Please contact us if anything on this statement does not match your records.")

	out, err := doc.Bytes()
	return out, "statement-" + slug(v.CustomerName) + ".pdf", err
}

// AgeingPDF renders the debt ageing report.
func (r *Repository) AgeingPDF(ctx context.Context, v *AgeingView) ([]byte, string, error) {
	lh, err := letterhead.Load(ctx, r.db)
	if err != nil {
		return nil, "", err
	}
	doc := pdfdoc.New(lh, "Debt Ageing", []pdfdoc.Field{
		{Label: "As of", Value: pdfdoc.Date(v.AsOf)},
		{Label: "Customers", Value: fmt.Sprint(len(v.Rows))},
	})

	doc.Fields([]pdfdoc.Field{
		{Label: "Total owed", Value: kes(v.Total)},
		{Label: "Over 90 days", Value: kes(v.Over90)},
		{Label: "0 – 30 days", Value: kes(v.Current)},
		{Label: "31 – 60 days", Value: kes(v.Days31To60)},
		{Label: "61 – 90 days", Value: kes(v.Days61To90)},
		{Label: "Past agreed due date", Value: kes(v.Overdue)},
		{Label: "Over credit limit", Value: plural(v.OverLimit, "customer", "customers")},
	})
	doc.Paragraph("Payments are applied to each customer's oldest debt first, so an amount shown " +
		"in an older column has been owed that long, however often the customer has paid since.")

	doc.Heading("By customer, longest-owed first")
	rows := make([][]string, 0, len(v.Rows)+1)
	for _, a := range v.Rows {
		name := a.Name
		if a.OverLimit {
			name += " *"
		}
		rows = append(rows, []string{
			name, blankIfZero(a.Current), blankIfZero(a.Days31To60),
			blankIfZero(a.Days61To90), blankIfZero(a.Over90), blankIfZero(a.Overdue), a.Total.Formatted(),
		})
	}
	rows = append(rows, []string{"TOTAL", v.Current.Formatted(), v.Days31To60.Formatted(),
		v.Days61To90.Formatted(), v.Over90.Formatted(), v.Overdue.Formatted(), v.Total.Formatted()})
	doc.Table([]pdfdoc.Column{
		{Header: "Customer", Width: 0.25, Align: pdfdoc.Left},
		{Header: "0-30", Width: 0.12, Align: pdfdoc.Right},
		{Header: "31-60", Width: 0.12, Align: pdfdoc.Right},
		{Header: "61-90", Width: 0.12, Align: pdfdoc.Right},
		{Header: "90+", Width: 0.12, Align: pdfdoc.Right},
		{Header: "Past due", Width: 0.12, Align: pdfdoc.Right},
		{Header: "Total (KES)", Width: 0.15, Align: pdfdoc.Right},
	}, rows)
	doc.Paragraph("\"Past due\" is the part owed beyond the date the customer agreed to pay by; " +
		"debts recorded without a due date are never counted as past due. " +
		"* over the customer's credit limit.")

	out, err := doc.Bytes()
	return out, "debt-ageing-" + dayKey(v.AsOf) + ".pdf", err
}

// PayablesPDF renders what the shop owes its suppliers, most urgent first.
func (r *Repository) PayablesPDF(ctx context.Context, v *PayablesView) ([]byte, string, error) {
	lh, err := letterhead.Load(ctx, r.db)
	if err != nil {
		return nil, "", err
	}
	doc := pdfdoc.New(lh, "Owed to Suppliers", []pdfdoc.Field{
		{Label: "As of", Value: pdfdoc.Date(v.AsOf)},
		{Label: "Suppliers", Value: fmt.Sprint(len(v.Rows))},
	})

	doc.Fields([]pdfdoc.Field{
		{Label: "Total owed", Value: kes(v.Owed)},
		{Label: "Past due", Value: kes(v.Overdue)},
		{Label: fmt.Sprintf("Due within %d days", v.WithinDays), Value: kes(v.DueSoon)},
		{Label: "Prepaid to suppliers", Value: kes(v.PrepaymentsHeld)},
	})
	doc.Paragraph("Payments are applied to each supplier's oldest bill first. \"Past due\" is the part " +
		"of bills whose due date has passed; bills recorded without a due date are never past due.")

	doc.Heading("By supplier, most urgent first")
	rows := make([][]string, 0, len(v.Rows)+1)
	for _, p := range v.Rows {
		next := ""
		if p.NextDue != nil {
			next = pdfdoc.Date(*p.NextDue)
		}
		rows = append(rows, []string{
			p.Name, pdfdoc.Date(p.OldestBill), next,
			blankIfZero(p.Overdue), blankIfZero(p.DueSoon), p.Owed.Formatted(),
		})
	}
	rows = append(rows, []string{"TOTAL", "", "", v.Overdue.Formatted(), v.DueSoon.Formatted(), v.Owed.Formatted()})
	doc.Table([]pdfdoc.Column{
		{Header: "Supplier", Width: 0.28, Align: pdfdoc.Left},
		{Header: "Oldest bill", Width: 0.15, Align: pdfdoc.Left},
		{Header: "Next due", Width: 0.15, Align: pdfdoc.Left},
		{Header: "Past due", Width: 0.14, Align: pdfdoc.Right},
		{Header: "Due soon", Width: 0.13, Align: pdfdoc.Right},
		{Header: "Owed (KES)", Width: 0.15, Align: pdfdoc.Right},
	}, rows)

	out, err := doc.Bytes()
	return out, "owed-to-suppliers-" + dayKey(v.AsOf) + ".pdf", err
}

// SalesPDF renders the sales report.
func (r *Repository) SalesPDF(ctx context.Context, v *SalesReportView) ([]byte, string, error) {
	lh, err := letterhead.Load(ctx, r.db)
	if err != nil {
		return nil, "", err
	}
	doc := pdfdoc.New(lh, "Sales Report", []pdfdoc.Field{
		{Label: "Period", Value: periodLabel(v.Period)},
		{Label: "Sales", Value: fmt.Sprint(v.Count)},
	})
	doc.Fields([]pdfdoc.Field{
		{Label: "Total sales", Value: kes(v.Total)},
		{Label: "Number of sales", Value: fmt.Sprint(v.Count)},
		{Label: "Paid on the spot", Value: fmt.Sprintf("%s (%d)", kes(v.PaidTotal), v.PaidCount)},
		{Label: "On credit", Value: fmt.Sprintf("%s (%d)", kes(v.CreditTotal), v.CreditCount)},
		{Label: "Cash", Value: kes(v.CashTotal)},
		{Label: "M-Pesa", Value: kes(v.MpesaTotal)},
		{Label: "Bank", Value: kes(v.BankTotal)},
	})

	doc.Heading("Best-selling products")
	products := make([][]string, 0, len(v.TopProducts))
	for i, p := range v.TopProducts {
		products = append(products, []string{fmt.Sprint(i + 1), p.ProductName, p.Quantity.String(),
			fmt.Sprint(p.Count), p.Amount.Formatted()})
	}
	doc.Table([]pdfdoc.Column{
		{Header: "#", Width: 0.07, Align: pdfdoc.Center},
		{Header: "Product", Width: 0.45, Align: pdfdoc.Left},
		{Header: "Qty sold", Width: 0.14, Align: pdfdoc.Right},
		{Header: "Sales", Width: 0.12, Align: pdfdoc.Right},
		{Header: "Value (KES)", Width: 0.22, Align: pdfdoc.Right},
	}, products)

	// Only days with sales. The JSON keeps every day, because a chart needs the
	// quiet ones to show a gap; on paper, a month of mostly-zero rows is two
	// pages of noise between the reader and the days that matter.
	doc.Heading("Day by day")
	daily := make([][]string, 0, len(v.Daily)+1)
	for _, d := range v.Daily {
		if d.Count == 0 {
			continue
		}
		daily = append(daily, []string{pdfdoc.Date(d.Date), fmt.Sprint(d.Count),
			blankIfZero(d.Cash), blankIfZero(d.Mpesa), blankIfZero(d.Bank), blankIfZero(d.Credit),
			d.Total.Formatted()})
	}
	daily = append(daily, []string{"TOTAL", fmt.Sprint(v.Count), v.CashTotal.Formatted(),
		v.MpesaTotal.Formatted(), v.BankTotal.Formatted(), v.CreditTotal.Formatted(), v.Total.Formatted()})
	doc.Table([]pdfdoc.Column{
		{Header: "Date", Width: 0.17, Align: pdfdoc.Left},
		{Header: "Sales", Width: 0.08, Align: pdfdoc.Right},
		{Header: "Cash", Width: 0.15, Align: pdfdoc.Right},
		{Header: "M-Pesa", Width: 0.15, Align: pdfdoc.Right},
		{Header: "Bank", Width: 0.13, Align: pdfdoc.Right},
		{Header: "Credit", Width: 0.15, Align: pdfdoc.Right},
		{Header: "Total (KES)", Width: 0.17, Align: pdfdoc.Right},
	}, daily)
	doc.Paragraph("Amounts in KES. Days with no sales are not listed.")

	out, err := doc.Bytes()
	return out, "sales-" + dayKey(v.Period.From) + "-to-" + dayKey(v.Period.To) + ".pdf", err
}

// CollectionsPDF renders collections and staff activity.
func (r *Repository) CollectionsPDF(ctx context.Context, v *CollectionsView) ([]byte, string, error) {
	lh, err := letterhead.Load(ctx, r.db)
	if err != nil {
		return nil, "", err
	}
	doc := pdfdoc.New(lh, "Collections Report", []pdfdoc.Field{
		{Label: "Period", Value: periodLabel(v.Period)},
		{Label: "Payments", Value: fmt.Sprint(v.PaymentCount)},
	})
	doc.Fields([]pdfdoc.Field{
		{Label: "Collected", Value: kes(v.TotalCollected)},
		{Label: "Payments", Value: fmt.Sprint(v.PaymentCount)},
		{Label: "Cash", Value: kes(v.Cash)},
		{Label: "M-Pesa", Value: kes(v.Mpesa)},
		{Label: "Bank", Value: kes(v.Bank)},
		{Label: "Advances held now", Value: kes(v.AdvancesHeld)},
		{Label: "Customers in credit", Value: fmt.Sprint(v.CustomersInCredit)},
	})
	if v.Unrecorded > 0 {
		doc.Paragraph(fmt.Sprintf("%s was collected in payments recorded before the payment method "+
			"was asked for; it is shown as \"Not recorded\".", kes(v.Unrecorded)))
	}

	doc.Heading("Staff activity")
	staff := make([][]string, 0, len(v.Staff))
	for _, s := range v.Staff {
		name := s.Name
		if !s.IsActive {
			name += " (left)"
		}
		staff = append(staff, []string{
			name, capitalise(string(s.Role)),
			fmt.Sprintf("%d · %s", s.SalesCount, s.SalesTotal.Formatted()),
			fmt.Sprintf("%d · %s", s.DebtsCount, s.DebtsTotal.Formatted()),
			fmt.Sprintf("%d · %s", s.PaymentsCount, s.PaymentsTotal.Formatted()),
		})
	}
	doc.Table([]pdfdoc.Column{
		{Header: "Name", Width: 0.25, Align: pdfdoc.Left},
		{Header: "Role", Width: 0.11, Align: pdfdoc.Left},
		{Header: "Sales", Width: 0.21, Align: pdfdoc.Right},
		{Header: "Debts entered", Width: 0.21, Align: pdfdoc.Right},
		{Header: "Payments taken", Width: 0.22, Align: pdfdoc.Right},
	}, staff)
	doc.Paragraph("Each column shows the number of entries, then their value in KES. " +
		"Debts from credit sales are counted under Sales, not twice.")

	doc.Heading("Collected day by day")
	daily := make([][]string, 0, len(v.Daily)+1)
	for _, d := range v.Daily {
		if d.Count == 0 {
			continue // see SalesPDF: every day in the JSON, only active days on paper
		}
		row := []string{pdfdoc.Date(d.Date), fmt.Sprint(d.Count),
			blankIfZero(d.Cash), blankIfZero(d.Mpesa), blankIfZero(d.Bank)}
		if v.Unrecorded > 0 {
			row = append(row, blankIfZero(d.Unrecorded))
		}
		daily = append(daily, append(row, d.Amount.Formatted()))
	}
	total := []string{"TOTAL", fmt.Sprint(v.PaymentCount), v.Cash.Formatted(), v.Mpesa.Formatted(), v.Bank.Formatted()}
	columns := []pdfdoc.Column{
		{Header: "Date", Width: 0.20, Align: pdfdoc.Left},
		{Header: "Payments", Width: 0.12, Align: pdfdoc.Right},
		{Header: "Cash", Width: 0.16, Align: pdfdoc.Right},
		{Header: "M-Pesa", Width: 0.17, Align: pdfdoc.Right},
		{Header: "Bank", Width: 0.15, Align: pdfdoc.Right},
	}
	// A row whose columns do not add up to its total reads as a mistake, so
	// payments with no recorded method get a column of their own — only when
	// there are any, which in time there will not be.
	if v.Unrecorded > 0 {
		total = append(total, v.Unrecorded.Formatted())
		columns = []pdfdoc.Column{
			{Header: "Date", Width: 0.17, Align: pdfdoc.Left},
			{Header: "Payments", Width: 0.11, Align: pdfdoc.Right},
			{Header: "Cash", Width: 0.14, Align: pdfdoc.Right},
			{Header: "M-Pesa", Width: 0.14, Align: pdfdoc.Right},
			{Header: "Bank", Width: 0.12, Align: pdfdoc.Right},
			{Header: "Not recorded", Width: 0.15, Align: pdfdoc.Right},
		}
	}
	daily = append(daily, append(total, v.TotalCollected.Formatted()))
	doc.Table(append(columns, pdfdoc.Column{Header: "Total (KES)", Width: 1 - widthOf(columns), Align: pdfdoc.Right}), daily)
	doc.Paragraph("Amounts in KES. Days with nothing collected are not listed.")

	out, err := doc.Bytes()
	return out, "collections-" + dayKey(v.Period.From) + "-to-" + dayKey(v.Period.To) + ".pdf", err
}

// slug makes a name safe for a download filename.
func slug(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			b.WriteRune(r)
		case b.Len() > 0 && !strings.HasSuffix(b.String(), "-"):
			b.WriteByte('-')
		}
	}
	return strings.Trim(b.String(), "-")
}

// capitalise upper-cases the first letter of an ASCII word: "owner" -> "Owner".
func capitalise(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func plural(n int, one, many string) string {
	if n == 1 {
		return fmt.Sprintf("%d %s", n, one)
	}
	return fmt.Sprintf("%d %s", n, many)
}

func widthOf(columns []pdfdoc.Column) float64 {
	var w float64
	for _, c := range columns {
		w += c.Width
	}
	return w
}
