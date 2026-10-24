package server_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/config"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
	"gorm.io/gorm"

	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/rbac"
	"salio/server-v2/internal/server"
	"salio/server-v2/internal/testsupport"
)

// These tests run the whole API — the server production runs, assembled by
// server.Build — as an unprivileged database role, over HTTP.
//
// Every other test in the module connects as the test database's superuser,
// which PostgreSQL exempts from row-level security. That is how the API came to
// be unable to register a business under the role production must use, with
// every test green. These are the tests that would have caught it.

const appRole, appPassword = "salio_e2e_app", "salio-e2e-app"

// restrictedRole creates (once) a login role with no superuser and no
// BYPASSRLS, granted ordinary read and write on every table — what
// deploy/postgres/roles.sql gives the production application role.
func restrictedRole(t *testing.T, admin *gorm.DB) {
	t.Helper()
	for _, stmt := range []string{
		fmt.Sprintf(`DO $$ BEGIN
			IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '%s') THEN
				CREATE ROLE %s LOGIN PASSWORD '%s' NOSUPERUSER NOBYPASSRLS;
			END IF; END $$`, appRole, appRole, appPassword),
		"GRANT USAGE ON SCHEMA public TO " + appRole,
		"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO " + appRole,
		"GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO " + appRole,
	} {
		if err := admin.Exec(stmt).Error; err != nil {
			t.Fatalf("preparing the restricted role: %v", err)
		}
	}
}

// configFor builds the API's configuration for a database role, from the test
// database's own connection string.
func configFor(t *testing.T, user, password string) *config.Config {
	t.Helper()
	pc, err := pgconn.ParseConfig(testsupport.DSN())
	if err != nil {
		t.Fatalf("parsing the test DSN: %v", err)
	}
	for k, v := range map[string]string{
		"DB_DRIVER": "postgres", "DB_HOST": pc.Host, "DB_PORT": strconv.Itoa(int(pc.Port)),
		"DB_NAME": pc.Database, "DB_USER": user, "DB_PASS": password, "DB_SSLMODE": "disable",
		"JWT_SECRET": "an-end-to-end-test-secret-of-32-chars-or-more", "APP_MODE": "development",
		"LOG_LEVEL": "error",
	} {
		t.Setenv(k, v)
	}
	cfg, err := config.LoadConfig()
	if err != nil {
		t.Fatalf("loading config: %v", err)
	}
	return cfg
}

type client struct {
	t   *testing.T
	url string
}

func (c client) do(method, path, token string, body any) (int, map[string]any) {
	c.t.Helper()
	var r io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		r = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.url+"/api/v1"+path, r)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatalf("%s %s: %v", method, path, err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	var out map[string]any
	if strings.HasPrefix(resp.Header.Get("Content-Type"), "application/json") ||
		strings.HasPrefix(resp.Header.Get("Content-Type"), "application/problem+json") {
		_ = json.Unmarshal(raw, &out)
	} else {
		out = map[string]any{"raw": raw}
	}
	return resp.StatusCode, out
}

func data(m map[string]any) map[string]any { d, _ := m["data"].(map[string]any); return d }

func (c client) mustOK(method, path, token string, body any) map[string]any {
	c.t.Helper()
	status, out := c.do(method, path, token, body)
	if status != http.StatusOK {
		c.t.Fatalf("%s %s = %d %v, want 200", method, path, status, out)
	}
	return out
}

func (c client) register(shop, phone, password string) string {
	c.t.Helper()
	out := c.mustOK("POST", "/auth/register-business", "", map[string]any{
		"business_name": shop, "name": "Owner", "phone": phone, "password": password,
	})
	return data(out)["token"].(string)
}

