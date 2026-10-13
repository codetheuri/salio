// Package pdfdoc renders Salio's printed documents: purchase orders, customer
// statements and reports.
//
// Every document shares one layout — the business's letterhead at the top, a
// title and reference block, tables, and a footer — so a shop's paperwork looks
// like it came from one place, whichever screen it was downloaded from. Each
// document type only describes its own content.
//
// The footer carries "Powered by Salio" on purpose: these PDFs leave the shop and
// land with suppliers and customers, and every one is a small advertisement for
// the app to another business.
package pdfdoc

import (
	"bytes"
	"fmt"
	"strings"
	"time"

	"github.com/go-pdf/fpdf"
)

// FooterTagline is printed at the foot of every page.
const FooterTagline = "Powered by Salio  ·  Digital debt, sales and stock records for shops"

// Layout, in millimetres on A4 portrait.
const (
	pageWidth    = 210.0
	pageHeight   = 297.0
	margin       = 15.0
	contentWidth = pageWidth - 2*margin
	logoMaxH     = 22.0
	logoMaxW     = 40.0
	footerHeight = 14.0
	rowHeight    = 7.0
)

// The palette: one accent, used sparingly, plus greys. Printed on cheap office
// printers more often than viewed on screen, so contrast matters more than
// subtlety.
var (
	accent    = rgb{13, 148, 136} // teal, matching the admin console
	ink       = rgb{31, 41, 55}
	muted     = rgb{107, 114, 128}
	rule      = rgb{209, 213, 219}
	zebra     = rgb{243, 244, 246}
	headerInk = rgb{255, 255, 255}
)

type rgb struct{ r, g, b int }

// Letterhead is the business printed at the top of every page.
type Letterhead struct {
	BusinessName string
	Address      string
	Phone        string
	Email        string

	// PrintedAt is when the document was generated, in the shop's time zone.
	// Zero means now on the server's clock.
	PrintedAt time.Time

	// Logo is a PNG or JPEG. Empty means none, and the name takes its place.
	Logo        []byte
	LogoType    string // "image/png" or "image/jpeg"
	BusinessTag string // optional second line under the name, e.g. "Agrovet"
}

// Field is one label-and-value line in a document's reference block or summary.
type Field struct {
	Label string
	Value string
}

// Align is a column's text alignment.
type Align string

const (
	Left   Align = "L"
	Right  Align = "R"
	Center Align = "C"
)

// Column describes one table column. Widths are fractions of the content width
// and should sum to 1, so a table always spans the page whatever its columns.
type Column struct {
	Header string
	Width  float64
	Align  Align
}

// Document is one PDF being built.
type Document struct {
	pdf     *fpdf.Fpdf
	tr      func(string) string
	lh      Letterhead
	title   string
	fields  []Field
	logo    string
	printed time.Time
}

// New starts a document. title is what the document is ("Purchase Order",
// "Customer Statement"); fields are its reference details, printed opposite the
// letterhead (number, date, period).
func New(lh Letterhead, title string, fields []Field) *Document {
	pdf := fpdf.New("P", "mm", "A4", "")
	pdf.SetMargins(margin, margin, margin)
	pdf.SetAutoPageBreak(false, margin+footerHeight)
	pdf.SetTitle(title+" - "+lh.BusinessName, true)
	pdf.SetAuthor(lh.BusinessName, true)
	pdf.SetCreator("Salio", true)
	pdf.AliasNbPages("{nb}")

	d := &Document{
		pdf:     pdf,
		tr:      pdf.UnicodeTranslatorFromDescriptor(""), // cp1252: covers names, "·", "×", currency text
		lh:      lh,
		title:   title,
		fields:  fields,
		printed: printedAt(lh.PrintedAt),
	}
	d.registerLogo()

	pdf.SetHeaderFunc(d.header)
	pdf.SetFooterFunc(d.footer)
	pdf.AddPage()
	return d
}

