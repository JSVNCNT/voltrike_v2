package firebase

import (
	"context"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/voltrike/voltrike-go/internal/communications"
)

type notificationRecipient struct {
	ID      string
	Profile map[string]any
}

type notificationTask struct {
	RecipientID, Channel, Purpose, IncidentID string
	Title, Body                               string
	Data                                      map[string]string
	Profile                                   map[string]any
	AuthEmailOnly                             bool
	DeliveryID                                string
	Stage, TodaID                             string
	Message                                   communications.Message
	Compose                                   func(string) (communications.Message, error)
}

type notificationPlan struct {
	Tasks   []notificationTask
	Skipped string
}

type notificationPlanner struct {
	document       func(context.Context, string) (map[string]any, error)
	administrators func(context.Context, string) ([]notificationRecipient, error)
	portalURL      string
	logoURL        string
}

var notificationBookingMessages = map[string][2]string{
	"driverAssigned":      {"Driver assigned", "Your driver accepted the booking."},
	"driverArriving":      {"Driver arrived", "Your driver has arrived at pickup."},
	"passengerOnBoard":    {"Trip started", "You are on the way to your destination."},
	"paymentConfirmation": {"Payment confirmation", "Waiting for the driver to confirm cash received."},
	"completed":           {"Trip completed", "Your receipt is ready."},
	"cancelled":           {"Booking cancelled", "Your booking was cancelled."},
}

func (planner notificationPlanner) plan(ctx context.Context, event notificationEvent, now time.Time) (notificationPlan, error) {
	if maximum := notificationMaximumAge(event.Type); maximum > 0 && !event.CreatedAt.IsZero() && now.Sub(event.CreatedAt) > maximum {
		return notificationPlan{Skipped: "stale-notification-event"}, nil
	}
	if event.Type == "booking.offer.created" {
		return planner.bookingOffer(ctx, event, now)
	}
	if strings.HasPrefix(event.Type, "booking.") {
		return planner.booking(ctx, event)
	}
	if strings.HasPrefix(event.Type, "toda.registration.") {
		return planner.todaRegistration(ctx, event)
	}
	if event.Type == "call.ringing" {
		uid := text(event.Payload, "recipientId")
		if !notificationIDValid(uid) {
			return notificationPlan{Skipped: "missing-recipient"}, nil
		}
		return notificationPlan{Tasks: []notificationTask{notificationPush(uid, "Incoming VolTrike call", "Your ride participant is calling.", map[string]string{
			"bookingId": text(event.Payload, "bookingId"), "callId": text(event.Payload, "callId"),
			"callerId": text(event.Payload, "callerId"), "recipientId": uid, "type": "incoming_call",
		})}}, nil
	}
	if event.Type == "chat.message.created" {
		bookingID, messageID := text(event.Payload, "bookingId"), text(event.Payload, "messageId")
		booking, err := planner.document(ctx, "bookings/"+bookingID)
		if err != nil {
			return notificationPlan{}, err
		}
		message, err := planner.document(ctx, "chat/"+bookingID+"/messages/"+messageID)
		if err != nil {
			return notificationPlan{}, err
		}
		if booking == nil || message == nil {
			return notificationPlan{Skipped: "projection-not-found"}, nil
		}
		sender, recipient := text(event.Payload, "senderId"), text(booking, "passengerId", "passengerID")
		if sender == recipient {
			recipient = text(booking, "driverId", "driverID")
		}
		if !notificationIDValid(recipient) {
			return notificationPlan{Skipped: "missing-recipient"}, nil
		}
		body := []rune(text(message, "text"))
		body = body[:min(120, len(body))]
		return notificationPlan{Tasks: []notificationTask{notificationPush(recipient, "New ride message", string(body), map[string]string{
			"bookingId": bookingID, "senderId": sender, "recipientId": recipient, "type": "chat_message",
		})}}, nil
	}
	if strings.HasPrefix(event.Type, "safety.") {
		return planner.safety(ctx, event)
	}
	if event.Type == "report.created" {
		report, err := planner.document(ctx, "reports/"+event.AggregateID)
		if err != nil {
			return notificationPlan{}, err
		}
		if report == nil {
			report = event.Payload
		}
		todaID, audience := text(report, "todaId"), stringSlice(report["reviewAudience"])
		developerOnly := todaID == "" || text(report, "reportedRole") == "passenger" || len(audience) > 0 && !contains(audience, "toda_admin")
		admins, err := planner.administrators(ctx, todaID)
		if err != nil {
			return notificationPlan{}, err
		}
		tasks := []notificationTask{}
		for _, admin := range admins {
			// Reports without a trusted TODA scope and passenger-account reports
			// belong to System Admin, matching the report review access policy.
			if developerOnly && text(admin.Profile, "role") != "developer_admin" {
				continue
			}
			tasks = append(tasks, notificationPush(admin.ID, "New ride report", "A ride report requires administrator review.", map[string]string{
				"type": "ride_report", "reportId": event.AggregateID, "bookingId": text(report, "bookingId"),
			}))
		}
		return notificationPlan{Tasks: tasks}, nil
	}
	if event.Type == "driver.registration.submitted" {
		id := text(event.Payload, "driverId")
		if id == "" {
			id = event.AggregateID
		}
		if !notificationIDValid(id) {
			return notificationPlan{Skipped: "missing-driver"}, nil
		}
		return planner.adminPush(ctx, text(event.Payload, "todaId"), "New driver application", "A driver application is ready for TODA review.", map[string]string{
			"type": "driver_registration", "driverId": id,
		})
	}
	if strings.HasPrefix(event.Type, "violation.") {
		return planner.violation(ctx, event)
	}
	return notificationPlan{Skipped: "non-notifiable-event"}, nil
}

