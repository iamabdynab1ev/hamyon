package domain

import (
	"errors"
	"time"
)

type Role string

const (
	RoleOwner  Role = "owner"
	RoleMember Role = "member"
)

type Family struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	JoinCode  string    `json:"joinCode"`
	CreatedAt time.Time `json:"createdAt"`
}

type User struct {
	ID        string    `json:"id"`
	FamilyID  string    `json:"familyId"`
	Login     string    `json:"login"`
	Name      string    `json:"name"`
	Role      Role      `json:"role"`
	IsActive  bool      `json:"isActive"`
	CreatedAt time.Time `json:"createdAt"`
}

// SyncFile описывает выложенный устройством файл изменений или резервную копию.
// Содержимое лежит в файловом хранилище, здесь только метаданные.
type SyncFile struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Kind      string    `json:"kind"`
	SizeBytes int64     `json:"sizeBytes"`
	OwnerID   string    `json:"ownerId"`
	OwnerName string    `json:"ownerName"`
	UpdatedAt time.Time `json:"updatedAt"`
}

var (
	ErrNotFound       = errors.New("not found")
	ErrLoginTaken     = errors.New("login already taken")
	ErrBadCredentials = errors.New("invalid login or password")
	ErrForbidden      = errors.New("forbidden")
)
