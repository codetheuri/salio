package business_test

import (
	"bytes"
	"context"
	"errors"
	"image"
	"image/color"
	"image/png"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/internal/business"
	"salio/server-v2/internal/letterhead"
)

func pngOf(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	img.Set(0, 0, color.RGBA{13, 148, 136, 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("encoding: %v", err)
	}
	return buf.Bytes()
}

func TestLogo_IsStoredAndPrintedInTheLetterhead(t *testing.T) {
	s, db := newService(t)
	owner := register(t, s, "0712000001")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	if s.HasLogo(ctx) {
		t.Fatal("a new business reports a logo")
	}
	logo := pngOf(t, 120, 60)
	if err := s.SetLogo(ctx, logo); err != nil {
		t.Fatalf("set logo: %v", err)
	}
	if !s.HasLogo(ctx) {
		t.Fatal("the logo was not stored")
	}

	lh, err := letterhead.Load(ctx, db)
	if err != nil {
		t.Fatalf("letterhead: %v", err)
	}
	if !bytes.Equal(lh.Logo, logo) || lh.LogoType != "image/png" || lh.BusinessName != "Test Shop" {
		t.Fatalf("letterhead = %+v", lh)
	}

	// Replacing works, and removing leaves none.
	if err := s.SetLogo(ctx, pngOf(t, 40, 40)); err != nil {
		t.Fatalf("replace: %v", err)
	}
	if err := s.DeleteLogo(ctx); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if s.HasLogo(ctx) {
		t.Fatal("the logo survived being deleted")
	}
}

func TestLogo_RefusesWhatIsNotASmallPNGOrJPEG(t *testing.T) {
	s, _ := newService(t)
	owner := register(t, s, "0712000002")
	ctx := tenant.WithTenant(context.Background(), owner.User.BusinessID)

	// The type is judged from the bytes, never from the Content-Type header,
	// and the image is decoded once here so a broken file is refused at upload
	// rather than discovered as a blank space on a purchase order.
	for name, tc := range map[string]struct {
		data []byte
		want error
	}{
		"empty":              {nil, business.ErrLogoEmpty},
		"a text file":        {[]byte("definitely not an image, just some text"), business.ErrLogoFormat},
		"a truncated PNG":    {pngOf(t, 50, 50)[:40], business.ErrLogoFormat},
		"over 512 KB":        {make([]byte, business.MaxLogoBytes+1), business.ErrLogoTooLarge},
		"an enormous canvas": {pngOf(t, 5000, 10), business.ErrLogoTooLarge},
	} {
		if err := s.SetLogo(ctx, tc.data); !errors.Is(err, tc.want) {
			t.Errorf("%s: got %v, want %v", name, err, tc.want)
		}
	}
}
