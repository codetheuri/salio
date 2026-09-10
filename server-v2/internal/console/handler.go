package console

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/session"
	"github.com/codetheuri/tusk/v2/pkg/view"
	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

// Paths the console redirects between. Named because a typo in a redirect string
// produces a loop rather than an error.
const (
	loginPath     = "/console/login"
	dashboardPath = "/console/dashboard"
	businessPath  = "/console/businesses"
)

type Handler struct {
	svc      *Service
	views    *view.Engine
	sessions *session.Manager
	log      logger.Logger
}

func NewHandler(svc *Service, views *view.Engine, sessions *session.Manager, log logger.Logger) *Handler {
	return &Handler{svc: svc, views: views, sessions: sessions, log: log}
}

// adminKey carries the resolved operator. Unexported struct key, so nothing
// outside this package can plant a value under it.
type adminKey struct{}

func adminFrom(ctx context.Context) *domain.SuperAdmin {
	admin, _ := ctx.Value(adminKey{}).(*domain.SuperAdmin)
	return admin
}

// RequireAdmin resolves a session to a live super_admin.
//
// Mounted inside session.Manager.Require, which has already established that a
// valid session exists. This second step asks whether its subject still does:
// a session outliving a deleted operator would otherwise keep working until its
// own expiry, which is the wrong answer to "remove that person's access".
func (h *Handler) RequireAdmin(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		sess, ok := session.FromContext(r.Context())
		if !ok {
			http.Redirect(w, r, loginPath, http.StatusSeeOther)
			return
		}

		admin, err := h.svc.Admin(r.Context(), sess.SubjectID)
		if err != nil {
			if !errors.Is(err, ErrNotFound) {
				h.log.Error("console: resolving the session subject", err)
			}
			// The session names someone who is gone. End it rather than leaving
			// a cookie that will fail this check again on every request.
			_ = h.sessions.Destroy(w, r)
			http.Redirect(w, r, loginPath, http.StatusSeeOther)
			return
		}

		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), adminKey{}, admin)))
	})
}

// render writes a page, or a 500 if it cannot.
//
// view.Engine buffers, so a template that fails halfway has written nothing to
// the response yet and this can still send a different status — the thing v1's
// render() could not do, having already committed to 200.
func (h *Handler) render(w http.ResponseWriter, status int, page string, data map[string]any) {
	if err := h.views.Render(w, status, page, data); err != nil {
		h.log.Error("console: rendering a page", err, "page", page)
		http.Error(w, "Something went wrong rendering this page.", http.StatusInternalServerError)
	}
}

// fail renders the error page. Used for the failures a reader can do something
// about — a business that does not exist — and for the ones they cannot.
func (h *Handler) fail(w http.ResponseWriter, r *http.Request, status int, title, detail string) {
	h.render(w, status, "error.html", map[string]any{
		"Admin": adminFrom(r.Context()), "ActivePage": "",
		"Status": status, "Title": title, "Detail": detail,
	})
}

// --- Sign in and out ---

// ShowLogin renders the login form.
func (h *Handler) ShowLogin(w http.ResponseWriter, r *http.Request) {
	// Asks whether a *valid* session exists, not whether a cookie is present.
	// v1 tested the cookie, so a stale one bounced the visitor between the login
	// page and the dashboard with no way out but clearing site data.
	if _, ok := session.FromContext(r.Context()); ok {
		http.Redirect(w, r, dashboardPath, http.StatusSeeOther)
		return
	}
	h.render(w, http.StatusOK, "login.html", map[string]any{"Year": time.Now().Year()})
}

// HandleLogin verifies credentials and starts a session.
func (h *Handler) HandleLogin(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		h.fail(w, r, http.StatusBadRequest, "Bad request", "That form could not be read.")
		return
	}
	email, password := r.FormValue("email"), r.FormValue("password")

	// 401, not 200: a failed sign-in is a failed sign-in to anything reading the
	// status, including logs and any rate limiter watching for a burst of them.
	reject := func(status int, msg string) {
		h.render(w, status, "login.html", map[string]any{
			"Year": time.Now().Year(), "Error": msg, "Email": email,
		})
	}

	admin, err := h.svc.Authenticate(r.Context(), email, password)
	if err != nil {
		if errors.Is(err, ErrInvalidLogin) {
			reject(http.StatusUnauthorized, "Incorrect email or password.")
			return
		}
		h.log.Error("console: authenticating", err)
		reject(http.StatusInternalServerError, "Something went wrong. Please try again.")
		return
	}

	if _, err := h.sessions.Start(w, r, admin.ID); err != nil {
		h.log.Error("console: starting a session", err, "admin_id", admin.ID)
		reject(http.StatusInternalServerError, "Sign-in failed. Please try again.")
		return
	}

	http.Redirect(w, r, dashboardPath, http.StatusSeeOther)
}

