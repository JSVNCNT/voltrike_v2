package firebase

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebaseadmin "firebase.google.com/go/v4"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"google.golang.org/api/option"
)

func authIntegrationEmulatorStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	host := os.Getenv("FIRESTORE_EMULATOR_HOST")
	if host == "" {
		t.Skip("requires local FIRESTORE_EMULATOR_HOST")
	}
	if !strings.HasPrefix(host, "127.0.0.1:") && !strings.HasPrefix(host, "localhost:") {
		t.Fatal("auth integration tests must use a loopback Firestore emulator")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	client, err := firestore.NewClient(ctx, "demo-voltrike-auth-integration", option.WithoutAuthentication())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return &Store{firestore: client}, ctx
}

func TestEmulatorCommunicationRateLimitSerializesConcurrentRequestsAndExpires(t *testing.T) {
	store, ctx := authIntegrationEmulatorStore(t)
	ref := store.firestore.Collection("communicationRateLimits").Doc("test-" + uuid.NewString())
	var accepted atomic.Int32
	var requests sync.WaitGroup
	failures := make(chan error, 8)
	for range 8 {
		requests.Go(func() {
			allowed, err := store.claimCommunicationRequest(ctx, ref, map[string]any{"purpose": "test"})
			if err != nil {
				failures <- err
			}
			if allowed {
				accepted.Add(1)
			}
		})
	}
	requests.Wait()
	close(failures)
	for err := range failures {
		t.Error(err)
	}
	if accepted.Load() != 1 {
		t.Fatalf("accepted %d concurrent sends inside one resend window", accepted.Load())
	}
	snapshot, err := ref.Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	expires, ok := snapshot.Data()["expiresAt"].(time.Time)
	if !ok || time.Until(expires) < 23*time.Hour {
		t.Fatal("communication rate limit did not retain its TTL")
	}
	if _, err := ref.Update(ctx, []firestore.Update{{Path: "lastRequestedAt", Value: time.Now().Add(-61 * time.Second)}}); err != nil {
		t.Fatal(err)
	}
	if allowed, err := store.claimCommunicationRequest(ctx, ref, map[string]any{"purpose": "test"}); err != nil || !allowed {
		t.Fatalf("expired resend limit remained active: %v", err)
	}
}

func TestEmulatorAdminPushReassignmentAndRemovalRespectCurrentOwner(t *testing.T) {
	store, ctx := authIntegrationEmulatorStore(t)
	first, second, inactive := "admin-"+uuid.NewString(), "admin-"+uuid.NewString(), "inactive-"+uuid.NewString()
	for uid, active := range map[string]bool{first: true, second: true, inactive: false} {
		if _, err := store.firestore.Collection("users").Doc(uid).Set(ctx, map[string]any{"role": "toda_admin", "isActive": active, "todaId": "toda-a"}); err != nil {
			t.Fatal(err)
		}
	}
	payload := map[string]any{"token": "test-web-push-" + uuid.NewString()}
	_, id, err := adminPushToken(payload)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.updateAdminWebPushToken(ctx, app.Principal{UID: first}, payload, true); err != nil {
		t.Fatal(err)
	}
	if _, err := store.updateAdminWebPushToken(ctx, app.Principal{UID: second}, payload, true); err != nil {
		t.Fatal(err)
	}
	if _, err := store.firestore.Collection("users").Doc(first).Collection("devices").Doc(id).Get(ctx); !isNotFound(err) {
		t.Fatal("reassigned browser token remained attached to the previous admin")
	}
	if _, err := store.updateAdminWebPushToken(ctx, app.Principal{UID: first}, payload, false); err != nil {
		t.Fatal(err)
	}
	registry := store.firestore.Collection("adminWebPushTokens").Doc(id)
	snapshot, err := registry.Get(ctx)
	if err != nil || text(snapshot.Data(), "ownerUid") != second {
		t.Fatal("previous admin could unregister the current owner's browser token")
	}
	if _, err := store.updateAdminWebPushToken(ctx, app.Principal{UID: inactive}, payload, true); !errors.Is(err, app.ErrPrecondition) {
		t.Fatal("inactive administrator could register a push token")
	}
	if _, err := store.updateAdminWebPushToken(ctx, app.Principal{UID: second}, payload, false); err != nil {
		t.Fatal(err)
	}
	if _, err := registry.Get(ctx); !isNotFound(err) {
		t.Fatal("current owner could not remove its token registry")
	}
	if _, err := store.firestore.Collection("users").Doc(second).Collection("devices").Doc(id).Get(ctx); !isNotFound(err) {
		t.Fatal("unregistered token remained in its device collection")
	}
}

func TestEmulatorVerificationSyncUsesAuthInsteadOfCallerFieldsOrClaims(t *testing.T) {
	store, ctx := authIntegrationEmulatorStore(t)
	uid := "verify-" + uuid.NewString()
	var verified atomic.Bool
	authServer := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if !strings.HasSuffix(request.URL.Path, "/accounts:lookup") {
			t.Errorf("unexpected auth API path %s", request.URL.Path)
			http.NotFound(writer, request)
			return
		}
		writer.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(writer).Encode(map[string]any{"users": []map[string]any{{"localId": uid, "email": "test@example.test", "emailVerified": verified.Load()}}})
	}))
	defer authServer.Close()
	t.Setenv("FIREBASE_AUTH_EMULATOR_HOST", strings.TrimPrefix(authServer.URL, "http://"))
	admin, err := firebaseadmin.NewApp(ctx, &firebaseadmin.Config{ProjectID: "demo-voltrike-auth-integration"}, option.WithoutAuthentication())
	if err != nil {
		t.Fatal(err)
	}
	store.auth, err = admin.Auth(ctx)
	if err != nil {
		t.Fatal(err)
	}
	profile := store.firestore.Collection("users").Doc(uid)
	if _, err := profile.Set(ctx, map[string]any{"emailVerified": true}); err != nil {
		t.Fatal(err)
	}
	command := app.OperationCommand{Name: "syncMyEmailVerification", Payload: map[string]any{"emailVerified": true}}
	result, err := store.executeAuthIntegration(ctx, app.Principal{UID: uid, Claims: map[string]any{"email_verified": true}}, command)
	if err != nil || result["emailVerified"] != false || result["changed"] != true {
		t.Fatalf("unverified auth user was incorrectly trusted: %v %v", result, err)
	}
	verified.Store(true)
	result, err = store.executeAuthIntegration(ctx, app.Principal{UID: uid}, command)
	if err != nil || result["emailVerified"] != true || result["changed"] != true {
		t.Fatalf("verified auth user did not update the profile: %v %v", result, err)
	}
	result, err = store.executeAuthIntegration(ctx, app.Principal{UID: uid}, command)
	if err != nil || result["changed"] != false {
		t.Fatalf("unchanged auth verification status was rewritten: %v %v", result, err)
	}
}