func (planner notificationPlanner) booking(ctx context.Context, event notificationEvent) (notificationPlan, error) {
	if !notificationIDValid(event.AggregateID) {
		return notificationPlan{Skipped: "missing-aggregate"}, nil
	}
	booking, err := planner.document(ctx, "bookings/"+event.AggregateID)
	if err != nil {
		return notificationPlan{}, err
	}
	if booking == nil {
		return notificationPlan{Skipped: "booking-not-found"}, nil
	}
	status := notificationBookingStatus(event)
	passenger, driver := notificationBookingCopy(status, text(booking, "cancellationCode"))
	if passenger[0] == "" {
		return notificationPlan{Skipped: "event-transition-not-notifiable"}, nil
	}
	tasks := []notificationTask{}
	if id := text(booking, "passengerId", "passengerID"); notificationIDValid(id) {
		tasks = append(tasks, notificationPush(id, passenger[0], passenger[1], map[string]string{"bookingId": event.AggregateID, "target": "passenger", "type": status}))
	}
	if id := text(booking, "driverId", "driverID"); notificationIDValid(id) && driver[0] != "" {
		tasks = append(tasks, notificationPush(id, driver[0], driver[1], map[string]string{"bookingId": event.AggregateID, "target": "driver", "type": status}))
	}
	return notificationPlan{Tasks: tasks}, nil
}

func (planner notificationPlanner) bookingOffer(ctx context.Context, event notificationEvent, now time.Time) (notificationPlan, error) {
	bookingID, driverID := text(event.Payload, "bookingId"), text(event.Payload, "driverId")
	if bookingID == "" {
		bookingID = event.AggregateID
	}
	if !notificationIDValid(bookingID) || !notificationIDValid(driverID) {
		return notificationPlan{Skipped: "missing-offer-identity"}, nil
	}
	booking, err := planner.document(ctx, "bookings/"+bookingID)
	if err != nil {
		return notificationPlan{}, err
	}
	offer, err := planner.document(ctx, "drivers/"+driverID+"/bookingOffers/"+bookingID)
	if err != nil {
		return notificationPlan{}, err
	}
	if booking == nil || offer == nil || text(booking, "status") != "pending" || text(offer, "status") != "offered" ||
		!notificationTime(offer["expiresAt"]).After(now) || integer(offer, "offerRound") != integer(booking, "offerRound") ||
		(integer(event.Payload, "offerRound") > 0 && integer(event.Payload, "offerRound") != integer(offer, "offerRound")) {
		return notificationPlan{Skipped: "offer-no-longer-actionable"}, nil
	}
	distance := int(math.Round(number(offer, "distanceMeters")))
	proximity := fmt.Sprintf("%d m", distance)
	if distance >= 1000 {
		proximity = fmt.Sprintf("%.1f km", float64(distance)/1000)
	}
	return notificationPlan{Tasks: []notificationTask{notificationPush(driverID, "New VolTrike booking", "A passenger "+proximity+" away is requesting a ride.", map[string]string{
		"bookingId": bookingID, "target": "driver", "type": "booking_offer",
	})}}, nil
}

