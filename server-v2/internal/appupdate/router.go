package appupdate

import (
	"net/http"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"github.com/go-chi/chi/v5"
)

// RegisterRoutes adds, all public (an app must be able to update before it
// signs in, and an outdated app may be unable to):
//   - GET /api/v1/app/version: the latest release, for the in-app updater;
//   - GET /app: the download page to share;
//   - GET /app/download/{abi}: the APK.
func RegisterRoutes(api huma.API, r chi.Router, store *Store, log logger.Logger) {
	h := NewHandler(store, log)

	huma.Register(api, huma.Operation{
		OperationID: "get-app-version",
		Method:      http.MethodGet,
		Path:        "/api/v1/app/version",
		Summary:     "Latest mobile app release",
		Description: "The latest Android release: version, the minimum build still allowed to sync, " +
			"the rollout percentage, notes and APK downloads with SHA-256. Public. 404 when nothing is published.",
		Tags: []string{"Mobile App"},
	}, h.Version)

	r.Group(func(r chi.Router) {
		r.Use(pageHeaders)
		r.Get("/app", h.Page)
		r.Get("/app/app.css", h.Stylesheet)
		r.Get("/app/download/{abi}", h.Download)
		r.Head("/app/download/{abi}", h.Download)
	})
}

// pageHeaders: the page loads only its own stylesheet; no scripts, frames
// or anything else, so a manifest's notes can never become code on it.
func pageHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("Content-Security-Policy", "default-src 'none'; style-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		next.ServeHTTP(w, r)
	})
}
