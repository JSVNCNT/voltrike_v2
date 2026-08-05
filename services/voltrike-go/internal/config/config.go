package config

import (
	"encoding/base64"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	Port                      string
	ProjectID                 string
	DatabaseURL               string
	GoogleRoutesAPIKey        string
	QuoteEncryptionKey        []byte
	PolicyCacheTTL            time.Duration
	RequestTimeout            time.Duration
	MaximumRequestBody        int64
	LocalInternalKey          string
	AllowedOrigins            string
	RequireAppCheck           bool
	AllowUnauthenticatedLocal bool
	DispatchCellDegrees       float64
	DispatchRadiusMeters      float64
	MaximumDispatchResults    int
}

func Load() (Config, error) {
	projectID := first(value("GOOGLE_CLOUD_PROJECT", ""), value("GCLOUD_PROJECT", ""))
	cfg := Config{
		Port:                      value("PORT", "8080"),
		ProjectID:                 projectID,
		DatabaseURL:               value("FIREBASE_DATABASE_URL", ""),
		GoogleRoutesAPIKey:        value("GOOGLE_ROUTES_API_KEY", ""),
		PolicyCacheTTL:            duration("POLICY_CACHE_TTL_SECONDS", 60*time.Second),
		RequestTimeout:            duration("REQUEST_TIMEOUT_SECONDS", 10*time.Second),
		MaximumRequestBody:        int64(number("MAX_REQUEST_BYTES", 128*1024)),
		LocalInternalKey:          value("GO_LOCAL_INTERNAL_KEY", ""),
		AllowedOrigins:            value("GO_ALLOWED_ORIGINS", "http://127.0.0.1:5173,http://localhost:5173"),
		RequireAppCheck:           boolValue("GO_REQUIRE_APP_CHECK", projectID != "demo-voltrike"),
		AllowUnauthenticatedLocal: boolValue("GO_ALLOW_UNAUTHENTICATED_LOCAL", false),
		// Must match functions/dispatch-spatial-index.js.
		DispatchCellDegrees:    0.05,
		DispatchRadiusMeters:   decimal("DISPATCH_RADIUS_METERS", 5000),
		MaximumDispatchResults: number("MAX_DISPATCH_RESULTS", 40),
	}
	if cfg.ProjectID == "" {
		return Config{}, fmt.Errorf("GOOGLE_CLOUD_PROJECT is required")
	}
	if cfg.AllowUnauthenticatedLocal && cfg.ProjectID != "demo-voltrike" {
		return Config{}, fmt.Errorf("GO_ALLOW_UNAUTHENTICATED_LOCAL is only allowed for demo-voltrike")
	}
	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("FIREBASE_DATABASE_URL is required")
	}
	if cfg.GoogleRoutesAPIKey == "" {
		return Config{}, fmt.Errorf("GOOGLE_ROUTES_API_KEY is required")
	}
	if encoded := value("GO_QUOTE_ENCRYPTION_KEY", ""); encoded != "" {
		key, err := base64.RawURLEncoding.DecodeString(encoded)
		if err != nil {
			key, err = base64.StdEncoding.DecodeString(encoded)
		}
		if err != nil || len(key) != 32 {
			return Config{}, fmt.Errorf("GO_QUOTE_ENCRYPTION_KEY must be base64 encoded 32 bytes")
		}
		cfg.QuoteEncryptionKey = key
	}
	if cfg.PolicyCacheTTL < time.Second || cfg.PolicyCacheTTL > 10*time.Minute {
		return Config{}, fmt.Errorf("POLICY_CACHE_TTL_SECONDS must be between 1 and 600")
	}
	if cfg.RequestTimeout < time.Second || cfg.RequestTimeout > 30*time.Second {
		return Config{}, fmt.Errorf("REQUEST_TIMEOUT_SECONDS must be between 1 and 30")
	}
	if cfg.DispatchCellDegrees <= 0 || cfg.DispatchCellDegrees > 1 || cfg.DispatchRadiusMeters <= 0 || cfg.MaximumDispatchResults < 1 || cfg.MaximumDispatchResults > 200 {
		return Config{}, fmt.Errorf("invalid dispatch configuration")
	}
	return cfg, nil
}

func boolValue(key string, fallback bool) bool {
	raw := strings.ToLower(value(key, ""))
	if raw == "" {
		return fallback
	}
	return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
}

func value(key, fallback string) string {
	if result := strings.TrimSpace(os.Getenv(key)); result != "" {
		return result
	}
	return fallback
}

func first(values ...string) string {
	for _, item := range values {
		if item != "" {
			return item
		}
	}
	return ""
}

func number(key string, fallback int) int {
	if raw := value(key, ""); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil {
			return parsed
		}
	}
	return fallback
}

func decimal(key string, fallback float64) float64 {
	if raw := value(key, ""); raw != "" {
		if parsed, err := strconv.ParseFloat(raw, 64); err == nil {
			return parsed
		}
	}
	return fallback
}

func duration(key string, fallback time.Duration) time.Duration {
	return time.Duration(number(key, int(fallback/time.Second))) * time.Second
}
