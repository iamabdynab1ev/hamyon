package repository

import (
	"context"
	"errors"
	"fmt"

	"cashew-server/internal/domain"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

const uniqueViolation = "23505"

type Repository struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

// CreateFamilyWithOwner заводит семью и её владельца одной транзакцией: семья без
// владельца никому не нужна, а владелец без семьи не смог бы войти.
func (r *Repository) CreateFamilyWithOwner(ctx context.Context, familyName, joinCode, login, name, passwordHash string) (domain.User, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return domain.User{}, fmt.Errorf("repository create family begin: %w", err)
	}
	defer tx.Rollback(ctx)

	var familyID string
	err = tx.QueryRow(ctx,
		`INSERT INTO families (name, join_code) VALUES ($1, $2) RETURNING id`,
		familyName, joinCode,
	).Scan(&familyID)
	if err != nil {
		return domain.User{}, fmt.Errorf("repository create family: %w", err)
	}

	user, err := insertUser(ctx, tx, familyID, login, name, passwordHash, domain.RoleOwner)
	if err != nil {
		return domain.User{}, err
	}

	if err := tx.Commit(ctx); err != nil {
		return domain.User{}, fmt.Errorf("repository create family commit: %w", err)
	}
	return user, nil
}

func (r *Repository) JoinFamily(ctx context.Context, joinCode, login, name, passwordHash string) (domain.User, error) {
	var familyID string
	err := r.pool.QueryRow(ctx, `SELECT id FROM families WHERE join_code = $1`, joinCode).Scan(&familyID)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("repository join family lookup: %w", err)
	}
	return insertUser(ctx, r.pool, familyID, login, name, passwordHash, domain.RoleMember)
}

type querier interface {
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

func insertUser(ctx context.Context, q querier, familyID, login, name, passwordHash string, role domain.Role) (domain.User, error) {
	user := domain.User{FamilyID: familyID, Login: login, Name: name, Role: role}
	err := q.QueryRow(ctx,
		`INSERT INTO users (family_id, login, name, password_hash, role)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, is_active, created_at`,
		familyID, login, name, passwordHash, role,
	).Scan(&user.ID, &user.IsActive, &user.CreatedAt)

	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return domain.User{}, domain.ErrLoginTaken
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("repository insert user: %w", err)
	}
	return user, nil
}

func (r *Repository) UserByLogin(ctx context.Context, login string) (domain.User, string, error) {
	var user domain.User
	var passwordHash string
	err := r.pool.QueryRow(ctx,
		`SELECT id, family_id, login, name, password_hash, role, is_active, created_at
		   FROM users WHERE login = $1`,
		login,
	).Scan(&user.ID, &user.FamilyID, &user.Login, &user.Name, &passwordHash,
		&user.Role, &user.IsActive, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, "", domain.ErrNotFound
	}
	if err != nil {
		return domain.User{}, "", fmt.Errorf("repository user by login: %w", err)
	}
	return user, passwordHash, nil
}

func (r *Repository) UserByID(ctx context.Context, id string) (domain.User, error) {
	var user domain.User
	err := r.pool.QueryRow(ctx,
		`SELECT id, family_id, login, name, role, is_active, created_at
		   FROM users WHERE id = $1`,
		id,
	).Scan(&user.ID, &user.FamilyID, &user.Login, &user.Name, &user.Role, &user.IsActive, &user.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.User{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.User{}, fmt.Errorf("repository user by id: %w", err)
	}
	return user, nil
}

func (r *Repository) Family(ctx context.Context, id string) (domain.Family, error) {
	var family domain.Family
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, join_code, created_at FROM families WHERE id = $1`, id,
	).Scan(&family.ID, &family.Name, &family.JoinCode, &family.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.Family{}, domain.ErrNotFound
	}
	if err != nil {
		return domain.Family{}, fmt.Errorf("repository family: %w", err)
	}
	return family, nil
}

func (r *Repository) Members(ctx context.Context, familyID string) ([]domain.User, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, family_id, login, name, role, is_active, created_at
		   FROM users WHERE family_id = $1 ORDER BY role, created_at`,
		familyID,
	)
	if err != nil {
		return nil, fmt.Errorf("repository members: %w", err)
	}
	defer rows.Close()

	members := make([]domain.User, 0, 8)
	for rows.Next() {
		var user domain.User
		if err := rows.Scan(&user.ID, &user.FamilyID, &user.Login, &user.Name,
			&user.Role, &user.IsActive, &user.CreatedAt); err != nil {
			return nil, fmt.Errorf("repository members scan: %w", err)
		}
		members = append(members, user)
	}
	return members, rows.Err()
}

