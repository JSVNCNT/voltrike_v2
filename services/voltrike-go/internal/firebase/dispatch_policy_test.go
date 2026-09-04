package firebase

import (
	"testing"
	"time"

	"github.com/voltrike/voltrike-go/internal/app"
)

func TestFutureTimeAcceptsLegacyLicenceDate(t *testing.T) {
	now := time.Date(2026, time.August, 6, 12, 0, 0, 0, time.UTC)
	if !futureTime("2026-08-06", now) {
		t.Fatal("expected a legacy calendar expiry to remain valid through its expiry day")
	}
	if futureTime("2026-08-05", now) {
		t.Fatal("expected an expired legacy calendar date to be rejected")
	}
	if futureTime("not-a-date", now) {
		t.Fatal("expected an invalid legacy expiry to be rejected")
	}
}

func TestDispatchServicePriority(t *testing.T) {
	request := app.DispatchRequest{
		PrimaryTodaIDs:     []string{"pickup-toda"},
		SecondaryTodaIDs:   []string{"destination-toda"},
		AllowAnyActiveToda: true,
	}
	if got := dispatchServicePriority("pickup-toda", request); got != 0 {
		t.Fatalf("pickup TODA priority = %d, want 0", got)
	}
	if got := dispatchServicePriority("destination-toda", request); got != 1 {
		t.Fatalf("destination TODA priority = %d, want 1", got)
	}
	if got := dispatchServicePriority("other-active-toda", request); got != 2 {
		t.Fatalf("fallback TODA priority = %d, want 2", got)
	}
}

func TestVehicleCanServeHonorsRequestedRideType(t *testing.T) {
	eTrike := map[string]any{"vehicleNumber": "E-Trike", "capacity": 2}
	eTuktuk := map[string]any{"vehicleNumber": "Electric Tuktuk", "capacity": 4}
	if !vehicleCanServe(eTrike, 2, "e_trike") || vehicleCanServe(eTrike, 2, "electric_tuktuk") {
		t.Fatal("E-Trike matching ignored the requested ride type")
	}
	if !vehicleCanServe(eTuktuk, 2, "electric_tuktuk") || vehicleCanServe(eTuktuk, 2, "e_trike") {
		t.Fatal("E-Tuktuk matching ignored the requested ride type")
	}
	if vehicleCanServe(eTrike, 3, "e_trike") {
		t.Fatal("E-Trike exceeded its registered two-passenger capacity")
	}
}
