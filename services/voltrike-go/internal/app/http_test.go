package app

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/voltrike/voltrike-go/internal/config"
)

func TestHTTPHealthAndLocalInternalAuthentication(t *testing.T) {
	server := &HTTPServer{
		cfg: config.Config{
			LocalInternalKey:   "internal-test-key",
			MaximumRequestBody: 1024,
		},
		service: &Service{},
	}
	health := httptest.NewRecorder()
	server.routes().ServeHTTP(
		health,
		httptest.NewRequest(http.MethodGet, "/healthz", nil),
	)
	if health.Code != http.StatusOK {
		t.Fatalf("health status=%d", health.Code)
	}

	unauthorized := httptest.NewRecorder()
	server.routes().ServeHTTP(
		unauthorized,
		httptest.NewRequest(http.MethodPost, "/v1/policy/invalidate", nil),
	)
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d", unauthorized.Code)
	}

	authorizedRequest := httptest.NewRequest(
		http.MethodPost,
		"/v1/policy/invalidate",
		nil,
	)
	authorizedRequest.Header.Set("X-Voltrike-Internal-Key", "internal-test-key")
	authorized := httptest.NewRecorder()
	server.routes().ServeHTTP(authorized, authorizedRequest)
	if authorized.Code != http.StatusOK {
		t.Fatalf("authorized status=%d", authorized.Code)
	}
}