// registerLogo loads the image once. A logo that will not decode is dropped
// rather than failing the document: an order with no logo still gets sent, an
// order that will not render at all does not.
func (d *Document) registerLogo() {
	if len(d.lh.Logo) == 0 {
		return
	}
	typ := "PNG"
	if d.lh.LogoType == "image/jpeg" {
		typ = "JPG"
	}
	info := d.pdf.RegisterImageOptionsReader("logo", fpdf.ImageOptions{ImageType: typ}, bytes.NewReader(d.lh.Logo))
	if d.pdf.Err() || info == nil {
		d.pdf.ClearError()
		return
	}
	d.logo = "logo"
}

// header draws the letterhead and the document's reference block on every page,
// so a page that gets separated from the rest still says whose it is.
func (d *Document) header() {
	p := d.pdf
	top := margin

	textX := margin
	if d.logo != "" {
		info := p.GetImageInfo(d.logo)
		w, h := info.Width(), info.Height()
		scale := logoMaxH / h
		if w*scale > logoMaxW {
			scale = logoMaxW / w
		}
		w, h = w*scale, h*scale
		p.ImageOptions(d.logo, margin, top, w, h, false, fpdf.ImageOptions{}, 0, "")
		textX = margin + w + 5
	}

	// Left: the business.
	nameWidth := contentWidth*0.6 - (textX - margin)
	p.SetXY(textX, top)
	d.setColor(ink)
	// The name is the one thing on the page that must never be cut short — it
	// is who the document is from. Long names are common ("Wanjiku Agrovet &
	// General Supplies"), so the font steps down until the whole name fits, and
	// only a name too long even at the smallest size is shortened.
	size := 16.0
	name := d.tr(d.lh.BusinessName)
	for size > 10 {
		p.SetFont("Helvetica", "B", size)
		if p.GetStringWidth(name) <= nameWidth {
			break
		}
		size -= 0.5
	}
	p.SetFont("Helvetica", "B", size)
	p.CellFormat(nameWidth, 8, d.fit(d.lh.BusinessName, nameWidth), "", 2, "L", false, 0, "")

	p.SetFont("Helvetica", "", 9)
	d.setColor(muted)
	for _, line := range d.contactLines() {
		p.SetX(textX)
		p.CellFormat(nameWidth, 4.5, d.fit(line, nameWidth), "", 2, "L", false, 0, "")
	}
	leftBottom := p.GetY()

	// Right: what this document is.
	blockX := margin + contentWidth*0.6
	blockW := contentWidth * 0.4
	p.SetXY(blockX, top)
	p.SetFont("Helvetica", "B", 14)
	d.setColor(accent)
	p.CellFormat(blockW, 8, d.tr(strings.ToUpper(d.title)), "", 2, "R", false, 0, "")
	p.SetFont("Helvetica", "", 9)
	// The value gets most of the width, and a gap separates it from its label:
	// a period ("13 Sep 2026 – 13 Oct 2026") is the longest value here, and
	// without the gap it printed flush against "Period" as one word.
	const gap = 2.0
	labelW, valueW := blockW*0.30, blockW*0.70-gap
	for _, f := range d.fields {
		p.SetX(blockX)
		d.setColor(muted)
		p.CellFormat(labelW, 4.5, d.tr(f.Label), "", 0, "R", false, 0, "")
		p.SetX(blockX + labelW + gap)
		d.setColor(ink)
		p.SetFont("Helvetica", "B", 9)
		p.CellFormat(valueW, 4.5, d.fit(f.Value, valueW), "", 2, "R", false, 0, "")
		p.SetFont("Helvetica", "", 9)
	}
	rightBottom := p.GetY()

	bottom := max(leftBottom, rightBottom, top+logoMaxH) + 3
	d.drawRule(bottom, accent, 0.6)
	p.SetY(bottom + 5)
	d.setColor(ink)
}

