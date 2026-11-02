package firebase

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/communications"
	"google.golang.org/grpc/status"
)

func (store *Store) executeAuthIntegration(ctx context.Context, principal app.Principal, command app.OperationCommand) (map[string]any, error) {
	if strings.TrimSpace(principal.UID) == "" {
		return nil, fmt.Errorf("%w: sign in first", app.ErrPrecondition)
	}
	switch command.Name {
	case "requestBrandedVerificationEmail":
		return store.requestVerificationEmail(ctx, principal.UID)
	case "requestBrandedPasswordResetEmail":
		return store.RequestPasswordReset(ctx, text(command.Payload, "email"))
	case "syncMyEmailVerification":
		return store.syncEmailVerification(ctx, principal.UID)
	case "registerAdminWebPushToken":
		return store.updateAdminWebPushToken(ctx, principal, command.Payload, true)
	case "unregisterAdminWebPushToken":
		return store.updateAdminWebPushToken(ctx, principal, command.Payload, false)
	default:
		return nil, fmt.Errorf("%w: unsupported authentication integration", app.ErrInvalidArgument)
	}
}

func (store *Store) emailSender() *communications.Sender {
	store.emailOnce.Do(func() {
		store.mailSender = communications.NewSender(communications.Settings{
			Login: store.cfg.BrevoSMTPLogin, Key: store.cfg.BrevoSMTPKey,
			SenderEmail: store.cfg.BrevoSenderEmail, SenderName: "VolTrike",
		})
	})
	return store.mailSender
}

func (store *Store) requestVerificationEmail(ctx context.Context, uid string) (map[string]any, error) {
	if store.auth == nil || store.firestore == nil {
		return nil, fmt.Errorf("%w: authentication email service is unavailable", app.ErrUnavailable)
	}
	user, err := store.auth.GetUser(ctx, uid)
	if err != nil {
		return nil, err
	}
	if user.EmailVerified {
		return map[string]any{"sent": false, "alreadyVerified": true}, nil
	}
	if !communications.ValidEmail(user.Email) {
		return nil, fmt.Errorf("%w: the account has no valid email", app.ErrPrecondition)
	}
	limiter := store.firestore.Collection("communicationRateLimits").Doc("verification-" + uid)
	allowed, err := store.claimCommunicationRequest(ctx, limiter, map[string]any{"purpose": "account_verification", "uid": uid})
	if err != nil {
		return nil, err
	}
	if !allowed {
		return nil, fmt.Errorf("%w: wait one minute before retrying", app.ErrRateLimited)
	}
	link, err := store.auth.EmailVerificationLink(ctx, user.Email)
	if err != nil {
		return nil, err
	}
	// Current auth emails omit the optional logo; the existing HTML shell and
	// branded copy remain identical to the auth-integrations.js implementation.
	messageID, err := store.emailSender().Send(ctx, user.Email, user.DisplayName, communications.VerificationEmail(user.DisplayName, link, ""))
	if err != nil {
		// Provider rejection must not consume the resend window. Release it after
		// cancellation as well, so a subsequent request can recover.
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
		defer cancel()
		_, _ = limiter.Delete(cleanupCtx)
		return nil, fmt.Errorf("%w: verification email delivery is temporarily unavailable", app.ErrUnavailable)
	}
	if err := store.recordAuthEmailDelivery(ctx, uid, "account_verification", messageID); err != nil {
		logAuthEmailAuditFailure("account_verification", err)
	}
	return map[string]any{"sent": true, "alreadyVerified": false}, nil
}

// RequestPasswordReset is intentionally available before sign-in. Responses
// remain generic for unknown accounts and requests inside the resend window.
func (store *Store) RequestPasswordReset(ctx context.Context, email string) (map[string]any, error) {
	email = strings.ToLower(strings.TrimSpace(email))
	if !communications.ValidEmail(email) {
		return nil, fmt.Errorf("%w: enter a valid email", app.ErrInvalidArgument)
	}
	if store.auth == nil || store.firestore == nil {
		return nil, fmt.Errorf("%w: password recovery is unavailable", app.ErrUnavailable)
	}
	hash := sha256.Sum256([]byte(email))
	emailHash := hex.EncodeToString(hash[:])
	limiter := store.firestore.Collection("communicationRateLimits").Doc("password-reset-" + emailHash)
	allowed, err := store.claimCommunicationRequest(ctx, limiter, map[string]any{"purpose": "password_reset", "emailHash": emailHash})
	if err != nil {
		return nil, err
	}
	accepted := map[string]any{"accepted": true}
	if !allowed {
		return accepted, nil
	}
	user, err := store.auth.GetUserByEmail(ctx, email)
	if auth.IsUserNotFound(err) {
		return accepted, nil
	}
	if err != nil {
		return nil, err
	}
	link, err := store.auth.PasswordResetLink(ctx, email)
	if err != nil {
		return nil, err
	}
	messageID, err := store.emailSender().Send(ctx, email, user.DisplayName, communications.PasswordResetEmail(user.DisplayName, link, ""))
	if err != nil {
		return nil, fmt.Errorf("%w: password reset email delivery is temporarily unavailable", app.ErrUnavailable)
	}
	if err := store.recordAuthEmailDelivery(ctx, user.UID, "password_reset", messageID); err != nil {
		logAuthEmailAuditFailure("password_reset", err)
	}
	return accepted, nil
}

