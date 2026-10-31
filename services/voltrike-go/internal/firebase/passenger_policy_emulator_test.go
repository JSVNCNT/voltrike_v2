package firebase

import (
	"context"
	"errors"
	"os"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
	"google.golang.org/api/option"
)

func passengerPolicyEmulatorStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	host := os.Getenv("FIRESTORE_EMULATOR_HOST")
	if host == "" {
		t.Skip("requires local FIRESTORE_EMULATOR_HOST")
	}
	if !strings.HasPrefix(host, "127.0.0.1:") && !strings.HasPrefix(host, "localhost:") {
		t.Fatal("policy integration tests must run against a loopback emulator")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	client, err := firestore.NewClient(ctx, "demo-voltrike-policy", option.WithoutAuthentication())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return &Store{firestore: client}, ctx
}

func TestEmulatorBookingCreationEnforcesPolicyAndHonorsExpiry(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	uid, id := "p-"+uuid.NewString(), "booking-"+uuid.NewString()
	user := store.firestore.Collection("users").Doc(uid)
	policy := store.firestore.Collection("passengerBookingPolicies").Doc(uid)
	if _, err := user.Set(ctx, map[string]any{"role": "passenger", "isActive": true, "firstName": "Private", "lastName": "Passenger"}); err != nil {
		t.Fatal(err)
	}
	command := app.CreateBookingCommand{
		BookingID: id, OperationID: uuid.NewString(), QuoteToken: uuid.NewString(),
		Pickup: core.Coordinate{Latitude: 10.67, Longitude: 122.95}, Destination: core.Coordinate{Latitude: 10.68, Longitude: 122.96},
	}
	if _, err := policy.Set(ctx, map[string]any{"blockedUntil": time.Now().Add(time.Hour)}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateBooking(ctx, app.Principal{UID: uid}, command, app.Quote{}); !errors.Is(err, app.ErrPrecondition) || !strings.Contains(err.Error(), "restricted until") {
		t.Fatalf("blocked passenger could book or received unexpected error: %v", err)
	}
	if _, err := policy.Set(ctx, map[string]any{"blockedUntil": time.Now().Add(-time.Second)}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateBooking(ctx, app.Principal{UID: uid}, command, app.Quote{}); err != nil {
		t.Fatalf("expired restriction still blocked booking: %v", err)
	}
}

func TestEmulatorAppealIsOwnedOnceOnlyAndPausesPenalty(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	uid, id, now := "p-"+uuid.NewString(), "booking-"+uuid.NewString(), time.Now().UTC().Truncate(time.Microsecond)
	policy := restrictedTestPolicy(now)
	policy["strikes"] = []map[string]any{{"bookingId": id, "at": now}, {"bookingId": "two", "at": now}, {"bookingId": "three", "at": now}}
	policy["restrictionBookingIds"] = []string{id, "two", "three"}
	ref := store.firestore.Collection("passengerBookingPolicies").Doc(uid)
	if _, err := ref.Set(ctx, policy); err != nil {
		t.Fatal(err)
	}
	if _, err := store.firestore.Collection("passengerCancellationEvents").Doc(id).Set(ctx, map[string]any{"passengerId": uid, "bookingId": id, "status": "counted", "createdAt": now}); err != nil {
		t.Fatal(err)
	}
	payload := map[string]any{"bookingId": id, "reason": "Driver requested cancellation; please review."}
	if _, err := store.appealPassengerCancellation(ctx, app.Principal{UID: "other"}, payload); err == nil {
		t.Fatal("another passenger appealed an event they do not own")
	}
	if _, err := store.appealPassengerCancellation(ctx, app.Principal{UID: uid}, payload); err != nil {
		t.Fatal(err)
	}
	snapshot, err := ref.Get(ctx)
	if err != nil || !bookingBlockedUntil(snapshot.Data()).IsZero() || len(activeCancellationStrikes(snapshot.Data(), now.Add(time.Second))) != 2 {
		t.Fatalf("appeal did not transactionally pause strike: %v", err)
	}
	if _, err := store.appealPassengerCancellation(ctx, app.Principal{UID: uid}, payload); err == nil {
		t.Fatal("duplicate appeal accepted")
	}
	if _, err := store.adminReviewPassengerCancellation(ctx, adminIdentity{UID: "toda", Role: "toda_admin", TodaID: "toda"}, map[string]any{"bookingId": id, "decision": "uphold", "reason": "Review has been completed."}); err == nil {
		t.Fatal("TODA admin reviewed passenger restriction")
	}
	if _, err := store.adminReviewPassengerCancellation(ctx, adminIdentity{UID: "system", Role: "developer_admin"}, map[string]any{"bookingId": id, "decision": "uphold", "reason": "Reviewed booking evidence confirms passenger fault."}); err != nil {
		t.Fatal(err)
	}
	snapshot, err = ref.Get(ctx)
	if err != nil || !bookingBlockedUntil(snapshot.Data()).Equal(now.Add(24*time.Hour)) || integer(snapshot.Data(), "restrictionCount") != 1 {
		t.Fatalf("review changed original cooldown: %#v err=%v", snapshot.Data(), err)
	}
}

func TestEmulatorAdminMaskingAndAuditedScopedDisclosure(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	uid, id := "p-"+uuid.NewString(), "booking-"+uuid.NewString()
	data := map[string]any{"bookingId": id, "passengerId": uid, "passengerName": "Private Passenger", "passengerPhone": "09123456789", "driverId": "driver", "todaId": "toda-a", "status": "completed", "updatedAt": time.Now(), "pickupAddress": "Private House"}
	if _, err := store.firestore.Collection("bookings").Doc(id).Set(ctx, data); err != nil {
		t.Fatal(err)
	}
	for _, actor := range []adminIdentity{{UID: "system", Role: "developer_admin"}, {UID: "toda", Role: "toda_admin", TodaID: "toda-a"}} {
		result, err := store.adminListBookings(ctx, actor, map[string]any{"search": id})
		if err != nil {
			t.Fatal(err)
		}
		items := result["items"].([]map[string]any)
		if len(items) != 1 || items[0]["passengerName"] != passengerReference(uid) || items[0]["passengerPhone"] != nil {
			t.Fatalf("%s received private passenger identity: %#v", actor.Role, result)
		}
		if _, err := store.adminRevealPassengerDetails(ctx, actor, map[string]any{"bookingId": id, "reason": "short"}); err == nil {
			t.Fatal("private identity disclosed without investigation reason")
		}
		result, err = store.adminRevealPassengerDetails(ctx, actor, map[string]any{"bookingId": id, "reason": "Investigating the passenger's safety report."})
		if err != nil || result["details"].(map[string]any)["passengerName"] != "Private Passenger" {
			t.Fatalf("authorized disclosure failed: %#v err=%v", result, err)
		}
	}
	if _, err := store.adminRevealPassengerDetails(ctx, adminIdentity{UID: "other", Role: "toda_admin", TodaID: "other"}, map[string]any{"bookingId": id, "reason": "Investigating a report outside my scope."}); err == nil {
		t.Fatal("out-of-scope TODA accessed passenger identity")
	}
	logs, err := store.firestore.Collection("adminAuditLogs").Where("bookingId", "==", id).Documents(ctx).GetAll()
	if err != nil || len(logs) != 2 {
		t.Fatalf("expected two successful audited disclosures; got %d, %v", len(logs), err)
	}
}