func (d *Document) contactLines() []string {
	var lines []string
	if d.lh.BusinessTag != "" {
		lines = append(lines, d.lh.BusinessTag)
	}
	if d.lh.Address != "" {
		lines = append(lines, d.lh.Address)
	}
	var contact []string
	if d.lh.Phone != "" {
		contact = append(contact, "Tel: "+d.lh.Phone)
	}
	if d.lh.Email != "" {
		contact = append(contact, d.lh.Email)
	}
	if len(contact) > 0 {
		lines = append(lines, strings.Join(contact, "   ·   "))
	}
	return lines
}

func (d *Document) footer() {
	p := d.pdf
	y := pageHeight - margin - 6
	d.drawRule(y-2, rule, 0.3)

	p.SetY(y)
	p.SetFont("Helvetica", "", 8)
	d.setColor(muted)
	p.CellFormat(contentWidth*0.7, 4, d.tr(FooterTagline), "", 0, "L", false, 0, "")
	p.CellFormat(contentWidth*0.3, 4,
		d.tr(fmt.Sprintf("Page %d of {nb}", p.PageNo())), "", 2, "R", false, 0, "")
	p.SetX(margin)
	p.CellFormat(contentWidth, 4,
		d.tr("Generated "+d.printed.Format("2 Jan 2006, 15:04")), "", 0, "L", false, 0, "")
}

// Heading starts a section.
func (d *Document) Heading(text string) {
	d.ensureSpace(14)
	p := d.pdf
	p.Ln(2)
	p.SetFont("Helvetica", "B", 11)
	d.setColor(ink)
	p.CellFormat(contentWidth, 7, d.tr(text), "", 2, "L", false, 0, "")
	p.Ln(1)
}

// Paragraph prints wrapped text.
func (d *Document) Paragraph(text string) {
	p := d.pdf
	p.SetFont("Helvetica", "", 9.5)
	d.setColor(ink)
	for _, line := range p.SplitText(d.tr(text), contentWidth) {
		d.ensureSpace(5)
		p.CellFormat(contentWidth, 5, line, "", 2, "L", false, 0, "")
	}
	p.Ln(2)
}

// Fields prints a block of label-and-value pairs in two columns, for party
// details ("Supplier", "Customer") and summaries.
func (d *Document) Fields(fields []Field) {
	p := d.pdf
	half := contentWidth / 2
	for i, f := range fields {
		if i%2 == 0 {
			d.ensureSpace(6)
		}
		x := margin
		if i%2 == 1 {
			x = margin + half
		}
		p.SetX(x)
		p.SetFont("Helvetica", "", 9)
		d.setColor(muted)
		p.CellFormat(half*0.38, 6, d.tr(f.Label), "", 0, "L", false, 0, "")
		p.SetFont("Helvetica", "B", 9.5)
		d.setColor(ink)
		ln := 0
		if i%2 == 1 || i == len(fields)-1 {
			ln = 1
		}
		p.CellFormat(half*0.62, 6, d.fit(f.Value, half*0.62), "", ln, "L", false, 0, "")
	}
	p.Ln(2)
}

// Table prints rows under a header, repeating the header on every page the
// table crosses. Text that would overflow its cell is shortened with "…" rather
// than spilling into the next column. A row whose first cell is "TOTAL" is
// printed bold, as the closing line of the table.
func (d *Document) Table(cols []Column, rows [][]string) {
	d.tableHeader(cols)
	p := d.pdf
	for i, row := range rows {
		if d.wouldOverflow(rowHeight) {
			p.AddPage()
			d.tableHeader(cols)
		}
		total := len(row) > 0 && strings.EqualFold(row[0], "TOTAL")
		fill := i%2 == 1 && !total
		if fill {
			d.setFill(zebra)
		}
		style := ""
		if total {
			style = "B"
			d.drawRule(p.GetY(), ink, 0.4)
		}
		p.SetFont("Helvetica", style, 9)
		d.setColor(ink)
		for c, col := range cols {
			w := col.Width * contentWidth
			text := ""
			if c < len(row) {
				text = row[c]
			}
			ln := 0
			if c == len(cols)-1 {
				ln = 1
			}
			p.CellFormat(w, rowHeight, d.fit(text, w-2), "", ln, string(col.Align), fill, 0, "")
		}
	}
	if len(rows) == 0 {
		p.SetFont("Helvetica", "I", 9)
		d.setColor(muted)
		p.CellFormat(contentWidth, rowHeight, d.tr("Nothing to show for this period."), "", 1, "C", false, 0, "")
	}
	p.Ln(3)
}

