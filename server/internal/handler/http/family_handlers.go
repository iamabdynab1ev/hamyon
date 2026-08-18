package http

import (
	"net/http"

	"cashew-server/internal/auth"
	"cashew-server/internal/domain"

	"github.com/go-chi/chi/v5"
)

type meResponse struct {
	User   domain.User   `json:"user"`
	Family domain.Family `json:"family"`
}

func (h *Handler) me(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	user, err := h.repo.UserByID(r.Context(), identity.UserID)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	family, err := h.repo.Family(r.Context(), identity.FamilyID)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	// Код приглашения — это по сути пароль от семьи, поэтому его видит только
	// владелец: остальным он не нужен и раздавать его они не должны.
	if !identity.IsOwner() {
		family.JoinCode = ""
	}

	writeJSON(w, http.StatusOK, meResponse{User: user, Family: family})
}

func (h *Handler) members(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	members, err := h.repo.Members(r.Context(), identity.FamilyID)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"members": members})
}

type setMemberActiveRequest struct {
	IsActive bool `json:"isActive"`
}

func (h *Handler) setMemberActive(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())
	if !identity.IsOwner() {
		writeError(w, http.StatusForbidden, "only the owner can manage members")
		return
	}

	var req setMemberActiveRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	if err := h.repo.SetMemberActive(r.Context(), identity.FamilyID, chi.URLParam(r, "userID"), req.IsActive); err != nil {
		h.writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"isActive": req.IsActive})
}
