package business

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg" // registers the decoder used by image.DecodeConfig
	_ "image/png"
	"net/http"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"salio/server-v2/internal/domain"
)

// MaxLogoBytes bounds an uploaded logo. A letterhead logo prints at about four
// centimetres; half a megabyte is far more than that needs, and every PDF the
// shop downloads carries it.
const MaxLogoBytes = 512 << 10

// maxLogoPixels bounds the image's dimensions. A small file can still declare
// an enormous canvas, and decoding one is a way to exhaust a server's memory.
const maxLogoPixels = 4000

var (
	ErrLogoEmpty    = errors.New("the logo is empty")
	ErrLogoTooLarge = errors.New("the logo is larger than 512 KB; a smaller image prints just as well")
	ErrLogoFormat   = errors.New("the logo must be a PNG or JPEG image")
	ErrLogoNotFound = errors.New("no logo has been uploaded")
)

// SetLogo validates and stores the business's logo, replacing any before it.
//
// The type is detected from the bytes, never taken from the request's
// Content-Type: a header is whatever the client chose to send. And the image is
// decoded once here, so a file that claims to be a PNG but is not is refused at
// upload — not discovered later as a blank space on a purchase order.
func (s *Service) SetLogo(ctx context.Context, data []byte) error {
	if len(data) == 0 {
		return ErrLogoEmpty
	}
	if len(data) > MaxLogoBytes {
		return ErrLogoTooLarge
	}

	contentType := http.DetectContentType(data)
	if contentType != "image/png" && contentType != "image/jpeg" {
		return ErrLogoFormat
	}
	// Two steps, in this order. DecodeConfig reads only the header, so it
	// cannot tell a whole image from one cut off halfway — the header survives
	// truncation — but it is cheap, and it is what bounds the canvas size before
	// anything is allocated for it. The full decode then proves the pixel data
	// is actually there, at a cost the size check has already bounded.
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || cfg.Width == 0 || cfg.Height == 0 {
		return ErrLogoFormat
	}
	if cfg.Width > maxLogoPixels || cfg.Height > maxLogoPixels {
		return ErrLogoTooLarge
	}
	if _, _, err := image.Decode(bytes.NewReader(data)); err != nil {
		return ErrLogoFormat
	}

	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return err
	}
	return s.repo.UpsertLogo(ctx, &domain.BusinessLogo{
		BusinessID: businessID, ContentType: contentType, Data: data, UpdatedAt: time.Now().UTC(),
	})
}

func (s *Service) GetLogo(ctx context.Context) (*domain.BusinessLogo, error) {
	return s.repo.GetLogo(ctx)
}

func (s *Service) DeleteLogo(ctx context.Context) error {
	return s.repo.DeleteLogo(ctx)
}

// HasLogo reports whether a logo is stored. A failed lookup reads as "no": the
// flag only decides whether the app tries to fetch one.
func (s *Service) HasLogo(ctx context.Context) bool {
	return s.repo.HasLogo(ctx)
}

// --- repository ---

func (r *Repository) UpsertLogo(ctx context.Context, logo *domain.BusinessLogo) error {
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "business_id"}},
		DoUpdates: clause.AssignmentColumns([]string{"content_type", "data", "updated_at"}),
	}).Create(logo).Error
}

func (r *Repository) GetLogo(ctx context.Context) (*domain.BusinessLogo, error) {
	var logo domain.BusinessLogo
	err := r.db.WithContext(ctx).First(&logo).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		return nil, ErrLogoNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("loading logo: %w", err)
	}
	return &logo, nil
}

func (r *Repository) DeleteLogo(ctx context.Context) error {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return err
	}
	res := r.db.WithContext(ctx).Where("business_id = ?", businessID).Delete(&domain.BusinessLogo{})
	if res.Error != nil {
		return res.Error
	}
	if res.RowsAffected == 0 {
		return ErrLogoNotFound
	}
	return nil
}

func (r *Repository) HasLogo(ctx context.Context) bool {
	var n int64
	if err := r.db.WithContext(ctx).Model(&domain.BusinessLogo{}).Count(&n).Error; err != nil {
		return false
	}
	return n > 0
}
