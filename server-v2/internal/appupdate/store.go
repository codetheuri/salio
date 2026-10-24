// Package appupdate publishes the Android app outside an app store: the
// latest version for the in-app updater, the APK downloads, and a download
// page to share instead of sending APK files over WhatsApp (docs/10, §6.3).
//
// A release is a folder (APP_RELEASES_DIR) holding the APKs and latest.json,
// written by mobile-v2/scripts/release.sh and copied to the server, APKs
// first and the manifest last. Nothing is uploaded through the API, so a
// stolen password cannot replace the app.
//
// Ported from DairyGo's internal/appupdate, with two additions the plan asks
// for: a staged rollout percentage, and release notes in English and
// Swahili. Its legacy version-code scale is gone: every Salio APK of build N
// has version code N (docs/10, D19). Both products should share one copy in
// Tusk (pkg/appupdate) once DairyGo moves to this version of it.
package appupdate

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sync"
	"time"
)

// ManifestName is the file describing the latest release.
const ManifestName = "latest.json"

// ErrNoRelease means no release has been published yet.
var ErrNoRelease = errors.New("no app release has been published")

// ErrUnknownABI means the release has no APK for that phone type.
var ErrUnknownABI = errors.New("no APK for this phone type")

// ABIs lists the phone types an APK is built for, most common first.
// x86_64 is for emulators.
var ABIs = []string{"arm64", "armv7", "x86_64"}

var (
	apkName   = regexp.MustCompile(`^[A-Za-z0-9._-]+\.apk$`)
	sha256Hex = regexp.MustCompile(`^[0-9a-f]{64}$`)
)

// Manifest is latest.json.
type Manifest struct {
	Version string `json:"version"`
	Build   int    `json:"build"`

	// MinBuild: older apps must update before they can sync. Applies to every
	// phone, whatever the rollout.
	MinBuild int `json:"min_build"`

	// RolloutPercent offers the release to this share of phones, each placed
	// in a fixed bucket by a random install ID (docs/10, §6.2). Ship to 10%,
	// watch crash reports, then raise it. Omitted means 100.
	RolloutPercent *int `json:"rollout_percent,omitempty"`

	// Notes by language: "en" is required, "sw" falls back to it.
	Notes       map[string]string `json:"notes"`
	PublishedAt time.Time         `json:"published_at"`
	Files       map[string]File   `json:"files"`
}

// Rollout is the share of phones the release is offered to.
func (m *Manifest) Rollout() int {
	if m.RolloutPercent == nil {
		return 100
	}
	return *m.RolloutPercent
}

// File is one APK of a release.
type File struct {
	Name   string `json:"name"`
	SHA256 string `json:"sha256"`
	Size   int64  `json:"size"`
}

// Store reads the published release from a folder.
type Store struct {
	dir string

	mu       sync.Mutex
	modTime  time.Time
	manifest *Manifest
}

// NewStore returns a Store for dir.
func NewStore(dir string) *Store { return &Store{dir: dir} }

// Latest returns the published release. It re-reads latest.json only when
// the file changes, so publishing needs no restart.
func (s *Store) Latest() (*Manifest, error) {
	path := filepath.Join(s.dir, ManifestName)
	info, err := os.Stat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, ErrNoRelease
	}
	if err != nil {
		return nil, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.manifest != nil && info.ModTime().Equal(s.modTime) {
		return s.manifest, nil
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var m Manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return nil, fmt.Errorf("%s: %w", ManifestName, err)
	}
	if err := s.validate(&m); err != nil {
		return nil, fmt.Errorf("%s: %w", ManifestName, err)
	}
	s.manifest, s.modTime = &m, info.ModTime()
	return &m, nil
}

// validate rejects a manifest the app must not act on, including one whose
// APKs are missing or only partly copied, so phones never download a broken
// file or are forced to update to a release that is not there.
func (s *Store) validate(m *Manifest) error {
	switch {
	case m.Version == "":
		return errors.New("version is empty")
	case m.Build <= 0:
		return errors.New("build must be positive")
	case m.MinBuild < 0 || m.MinBuild > m.Build:
		return errors.New("min_build must be between 0 and build")
	case m.RolloutPercent != nil && (*m.RolloutPercent < 0 || *m.RolloutPercent > 100):
		return errors.New("rollout_percent must be between 0 and 100")
	case m.Notes["en"] == "":
		return errors.New(`notes must have "en"`)
	case len(m.Files) == 0:
		return errors.New("no files")
	}
	for lang := range m.Notes {
		if lang != "en" && lang != "sw" {
			return fmt.Errorf("notes: unknown language %q", lang)
		}
	}
	for abi, f := range m.Files {
		if !slices.Contains(ABIs, abi) {
			return fmt.Errorf("unknown phone type %q", abi)
		}
		if !apkName.MatchString(f.Name) {
			return fmt.Errorf("%s: invalid file name %q", abi, f.Name)
		}
		if !sha256Hex.MatchString(f.SHA256) {
			return fmt.Errorf("%s: sha256 must be 64 lowercase hex digits", abi)
		}
		info, err := os.Stat(filepath.Join(s.dir, f.Name))
		if err != nil {
			return fmt.Errorf("%s: %w", abi, err)
		}
		if info.Size() != f.Size {
			return fmt.Errorf("%s: %s is %d bytes, expected %d", abi, f.Name, info.Size(), f.Size)
		}
	}
	return nil
}

// Open opens the APK for abi. The caller closes it.
func (s *Store) Open(abi string) (*os.File, File, *Manifest, error) {
	m, err := s.Latest()
	if err != nil {
		return nil, File{}, nil, err
	}
	f, ok := m.Files[abi]
	if !ok {
		return nil, File{}, nil, ErrUnknownABI
	}
	// The name was validated as a plain file name, so it cannot leave dir.
	file, err := os.Open(filepath.Join(s.dir, f.Name))
	if err != nil {
		return nil, File{}, nil, err
	}
	return file, f, m, nil
}
