package console

import (
	"fmt"
	"net/http"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/session"
	"github.com/go-chi/chi/v5"
	"gorm.io/gorm"
)

// Session policy for the console.
//
// Shorter than the mobile token's 30 days by two orders of magnitude, and
// deliberately so: a shopkeeper offline for a week must stay signed in, whereas
// a platform operator with read access to every business on Salio should not
// leave a live session on a laptop overnight.
const (
	sessionLifetime    = 8 * time.Hour
	sessionIdleTimeout = 30 * time.Minute
	sessionKind        = "console"
	sessionCookieName  = "salio_console_session"
)

// Options configures the console.
type Options struct {
	DB     *gorm.DB
	Logger logger.Logger

	// Secure marks the session cookie HTTPS-only. Drive it from
	// Config.IsProduction(); setting it true in local development means the
	// browser silently drops the cookie and sign-in appears to do nothing.
	Secure bool

	// Reload re-parses templates on every render. Development only.
	Reload bool
}

// Mount attaches the admin console to a router under /console.
//
// It takes a chi router rather than a huma.API on purpose: these are HTML pages
// with form posts and cookie sessions, which do not belong in an OpenAPI
// document describing a JSON API for a phone.
func Mount(r chi.Router, opts Options) error {
	if opts.DB == nil || opts.Logger == nil {
		return fmt.Errorf("console: Options.DB and Options.Logger are required")
	}

	views, err := newEngine(opts.Reload)
	if err != nil {
		// Returned, not logged: a console template that does not parse should
		// stop the process starting, rather than wait to 500 at whichever page
		// an operator opens first.
		return fmt.Errorf("console: parsing templates: %w", err)
	}

	sessions, err := session.New(session.NewGormStore(opts.DB), session.Options{
		Kind:       sessionKind,
		CookieName: sessionCookieName,

		// Scoping the cookie to /console keeps it off every API request. The
		// mobile client authenticates with a bearer token and has no use for it,
		// and a cookie that is never sent cannot be replayed.
		Path:        "/console",
		Secure:      opts.Secure,
		SameSite:    http.SameSiteLaxMode,
		Lifetime:    sessionLifetime,
		IdleTimeout: sessionIdleTimeout,
	})
	if err != nil {
		return fmt.Errorf("console: configuring sessions: %w", err)
	}

	h := NewHandler(NewService(NewRepository(opts.DB)), views, sessions, opts.Logger)

	r.Route("/console", func(r chi.Router) {
		// Its own group, with no session middleware: stylesheets are not
		// secrets, an unstyled login page is a confusing way to be told you are
		// signed out, and an asset request has no reason to cost a session
		// lookup. Embedded, so this serves from the binary with no files on disk.
		//
		// chi requires every Use on a router to precede its routes, so the two
		// halves have to be separate groups rather than a Handle followed by a
		// Use — which panics at mount time.
		r.Group(func(r chi.Router) {
			r.Handle("/static/*", http.StripPrefix("/console/static/",
				http.FileServer(http.FS(StaticFS()))))
		})

		r.Group(func(r chi.Router) {
			// Loads a session where one exists and clears a dead cookie. It
			// refuses nothing — the login form lives under here too, and needs to
			// ask whether the visitor is already signed in.
			r.Use(sessions.Middleware())

			r.Get("/", func(w http.ResponseWriter, r *http.Request) {
				// To the dashboard, not the login page: Require below sends an
				// unauthenticated visitor on to sign in, while someone already
				// signed in lands where they meant to go.
				http.Redirect(w, r, dashboardPath, http.StatusSeeOther)
			})
			r.Get("/login", h.ShowLogin)
			r.Post("/login", h.HandleLogin)

			r.Group(func(r chi.Router) {
				r.Use(sessions.Require(loginPath)) // a valid session exists
				r.Use(h.RequireAdmin)              // and its subject still does

				// POST, so a link or an <img> cannot sign an operator out.
				// Combined with SameSite=Lax — which withholds the cookie from
				// cross-site form posts — this is the console's CSRF story. It
				// holds because logout is the only state-changing action here;
				// the first page that mutates business data needs a real token.
				r.Post("/logout", h.HandleLogout)

				r.Get("/dashboard", h.ShowDashboard)
				r.Get("/businesses", h.ShowBusinesses)
				r.Get("/businesses/{id}", h.ShowBusiness)
				r.Get("/users", h.ShowUsers)
			})
		})
	})

	return nil
}
