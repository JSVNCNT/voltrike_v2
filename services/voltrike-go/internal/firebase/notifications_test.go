package firebase

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestNotificationDeliveryRetriesFailuresAndAbandonedLeases(t *testing.T) {
	now := time.Date(2026, 11, 2, 0, 0, 0, 0, time.UTC)
	cases := []struct {
		name string
		data map[string]any
		want bool
	}{
		{"new", map[string]any{}, true},
		{"pending", map[string]any{"status": "pending"}, true},
		{"failed legacy delivery", map[string]any{"status": "failed", "createdAt": now.Add(-time.Hour)}, true},
		{"failed due delivery", map[string]any{"status": "failed", "nextAttemptAt": now.Add(-time.Second)}, true},
		{"backoff", map[string]any{"status": "failed", "nextAttemptAt": now.Add(time.Second)}, false},
		{"accepted", map[string]any{"status": "accepted"}, false},
		{"completed", map[string]any{"status": "completed"}, false},
		{"active lease", map[string]any{"status": "sending", "leaseExpiresAt": now.Add(time.Second)}, false},
		{"expired lease", map[string]any{"status": "sending", "leaseExpiresAt": now.Add(-time.Second)}, true},
		{"active legacy lease", map[string]any{"status": "sending", "createdAt": now.Add(-time.Minute)}, false},
		{"abandoned legacy lease", map[string]any{"status": "sending", "createdAt": now.Add(-10 * time.Minute)}, true},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := notificationDeliveryRetryable(test.data, now); got != test.want {
				t.Fatalf("retryable = %v, want %v", got, test.want)
			}
		})
	}
}

func TestNotificationPlanUsesRecordedTransitionAndPreservesRoleCopy(t *testing.T) {
	planner := notificationTestPlanner(map[string]map[string]any{"bookings/b1": {"status": "completed", "passengerId": "passenger", "driverId": "driver"}}, nil)
	plan, err := planner.plan(context.Background(), notificationEvent{Type: "booking.paymentConfirmation", AggregateID: "b1", Payload: map[string]any{"status": "paymentConfirmation"}}, time.Now())
	if err != nil || len(plan.Tasks) != 2 {
		t.Fatalf("tasks = %#v, err = %v", plan.Tasks, err)
	}
	for _, task := range plan.Tasks {
		if task.Data["type"] != "paymentConfirmation" {
			t.Fatal("a later booking projection replaced the recorded transition")
		}
		if task.RecipientID == "driver" && task.Title != "Confirm cash received" {
			t.Fatalf("driver received passenger-only copy: %q", task.Title)
		}
	}
	passenger, driver := notificationBookingCopy("cancelled", "passenger_no_show")
	if passenger[0] != "Passenger no-show" || driver[0] != "Passenger no-show" {
		t.Fatal("no-show cancellation copy was lost")
	}
}

func TestNotificationFreshnessPreservesSafetyAndRegistrationMail(t *testing.T) {
	now := time.Now().UTC()
	planner := notificationTestPlanner(nil, nil)
	for _, eventType := range []string{"call.ringing", "booking.completed", "chat.message.created", "driver.registration.submitted", "report.created", "violation.created"} {
		plan, err := planner.plan(context.Background(), notificationEvent{Type: eventType, CreatedAt: now.Add(-2 * time.Hour)}, now)
		if err != nil || plan.Skipped != "stale-notification-event" {
			t.Fatalf("stale %s was not skipped: %#v %v", eventType, plan, err)
		}
	}
	if notificationMaximumAge("safety.sos.created") != 0 || notificationMaximumAge("toda.registration.approved") != 0 {
		t.Fatal("unresolved SOS or registration mail acquired a live-push expiry")
	}
}

func TestNotificationOfferChecksExpiryAndRoundBeforePush(t *testing.T) {
	now := time.Now().UTC()
	docs := map[string]map[string]any{
		"bookings/b1":                     {"status": "pending", "offerRound": 2},
		"drivers/driver/bookingOffers/b1": {"status": "offered", "offerRound": 2, "expiresAt": now.Add(time.Minute), "distanceMeters": 1450},
	}
	event := notificationEvent{Type: "booking.offer.created", AggregateID: "b1", Payload: map[string]any{"bookingId": "b1", "driverId": "driver", "offerRound": 2}}
	planner := notificationTestPlanner(docs, nil)
	plan, err := planner.plan(context.Background(), event, now)
	if err != nil || len(plan.Tasks) != 1 || plan.Tasks[0].Data["type"] != "booking_offer" || !strings.Contains(plan.Tasks[0].Body, "1.4 km") {
		t.Fatalf("valid legacy-compatible offer push missing: %#v err=%v", plan, err)
	}
	docs["drivers/driver/bookingOffers/b1"]["offerRound"] = 3
	plan, err = planner.plan(context.Background(), event, now)
	if err != nil || plan.Skipped != "offer-no-longer-actionable" {
		t.Fatal("superseded offer produced a push")
	}
	docs["drivers/driver/bookingOffers/b1"]["offerRound"] = 2
	docs["drivers/driver/bookingOffers/b1"]["expiresAt"] = now.Add(-time.Second)
	plan, err = planner.plan(context.Background(), event, now)
	if err != nil || plan.Skipped != "offer-no-longer-actionable" {
		t.Fatal("expired offer produced a push")
	}
}

