package http

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"cashew-server/internal/auth"
	"cashew-server/internal/config"
	"cashew-server/internal/domain"
	"cashew-server/internal/repository"
	"cashew-server/internal/storage"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
)

type Handler struct {
	cfg   config.Config
	repo  *repository.Repository
	store *storage.Store
	log   *slog.Logger
}

func New(cfg config.Config, repo *repository.Repository, store *storage.Store, log *slog.Logger) *Handler {
	return &Handler{cfg: cfg, repo: repo, store: store, log: log}
}

func (h *Handler) Routes() http.Handler {
	router := chi.NewRouter()
	router.Use(middleware.RequestID, middleware.Recoverer, middleware.RealIP)
	router.Use(h.cors)

	router.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Короткий путь: эта ссылка сохраняется в заметке операции и открывается
	// без авторизации, поэтому она живёт вне /api/v1.
	router.Get("/a/{key}", h.downloadAttachment)

	router.Route("/api/v1", func(api chi.Router) {
		api.Post("/auth/register-family", h.registerFamily)
		api.Post("/auth/join-family", h.joinFamily)
		api.Post("/auth/login", h.login)

		api.Group(func(private chi.Router) {
			private.Use(h.authenticate)

			private.Get("/me", h.me)
			private.Get("/family/members", h.members)
			private.Post("/family/members/{userID}/active", h.setMemberActive)

			private.Post("/attachments", h.uploadAttachment)

			private.Get("/sync/files", h.listSyncFiles)
			private.Put("/sync/files/{name}", h.uploadSyncFile)
			private.Get("/sync/files/{name}", h.downloadSyncFile)
			private.Delete("/sync/files/{name}", h.deleteSyncFile)
		})
	})

	return router
}

func (h *Handler) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if allowed := h.allowedOrigin(origin); allowed != "" {
			w.Header().Set("Access-Control-Allow-Origin", allowed)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Max-Age", "86400")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (h *Handler) allowedOrigin(origin string) string {
	if origin == "" {
		return ""
	}
	for _, allowed := range h.cfg.AllowedOrigins {
		allowed = strings.TrimSpace(allowed)
		if allowed == "*" {
			return origin
		}
		if allowed == origin {
			return origin
		}
	}
	return ""
}

// authenticate проверяет токен и кладёт в контекст, кто именно пришёл. Всё, что
// ниже, работает только внутри семьи из токена, поэтому идентификатор семьи
// никогда не берётся из тела запроса.
func (h *Handler) authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, found := strings.CutPrefix(header, "Bearer ")
		if !found || strings.TrimSpace(token) == "" {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}

		identity, err := auth.ParseToken(h.cfg.JWTSecret, strings.TrimSpace(token))
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid or expired token")
			return
		}

		user, err := h.repo.UserByID(r.Context(), identity.UserID)
		if err != nil || !user.IsActive {
			writeError(w, http.StatusUnauthorized, "account is not active")
			return
		}

		next.ServeHTTP(w, r.WithContext(auth.WithIdentity(r.Context(), identity)))
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if payload != nil {
		_ = json.NewEncoder(w).Encode(payload)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]string{"error": message})
}

func (h *Handler) writeDomainError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, domain.ErrNotFound):
		writeError(w, http.StatusNotFound, "not found")
	case errors.Is(err, domain.ErrLoginTaken):
		writeError(w, http.StatusConflict, "login already taken")
	case errors.Is(err, domain.ErrBadCredentials):
		writeError(w, http.StatusUnauthorized, "invalid login or password")
	case errors.Is(err, domain.ErrForbidden):
		writeError(w, http.StatusForbidden, "forbidden")
	default:
		h.log.Error("unhandled error", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
	}
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil {
		writeError(w, http.StatusBadRequest, "malformed request body")
		return false
	}
	return true
}
