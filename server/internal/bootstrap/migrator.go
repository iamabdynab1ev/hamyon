package bootstrap

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Migrator прогоняет .sql файлы из каталога миграций по возрастанию номера в
// имени и запоминает применённые версии, чтобы повторный запуск ничего не делал.
// Формат файлов совпадает с goose, используется только секция Up.
type Migrator struct {
	pool *pgxpool.Pool
}

func NewMigrator(pool *pgxpool.Pool) *Migrator { return &Migrator{pool: pool} }

func (m *Migrator) Up(ctx context.Context, dir string) error {
	if _, err := m.pool.Exec(ctx,
		`CREATE TABLE IF NOT EXISTS schema_migrations (
			version    BIGINT PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
		)`); err != nil {
		return fmt.Errorf("bootstrap migrate ensure table: %w", err)
	}

	applied, err := m.appliedVersions(ctx)
	if err != nil {
		return err
	}

	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("bootstrap migrate read dir %q: %w", dir, err)
	}

	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".sql") {
			names = append(names, entry.Name())
		}
	}
	sort.Strings(names)

	for _, name := range names {
		version, err := versionFromName(name)
		if err != nil {
			return err
		}
		if applied[version] {
			continue
		}

		raw, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return fmt.Errorf("bootstrap migrate read %q: %w", name, err)
		}

		statements := upSection(string(raw))
		if strings.TrimSpace(statements) == "" {
			return fmt.Errorf("bootstrap migrate %q: empty Up section", name)
		}

		tx, err := m.pool.Begin(ctx)
		if err != nil {
			return fmt.Errorf("bootstrap migrate begin %q: %w", name, err)
		}
		if _, err := tx.Exec(ctx, statements); err != nil {
			tx.Rollback(ctx)
			return fmt.Errorf("bootstrap migrate apply %q: %w", name, err)
		}
		if _, err := tx.Exec(ctx, `INSERT INTO schema_migrations (version) VALUES ($1)`, version); err != nil {
			tx.Rollback(ctx)
			return fmt.Errorf("bootstrap migrate record %q: %w", name, err)
		}
		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("bootstrap migrate commit %q: %w", name, err)
		}
	}
	return nil
}

func (m *Migrator) appliedVersions(ctx context.Context) (map[int64]bool, error) {
	rows, err := m.pool.Query(ctx, `SELECT version FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("bootstrap migrate applied versions: %w", err)
	}
	defer rows.Close()

	applied := make(map[int64]bool)
	for rows.Next() {
		var version int64
		if err := rows.Scan(&version); err != nil {
			return nil, fmt.Errorf("bootstrap migrate scan version: %w", err)
		}
		applied[version] = true
	}
	return applied, rows.Err()
}

func versionFromName(name string) (int64, error) {
	prefix, _, found := strings.Cut(name, "_")
	if !found {
		return 0, fmt.Errorf("bootstrap migrate: %q must be named <version>_<name>.sql", name)
	}
	version, err := strconv.ParseInt(prefix, 10, 64)
	if err != nil {
		return 0, fmt.Errorf("bootstrap migrate: %q has non-numeric version: %w", name, err)
	}
	return version, nil
}

func upSection(content string) string {
	_, after, found := strings.Cut(content, "-- +goose Up")
	if !found {
		return content
	}
	if before, _, found := strings.Cut(after, "-- +goose Down"); found {
		after = before
	}
	replacer := strings.NewReplacer("-- +goose StatementBegin", "", "-- +goose StatementEnd", "")
	return replacer.Replace(after)
}
