package syncengine

import (
	"context"

	"github.com/codetheuri/tusk/v2/pkg/logger"
	"github.com/danielgtaylor/huma/v2"
)

type Handler struct {
	service *Service
	log     logger.Logger
}

func NewHandler(service *Service, log logger.Logger) *Handler {
	return &Handler{service: service, log: log}
}

func (h *Handler) Pull(ctx context.Context, in *PullInput) (*PullOutput, error) {
	view, err := h.service.Pull(ctx, in.Cursor, in.Limit)
	if err != nil {
		h.log.Error("sync module error while pulling changes", err)
		return nil, huma.Error500InternalServerError("Sync failed. Please try again.")
	}

	resp := &PullOutput{}
	resp.Body.Success = true
	resp.Body.Data = *view
	return resp, nil
}

func (h *Handler) Push(ctx context.Context, in *PushInput) (*PushOutput, error) {
	view, err := h.service.Push(ctx, *in)
	if err != nil {
		h.log.Error("sync module error while applying a push", err)
		return nil, huma.Error500InternalServerError("Sync failed. Please try again.")
	}

	// 200 with a conflict list, not an error status. Conflicts are the normal
	// outcome of two people working offline on one shop's book, not a failure of
	// the request — and a 4xx would make a client treat the applied records as
	// unapplied and push them again.
	resp := &PushOutput{}
	resp.Body.Success = true
	resp.Body.Data = *view
	return resp, nil
}