func TestNotificationSafetyPreferencesAndActionability(t *testing.T) {
	docs := map[string]map[string]any{"safetyIncidents/s1": {"status": "open", "responseStatus": "reported", "bookingId": "b1", "todaId": "t1"}}
	admins := []notificationRecipient{
		{ID: "developer", Profile: map[string]any{"role": "developer_admin", "isActive": true}},
		{ID: "local", Profile: map[string]any{"role": "toda_admin", "todaId": "t1", "isActive": true, "safetyEmailEnabled": false}},
	}
	planner := notificationTestPlanner(docs, admins)
	plan, err := planner.plan(context.Background(), notificationEvent{Type: "safety.sos.created", AggregateID: "s1"}, time.Now())
	if err != nil || len(plan.Tasks) != 3 {
		t.Fatalf("expected two pushes and one opted-in email, got %#v %v", plan, err)
	}
	for _, task := range plan.Tasks {
		if task.Channel == "email" && task.RecipientID != "developer" {
			t.Fatal("opted-out administrator received email")
		}
	}
	docs["safetyIncidents/s1"]["responseStatus"] = "resolved"
	plan, err = planner.plan(context.Background(), notificationEvent{Type: "safety.escalated", AggregateID: "s1"}, time.Now())
	if err != nil || plan.Skipped != "safety-incident-not-actionable" {
		t.Fatal("resolved incident escalated again")
	}
	plan, err = planner.plan(context.Background(), notificationEvent{Type: "safety.sos.safe", AggregateID: "s1"}, time.Now())
	if err != nil || len(plan.Tasks) != 3 {
		t.Fatal("reporter-safe event was lost")
	}
}

func TestNotificationTODARegistrationPortsEveryBrandedStageAndLegacyKey(t *testing.T) {
	planner := notificationTestPlanner(map[string]map[string]any{
		"todaApplications/t1": {"adminUid": "applicant", "status": "approved"}, "todas/t1": {"name": "Central TODA"},
	}, nil)
	for _, stage := range []string{"submitted", "approved", "declined"} {
		plan, err := planner.plan(context.Background(), notificationEvent{Type: "toda.registration." + stage, AggregateID: "t1"}, time.Now())
		if err != nil || len(plan.Tasks) != 1 {
			t.Fatalf("%s mail not queued: %#v %v", stage, plan, err)
		}
		task := plan.Tasks[0]
		message, err := task.Compose("Pending Administrator")
		if err != nil || !strings.Contains(message.HTML, "Central TODA") || !strings.Contains(message.Text, "Pending Administrator") || !task.AuthEmailOnly {
			t.Fatalf("branded %s mail lost name/TODA/auth recipient: %#v %v", stage, task, err)
		}
		if task.DeliveryID != notificationTokenHash("toda-registration:t1:applicant:"+stage) {
			t.Fatal("legacy accepted registration delivery would not deduplicate")
		}
	}
}

func TestNotificationViolationMessagesExcludeSenderAndHideMessageBody(t *testing.T) {
	planner := notificationTestPlanner(map[string]map[string]any{
		"driverViolations/v1":             {"driverId": "driver", "ownerTodaId": "t1"},
		"driverViolations/v1/messages/m1": {"senderId": "admin", "body": "Private case details"},
	}, []notificationRecipient{{ID: "admin"}, {ID: "other-admin"}})
	plan, err := planner.plan(context.Background(), notificationEvent{Type: "violation.message.created", Payload: map[string]any{"violationId": "v1", "messageId": "m1"}}, time.Now())
	if err != nil || len(plan.Tasks) != 2 {
		t.Fatalf("case message recipients = %#v, %v", plan, err)
	}
	for _, task := range plan.Tasks {
		if task.RecipientID == "admin" || strings.Contains(task.Body, "Private case details") || task.Data["type"] != "driver_violation_message" {
			t.Fatalf("unsafe or incorrect case-message push: %#v", task)
		}
	}
}

