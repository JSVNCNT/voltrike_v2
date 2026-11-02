package firebase

import (
	"context"
	"testing"
	"time"

	"github.com/voltrike/voltrike-go/internal/config"
)

func demoTestData(bookingID string, now time.Time) map[string]any {
	return map[string]any{"isDemo": true, "seedTag": demoActivationTag, "todaId": demoActivationToda, "bookingId": bookingID, "createdAt": now.Add(-time.Hour), "updatedAt": now.Add(-time.Hour)}
}

func demoTestHolding(collection, id, bookingID string, now time.Time) demoActivationRecord {
	data := demoTestData(bookingID, now)
	return demoActivationRecord{ID: collection + "-" + id, UpdateTime: now.Add(-2 * time.Hour), Data: map[string]any{
		"seedTag": demoActivationTag, "isDemo": true, "todaId": demoActivationToda,
		"date": now.In(demoActivationZone).Format(time.DateOnly), "activationStatus": "held",
		"originalCollection": collection, "originalId": id, "data": data,
	}}
}

func TestDemoActivationUsesUTCPlusEightAndGatesWholeBookingGroup(t *testing.T) {
	now := time.Date(2026, 11, 1, 18, 0, 0, 0, time.UTC) // November 2 in the original job's timezone.
	ready := demoTestHolding("bookings", "ready", "ready", now)
	blockedBooking := demoTestHolding("bookings", "blocked", "blocked", now)
	blockedSettlement := demoTestHolding("settlements", "blocked", "blocked", now)
	blockedSettlement.Data["data"].(map[string]any)["settlementTimestamp"] = now.Add(time.Minute)
	tomorrow := demoTestHolding("bookings", "tomorrow", "tomorrow", now)
	tomorrow.Data["date"] = "2026-11-03"
	activated := demoTestHolding("bookings", "already", "already", now)
	activated.Data["activationStatus"] = "activated"
	eligible, err := eligibleDemoActivationRecords([]demoActivationRecord{ready, blockedBooking, blockedSettlement, tomorrow, activated}, now)
	if err != nil || len(eligible) != 1 || eligible[0].ID != ready.ID {
		t.Fatalf("future timestamps or dates were activated: %#v %v", eligible, err)
	}
}

func TestDemoActivationCutoffAndProjectGuardRunBeforeDatabaseAccess(t *testing.T) {
	store := &Store{cfg: config.Config{ProjectID: demoActivationProject}}
	result, err := store.activateDemoAt(context.Background(), time.Date(2027, 2, 28, 16, 0, 0, 0, time.UTC))
	if err != nil || result["reason"] != "demo_period_ended" {
		t.Fatalf("job accessed Firestore after the original cutoff: %v %v", result, err)
	}
	if _, err := (&Store{cfg: config.Config{ProjectID: "different-project"}}).ActivateDemo(context.Background()); err == nil {
		t.Fatal("job accepted another production project")
	}
	if _, _, err := OpenDemoActivation(context.Background(), "different-project"); err == nil {
		t.Fatal("constructor accepted another project")
	}
}

func TestDemoActivationPlanningIsCreateOnlyAndRejectsScopeExpansion(t *testing.T) {
	now := time.Date(2026, 11, 2, 3, 0, 0, 0, time.UTC)
	held := demoTestHolding("bookings", "trip", "trip", now)
	writes, added, err := planDemoActivationWrites([]demoActivationRecord{held}, nil, now)
	if err != nil || added != 1 || len(writes) != 2 || writes[0].create == nil || writes[1].updateTime != held.UpdateTime {
		t.Fatalf("activation lost create-only or holding update preconditions: %v %v", writes, err)
	}
	before := map[string][]demoActivationRecord{"bookings": {{ID: "trip", Data: demoTestData("trip", now)}}}
	writes, added, err = planDemoActivationWrites([]demoActivationRecord{held}, before, now)
	if err != nil || added != 0 || len(writes) != 1 || writes[0].collection != "demoSeedFutureRecords" {
		t.Fatal("existing synthetic live record was overwritten")
	}
	for _, change := range []func(*demoActivationRecord){
		func(record *demoActivationRecord) { record.Data["isDemo"] = false },
		func(record *demoActivationRecord) { record.Data["todaId"] = "different-toda" },
		func(record *demoActivationRecord) { record.Data["originalCollection"] = "users" },
		func(record *demoActivationRecord) { record.Data["originalId"] = "parent/child" },
		func(record *demoActivationRecord) {
			record.Data["data"].(map[string]any)["seedTag"] = "another-dataset"
		},
		func(record *demoActivationRecord) {
			record.Data["data"].(map[string]any)["completedAt"] = now.Add(time.Hour)
		},
	} {
		changed := demoTestHolding("bookings", "trip", "trip", now)
		change(&changed)
		if _, _, err := planDemoActivationWrites([]demoActivationRecord{changed}, nil, now); err == nil {
			t.Fatal("activation accepted an unsafe held record")
		}
	}
}