func (d *Document) tableHeader(cols []Column) {
	p := d.pdf
	d.ensureSpace(rowHeight * 2)
	d.setFill(accent)
	p.SetFont("Helvetica", "B", 9)
	p.SetTextColor(headerInk.r, headerInk.g, headerInk.b)
	for i, col := range cols {
		ln := 0
		if i == len(cols)-1 {
			ln = 1
		}
		w := col.Width * contentWidth
		p.CellFormat(w, rowHeight, d.fit(col.Header, w-2), "", ln, string(col.Align), true, 0, "")
	}
	d.setColor(ink)
}

// Signature prints lines for a person to sign and date, as a purchase order and
// a statement both need when they are handed over on paper.
func (d *Document) Signature(labels ...string) {
	d.ensureSpace(24)
	p := d.pdf
	p.Ln(8)
	w := contentWidth / float64(len(labels))
	y := p.GetY() + 8
	for i, label := range labels {
		x := margin + float64(i)*w
		p.SetDrawColor(ink.r, ink.g, ink.b)
		p.SetLineWidth(0.3)
		p.Line(x+2, y, x+w-8, y)
		p.SetXY(x+2, y+1)
		p.SetFont("Helvetica", "", 8.5)
		d.setColor(muted)
		p.CellFormat(w-10, 4, d.tr(label), "", 0, "L", false, 0, "")
	}
	p.SetY(y + 8)
}

// Bytes finishes the document.
func (d *Document) Bytes() ([]byte, error) {
	var buf bytes.Buffer
	if err := d.pdf.Output(&buf); err != nil {
		return nil, fmt.Errorf("pdfdoc: rendering %q: %w", d.title, err)
	}
	return buf.Bytes(), nil
}

// --- helpers ---

func (d *Document) wouldOverflow(h float64) bool {
	return d.pdf.GetY()+h > pageHeight-margin-footerHeight
}

func (d *Document) ensureSpace(h float64) {
	if d.wouldOverflow(h) {
		d.pdf.AddPage()
	}
}

// fit translates text for the PDF's encoding and shortens it to a width.
func (d *Document) fit(text string, width float64) string {
	s := d.tr(text)
	if d.pdf.GetStringWidth(s) <= width {
		return s
	}
	ellipsis := d.tr("…")
	for len(s) > 0 && d.pdf.GetStringWidth(s+ellipsis) > width {
		s = s[:len(s)-1]
	}
	return s + ellipsis
}

func (d *Document) drawRule(y float64, c rgb, width float64) {
	d.pdf.SetDrawColor(c.r, c.g, c.b)
	d.pdf.SetLineWidth(width)
	d.pdf.Line(margin, y, pageWidth-margin, y)
}

func (d *Document) setColor(c rgb) { d.pdf.SetTextColor(c.r, c.g, c.b) }
func (d *Document) setFill(c rgb)  { d.pdf.SetFillColor(c.r, c.g, c.b) }

// Date formats a day the way it reads on paper in Kenya: "13 Oct 2026".
func Date(t time.Time) string { return t.Format("2 Jan 2006") }

// KES prefixes an already-formatted amount with the currency.
func KES(formatted string) string { return "KES " + formatted }

func printedAt(t time.Time) time.Time {
	if t.IsZero() {
		return time.Now()
	}
	return t
}
