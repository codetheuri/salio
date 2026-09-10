package business

import (
	"time"

	"github.com/google/uuid"

	"salio/server-v2/internal/domain"
)

// UserView is what the API returns for a user. It exists so that adding a field
// to domain.User — a password reset token, an internal flag — cannot leak it by
// default. The password hash is already excluded by its json tag, but relying on
// a tag is relying on nobody ever forgetting one.
type UserView struct {
	ID         uuid.UUID   `json:"id"`
	BusinessID uuid.UUID   `json:"business_id"`
	Name       string      `json:"name"`
	Phone      string      `json:"phone"`
	Role       domain.Role `json:"role"`
	IsActive   bool        `json:"is_active"`
	CreatedAt  time.Time   `json:"created_at"`
}

func viewUser(u domain.User) UserView {
	return UserView{
		ID: u.ID, BusinessID: u.BusinessID, Name: u.Name,
		Phone: u.Phone, Role: u.Role, IsActive: u.IsActive, CreatedAt: u.CreatedAt,
	}
}

func viewUsers(us []domain.User) []UserView {
	// Non-nil so an empty staff list serialises as [] rather than null, which
	// clients otherwise have to special-case.
	out := make([]UserView, 0, len(us))
	for _, u := range us {
		out = append(out, viewUser(u))
	}
	return out
}

// BusinessView is the business record as returned to a client.
type BusinessView struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	Type      *string   `json:"type,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

func viewBusiness(b domain.Business) BusinessView {
	return BusinessView{ID: b.ID, Name: b.Name, Type: b.Type, CreatedAt: b.CreatedAt}
}

// --- Requests ---

type RegisterBusinessInput struct {
	Body struct {
		BusinessName string `json:"business_name" required:"true" minLength:"2" maxLength:"255" doc:"Name of the shop"`
		BusinessType string `json:"business_type,omitempty" maxLength:"100" doc:"Kiosk, agrovet, hardware, and so on"`
		Name         string `json:"name" required:"true" minLength:"2" maxLength:"255" doc:"The owner's name"`
		Phone        string `json:"phone" required:"true" minLength:"9" maxLength:"50" doc:"Used to sign in"`
		Password     string `json:"password" required:"true" minLength:"4" maxLength:"72" doc:"At least 8 characters"`
	}
}

type LoginInput struct {
	Body struct {
		Phone    string `json:"phone" required:"true" minLength:"9" maxLength:"50"`
		Password string `json:"password" required:"true" minLength:"1" maxLength:"72"`
	}
}

type JoinBusinessInput struct {
	Body struct {
		Code     string `json:"code" required:"true" minLength:"4" maxLength:"10" doc:"Invite code from the owner"`
		Name     string `json:"name" required:"true" minLength:"2" maxLength:"255"`
		Phone    string `json:"phone" required:"true" minLength:"9" maxLength:"50"`
		Password string `json:"password" required:"true" minLength:"8" maxLength:"72"`
	}
}

type UpdateMeInput struct {
	Body struct {
		Name string `json:"name" required:"true" minLength:"2" maxLength:"255"`
	}
}

type UpdateBusinessInput struct {
	Body struct {
		Name string `json:"name" required:"true" minLength:"2" maxLength:"255"`
		Type string `json:"type,omitempty" maxLength:"100"`
	}
}

type StaffIDInput struct {
	UserID uuid.UUID `path:"userID" doc:"The staff member to deactivate"`
}

type EmptyInput struct{}

// --- Responses ---

// AuthOutput carries a token and the user it belongs to.
type AuthOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
		Data    struct {
			Token string   `json:"token"`
			User  UserView `json:"user"`
		} `json:"data"`
	}
}

type UserOutput struct {
	Body struct {
		Success bool     `json:"success"`
		Message string   `json:"message"`
		Data    UserView `json:"data"`
	}
}

type StaffListOutput struct {
	Body struct {
		Success bool       `json:"success"`
		Message string     `json:"message"`
		Data    []UserView `json:"data"`
	}
}

type BusinessOutput struct {
	Body struct {
		Success bool         `json:"success"`
		Message string       `json:"message"`
		Data    BusinessView `json:"data"`
	}
}

type InviteOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
		Data    struct {
			Code      string    `json:"code"`
			ExpiresAt time.Time `json:"expires_at"`
		} `json:"data"`
	}
}

type MessageOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
	}
}