func TestDemoActivationSummariesPreserveSeededDriverAndPassengerMetrics(t *testing.T) {
	now := time.Date(2026, 11, 2, 3, 0, 0, 0, time.UTC)
	driver, passenger := demoTestData("", now), demoTestData("", now)
	driver["uid"], passenger["uid"] = "driver", "passenger"
	delete(passenger, "todaId") // The original seeder omits a passenger's TODA.
	before := map[string][]demoActivationRecord{"drivers": {{ID: "driver", Data: driver, UpdateTime: now.Add(-time.Hour)}}, "passengers": {{ID: "passenger", Data: passenger, UpdateTime: now.Add(-time.Hour)}}}
	after := map[string][]demoActivationRecord{
		"settlements": {{Data: map[string]any{"driverId": "driver", "grossFare": int64(100)}}, {Data: map[string]any{"driverId": "driver", "grossFare": 150.5}}, {Data: map[string]any{"driverId": "other", "grossFare": 999}}},
		"ratings":     {{Data: map[string]any{"driverId": "driver", "rating": int64(4)}}, {Data: map[string]any{"driverId": "driver", "rating": int64(5)}}},
		"bookings":    {{Data: map[string]any{"passengerId": "passenger", "status": "completed"}}, {Data: map[string]any{"passengerId": "passenger", "status": "cancelled"}}},
	}
	writes, err := planDemoProfileSummaries(before, after, now)
	if err != nil || len(writes) != 2 {
		t.Fatalf("profile summaries failed: %v", err)
	}
	values := map[string]any{}
	for _, update := range writes[0].updates {
		values[update.Path] = update.Value
	}
	if values["completedTrips"] != 2 || values["totalEarnings"] != 250.5 || values["ratingCount"] != 2 || values["rating"] != 4.5 {
		t.Fatalf("driver summary changed: %#v", values)
	}
	if writes[1].updates[0].Value != 1 {
		t.Fatal("passenger summary counted non-completed bookings")
	}
	driver["isDemo"] = false
	if _, err := planDemoProfileSummaries(before, after, now); err == nil {
		t.Fatal("profile refresh accepted a non-demo driver")
	}
}

func TestDemoActivationVerificationRejectsOrphansAndChangedFutureHoldings(t *testing.T) {
	now := time.Date(2026, 11, 2, 3, 0, 0, 0, time.UTC)
	future := demoTestHolding("bookings", "future", "future", now)
	future.Data["date"] = "2026-11-03"
	before := map[string][]demoActivationRecord{"demoSeedFutureRecords": {future}}
	after := map[string][]demoActivationRecord{"demoSeedFutureRecords": {future}, "bookings": {{ID: "trip", Data: demoTestData("trip", now)}}}
	if _, err := verifyDemoActivation(before, after, now); err != nil {
		t.Fatal(err)
	}
	after["reports"] = []demoActivationRecord{{Data: map[string]any{"bookingId": "missing"}}}
	if _, err := verifyDemoActivation(before, after, now); err == nil {
		t.Fatal("verification accepted an orphaned synthetic report")
	}
	delete(after, "reports")
	changed := future
	changed.UpdateTime = now
	after["demoSeedFutureRecords"] = []demoActivationRecord{changed}
	if _, err := verifyDemoActivation(before, after, now); err == nil {
		t.Fatal("verification accepted a modified future holding")
	}
}
