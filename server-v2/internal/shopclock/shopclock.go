// Package shopclock answers "what day is it?" for the business making the
// request, in that business's own time zone.
//
// It reads the zone on every call rather than caching it: one primary-key read
// costs less than the write it dates, and a cache would have to be invalidated
// on every server instance when an owner changes the zone. Every repository
// that needs a date asks through here, so no module can fall back to the
// server's zone by accident.
package shopclock

import (
	"context"
	"fmt"
	"time"

	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
)

// Location is the time zone of the business in ctx. Tenant-scoped by the
// Business model's callbacks: it can only read the caller's own business.
func Location(ctx context.Context, db *gorm.DB) (*time.Location, error) {
	// First, not Scan: First runs the query callbacks that add the tenant
	// condition, the same path every other tenant read takes.
	var b domain.Business
	if err := db.WithContext(ctx).Select("id", "time_zone").First(&b).Error; err != nil {
		return nil, fmt.Errorf("reading the business time zone: %w", err)
	}
	return domain.ZoneOrDefault(b.TimeZone), nil
}

// Now is the current instant, as seen on the business's wall clock — for
// printing ("Printed 13 Oct 2026, 01:15"), never for storing.
func Now(ctx context.Context, db *gorm.DB) (time.Time, error) {
	loc, err := Location(ctx, db)
	if err != nil {
		return time.Time{}, err
	}
	return time.Now().In(loc), nil
}

// Today is the business's current calendar date, as a midnight-UTC value; see
// domain.DateIn.
func Today(ctx context.Context, db *gorm.DB) (time.Time, error) {
	loc, err := Location(ctx, db)
	if err != nil {
		return time.Time{}, err
	}
	return domain.DateIn(time.Now(), loc), nil
}
