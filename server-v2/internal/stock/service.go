package stock

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/codetheuri/tusk/v2/pkg/tenant"
	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

const dateLayout = "2006-01-02"

type Service struct {
	repo *Repository
}

func NewService(repo *Repository) *Service { return &Service{repo: repo} }

// --- Stock requests ---

func (s *Service) CreateRequest(ctx context.Context, userID uuid.UUID, in CreateRequestInput) (*StockRequestView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	if in.Body.ID != nil {
		if existing, err := s.repo.GetRequest(ctx, *in.Body.ID); err == nil {
			v := requestView(*existing)
			return &v, nil
		} else if !errors.Is(err, ErrRequestNotFound) {
			return nil, err
		}
	}

	neededOn, err := s.dateOrToday(ctx, in.Body.NeededOn)
	if err != nil {
		return nil, err
	}

	req := &domain.StockRequest{
		BusinessID: businessID, UserID: userID,
		ProductName: in.Body.ProductName, NeededOn: neededOn, Notes: trimmedOrNil(in.Body.Notes),
	}
	if in.Body.ID != nil {
		req.ID = *in.Body.ID
	}
	if err := ValidateRequest(req); err != nil {
		return nil, err
	}
	if err := s.repo.CreateRequest(ctx, req); err != nil {
		return nil, err
	}
	v := requestView(*req)
	return &v, nil
}

func (s *Service) ListRequests(ctx context.Context, status string) ([]StockRequestView, error) {
	rows, err := s.repo.ListRequests(ctx, status)
	if err != nil {
		return nil, err
	}
	out := make([]StockRequestView, 0, len(rows))
	for _, r := range rows {
		out = append(out, requestView(r))
	}
	return out, nil
}

func (s *Service) UpdateRequest(ctx context.Context, in UpdateRequestInput) (*StockRequestView, error) {
	req, err := s.repo.GetRequest(ctx, in.RequestID)
	if err != nil {
		return nil, err
	}
	if err := CheckEditable(req); err != nil {
		return nil, err
	}

	req.ProductName = in.Body.ProductName
	req.Notes = trimmedOrNil(in.Body.Notes)
	if in.Body.NeededOn != nil && *in.Body.NeededOn != "" {
		if req.NeededOn, err = time.Parse(dateLayout, *in.Body.NeededOn); err != nil {
			return nil, ErrInvalidDate
		}
	}
	if err := ValidateRequest(req); err != nil {
		return nil, err
	}
	if err := s.repo.UpdateRequest(ctx, req); err != nil {
		return nil, err
	}
	v := requestView(*req)
	return &v, nil
}

func (s *Service) DeleteRequest(ctx context.Context, id uuid.UUID) error {
	req, err := s.repo.GetRequest(ctx, id)
	if err != nil {
		return err
	}
	if err := CheckEditable(req); err != nil {
		return err
	}
	return s.repo.DeleteRequest(ctx, id)
}

// --- Purchase orders ---

// CreateOrder places an order from pending requests and any extra products.
//
// A quantity is required on every line. That is the point at which a note that
// something ran out becomes an instruction to a supplier, and "send us some
// Duodip" is not an order anyone can fill.
func (s *Service) CreateOrder(ctx context.Context, userID uuid.UUID, in CreateOrderInput) (*PurchaseOrderView, error) {
	businessID, err := tenant.MustFromContext(ctx)
	if err != nil {
		return nil, err
	}

	supplier := strings.TrimSpace(in.Body.SupplierName)
	if supplier == "" {
		return nil, ErrSupplierRequired
	}
	if len(in.Body.Lines) == 0 {
		return nil, ErrNoLines
	}
	orderedOn, err := s.dateOrToday(ctx, in.Body.OrderedOn)
	if err != nil {
		return nil, err
	}

	// Collect the requests named, refusing duplicates, then load them so each
	// line can carry the product name as it stands at the moment of ordering.
	var requestIDs []uuid.UUID
	seen := map[uuid.UUID]bool{}
	for _, l := range in.Body.Lines {
		if !l.Quantity.IsPositive() {
			return nil, ErrQuantityRequired
		}
		hasRequest := l.StockRequestID != nil
		hasName := l.ProductName != nil && strings.TrimSpace(*l.ProductName) != ""
		if hasRequest == hasName {
			return nil, ErrLineNeedsProduct
		}
		if hasRequest {
			if seen[*l.StockRequestID] {
				return nil, ErrDuplicateRequest
			}
			seen[*l.StockRequestID] = true
			requestIDs = append(requestIDs, *l.StockRequestID)
		}
	}

	names := map[uuid.UUID]string{}
	for _, id := range requestIDs {
		req, err := s.repo.GetRequest(ctx, id)
		if errors.Is(err, ErrRequestNotFound) {
			return nil, ErrRequestUnavailable
		}
		if err != nil {
			return nil, err
		}
		if !req.IsPending() {
			return nil, ErrRequestUnavailable
		}
		names[id] = req.ProductName
	}

	order := &domain.PurchaseOrder{
		BusinessID: businessID, CreatedBy: userID,
		SupplierName: supplier, SupplierPhone: trimmedOrNil(in.Body.SupplierPhone),
		Notes: trimmedOrNil(in.Body.Notes), Status: domain.OrderStatusOrdered, OrderedOn: orderedOn,
	}
	for i, l := range in.Body.Lines {
		line := domain.PurchaseOrderLine{Quantity: l.Quantity, Position: i + 1}
		if l.StockRequestID != nil {
			id := *l.StockRequestID
			line.StockRequestID = &id
			line.ProductName = names[id]
		} else {
			line.ProductName = strings.TrimSpace(*l.ProductName)
		}
		order.Lines = append(order.Lines, line)
	}

	// The repository re-checks that every request is still pending, inside its
	// transaction and under the lock: two people ordering the same request at
	// once must not both succeed.
	if err := s.repo.CreateOrder(ctx, order, requestIDs); err != nil {
		return nil, err
	}
	v := orderView(*order)
	return &v, nil
}

func (s *Service) GetOrder(ctx context.Context, id uuid.UUID) (*domain.PurchaseOrder, error) {
	return s.repo.GetOrder(ctx, id)
}

func (s *Service) ListOrders(ctx context.Context, status string) ([]PurchaseOrderView, error) {
	rows, err := s.repo.ListOrders(ctx, status)
	if err != nil {
		return nil, err
	}
	out := make([]PurchaseOrderView, 0, len(rows))
	for _, o := range rows {
		out = append(out, orderView(o))
	}
	return out, nil
}

func (s *Service) CancelOrder(ctx context.Context, id uuid.UUID) error {
	return s.repo.CancelOrder(ctx, id)
}

// dateOrToday parses a date the client sent, or takes the business's today.
func (s *Service) dateOrToday(ctx context.Context, date *string) (time.Time, error) {
	if date == nil || *date == "" {
		return s.repo.Today(ctx)
	}
	t, err := time.Parse(dateLayout, *date)
	if err != nil {
		return time.Time{}, ErrInvalidDate
	}
	return t, nil
}

func trimmedOrNil(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}
