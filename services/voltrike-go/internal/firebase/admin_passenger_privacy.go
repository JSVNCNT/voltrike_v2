package firebase

import (
	"context"
	"crypto/sha256"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

func passengerReference(uid string) string {
	if uid == "" {
		return "Passenger (identity restricted)"
	}
	digest := sha256.Sum256([]byte("voltrike-passenger-reference:" + uid))
	return fmt.Sprintf("Passenger P-%X", digest[:5])
}

// Only a known Bacolod barangay may become a public area label. Never echo
// arbitrary text following "Barangay" from a passenger-supplied address.
var barangayPattern = regexp.MustCompile(`(?i)\bbarangay\s+(?:[1-9]|[1-3][0-9]|4[01]|` +
	`Alangilan|Alijis|Banago|Bata|Cabug|Estefania|Felisa|Granada|Mandalagan|Mansilingan|Montevista|` +
	`Pahanocoy|Punta Taytay|Singcang-Airport|Sum-ag|Taculing|Tangub|Villamonte|Vista Alegre|Handumanan)\b`)

func adminAreaLabel(value string) string {
	if area := barangayPattern.FindString(value); area != "" {
		return strings.TrimSpace(area)
	}
	if value == "" {
		return ""
	}
	return "Location restricted"
}

func restrictedPassengerProfile(uid string, original map[string]any) map[string]any {
	result := map[string]any{"firstName": passengerReference(uid), "role": "passenger"}
	if active, ok := original["isActive"].(bool); ok {
		result["isActive"] = active
	}
	return result
}

// This returns a fresh map: redaction must never mutate a domain snapshot or
// accidentally replace the participants' readable booking/profile data.
func maskAdminPassengerData(original map[string]any) map[string]any {
	data := copyMap(original)
	uid := text(data, "passengerId", "passengerID")
	_, hasPassengerName := data["passengerName"]
	sensitive := uid != "" || hasPassengerName || text(data, "reportId", "reporterId", "incidentId", "messageId") != ""
	if uid != "" || hasPassengerName {
		data["passengerName"] = passengerReference(uid)
		for _, key := range []string{"passengerPhone", "passengerPhoneNumber", "passengerEmail", "passengerPhotoUrl", "passengerProfile", "passenger", "passengerFirstName", "passengerMiddleName", "passengerLastName", "passengerLocation"} {
			delete(data, key)
		}
	}
	for _, party := range []struct{ role, id, profile, legacy string }{
		{"reporterRole", "reporterId", "reporter", "reporterProfile"},
		{"reportedRole", "reportedUserId", "reportedUser", "reportedUserProfile"},
	} {
		profile, _ := data[party.profile].(map[string]any)
		if profile == nil {
			profile, _ = data[party.legacy].(map[string]any)
		}
		role := text(data, party.role)
		if role == "" {
			role = text(profile, "role")
		}
		// Legacy parties without an explicit driver role default to private.
		if text(data, party.id) != "" && role != "driver" {
			data[party.profile] = restrictedPassengerProfile(text(data, party.id), profile)
			delete(data, party.legacy)
			for _, key := range []string{party.profile + "Name", party.profile + "Email", party.profile + "Phone", party.profile + "PhotoUrl"} {
				delete(data, key)
			}
		}
	}
	if text(data, "senderRole") == "passenger" {
		data["senderName"] = passengerReference(text(data, "senderId"))
		for _, key := range []string{"senderEmail", "senderPhone", "senderPhotoUrl", "senderProfile"} {
			delete(data, key)
		}
	}
	if !sensitive {
		return data
	}
	for _, key := range []string{"pickupName", "pickupAddress", "destinationName", "destinationAddress"} {
		if value := text(data, key); value != "" {
			data[key] = adminAreaLabel(value)
		}
	}
	for _, key := range []string{"pickup", "destination", "routeLegs", "routePoints", "routePolyline", "authoritativeRoutePolyline", "encodedPolyline", "location", "passengerCoordinates"} {
		delete(data, key)
	}
	if stops := jsonMapSlice(data["routeStops"]); len(stops) > 0 {
		masked := make([]map[string]any, 0, len(stops))
		for _, stop := range stops {
			masked = append(masked, map[string]any{
				"sequence": stop["sequence"], "type": stop["type"], "final": stop["final"], "status": stop["status"],
				"name": adminAreaLabel(text(stop, "address", "name")), "address": adminAreaLabel(text(stop, "address", "name")),
			})
		}
		data["routeStops"] = masked
	}
	for _, key := range []string{"passengerNote", "comment", "details", "description", "reasonDetail", "cancellationDetail", "appealReason", "manualAppealReason", "originalText", "displayText", "disputeReason", "lastResponseNote", "resolutionNote", "reviewReason"} {
		if text(data, key) != "" {
			data[key] = "Restricted — open case details for authorized review."
		}
	}
	data["passengerIdentityMasked"] = true
	return data
}

func maskAdminResult(result map[string]any) map[string]any {
	masked := maskAdminPassengerData(result)
	for _, key := range []string{"items", "item"} {
		switch value := result[key].(type) {
		case []map[string]any:
			items := make([]map[string]any, 0, len(value))
			for _, item := range value {
				items = append(items, maskAdminPassengerData(item))
			}
			masked[key] = items
		case map[string]any:
			masked[key] = maskAdminPassengerData(value)
		}
	}
	return masked
}

func (store *Store) adminRevealPassengerDetails(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	bookingID, reason := text(payload, "bookingId"), strings.TrimSpace(text(payload, "reason"))
	if bookingID == "" || len(reason) < 10 || len(reason) > 500 {
		return nil, fmt.Errorf("%w: a booking and investigation reason of 10–500 characters are required", app.ErrInvalidArgument)
	}
	booking, err := store.firestore.Collection("bookings").Doc(bookingID).Get(ctx)
	if err != nil || !actor.canAccessToda(text(booking.Data(), "todaId", "driverTodaId")) {
		return nil, fmt.Errorf("%w: booking is outside administrator scope", app.ErrPrecondition)
	}
	data := booking.Data()
	uid := text(data, "passengerId", "passengerID")
	details := map[string]any{
		"bookingId": bookingID, "passengerName": text(data, "passengerName"),
		"phoneNumber":   text(data, "passengerPhone", "passengerPhoneNumber"),
		"pickupAddress": text(data, "pickupAddress"), "destinationAddress": text(data, "destinationAddress"),
		"passengerNote": text(data, "passengerNote"), "cancellationDetail": text(data, "cancellationDetail"),
	}
	if profile, err := store.firestore.Collection("users").Doc(uid).Get(ctx); err == nil {
		details["passengerName"] = passengerDisplayName(profile.Data())
		details["phoneNumber"], details["email"] = text(profile.Data(), "phoneNumber", "phone"), text(profile.Data(), "email")
	}
	for _, source := range []struct{ key, collection string }{{"reportId", "reports"}, {"incidentId", "safetyIncidents"}, {"chatIncidentId", "chatModerationIncidents"}} {
		id := text(payload, source.key)
		if id == "" {
			continue
		}
		record, err := store.firestore.Collection(source.collection).Doc(id).Get(ctx)
		if err != nil || text(record.Data(), "bookingId") != bookingID || !actor.canAccessToda(text(record.Data(), "todaId", "driverTodaId")) {
			return nil, fmt.Errorf("%w: case is outside administrator scope", app.ErrPrecondition)
		}
		if !actor.developer() && (text(record.Data(), "reportedRole") == "passenger" || source.key == "chatIncidentId" && !actorCanAccessChatIncident(actor, record.Data())) {
			return nil, fmt.Errorf("%w: passenger-account cases require System Admin", app.ErrPrecondition)
		}
		for _, key := range []string{"details", "originalText", "displayText", "lastResponseNote", "resolutionNote"} {
			if value := text(record.Data(), key); value != "" {
				details[key] = value
			}
		}
	}
	if ratings, err := store.firestore.Collection("ratings").Where("bookingId", "==", bookingID).Limit(1).Documents(ctx).GetAll(); err == nil && len(ratings) > 0 {
		details["ratingComment"] = text(ratings[0].Data(), "comment")
	}
	if actor.developer() {
		if event, err := store.firestore.Collection("passengerCancellationEvents").Doc(bookingID).Get(ctx); err == nil {
			details["appealReason"], details["reasonDetail"], details["reviewReason"] = event.Data()["appealReason"], event.Data()["reasonDetail"], event.Data()["reviewReason"]
			details["manualAppealReason"] = event.Data()["manualAppealReason"]
		}
	}
	// Fail closed: no identity response is released unless the access log exists.
	_, err = store.firestore.Collection("adminAuditLogs").Doc(uuid.NewString()).Create(ctx, map[string]any{
		"operation": "adminRevealPassengerDetails", "actorUid": actor.UID, "actorRole": actor.Role, "actorTodaId": actor.TodaID,
		"bookingId": bookingID, "passengerId": uid, "reason": reason, "createdAt": time.Now().UTC(),
	})
	if err != nil {
		return nil, fmt.Errorf("record private case access: %w", err)
	}
	return map[string]any{"details": details}, nil
}
