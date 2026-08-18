package http

import (
	"io"
	"net/http"
	"path"
	"strings"

	"cashew-server/internal/auth"

	"github.com/go-chi/chi/v5"
)

func (h *Handler) listSyncFiles(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	kind := r.URL.Query().Get("kind")
	if kind != "" && kind != "sync" && kind != "backup" {
		writeError(w, http.StatusBadRequest, "kind must be sync or backup")
		return
	}

	files, err := h.repo.SyncFiles(r.Context(), identity.FamilyID, kind)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"files": files})
}

func (h *Handler) uploadSyncFile(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	name, ok := safeFileName(w, chi.URLParam(r, "name"))
	if !ok {
		return
	}
	kind := "sync"
	if strings.HasPrefix(name, "backup") {
		kind = "backup"
	}

	storageKey := h.store.Key(identity.FamilyID, name)
	size, err := h.store.Save(storageKey, http.MaxBytesReader(w, r.Body, h.cfg.MaxUploadSize))
	if err != nil {
		h.writeDomainError(w, err)
		return
	}

	if err := h.repo.UpsertSyncFile(r.Context(), identity.FamilyID, identity.UserID,
		name, kind, storageKey, size); err != nil {
		h.writeDomainError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"name": name, "sizeBytes": size})
}

func (h *Handler) downloadSyncFile(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	name, ok := safeFileName(w, chi.URLParam(r, "name"))
	if !ok {
		return
	}

	file, storageKey, err := h.repo.SyncFileByName(r.Context(), identity.FamilyID, name)
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

	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Last-Modified", file.UpdatedAt.UTC().Format(http.TimeFormat))
	if _, err := io.Copy(w, body); err != nil {
		h.log.Error("send sync file", "name", name, "error", err)
	}
}

func (h *Handler) deleteSyncFile(w http.ResponseWriter, r *http.Request) {
	identity, _ := auth.IdentityFrom(r.Context())

	name, ok := safeFileName(w, chi.URLParam(r, "name"))
	if !ok {
		return
	}

	file, _, err := h.repo.SyncFileByName(r.Context(), identity.FamilyID, name)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	// Свой файл участник убирает сам, чужие трогает только владелец.
	if file.OwnerID != identity.UserID && !identity.IsOwner() {
		writeError(w, http.StatusForbidden, "only the owner can delete other devices' files")
		return
	}

	storageKey, err := h.repo.DeleteSyncFile(r.Context(), identity.FamilyID, name)
	if err != nil {
		h.writeDomainError(w, err)
		return
	}
	if err := h.store.Remove(storageKey); err != nil {
		h.log.Error("remove sync file", "name", name, "error", err)
	}

	w.WriteHeader(http.StatusNoContent)
}

// safeFileName отсекает имена с путями: имя приходит из URL и попадает в базу,
// а хранилище берёт от него хеш, так что подниматься по каталогам нечем, но и
// хранить «../» как имя файла незачем.
func safeFileName(w http.ResponseWriter, raw string) (string, bool) {
	name := strings.TrimSpace(raw)
	if name == "" || name != path.Base(name) || strings.ContainsAny(name, `/\`) || strings.HasPrefix(name, ".") {
		writeError(w, http.StatusBadRequest, "invalid file name")
		return "", false
	}
	if len(name) > 200 {
		writeError(w, http.StatusBadRequest, "file name is too long")
		return "", false
	}
	return name, true
}
