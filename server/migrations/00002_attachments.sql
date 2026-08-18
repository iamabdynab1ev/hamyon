-- +goose Up
-- +goose StatementBegin

-- Вложения к операциям: фото чека или файл. В заметке операции хранится ссылка,
-- поэтому файл должен открываться по обычному URL, без заголовка авторизации.
-- Доступ даёт public_key — случайная строка, которую нельзя подобрать.
CREATE TABLE attachments (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    family_id   UUID        NOT NULL REFERENCES families (id) ON DELETE CASCADE,
    user_id     UUID        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    public_key  TEXT        NOT NULL UNIQUE,
    name        TEXT        NOT NULL,
    mime_type   TEXT        NOT NULL,
    size_bytes  BIGINT      NOT NULL,
    storage_key TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX attachments_family_id_idx ON attachments (family_id);

-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
DROP TABLE IF EXISTS attachments;
-- +goose StatementEnd
