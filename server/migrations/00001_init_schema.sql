-- +goose Up
-- +goose StatementBegin

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Владелец видит и правит всё в своей семье, участник работает только со своими
-- операциями. Роль хранится на сервере, приложение её только читает.
CREATE TYPE member_role AS ENUM ('owner', 'member');

CREATE TABLE families (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT        NOT NULL,
    join_code  TEXT        NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id     UUID        NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    login         TEXT        NOT NULL UNIQUE,
    name          TEXT        NOT NULL,
    password_hash TEXT        NOT NULL,
    role          member_role NOT NULL DEFAULT 'member',
    is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX users_family_id_idx ON users (family_id);

-- Приложение синхронизируется, обмениваясь файлами SQLite: каждое устройство
-- выкладывает свои изменения под именем sync-<clientID>.sqlite, остальные их
-- забирают и сливают у себя. Сервер хранит эти файлы и не заглядывает внутрь.
CREATE TABLE sync_files (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id   UUID        NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name        TEXT        NOT NULL,
    kind        TEXT        NOT NULL CHECK (kind IN ('sync', 'backup')),
    size_bytes  BIGINT      NOT NULL,
    storage_key TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (family_id, name)
);

CREATE INDEX sync_files_family_kind_idx ON sync_files (family_id, kind);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS sync_files;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS families;
DROP TYPE IF EXISTS member_role;
-- +goose StatementEnd
