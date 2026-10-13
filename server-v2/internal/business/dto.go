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

	// MustChangePassword: the owner reset this password. The app shows the
	// change-password screen and nothing else until it is changed; the server
	// refuses everything else meanwhile (internal/session).
	MustChangePassword bool      `json:"must_change_password"`
	CreatedAt          time.Time `json:"created_at"`
}

func viewUser(u domain.User) UserView {
	return UserView{
		ID: u.ID, BusinessID: u.BusinessID, Name: u.Name,
		Phone: u.Phone, Role: u.Role, IsActive: u.IsActive,
		MustChangePassword: u.MustChangePassword, CreatedAt: u.CreatedAt,
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
	ID      uuid.UUID `json:"id"`
	Name    string    `json:"name"`
	Type    *string   `json:"type,omitempty"`
	Phone   *string   `json:"phone,omitempty"`
	Email   *string   `json:"email,omitempty"`
	Address *string   `json:"address,omitempty"`

	// TimeZone is the IANA zone the business's dates are taken in.
	TimeZone string `json:"time_zone"`

	// HasLogo says whether GET /api/v1/business/logo will return an image, so
	// the app can decide whether to fetch one without a request that 404s.
	HasLogo   bool      `json:"has_logo"`
	CreatedAt time.Time `json:"created_at"`
}

func viewBusiness(b domain.Business, hasLogo bool) BusinessView {
	return BusinessView{
		ID: b.ID, Name: b.Name, Type: b.Type,
		Phone: b.Phone, Email: b.Email, Address: b.Address,
		TimeZone: b.TimeZone, HasLogo: hasLogo, CreatedAt: b.CreatedAt,
	}
}

// --- Requests ---

type RegisterBusinessInput struct {
	Body struct {
		BusinessName string `json:"business_name" required:"true" minLength:"2" maxLength:"255" doc:"Name of the shop"`
		BusinessType string `json:"business_type,omitempty" maxLength:"100" doc:"Kiosk, agrovet, hardware, and so on"`
		Name         string `json:"name" required:"true" minLength:"2" maxLength:"255" doc:"The owner's name"`
		Phone        string `json:"phone" required:"true" minLength:"9" maxLength:"50" doc:"Used to sign in"`
		Password     string `json:"password" required:"true" minLength:"8" maxLength:"72" doc:"At least 8 characters"`

		// The app sends the phone's own zone, so a shop outside Kenya gets
		// the right dates from its first entry without a settings visit.
		TimeZone string `json:"time_zone,omitempty" maxLength:"64" doc:"IANA zone, e.g. Africa/Nairobi. Defaults to Africa/Nairobi."`
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

		// Printed in the letterhead of every PDF. Sending an empty string
		// clears one; leaving a field out does the same, since this is a full
		// replacement of the business details rather than a patch.
		Phone   string `json:"phone,omitempty" maxLength:"50" doc:"Shown on purchase orders and statements"`
		Email   string `json:"email,omitempty" maxLength:"255" doc:"Shown on purchase orders and statements"`
		Address string `json:"address,omitempty" maxLength:"500" doc:"e.g. Shop 4, Kiambu Road, Ruiru"`

		// Unlike the contact details, leaving this out keeps the current
		// zone: a client that predates the field must not reset a shop in
		// Lagos to Nairobi by saving its name.
		TimeZone string `json:"time_zone,omitempty" maxLength:"64" doc:"IANA zone, e.g. Africa/Nairobi. Omit to keep the current one."`
	}
}

// UploadLogoInput takes the image as the raw request body.
//
// A raw body rather than multipart: one image, no other fields, and a phone app
// can send bytes with a Content-Type in one line, where multipart needs a
// boundary-encoding library.
type UploadLogoInput struct {
	RawBody []byte `contentType:"image/png" doc:"A PNG or JPEG, at most 512 KB"`
}

type LogoOutput struct {
	ContentType  string `header:"Content-Type"`
	CacheControl string `header:"Cache-Control"`
	Body         []byte
}

type ChangePasswordInput struct {
	Body struct {
		CurrentPassword string `json:"current_password" required:"true" minLength:"1" maxLength:"72"`
		NewPassword     string `json:"new_password" required:"true" minLength:"8" maxLength:"72" doc:"At least 8 characters"`
	}
}

type ResetPasswordOutput struct {
	Body struct {
		Success bool   `json:"success"`
		Message string `json:"message"`
		Data    struct {
			// Shown once, to the owner, to pass on in person. The staff member
			// must replace it at their next sign-in.
			TemporaryPassword string `json:"temporary_password"`
		} `json:"data"`
	}
}

type StaffIDInput struct {
	UserID uuid.UUID `path:"userID" doc:"The staff member"`
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
