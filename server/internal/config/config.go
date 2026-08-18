package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr       string
	DatabaseURL    string
	MigrationsDir  string
	StorageDir     string
	JWTSecret      []byte
	TokenTTL       time.Duration
	MaxUploadSize  int64
	AllowedOrigins []string
}

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:      env("HTTP_ADDR", ":8080"),
		DatabaseURL:   os.Getenv("DATABASE_URL"),
		MigrationsDir: env("MIGRATIONS_DIR", "migrations"),
		StorageDir:    env("STORAGE_DIR", "data/files"),
		JWTSecret:     []byte(os.Getenv("JWT_SECRET")),
		TokenTTL:      30 * 24 * time.Hour,
		MaxUploadSize: 256 << 20,
		// Веб-версия приложения живёт на другом порту, поэтому без CORS браузер
		// не пустит её к API. По умолчанию разрешаем всё: запросы авторизуются
		// токеном в заголовке, а не cookie, так что подделать их с чужого сайта
		// нельзя. Для рабочего сервера список стоит сузить.
		AllowedOrigins: strings.Split(env("CORS_ORIGINS", "*"), ","),
	}

	if strings.TrimSpace(cfg.DatabaseURL) == "" {
		return Config{}, fmt.Errorf("config: DATABASE_URL is required")
	}
	// Токены подписываются этим ключом, поэтому пустой или короткий секрет
	// означал бы, что кто угодно может выписать себе доступ к чужой семье.
	if len(cfg.JWTSecret) < 32 {
		return Config{}, fmt.Errorf("config: JWT_SECRET must be at least 32 bytes")
	}

	if raw := os.Getenv("TOKEN_TTL_HOURS"); raw != "" {
		hours, err := strconv.Atoi(raw)
		if err != nil || hours <= 0 {
			return Config{}, fmt.Errorf("config: invalid TOKEN_TTL_HOURS %q", raw)
		}
		cfg.TokenTTL = time.Duration(hours) * time.Hour
	}

	return cfg, nil
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
