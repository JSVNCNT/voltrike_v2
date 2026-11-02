package firebase

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"google.golang.org/api/iterator"
)

const notificationLeaseDuration = 5 * time.Minute

type notificationEvent struct {
	ID, Type, AggregateID string
	Payload               map[string]any
	CreatedAt             time.Time
}

type notificationLease struct {
	Token    string
	Attempts int
	Event    notificationEvent
}

// ProcessOutbox consumes one committed integration event. Both the event and
// each recipient/channel have durable, fenced leases, so a partial failure can
// resume without resending channels that the provider already accepted.
func (store *Store) ProcessOutbox(ctx context.Context, eventID string) (map[string]any, error) {
	if !notificationIDValid(eventID) {
		return nil, fmt.Errorf("%w: a valid outbox event ID is required", app.ErrInvalidArgument)
	}
	lease, reason, err := store.claimNotificationEvent(ctx, eventID)
	if err != nil {
		return nil, err
	}
	if lease == nil {
		return map[string]any{"skipped": true, "reason": reason}, nil
	}
	planner := notificationPlanner{
		document: store.notificationDocument, administrators: store.notificationAdministrators,
		portalURL: store.cfg.AdminPortalURL, logoURL: store.cfg.EmailLogoURL,
	}
	plan, processErr := planner.plan(ctx, lease.Event, time.Now().UTC())
	result := map[string]any{"eventId": eventID, "attempted": 0, "succeeded": 0, "emailSent": 0}
	if processErr == nil && plan.Skipped != "" {
		result["skipped"], result["reason"] = true, plan.Skipped
	}
	if processErr == nil && len(plan.Tasks) > 0 {
		result, processErr = store.deliverNotificationTasks(ctx, lease.Event, plan.Tasks)
	}
	// A request deadline must not prevent releasing the lease and scheduling a
	// retry. The bounded cleanup context carries no client cancellation.
	finishCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()
	if err := store.finishNotificationEvent(finishCtx, eventID, *lease, result, processErr); err != nil {
		return result, errors.Join(processErr, err)
	}
	return result, processErr
}

// RetryOutbox is called by the hosted scheduler. notificationRetryAt is a
// single-field queue index: new events are due immediately, in-flight events
// become due at lease expiry, and completed events leave the queue.
func (store *Store) RetryOutbox(ctx context.Context) (map[string]any, error) {
	items := store.firestore.Collection("outbox").Where("notificationRetryAt", "<=", time.Now().UTC()).
		OrderBy("notificationRetryAt", firestore.Asc).Limit(100).Documents(ctx)
	defer items.Stop()
	ids := []string{}
	for {
		doc, err := items.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("list retryable outbox events: %w", err)
		}
		ids = append(ids, doc.Ref.ID)
	}
	processed, failed := 0, 0
	for _, id := range ids {
		if ctx.Err() != nil {
			return map[string]any{"processed": processed, "failed": failed, "remaining": len(ids) - processed}, ctx.Err()
		}
		_, err := store.ProcessOutbox(ctx, id)
		processed++
		if err != nil {
			failed++
			// Provider error bodies can contain email addresses or tokens. Log
			// only the event ID; detailed errors remain within the request trace.
			slog.Warn("outbox retry failed", "eventId", id)
		}
	}
	return map[string]any{"processed": processed, "failed": failed}, nil
}

func (store *Store) claimNotificationEvent(ctx context.Context, id string) (*notificationLease, string, error) {
	ref := store.firestore.Collection("outbox").Doc(id)
	var lease *notificationLease
	reason := "already-completed-or-leased"
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		lease = nil // Firestore may retry the transaction callback.
		snapshot, err := tx.Get(ref)
		if isNotFound(err) {
			reason = "event-not-found"
			return nil
		}
		if err != nil {
			return err
		}
		data, now := snapshot.Data(), time.Now().UTC()
		consumer := notificationMap(data["consumerStatus"])
		if text(consumer, "notifications") == "completed" {
			return tx.Update(ref, []firestore.Update{{Path: "notificationRetryAt", Value: firestore.Delete}})
		}
		if text(consumer, "notifications") == "processing" && notificationLeaseActive(consumer, "notificationsLeaseExpiresAt", "notificationsStartedAt", now) {
			return nil
		}
		if next := notificationTime(data["notificationRetryAt"]); next.After(now) {
			reason = "retry-deferred"
			return nil
		}
		token, attempts := uuid.NewString(), integer(consumer, "notificationsAttemptCount")+1
		lease = &notificationLease{Token: token, Attempts: attempts, Event: notificationEvent{
			ID: id, Type: text(data, "type"), AggregateID: text(data, "aggregateId"),
			Payload: notificationMap(data["payload"]), CreatedAt: notificationTime(data["createdAt"]),
		}}
		return tx.Update(ref, []firestore.Update{
			{Path: "consumerStatus.notifications", Value: "processing"},
			{Path: "consumerStatus.notificationsStartedAt", Value: now},
			{Path: "consumerStatus.notificationsLeaseExpiresAt", Value: now.Add(notificationLeaseDuration)},
			{Path: "consumerStatus.notificationsLeaseToken", Value: token},
			{Path: "consumerStatus.notificationsAttemptCount", Value: attempts},
			{Path: "notificationRetryAt", Value: now.Add(notificationLeaseDuration)},
		})
	})
	return lease, reason, err
}