// HandleLogout ends the session and clears the cookie.
func (h *Handler) HandleLogout(w http.ResponseWriter, r *http.Request) {
	if err := h.sessions.Destroy(w, r); err != nil {
		// The cookie is cleared either way, so the operator is signed out of
		// this browser. Worth logging: a row that would not delete is a database
		// problem, not a user-facing one.
		h.log.Error("console: destroying a session", err)
	}
	http.Redirect(w, r, loginPath, http.StatusSeeOther)
}

// --- Pages ---

func (h *Handler) ShowDashboard(w http.ResponseWriter, r *http.Request) {
	summary, businesses, err := h.svc.Dashboard(r.Context())
	if err != nil {
		h.log.Error("console: building the dashboard", err)
		h.fail(w, r, http.StatusInternalServerError, "Dashboard unavailable",
			"The platform summary could not be loaded.")
		return
	}

	h.render(w, http.StatusOK, "dashboard.html", map[string]any{
		"Admin": adminFrom(r.Context()), "ActivePage": "dashboard",
		"Summary": summary, "Businesses": businesses,
	})
}

func (h *Handler) ShowBusinesses(w http.ResponseWriter, r *http.Request) {
	rows, page, err := h.svc.Businesses(r.Context(), intParam(r, "page", 1), intParam(r, "limit", defaultPageSize))
	if err != nil {
		h.log.Error("console: listing businesses", err)
		h.fail(w, r, http.StatusInternalServerError, "Businesses unavailable",
			"The business list could not be loaded.")
		return
	}

	h.render(w, http.StatusOK, "businesses.html", map[string]any{
		"Admin": adminFrom(r.Context()), "ActivePage": "businesses",
		"Businesses": rows, "Page": page, "PageSizes": PageSizes(),
	})
}

func (h *Handler) ShowBusiness(w http.ResponseWriter, r *http.Request) {
	businessID, err := uuid.Parse(chi.URLParam(r, "id"))
	if err != nil {
		h.fail(w, r, http.StatusNotFound, "No such business", "That is not a valid business identifier.")
		return
	}

	detail, users, err := h.svc.Business(r.Context(), businessID)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			h.fail(w, r, http.StatusNotFound, "No such business",
				"That business does not exist, or has been removed.")
			return
		}
		h.log.Error("console: loading a business", err, "business_id", businessID)
		h.fail(w, r, http.StatusInternalServerError, "Business unavailable",
			"That business could not be loaded.")
		return
	}

	h.render(w, http.StatusOK, "business_details.html", map[string]any{
		// Businesses stays highlighted in the sidebar: a detail page is a place
		// within that section, not a section of its own.
		"Admin": adminFrom(r.Context()), "ActivePage": "businesses",
		"Details": detail, "Users": users,
	})
}

func (h *Handler) ShowUsers(w http.ResponseWriter, r *http.Request) {
	rows, page, err := h.svc.Users(r.Context(), intParam(r, "page", 1), intParam(r, "limit", defaultPageSize))
	if err != nil {
		h.log.Error("console: listing users", err)
		h.fail(w, r, http.StatusInternalServerError, "Users unavailable",
			"The user list could not be loaded.")
		return
	}

	h.render(w, http.StatusOK, "users.html", map[string]any{
		"Admin": adminFrom(r.Context()), "ActivePage": "users",
		"Users": rows, "Page": page, "PageSizes": PageSizes(),
	})
}

// intParam reads a positive integer from the query string, falling back to a
// default. A malformed value is the default rather than an error: a person who
// hand-edits ?page= in the address bar should get a page, not a stack trace.
func intParam(r *http.Request, name string, fallback int) int {
	v, err := strconv.Atoi(r.URL.Query().Get(name))
	if err != nil || v < 1 {
		return fallback
	}
	return v
}
