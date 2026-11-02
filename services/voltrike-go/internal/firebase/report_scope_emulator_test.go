package firebase

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

func TestEmulatorReportCreationReplacesLegacyScopeEnrichmentBeforeNotification(t *testing.T) {
	store, ctx := passengerPolicyEmulatorStore(t)
	for _, scenario := range []struct {
		name          string
		bookingField  string
		driverMissing bool
		reporterRole  string
	}{
		{name: "legacy booking driver lookup", reporterRole: "passenger"},
		{name: "booking TODA remains authoritative", bookingField: "todaId", reporterRole: "passenger"},
		{name: "booking TODA alias remains authoritative", bookingField: "driverTodaId", reporterRole: "passenger"},
		{name: "passenger report audience", reporterRole: "driver"},
		{name: "missing driver is developer only", driverMissing: true, reporterRole: "passenger"},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			bookingID, reportID := "booking-"+uuid.NewString(), "report-"+uuid.NewString()
			passengerID, driverID := "passenger-"+uuid.NewString(), "driver-"+uuid.NewString()
			todaID := "toda-" + uuid.NewString()
			booking := map[string]any{"passengerId": passengerID, "driverId": driverID}
			if scenario.bookingField != "" {
				booking[scenario.bookingField] = todaID
			}
			if _, err := store.firestore.Collection("bookings").Doc(bookingID).Set(ctx, booking); err != nil {
				t.Fatal(err)
			}
			if !scenario.driverMissing {
				driverTodaID := todaID
				if scenario.bookingField != "" {
					driverTodaID = "different-current-toda"
				}
				if _, err := store.firestore.Collection("drivers").Doc(driverID).Set(ctx, map[string]any{"todaId": driverTodaID}); err != nil {
					t.Fatal(err)
				}
			} else {
				todaID = ""
			}
			reporterID, reportedRole := passengerID, "driver"
			if scenario.reporterRole == "driver" {
				reporterID, reportedRole = driverID, "passenger"
			}
			payload := map[string]any{"reportId": reportID, "bookingId": bookingID, "category": "safety", "details": "A report requiring review"}
			if _, err := store.createRideReport(ctx, app.Principal{UID: reporterID}, payload); err != nil {
				t.Fatal(err)
			}
			report, err := store.firestore.Collection("reports").Doc(reportID).Get(ctx)
			if err != nil {
				t.Fatal(err)
			}
			if text(report.Data(), "todaId") != todaID || text(report.Data(), "reportedRole") != reportedRole {
				t.Fatalf("report lost trusted booking/driver scope or roles: %#v", report.Data())
			}
			audience := stringSlice(report.Data()["reviewAudience"])
			if !contains(audience, "developer_admin") || contains(audience, "toda_admin") != (reportedRole == "driver") {
				t.Fatalf("incorrect report review audience: %#v", audience)
			}
			result, err := store.createRideReport(ctx, app.Principal{UID: reporterID}, payload)
			if err != nil || result["idempotent"] != true {
				t.Fatalf("report retry was not idempotent: %#v %v", result, err)
			}
			event := notificationTestEvent(t, store, ctx, reportID, "report.created")
			if text(notificationMap(event["payload"]), "todaId") != todaID {
				t.Fatal("committed report event lost its trusted scope")
			}
			planner := notificationPlanner{
				document: store.notificationDocument,
				administrators: func(_ context.Context, scope string) ([]notificationRecipient, error) {
					if scope != todaID {
						t.Fatalf("notification looked up administrators for wrong scope: %q", scope)
					}
					return []notificationRecipient{
						{ID: "developer", Profile: map[string]any{"role": "developer_admin"}},
						{ID: "toda-admin", Profile: map[string]any{"role": "toda_admin"}},
					}, nil
				},
			}
			plan, err := planner.plan(ctx, notificationEvent{Type: "report.created", AggregateID: reportID}, time.Now())
			count := 2
			if scenario.driverMissing || reportedRole == "passenger" {
				count = 1
			}
			if err != nil || len(plan.Tasks) != count || plan.Tasks[0].RecipientID != "developer" {
				t.Fatalf("report notification audience does not match review access: %#v %v", plan.Tasks, err)
			}
		})
	}
}
