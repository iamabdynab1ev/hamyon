package http

import (
	"net/http"
	"strings"

	"cashew-server/internal/auth"
	"cashew-server/internal/domain"
)

type registerFamilyRequest struct {
	FamilyName string `json:"familyName"`
	Login      string `json:"login"`
	Name       string `json:"name"`
	Password   string `json:"password"`
}

type joinFamilyRequest struct {
	JoinCode string `json:"joinCode"`
	Login    string `json:"login"`
	Name     string `json:"name"`
	Password string `json:"password"`
}

type loginRequest struct {
	Login    string `json:"login"`
	Password string `json:"password"`
}

type sessionResponse struct {
	Token     string      `json:"token"`
	ExpiresAt string      `json:"expiresAt"`
	User      domain.User `json:"user"`
	JoinCode  string      `json:"joinCode,omitempty"`
}

func (h *Handler) registerFamily(w http.ResponseWriter, r *http.Request) {
	var req registerFamilyRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if !validCredentials(w, req.Login, req.Password, req.Name) {
		return
	}
	familyName := strings.TrimSpace(req.FamilyName)
	if familyName == "" {
		writeError(w, http.StatusBadRequest, "familyName is required")
		return
	}

	joinCode, err := auth.GenerateJoinCode()
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	passwordHash, err := auth.HashPassword(req.Password)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	user, err := h.repo.CreateFamilyWithOwner(r.Context(), familyName, joinCode,
		auth.NormalizeLogin(req.Login), strings.TrimSpace(req.Name), passwordHash)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	h.respondWithSession(w, user, joinCode)
}

func (h *Handler) joinFamily(w http.ResponseWriter, r *http.Request) {
	var req joinFamilyRequest
	if !decodeJSON(w, r, &req) {
		return
	}
	if !validCredentials(w, req.Login, req.Password, req.Name) {
		return
	}

	joinCode := strings.ToUpper(strings.TrimSpace(req.JoinCode))
	if joinCode == "" {
		writeError(w, http.StatusBadRequest, "joinCode is required")
		return
	}

	passwordHash, err := auth.HashPassword(req.Password)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	user, err := h.repo.JoinFamily(r.Context(), joinCode,
		auth.NormalizeLogin(req.Login), strings.TrimSpace(req.Name), passwordHash)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	h.respondWithSession(w, user, "")
}

func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !decodeJSON(w, r, &req) {
		return
	}

	user, passwordHash, err := h.repo.UserByLogin(r.Context(), auth.NormalizeLogin(req.Login))
	// Отвечаем одинаково на неизвестный логин и на неверный пароль, чтобы по
	// ответу нельзя было перебором узнать, какие логины существуют.
	if err != nil || !auth.CheckPassword(passwordHash, req.Password) {
		writeError(w, http.StatusUnauthorized, "invalid login or password")
		return
	}
	if !user.IsActive {
		writeError(w, http.StatusForbidden, "account is disabled")
		return
	}

	h.respondWithSession(w, user, "")
}

func (h *Handler) respondWithSession(w http.ResponseWriter, user domain.User, joinCode string) {
	token, expiresAt, err := auth.IssueToken(h.cfg.JWTSecret, user, h.cfg.TokenTTL)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, sessionResponse{
		Token:     token,
		ExpiresAt: expiresAt.UTC().Format("2006-01-02T15:04:05Z"),
		User:      user,
		JoinCode:  joinCode,
	})
}

func validCredentials(w http.ResponseWriter, login, password, name string) bool {
	if strings.TrimSpace(login) == "" {
		writeError(w, http.StatusBadRequest, "login is required")
		return false
	}
	if strings.TrimSpace(name) == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return false
	}
	if len(password) < 8 {
		writeError(w, http.StatusBadRequest, "password must be at least 8 characters")
		return false
	}
	return true
}