func startAsRestrictedRole(t *testing.T) client {
	t.Helper()
	admin := testsupport.Connect(t) // migrates, empties every table, cleans up after
	restrictedRole(t, admin)

	app, err := server.Build(configFor(t, appRole, appPassword), logger.NewTextLogger("error"),
		server.Options{MigrateOnBoot: false, RequireRLS: true})
	if err != nil {
		t.Fatalf("building the server as %s: %v", appRole, err)
	}
	srv := httptest.NewServer(app.Router())
	t.Cleanup(func() {
		srv.Close()
		if sqlDB, err := app.DB().DB(); err == nil {
			_ = sqlDB.Close()
		}
	})
	return client{t: t, url: srv.URL}
}

func TestBuild_RefusesARoleThatBypassesRowLevelSecurity(t *testing.T) {
	testsupport.Connect(t)
	pc, err := pgconn.ParseConfig(testsupport.DSN())
	if err != nil {
		t.Fatal(err)
	}
	// The test database's own user is a superuser: exactly what production
	// must never run as, and what every test before these ran as.
	_, err = server.Build(configFor(t, pc.User, pc.Password), logger.NewTextLogger("error"),
		server.Options{RequireRLS: true})
	if err == nil {
		t.Fatal("Build accepted a superuser with RequireRLS set")
	}
}

func TestAPI_WorksEndToEndUnderRowLevelSecurity(t *testing.T) {
	c := startAsRestrictedRole(t)

	owner := c.register("Ruiru Agrovet", "0714000001", "owner-pass-1")

	// The pre-tenant paths: a taken phone, signing in, joining by invite.
	if status, _ := c.do("POST", "/auth/register-business", "", map[string]any{
		"business_name": "Copy", "name": "Someone", "phone": "0714000001", "password": "whatever-1",
	}); status != http.StatusConflict {
		t.Fatalf("registering a taken phone = %d, want 409", status)
	}
	c.mustOK("POST", "/auth/login", "", map[string]any{"phone": "0714000001", "password": "owner-pass-1"})
	code := data(c.mustOK("POST", "/auth/invite", owner, nil))["code"].(string)
	staff := data(c.mustOK("POST", "/auth/join", "", map[string]any{
		"code": code, "name": "Staff", "phone": "0714000002", "password": "staff-pass-1",
	}))["token"].(string)

	// Ordinary work, through REST and through sync.
	cid := data(c.mustOK("POST", "/customers", staff, map[string]any{"name": "Wanjiku"}))["id"].(string)
	c.mustOK("POST", "/transactions", staff, map[string]any{
		"customer_id": cid, "type": "debt", "amount": "1000", "description": "DAP 50kg",
	})
	c.mustOK("POST", "/sales", staff, map[string]any{
		"product_name": "Duodip 20ml", "quantity": "1", "amount": "450", "payment_method": "mpesa", "reference": "SJK4X7Y2PQ",
	})
	push := data(c.mustOK("POST", "/sync/push", staff, map[string]any{
		"operation_id": uuid.NewString(),
		"transactions": []map[string]any{{
			"id": uuid.NewString(), "customer_id": cid, "type": "payment", "amount": "400.00",
			"description": "part", "payment_method": "cash", "transaction_date": time.Now().UTC().Format(time.RFC3339),
		}},
	}))
	if push["applied_transactions"].(float64) != 1 {
		t.Fatalf("sync push = %v", push)
	}
	pulled := data(c.mustOK("GET", "/sync/pull?cursor=0", owner, nil))
	if len(pulled["transactions"].([]any)) != 2 || len(pulled["sales"].([]any)) != 1 {
		t.Fatalf("pull = %v", pulled)
	}
	got := data(c.mustOK("GET", "/customers/"+cid, owner, nil))
	if got["balance"] != "600.00" {
		t.Fatalf("balance = %v, want 600.00", got["balance"])
	}
	sid := data(c.mustOK("POST", "/suppliers", owner, map[string]any{"name": "Elgon Kenya"}))["id"].(string)
	c.mustOK("POST", "/supplier-transactions", owner, map[string]any{
		"supplier_id": sid, "type": "bill", "amount": "5000", "description": "Invoice 1",
	})
	if status, out := c.do("GET", "/reports/ageing/pdf", owner, nil); status != 200 || !bytes.HasPrefix(out["raw"].([]byte), []byte("%PDF")) {
		t.Fatalf("ageing pdf = %d", status)
	}

	// Another business sees none of it — the database refuses too, now.
	other := c.register("Other Shop", "0714000009", "other-pass-1")
	if status, _ := c.do("GET", "/customers/"+cid, other, nil); status != http.StatusNotFound {
		t.Fatalf("another business reading a customer by id = %d, want 404", status)
	}
	if list := c.mustOK("GET", "/customers", other, nil)["data"].([]any); len(list) != 0 {
		t.Fatalf("another business listed %d customers", len(list))
	}
}

