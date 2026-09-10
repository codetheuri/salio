package console_test

import (
	"context"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/id"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"salio/server-v2/internal/console"
	"salio/server-v2/internal/domain"
	"salio/server-v2/internal/money"
	"salio/server-v2/internal/testsupport"
)

const testPassword = "correct-horse-battery-staple"

// fixture is a platform with two businesses in it. Two, always: almost every
// question worth asking of the console is "does it see across businesses, and
// does it add them up correctly", and one business cannot answer either.
type fixture struct {
	db  *gorm.DB
	svc *console.Service
	ctx context.Context

	admin domain.SuperAdmin
	alpha uuid.UUID // "Alpha Agrovet"
	beta  uuid.UUID // "Beta Kiosk"
}

func newFixture(t *testing.T) *fixture {
	t.Helper()
	db := testsupport.Connect(t)

	f := &fixture{
		db:  db,
		svc: console.NewService(console.NewRepository(db)),
		ctx: context.Background(),
	}

	f.admin = f.newAdmin(t, "Operator", "ops@salio.co.ke")
	f.alpha = f.newBusiness(t, "Alpha Agrovet", "Wanjiku", "0712000001")
	f.beta = f.newBusiness(t, "Beta Kiosk", "Otieno", "0712000002")
	return f
}

func (f *fixture) newAdmin(t *testing.T, name, email string) domain.SuperAdmin {
	t.Helper()
	admin, err := f.svc.CreateAdmin(f.ctx, name, email, testPassword)
	if err != nil {
		t.Fatalf("creating admin: %v", err)
	}
	return *admin
}

// newBusiness creates a business and its owner.
//
// tenant.Unscoped is called fresh for each statement rather than stored in a
// variable. Its return shares one gorm.Statement with the receiver, so a second
// Create built on the first inherits the first's model — which has already
// written a User's values into the businesses table once in this codebase.
func (f *fixture) newBusiness(t *testing.T, name, owner, phone string) uuid.UUID {
	t.Helper()

	b := domain.Business{ID: id.New(), Name: name}
	if err := tenant.Unscoped(f.db).Create(&b).Error; err != nil {
		t.Fatalf("creating business: %v", err)
	}

	u := domain.User{
		ID: id.New(), BusinessID: b.ID, Name: owner, Phone: phone,
		PasswordHash: "x", Role: domain.RoleOwner, IsActive: true,
	}
	if err := tenant.Unscoped(f.db).Create(&u).Error; err != nil {
		t.Fatalf("creating owner: %v", err)
	}
	return b.ID
}

func (f *fixture) newUser(t *testing.T, businessID uuid.UUID, name, phone string, role domain.Role, active bool) uuid.UUID {
	t.Helper()
	u := domain.User{
		ID: id.New(), BusinessID: businessID, Name: name, Phone: phone,
		PasswordHash: "x", Role: role, IsActive: true,
	}
	if err := tenant.Unscoped(f.db).Create(&u).Error; err != nil {
		t.Fatalf("creating user: %v", err)
	}

	// Deactivation is a second statement rather than IsActive:false on the
	// insert. GORM omits a zero-valued field whose column has a default, so
	// false on a `default:true` column is silently written as true — and no
	// production path creates an already-deactivated user anyway.
	if !active {
		if err := tenant.Unscoped(f.db).Model(&domain.User{}).
			Where("id = ?", u.ID).Update("is_active", false).Error; err != nil {
			t.Fatalf("deactivating user: %v", err)
		}
	}
	return u.ID
}

func (f *fixture) newCustomer(t *testing.T, businessID uuid.UUID, name string) uuid.UUID {
	t.Helper()

	var creator domain.User
	if err := tenant.Unscoped(f.db).Where("business_id = ?", businessID).First(&creator).Error; err != nil {
		t.Fatalf("finding a creator: %v", err)
	}

	c := domain.Customer{ID: id.New(), BusinessID: businessID, Name: name, CreatedBy: creator.ID}
	if err := tenant.Unscoped(f.db).Create(&c).Error; err != nil {
		t.Fatalf("creating customer: %v", err)
	}
	return c.ID
}

