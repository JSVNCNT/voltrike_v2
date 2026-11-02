package firebase

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"firebase.google.com/go/v4/messaging"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/communications"
	"google.golang.org/api/iterator"
)

type notificationDeliveryLease struct {
	Token                 string
	Attempts              int
	CompletedDeviceHashes []string
}

type notificationDevice struct {
	Token string
	Refs  []*firestore.DocumentRef
}

func (store *Store) deliverNotificationTask(ctx context.Context, event notificationEvent, task notificationTask) (map[string]any, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	id := task.DeliveryID
	if id == "" {
		id = notificationDeliveryID(event.ID, task.RecipientID, task.Channel)
	}
	lease, reason, err := store.claimNotificationDelivery(ctx, id, event, task)
	if err != nil {
		return nil, err
	}
	if lease == nil {
		if reason == "accepted" {
			return map[string]any{"skipped": 1}, nil
		}
		// A channel still being sent is not a completed channel. Keep its
		// parent event retryable until that lease settles or expires.
		return map[string]any{"skipped": 1}, fmt.Errorf("notification recipient delivery is leased or waiting to retry")
	}
	details := map[string]any{}
	completedHashes := append([]string{}, lease.CompletedDeviceHashes...)
	var deliveryErr error
	if task.Channel == "email" {
		to, name, err := store.notificationEmailRecipient(ctx, task)
		deliveryErr = err
		if err == nil && to == "" {
			details["skipped"], details["reason"] = 1, "email-disabled-or-missing"
		} else if err == nil {
			message := task.Message
			if task.Compose != nil {
				message, deliveryErr = task.Compose(name)
			}
			if deliveryErr == nil {
				providerID, err := store.emailSender().Send(ctx, to, name, message)
				deliveryErr = err
				if err == nil {
					details["emailSent"], details["providerMessageId"] = 1, providerID
				}
			}
		}
	} else {
		details, completedHashes, deliveryErr = store.sendNotificationPush(ctx, task, completedHashes)
	}
	finishCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	if err := store.finishNotificationDelivery(finishCtx, id, *lease, details, completedHashes, deliveryErr); err != nil {
		return details, errors.Join(deliveryErr, err)
	}
	return details, deliveryErr
}

func (store *Store) claimNotificationDelivery(ctx context.Context, id string, event notificationEvent, task notificationTask) (*notificationDeliveryLease, string, error) {
	ref := store.firestore.Collection("communicationDeliveries").Doc(id)
	var result *notificationDeliveryLease
	reason := "leased-or-deferred"
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		result = nil
		snapshot, err := tx.Get(ref)
		data := map[string]any{}
		if err == nil {
			data = snapshot.Data()
		} else if !isNotFound(err) {
			return err
		}
		now := time.Now().UTC()
		if notificationDeliveryAccepted(data) {
			reason = "accepted"
			return nil
		}
		if !notificationDeliveryRetryable(data, now) {
			return nil
		}
		result = &notificationDeliveryLease{Token: uuid.NewString(), Attempts: integer(data, "attemptCount") + 1, CompletedDeviceHashes: stringSlice(data["completedDeviceHashes"])}
		fields := map[string]any{
			"recipientId": task.RecipientID, "outboxEventId": event.ID, "purpose": task.Purpose, "channel": task.Channel,
			"status": "sending", "leaseToken": result.Token, "leaseExpiresAt": now.Add(notificationLeaseDuration),
			"attemptCount": result.Attempts, "startedAt": now, "updatedAt": now, "expiresAt": now.Add(30 * 24 * time.Hour),
		}
		if task.Channel == "email" {
			fields["provider"] = "brevo"
		} else {
			fields["provider"] = "fcm"
		}
		if task.IncidentID != "" {
			fields["incidentId"] = task.IncidentID
		}
		if task.TodaID != "" {
			fields["todaId"], fields["stage"] = task.TodaID, task.Stage
		}
		if len(data) == 0 {
			fields["createdAt"] = now
		}
		return tx.Set(ref, fields, firestore.MergeAll)
	})
	return result, reason, err
}