func (planner notificationPlanner) safety(ctx context.Context, event notificationEvent) (notificationPlan, error) {
	incident, err := planner.document(ctx, "safetyIncidents/"+event.AggregateID)
	if err != nil {
		return notificationPlan{}, err
	}
	if incident == nil {
		incident = event.Payload
	}
	if !notificationSafetyActionable(event.Type, incident) {
		return notificationPlan{Skipped: "safety-incident-not-actionable"}, nil
	}
	title := "VolTrike safety alert"
	if event.Type == "safety.escalated" {
		title = "Unacknowledged VolTrike SOS"
	}
	bookingID := text(incident, "bookingId")
	if bookingID == "" {
		bookingID = "unknown"
	}
	admins, err := planner.administrators(ctx, text(incident, "todaId"))
	if err != nil {
		return notificationPlan{}, err
	}
	tasks := []notificationTask{}
	for _, recipient := range admins {
		tasks = append(tasks, notificationPush(recipient.ID, title, "Safety incident for booking "+bookingID+" requires review.", map[string]string{
			"type": "safety_incident", "incidentId": event.AggregateID, "bookingId": bookingID, "escalationLevel": fmt.Sprint(integer(incident, "escalationLevel")),
		}))
		if !booleanDefault(recipient.Profile, true, "safetyEmailEnabled") {
			continue
		}
		tasks = append(tasks, notificationTask{
			RecipientID: recipient.ID, Channel: "email", Purpose: "administrator_safety_alert", IncidentID: event.AggregateID, Profile: recipient.Profile,
			Compose: func(name string) (communications.Message, error) {
				return communications.SafetyAlertEmail(communications.SafetyAlert{RecipientName: name, EventLabel: title, AdminPortalURL: planner.portalURL, LogoURL: planner.logoURL, Incident: incident}), nil
			},
		})
	}
	return notificationPlan{Tasks: tasks}, nil
}

func (planner notificationPlanner) todaRegistration(ctx context.Context, event notificationEvent) (notificationPlan, error) {
	stage := strings.TrimPrefix(event.Type, "toda.registration.")
	if stage != "submitted" && stage != "approved" && stage != "declined" {
		return notificationPlan{Skipped: "unknown-toda-registration-stage"}, nil
	}
	id := text(event.Payload, "todaId")
	if id == "" {
		id = event.AggregateID
	}
	application, err := planner.document(ctx, "todaApplications/"+id)
	if err != nil {
		return notificationPlan{}, err
	}
	uid := text(event.Payload, "adminUid")
	if uid == "" {
		uid = text(application, "adminUid")
	}
	if !notificationIDValid(uid) {
		return notificationPlan{Skipped: "missing-toda-administrator"}, nil
	}
	toda, err := planner.document(ctx, "todas/"+id)
	if err != nil {
		return notificationPlan{}, err
	}
	name := text(event.Payload, "todaName")
	if name == "" {
		name = text(toda, "name")
	}
	if name == "" {
		name = id
	}
	// Retain the deployed registration delivery key so already accepted status
	// emails cannot be resent during the Node-to-Go cutover.
	key := fmt.Sprintf("%x", notificationSHA256("toda-registration:"+id+":"+uid+":"+stage))
	return notificationPlan{Tasks: []notificationTask{{
		RecipientID: uid, Channel: "email", Purpose: "toda_registration_status", AuthEmailOnly: true, DeliveryID: key, TodaID: id, Stage: stage,
		Compose: func(administratorName string) (communications.Message, error) {
			return communications.TodaApplicationEmail(communications.TodaApplication{AdministratorName: administratorName, TodaName: name, Status: stage, AdminPortalURL: planner.portalURL, LogoURL: planner.logoURL})
		},
	}}}, nil
}

