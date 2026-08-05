package app

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/voltrike/voltrike-go/internal/config"
)

type testIdentityVerifier struct{ appCheckError error }

func (testIdentityVerifier) VerifyIDToken(context.Context, string) (Principal, error) {
	return Principal{UID: "test-user"}, nil
}

func (verifier testIdentityVerifier) VerifyAppCheck(string) error {
	return verifier.appCheckError
}

func TestV2CapabilitiesRequiresIdentity(t *testing.T) {
	server := &HTTPServer{
		cfg: config.Config{
			MaximumRequestBody:        1024,
			AllowUnauthenticatedLocal: false,
			RequireAppCheck:           false,
			AllowedOrigins:            "http://localhost:5173",
		},
		service:  &Service{},
		verifier: testIdentityVerifier{},
	}
	unauthorized := httptest.NewRecorder()
	server.routes().ServeHTTP(
		unauthorized,
		httptest.NewRequest(http.MethodGet, "/api/v2/capabilities", nil),
	)
	if unauthorized.Code != http.StatusUnauthorized {
		t.Fatalf("unauthorized status=%d", unauthorized.Code)
	}

	request := httptest.NewRequest(http.MethodGet, "/api/v2/capabilities", nil)
	request.Header.Set("Authorization", "Bearer test-token")
	authorized := httptest.NewRecorder()
	server.routes().ServeHTTP(authorized, request)
	if authorized.Code != http.StatusOK {
		t.Fatalf("authorized status=%d", authorized.Code)
	}
}

func TestV2AppCheckFailsClosed(t *testing.T) {
	server := &HTTPServer{
		cfg: config.Config{
			MaximumRequestBody: 1024,
			RequireAppCheck:    true,
			AllowedOrigins:     "http://localhost:5173",
		},
		service:  &Service{},
		verifier: testIdentityVerifier{appCheckError: errors.New("invalid app check")},
	}
	missing := httptest.NewRequest(http.MethodGet, "/api/v2/capabilities", nil)
	missing.Header.Set("Authorization", "Bearer test-token")
	missingResponse := httptest.NewRecorder()
	server.routes().ServeHTTP(missingResponse, missing)
	if missingResponse.Code != http.StatusUnauthorized {
		t.Fatalf("missing App Check status=%d", missingResponse.Code)
	}

	invalid := httptest.NewRequest(http.MethodGet, "/api/v2/capabilities", nil)
	invalid.Header.Set("Authorization", "Bearer test-token")
	invalid.Header.Set("X-Firebase-AppCheck", "invalid-token")
	invalidResponse := httptest.NewRecorder()
	server.routes().ServeHTTP(invalidResponse, invalid)
	if invalidResponse.Code != http.StatusUnauthorized {
		t.Fatalf("invalid App Check status=%d", invalidResponse.Code)
	}
}

func TestV2LocalIdentityRequiresExplicitDemoMode(t *testing.T) {
	server := &HTTPServer{
		cfg: config.Config{
			MaximumRequestBody:        1024,
			AllowUnauthenticatedLocal: true,
			RequireAppCheck:           false,
			AllowedOrigins:            "http://localhost:5173",
		},
		service: &Service{},
	}
	request := httptest.NewRequest(http.MethodGet, "/api/v2/me", nil)
	request.Header.Set("X-Debug-UID", "local-user")
	response := httptest.NewRecorder()
	server.routes().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("local identity status=%d", response.Code)
	}
}
