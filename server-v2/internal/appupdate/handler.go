package appupdate

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"html/template"
	"net/http"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/codetheuri/tusk/v2/pkg/response"
	"github.com/danielgtaylor/huma/v2"
	"github.com/go-chi/chi/v5"
)

// maxDownloadTime bounds one APK download. A server's usual write timeout
// would cut a 20 MB file on a slow rural connection (about 30 minutes at
// 100 kbps), while an unlimited one would let idle clients hold connections
// for ever.
const maxDownloadTime = 2 * time.Hour

//go:embed page
var pageFiles embed.FS

var pageTemplate = template.Must(template.New("index.html").Funcs(template.FuncMap{
	"mb": megabytes,
}).ParseFS(pageFiles, "page/index.html"))

// megabytes writes a size for people: "18 MB", or "0.3 MB" below 10 MB,
// where whole megabytes would round a small file down to nothing.
func megabytes(size int64) string {
	mb := float64(size) / (1 << 20)
	if mb < 10 {
		return fmt.Sprintf("%.1f MB", mb)
	}
	return fmt.Sprintf("%.0f MB", mb)
}

// Handler serves releases.
type Handler struct {
	store *Store
	log   logger.Logger
}

// NewHandler returns a Handler reading from store.
func NewHandler(store *Store, log logger.Logger) *Handler {
	return &Handler{store: store, log: log}
}

// ReleaseFile is one APK as the app sees it.
type ReleaseFile struct {
	URL    string `json:"url" doc:"Download path, relative to the API host"`
	SHA256 string `json:"sha256" doc:"SHA-256 of the APK, checked by the app before installing"`
	Size   int64  `json:"size" doc:"Size in bytes"`
}

// ReleaseInfo is the latest release.
type ReleaseInfo struct {
	Version        string                 `json:"version" example:"2.0.3"`
	Build          int                    `json:"build" example:"15" doc:"The build number; every APK of this release has it as its Android version code. Higher is newer."`
	MinBuild       int                    `json:"min_build" example:"12" doc:"Apps below this build must update before they can sync. Applies to every phone, whatever the rollout."`
	RolloutPercent int                    `json:"rollout_percent" example:"100" doc:"Offered to this share of phones (0 to 100), by each phone's fixed bucket"`
	Notes          map[string]string      `json:"notes" doc:"What is new, by language: en, and sw when written"`
	PublishedAt    time.Time              `json:"published_at"`
	PageURL        string                 `json:"page_url" example:"/app"`
	Files          map[string]ReleaseFile `json:"files" doc:"By phone type: arm64 (most phones), armv7 (older phones), x86_64 (emulators)"`
}

// VersionOutput is the response of GET /api/v1/app/version.
type VersionOutput struct {
	Body response.Data[ReleaseInfo]
}

// Version returns the latest release, for the in-app updater.
func (h *Handler) Version(ctx context.Context, _ *struct{}) (*VersionOutput, error) {
	m, err := h.store.Latest()
	if errors.Is(err, ErrNoRelease) {
		return nil, huma.Error404NotFound(err.Error())
	}
	if err != nil {
		h.log.Error("App release manifest is invalid", err)
		return nil, huma.Error503ServiceUnavailable("App release information is unavailable")
	}
	info := ReleaseInfo{
		Version:        m.Version,
		Build:          m.Build,
		MinBuild:       m.MinBuild,
		RolloutPercent: m.Rollout(),
		Notes:          m.Notes,
		PublishedAt:    m.PublishedAt,
		PageURL:        "/app",
		Files:          make(map[string]ReleaseFile, len(m.Files)),
	}
	for abi, f := range m.Files {
		info.Files[abi] = ReleaseFile{URL: "/app/download/" + abi, SHA256: f.SHA256, Size: f.Size}
	}
	out := &VersionOutput{}
	out.Body.Success = true
	out.Body.Message = "Latest app release"
	out.Body.Data = info
	return out, nil
}

// Download sends the APK for the phone type in the path. It supports Range
// requests, so an interrupted download continues where it stopped, and its
// ETag is the file's SHA-256, so If-Range restarts a download whose file
// changed underneath it.
func (h *Handler) Download(w http.ResponseWriter, r *http.Request) {
	file, f, m, err := h.store.Open(chi.URLParam(r, "abi"))
	switch {
	case errors.Is(err, ErrNoRelease), errors.Is(err, ErrUnknownABI):
		http.Error(w, err.Error(), http.StatusNotFound)
		return
	case err != nil:
		h.log.Error("Failed to open app release", err)
		http.Error(w, "The app download is unavailable", http.StatusServiceUnavailable)
		return
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		http.Error(w, "The app download is unavailable", http.StatusServiceUnavailable)
		return
	}

	if err := http.NewResponseController(w).SetWriteDeadline(time.Now().Add(maxDownloadTime)); err != nil {
		h.log.Error("Cannot extend the write deadline for an app download", err)
	}
	// The package type makes phones open the file with the installer, not
	// a PDF reader or gallery.
	w.Header().Set("Content-Type", "application/vnd.android.package-archive")
	w.Header().Set("Content-Disposition", fmt.Sprintf(`attachment; filename="Salio-%s.apk"`, m.Version))
	w.Header().Set("ETag", `"`+f.SHA256+`"`)
	w.Header().Set("Cache-Control", "no-cache")
	http.ServeContent(w, r, f.Name, info.ModTime(), file)
}

// Page shows the download page. The release is offered here to everyone:
// the rollout limits the in-app offer, not a person who asked for the app.
func (h *Handler) Page(w http.ResponseWriter, r *http.Request) {
	m, err := h.store.Latest()
	if err != nil && !errors.Is(err, ErrNoRelease) {
		h.log.Error("App release manifest is invalid", err)
		m = nil
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if m == nil {
		w.WriteHeader(http.StatusServiceUnavailable)
	}
	if err := pageTemplate.Execute(w, m); err != nil {
		h.log.Error("Failed to render the app download page", err)
	}
}

// Stylesheet serves the page's styles (a file, so the page's
// Content-Security-Policy can forbid inline code).
func (h *Handler) Stylesheet(w http.ResponseWriter, r *http.Request) {
	http.ServeFileFS(w, r, pageFiles, "page/app.css")
}
