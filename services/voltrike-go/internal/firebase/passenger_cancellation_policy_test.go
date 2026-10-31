package firebase

import (
	"fmt"
	"testing"
	"time"
)

func TestCancellationAssessmentProtectsSearchingAndSafetyCases(t *testing.T) {
	assigned := map[string]any{"passengerId": "p", "driverId": "d", "status": "driverAssigned"}
	for _, test := range []struct{ actor, action, reason, want string }{
		{"p", "cancel", "change_of_plans", "counted"},
		{"p", "cancel", "booked_by_mistake", "counted"},
		{"p", "cancel", "safety_concern", "pending_review"},
		{"p", "cancel", "driver_asked_me_to_cancel", "pending_review"},
		{"p", "cancel", "driver_is_taking_too_long", "pending_review"},
		{"p", "cancel", "driver_is_not_moving", "pending_review"},
		{"p", "cancel", "unknown_or_forged", "pending_review"},
		{"p", "noShow", "", "excluded"},
		{"d", "noShow", "", "pending_review"},
		{"d", "cancel", "change_of_plans", "excluded"},
	} {
		t.Run(test.actor+test.action+test.reason, func(t *testing.T) {
			if got := cancellationAssessment(assigned, test.actor, test.action, test.reason); got != test.want {
				t.Fatalf("assessment=%q, want %q", got, test.want)
			}
		})
	}
	for _, reason := range []string{"change_of_plans", "booked_by_mistake", "search_timeout"} {
		if got := cancellationAssessment(map[string]any{"passengerId": "p", "status": "pending"}, "p", "cancel", reason); got != "excluded" {
			t.Fatalf("searching cancellation counted: %s", reason)
		}
	}
}

func TestThirdStrikeBlocksForFull24HoursAndIsIdempotent(t *testing.T) {
	now := time.Date(2026, 10, 31, 15, 58, 0, 0, time.UTC)
	policy := map[string]any{}
	for index := 1; index <= 3; index++ {
		at := now.Add(time.Duration(index-3) * time.Hour)
		policy = addCancellationStrike(policy, fmt.Sprint(index), at, at)
		if index < 3 && !bookingBlockedUntil(policy).IsZero() {
			t.Fatalf("blocked at strike %d", index)
		}
	}
	if until := bookingBlockedUntil(policy); !until.Equal(now.Add(24 * time.Hour)) {
		t.Fatalf("cooldown ends at %v; expected full 24 hours", until)
	}
	policy = addCancellationStrike(policy, "3", now, now.Add(time.Minute))
	if integer(policy, "restrictionCount") != 1 || len(activeCancellationStrikes(policy, now.Add(time.Minute))) != 3 || !bookingBlockedUntil(policy).Equal(now.Add(24*time.Hour)) {
		t.Fatalf("duplicate cancellation changed penalty: %#v", policy)
	}
}

func TestRollingWindowPreservesNativeFirestoreTimes(t *testing.T) {
	now := time.Now().UTC()
	policy := map[string]any{"strikes": []any{
		map[string]any{"bookingId": "inside", "at": now.Add(-24*time.Hour + time.Second)},
		map[string]any{"bookingId": "boundary", "at": now.Add(-24 * time.Hour)},
		map[string]any{"bookingId": "future", "at": now.Add(time.Second)},
		map[string]any{"bookingId": "bad", "at": "not a server timestamp"},
	}}
	strikes := activeCancellationStrikes(policy, now)
	if len(strikes) != 1 || strikes[0]["bookingId"] != "inside" {
		t.Fatalf("incorrect rolling strikes: %#v", strikes)
	}
	policy = addCancellationStrike(policy, "next", now, now)
	if len(activeCancellationStrikes(policy, now)) != 2 || !bookingBlockedUntil(policy).IsZero() {
		t.Fatalf("expired or malformed strike contributed to restriction: %#v", policy)
	}
}

func restrictedTestPolicy(now time.Time) map[string]any {
	policy := map[string]any{}
	for _, id := range []string{"one", "two", "three"} {
		policy = addCancellationStrike(policy, id, now, now)
	}
	return policy
}

