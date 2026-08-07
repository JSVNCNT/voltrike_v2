package main

import (
	"log/slog"
	"strings"
	"time"

	"github.com/getsentry/sentry-go"
	"github.com/voltrike/voltrike-go/internal/config"
)

func initializeErrorMonitoring(cfg config.Config) func() {
	err := sentry.Init(sentry.ClientOptions{
		Dsn:              cfg.SentryDSN,
		Environment:      cfg.SentryEnvironment,
		Release:          cfg.SentryRelease,
		AttachStacktrace: true,
		SendDefaultPII:   false,
		EnableTracing:    cfg.SentryDSN != "" && cfg.SentryTracesSampleRate > 0,
		TracesSampleRate: cfg.SentryTracesSampleRate,
		DisableLogs:      true,
		MaxBreadcrumbs:   50,
		BeforeSend:       scrubSentryEvent,
	})
	if err != nil {
		slog.Warn("Sentry monitoring initialization failed", "error", err)
	} else if cfg.SentryDSN != "" {
		slog.Info("Sentry error monitoring enabled", "environment", cfg.SentryEnvironment)
	}
	return func() {
		if cfg.SentryDSN != "" {
			sentry.Flush(2 * time.Second)
		}
	}
}

func captureStartupError(label string, err error) {
	if err == nil {
		return
	}
	sentry.WithScope(func(scope *sentry.Scope) {
		scope.SetTag("startup_stage", label)
		sentry.CaptureException(err)
	})
	sentry.Flush(2 * time.Second)
}

func scrubSentryEvent(event *sentry.Event, _ *sentry.EventHint) *sentry.Event {
	event.User = sentry.User{}
	for _, breadcrumb := range event.Breadcrumbs {
		breadcrumb.Data = nil
	}
	if event.Request == nil {
		return event
	}
	event.Request.Data = ""
	event.Request.QueryString = ""
	event.Request.Cookies = ""
	for header := range event.Request.Headers {
		switch strings.ToLower(header) {
		case "accept", "content-type", "user-agent", "host":
		default:
			delete(event.Request.Headers, header)
		}
	}
	return event
}