func (store *Store) finishNotificationEvent(ctx context.Context, id string, lease notificationLease, details map[string]any, failure error) error {
	ref := store.firestore.Collection("outbox").Doc(id)
	return store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err != nil {
			return err
		}
		consumer := notificationMap(snapshot.Data()["consumerStatus"])
		if text(consumer, "notificationsLeaseToken") != lease.Token {
			return fmt.Errorf("outbox notification lease was replaced")
		}
		now, next, status := time.Now().UTC(), any(firestore.Delete), "completed"
		if failure != nil {
			status = "failed"
			next = now.Add(notificationRetryDelay(lease.Attempts))
		}
		return tx.Update(ref, []firestore.Update{
			{Path: "consumerStatus.notifications", Value: status},
			{Path: "consumerStatus.notificationsFinishedAt", Value: now},
			{Path: "consumerStatus.notificationsDetails", Value: details},
			{Path: "consumerStatus.notificationsLeaseExpiresAt", Value: firestore.Delete},
			{Path: "consumerStatus.notificationsLeaseToken", Value: firestore.Delete},
			{Path: "notificationRetryAt", Value: next},
			{Path: "expiresAt", Value: now.Add(30 * 24 * time.Hour)},
		})
	})
}

func (store *Store) deliverNotificationTasks(ctx context.Context, event notificationEvent, tasks []notificationTask) (map[string]any, error) {
	type outcome struct {
		details map[string]any
		err     error
	}
	jobs, results := make(chan notificationTask), make(chan outcome, len(tasks))
	var workers sync.WaitGroup
	for range min(5, len(tasks)) {
		workers.Go(func() {
			for task := range jobs {
				details, err := store.deliverNotificationTask(ctx, event, task)
				results <- outcome{details, err}
			}
		})
	}
	for _, task := range tasks {
		jobs <- task
	}
	close(jobs)
	workers.Wait()
	close(results)
	summary := map[string]any{"eventId": event.ID, "attempted": 0, "succeeded": 0, "emailSent": 0, "skipped": 0, "failed": 0}
	var failures []error
	for result := range results {
		for _, key := range []string{"attempted", "succeeded", "emailSent", "skipped"} {
			summary[key] = integer(summary, key) + integer(result.details, key)
		}
		if result.err != nil {
			summary["failed"] = integer(summary, "failed") + 1
			failures = append(failures, result.err)
		}
	}
	return summary, errors.Join(failures...)
}

func notificationRetryDelay(attempt int) time.Duration {
	return time.Duration(1<<min(max(attempt-1, 0), 6)) * 30 * time.Second
}

func notificationIDValid(id string) bool {
	return strings.TrimSpace(id) != "" && len(id) <= 1500 && !strings.Contains(id, "/") && id != "." && id != ".."
}

func notificationMap(value any) map[string]any {
	if result, ok := value.(map[string]any); ok && result != nil {
		return result
	}
	return map[string]any{}
}

func notificationTime(value any) time.Time {
	switch value := value.(type) {
	case time.Time:
		return value
	case string:
		parsed, _ := time.Parse(time.RFC3339Nano, value)
		return parsed
	case int64:
		return time.UnixMilli(value)
	case int:
		return time.UnixMilli(int64(value))
	case float64:
		return time.UnixMilli(int64(value))
	default:
		return time.Time{}
	}
}

func notificationLeaseActive(data map[string]any, expiryKey, startedKey string, now time.Time) bool {
	if expiry := notificationTime(data[expiryKey]); !expiry.IsZero() {
		return expiry.After(now)
	}
	started := notificationTime(data[startedKey])
	return !started.IsZero() && started.Add(notificationLeaseDuration).After(now)
}

func notificationDeliveryID(eventID, recipientID, channel string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(eventID+":"+recipientID+":"+channel)))
}