func (planner notificationPlanner) violation(ctx context.Context, event notificationEvent) (notificationPlan, error) {
	id := text(event.Payload, "violationId")
	if id == "" {
		id = event.AggregateID
	}
	violation, err := planner.document(ctx, "driverViolations/"+id)
	if err != nil {
		return notificationPlan{}, err
	}
	if violation == nil {
		violation = event.Payload
	}
	todaID := text(violation, "ownerTodaId", "todaId")
	if event.Type == "violation.message.created" {
		messageID := text(event.Payload, "messageId")
		message, err := planner.document(ctx, "driverViolations/"+id+"/messages/"+messageID)
		if err != nil {
			return notificationPlan{}, err
		}
		if message == nil {
			return notificationPlan{Skipped: "case-message-not-found"}, nil
		}
		admins, err := planner.administrators(ctx, todaID)
		if err != nil {
			return notificationPlan{}, err
		}
		recipients := map[string]bool{}
		for _, admin := range admins {
			recipients[admin.ID] = true
		}
		if driver := text(violation, "driverId"); notificationIDValid(driver) {
			recipients[driver] = true
		}
		delete(recipients, text(message, "senderId"))
		tasks := []notificationTask{}
		for recipient := range recipients {
			tasks = append(tasks, notificationPush(recipient, "New restricted-area case message", "Open VolTrike to read the new case message.", map[string]string{
				"type": "driver_violation_message", "violationId": id, "messageId": messageID,
			}))
		}
		return notificationPlan{Tasks: tasks}, nil
	}
	if event.Type == "violation.updated" {
		uid := text(violation, "driverId")
		if !notificationIDValid(uid) {
			return notificationPlan{Skipped: "missing-driver"}, nil
		}
		status := text(event.Payload, "status")
		if status == "" {
			status = text(violation, "status")
		}
		title := "Restricted-area case updated"
		switch status {
		case "resolved":
			title = "Restricted-area case resolved"
		case "dismissed":
			title = "Restricted-area case dismissed"
		}
		body := text(event.Payload, "note")
		if body == "" {
			body = "An administrator updated your restricted-area case."
		}
		return notificationPlan{Tasks: []notificationTask{notificationPush(uid, title, body, map[string]string{"type": "driver_violation", "violationId": id})}}, nil
	}
	plan, err := planner.adminPush(ctx, todaID, "Route restriction case", "A driver restriction case has new activity.", map[string]string{"type": "driver_violation", "violationId": id})
	if err != nil {
		return notificationPlan{}, err
	}
	if uid := text(violation, "driverId"); event.Type == "violation.created" && notificationIDValid(uid) {
		plan.Tasks = append(plan.Tasks, notificationPush(uid, "Restricted e-trike area entered", "Leave the restricted area using the nearest permitted street.", map[string]string{"type": "driver_violation", "violationId": id}))
		plan.Tasks = append(plan.Tasks, notificationTask{RecipientID: uid, Channel: "email", Purpose: "driver_route_safety_case", AuthEmailOnly: true,
			Message: communications.PlainEmail("VolTrike route safety case", "A route restriction case was recorded. Open the driver app for details."),
		})
	}
	return plan, nil
}

func (planner notificationPlanner) adminPush(ctx context.Context, todaID, title, body string, data map[string]string) (notificationPlan, error) {
	admins, err := planner.administrators(ctx, todaID)
	if err != nil {
		return notificationPlan{}, err
	}
	tasks := make([]notificationTask, 0, len(admins))
	for _, recipient := range admins {
		tasks = append(tasks, notificationPush(recipient.ID, title, body, data))
	}
	return notificationPlan{Tasks: tasks}, nil
}

func notificationPush(uid, title, body string, data map[string]string) notificationTask {
	return notificationTask{RecipientID: uid, Channel: "push", Purpose: data["type"], Title: title, Body: body, Data: data}
}

func notificationMaximumAge(eventType string) time.Duration {
	switch {
	case eventType == "call.ringing":
		return 2 * time.Minute
	case strings.HasPrefix(eventType, "booking."), eventType == "chat.message.created", eventType == "safety.sos.safe", eventType == "safety.sos.emergency_call_attempted":
		return 15 * time.Minute
	case eventType == "driver.registration.submitted", eventType == "report.created", strings.HasPrefix(eventType, "violation."):
		return time.Hour
	default:
		return 0
	}
}

func notificationBookingStatus(event notificationEvent) string {
	if status := text(event.Payload, "status"); notificationBookingMessages[status][0] != "" {
		return status
	}
	status := strings.TrimPrefix(event.Type, "booking.")
	if notificationBookingMessages[status][0] != "" {
		return status
	}
	return ""
}

func notificationBookingCopy(status, cancellationCode string) ([2]string, [2]string) {
	passenger := notificationBookingMessages[status]
	driver := passenger
	if copy := (map[string][2]string{
		"passengerOnBoard": {"Trip started", "Navigate to the destination."}, "paymentConfirmation": {"Confirm cash received", "Confirm cash to complete the trip."}, "completed": {"Trip completed", "Your earnings receipt is ready."},
	}[status]); copy[0] != "" {
		driver = copy
	}
	if status == "cancelled" {
		switch {
		case cancellationCode == "passenger_no_show":
			passenger, driver = [2]string{"Passenger no-show", "This booking was closed as a passenger no-show."}, [2]string{"Passenger no-show", "The no-show booking was closed."}
		case strings.Contains(cancellationCode, "passenger"):
			passenger, driver = [2]string{"Cancelled by passenger", "You cancelled this booking."}, [2]string{"Cancelled by passenger", "The passenger cancelled the trip."}
		default:
			passenger, driver = [2]string{"Cancelled by driver", "Your driver cancelled this booking."}, [2]string{"Cancelled by driver", "You cancelled the trip."}
		}
	}
	return passenger, driver
}

func notificationSafetyActionable(eventType string, incident map[string]any) bool {
	if eventType == "safety.sos.safe" {
		return text(incident, "responseStatus") == "resolved"
	}
	return text(incident, "status") == "open" && (text(incident, "responseStatus") == "" || text(incident, "responseStatus") == "reported")
}
