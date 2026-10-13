package shopclock_test

import (
	"context"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/shopclock"
	"salio/server-v2/internal/testsupport"
)

// Kiritimati is UTC+14 and Pago Pago UTC-11: 25 hours apart, so they are on
// different calendar days at every instant. That makes "each business gets its
// own today" testable without faking the clock.
const (
	ahead  = "Pacific/Kiritimati"
	behind = "Pacific/Pago_Pago"
)

func business(t *testing.T, db *gorm.DB, zone string) context.Context {
	t.Helper()
	b := &domain.Business{Name: "Shop in " + zone, TimeZone: zone}
	if err := tenant.Unscoped(db.WithContext(context.Background())).Create(b).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	return tenant.WithTenant(context.Background(), b.ID)
}

func TestToday_EachBusinessGetsItsOwnDate(t *testing.T) {
	db := testsupport.Connect(t)
	aheadCtx, behindCtx := business(t, db, ahead), business(t, db, behind)

	a, err := shopclock.Today(aheadCtx, db)
	if err != nil {
		t.Fatalf("today (ahead): %v", err)
	}
	b, err := shopclock.Today(behindCtx, db)
	if err != nil {
		t.Fatalf("today (behind): %v", err)
	}

	if !a.After(b) {
		t.Fatalf("%s today = %s, %s today = %s; want the first later — each business must read its own zone",
			ahead, a.Format(time.DateOnly), behind, b.Format(time.DateOnly))
	}
	if a.Location() != time.UTC || b.Location() != time.UTC {
		t.Fatalf("want midnight-UTC dates, got %s and %s", a, b)
	}
}

func TestLocation_ABusinessCreatedWithoutAZoneIsInNairobi(t *testing.T) {
	db := testsupport.Connect(t)

	// No TimeZone: GORM must leave the column out so its default applies,
	// rather than writing "" — the zero-value trap this project keeps meeting.
	b := &domain.Business{Name: "Shop with no zone"}
	if err := tenant.Unscoped(db.WithContext(context.Background())).Create(b).Error; err != nil {
		t.Fatalf("create business: %v", err)
	}
	var stored string
	if err := db.Raw("SELECT time_zone FROM businesses WHERE id = ?", b.ID).Scan(&stored).Error; err != nil {
		t.Fatalf("read zone: %v", err)
	}
	if stored != domain.DefaultTimeZone {
		t.Fatalf("stored time_zone = %q, want %q", stored, domain.DefaultTimeZone)
	}

	loc, err := shopclock.Location(tenant.WithTenant(context.Background(), b.ID), db)
	if err != nil {
		t.Fatalf("location: %v", err)
	}
	if loc.String() != domain.DefaultTimeZone {
		t.Fatalf("location = %s, want %s", loc, domain.DefaultTimeZone)
	}
}

func TestLocation_NeedsATenant(t *testing.T) {
	db := testsupport.Connect(t)
	business(t, db, ahead)

	// Without a tenant there is no "the business" to ask; it must not quietly
	// read some other shop's zone.
	if _, err := shopclock.Location(context.Background(), db); err == nil {
		t.Fatal("want an error without a tenant in the context")
	}
}