func (store *Store) finishNotificationDelivery(ctx context.Context, id string, lease notificationDeliveryLease, details map[string]any, completedHashes []string, failure error) error {
	ref := store.firestore.Collection("communicationDeliveries").Doc(id)
	return store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err != nil {
			return err
		}
		if text(snapshot.Data(), "leaseToken") != lease.Token {
			return fmt.Errorf("notification recipient lease was replaced")
		}
		now := time.Now().UTC()
		fields := map[string]any{
			"status": "accepted", "acceptedAt": now, "updatedAt": now, "details": details,
			"leaseToken": firestore.Delete, "leaseExpiresAt": firestore.Delete,
			"nextAttemptAt": firestore.Delete, "completedDeviceHashes": completedHashes,
			"errorCode": firestore.Delete,
		}
		if providerID := text(details, "providerMessageId"); providerID != "" {
			fields["providerMessageId"] = providerID
		}
		if failure != nil {
			fields["status"], fields["failedAt"] = "failed", now
			fields["acceptedAt"], fields["errorCode"] = firestore.Delete, "provider_or_dependency_error"
			fields["nextAttemptAt"] = now.Add(notificationRetryDelay(lease.Attempts))
		}
		return tx.Set(ref, fields, firestore.MergeAll)
	})
}

func notificationDeliveryAccepted(data map[string]any) bool {
	status := text(data, "status")
	return status == "accepted" || status == "completed" || status == "skipped"
}

func notificationDeliveryRetryable(data map[string]any, now time.Time) bool {
	if notificationDeliveryAccepted(data) || notificationTime(data["nextAttemptAt"]).After(now) {
		return false
	}
	if text(data, "status") == "sending" {
		if _, ok := data["startedAt"]; !ok {
			// Compatibility with delivery records created by the Node worker.
			copy := make(map[string]any, len(data)+1)
			for key, value := range data {
				copy[key] = value
			}
			copy["startedAt"] = data["createdAt"]
			data = copy
		}
		return !notificationLeaseActive(data, "leaseExpiresAt", "startedAt", now)
	}
	return true // missing, pending and failed records are all recoverable.
}

func (store *Store) notificationEmailRecipient(ctx context.Context, task notificationTask) (string, string, error) {
	profile := task.Profile
	if profile == nil {
		var err error
		profile, err = store.notificationDocument(ctx, "users/"+task.RecipientID)
		if err != nil {
			return "", "", err
		}
	}
	name := strings.TrimSpace(text(profile, "firstName") + " " + text(profile, "lastName"))
	if name == "" {
		name = text(profile, "displayName")
	}
	if !task.AuthEmailOnly {
		preferred := text(profile, "safetyContactEmail")
		if preferred == "" {
			preferred = text(profile, "email")
		}
		if communications.ValidEmail(preferred) {
			if name == "" {
				name = "Administrator"
			}
			return preferred, name, nil
		}
	}
	if store.auth == nil {
		return "", "", fmt.Errorf("Firebase Auth email lookup is unavailable")
	}
	user, err := store.auth.GetUser(ctx, task.RecipientID)
	if auth.IsUserNotFound(err) {
		return "", name, nil
	}
	if err != nil {
		return "", "", fmt.Errorf("look up notification recipient: %w", err)
	}
	if name == "" {
		name = user.DisplayName
	}
	if name == "" {
		name = "Administrator"
	}
	if !communications.ValidEmail(user.Email) {
		return "", name, nil
	}
	return strings.TrimSpace(user.Email), name, nil
}

func (store *Store) sendNotificationPush(ctx context.Context, task notificationTask, completed []string) (map[string]any, []string, error) {
	if store.messaging == nil {
		return nil, completed, fmt.Errorf("Firebase Messaging is unavailable")
	}
	devices, err := store.notificationDevices(ctx, task.RecipientID, completed)
	if err != nil {
		return nil, completed, err
	}
	details := map[string]any{"attempted": len(devices), "succeeded": 0}
	var failures []error
	for offset := 0; offset < len(devices); offset += 500 {
		batch := devices[offset:min(offset+500, len(devices))]
		tokens := make([]string, len(batch))
		for index, device := range batch {
			tokens[index] = device.Token
		}
		channel, sound := notificationAndroidChannel(task.Data["type"])
		response, sendErr := store.messaging.SendEachForMulticast(ctx, &messaging.MulticastMessage{
			Tokens: tokens, Notification: &messaging.Notification{Title: task.Title, Body: task.Body}, Data: task.Data,
			Android: &messaging.AndroidConfig{Priority: "high", Notification: &messaging.AndroidNotification{ChannelID: channel, Sound: sound}},
		})
		if sendErr != nil {
			failures = append(failures, fmt.Errorf("send push batch: %w", sendErr))
			continue
		}
		for index, result := range response.Responses {
			device := batch[index]
			if result.Success {
				details["succeeded"] = integer(details, "succeeded") + 1
				completed = append(completed, notificationTokenHash(device.Token))
			} else if notificationInvalidToken(result.Error) {
				if err := store.removeNotificationDevice(ctx, device); err != nil {
					failures = append(failures, err)
				} else {
					completed = append(completed, notificationTokenHash(device.Token))
				}
			} else {
				failures = append(failures, fmt.Errorf("push provider rejected a recipient delivery: %w", result.Error))
			}
		}
	}
	return details, completed, errors.Join(failures...)
}

