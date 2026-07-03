package console

import (
	"errors"
	"html/template"
	"log/slog"
	"net/http"
	"path/filepath"
	"time"

	"salio/server/internal/models"
	"salio/server/internal/repository"
)

// Handler handles all HTTP requests for the /console/* routes.
type Handler struct {
	repo         *repository.ConsoleRepository
	templatesDir string
	isProduction bool
}

// NewHandler creates a new console Handler and validates that templates can be parsed.
// In production, templates are cached. In development they reload on each request
// so you can edit HTML without restarting the server.
func NewHandler(repo *repository.ConsoleRepository, templatesDir string, isProduction bool) (*Handler, error) {
	h := &Handler{
		repo:         repo,
		templatesDir: templatesDir,
		isProduction: isProduction,
	}

	// Validate templates parse correctly at startup
	if _, err := h.parseTemplates("login.html"); err != nil {
		return nil, err
	}
	return h, nil
}

// parseTemplates parses base.html + layout.html + the given page file together.
// Go templates work by defining named blocks. All templates in a set can reference
// each other's {{define}} blocks, so we always include base and layout.
func (h *Handler) parseTemplates(pageFile string) (*template.Template, error) {
	base := filepath.Join(h.templatesDir, "console", "base.html")
	layout := filepath.Join(h.templatesDir, "console", "layout.html")
	page := filepath.Join(h.templatesDir, "console", pageFile)

	tmpl, err := template.ParseFiles(base, layout, page)
	if err != nil {
		return nil, err
	}
	return tmpl, nil
}

// render executes the "base" template (which pulls in page content via {{template "content" .}}).
// In development, templates are re-parsed on every request so HTML edits are live.
// In production, we would cache the parsed templates — add that optimisation later.
func (h *Handler) render(w http.ResponseWriter, r *http.Request, pageFile string, data any) {
	tmpl, err := h.parseTemplates(pageFile)
	if err != nil {
		slog.Error("Template parse error", "file", pageFile, "error", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")

	// Execute the "base" template — it's the root that calls {{template "content" .}}
	if err := tmpl.ExecuteTemplate(w, "base", data); err != nil {
		slog.Error("Template render error", "file", pageFile, "error", err)
	}
}

// adminFromCtx safely extracts the super admin from the request context.
func adminFromCtx(r *http.Request) *models.SuperAdmin {
	admin, _ := r.Context().Value(contextKeyAdmin).(*models.SuperAdmin)
	return admin
}

// --- Login / Logout ---

// ShowLogin renders the login page (GET /console/login).
func (h *Handler) ShowLogin(w http.ResponseWriter, r *http.Request) {
	if _, err := r.Cookie(sessionCookieName); err == nil {
		http.Redirect(w, r, "/console/dashboard", http.StatusSeeOther)
		return
	}
	h.render(w, r, "login.html", map[string]any{
		"Year": time.Now().Year(),
	})
}

// HandleLogin processes the login form (POST /console/login).
func (h *Handler) HandleLogin(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, "Invalid form", http.StatusBadRequest)
		return
	}

	email := r.FormValue("email")
	password := r.FormValue("password")

	renderError := func(msg string) {
		h.render(w, r, "login.html", map[string]any{
			"Year":  time.Now().Year(),
			"Error": msg,
			"Email": email,
		})
	}

	admin, err := h.repo.GetSuperAdminByEmail(r.Context(), email)
	if err != nil {
		if errors.Is(err, repository.ErrNotFound) {
			renderError("Invalid email or password.")
			return
		}
		slog.Error("Login: DB error", "error", err)
		renderError("Something went wrong. Please try again.")
		return
	}

	if !repository.VerifySuperAdminPassword(admin.PasswordHash, password) {
		renderError("Invalid email or password.")
		return
	}

	session, err := h.repo.CreateSession(r.Context(), admin.ID, 8*time.Hour)
	if err != nil {
		slog.Error("Login: failed to create session", "admin_id", admin.ID, "error", err)
		renderError("Login failed. Please try again.")
		return
	}

	SetSessionCookie(w, session.ID, h.isProduction)
	http.Redirect(w, r, "/console/dashboard", http.StatusSeeOther)
}

// HandleLogout clears the session and redirects to login.
func (h *Handler) HandleLogout(w http.ResponseWriter, r *http.Request) {
	if cookie, err := r.Cookie(sessionCookieName); err == nil {
		_ = h.repo.DeleteSession(r.Context(), cookie.Value)
	}
	ClearSessionCookie(w)
	http.Redirect(w, r, "/console/login", http.StatusSeeOther)
}

// --- Dashboard ---

func (h *Handler) ShowDashboard(w http.ResponseWriter, r *http.Request) {
	admin := adminFromCtx(r)

	summary, err := h.repo.GetSummary(r.Context())
	if err != nil {
		slog.Error("Dashboard: failed to get summary", "error", err)
		summary = &models.ConsoleSummary{}
	}

	businesses, err := h.repo.GetBusinesses(r.Context(), 10, 0)
	if err != nil {
		slog.Error("Dashboard: failed to get businesses", "error", err)
	}

	h.render(w, r, "dashboard.html", map[string]any{
		"Admin":      admin,
		"ActivePage": "dashboard",
		"Summary":    summary,
		"Businesses": businesses,
	})
}

// --- Businesses ---

func (h *Handler) ShowBusinesses(w http.ResponseWriter, r *http.Request) {
	admin := adminFromCtx(r)

	businesses, err := h.repo.GetBusinesses(r.Context(), 50, 0)
	if err != nil {
		slog.Error("Businesses: failed to fetch", "error", err)
	}

	total, _ := h.repo.CountBusinesses(r.Context())

	h.render(w, r, "businesses.html", map[string]any{
		"Admin":      admin,
		"ActivePage": "businesses",
		"Businesses": businesses,
		"Total":      total,
	})


}

//users and staff


func (h *Handler) ShowUsers(w http.ResponseWriter, r *http.Request) {
	
   admin := adminFromCtx(r)

   users, err := h.repo.GetUsers(r.Context(), 50, 0)
   if err != nil {
	   slog.Error("Users: failed to fetch", "error", err)
   }
   
   total, _ := h.repo.CountUsers(r.Context())

   h.render(w, r, "users.html", map[string]any{
	   "Admin":      admin,
	   "ActivePage": "users",
	   "Users":      users,
	   "Total":      total,
   })
}


// ShowStaff

	
   