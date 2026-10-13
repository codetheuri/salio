// Package letterhead loads the business details printed at the top of every PDF.
//
// One function, used by every document, so a purchase order and a customer
// statement can never disagree about how the shop presents itself.
package letterhead

import (
	"context"
	"errors"
	"fmt"
	"time"

	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/pdfdoc"
)

// Load reads the caller's business and its logo. Tenant-scoped by the models'
// callbacks: it can only ever load the business making the request.
func Load(ctx context.Context, db *gorm.DB) (pdfdoc.Letterhead, error) {
	var b domain.Business
	if err := db.WithContext(ctx).First(&b).Error; err != nil {
		return pdfdoc.Letterhead{}, fmt.Errorf("loading the business for the letterhead: %w", err)
	}

	lh := pdfdoc.Letterhead{
		BusinessName: b.Name,
		BusinessTag:  deref(b.Type),
		Address:      deref(b.Address),
		Phone:        deref(b.Phone),
		Email:        deref(b.Email),
		PrintedAt:    time.Now().In(domain.ZoneOrDefault(b.TimeZone)),
	}

	// A missing logo is normal — most shops will never upload one — so its
	// absence is not an error, and neither is a failure to read it: a document
	// without a logo is still a document worth sending.
	var logo domain.BusinessLogo
	err := db.WithContext(ctx).First(&logo).Error
	switch {
	case err == nil:
		lh.Logo, lh.LogoType = logo.Data, logo.ContentType
	case !errors.Is(err, gorm.ErrRecordNotFound):
		// Fall through without a logo.
	}
	return lh, nil
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}