func (f *fixture) entry(t *testing.T, businessID, customerID uuid.UUID, typ domain.TransactionType, amount string) {
	t.Helper()

	amt, err := money.Parse(amount)
	if err != nil {
		t.Fatalf("parsing %q: %v", amount, err)
	}

	var creator domain.User
	if err := tenant.Unscoped(f.db).Where("business_id = ?", businessID).First(&creator).Error; err != nil {
		t.Fatalf("finding a creator: %v", err)
	}

	tx := domain.Transaction{
		ID: id.New(), BusinessID: businessID, CustomerID: customerID, UserID: creator.ID,
		Type: typ, Amount: amt, TransactionDate: time.Now().UTC(),
	}
	if err := tenant.Unscoped(f.db).Create(&tx).Error; err != nil {
		t.Fatalf("creating transaction: %v", err)
	}
}

// --- Authentication ---

func TestAuthenticate_AcceptsTheRightPassword(t *testing.T) {
	f := newFixture(t)

	admin, err := f.svc.Authenticate(f.ctx, "ops@salio.co.ke", testPassword)
	if err != nil {
		t.Fatalf("authenticate: %v", err)
	}
	if admin.ID != f.admin.ID {
		t.Fatalf("authenticated as %s, want %s", admin.ID, f.admin.ID)
	}
}

func TestAuthenticate_IsCaseInsensitiveOnEmail(t *testing.T) {
	f := newFixture(t)

	// Someone typing their own email into a phone keyboard gets a capital first
	// letter for free. Refusing that is a support ticket, not a security measure.
	if _, err := f.svc.Authenticate(f.ctx, "Ops@Salio.co.ke", testPassword); err != nil {
		t.Fatalf("mixed-case email was rejected: %v", err)
	}
}

func TestAuthenticate_RejectsAWrongPasswordAndAnUnknownEmail(t *testing.T) {
	f := newFixture(t)

	for _, tc := range []struct{ name, email, password string }{
		{"wrong password", "ops@salio.co.ke", "not-the-password"},
		{"unknown email", "nobody@salio.co.ke", testPassword},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := f.svc.Authenticate(f.ctx, tc.email, tc.password); err != console.ErrInvalidLogin {
				t.Fatalf("got %v, want ErrInvalidLogin — the two cases must be indistinguishable", err)
			}
		})
	}
}

// --- Dashboard ---

func TestSummary_CountsEveryBusinessNotJustOne(t *testing.T) {
	f := newFixture(t)

	alphaCustomer := f.newCustomer(t, f.alpha, "Mama Mboga")
	betaCustomer := f.newCustomer(t, f.beta, "Juma")

	f.entry(t, f.alpha, alphaCustomer, domain.TypeDebt, "1000.00")
	f.entry(t, f.alpha, alphaCustomer, domain.TypePayment, "250.50")
	f.entry(t, f.beta, betaCustomer, domain.TypeDebt, "400.00")

	summary, _, err := f.svc.Dashboard(f.ctx)
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}

	if summary.TotalBusinesses != 2 {
		t.Errorf("businesses = %d, want 2", summary.TotalBusinesses)
	}
	if summary.TotalUsers != 2 {
		t.Errorf("users = %d, want 2", summary.TotalUsers)
	}
	if summary.TotalCustomers != 2 {
		t.Errorf("customers = %d, want 2", summary.TotalCustomers)
	}
	if summary.TotalTransactions != 3 {
		t.Errorf("transactions = %d, want 3", summary.TotalTransactions)
	}

	// 1000.00 + 400.00 issued, 250.50 collected, so 1149.50 outstanding — and
	// exactly that, to the cent. The whole reason amounts are integer minor
	// units rather than float64 is that this assertion has to hold.
	if got, want := summary.TotalDebt.String(), "1400.00"; got != want {
		t.Errorf("total debt = %s, want %s", got, want)
	}
	if got, want := summary.TotalPayments.String(), "250.50"; got != want {
		t.Errorf("total payments = %s, want %s", got, want)
	}
	if got, want := summary.OutstandingBalance.String(), "1149.50"; got != want {
		t.Errorf("outstanding = %s, want %s", got, want)
	}
}