func TestAPI_SessionsEnd(t *testing.T) {
	c := startAsRestrictedRole(t)
	owner := c.register("Ruiru Agrovet", "0715000001", "owner-pass-1")
	code := data(c.mustOK("POST", "/auth/invite", owner, nil))["code"].(string)
	joined := data(c.mustOK("POST", "/auth/join", "", map[string]any{
		"code": code, "name": "Staff", "phone": "0715000002", "password": "staff-pass-1",
	}))
	staff := joined["token"].(string)
	staffID := joined["user"].(map[string]any)["id"].(string)

	// Tokens carry whole seconds; step past the one they were issued in.
	time.Sleep(1100 * time.Millisecond)

	// Changing a password signs out every other session and keeps this one.
	if status, _ := c.do("PUT", "/users/me/password", owner, map[string]any{
		"current_password": "not-it", "new_password": "owner-pass-2",
	}); status != http.StatusUnprocessableEntity {
		t.Fatalf("wrong current password = %d, want 422 (a 401 would sign the app out)", status)
	}
	fresh := data(c.mustOK("PUT", "/users/me/password", owner, map[string]any{
		"current_password": "owner-pass-1", "new_password": "owner-pass-2",
	}))["token"].(string)
	if status, _ := c.do("GET", "/customers", owner, nil); status != http.StatusUnauthorized {
		t.Fatalf("the old token after a password change = %d, want 401", status)
	}
	c.mustOK("GET", "/customers", fresh, nil)

	// An owner's reset: the staff member is signed out, signs in with the
	// temporary password, and can do nothing until they choose their own.
	time.Sleep(1100 * time.Millisecond)
	temp := data(c.mustOK("POST", "/staff/"+staffID+"/reset-password", fresh, nil))["temporary_password"].(string)
	if status, _ := c.do("GET", "/customers", staff, nil); status != http.StatusUnauthorized {
		t.Fatalf("staff token after a reset = %d, want 401", status)
	}
	signedIn := data(c.mustOK("POST", "/auth/login", "", map[string]any{"phone": "0715000002", "password": temp}))
	if signedIn["user"].(map[string]any)["must_change_password"] != true {
		t.Fatal("signing in with a temporary password did not say a new one is needed")
	}
	tempToken := signedIn["token"].(string)
	if status, _ := c.do("GET", "/customers", tempToken, nil); status != http.StatusForbidden {
		t.Fatalf("work before choosing a password = %d, want 403", status)
	}
	time.Sleep(1100 * time.Millisecond)
	own := data(c.mustOK("PUT", "/users/me/password", tempToken, map[string]any{
		"current_password": temp, "new_password": "staff-pass-2",
	}))["token"].(string)
	c.mustOK("GET", "/customers", own, nil)

	// Deactivation ends access at once — not when the 30-day token expires.
	c.mustOK("DELETE", "/staff/"+staffID, fresh, nil)
	for _, path := range []string{"/customers", "/sync/pull?cursor=0"} {
		if status, _ := c.do("GET", path, own, nil); status != http.StatusUnauthorized {
			t.Fatalf("deactivated staff GET %s = %d, want 401", path, status)
		}
	}
}

