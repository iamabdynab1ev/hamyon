# Hamyon Server

Сервер семейной версии Hamyon: аутентификация, роли и обмен файлами
синхронизации между устройствами семьи вместо Google Drive.

## Как это работает

Приложение синхронизируется, обмениваясь файлами SQLite: каждое устройство
выкладывает свои изменения под именем `sync-<clientID>.sqlite`, остальные их
забирают и сливают у себя. Сервер хранит эти файлы по семьям и не заглядывает
внутрь — вся логика слияния остаётся в приложении.

Поэтому сводный дашборд владельца **не требует расчётов на сервере**: после
синхронизации на устройстве владельца уже лежат все операции семьи.

## Роли

| Роль | Права |
|---|---|
| `owner` | видит и удаляет файлы всех устройств семьи, управляет участниками, видит код приглашения |
| `member` | выкладывает и забирает файлы, удаляет только свои |

## Запуск

```bash
cp .env.example .env
# заполнить POSTGRES_PASSWORD и JWT_SECRET (openssl rand -base64 48)

docker compose up -d --build
curl http://localhost:8080/health
```

Без плагина `docker compose` можно поднять базу отдельно и запустить сервер локально:

```bash
docker run -d --name cashew-db -p 5432:5432 \
  -e POSTGRES_USER=cashew -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=cashew \
  postgres:16-alpine

DATABASE_URL="postgres://cashew:secret@127.0.0.1:5432/cashew?sslmode=disable" \
JWT_SECRET="$(openssl rand -base64 48)" \
go run ./cmd/server
```

Миграции применяются автоматически при старте.

## Переменные окружения

| Переменная | По умолчанию | Описание |
|---|---|---|
| `DATABASE_URL` | — | обязательна |
| `JWT_SECRET` | — | обязателен, не короче 32 символов |
| `HTTP_ADDR` | `:8080` | адрес прослушивания |
| `STORAGE_DIR` | `data/files` | где лежат файлы синхронизации |
| `MIGRATIONS_DIR` | `migrations` | каталог миграций |
| `TOKEN_TTL_HOURS` | `720` | срок жизни токена |

## API

Все методы кроме `/health` и `/auth/*` требуют заголовок
`Authorization: Bearer <token>`.

| Метод | Путь | Описание |
|---|---|---|
| `GET` | `/health` | проверка живости |
| `POST` | `/api/v1/auth/register-family` | создать семью, стать владельцем |
| `POST` | `/api/v1/auth/join-family` | войти в семью по коду приглашения |
| `POST` | `/api/v1/auth/login` | вход по логину и паролю |
| `GET` | `/api/v1/me` | текущий пользователь и семья |
| `GET` | `/api/v1/family/members` | участники семьи |
| `POST` | `/api/v1/family/members/{userID}/active` | включить или отключить участника (владелец) |
| `GET` | `/api/v1/sync/files` | файлы семьи, можно `?kind=sync\|backup` |
| `PUT` | `/api/v1/sync/files/{name}` | выложить файл (тело — содержимое) |
| `GET` | `/api/v1/sync/files/{name}` | скачать файл |
| `DELETE` | `/api/v1/sync/files/{name}` | удалить файл |

### Пример

```bash
API=http://localhost:8080/api/v1

# Владелец создаёт семью и получает код приглашения
curl -X POST $API/auth/register-family -H 'Content-Type: application/json' \
  -d '{"familyName":"Оила","login":"papa@example.com","name":"Папа","password":"parol12345"}'

# Родственник присоединяется по коду
curl -X POST $API/auth/join-family -H 'Content-Type: application/json' \
  -d '{"joinCode":"NN29ESV3","login":"son@example.com","name":"Сын","password":"parol12345"}'

# Устройство выкладывает свои изменения
curl -X PUT "$API/sync/files/sync-<clientID>.sqlite" \
  -H "Authorization: Bearer $TOKEN" --data-binary @sync.sqlite
```