func TestSummary_IgnoresDeletedRows(t *testing.T) {
	f := newFixture(t)

	customer := f.newCustomer(t, f.alpha, "Mama Mboga")
	f.entry(t, f.alpha, customer, domain.TypeDebt, "1000.00")
	f.entry(t, f.alpha, customer, domain.TypeDebt, "500.00")

	// A voided entry is a tombstone, not a deletion — it still exists so the
	// void can reach other devices. It must not still count.
	if err := tenant.Unscoped(f.db).Model(&domain.Transaction{}).
		Where("business_id = ? AND amount = 500.00", f.alpha).
		Update("is_deleted", true).Error; err != nil {
		t.Fatalf("voiding: %v", err)
	}

	summary, _, err := f.svc.Dashboard(f.ctx)
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}
	if got, want := summary.TotalDebt.String(), "1000.00"; got != want {
		t.Errorf("total debt = %s, want %s — a voided entry was still counted", got, want)
	}
	if summary.TotalTransactions != 1 {
		t.Errorf("transactions = %d, want 1", summary.TotalTransactions)
	}
}

func TestSummary_CountsDeactivatedUsersSeparately(t *testing.T) {
	f := newFixture(t)
	f.newUser(t, f.alpha, "Left Last Month", "0712000009", domain.RoleStaff, false)

	summary, _, err := f.svc.Dashboard(f.ctx)
	if err != nil {
		t.Fatalf("dashboard: %v", err)
	}
	if summary.TotalUsers != 3 {
		t.Errorf("users = %d, want 3", summary.TotalUsers)
	}
	if summary.InactiveUsers != 1 {
		t.Errorf("inactive = %d, want 1", summary.InactiveUsers)
	}
}

// --- Businesses ---

