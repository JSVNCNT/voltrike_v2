package firebase

import (
	"testing"
	"time"

	"github.com/voltrike/voltrike-go/internal/app"
)

func TestPublicTodaDataExcludesLegalRegistration(t *testing.T) {
	payload := map[string]any{
		"cityName":     "Bacolod City",
		"registration": map[string]any{"presidentTin": "private"},
		"documents":    map[string]any{"permit": "private"},
		"submittedBy":  "private-user",
	}
	public := publicTodaData(payload, "toda-1", "Central TODA", "pending", false, time.Unix(1, 0))
	for _, key := range []string{"registration", "documents", "submittedBy"} {
		if _, exists := public[key]; exists {
			t.Fatalf("public TODA data leaked %q", key)
		}
	}
	if public["cityName"] != "Bacolod City" || public["name"] != "Central TODA" {
		t.Fatalf("public directory fields missing: %#v", public)
	}
}

func TestAdminIdentityRequiresMatchingActiveClaims(t *testing.T) {
	principal := app.Principal{UID: "admin-1", Claims: map[string]any{
		"adminRole": "toda_admin", "todaId": "toda-1",
	}}
	identity, err := adminIdentityFromProfile(principal, map[string]any{
		"role": "toda_admin", "todaId": "toda-1", "isActive": true,
	})
	if err != nil || !identity.canAccessToda("toda-1") || identity.canAccessToda("toda-2") {
		t.Fatalf("unexpected scoped identity: %#v err=%v", identity, err)
	}
	if _, err := adminIdentityFromProfile(principal, map[string]any{
		"role": "toda_admin", "todaId": "toda-1", "isActive": false,
	}); err == nil {
		t.Fatal("inactive administrator was accepted")
	}
	if _, err := adminIdentityFromProfile(principal, map[string]any{
		"role": "developer_admin", "isActive": true,
	}); err == nil {
		t.Fatal("mismatched administrator claim was accepted")
	}
}

func TestAdminBookingMatchesSearchOperationalFields(t *testing.T) {
	booking := map[string]any{
		"passengerName":      "Passenger Test",
		"driverName":         "Driver Test",
		"plateNumber":        "ABC-1234",
		"todaName":           "Barangay 40 TODA",
		"pickupAddress":      "Burgos Avenue",
		"destinationAddress": "Metro Bacolod Hospital",
		"receiptNumber":      "VT-NEW-RIDE",
		"status":             "passengerOnBoard",
	}
	for _, needle := range []string{
		"new-booking-id", "passenger test", "driver test", "abc-1234",
		"barangay 40", "burgos", "hospital", "vt-new-ride", "passengeronboard",
	} {
		if !adminBookingMatchesSearch("new-booking-id", booking, needle) {
			t.Fatalf("booking did not match %q", needle)
		}
	}
	if adminBookingMatchesSearch("new-booking-id", booking, "unrelated ride") {
		t.Fatal("booking matched unrelated search")
	}
}
