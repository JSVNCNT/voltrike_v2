package firebase

import (
	"context"
	"os"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/config"
	"google.golang.org/api/option"
)

func demoActivationEmulatorStore(t *testing.T) (*Store, context.Context) {
	t.Helper()
	host := os.Getenv("FIRESTORE_EMULATOR_HOST")
	if host == "" {
		t.Skip("requires local FIRESTORE_EMULATOR_HOST")
	}
	if !strings.HasPrefix(host, "127.0.0.1:") && !strings.HasPrefix(host, "localhost:") {
		t.Fatal("demo activation tests must use a loopback emulator")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	// A unique emulator-only project keeps the fixed seed tag isolated between
	// test cases and repeated runs; production project checks remain enabled.
	project := "demo-activation-" + strings.ReplaceAll(uuid.NewString(), "-", "")[:12]
	client, err := firestore.NewClient(ctx, project, option.WithoutAuthentication())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return &Store{firestore: client, cfg: config.Config{ProjectID: demoActivationProject}}, ctx
}

func TestEmulatorDemoActivationPreservesFutureGroupsAndUnrelatedProfiles(t *testing.T) {
	store, ctx := demoActivationEmulatorStore(t)
	now := time.Date(2026, 11, 2, 3, 0, 0, 0, time.UTC)
	for _, collection := range []string{"bookings", "settlements", "ratings", "reports"} {
		held := demoTestHolding(collection, "ready", "ready", now)
		data := held.Data["data"].(map[string]any)
		data["driverId"], data["passengerId"], data["status"] = "driver", "passenger", "completed"
		data["grossFare"], data["rating"] = 250.0, 5.0
		if _, err := store.firestore.Collection("demoSeedFutureRecords").Doc(held.ID).Set(ctx, held.Data); err != nil {
			t.Fatal(err)
		}
	}
	blockedBooking := demoTestHolding("bookings", "blocked", "blocked", now)
	blockedSettlement := demoTestHolding("settlements", "blocked", "blocked", now)
	blockedSettlement.Data["data"].(map[string]any)["settlementTimestamp"] = now.Add(time.Hour)
	tomorrow := demoTestHolding("bookings", "tomorrow", "tomorrow", now)
	tomorrow.Data["date"] = "2026-11-03"
	for _, held := range []demoActivationRecord{blockedBooking, blockedSettlement, tomorrow} {
		if _, err := store.firestore.Collection("demoSeedFutureRecords").Doc(held.ID).Set(ctx, held.Data); err != nil {
			t.Fatal(err)
		}
	}
	futureBefore, err := store.firestore.Collection("demoSeedFutureRecords").Doc(tomorrow.ID).Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	driver, passenger := demoTestData("", now), demoTestData("", now)
	driver["uid"], passenger["uid"] = "driver", "passenger"
	delete(passenger, "todaId")
	for collection, data := range map[string]map[string]any{"drivers": driver, "passengers": passenger} {
		if _, err := store.firestore.Collection(collection).Doc(text(data, "uid")).Set(ctx, data); err != nil {
			t.Fatal(err)
		}
	}
	ordinary := store.firestore.Collection("drivers").Doc("ordinary-real-driver")
	if _, err := ordinary.Set(ctx, map[string]any{"isDemo": false, "completedTrips": 99}); err != nil {
		t.Fatal(err)
	}
	result, err := store.activateDemoAt(ctx, now)
	if err != nil || result["addedLiveDocuments"] != 4 || result["liveBookings"] != 1 || result["liveSettlements"] != 1 {
		t.Fatalf("demo activation result = %v, %v", result, err)
	}
	driverAfter, err := store.firestore.Collection("drivers").Doc("driver").Get(ctx)
	if err != nil || integer(driverAfter.Data(), "completedTrips") != 1 || number(driverAfter.Data(), "totalEarnings") != 250 || number(driverAfter.Data(), "rating") != 5 {
		t.Fatalf("seeded driver summaries changed: %v", err)
	}
	passengerAfter, err := store.firestore.Collection("passengers").Doc("passenger").Get(ctx)
	if err != nil || integer(passengerAfter.Data(), "totalTrips") != 1 {
		t.Fatalf("seeded passenger summary changed: %v", err)
	}
	ordinaryAfter, err := ordinary.Get(ctx)
	if err != nil || integer(ordinaryAfter.Data(), "completedTrips") != 99 {
		t.Fatal("ordinary driver was changed by synthetic activation")
	}
	for _, id := range []string{blockedBooking.ID, blockedSettlement.ID, tomorrow.ID} {
		snapshot, err := store.firestore.Collection("demoSeedFutureRecords").Doc(id).Get(ctx)
		if err != nil || text(snapshot.Data(), "activationStatus") != "held" {
			t.Fatal("future synthetic holding was activated")
		}
		if id == tomorrow.ID && !snapshot.UpdateTime.Equal(futureBefore.UpdateTime) {
			t.Fatal("future holding updateTime changed")
		}
	}
	// A second hourly execution does not recreate data or rebuild summaries.
	if result, err := store.activateDemoAt(ctx, now); err != nil || result["reason"] != "no_records_due" {
		t.Fatalf("repeated activation was not idempotent: %v %v", result, err)
	}
}

func TestEmulatorDemoActivationCannotOverwriteUnrelatedDestination(t *testing.T) {
	store, ctx := demoActivationEmulatorStore(t)
	now := time.Date(2026, 11, 2, 3, 0, 0, 0, time.UTC)
	held := demoTestHolding("bookings", "collision", "collision", now)
	holding := store.firestore.Collection("demoSeedFutureRecords").Doc(held.ID)
	if _, err := holding.Set(ctx, held.Data); err != nil {
		t.Fatal(err)
	}
	live := store.firestore.Collection("bookings").Doc("collision")
	if _, err := live.Set(ctx, map[string]any{"isDemo": false, "sentinel": "ordinary-existing-record"}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.activateDemoAt(ctx, now); err == nil {
		t.Fatal("activation overwrote an existing unmarked booking")
	}
	snapshot, err := live.Get(ctx)
	if err != nil || text(snapshot.Data(), "sentinel") != "ordinary-existing-record" || snapshot.Data()["isDemo"] != false {
		t.Fatal("unrelated live booking changed")
	}
	snapshot, err = holding.Get(ctx)
	if err != nil || text(snapshot.Data(), "activationStatus") != "held" {
		t.Fatal("holding was marked active despite failed create precondition")
	}
}