func (r *Repository) SetMemberActive(ctx context.Context, familyID, userID string, active bool) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE users SET is_active = $1 WHERE id = $2 AND family_id = $3 AND role <> 'owner'`,
		active, userID, familyID,
	)
	if err != nil {
		return fmt.Errorf("repository set member active: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return domain.ErrNotFound
	}
	return nil
}

func (r *Repository) UpsertSyncFile(ctx context.Context, familyID, userID, name, kind, storageKey string, size int64) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO sync_files (family_id, user_id, name, kind, size_bytes, storage_key)
		 VALUES ($1, $2, $3, $4, $5, $6)
		 ON CONFLICT (family_id, name) DO UPDATE
		 SET user_id = EXCLUDED.user_id,
		     kind = EXCLUDED.kind,
		     size_bytes = EXCLUDED.size_bytes,
		     storage_key = EXCLUDED.storage_key,
		     updated_at = now()`,
		familyID, userID, name, kind, size, storageKey,
	)
	if err != nil {
		return fmt.Errorf("repository upsert sync file: %w", err)
	}
	return nil
}

// SyncFiles возвращает файлы семьи вместе с именем владельца устройства, чтобы
// приложение могло показать, чьи именно изменения оно подтягивает.
func (r *Repository) SyncFiles(ctx context.Context, familyID, kind string) ([]domain.SyncFile, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT f.id, f.name, f.kind, f.size_bytes, f.user_id, u.name, f.updated_at
		   FROM sync_files f
		   JOIN users u ON u.id = f.user_id
		  WHERE f.family_id = $1 AND ($2 = '' OR f.kind = $2)
		  ORDER BY f.updated_at DESC`,
		familyID, kind,
	)
	if err != nil {
		return nil, fmt.Errorf("repository sync files: %w", err)
	}
	defer rows.Close()

	files := make([]domain.SyncFile, 0, 8)
	for rows.Next() {
		var file domain.SyncFile
		if err := rows.Scan(&file.ID, &file.Name, &file.Kind, &file.SizeBytes,
			&file.OwnerID, &file.OwnerName, &file.UpdatedAt); err != nil {
			return nil, fmt.Errorf("repository sync files scan: %w", err)
		}
		files = append(files, file)
	}
	return files, rows.Err()
}

func (r *Repository) SyncFileByName(ctx context.Context, familyID, name string) (domain.SyncFile, string, error) {
	var file domain.SyncFile
	var storageKey string
	err := r.pool.QueryRow(ctx,
		`SELECT f.id, f.name, f.kind, f.size_bytes, f.user_id, u.name, f.updated_at, f.storage_key
		   FROM sync_files f
		   JOIN users u ON u.id = f.user_id
		  WHERE f.family_id = $1 AND f.name = $2`,
		familyID, name,
	).Scan(&file.ID, &file.Name, &file.Kind, &file.SizeBytes, &file.OwnerID,
		&file.OwnerName, &file.UpdatedAt, &storageKey)
	if errors.Is(err, pgx.ErrNoRows) {
		return domain.SyncFile{}, "", domain.ErrNotFound
	}
	if err != nil {
		return domain.SyncFile{}, "", fmt.Errorf("repository sync file by name: %w", err)
	}
	return file, storageKey, nil
}

func (r *Repository) DeleteSyncFile(ctx context.Context, familyID, name string) (string, error) {
	var storageKey string
	err := r.pool.QueryRow(ctx,
		`DELETE FROM sync_files WHERE family_id = $1 AND name = $2 RETURNING storage_key`,
		familyID, name,
	).Scan(&storageKey)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", domain.ErrNotFound
	}
	if err != nil {
		return "", fmt.Errorf("repository delete sync file: %w", err)
	}
	return storageKey, nil
}
