package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Store держит содержимое sync-файлов на диске. Ключ выводится из идентификатора
// семьи и имени файла, поэтому имя, пришедшее от клиента, никогда не попадает в
// путь напрямую и не может увести запись за пределы каталога.
type Store struct {
	root string
}

func New(root string) (*Store, error) {
	if err := os.MkdirAll(root, 0o750); err != nil {
		return nil, fmt.Errorf("storage init %q: %w", root, err)
	}
	return &Store{root: root}, nil
}

func (s *Store) Key(familyID, name string) string {
	sum := sha256.Sum256([]byte(name))
	return filepath.Join(familyID, hex.EncodeToString(sum[:])+".bin")
}

func (s *Store) Save(key string, src io.Reader) (int64, error) {
	path := filepath.Join(s.root, key)
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return 0, fmt.Errorf("storage save mkdir: %w", err)
	}

	// Пишем во временный файл и переименовываем: если загрузка оборвётся,
	// прежняя версия останется целой, а не превратится в обрезанный файл.
	tmp, err := os.CreateTemp(filepath.Dir(path), ".upload-*")
	if err != nil {
		return 0, fmt.Errorf("storage save temp: %w", err)
	}
	defer os.Remove(tmp.Name())

	written, err := io.Copy(tmp, src)
	if err != nil {
		tmp.Close()
		return 0, fmt.Errorf("storage save copy: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return 0, fmt.Errorf("storage save close: %w", err)
	}
	if err := os.Rename(tmp.Name(), path); err != nil {
		return 0, fmt.Errorf("storage save rename: %w", err)
	}
	return written, nil
}

func (s *Store) Open(key string) (io.ReadCloser, error) {
	file, err := os.Open(filepath.Join(s.root, key))
	if err != nil {
		return nil, fmt.Errorf("storage open: %w", err)
	}
	return file, nil
}

func (s *Store) Remove(key string) error {
	if err := os.Remove(filepath.Join(s.root, key)); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("storage remove: %w", err)
	}
	return nil
}
