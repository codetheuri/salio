package syncengine

import (
	"net/http"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"

	"salio/server-v2/internal/rbac"
)

func RegisterRoutes(api huma.API, db *gorm.DB, log logger.Logger) {
	handler := NewHandler(NewService(NewRepository(db)), log)
	guard := authz.NewGuard(api, db)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "sync-pull",
		Method:      http.MethodGet,
		Path:        "/api/v1/sync/pull",
		Summary:     "Download changes since a cursor",
		Description: "Returns one page of changes ordered by a server-issued cursor. " +
			"Advance the cursor only to `next_cursor`, and pull again while `has_more` is true. " +
			"`resync_required` means the cursor is too old to honour: discard local data and pull from 0.",
		Tags: []string{"Sync"},
	}, rbac.PermSyncPull), handler.Pull)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "sync-push",
		Method:      http.MethodPost,
		Path:        "/api/v1/sync/push",
		Summary:     "Upload changes made offline",
		Description: "Applies a batch and reports what was not accepted in `conflicts`. " +
			"Reuse the same `operation_id` when retrying: the outcome is recorded, so a retry " +
			"replays the original response instead of applying the batch twice.",
		Tags: []string{"Sync"},
	}, rbac.PermSyncPush), handler.Push)
}
