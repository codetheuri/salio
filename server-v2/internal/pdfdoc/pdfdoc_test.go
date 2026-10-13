package pdfdoc

import (
	"bytes"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"regexp"
	"testing"
)

// sampleLogo is a small generated PNG, so the test needs no fixture file.
func sampleLogo(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 120, 120))
	for y := range 120 {
		for x := range 120 {
			c := color.RGBA{13, 148, 136, 255}
			if (x-60)*(x-60)+(y-60)*(y-60) < 30*30 {
				c = color.RGBA{255, 255, 255, 255}
			}
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("encoding logo: %v", err)
	}
	return buf.Bytes()
}

func sample(t *testing.T, rows int, logo []byte) []byte {
	t.Helper()
	d := New(Letterhead{
		BusinessName: "Wanjiku Agrovet & General Supplies",
		BusinessTag:  "Agrovet",
		Address:      "Shop 4, Kiambu Road, Ruiru",
		Phone:        "0712 345 678",
		Email:        "wanjiku.agrovet@example.com",
		Logo:         logo, LogoType: "image/png",
	}, "Purchase Order", []Field{
		{Label: "Order no.", Value: "PO-0007"},
		{Label: "Date", Value: "13 Oct 2026"},
	})
	d.Fields([]Field{
		{Label: "Supplier", Value: "Twiga Agro Distributors"},
		{Label: "Supplier tel.", Value: "0722 000 111"},
	})
	d.Heading("Products requested")
	var data [][]string
	for i := 1; i <= rows; i++ {
		data = append(data, []string{fmt.Sprint(i), fmt.Sprintf("Duodip 20ml — line %d with a long name that must be shortened", i), "12", "pcs"})
	}
	d.Table([]Column{
		{Header: "#", Width: 0.08, Align: Center},
		{Header: "Product", Width: 0.62, Align: Left},
		{Header: "Quantity", Width: 0.15, Align: Right},
		{Header: "Unit", Width: 0.15, Align: Left},
	}, data)
	d.Paragraph("Please deliver to the shop address above. Call before delivery.")
	d.Signature("Ordered by", "Received by")

	out, err := d.Bytes()
	if err != nil {
		t.Fatalf("rendering: %v", err)
	}
	return out
}

func TestDocument_RendersAValidPDFWithALogo(t *testing.T) {
	out := sample(t, 5, sampleLogo(t))
	if !bytes.HasPrefix(out, []byte("%PDF-")) {
		t.Fatal("output is not a PDF")
	}
	if os.Getenv("PDFDOC_SAMPLE_DIR") != "" {
		_ = os.WriteFile(filepath.Join(os.Getenv("PDFDOC_SAMPLE_DIR"), "sample.pdf"), out, 0o644)
	}
}

func TestDocument_ALongTableRunsOntoMorePages(t *testing.T) {
	out := sample(t, 90, nil)
	pages := len(regexp.MustCompile(`/Type /Page\b`).FindAll(out, -1))
	if pages < 3 {
		t.Fatalf("90 rows rendered on %d pages; the table should break across pages with its header repeated", pages)
	}
	if os.Getenv("PDFDOC_SAMPLE_DIR") != "" {
		_ = os.WriteFile(filepath.Join(os.Getenv("PDFDOC_SAMPLE_DIR"), "long.pdf"), out, 0o644)
	}
}

func TestDocument_ABrokenLogoDoesNotStopTheDocument(t *testing.T) {
	// An order with no logo still gets sent; an order that will not render at
	// all does not.
	out := sample(t, 2, []byte("this is not an image"))
	if !bytes.HasPrefix(out, []byte("%PDF-")) {
		t.Fatal("a broken logo stopped the document from rendering")
	}
}
