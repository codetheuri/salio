package console

import (
	"embed"
	"fmt"
	"html/template"
	"io/fs"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/view"

	"salio/server-v2/internal/money"
)

// Templates and static files are compiled into the binary.
//
// v1 served them with http.Dir("static") and template.ParseFiles("templates/…"),
// which made the working directory part of the deployment contract: the same
// binary worked from the repository root and 404'd everywhere else. Embedding
// removes the question.
//
//go:embed templates
var templateFS embed.FS

//go:embed static
var staticFS embed.FS

// StaticFS is the file system served under /console/static.
func StaticFS() fs.FS {
	sub, err := fs.Sub(staticFS, "static")
	if err != nil {
		// Unreachable: the directory is embedded above, so it exists in the
		// binary or the binary did not build.
		panic(err)
	}
	return sub
}

// newEngine parses every console page.
//
// Reload is for development only, and comes from configuration rather than a
// constant. Note that it re-reads through templateFS, which is the embedded
// copy — editing a file under internal/console/templates and refreshing shows
// the change only when the process is rebuilt, which `make dev` does anyway.
func newEngine(reload bool) (*view.Engine, error) {
	return view.New(view.Config{
		FS:      templateFS,
		Dir:     "templates",
		Layouts: []string{"base.html", "layout.html"},
		Entry:   "base",
		Reload:  reload,
		Funcs: template.FuncMap{
			"initial":  initial,
			"shortID":  shortID,
			"money":    formatMoney,
			"date":     func(t time.Time) string { return t.Format("Jan 2, 2006") },
			"datetime": func(t time.Time) string { return t.Format("Jan 2, 2006 15:04") },
			"since":    since,
		},
	})
}

// initial is the letter shown in an avatar circle.
//
// The obvious {{slice .Name 0 1}} — which the v1 templates used — panics on an
// empty name and cuts a multi-byte character in half on a non-ASCII one, which
// renders as a replacement glyph. Ranging takes a whole rune or nothing.
func initial(name string) string {
	for _, r := range name {
		return strings.ToUpper(string(r))
	}
	return "?"
}

// shortID abbreviates a UUID for display. Enough to tell two rows apart by eye;
// the full value is in the link.
func shortID(v fmt.Stringer) string {
	s := v.String()
	if len(s) > 8 {
		return s[:8] + "…"
	}
	return s
}

// formatMoney renders an exact amount as KES with thousands separators.
//
// It formats money.Amount's own decimal string rather than converting to a
// float first: v1's templates used {{printf "%.0f"}} on a float64, which both
// rounds and, past 2^53 minor units, silently loses precision.
func formatMoney(a money.Amount) string {
	s := a.String()

	neg := strings.HasPrefix(s, "-")
	s = strings.TrimPrefix(s, "-")

	whole, frac, _ := strings.Cut(s, ".")

	var b strings.Builder
	for i, digit := range whole {
		if i > 0 && (len(whole)-i)%3 == 0 {
			b.WriteByte(',')
		}
		b.WriteRune(digit)
	}

	out := b.String()
	if frac != "" {
		out += "." + frac
	}
	if neg {
		return "-" + out
	}
	return out
}

// since renders how long ago something happened, for a nil-able timestamp.
func since(t *time.Time) string {
	if t == nil {
		return "never"
	}
	d := time.Since(*t)
	switch {
	case d < time.Hour:
		return fmt.Sprintf("%dm ago", int(d.Minutes()))
	case d < 24*time.Hour:
		return fmt.Sprintf("%dh ago", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd ago", int(d.Hours()/24))
	}
}