func TestBusinesses_ListsEveryBusinessWithItsOwner(t *testing.T) {
	f := newFixture(t)

	rows, page, err := f.svc.Businesses(f.ctx, 1, 10)
	if err != nil {
		t.Fatalf("businesses: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("got %d businesses, want 2", len(rows))
	}
	if page.Total != 2 {
		t.Errorf("total = %d, want 2", page.Total)
	}

	byName := map[string]console.BusinessRow{}
	for _, r := range rows {
		byName[r.Name] = r
	}
	if got := byName["Alpha Agrovet"].OwnerName; got != "Wanjiku" {
		t.Errorf("Alpha's owner = %q, want Wanjiku", got)
	}
	if got := byName["Beta Kiosk"].OwnerPhone; got != "0712000002" {
		t.Errorf("Beta's owner phone = %q, want 0712000002", got)
	}
}

func TestBusinesses_StillListsABusinessWhoseOwnerIsDeactivated(t *testing.T) {
	f := newFixture(t)

	// v1 joined users on role = 'owner' with an inner join, so this made the
	// business disappear from the console altogether — the one an operator is
	// most likely to be looking for, since something has clearly gone wrong with
	// it. The LATERAL join keeps the row and prefers an active owner if there is
	// one.
	if err := tenant.Unscoped(f.db).Model(&domain.User{}).
		Where("business_id = ?", f.beta).Update("is_active", false).Error; err != nil {
		t.Fatalf("deactivating: %v", err)
	}

	rows, _, err := f.svc.Businesses(f.ctx, 1, 10)
	if err != nil {
		t.Fatalf("businesses: %v", err)
	}
	if len(rows) != 2 {
		t.Fatalf("got %d businesses, want 2 — a deactivated owner hid one", len(rows))
	}
}

func TestBusinesses_DoesNotDuplicateABusinessWithTwoOwners(t *testing.T) {
	f := newFixture(t)
	f.newUser(t, f.alpha, "Second Owner", "0712000010", domain.RoleOwner, true)

	rows, _, err := f.svc.Businesses(f.ctx, 1, 10)
	if err != nil {
		t.Fatalf("businesses: %v", err)
	}

	// v1's inner join produced one row per owner, so a business with a second
	// owner was listed twice and counted twice in "showing N of M".
	seen := 0
	for _, r := range rows {
		if r.ID == f.alpha {
			seen++
		}
	}
	if seen != 1 {
		t.Fatalf("Alpha appeared %d times, want 1", seen)
	}
}

func TestBusiness_ReportsItsOwnLedgerAndNobodyElses(t *testing.T) {
	f := newFixture(t)

	alphaCustomer := f.newCustomer(t, f.alpha, "Mama Mboga")
	betaCustomer := f.newCustomer(t, f.beta, "Juma")

	f.entry(t, f.alpha, alphaCustomer, domain.TypeDebt, "1000.00")
	f.entry(t, f.alpha, alphaCustomer, domain.TypePayment, "300.00")
	f.entry(t, f.beta, betaCustomer, domain.TypeDebt, "9999.00")

	detail, users, err := f.svc.Business(f.ctx, f.alpha)
	if err != nil {
		t.Fatalf("business: %v", err)
	}

	if got, want := detail.TotalDebt.String(), "1000.00"; got != want {
		t.Errorf("debt = %s, want %s — Beta's ledger leaked in", got, want)
	}
	if got, want := detail.TotalPayments.String(), "300.00"; got != want {
		t.Errorf("payments = %s, want %s", got, want)
	}
	if got, want := detail.OutstandingBalance.String(), "700.00"; got != want {
		t.Errorf("outstanding = %s, want %s", got, want)
	}
	if detail.TotalTransactions != 2 {
		t.Errorf("transactions = %d, want 2", detail.TotalTransactions)
	}
	if detail.CustomerCount != 1 {
		t.Errorf("customers = %d, want 1", detail.CustomerCount)
	}
	if len(users) != 1 {
		t.Errorf("users = %d, want 1", len(users))
	}
}

func TestBusiness_WithNoActivityReportsNeverRatherThanYearOne(t *testing.T) {
	f := newFixture(t)

	detail, _, err := f.svc.Business(f.ctx, f.alpha)
	if err != nil {
		t.Fatalf("business: %v", err)
	}
	if detail.LastActivityAt != nil {
		t.Errorf("last activity = %v, want nil for a business that has recorded nothing", detail.LastActivityAt)
	}
	if got, want := detail.OutstandingBalance.String(), "0.00"; got != want {
		t.Errorf("outstanding = %s, want %s", got, want)
	}
}

func TestBusiness_UnknownIDIsNotFound(t *testing.T) {
	f := newFixture(t)

	if _, _, err := f.svc.Business(f.ctx, id.New()); err != console.ErrNotFound {
		t.Fatalf("got %v, want ErrNotFound", err)
	}
}

// --- Users ---

func TestUsers_ListsAcrossBusinessesWithTheirBusinessName(t *testing.T) {
	f := newFixture(t)
	f.newUser(t, f.beta, "Staffer", "0712000011", domain.RoleStaff, true)

	rows, page, err := f.svc.Users(f.ctx, 1, 10)
	if err != nil {
		t.Fatalf("users: %v", err)
	}
	if len(rows) != 3 || page.Total != 3 {
		t.Fatalf("got %d rows and total %d, want 3 and 3", len(rows), page.Total)
	}

	for _, r := range rows {
		if r.BusinessName == "" {
			t.Errorf("user %s has no business name", r.Name)
		}
	}
}

func TestUsers_PaginatesWithoutLosingOrRepeatingAnyone(t *testing.T) {
	f := newFixture(t)
	for i := 0; i < 8; i++ {
		f.newUser(t, f.alpha, "Staff", "07120001"+string(rune('0'+i))+"0", domain.RoleStaff, true)
	}

	seen := map[uuid.UUID]bool{}
	for page := 1; page <= 2; page++ {
		rows, meta, err := f.svc.Users(f.ctx, page, 5)
		if err != nil {
			t.Fatalf("users page %d: %v", page, err)
		}
		if meta.Total != 10 {
			t.Fatalf("total = %d, want 10", meta.Total)
		}
		for _, r := range rows {
			if seen[r.ID] {
				t.Fatalf("user %s appeared on two pages", r.ID)
			}
			seen[r.ID] = true
		}
	}
	if len(seen) != 10 {
		t.Fatalf("saw %d users across both pages, want 10", len(seen))
	}
}

func TestPagination_RefusesAnUnreasonablePageSize(t *testing.T) {
	f := newFixture(t)

	// ?limit=100000 is a query string, which means it is whatever a visitor
	// types. Honouring it would let anyone ask the database for every row in the
	// system in one statement.
	_, page, err := f.svc.Users(f.ctx, 1, 100000)
	if err != nil {
		t.Fatalf("users: %v", err)
	}
	if page.Limit != 10 {
		t.Fatalf("limit = %d, want the default of 10", page.Limit)
	}
}

// --- The HTTP surface ---

// newServer mounts the console the way cmd/api does, so these exercise the real
// middleware chain rather than calling handlers directly.
func newServer(t *testing.T, f *fixture) *httptest.Server {
	t.Helper()

	r := chi.NewRouter()
	if err := console.Mount(r, console.Options{
		DB:     f.db,
		Logger: logger.NewTextLogger("error"),
		Secure: false, // an httptest server is plain HTTP; true drops the cookie
	}); err != nil {
		t.Fatalf("mounting the console: %v", err)
	}

	srv := httptest.NewServer(r)
	t.Cleanup(srv.Close)
	return srv
}

// newClient returns a client that keeps cookies and does not follow redirects,
// so a test can assert on the redirect itself.
func newClient(t *testing.T) *http.Client {
	t.Helper()

	jar, err := cookiejar.New(nil)
	if err != nil {
		t.Fatalf("cookie jar: %v", err)
	}
	return &http.Client{
		Jar: jar,
		// Redirects are the assertion in several of these tests, so following
		// them would hide exactly what is being checked.
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}
}

func TestHTTP_MountingParsesEveryTemplate(t *testing.T) {
	f := newFixture(t)

	// view.New parses every page at construction, so Mount returning nil is the
	// assertion: a template with a typo in it stops the process starting rather
	// than 500ing at whichever page someone opens first, which is what v1 did by
	// validating login.html alone.
	newServer(t, f)
}

func TestHTTP_ProtectedPagesRedirectToLogin(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	for _, path := range []string{"/console/dashboard", "/console/businesses", "/console/users"} {
		res, err := client.Get(srv.URL + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		res.Body.Close()

		if res.StatusCode != http.StatusSeeOther {
			t.Errorf("GET %s = %d, want 303", path, res.StatusCode)
		}
		if got := res.Header.Get("Location"); got != "/console/login" {
			t.Errorf("GET %s redirected to %q, want /console/login", path, got)
		}
	}
}

func TestHTTP_SignInThenReadThenSignOut(t *testing.T) {
	f := newFixture(t)
	customer := f.newCustomer(t, f.alpha, "Mama Mboga")
	f.entry(t, f.alpha, customer, domain.TypeDebt, "1500.50")

	srv := newServer(t, f)
	client := newClient(t)

	res := postForm(t, client, srv.URL+"/console/login", url.Values{
		"email":    {"ops@salio.co.ke"},
		"password": {testPassword},
	})
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/console/dashboard" {
		t.Fatalf("login = %d to %q, want 303 to /console/dashboard", res.StatusCode, res.Header.Get("Location"))
	}

	body := getBody(t, client, srv.URL+"/console/dashboard", http.StatusOK)
	for _, want := range []string{"Platform Overview", "Alpha Agrovet", "1,500.50"} {
		if !strings.Contains(body, want) {
			t.Errorf("the dashboard does not mention %q", want)
		}
	}

	body = getBody(t, client, srv.URL+"/console/businesses/"+f.alpha.String(), http.StatusOK)
	if !strings.Contains(body, "Wanjiku") {
		t.Error("the business page does not name the owner")
	}

	res = postForm(t, client, srv.URL+"/console/logout", nil)
	if res.StatusCode != http.StatusSeeOther || res.Header.Get("Location") != "/console/login" {
		t.Fatalf("logout = %d to %q, want 303 to /console/login", res.StatusCode, res.Header.Get("Location"))
	}

	// The session row is gone, not merely the cookie: signing out has to end
	// access for anyone who copied the token, which is the entire reason the
	// console uses database-backed sessions instead of a JWT.
	res, err := client.Get(srv.URL + "/console/dashboard")
	if err != nil {
		t.Fatalf("GET after logout: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusSeeOther {
		t.Fatalf("after logout the dashboard returned %d, want a redirect to login", res.StatusCode)
	}
}

func TestHTTP_LoginPageDoesNotLoopOnAStaleCookie(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	res := postForm(t, client, srv.URL+"/console/login", url.Values{
		"email": {"ops@salio.co.ke"}, "password": {testPassword},
	})
	if res.StatusCode != http.StatusSeeOther {
		t.Fatalf("login = %d, want 303", res.StatusCode)
	}

	// Delete the session behind the browser's back — an operator revoked, or an
	// expired row swept. The cookie is still in the jar.
	if err := f.db.Exec("DELETE FROM sessions").Error; err != nil {
		t.Fatalf("clearing sessions: %v", err)
	}

	// v1 redirected whenever the cookie merely existed, so this request bounced
	// /console/login → /console/dashboard → /console/login forever, and the only
	// way out was clearing site data.
	body := getBody(t, client, srv.URL+"/console/login", http.StatusOK)
	if !strings.Contains(body, "Sign in to Console") {
		t.Fatal("the login form was not rendered for a visitor holding a dead cookie")
	}
}

func TestHTTP_SessionOutlivingItsAdminIsRefused(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	postForm(t, client, srv.URL+"/console/login", url.Values{
		"email": {"ops@salio.co.ke"}, "password": {testPassword},
	})
	getBody(t, client, srv.URL+"/console/dashboard", http.StatusOK)

	if err := f.db.Exec("DELETE FROM super_admins WHERE id = ?", f.admin.ID).Error; err != nil {
		t.Fatalf("deleting the admin: %v", err)
	}

	// Removing an operator must end their access now, not whenever their session
	// happened to expire.
	res, err := client.Get(srv.URL + "/console/dashboard")
	if err != nil {
		t.Fatalf("GET: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusSeeOther {
		t.Fatalf("a session for a deleted admin returned %d, want a redirect to login", res.StatusCode)
	}
}

func TestHTTP_BadCredentialsAnswer401AndNotAServerError(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	res := postForm(t, client, srv.URL+"/console/login", url.Values{
		"email": {"ops@salio.co.ke"}, "password": {"wrong"},
	})
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("bad login = %d, want 401", res.StatusCode)
	}
}

func TestHTTP_AnUnknownBusinessIs404NotACrash(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	postForm(t, client, srv.URL+"/console/login", url.Values{
		"email": {"ops@salio.co.ke"}, "password": {testPassword},
	})

	for _, path := range []string{
		"/console/businesses/" + id.New().String(),
		"/console/businesses/not-a-uuid",
	} {
		body := getBody(t, client, srv.URL+path, http.StatusNotFound)
		if !strings.Contains(body, "No such business") {
			t.Errorf("GET %s did not render the not-found page", path)
		}
	}
}

func TestHTTP_StaticAssetsAreServedWithoutASession(t *testing.T) {
	f := newFixture(t)
	srv := newServer(t, f)
	client := newClient(t)

	// An unstyled login page is a confusing way to be told you are signed out,
	// and a stylesheet is not a secret.
	res, err := client.Get(srv.URL + "/console/static/css/console.css")
	if err != nil {
		t.Fatalf("GET the stylesheet: %v", err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("the stylesheet returned %d, want 200", res.StatusCode)
	}
}

// --- Helpers ---

func postForm(t *testing.T, client *http.Client, url string, form url.Values) *http.Response {
	t.Helper()
	res, err := client.PostForm(url, form)
	if err != nil {
		t.Fatalf("POST %s: %v", url, err)
	}
	res.Body.Close()
	return res
}

func getBody(t *testing.T, client *http.Client, url string, wantStatus int) string {
	t.Helper()
	res, err := client.Get(url)
	if err != nil {
		t.Fatalf("GET %s: %v", url, err)
	}
	defer res.Body.Close()

	body, err := io.ReadAll(res.Body)
	if err != nil {
		t.Fatalf("reading %s: %v", url, err)
	}
	if res.StatusCode != wantStatus {
		t.Fatalf("GET %s = %d, want %d", url, res.StatusCode, wantStatus)
	}
	return string(body)
}
