package http

import (
	"crypto/rand"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"

	"cashew-server/internal/auth"
	"cashew-server/internal/domain"

	"github.com/go-chi/chi/v5"
)

type uploadAttachmentResponse struct {
	domain.Attachment
	URL string `json:"url"`
}

func (h *Handler) uploadAttachment(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	name, ok := safeFileName(w, r.URL.Query().Get("name"))
	if !ok {
		return
	}

	publicKey, err := newPublicKey()
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	storageKey := h.store.Key(identity.FamilyID, "attachment-"+publicKey)
	size, err := h.store.Save(storageKey, http.MaxBytesReader(w, r.Body, h.cfg.MaxUploadSize))
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	attachment, err := h.repo.CreateAttachment(r.Context(), identity.FamilyID,
		identity.UserID, publicKey, name, mimeTypeFor(name), storageKey, size)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, uploadAttachmentResponse{
		Attachment: attachment,
		URL:        h.attachmentURL(r, publicKey),
	})
}

// downloadAttachment отдаёт файл без проверки токена: ссылка сохраняется в
// заметке операции и открывается обычным браузером. Защищает сам ключ — 32
// случайных байта, перебрать который нельзя.
func (h *Handler) downloadAttachment(w http.ResponseWriter, r *http.Request) {
	attachment, storageKey, err := h.repo.AttachmentByPublicKey(r.Context(), chi.URLParam(r, "key"))
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	body, err := h.store.Open(storageKey)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	defer body.Close()

	w.Header().Set("Content-Type", attachment.MimeType)
	w.Header().Set("Content-Disposition", "inline; filename=\""+attachment.Name+"\"")
	w.Header().Set("Cache-Control", "private, max-age=86400")
	if _, err := io.Copy(w, body); err != nil {
		h.log.Error("send attachment", "key", attachment.PublicKey, "error", err)
	}
}

func (h *Handler) attachmentURL(r *http.Request, publicKey string) string {
	scheme := "https"
	// За обратным прокси запрос приходит по http, а наружу смотрит https —
	// заголовок ставит сам прокси, поэтому ему верим.
	if forwarded := r.Header.Get("X-Forwarded-Proto"); forwarded != "" {
		scheme = forwarded
	} else if r.TLS == nil {
		scheme = "http"
	}
	return fmt.Sprintf("%s://%s/a/%s", scheme, r.Host, publicKey)
}

func newPublicKey() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", fmt.Errorf("attachment public key: %w", err)
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func mimeTypeFor(name string) string {
	switch strings.ToLower(filepath.Ext(name)) {
	case ".jpg", ".jpeg":
		return "image/jpeg"
	case ".png":
		return "image/png"
	case ".gif":
		return "image/gif"
	case ".webp":
		return "image/webp"
	case ".heic":
		return "image/heic"
	case ".pdf":
		return "application/pdf"
	case ".csv":
		return "text/csv"
	case ".txt":
		return "text/plain"
	default:
		return "application/octet-stream"
	}
}
