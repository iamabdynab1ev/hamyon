package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"cashew-server/internal/bootstrap"
	"cashew-server/internal/config"
	httphandler "cashew-server/internal/handler/http"
	"cashew-server/internal/repository"
	"cashew-server/internal/storage"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	if err := run(log); err != nil {
		log.Error("server stopped", "error", err)
		os.Exit(1)
	}
}

func run(log *slog.Logger) error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	// База может подниматься дольше сервера, поэтому даём ей время ответить,
	// вместо того чтобы падать на первой же неудачной попытке.
	if err := waitForDatabase(ctx, pool, log); err != nil {
		return err
	}

	if err := bootstrap.NewMigrator(pool).Up(ctx, cfg.MigrationsDir); err != nil {
		return err
	}
	log.Info("migrations applied")

	store, err := storage.New(cfg.StorageDir)
	if err != nil {
		return err
	}

	handler := httphandler.New(cfg, repository.New(pool), store, log)
	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           handler.Routes(),
		ReadHeaderTimeout: 10 * time.Second,
		WriteTimeout:      5 * time.Minute,
		IdleTimeout:       2 * time.Minute,
	}

	serverErrors := make(chan error, 1)
	go func() {
		log.Info("listening", "addr", cfg.HTTPAddr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			serverErrors <- err
		}
	}()

	select {
	case err := <-serverErrors:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}

func waitForDatabase(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger) error {
	const attempts = 30

	var lastErr error
	for attempt := 1; attempt <= attempts; attempt++ {
		if err := pool.Ping(ctx); err == nil {
			return nil
		} else {
			lastErr = err
		}
		log.Info("waiting for database", "attempt", attempt)

		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}
	return lastErr
}