// B2 and B14 through the real router, as the restricted role: a push may carry
// fields this server does not know, and a refused record comes back as the
// server holds it, supplier records only to those who may read them.
func TestAPI_SyncIgnoresUnknownFieldsAndReturnsTheServersCopy(t *testing.T) {
	c := startAsRestrictedRole(t)
	owner := c.register("Ruiru Agrovet", "0716000001", "owner-pass-1")
	code := data(c.mustOK("POST", "/auth/invite", owner, nil))["code"].(string)
	joined := data(c.mustOK("POST", "/auth/join", "", map[string]any{
		"code": code, "name": "Staff", "phone": "0716000002", "password": "staff-pass-1",
	}))
	staff := joined["token"].(string)
	staffID := joined["user"].(map[string]any)["id"].(string)

	// REST stays strict.
	if status, _ := c.do("POST", "/customers", staff, map[string]any{"name": "Wanjiku", "nickname": "Shiku"}); status != http.StatusUnprocessableEntity {
		t.Fatalf("REST create with an unknown field = %d, want 422", status)
	}

	// Sync does not: unknown fields at the top and inside a record.
	cid := uuid.NewString()
	now := time.Now().UTC().Format(time.RFC3339)
	push := data(c.mustOK("POST", "/sync/push", staff, map[string]any{
		"operation_id":  uuid.NewString(),
		"loyalty_cards": []any{map[string]any{"id": uuid.NewString()}},
		"customers": []map[string]any{{
			"id": cid, "name": "Wanjiku", "nickname": "Shiku", "created_by": staffID,
			"created_at": now, "updated_at": now,
		}},
	}))
	if push["applied_customers"].(float64) != 1 {
		t.Fatalf("push with unknown fields = %v", push)
	}

	// Staff may not delete: refused, with the live customer to put back.
	refused := data(c.mustOK("POST", "/sync/push", staff, map[string]any{
		"operation_id": uuid.NewString(),
		"customers": []map[string]any{{
			"id": cid, "name": "Wanjiku", "is_deleted": true, "updated_at": now,
			"changed_fields": []string{"is_deleted"},
		}},
	}))
	current := refused["current"].(map[string]any)
	copies := current["customers"].([]any)
	if len(refused["conflicts"].([]any)) != 1 || len(copies) != 1 {
		t.Fatalf("refused delete = %v", refused)
	}
	if got := copies[0].(map[string]any); got["id"] != cid || got["is_deleted"] != false || got["name"] != "Wanjiku" {
		t.Fatalf("server's copy = %v, want the live customer", got)
	}

	// A supplier the owner made, edited by staff: refused, and its copy is
	// not handed to someone who may not read suppliers.
	sid := data(c.mustOK("POST", "/suppliers", owner, map[string]any{"name": "Elgon Kenya"}))["id"].(string)
	refused = data(c.mustOK("POST", "/sync/push", staff, map[string]any{
		"operation_id": uuid.NewString(),
		"suppliers":    []map[string]any{{"id": sid, "name": "Renamed", "updated_at": now}},
	}))
	current = refused["current"].(map[string]any)
	if len(refused["conflicts"].([]any)) != 1 || len(current["suppliers"].([]any)) != 0 {
		t.Fatalf("staff supplier push = %v, want one conflict and no copy", refused)
	}
}

