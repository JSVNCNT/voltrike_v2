package app

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/voltrike/voltrike-go/internal/config"
)

type integrationHTTPStore struct {
	email, event string
	err          error
	retried      bool
}

func (*integrationHTTPStore) LoadPolicy(context.Context) (Policy, error) { return Policy{}, nil }
func (*integrationHTTPStore) ReadDispatchCell(context.Context, string) (map[string]DispatchPresence, error) {
	return nil, nil
}
func (store *integrationHTTPStore) RequestPasswordReset(_ context.Context, email string) (map[string]any, error) {
	store.email = email
	return map[string]any{"accepted": true}, store.err
}
func (store *integrationHTTPStore) ProcessOutbox(_ context.Context, event string) (map[string]any, error) {
	store.event = event
	return map[string]any{"processed": true}, store.err
}
func (store *integrationHTTPStore) RetryOutbox(context.Context) (map[string]any, error) {
	store.retried = true
	return map[string]any{"processed": 1}, nil
}

func (*integrationHTTPStore) ExecuteOperation(context.Context, Principal, OperationCommand) (map[string]any, error) {
	return map[string]any{"registered": true}, nil
}

func TestPasswordRecoveryDoesNotRequireSignedInUser(t *testing.T) {
	store := &integrationHTTPStore{}
	server := &HTTPServer{cfg: config.Config{MaximumRequestBody: 1024}, service: &Service{store: store}}
	response := httptest.NewRecorder()
	server.routes().ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/auth/password-reset", strings.NewReader(`{"email":"person@example.com"}`)))
	if response.Code != http.StatusOK || store.email != "person@example.com" || !strings.Contains(response.Body.String(), `"accepted":true`) {
		t.Fatalf("signed-out recovery failed: status=%d body=%s", response.Code, response.Body.String())
	}
	store.err = ErrUnavailable
	response = httptest.NewRecorder()
	server.routes().ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/auth/password-reset", strings.NewReader(`{"email":"person@example.com"}`)))
	if response.Code != http.StatusServiceUnavailable || !strings.Contains(response.Body.String(), `"unavailable"`) {
		t.Fatalf("provider failure must allow client Firebase fallback: %d %s", response.Code, response.Body.String())
	}
}

func TestWorkerOnlyConsumesValidatedProjectOutboxEvents(t *testing.T) {
	for _, scenario := range []struct {
		name, source, subject, eventType string
		enabled                          bool
		status                           int
	}{
		{"valid", "//firestore.googleapis.com/projects/demo-voltrike/databases/(default)", "documents/outbox/event-1", "google.cloud.firestore.document.v1.created", true, 200},
		{"wrong project", "//firestore.googleapis.com/projects/other/databases/(default)", "documents/outbox/event-1", "google.cloud.firestore.document.v1.created", true, 400},
		{"wrong collection", "//firestore.googleapis.com/projects/demo-voltrike/databases/(default)", "documents/users/event-1", "google.cloud.firestore.document.v1.created", true, 400},
		{"nested path", "//firestore.googleapis.com/projects/demo-voltrike/databases/(default)", "documents/outbox/event-1/extra", "google.cloud.firestore.document.v1.created", true, 400},
		{"wrong event", "//firestore.googleapis.com/projects/demo-voltrike/databases/(default)", "documents/outbox/event-1", "google.cloud.firestore.document.v1.updated", true, 400},
		{"cutover disabled", "//firestore.googleapis.com/projects/demo-voltrike/databases/(default)", "documents/outbox/event-1", "google.cloud.firestore.document.v1.created", false, 503},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			store := &integrationHTTPStore{}
			server := &HTTPServer{cfg: config.Config{ProjectID: "demo-voltrike", IntegrationWorker: true, NotificationsEnabled: scenario.enabled}, service: &Service{store: store}}
			request := httptest.NewRequest(http.MethodPost, "/events/outbox", strings.NewReader("protobuf payload is deliberately not trusted"))
			request.Header.Set("Ce-Id", "delivery-1")
			request.Header.Set("Ce-Type", scenario.eventType)
			request.Header.Set("Ce-Source", scenario.source)
			request.Header.Set("Ce-Subject", scenario.subject)
			response := httptest.NewRecorder()
			server.routes().ServeHTTP(response, request)
			if response.Code != scenario.status || (store.event != "") != (scenario.status == 200) {
				t.Fatalf("unexpected event result: status=%d event=%q", response.Code, store.event)
			}
		})
	}
}

func TestPublicAPIHasNoEventConsumerAndWorkerHasNoPublicOperations(t *testing.T) {
	for _, worker := range []bool{false, true} {
		server := &HTTPServer{cfg: config.Config{IntegrationWorker: worker, LocalInternalKey: "test"}, service: &Service{}}
		path := "/events/outbox"
		if worker {
			path = "/api/v2/operations/example"
		}
		request := httptest.NewRequest(http.MethodPost, path, nil)
		request.Header.Set("X-Voltrike-Internal-Key", "test")
		response := httptest.NewRecorder()
		server.routes().ServeHTTP(response, request)
		if response.Code != http.StatusNotFound {
			t.Fatalf("worker=%v exposed an unintended endpoint: %d", worker, response.Code)
		}
	}
}

func TestAdminPushRegistrationRequiresIdentityWithoutAppCheck(t *testing.T) {
	server := &HTTPServer{
		cfg:      config.Config{RequireAppCheck: false, MaximumRequestBody: 1024},
		service:  &Service{store: &integrationHTTPStore{}},
		verifier: testIdentityVerifier{appCheckError: errors.New("App Check must not be used")},
	}
	for _, authenticated := range []bool{false, true} {
		request := httptest.NewRequest(http.MethodPost, "/api/v2/operations/registerAdminWebPushToken", strings.NewReader(`{"commandId":"register-test","payload":{"token":"test-token"}}`))
		if authenticated {
			request.Header.Set("Authorization", "Bearer identity")
		}
		response := httptest.NewRecorder()
		server.routes().ServeHTTP(response, request)
		want := http.StatusUnauthorized
		if authenticated {
			want = http.StatusOK
		}
		if response.Code != want {
			t.Fatalf("authenticated=%v: status=%d body=%s", authenticated, response.Code, response.Body.String())
		}
	}
}

func TestEmailResendRateLimitContract(t *testing.T) {
	response := httptest.NewRecorder()
	writeServiceError(response, ErrRateLimited)
	if response.Code != 429 || response.Header().Get("Retry-After") != "60" || !strings.Contains(response.Body.String(), "resource_exhausted") {
		t.Fatalf("resend rate limit lost its contract: %d %s", response.Code, response.Body.String())
	}
}

func TestNotificationRetrySurvivesUnrelatedMaintenanceFailure(t *testing.T) {
	// This store deliberately lacks booking maintenance dependencies.
	store := &integrationHTTPStore{}
	server := &HTTPServer{cfg: config.Config{IntegrationWorker: true, NotificationsEnabled: true}, service: &Service{store: store}}
	response := httptest.NewRecorder()
	server.routes().ServeHTTP(response, httptest.NewRequest(http.MethodPost, "/tasks/maintenance", nil))
	if response.Code != http.StatusServiceUnavailable || !store.retried {
		t.Fatalf("maintenance failure starved notification recovery: status=%d retried=%v", response.Code, store.retried)
	}
}
