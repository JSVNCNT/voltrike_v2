package firebase

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebaseadmin "firebase.google.com/go/v4"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

func TestEmulatorNotificationProducersCommitDomainWritesAndOutboxTogether(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	todaID, applicant := "toda-"+uuid.NewString(), "applicant-"+uuid.NewString()
	if _, err := store.registerToda(ctx, app.Principal{UID: applicant}, map[string]any{"todaId": todaID, "name": "Notification test TODA"}, false); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"todas/" + todaID, "todaApplications/" + todaID, "users/" + applicant} {
		if _, err := store.firestore.Doc(path).Get(ctx); err != nil {
			t.Fatalf("registration projection %s missing: %v", path, err)
		}
	}
	event := notificationTestEvent(t, store, ctx, todaID, "toda.registration.submitted")
	if payload := notificationMap(event["payload"]); text(payload, "adminUid") != applicant || text(payload, "todaName") != "Notification test TODA" {
		t.Fatalf("registration email identity missing from committed event: %#v", event)
	}

	bookingID, driverID := "booking-"+uuid.NewString(), "driver-"+uuid.NewString()
	booking := store.firestore.Collection("bookings").Doc(bookingID)
	if _, err := booking.Set(ctx, map[string]any{"status": "pending", "passengerId": applicant, "offerRound": 0}); err != nil {
		t.Fatal(err)
	}
	if err := store.PublishBookingOffers(ctx, bookingID, []app.DispatchCandidate{{DriverID: driverID, TodaID: todaID, DistanceMeters: 150}}, time.Now().Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	offer, err := store.firestore.Collection("drivers").Doc(driverID).Collection("bookingOffers").Doc(bookingID).Get(ctx)
	if err != nil || text(offer.Data(), "status") != "offered" {
		t.Fatalf("committed offer missing: %v", err)
	}
	event = notificationTestEvent(t, store, ctx, bookingID, "booking.offer.created")
	if payload := notificationMap(event["payload"]); text(payload, "driverId") != driverID || integer(payload, "offerRound") != integer(offer.Data(), "offerRound") {
		t.Fatalf("offer push does not identify its committed round: %#v", event)
	}

	violationID := "violation-" + uuid.NewString()
	violation := store.firestore.Collection("driverViolations").Doc(violationID)
	if _, err := violation.Set(ctx, map[string]any{"driverId": driverID, "ownerTodaId": todaID, "status": "open"}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.adminUpdateViolation(ctx, adminIdentity{UID: "developer", Role: "developer_admin"}, map[string]any{"violationId": violationID, "action": "resolve", "note": "Case reviewed"}); err != nil {
		t.Fatal(err)
	}
	updated, err := violation.Get(ctx)
	if err != nil || text(updated.Data(), "status") != "resolved" {
		t.Fatalf("administrator status update missing: %v", err)
	}
	event = notificationTestEvent(t, store, ctx, violationID, "violation.updated")
	if payload := notificationMap(event["payload"]); text(payload, "status") != "resolved" || text(payload, "driverId") != driverID || text(payload, "note") != "Case reviewed" {
		t.Fatalf("case update push was not committed with the domain change: %#v", event)
	}
}

func TestEmulatorLocationIngressAutomaticallyObservesRestrictionsAndNewSessions(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	host := os.Getenv("FIREBASE_DATABASE_EMULATOR_HOST")
	if host == "" {
		t.Skip("requires local FIREBASE_DATABASE_EMULATOR_HOST")
	}
	if !strings.HasPrefix(host, "127.0.0.1:") && !strings.HasPrefix(host, "localhost:") {
		t.Fatal("automatic monitoring test must use a loopback RTDB emulator")
	}
	// The Go RTDB SDK parses a scheme-like localhost URL and explicit namespace;
	// a bare numeric-IP URL is rejected by its URI parser.
	emulatorHost := strings.Replace(host, "127.0.0.1:", "localhost:", 1)
	t.Setenv("FIREBASE_DATABASE_EMULATOR_HOST", emulatorHost+"?ns=demo-voltrike-policy-default-rtdb")
	admin, err := firebaseadmin.NewApp(ctx, &firebaseadmin.Config{ProjectID: "demo-voltrike-policy", DatabaseURL: "https://demo-voltrike-policy-default-rtdb.firebaseio.com"})
	if err != nil {
		t.Fatal(err)
	}
	store.realtime, err = admin.Database(ctx)
	if err != nil {
		t.Fatal(err)
	}
	store.cfg.AutomaticRestrictionMonitoring = true
	uid, sessionID, restrictionID := "driver-"+uuid.NewString(), "session-"+uuid.NewString(), "restriction-"+uuid.NewString()
	state := store.firestore.Collection("driverRestrictionStates").Doc(uid).Collection("restrictions").Doc(restrictionID)
	seed := map[string]map[string]any{
		"drivers/" + uid:               {"driverStatus": "approved", "todaId": "toda-test"},
		"driver_profiles/" + uid:       {"activeSessionId": sessionID},
		"driver_sessions/" + sessionID: {"driverId": uid, "leaseGeneration": 1, "sampleSequence": 0, "status": "active", "expiresAt": time.Now().Add(time.Minute)},
		"routeRestrictions/" + restrictionID: {
			"name": "Ingress test", "isActive": true, "type": "no_service_area", "geometryType": "polygon",
			"polygon": []map[string]any{
				{"latitude": 10.66, "longitude": 122.94}, {"latitude": 10.68, "longitude": 122.94},
				{"latitude": 10.68, "longitude": 122.96}, {"latitude": 10.66, "longitude": 122.96},
			},
		},
	}
	for path, value := range seed {
		if _, err := store.firestore.Doc(path).Set(ctx, value); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_, _ = store.firestore.Collection("routeRestrictions").Doc(restrictionID).Delete(cleanup)
	})
	command := app.DriverLocationCommand{SessionID: sessionID, LeaseGeneration: 1, SampleSequence: 1, Latitude: 10.67, Longitude: 122.95, Accuracy: 5, ObservedAt: time.Now().UTC(), Online: true, Available: true}
	if err := store.UpdateDriverLocation(ctx, app.Principal{UID: uid}, command); err != nil {
		t.Fatal(err)
	}
	first, err := state.Get(ctx)
	if err != nil || integer(first.Data(), "candidateInsideSamples") != 1 {
		t.Fatalf("first published location did not invoke the server monitor: %v", err)
	}
	command.SampleSequence = 2
	command.ObservedAt = command.ObservedAt.Add(time.Millisecond)
	if err := store.UpdateDriverLocation(ctx, app.Principal{UID: uid}, command); err != nil {
		t.Fatal(err)
	}
	second, err := state.Get(ctx)
	if err != nil || second.Data()["inside"] != true || text(second.Data(), "activeViolationId") == "" {
		t.Fatalf("second observation did not create the restricted-area case: %v", err)
	}
	violationID := text(second.Data(), "activeViolationId")
	notificationTestEvent(t, store, ctx, violationID, "violation.created")
	if err := store.UpdateDriverLocation(ctx, app.Principal{UID: uid}, command); err != nil {
		t.Fatal(err)
	}
	newSession := "session-" + uuid.NewString()
	if _, err := store.firestore.Collection("driver_sessions").Doc(newSession).Set(ctx, map[string]any{"driverId": uid, "leaseGeneration": 1, "sampleSequence": 0, "status": "active", "expiresAt": time.Now().Add(time.Minute)}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.firestore.Collection("driver_profiles").Doc(uid).Update(ctx, []firestore.Update{{Path: "activeSessionId", Value: newSession}}); err != nil {
		t.Fatal(err)
	}
	command.SessionID, command.SampleSequence = newSession, 1
	command.ObservedAt = command.ObservedAt.Add(time.Millisecond)
	if err := store.UpdateDriverLocation(ctx, app.Principal{UID: uid}, command); err != nil {
		t.Fatal(err)
	}
	latest, err := state.Get(ctx)
	if err != nil || text(latest.Data(), "sessionId") != newSession || integer(latest.Data(), "lastSequence") != 1 || text(latest.Data(), "activeViolationId") != violationID {
		t.Fatalf("prior-session sequence suppressed or duplicated a new-session observation: %#v %v", latest, err)
	}
}

func notificationTestEvent(t *testing.T, store *Store, ctx context.Context, aggregateID, eventType string) map[string]any {
	t.Helper()
	items, err := store.firestore.Collection("outbox").Where("aggregateId", "==", aggregateID).Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var found map[string]any
	for _, doc := range items {
		if data := doc.Data(); text(data, "type") == eventType {
			if found != nil {
				t.Fatalf("duplicate %s event for %s", eventType, aggregateID)
			}
			found = data
		}
	}
	if found == nil {
		t.Fatalf("missing committed %s event for %s", eventType, aggregateID)
	}
	if created := notificationTime(found["createdAt"]); created.IsZero() || !notificationTime(found["notificationRetryAt"]).Equal(created) {
		t.Fatalf("event does not start in the durable retry queue: %#v", found)
	}
	return found
}