// B5 and B15 through the real router, as the restricted role: sign-in and
// /users/me carry the permissions the routes check, and every phone number
// is stored in one form whichever way it was typed, by REST and by sync.
func TestAPI_PermissionsAndOnePhoneForm(t *testing.T) {
	c := startAsRestrictedRole(t)

	registered := data(c.mustOK("POST", "/auth/register-business", "", map[string]any{
		"business_name": "Ruiru Agrovet", "name": "Owner", "phone": "0717 000 001", "password": "owner-pass-1",
	}))
	owner := registered["token"].(string)
	user := registered["user"].(map[string]any)
	if user["phone"] != "+254717000001" {
		t.Fatalf("stored login phone = %v, want +254717000001", user["phone"])
	}
	if got := strings.Join(toStrings(user["permissions"]), ","); got != strings.Join(sorted(rbac.PermissionsFor(domain.RoleOwner)), ",") {
		t.Fatalf("owner permissions at sign-up = %s", got)
	}

	// The same login, typed three other ways.
	for _, typed := range []string{"+254717000001", "717000001", "254 717 000 001"} {
		c.mustOK("POST", "/auth/login", "", map[string]any{"phone": typed, "password": "owner-pass-1"})
	}
	if status, _ := c.do("POST", "/auth/register-business", "", map[string]any{
		"business_name": "Copy", "name": "Someone", "phone": "+254717000001", "password": "whatever-1",
	}); status != http.StatusConflict {
		t.Fatalf("registering the same number in another form = %d, want 409", status)
	}
	if status, out := c.do("POST", "/auth/register-business", "", map[string]any{
		"business_name": "Copy", "name": "Someone", "phone": "0712 34A 678", "password": "whatever-1",
	}); status != http.StatusUnprocessableEntity {
		t.Fatalf("registering an unreadable number = %d %v, want 422", status, out)
	}

	code := data(c.mustOK("POST", "/auth/invite", owner, nil))["code"].(string)
	joined := data(c.mustOK("POST", "/auth/join", "", map[string]any{
		"code": code, "name": "Staff", "phone": "0717000002", "password": "staff-pass-1",
	}))
	staff := joined["token"].(string)
	staffID := joined["user"].(map[string]any)["id"].(string)
	me := data(c.mustOK("GET", "/users/me", staff, nil))
	if got := strings.Join(toStrings(me["permissions"]), ","); got != strings.Join(sorted(rbac.PermissionsFor(domain.RoleStaff)), ",") {
		t.Fatalf("staff permissions from /users/me = %s", got)
	}

	// Customers: REST and sync store one form, and see one number as one.
	rest := data(c.mustOK("POST", "/customers", staff, map[string]any{"name": "Wanjiku", "phone": "0722 111 222"}))
	if rest["phone"] != "+254722111222" {
		t.Fatalf("REST customer phone = %v", rest["phone"])
	}
	if status, _ := c.do("POST", "/customers", staff, map[string]any{"name": "Copy", "phone": "+254722111222"}); status != http.StatusConflict {
		t.Fatalf("the same customer number in another form = %d, want 409", status)
	}
	now := time.Now().UTC().Format(time.RFC3339)
	push := data(c.mustOK("POST", "/sync/push", staff, map[string]any{
		"operation_id": uuid.NewString(),
		"customers": []map[string]any{
			{"id": uuid.NewString(), "name": "Otieno", "phone": "0733 444 555", "created_by": staffID, "created_at": now, "updated_at": now},
			{"id": uuid.NewString(), "name": "Bad", "phone": "call me", "created_by": staffID, "created_at": now, "updated_at": now},
		},
	}))
	conflicts := push["conflicts"].([]any)
	if push["applied_customers"].(float64) != 1 || len(conflicts) != 1 ||
		conflicts[0].(map[string]any)["field"] != "phone" {
		t.Fatalf("sync push = %v, want Otieno applied and Bad refused on phone", push)
	}
	pulled := data(c.mustOK("GET", "/sync/pull?cursor=0", owner, nil))
	found := false
	for _, row := range pulled["customers"].([]any) {
		if r := row.(map[string]any); r["name"] == "Otieno" {
			found = r["phone"] == "+254733444555"
		}
	}
	if !found {
		t.Fatalf("Otieno's phone was not stored as +254733444555: %v", pulled["customers"])
	}
}

func toStrings(v any) []string {
	var out []string
	for _, s := range v.([]any) {
		out = append(out, s.(string))
	}
	return out
}

func sorted(s []string) []string {
	out := slices.Clone(s)
	slices.Sort(out)
	return out
}