func TestNotificationReportsRespectTrustedScopeAndReviewAudience(t *testing.T) {
	admins := []notificationRecipient{
		{ID: "developer", Profile: map[string]any{"role": "developer_admin"}},
		{ID: "toda-admin", Profile: map[string]any{"role": "toda_admin", "todaId": "t1"}},
	}
	for _, test := range []struct {
		name   string
		report map[string]any
		count  int
	}{
		{"scoped driver", map[string]any{"todaId": "t1", "reportedRole": "driver", "reviewAudience": []string{"developer_admin", "toda_admin"}}, 2},
		{"unscoped driver", map[string]any{"reportedRole": "driver", "reviewAudience": []string{"developer_admin", "toda_admin"}}, 1},
		{"passenger", map[string]any{"todaId": "t1", "reportedRole": "passenger"}, 1},
		{"restricted audience", map[string]any{"todaId": "t1", "reportedRole": "driver", "reviewAudience": []string{"developer_admin"}}, 1},
	} {
		t.Run(test.name, func(t *testing.T) {
			planner := notificationTestPlanner(map[string]map[string]any{"reports/r1": test.report}, admins)
			plan, err := planner.plan(context.Background(), notificationEvent{Type: "report.created", AggregateID: "r1"}, time.Now())
			if err != nil || len(plan.Tasks) != test.count {
				t.Fatalf("report tasks = %#v, err = %v", plan.Tasks, err)
			}
			if test.count == 1 && plan.Tasks[0].RecipientID != "developer" {
				t.Fatalf("report outside TODA review policy reached %s", plan.Tasks[0].RecipientID)
			}
		})
	}
}

func TestNotificationAdministratorScopeAndAndroidChannels(t *testing.T) {
	for _, profile := range []map[string]any{
		{"role": "toda_admin", "isActive": true, "todaId": "different"},
		{"role": "developer_admin", "isActive": false}, {"role": "driver", "isActive": true, "todaId": "t1"},
	} {
		if notificationAdministratorInScope(profile, "t1") {
			t.Fatalf("out-of-scope account was selected: %#v", profile)
		}
	}
	if !notificationAdministratorInScope(map[string]any{"role": "developer_admin", "isActive": true}, "t1") ||
		!notificationAdministratorInScope(map[string]any{"role": "toda_admin", "isActive": true, "todaId": "t1"}, "t1") {
		t.Fatal("active responsible administrators were excluded")
	}
	channels := map[string]string{"incoming_call": "incoming_calls_v2", "chat_message": "chat_messages", "safety_incident": "safety_incidents", "driver_violation_message": "driver_restriction_alerts_v1", "booking_offer": "booking_updates"}
	for kind, want := range channels {
		if got, _ := notificationAndroidChannel(kind); got != want {
			t.Fatalf("%s channel = %s, want %s", kind, got, want)
		}
	}
}

func TestEmulatorNotificationDeliveryLeaseRecoversAndFencesCompletion(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	id, eventID := uuid.NewString(), uuid.NewString()
	ref := store.firestore.Collection("communicationDeliveries").Doc(id)
	if _, err := ref.Set(ctx, map[string]any{"status": "failed", "attemptCount": 1, "completedDeviceHashes": []string{"already-sent-device"}}); err != nil {
		t.Fatal(err)
	}
	event, task := notificationEvent{ID: eventID}, notificationTask{RecipientID: "driver", Channel: "push", Purpose: "booking_offer"}
	lease, _, err := store.claimNotificationDelivery(ctx, id, event, task)
	if err != nil || lease == nil || len(lease.CompletedDeviceHashes) != 1 {
		t.Fatalf("failed delivery did not recover previous success: %#v %v", lease, err)
	}
	second, _, err := store.claimNotificationDelivery(ctx, id, event, task)
	if err != nil || second != nil {
		t.Fatal("concurrent worker acquired an active delivery lease")
	}
	stale := *lease
	stale.Token = "replaced-worker"
	if err := store.finishNotificationDelivery(ctx, id, stale, nil, nil, nil); err == nil {
		t.Fatal("a different worker could complete the delivery")
	}
	if err := store.finishNotificationDelivery(ctx, id, *lease, map[string]any{"succeeded": 1}, []string{"already-sent-device", "second-device"}, nil); err != nil {
		t.Fatal(err)
	}
	third, reason, err := store.claimNotificationDelivery(ctx, id, event, task)
	if err != nil || third != nil || reason != "accepted" {
		t.Fatal("accepted delivery would be resent")
	}
}

func notificationTestPlanner(docs map[string]map[string]any, admins []notificationRecipient) notificationPlanner {
	return notificationPlanner{
		document:       func(_ context.Context, path string) (map[string]any, error) { return docs[path], nil },
		administrators: func(_ context.Context, _ string) ([]notificationRecipient, error) { return admins, nil },
		portalURL:      "https://admin.example.test", logoURL: "https://admin.example.test/logo.png",
	}
}
