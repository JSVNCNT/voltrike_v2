package firebase

import (
	"context"
	"errors"
	"strings"
	"testing"

	"github.com/voltrike/voltrike-go/internal/app"
)

func TestAuthIntegrationsRejectAnonymousBeforeAccessingTrustedState(t *testing.T) {
	store := &Store{}
	for _, name := range []string{"requestBrandedVerificationEmail", "requestBrandedPasswordResetEmail", "syncMyEmailVerification", "registerAdminWebPushToken", "unregisterAdminWebPushToken"} {
		_, err := store.executeAuthIntegration(context.Background(), app.Principal{}, app.OperationCommand{Name: name})
		if !errors.Is(err, app.ErrPrecondition) {
			t.Fatalf("%s accepted an anonymous caller: %v", name, err)
		}
	}
	if _, err := store.executeAuthIntegration(context.Background(), app.Principal{UID: "user"}, app.OperationCommand{Name: "invented"}); !errors.Is(err, app.ErrInvalidArgument) {
		t.Fatalf("unknown integration error = %v", err)
	}
}

func TestPublicPasswordResetValidatesBeforeAccessingAccounts(t *testing.T) {
	for _, email := range []string{"", "missing-at.example.test", "a@example.test\r\nBcc: victim@example.test", "Person <person@example.test>"} {
		if _, err := (&Store{}).RequestPasswordReset(context.Background(), email); !errors.Is(err, app.ErrInvalidArgument) {
			t.Fatalf("invalid email reached account lookup: %v", err)
		}
	}
}

func TestAdminPushTokensHaveStableIDsAndEnforceBounds(t *testing.T) {
	value := strings.Repeat("a", 40)
	token, id, err := adminPushToken(map[string]any{"token": " " + value + " "})
	if err != nil || token != value || id != "e33cdf9c7f7120b98e8c78408953e07f2ecd183006b5606df349b4c212acf43e" {
		t.Fatalf("push token identity changed: token length=%d id=%s err=%v", len(token), id, err)
	}
	for _, token := range []string{"", strings.Repeat("x", 19), strings.Repeat("x", 4097)} {
		if _, _, err := adminPushToken(map[string]any{"token": token}); !errors.Is(err, app.ErrInvalidArgument) {
			t.Fatal("invalid push token was accepted")
		}
	}
}
