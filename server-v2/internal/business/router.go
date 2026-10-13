package business

import (
	"net/http"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
	"gorm.io/gorm"

	"salio/server-v2/internal/rbac"
)

// RegisterRoutes wires the business module into a Huma API.
//
// jwtSecret and tokenTTL are passed rather than read from a shared config type,
// so this module — like every other one on Tusk — depends only on what it
// actually uses.
func RegisterRoutes(api huma.API, db *gorm.DB, jwtSecret string, tokenTTL time.Duration, log logger.Logger) {
	repo := NewRepository(db)
	service := NewService(repo, jwtSecret, tokenTTL)
	handler := NewHandler(service, log)
	guard := authz.NewGuard(api, db)

	// ---------------------------------------------------------------
	// Public: no tenant, no permission. A caller with no account yet has
	// to be able to reach these to get one.
	// ---------------------------------------------------------------

	huma.Register(api, huma.Operation{
		OperationID: "register-business",
		Method:      http.MethodPost,
		Path:        "/api/v1/auth/register-business",
		Summary:     "Register a new business",
		Description: "Creates a business and its first owner, and returns a token.",
		Tags:        []string{"Authentication"},
	}, handler.Register)

	huma.Register(api, huma.Operation{
		OperationID: "login",
		Method:      http.MethodPost,
		Path:        "/api/v1/auth/login",
		Summary:     "Sign in",
		Description: "Authenticates by phone and password.",
		Tags:        []string{"Authentication"},
	}, handler.Login)

	huma.Register(api, huma.Operation{
		OperationID: "join-business",
		Method:      http.MethodPost,
		Path:        "/api/v1/auth/join",
		Summary:     "Join a business",
		Description: "Redeems an invite code and creates a staff account.",
		Tags:        []string{"Authentication"},
	}, handler.Join)

	// ---------------------------------------------------------------
	// Protected: BearerSecurity plus a permission from the roles matrix in
	// pkg rbac. Guard.Protected is what makes each requirement visible in
	// the generated OpenAPI docs, not only enforced at runtime.
	// ---------------------------------------------------------------

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "create-invite",
		Method:      http.MethodPost,
		Path:        "/api/v1/auth/invite",
		Summary:     "Create a staff invite",
		Tags:        []string{"Business"},
	}, rbac.PermStaffManage), handler.CreateInvite)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-business",
		Method:      http.MethodGet,
		Path:        "/api/v1/business",
		Summary:     "Get business details",
		Tags:        []string{"Business"},
	}, rbac.PermBusinessRead), handler.GetBusiness)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "update-business",
		Method:      http.MethodPut,
		Path:        "/api/v1/business",
		Summary:     "Update business details",
		Tags:        []string{"Business"},
	}, rbac.PermBusinessUpdate), handler.UpdateBusiness)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "upload-business-logo",
		Method:      http.MethodPut,
		Path:        "/api/v1/business/logo",
		Summary:     "Upload the logo printed on PDFs (PNG or JPEG, up to 512 KB)",
		Tags:        []string{"Business"},
	}, rbac.PermBusinessUpdate), handler.UploadLogo)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-business-logo",
		Method:      http.MethodGet,
		Path:        "/api/v1/business/logo",
		Summary:     "Download the business logo",
		Tags:        []string{"Business"},
	}, rbac.PermBusinessRead), handler.GetLogo)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "delete-business-logo",
		Method:      http.MethodDelete,
		Path:        "/api/v1/business/logo",
		Summary:     "Remove the business logo",
		Tags:        []string{"Business"},
	}, rbac.PermBusinessUpdate), handler.DeleteLogo)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "get-me",
		Method:      http.MethodGet,
		Path:        "/api/v1/users/me",
		Summary:     "Get your own profile",
		Tags:        []string{"Users"},
	}, ""), handler.Me)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "update-me",
		Method:      http.MethodPut,
		Path:        "/api/v1/users/me",
		Summary:     "Update your own profile",
		Tags:        []string{"Users"},
	}, ""), handler.UpdateMe)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "list-staff",
		Method:      http.MethodGet,
		Path:        "/api/v1/staff",
		Summary:     "List staff",
		Tags:        []string{"Users"},
	}, rbac.PermStaffRead), handler.ListStaff)

	huma.Register(api, guard.Protected(huma.Operation{
		OperationID: "deactivate-staff",
		Method:      http.MethodDelete,
		Path:        "/api/v1/staff/{userID}",
		Summary:     "Deactivate a staff member",
		Tags:        []string{"Users"},
	}, rbac.PermStaffManage), handler.DeactivateStaff)
}
