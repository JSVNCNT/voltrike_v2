package firebase

import (
	"testing"
	"time"
)

func TestSettlementSnapshotStoresOneRidePriceWithoutCommission(t *testing.T) {
	settlement, err := settlementSnapshot(map[string]any{
		"amountDue":         82.345,
		"commissionPercent": 30.0,
		"passengerId":       "passenger-1",
		"driverId":          "driver-1",
		"todaId":            "toda-1",
	}, "booking-123", time.Unix(1, 0).UTC())
	if err != nil {
		t.Fatal(err)
	}
	if got := number(settlement, "amountDue"); got != 82.35 {
		t.Fatalf("ride price = %.2f, want 82.35", got)
	}
	if got := number(settlement, "grossFare"); got != 82.35 {
		t.Fatalf("settled fare = %.2f, want 82.35", got)
	}
	for _, field := range []string{
		"commissionPercent", "commissionAmount", "driverNetEarnings",
	} {
		if _, exists := settlement[field]; exists {
			t.Fatalf("settlement exposed removed field %q", field)
		}
	}
}
