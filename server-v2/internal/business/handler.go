package business

import (
	"context"
	"errors"

	"github.com/codetheuri/tusk/v2/pkg/authz"
	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
)

// Handler translates HTTP concerns — status codes, the response envelope — from
// the service's own errors. It contains no business rules of its own.
type Handler struct {
	service *Service
	log     logger.Logger
}

func NewHandler(service *Service, log logger.Logger) *Handler {
	return &Handler{service: service, log: log}
}

func (h *Handler) Register(ctx context.Context, in *RegisterBusinessInput) (*AuthOutput, error) {
	auth, err := h.service.Register(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "registering the business")
	}
	return authResponse(auth, "Business registered"), nil
}

func (h *Handler) Login(ctx context.Context, in *LoginInput) (*AuthOutput, error) {
	auth, err := h.service.Login(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "logging in")
	}
	return authResponse(auth, "Logged in"), nil
}

func (h *Handler) Join(ctx context.Context, in *JoinBusinessInput) (*AuthOutput, error) {
	auth, err := h.service.Join(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "joining the business")
	}
	return authResponse(auth, "Joined business"), nil
}

func (h *Handler) CreateInvite(ctx context.Context, _ *EmptyInput) (*InviteOutput, error) {
	invite, err := h.service.CreateInvite(ctx)
	if err != nil {
		return nil, h.mapError(err, "creating the invite")
	}
	resp := &InviteOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Invite created"
	resp.Body.Data.Code = invite.Code
	resp.Body.Data.ExpiresAt = invite.ExpiresAt
	return resp, nil
}

func (h *Handler) GetBusiness(ctx context.Context, _ *EmptyInput) (*BusinessOutput, error) {
	b, err := h.service.GetBusiness(ctx)
	if err != nil {
		return nil, h.mapError(err, "loading the business")
	}
	resp := &BusinessOutput{}
	resp.Body.Success = true
	resp.Body.Data = viewBusiness(*b)
	return resp, nil
}

func (h *Handler) UpdateBusiness(ctx context.Context, in *UpdateBusinessInput) (*BusinessOutput, error) {
	b, err := h.service.UpdateBusiness(ctx, *in)
	if err != nil {
		return nil, h.mapError(err, "updating the business")
	}
	resp := &BusinessOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Business updated"
	resp.Body.Data = viewBusiness(*b)
	return resp, nil
}

func (h *Handler) Me(ctx context.Context, _ *EmptyInput) (*UserOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	u, err := h.service.Me(ctx, sub.UserID)
	if err != nil {
		return nil, h.mapError(err, "loading your profile")
	}
	resp := &UserOutput{}
	resp.Body.Success = true
	resp.Body.Data = viewUser(*u)
	return resp, nil
}

func (h *Handler) UpdateMe(ctx context.Context, in *UpdateMeInput) (*UserOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	u, err := h.service.UpdateMe(ctx, sub.UserID, in.Body.Name)
	if err != nil {
		return nil, h.mapError(err, "updating your profile")
	}
	resp := &UserOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Profile updated"
	resp.Body.Data = viewUser(*u)
	return resp, nil
}

func (h *Handler) ListStaff(ctx context.Context, _ *EmptyInput) (*StaffListOutput, error) {
	users, err := h.service.ListStaff(ctx)
	if err != nil {
		return nil, h.mapError(err, "listing staff")
	}
	resp := &StaffListOutput{}
	resp.Body.Success = true
	resp.Body.Data = viewUsers(users)
	return resp, nil
}

func (h *Handler) DeactivateStaff(ctx context.Context, in *StaffIDInput) (*MessageOutput, error) {
	sub, ok := authz.SubjectFromContext(ctx)
	if !ok {
		return nil, huma.Error401Unauthorized("authentication required")
	}
	if err := h.service.DeactivateStaff(ctx, sub.UserID, in.UserID); err != nil {
		return nil, h.mapError(err, "deactivating that staff member")
	}
	resp := &MessageOutput{}
	resp.Body.Success = true
	resp.Body.Message = "Staff member deactivated"
	return resp, nil
}

// mapError turns a service error into the right HTTP status.
//
// One place for this mapping so a handler cannot forget a case and let an
// internal error message reach a client — action is logged with detail; the
// client gets something it can act on.
func (h *Handler) mapError(err error, action string) error {
	switch {
	case errors.Is(err, ErrNotFound):
		return huma.Error404NotFound("Not found")
	case errors.Is(err, ErrPhoneTaken):
		return huma.Error409Conflict(err.Error())
	case errors.Is(err, ErrInvalidLogin), errors.Is(err, ErrAccountInactive):
		return huma.Error401Unauthorized(err.Error())
	case errors.Is(err, ErrInviteUnusable):
		return huma.Error400BadRequest(err.Error())
	case errors.Is(err, ErrCannotRemoveSelf), errors.Is(err, ErrLastOwner):
		return huma.Error422UnprocessableEntity(err.Error())
	default:
		h.log.Error("business module error while "+action, err)
		return huma.Error500InternalServerError("Something went wrong. Please try again.")
	}
}

func authResponse(a *Authenticated, message string) *AuthOutput {
	resp := &AuthOutput{}
	resp.Body.Success = true
	resp.Body.Message = message
	resp.Body.Data.Token = a.Token
	resp.Body.Data.User = viewUser(a.User)
	return resp
}