func (store *Store) claimCommunicationRequest(ctx context.Context, limiter *firestore.DocumentRef, fields map[string]any) (bool, error) {
	now := time.Now().UTC()
	allowed := false
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		// Transactions may retry: never retain the previous attempt's decision.
		allowed = false
		snapshot, err := tx.Get(limiter)
		if err != nil && !isNotFound(err) {
			return err
		}
		if err == nil {
			if last, ok := snapshot.Data()["lastRequestedAt"].(time.Time); ok && now.Sub(last) < time.Minute {
				return nil
			}
		}
		entry := make(map[string]any, len(fields)+2)
		for key, value := range fields {
			entry[key] = value
		}
		entry["lastRequestedAt"], entry["expiresAt"] = now, now.Add(24*time.Hour)
		if err := tx.Set(limiter, entry, firestore.MergeAll); err != nil {
			return err
		}
		allowed = true
		return nil
	})
	return allowed, err
}

func (store *Store) recordAuthEmailDelivery(ctx context.Context, uid, purpose, messageID string) error {
	now := time.Now().UTC()
	_, _, err := store.firestore.Collection("communicationDeliveries").Add(ctx, map[string]any{
		"recipientId": uid, "purpose": purpose, "channel": "email", "provider": "brevo",
		"providerMessageId": messageID, "status": "accepted", "createdAt": firestore.ServerTimestamp,
		"expiresAt": now.Add(30 * 24 * time.Hour),
	})
	return err
}

func logAuthEmailAuditFailure(purpose string, err error) {
	// Do not turn an already accepted send into an error: clients could send a
	// duplicate Firebase fallback. Raw provider bodies and addresses stay out.
	slog.Error("Authentication email audit write failed", "purpose", purpose, "code", status.Code(err).String())
}

// Firebase Auth, rather than caller-supplied fields or stale token claims, owns
// the verified-email status copied to profile/admin displays.
func (store *Store) syncEmailVerification(ctx context.Context, uid string) (map[string]any, error) {
	if store.auth == nil || store.firestore == nil {
		return nil, fmt.Errorf("%w: authentication service is unavailable", app.ErrUnavailable)
	}
	user, err := store.auth.GetUser(ctx, uid)
	if err != nil {
		return nil, err
	}
	profile := store.firestore.Collection("users").Doc(uid)
	snapshot, err := profile.Get(ctx)
	if isNotFound(err) {
		return nil, fmt.Errorf("%w: the account profile was not found", app.ErrPrecondition)
	}
	if err != nil {
		return nil, err
	}
	previous, exists := snapshot.Data()["emailVerified"].(bool)
	changed := !exists || previous != user.EmailVerified
	if changed {
		if _, err := profile.Update(ctx, []firestore.Update{{Path: "emailVerified", Value: user.EmailVerified}, {Path: "updatedAt", Value: firestore.ServerTimestamp}}); err != nil {
			return nil, err
		}
	}
	return map[string]any{"emailVerified": user.EmailVerified, "changed": changed}, nil
}

func adminPushToken(payload map[string]any) (string, string, error) {
	token := strings.TrimSpace(text(payload, "token"))
	if len(token) < 20 || len(token) > 4096 {
		return "", "", fmt.Errorf("%w: a valid push token is required", app.ErrInvalidArgument)
	}
	hash := sha256.Sum256([]byte(token))
	return token, hex.EncodeToString(hash[:]), nil
}

func (store *Store) updateAdminWebPushToken(ctx context.Context, principal app.Principal, payload map[string]any, register bool) (map[string]any, error) {
	if store.firestore == nil {
		return nil, fmt.Errorf("%w: device registration is unavailable", app.ErrUnavailable)
	}
	profile, err := store.firestore.Collection("users").Doc(principal.UID).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: administrator access is required", app.ErrPrecondition)
	}
	data := profile.Data()
	role := text(data, "role")
	if data["isActive"] != true || (role != "developer_admin" && role != "toda_admin") {
		return nil, fmt.Errorf("%w: administrator access is required", app.ErrPrecondition)
	}
	token, id, err := adminPushToken(payload)
	if err != nil {
		return nil, err
	}
	device := store.firestore.Collection("users").Doc(principal.UID).Collection("devices").Doc(id)
	registry := store.firestore.Collection("adminWebPushTokens").Doc(id)
	err = store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		owner, err := tx.Get(registry)
		if err != nil && !isNotFound(err) {
			return err
		}
		previousUID := ""
		if err == nil {
			previousUID = text(owner.Data(), "ownerUid")
		}
		if !register {
			if previousUID != principal.UID {
				return nil
			}
			if err := tx.Delete(registry); err != nil {
				return err
			}
			return tx.Delete(device)
		}
		if previousUID != "" && previousUID != principal.UID {
			if err := tx.Delete(store.firestore.Collection("users").Doc(previousUID).Collection("devices").Doc(id)); err != nil {
				return err
			}
		}
		if err := tx.Set(device, map[string]any{
			"token": token, "platform": "web", "ownerUid": principal.UID,
			"adminRole": role, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
		var todaID any
		if value := text(data, "todaId"); value != "" {
			todaID = value
		}
		return tx.Set(registry, map[string]any{
			"tokenHash": id, "ownerUid": principal.UID, "ownerRole": role,
			"ownerTodaId": todaID, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll)
	})
	if err != nil {
		return nil, err
	}
	if register {
		return map[string]any{"registered": true, "deviceId": id}, nil
	}
	return map[string]any{"unregistered": true, "deviceId": id}, nil
}