func (store *Store) notificationDevices(ctx context.Context, uid string, completed []string) ([]notificationDevice, error) {
	items := store.firestore.Collection("users").Doc(uid).Collection("devices").Documents(ctx)
	defer items.Stop()
	finished := map[string]bool{}
	for _, hash := range completed {
		finished[hash] = true
	}
	devices, positions := []notificationDevice{}, map[string]int{}
	for {
		doc, err := items.Next()
		if err == iterator.Done {
			return devices, nil
		}
		if err != nil {
			return nil, err
		}
		token := text(doc.Data(), "token")
		if token == "" || finished[notificationTokenHash(token)] {
			continue
		}
		if position, ok := positions[token]; ok {
			devices[position].Refs = append(devices[position].Refs, doc.Ref)
		} else {
			positions[token] = len(devices)
			devices = append(devices, notificationDevice{Token: token, Refs: []*firestore.DocumentRef{doc.Ref}})
		}
	}
}

func (store *Store) removeNotificationDevice(ctx context.Context, device notificationDevice) error {
	for _, ref := range device.Refs {
		if err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			doc, err := tx.Get(ref)
			if isNotFound(err) {
				return nil
			}
			if err != nil {
				return err
			}
			if text(doc.Data(), "token") != device.Token {
				return nil // Do not delete a newly refreshed token.
			}
			return tx.Delete(ref)
		}); err != nil {
			return fmt.Errorf("remove expired push token: %w", err)
		}
	}
	return nil
}

func (store *Store) notificationDocument(ctx context.Context, path string) (map[string]any, error) {
	parts := strings.Split(path, "/")
	if len(parts)%2 != 0 {
		return nil, fmt.Errorf("invalid notification projection path")
	}
	for _, part := range parts {
		if !notificationIDValid(part) {
			return nil, fmt.Errorf("invalid notification projection ID")
		}
	}
	doc, err := store.firestore.Doc(path).Get(ctx)
	if isNotFound(err) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return doc.Data(), nil
}

func (store *Store) notificationAdministrators(ctx context.Context, todaID string) ([]notificationRecipient, error) {
	// A single-field role query needs no deployment-specific composite index.
	// Preserve the existing integration's bound of 100 active administrators.
	items := store.firestore.Collection("users").Where("role", "in", []string{"developer_admin", "toda_admin"}).Documents(ctx)
	defer items.Stop()
	result := []notificationRecipient{}
	active := 0
	for {
		doc, err := items.Next()
		if err == iterator.Done {
			return result, nil
		}
		if err != nil {
			return nil, err
		}
		profile := doc.Data()
		if !booleanDefault(profile, false, "isActive") {
			continue
		}
		active++
		if notificationAdministratorInScope(profile, todaID) {
			result = append(result, notificationRecipient{ID: doc.Ref.ID, Profile: profile})
		}
		if active >= 100 {
			return result, nil
		}
	}
}

func notificationAdministratorInScope(profile map[string]any, todaID string) bool {
	role := text(profile, "role")
	return booleanDefault(profile, false, "isActive") && (role == "developer_admin" || role == "toda_admin" && (todaID == "" || text(profile, "todaId") == todaID))
}

func notificationAndroidChannel(kind string) (string, string) {
	switch kind {
	case "incoming_call":
		return "incoming_calls_v2", "call_ringtone"
	case "chat_message":
		return "chat_messages", "chat_ringtone"
	case "safety_incident":
		return "safety_incidents", "booking_ringtone"
	case "driver_violation", "driver_violation_message":
		return "driver_restriction_alerts_v1", "booking_ringtone"
	default:
		return "booking_updates", "booking_ringtone"
	}
}

func notificationInvalidToken(err error) bool {
	return messaging.IsRegistrationTokenNotRegistered(err) || messaging.IsInvalidArgument(err) && strings.Contains(strings.ToLower(fmt.Sprint(err)), "registration token")
}

func notificationTokenHash(token string) string { return fmt.Sprintf("%x", notificationSHA256(token)) }
func notificationSHA256(value string) [32]byte  { return sha256.Sum256([]byte(value)) }
