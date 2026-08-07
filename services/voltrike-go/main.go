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

	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/config"
	"github.com/voltrike/voltrike-go/internal/firebase"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	cfg, err := config.Load()
	if err != nil {
		slog.Error("invalid service configuration", "error", err)
		os.Exit(1)
	}
	shutdownMonitoring := initializeErrorMonitoring(cfg)
	defer shutdownMonitoring()
	store, closeStore, err := firebase.Open(ctx, cfg)
	if err != nil {
		captureStartupError("firebase_clients", err)
		slog.Error("open Firebase clients", "error", err)
		os.Exit(1)
	}
	defer closeStore()
	service, err := app.NewService(cfg, store)
	if err != nil {
		captureStartupError("service", err)
		slog.Error("create service", "error", err)
		os.Exit(1)
	}
	server := app.NewHTTPServer(cfg, service, store)
	go func() {
		slog.Info("VolTrike Go service listening", "port", cfg.Port, "project", cfg.ProjectID)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			captureStartupError("http_server", err)
			slog.Error("http server stopped", "error", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		captureStartupError("graceful_shutdown", err)
		slog.Error("graceful shutdown failed", "error", err)
	}
}
