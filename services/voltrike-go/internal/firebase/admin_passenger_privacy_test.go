package firebase

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestAdminPassengerMaskRemovesIdentityAndFreeTextWithoutMutatingBooking(t *testing.T) {
	booking := map[string]any{
		"passengerId": "passenger-1", "passengerName": "Private Passenger", "passengerPhone": "09123456789",
		"passengerEmail": "private@example.test", "passengerPhotoUrl": "https://private-photo.test",
		"pickup":     map[string]any{"latitude": 10.67, "longitude": 122.95},
		"pickupName": "Private House", "pickupAddress": "House 22, Barangay Taculing, Bacolod City",
		"destinationAddress": "Private Hospital", "passengerNote": "My name is Private Passenger",
		"authoritativeRoutePolyline": "private-path", "routeLegs": []any{"private-leg"},
		"driverName": "Driver Name", "status": "completed", "bookingId": "booking-1",
		"routeStops": []map[string]any{{"sequence": 0, "type": "pickup", "name": "Private House", "address": "House 22, Barangay Taculing, Bacolod City", "location": map[string]any{"latitude": 10.67}}},
	}
	masked := maskAdminPassengerData(booking)
	raw, _ := json.Marshal(masked)
	for _, secret := range []string{"Private Passenger", "09123456789", "private@example.test", "private-photo", "House 22", "Private House", "Private Hospital", "private-path", "private-leg", "10.67"} {
		if strings.Contains(string(raw), secret) {
			t.Fatalf("admin response leaked %q: %s", secret, raw)
		}
	}
	if masked["passengerName"] != passengerReference("passenger-1") || masked["pickupAddress"] != "Barangay Taculing" || masked["driverName"] != "Driver Name" {
		t.Fatalf("safe operational fields lost: %#v", masked)
	}
	if booking["passengerName"] != "Private Passenger" || booking["pickupAddress"] != "House 22, Barangay Taculing, Bacolod City" || booking["pickup"] == nil {
		t.Fatal("masking modified participant booking data")
	}
	if again, _ := json.Marshal(maskAdminPassengerData(masked)); string(again) != string(raw) {
		t.Fatal("repeated masking changed presentation")
	}
}

func TestAdminReportMasksPassengerAndPreservesDriverReviewIdentity(t *testing.T) {
	report := map[string]any{
		"reportId": "report-1", "reporterId": "passenger-1", "reporterRole": "passenger",
		"reporterName": "Private Passenger", "reporterProfile": map[string]any{"firstName": "Private", "email": "private@example.test"},
		"reportedUserId": "driver-1", "reportedRole": "driver", "reportedUser": map[string]any{"firstName": "Driver", "isActive": true},
		"details": "Private Passenger lives at House 22",
	}
	masked := maskAdminPassengerData(report)
	raw, _ := json.Marshal(masked)
	if strings.Contains(string(raw), "Private Passenger") || strings.Contains(string(raw), "private@example.test") || strings.Contains(string(raw), "House 22") {
		t.Fatalf("report leaked passenger data: %s", raw)
	}
	if text(masked["reportedUser"].(map[string]any), "firstName") != "Driver" {
		t.Fatal("driver verification identity was removed")
	}
}

func TestAdminLegacyReportDefaultsUnknownPartiesToRestricted(t *testing.T) {
	masked := maskAdminPassengerData(map[string]any{"reportId": "old", "reporterId": "p", "reporter": map[string]any{"firstName": "Private"}})
	if text(masked["reporter"].(map[string]any), "firstName") != passengerReference("p") {
		t.Fatal("unknown legacy passenger identity leaked")
	}
}

func TestAdminChatAndRatingsMaskAllFreeText(t *testing.T) {
	for _, record := range []map[string]any{
		{"incidentId": "chat-1", "senderRole": "passenger", "senderId": "p", "senderName": "Private Passenger", "originalText": "Private Passenger", "displayText": "Private Passenger"},
		{"passengerId": "p", "passengerName": "Private Passenger", "comment": "Private Passenger", "rating": 5},
	} {
		masked := maskAdminResult(map[string]any{"items": []map[string]any{record}, "item": record})
		raw, _ := json.Marshal(masked)
		if strings.Contains(string(raw), "Private Passenger") {
			t.Fatalf("list/detail result leaked identity: %s", raw)
		}
	}
}

func TestPassengerReferenceIsStableDistinctAndIndependentOfNames(t *testing.T) {
	if passengerReference("p") != passengerReference("p") || passengerReference("p") == passengerReference("q") || !strings.HasPrefix(passengerReference("p"), "Passenger P-") {
		t.Fatal("invalid passenger references")
	}
	if strings.Contains(passengerReference(""), "P-") {
		t.Fatal("missing identity received a synthetic shared passenger reference")
	}
}

func TestAdminAreaLabelDoesNotEchoAddressSuffixOrUnknownBarangay(t *testing.T) {
	for input, expected := range map[string]string{
		"House 22, Barangay Taculing, Bacolod":              "Barangay Taculing",
		"Barangay Taculing — Private Passenger at House 22": "Barangay Taculing",
		"Barangay Private Passenger":                        "Location restricted",
		"Barangay 40 Private House 22":                      "Barangay 40",
		"Barangay 99":                                       "Location restricted",
	} {
		if got := adminAreaLabel(input); got != expected {
			t.Fatalf("area label %q=%q, want %q", input, got, expected)
		}
	}
}
