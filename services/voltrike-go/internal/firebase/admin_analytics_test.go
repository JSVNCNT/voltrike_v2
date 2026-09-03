package firebase

import (
	"testing"
	"time"
)

func TestBuildOverviewAnalyticsUsesRealScopedDocuments(t *testing.T) {
	location, err := time.LoadLocation("Asia/Manila")
	if err != nil {
		t.Fatal(err)
	}
	start := time.Date(2026, time.August, 1, 0, 0, 0, 0, location)
	end := start.AddDate(0, 0, overviewAnalyticsDays)
	actor := adminIdentity{Role: "toda_admin", TodaID: "toda-a"}
	bookings := []map[string]any{
		{"todaId": "toda-a", "createdAt": start.Add(3 * time.Hour)},
		{"todaId": "toda-a", "createdAt": start.AddDate(0, 0, 1).Add(4 * time.Hour)},
		{"todaId": "toda-b", "createdAt": start.AddDate(0, 0, 1).Add(5 * time.Hour)},
	}
	settlements := []map[string]any{
		{"todaId": "toda-a", "status": "settled", "settlementTimestamp": start.AddDate(0, 0, 1).Add(6 * time.Hour), "grossFare": 100.0, "commissionAmount": 10.0, "driverNetEarnings": 90.0},
		{"todaId": "toda-a", "status": "pending", "settlementTimestamp": start.AddDate(0, 0, 1).Add(7 * time.Hour), "grossFare": 50.0},
		{"todaId": "toda-b", "status": "settled", "settlementTimestamp": start.AddDate(0, 0, 1).Add(8 * time.Hour), "grossFare": 500.0, "commissionAmount": 50.0, "driverNetEarnings": 450.0},
	}

	result := buildOverviewAnalytics(actor, bookings, settlements, start, end, location)
	days := result["days"].([]map[string]any)
	if got := integer(days[0], "bookings"); got != 1 {
		t.Fatalf("day one bookings = %d, want 1", got)
	}
	if got := integer(days[1], "bookings"); got != 1 {
		t.Fatalf("day two bookings = %d, want 1", got)
	}
	if got := integer(days[1], "completedRides"); got != 1 {
		t.Fatalf("day two completed rides = %d, want 1", got)
	}
	for _, field := range []string{"grossFare", "commissionAmount", "driverNetEarnings"} {
		if _, exposed := days[1][field]; exposed {
			t.Fatalf("admin analytics exposed financial field %q", field)
		}
	}
	if result["scope"] != "toda-a" {
		t.Fatalf("scope = %v, want toda-a", result["scope"])
	}
}

func TestBuildOverviewAnalyticsUsesManilaCalendarDays(t *testing.T) {
	location, err := time.LoadLocation("Asia/Manila")
	if err != nil {
		t.Fatal(err)
	}
	start := time.Date(2026, time.August, 1, 0, 0, 0, 0, location)
	end := start.AddDate(0, 0, overviewAnalyticsDays)
	actor := adminIdentity{Role: "developer_admin"}
	// 16:30 UTC is already the following calendar day in Manila.
	createdAt := time.Date(2026, time.August, 1, 16, 30, 0, 0, time.UTC)
	result := buildOverviewAnalytics(actor, []map[string]any{{"createdAt": createdAt}}, nil, start, end, location)
	days := result["days"].([]map[string]any)
	if got := integer(days[1], "bookings"); got != 1 {
		t.Fatalf("Manila day two bookings = %d, want 1", got)
	}
}

func TestAdminMetricStatusOpenExcludesTerminalRecords(t *testing.T) {
	for _, test := range []struct {
		name string
		data map[string]any
		want bool
	}{
		{name: "open report", data: map[string]any{"status": "open"}, want: true},
		{name: "legacy report", data: map[string]any{}, want: true},
		{name: "resolved report", data: map[string]any{"status": "resolved"}, want: false},
		{name: "responding safety incident", data: map[string]any{"responseStatus": "responding", "status": "open"}, want: true},
		{name: "resolved safety response", data: map[string]any{"responseStatus": "resolved", "status": "open"}, want: false},
	} {
		t.Run(test.name, func(t *testing.T) {
			if got := adminMetricStatusOpen(test.data, "open", "reported", "acknowledged", "responding"); got != test.want {
				t.Fatalf("adminMetricStatusOpen() = %v, want %v", got, test.want)
			}
		})
	}
}

func TestRedactAdminFinancialFields(t *testing.T) {
	data := map[string]any{
		"bookingId":         "booking-1",
		"status":            "completed",
		"amountDue":         80.0,
		"grossFare":         80.0,
		"commissionAmount":  2.0,
		"driverNetEarnings": 78.0,
		"totalEarnings":     500.0,
		"fareBreakdown":     map[string]any{"total": 80.0},
	}

	redactAdminFinancialFields(data)

	for _, field := range []string{
		"amountDue", "grossFare", "commissionAmount", "driverNetEarnings",
		"totalEarnings", "fareBreakdown",
	} {
		if _, exposed := data[field]; exposed {
			t.Fatalf("admin record exposed financial field %q", field)
		}
	}
	if data["bookingId"] != "booking-1" || data["status"] != "completed" {
		t.Fatal("redaction removed operational booking fields")
	}
}