func TestAppealPausesAutomaticRestrictionAndKeepsManualRestriction(t *testing.T) {
	now := time.Now().UTC()
	policy := restrictedTestPolicy(now)
	manual := now.Add(72 * time.Hour)
	policy["manualBlockedUntil"] = manual
	policy = removeCancellationStrike(policy, "two", now.Add(time.Minute))
	if !storedTime(policy["blockedUntil"]).IsZero() || !bookingBlockedUntil(policy).Equal(manual) {
		t.Fatalf("appeal did not preserve manual decision: %#v", policy)
	}
}

func TestUnrelatedOldCancellationCannotLiftCurrentRestriction(t *testing.T) {
	now := time.Now().UTC()
	policy := restrictedTestPolicy(now)
	policy = removeCancellationStrike(policy, "old-unrelated-booking", now.Add(23*time.Hour))
	if !bookingBlockedUntil(policy).Equal(now.Add(24 * time.Hour)) {
		t.Fatal("unrelated cancellation lifted restriction")
	}
}

func TestUpheldAppealResumesOriginalExpiryWithoutNewRestriction(t *testing.T) {
	now := time.Now().UTC()
	policy := removeCancellationStrike(restrictedTestPolicy(now), "two", now.Add(time.Hour))
	policy["disputedBookingIds"] = []string{"two"}
	policy = upholdCancellationStrike(policy, "two", now, now.Add(2*time.Hour))
	if !bookingBlockedUntil(policy).Equal(now.Add(24*time.Hour)) || integer(policy, "restrictionCount") != 1 {
		t.Fatalf("upheld appeal extended or duplicated restriction: %#v", policy)
	}
}

func TestMultipleAppealsRemainPausedUntilAllBasisDisputesResolve(t *testing.T) {
	now := time.Now().UTC()
	policy := removeCancellationStrike(restrictedTestPolicy(now), "one", now)
	policy = removeCancellationStrike(policy, "two", now)
	policy["disputedBookingIds"] = []string{"one", "two"}
	policy = upholdCancellationStrike(policy, "one", now, now.Add(time.Hour))
	if !storedTime(policy["blockedUntil"]).IsZero() {
		t.Fatal("restriction resumed while another qualifying strike was disputed")
	}
	policy = upholdCancellationStrike(policy, "two", now, now.Add(2*time.Hour))
	if !bookingBlockedUntil(policy).Equal(now.Add(24 * time.Hour)) {
		t.Fatal("restriction failed to resume after both appeals were upheld")
	}
}

func TestWaivedBasisCannotBeReinstatedByAnotherUpheldAppeal(t *testing.T) {
	now := time.Now().UTC()
	policy := removeCancellationStrike(restrictedTestPolicy(now), "one", now)
	policy = removeCancellationStrike(policy, "two", now)
	policy["disputedBookingIds"] = []string{"two"}
	policy["restrictionBookingIds"] = []string{"two", "three"} // one was waived
	policy = upholdCancellationStrike(policy, "two", now, now.Add(time.Hour))
	if !bookingBlockedUntil(policy).IsZero() {
		t.Fatal("a waived strike was counted toward a resumed restriction")
	}
}

func TestNoShowEvidenceRequiresFreshAccurateGPSNearPickup(t *testing.T) {
	now := time.Now().UTC()
	booking := map[string]any{"pickup": map[string]any{"latitude": 10.67, "longitude": 122.95}}
	location := map[string]any{"latitude": 10.67, "longitude": 122.95, "online": true, "accuracy": 15, "timestamp": now.UnixMilli(), "receivedAt": now.UnixMilli()}
	if !verifiedPickupArrival(booking, location, now) {
		t.Fatal("valid arrival was not verified")
	}
	for _, change := range []map[string]any{
		{"latitude": 10.69}, {"accuracy": 300}, {"timestamp": now.Add(-2 * time.Minute).UnixMilli()},
		{"receivedAt": now.Add(-2 * time.Minute).UnixMilli()}, {"online": false}, {"timestamp": now.Add(time.Minute).UnixMilli()},
	} {
		candidate := copyMap(location)
		for key, value := range change {
			candidate[key] = value
		}
		if verifiedPickupArrival(booking, candidate, now) {
			t.Fatalf("invalid arrival verified: %#v", change)
		}
	}
}
