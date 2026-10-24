package phone_test

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/tenant"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/testsupport"
)

// Migration 00010 converted the numbers already stored with an SQL copy of
// phone.Normalize. Both are held to the same cases, so they cannot drift.
func TestMigrationFunctionMatchesSharedVectors(t *testing.T) {
	db := testsupport.Connect(t)
	raw, err := os.ReadFile("../../../testdata/shared/phone.json")
	if err != nil {
		t.Fatal(err)
	}
	var v struct {
		Normalize []struct {
			Text string `json:"text"`
			E164 string `json:"e164"`
		} `json:"normalize"`
		Invalid []string `json:"invalid"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	canonical := func(s string) *string {
		var out *string
		if err := db.Raw("SELECT salio_canonical_phone(?)", s).Scan(&out).Error; err != nil {
			t.Fatalf("salio_canonical_phone(%q): %v", s, err)
		}
		return out
	}
	for _, c := range v.Normalize {
		if got := canonical(c.Text); got == nil || *got != c.E164 {
			t.Errorf("salio_canonical_phone(%q) = %v; want %q", c.Text, got, c.E164)
		}
	}
	for _, text := range v.Invalid {
		if got := canonical(text); got != nil {
			t.Errorf("salio_canonical_phone(%q) = %q; want NULL", text, *got)
		}
	}
}

// The conversion itself, run again on rows written the old way: every free
// number converted; two that are one number left alone, both of them.
func TestMigrationConvertsFreeNumbersAndLeavesDuplicates(t *testing.T) {
	db := testsupport.Connect(t)
	sqlText, err := os.ReadFile("../../database/migrations/00010_phone_numbers_in_one_form.sql")
	if err != nil {
		t.Fatal(err)
	}
	start := strings.Index(string(sqlText), "-- Logins:")
	end := strings.Index(string(sqlText), "ALTER TABLE users     FORCE")
	if start < 0 || end < start {
		t.Fatal("cannot find the conversion in migration 00010")
	}

	shop := domain.Business{ID: id.New(), Name: "Shop"}
	if err := tenant.Unscoped(db).Create(&shop).Error; err != nil {
		t.Fatal(err)
	}
	owner := domain.User{ID: id.New(), BusinessID: shop.ID, Name: "Owner", Phone: "0700 000 001",
		PasswordHash: "x", Role: domain.RoleOwner, IsActive: true}
	if err := tenant.Unscoped(db).Create(&owner).Error; err != nil {
		t.Fatal(err)
	}
	customer := func(p string) uuid {
		c := domain.Customer{ID: id.New(), BusinessID: shop.ID, Name: "C " + p, Phone: &p, CreatedBy: owner.ID}
		if err := tenant.Unscoped(db).Create(&c).Error; err != nil {
			t.Fatal(err)
		}
		return uuid(c.ID.String())
	}
	free := customer("0712 345 678")
	dupA, dupB := customer("0722000111"), customer("+254722000111")
	odd := customer("ask at the counter")

	if err := db.Exec(string(sqlText[start:end])).Error; err != nil {
		t.Fatalf("running the conversion: %v", err)
	}

	phoneOf := func(id uuid) string {
		var p string
		if err := tenant.Unscoped(db).Model(&domain.Customer{}).Where("id = ?", string(id)).
			Pluck("phone", &p).Error; err != nil {
			t.Fatal(err)
		}
		return p
	}
	for _, c := range []struct {
		id   uuid
		want string
	}{
		{free, "+254712345678"},
		{dupA, "0722000111"},
		{dupB, "+254722000111"},
		{odd, "ask at the counter"},
	} {
		if got := phoneOf(c.id); got != c.want {
			t.Errorf("customer phone = %q, want %q", got, c.want)
		}
	}
	var login string
	tenant.Unscoped(db).Model(&domain.User{}).Where("id = ?", owner.ID).Pluck("phone", &login)
	if login != "+254700000001" {
		t.Errorf("login phone = %q, want +254700000001", login)
	}
}

type uuid string
