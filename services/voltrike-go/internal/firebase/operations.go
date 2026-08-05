package firebase

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
)

func (store *Store) ExecuteOperation(ctx context.Context, principal app.Principal, command app.OperationCommand) (map[string]any, error) {
	switch command.Name {
	case "createRideReport":
		return store.createRideReport(ctx, principal, command.Payload)
	case "submitDriverRating":
		return store.submitDriverRating(ctx, principal, command.Payload)
	case "createSafetyIncident":
		return store.createSafetyIncident(ctx, principal, command.Payload)
	case "getMySafetyIncident":
		return store.getMySafetyIncident(ctx, principal, command.Payload)
	case "updateMySafetyIncident":
		return store.updateMySafetyIncident(ctx, principal, command.Payload)
	case "getShareTripInformation":
		return store.getShareTripInformation(ctx, principal, command.Payload)
	case "getDriverEarningsSummary":
		return store.getDriverEarningsSummary(ctx, principal)
	case "startBookingCall":
		return store.startBookingCall(ctx, principal, command.Payload)
	case "respondBookingCall":
		return store.respondBookingCall(ctx, principal, command.Payload)
	case "createBookingCallToken":
		return store.createBookingCallToken(ctx, principal, command.Payload)
	case "endBookingCall":
		return store.endBookingCall(ctx, principal, command.Payload)
	case "sendRideChatMessage":
		return store.sendRideChatMessage(ctx, principal, command)
	case "markRideChatSeen":
		return store.markRideChatSeen(ctx, principal, command.Payload)
	case "setRideChatTyping":
		return store.setRideChatTyping(ctx, principal, command.Payload)
	case "driverReportRestrictionPosition":
		return store.reportRestrictionPosition(ctx, principal, command.Payload)
	case "listMyDriverViolations":
		return store.listMyDriverViolations(ctx, principal, command.Payload)
	case "sendDriverViolationMessage":
		return store.sendDriverViolationMessage(ctx, principal, command)
	case "markDriverViolationMessagesRead":
		return store.markDriverViolationMessagesRead(ctx, principal, command.Payload)
	default:
		return nil, fmt.Errorf("%w: unsupported operation %q", app.ErrInvalidArgument, command.Name)
	}
}

func (store *Store) participantBooking(ctx context.Context, principal app.Principal, bookingID string) (map[string]any, error) {
	if strings.TrimSpace(bookingID) == "" {
		return nil, fmt.Errorf("%w: bookingId is required", app.ErrInvalidArgument)
	}
	snapshot, err := store.firestore.Collection("bookings").Doc(bookingID).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: booking not found", app.ErrPrecondition)
	}
	data := snapshot.Data()
	if text(data, "passengerId", "passengerID") != principal.UID && text(data, "driverId", "driverID") != principal.UID && !adminPrincipal(principal) {
		return nil, fmt.Errorf("%w: user is not a booking participant", app.ErrPrecondition)
	}
	return data, nil
}

func (store *Store) createRideReport(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	reportID, bookingID := text(payload, "reportId"), text(payload, "bookingId")
	category, details := text(payload, "category"), text(payload, "details")
	if reportID == "" || category == "" || len(details) < 5 {
		return nil, fmt.Errorf("%w: reportId, category, and report details are required", app.ErrInvalidArgument)
	}
	booking, err := store.participantBooking(ctx, principal, bookingID)
	if err != nil {
		return nil, err
	}
	passengerID, driverID := text(booking, "passengerId", "passengerID"), text(booking, "driverId", "driverID")
	reportedID, reporterRole, reportedRole := passengerID, "driver", "passenger"
	if principal.UID == passengerID {
		reportedID, reporterRole, reportedRole = driverID, "passenger", "driver"
	}
	if reportedID == "" {
		return nil, fmt.Errorf("%w: booking has no other participant", app.ErrPrecondition)
	}
	ref := store.firestore.Collection("reports").Doc(reportID)
	created := false
	err = store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		existing, readErr := tx.Get(ref)
		if readErr == nil {
			data := existing.Data()
			if text(data, "reporterId") == principal.UID && text(data, "bookingId") == bookingID {
				return nil
			}
			return fmt.Errorf("%w: reportId is already in use", app.ErrPrecondition)
		}
		if !isNotFound(readErr) {
			return readErr
		}
		now := time.Now().UTC()
		tx.Create(ref, map[string]any{
			"reportId": reportID, "bookingId": bookingID, "reporterId": principal.UID,
			"reportedUserId": reportedID, "todaId": text(booking, "todaId", "driverTodaId"),
			"reporterRole": reporterRole, "reportedRole": reportedRole, "category": category,
			"details": truncate(details, 2000), "status": "open", "createdAt": now, "updatedAt": now,
		})
		writeOutbox(tx, store, "report.created", reportID, map[string]any{"reportId": reportID, "bookingId": bookingID})
		created = true
		return nil
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"reportId": reportID, "idempotent": !created}, nil
}

func (store *Store) submitDriverRating(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, rating := text(payload, "bookingId"), integer(payload, "rating")
	if bookingID == "" || rating < 1 || rating > 5 {
		return nil, fmt.Errorf("%w: bookingId and a rating from 1 to 5 are required", app.ErrInvalidArgument)
	}
	ratingID := bookingID + "_" + principal.UID
	result := map[string]any{"ratingId": ratingID, "idempotent": false}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		bookingRef := store.firestore.Collection("bookings").Doc(bookingID)
		ratingRef := store.firestore.Collection("ratings").Doc(ratingID)
		bookingSnapshot, bookingErr := tx.Get(bookingRef)
		if bookingErr != nil {
			return fmt.Errorf("%w: booking not found", app.ErrPrecondition)
		}
		existing, existingErr := tx.Get(ratingRef)
		if existingErr == nil {
			if text(existing.Data(), "passengerId") == principal.UID {
				result["idempotent"] = true
				return nil
			}
			return fmt.Errorf("%w: rating already exists", app.ErrPrecondition)
		}
		if !isNotFound(existingErr) {
			return existingErr
		}
		booking := bookingSnapshot.Data()
		driverID := text(booking, "driverId", "driverID")
		if text(booking, "passengerId", "passengerID") != principal.UID || text(booking, "status") != "completed" || driverID == "" {
			return fmt.Errorf("%w: only the passenger of a completed booking may rate", app.ErrPrecondition)
		}
		driverRef := store.firestore.Collection("drivers").Doc(driverID)
		driverSnapshot, driverErr := tx.Get(driverRef)
		if driverErr != nil {
			return fmt.Errorf("%w: driver profile not found", app.ErrPrecondition)
		}
		driver := driverSnapshot.Data()
		count, average := integer(driver, "ratingCount"), number(driver, "rating")
		nextCount := count + 1
		nextAverage := mathRound((average*float64(count)+float64(rating))/float64(nextCount), 2)
		now := time.Now().UTC()
		tx.Create(ratingRef, map[string]any{
			"ratingId": ratingID, "bookingId": bookingID, "driverId": driverID,
			"passengerId": principal.UID, "todaId": text(booking, "todaId", "driverTodaId"),
			"driverName": text(booking, "driverName"), "passengerName": text(booking, "passengerName"),
			"rating": rating, "comment": truncate(text(payload, "comment"), 1000), "createdAt": now,
		})
		tx.Set(driverRef, map[string]any{"rating": nextAverage, "ratingCount": nextCount, "updatedAt": now}, firestore.MergeAll)
		writeOutbox(tx, store, "rating.created", ratingID, map[string]any{"ratingId": ratingID, "driverId": driverID})
		result["rating"], result["ratingCount"] = nextAverage, nextCount
		return nil
	})
	return result, err
}

func (store *Store) createSafetyIncident(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	booking, err := store.participantBooking(ctx, principal, bookingID)
	if err != nil {
		return nil, err
	}
	status := text(booking, "status")
	if !contains([]string{"driverAssigned", "driverArriving", "passengerOnBoard", "paymentConfirmation"}, status) {
		return nil, fmt.Errorf("%w: SOS is unavailable in the current booking state", app.ErrPrecondition)
	}
	acknowledgement := "needs_review"
	if text(payload, "acknowledgement") == "accidental" {
		acknowledgement = "accidental"
	}
	incidentID := fmt.Sprintf("sos_%x", sha256.Sum256([]byte(bookingID+":"+principal.UID)))[:44]
	ref := store.firestore.Collection("safetyIncidents").Doc(incidentID)
	idempotent := false
	err = store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		existing, readErr := tx.Get(ref)
		if readErr == nil {
			if text(existing.Data(), "reportedBy") != principal.UID {
				return fmt.Errorf("%w: safety incident identity conflict", app.ErrPrecondition)
			}
			idempotent = true
			return nil
		}
		if !isNotFound(readErr) {
			return readErr
		}
		now := time.Now().UTC()
		responseStatus, incidentStatus, deliveryStatus := "reported", "open", "pending"
		if acknowledgement == "accidental" {
			responseStatus, incidentStatus, deliveryStatus = "resolved", "accidental", "not_required"
		}
		tx.Create(ref, map[string]any{
			"schemaVersion": 3, "incidentId": incidentID, "bookingId": bookingID, "category": "sos",
			"reportedBy": principal.UID, "reporterRole": participantRole(booking, principal.UID),
			"passengerId": text(booking, "passengerId", "passengerID"), "driverId": text(booking, "driverId", "driverID"),
			"todaId": text(booking, "todaId", "driverTodaId"), "bookingStatus": status,
			"pickup": booking["pickup"], "pickupAddress": booking["pickupAddress"],
			"destination": booking["destination"], "destinationAddress": booking["destinationAddress"],
			"acknowledgement": acknowledgement, "status": incidentStatus, "responseStatus": responseStatus,
			"deliveryStatus": deliveryStatus, "escalationLevel": 0, "createdAt": now, "updatedAt": now,
		})
		if acknowledgement == "needs_review" {
			writeOutbox(tx, store, "safety.sos.created", incidentID, map[string]any{"incidentId": incidentID, "bookingId": bookingID})
		}
		return nil
	})
	return map[string]any{"incidentId": incidentID, "idempotent": idempotent, "acknowledgement": acknowledgement, "deliveryStatus": map[bool]string{true: "not_required", false: "pending"}[acknowledgement == "accidental"], "emergencyDispatch": "manual_911_call_available"}, err
}

func (store *Store) getMySafetyIncident(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	if _, err := store.participantBooking(ctx, principal, bookingID); err != nil {
		return nil, err
	}
	incidentID := fmt.Sprintf("sos_%x", sha256.Sum256([]byte(bookingID+":"+principal.UID)))[:44]
	snapshot, err := store.firestore.Collection("safetyIncidents").Doc(incidentID).Get(ctx)
	if isNotFound(err) {
		return map[string]any{"incident": nil}, nil
	}
	if err != nil {
		return nil, err
	}
	data := snapshot.Data()
	return map[string]any{"incident": map[string]any{"incidentId": incidentID, "status": text(data, "status"), "responseStatus": text(data, "responseStatus"), "deliveryStatus": text(data, "deliveryStatus"), "escalationLevel": integer(data, "escalationLevel"), "updatedAt": data["updatedAt"]}}, nil
}

func (store *Store) updateMySafetyIncident(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, action := text(payload, "bookingId"), text(payload, "action")
	if !contains([]string{"safe", "still_need_help", "emergency_call_attempted"}, action) {
		return nil, fmt.Errorf("%w: unsupported safety action", app.ErrInvalidArgument)
	}
	incidentID := fmt.Sprintf("sos_%x", sha256.Sum256([]byte(bookingID+":"+principal.UID)))[:44]
	ref, now := store.firestore.Collection("safetyIncidents").Doc(incidentID), time.Now().UTC()
	updates := map[string]any{"updatedAt": now}
	if action == "safe" {
		updates["status"], updates["responseStatus"], updates["reporterMarkedSafeAt"], updates["resolvedAt"] = "reporter_safe", "resolved", now, now
	} else if action == "still_need_help" {
		updates["status"], updates["responseStatus"], updates["acknowledgement"], updates["escalationLevel"] = "open", "reported", "needs_review", 2
	} else {
		updates["emergencyCallAttemptedAt"], updates["emergencyCallAttemptedBy"] = now, principal.UID
	}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, readErr := tx.Get(ref)
		if readErr != nil || text(snapshot.Data(), "reportedBy") != principal.UID {
			return fmt.Errorf("%w: safety incident not found", app.ErrPrecondition)
		}
		tx.Set(ref, updates, firestore.MergeAll)
		writeOutbox(tx, store, "safety.sos."+action, incidentID, map[string]any{"incidentId": incidentID, "bookingId": bookingID})
		return nil
	})
	return map[string]any{"incidentId": incidentID, "status": updates["status"], "responseStatus": updates["responseStatus"]}, err
}

func (store *Store) getShareTripInformation(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	data, err := store.participantBooking(ctx, principal, bookingID)
	if err != nil {
		return nil, err
	}
	return map[string]any{
		"bookingReference": bookingID, "status": text(data, "status"), "passengerName": valueOr(data, "passengerName", "Passenger"),
		"driverName": data["driverName"], "vehicleNumber": data["vehicleNumber"], "plateNumber": data["plateNumber"],
		"todaName": data["todaName"], "pickupAddress": data["pickupAddress"], "destinationAddress": data["destinationAddress"], "updatedAt": data["updatedAt"],
	}, nil
}

func (store *Store) getDriverEarningsSummary(ctx context.Context, principal app.Principal) (map[string]any, error) {
	documents, err := store.firestore.Collection("bookings").Where("driverId", "==", principal.UID).Where("status", "==", "completed").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	now := time.Now()
	day := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	week := day.AddDate(0, 0, 1-int(day.Weekday()+6)%7)
	month := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, now.Location())
	var todayTotal, weekTotal, monthTotal, total float64
	for _, document := range documents {
		data, amount := document.Data(), number(document.Data(), "driverNetEarnings")
		total += amount
		completed, ok := data["completedAt"].(time.Time)
		if !ok {
			continue
		}
		if !completed.Before(day) {
			todayTotal += amount
		}
		if !completed.Before(week) {
			weekTotal += amount
		}
		if !completed.Before(month) {
			monthTotal += amount
		}
	}
	average := 0.0
	if len(documents) > 0 {
		average = total / float64(len(documents))
	}
	return map[string]any{"today": todayTotal, "week": weekTotal, "month": monthTotal, "total": total, "completedTrips": len(documents), "averageNetEarnings": average}, nil
}

func (store *Store) startBookingCall(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	if store.cfg.LiveKitServerURL == "" {
		return nil, fmt.Errorf("%w: voice calling is not configured", app.ErrUnavailable)
	}
	callRef := store.firestore.Collection("bookingCalls").Doc(bookingID)
	result := map[string]any{}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		bookingSnapshot, bookingErr := tx.Get(store.firestore.Collection("bookings").Doc(bookingID))
		if bookingErr != nil {
			return fmt.Errorf("%w: booking not found", app.ErrPrecondition)
		}
		booking := bookingSnapshot.Data()
		if text(booking, "passengerId", "passengerID") != principal.UID && text(booking, "driverId", "driverID") != principal.UID {
			return fmt.Errorf("%w: user is not a call participant", app.ErrPrecondition)
		}
		if !contains([]string{"driverAssigned", "driverArriving", "passengerOnBoard", "paymentConfirmation"}, text(booking, "status")) {
			return fmt.Errorf("%w: calls are unavailable at this ride stage", app.ErrPrecondition)
		}
		recipientID := text(booking, "passengerId", "passengerID")
		if recipientID == principal.UID {
			recipientID = text(booking, "driverId", "driverID")
		}
		if recipientID == "" {
			return fmt.Errorf("%w: other call participant is unavailable", app.ErrPrecondition)
		}
		existing, existingErr := tx.Get(callRef)
		if existingErr == nil {
			data := existing.Data()
			status := effectiveCallStatus(data, time.Now().UTC())
			if status == "ringing" && text(data, "callerId") == principal.UID && text(data, "recipientId") == recipientID {
				result = callResult(data)
				result["idempotent"] = true
				return nil
			}
			if status == "ringing" || status == "accepted" {
				return fmt.Errorf("%w: a ride call is already active", app.ErrPrecondition)
			}
		} else if !isNotFound(existingErr) {
			return existingErr
		}
		now, callID := time.Now().UTC(), "call_"+strings.ReplaceAll(uuid.NewString(), "-", "")
		data := map[string]any{
			"schemaVersion": 3, "bookingId": bookingID, "callId": callID, "roomName": "voltrike_" + callID,
			"serverUrl": store.cfg.LiveKitServerURL, "callerId": principal.UID, "recipientId": recipientID,
			"status": "ringing", "createdAt": now, "updatedAt": now, "expiresAt": now.Add(30 * time.Second),
		}
		tx.Set(callRef, data)
		writeOutbox(tx, store, "call.ringing", callID, map[string]any{"bookingId": bookingID, "callId": callID, "recipientId": recipientID})
		result = callResult(data)
		result["idempotent"] = false
		return nil
	})
	return result, err
}

func (store *Store) respondBookingCall(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, callID, response := text(payload, "bookingId"), text(payload, "callId"), text(payload, "response")
	if !contains([]string{"accepted", "declined", "expired"}, response) {
		return nil, fmt.Errorf("%w: unsupported call response", app.ErrInvalidArgument)
	}
	result := map[string]any{}
	callRef := store.firestore.Collection("bookingCalls").Doc(bookingID)
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		bookingSnapshot, bookingErr := tx.Get(store.firestore.Collection("bookings").Doc(bookingID))
		callSnapshot, callErr := tx.Get(callRef)
		if bookingErr != nil || callErr != nil {
			return fmt.Errorf("%w: call invitation is unavailable", app.ErrPrecondition)
		}
		booking, call := bookingSnapshot.Data(), callSnapshot.Data()
		if text(booking, "passengerId", "passengerID") != principal.UID && text(booking, "driverId", "driverID") != principal.UID {
			return fmt.Errorf("%w: user is not a call participant", app.ErrPrecondition)
		}
		if text(call, "callId") != callID {
			return fmt.Errorf("%w: call invitation is no longer current", app.ErrPrecondition)
		}
		now, current := time.Now().UTC(), effectiveCallStatus(call, time.Now().UTC())
		if contains([]string{"declined", "expired", "ended"}, current) {
			result = callResult(call)
			result["status"], result["idempotent"] = current, true
			return nil
		}
		if current == "accepted" {
			if response != "accepted" || text(call, "acceptedBy") != principal.UID {
				return fmt.Errorf("%w: call is already accepted", app.ErrPrecondition)
			}
			result = callResult(call)
			result["idempotent"] = true
			return nil
		}
		if response != "expired" && text(call, "recipientId") != principal.UID {
			return fmt.Errorf("%w: only the called participant can respond", app.ErrPrecondition)
		}
		if response == "expired" && futureTime(call["expiresAt"], now) {
			return fmt.Errorf("%w: call invitation has not expired", app.ErrPrecondition)
		}
		updates := map[string]any{"status": response, "updatedAt": now}
		if response == "accepted" {
			updates["acceptedBy"], updates["acceptedAt"], updates["endsAt"] = principal.UID, now, now.Add(30*time.Minute)
		} else {
			updates["respondedBy"], updates["respondedAt"] = principal.UID, now
		}
		tx.Set(callRef, updates, firestore.MergeAll)
		for key, value := range updates {
			call[key] = value
		}
		writeOutbox(tx, store, "call."+response, callID, map[string]any{"bookingId": bookingID, "callId": callID})
		result = callResult(call)
		result["idempotent"] = false
		return nil
	})
	if err == nil && response == "accepted" && text(result, "acceptedBy") == principal.UID {
		credentials, credentialErr := store.liveKitCredentials(result, principal.UID)
		if credentialErr != nil {
			return nil, credentialErr
		}
		for key, value := range credentials {
			result[key] = value
		}
	}
	return result, err
}

func (store *Store) createBookingCallToken(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, callID := text(payload, "bookingId"), text(payload, "callId")
	if _, err := store.participantBooking(ctx, principal, bookingID); err != nil {
		return nil, err
	}
	snapshot, err := store.firestore.Collection("bookingCalls").Doc(bookingID).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: active call unavailable", app.ErrPrecondition)
	}
	call := snapshot.Data()
	if text(call, "callId") != callID || effectiveCallStatus(call, time.Now().UTC()) != "accepted" {
		return nil, fmt.Errorf("%w: call must be accepted before joining", app.ErrPrecondition)
	}
	return store.liveKitCredentials(callResult(call), principal.UID)
}

func (store *Store) endBookingCall(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, callID := text(payload, "bookingId"), text(payload, "callId")
	if _, err := store.participantBooking(ctx, principal, bookingID); err != nil {
		return nil, err
	}
	ref, now := store.firestore.Collection("bookingCalls").Doc(bookingID), time.Now().UTC()
	result := map[string]any{}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, readErr := tx.Get(ref)
		if readErr != nil || text(snapshot.Data(), "callId") != callID {
			return fmt.Errorf("%w: call is no longer current", app.ErrPrecondition)
		}
		call := snapshot.Data()
		if contains([]string{"declined", "expired", "ended"}, effectiveCallStatus(call, now)) {
			result = callResult(call)
			result["idempotent"] = true
			return nil
		}
		updates := map[string]any{"status": "ended", "endedBy": principal.UID, "endedAt": now, "updatedAt": now}
		tx.Set(ref, updates, firestore.MergeAll)
		for key, value := range updates {
			call[key] = value
		}
		writeOutbox(tx, store, "call.ended", callID, map[string]any{"bookingId": bookingID, "callId": callID})
		result = callResult(call)
		result["idempotent"] = false
		return nil
	})
	return result, err
}

func effectiveCallStatus(call map[string]any, now time.Time) string {
	status := text(call, "status")
	if status == "ringing" && !futureTime(call["expiresAt"], now) {
		return "expired"
	}
	if status == "accepted" && !futureTime(call["endsAt"], now) {
		return "ended"
	}
	return status
}

func callResult(call map[string]any) map[string]any {
	return map[string]any{
		"bookingId": text(call, "bookingId"), "callId": text(call, "callId"), "roomName": text(call, "roomName"),
		"serverUrl": text(call, "serverUrl"), "callerId": text(call, "callerId"), "recipientId": text(call, "recipientId"),
		"acceptedBy": text(call, "acceptedBy"), "status": text(call, "status"),
		"expiresAtMillis": timeMillis(call["expiresAt"]), "endsAtMillis": timeMillis(call["endsAt"]),
	}
}

func timeMillis(value any) int64 {
	switch typed := value.(type) {
	case time.Time:
		return typed.UnixMilli()
	case *time.Time:
		if typed != nil {
			return typed.UnixMilli()
		}
	case int64:
		return typed
	case float64:
		return int64(typed)
	}
	return 0
}

func (store *Store) liveKitCredentials(call map[string]any, participantID string) (map[string]any, error) {
	if store.cfg.LiveKitServerURL == "" || store.cfg.LiveKitAPIKey == "" || store.cfg.LiveKitAPISecret == "" {
		return nil, fmt.Errorf("%w: voice calling is not configured", app.ErrUnavailable)
	}
	now, endsAt := time.Now().UTC(), time.UnixMilli(int64(number(call, "endsAtMillis")))
	if endsAt.IsZero() || !endsAt.After(now) {
		return nil, fmt.Errorf("%w: call has ended", app.ErrPrecondition)
	}
	expires := now.Add(10 * time.Minute)
	if endsAt.Before(expires) {
		expires = endsAt
	}
	header, _ := json.Marshal(map[string]any{"alg": "HS256", "typ": "JWT"})
	claims, _ := json.Marshal(map[string]any{
		"iss": store.cfg.LiveKitAPIKey, "sub": participantID, "jti": uuid.NewString(), "nbf": now.Unix() - 5, "exp": expires.Unix(),
		"name": participantID, "video": map[string]any{"roomJoin": true, "room": text(call, "roomName"), "canPublish": true, "canSubscribe": true},
	})
	encode := base64.RawURLEncoding.EncodeToString
	unsigned := encode(header) + "." + encode(claims)
	mac := hmac.New(sha256.New, []byte(store.cfg.LiveKitAPISecret))
	_, _ = mac.Write([]byte(unsigned))
	return map[string]any{"serverUrl": store.cfg.LiveKitServerURL, "token": unsigned + "." + encode(mac.Sum(nil)), "roomName": text(call, "roomName"), "callId": text(call, "callId"), "endsAtMillis": endsAt.UnixMilli()}, nil
}

func (store *Store) sendRideChatMessage(ctx context.Context, principal app.Principal, command app.OperationCommand) (map[string]any, error) {
	bookingID, body := text(command.Payload, "bookingId"), truncate(text(command.Payload, "text"), 2000)
	if body == "" {
		return nil, fmt.Errorf("%w: message text is required", app.ErrInvalidArgument)
	}
	booking, err := store.participantBooking(ctx, principal, bookingID)
	if err != nil {
		return nil, err
	}
	messageID := strings.TrimSpace(command.CommandID)
	if messageID == "" {
		messageID = uuid.NewString()
	}
	conversation := store.firestore.Collection("chat").Doc(bookingID)
	message := conversation.Collection("messages").Doc(messageID)
	now := time.Now().UTC()
	created := false
	err = store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		existing, readErr := tx.Get(message)
		if readErr == nil {
			if text(existing.Data(), "senderId") != principal.UID {
				return fmt.Errorf("%w: messageId is already in use", app.ErrPrecondition)
			}
			return nil
		}
		if !isNotFound(readErr) {
			return readErr
		}
		tx.Set(conversation, map[string]any{
			"bookingId": bookingID, "members": []string{text(booking, "passengerId", "passengerID"), text(booking, "driverId", "driverID")},
			"lastMessage": body, "lastMessageAt": now, "updatedAt": now,
		}, firestore.MergeAll)
		tx.Create(message, map[string]any{"messageId": messageID, "senderId": principal.UID, "text": body, "sentAt": now, "seenBy": []string{principal.UID}})
		writeOutbox(tx, store, "chat.message.created", messageID, map[string]any{"bookingId": bookingID, "messageId": messageID, "senderId": principal.UID})
		created = true
		return nil
	})
	return map[string]any{"messageId": messageID, "idempotent": !created}, err
}

func (store *Store) markRideChatSeen(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	if _, err := store.participantBooking(ctx, principal, bookingID); err != nil {
		return nil, err
	}
	documents, err := store.firestore.Collection("chat").Doc(bookingID).Collection("messages").OrderBy("sentAt", firestore.Desc).Limit(50).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	batch, changed := store.firestore.Batch(), 0
	for _, document := range documents {
		if !contains(stringSlice(document.Data()["seenBy"]), principal.UID) {
			batch.Set(document.Ref, map[string]any{"seenBy": firestore.ArrayUnion(principal.UID)}, firestore.MergeAll)
			changed++
		}
	}
	if changed > 0 {
		if _, err = batch.Commit(ctx); err != nil {
			return nil, err
		}
	}
	return map[string]any{"markedRead": changed}, nil
}

func (store *Store) setRideChatTyping(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID := text(payload, "bookingId")
	if _, err := store.participantBooking(ctx, principal, bookingID); err != nil {
		return nil, err
	}
	_, err := store.firestore.Collection("chat").Doc(bookingID).Collection("typing").Doc(principal.UID).Set(ctx, map[string]any{"isTyping": booleanDefault(payload, false, "isTyping"), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) reportRestrictionPosition(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	driverSnapshot, err := store.firestore.Collection("drivers").Doc(principal.UID).Get(ctx)
	if err != nil || text(driverSnapshot.Data(), "driverStatus") != "approved" {
		return nil, fmt.Errorf("%w: approved driver profile is required", app.ErrPrecondition)
	}
	profile, err := store.firestore.Collection("driver_profiles").Doc(principal.UID).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: active driver session is required", app.ErrPrecondition)
	}
	sessionID := text(profile.Data(), "activeSessionId")
	location := map[string]any{}
	if sessionID == "" || store.realtime.NewRef("driverLocations/"+principal.UID+"/"+sessionID).Get(ctx, &location) != nil {
		return nil, fmt.Errorf("%w: fresh driver location is required", app.ErrPrecondition)
	}
	point := core.Coordinate{Latitude: number(location, "latitude"), Longitude: number(location, "longitude")}
	if !point.Valid() || time.Now().UnixMilli()-int64(number(location, "timestamp")) > 120000 {
		return nil, fmt.Errorf("%w: driver location is stale", app.ErrPrecondition)
	}
	restrictions, _, err := store.readRestrictions(ctx)
	if err != nil {
		return nil, err
	}
	inside := make([]string, 0)
	created, exited, pending := []string{}, []string{}, []string{}
	for _, restriction := range restrictions {
		isInside := core.FirstEndpointConflict(point, point, []core.Restriction{restriction}) != nil
		if isInside {
			inside = append(inside, restriction.ID)
		}
		transition, violationID, transitionErr := store.observeRestriction(ctx, principal, driverSnapshot.Data(), restriction, location, isInside, text(payload, "bookingId"))
		if transitionErr != nil {
			return nil, transitionErr
		}
		switch transition {
		case "enter":
			created = append(created, violationID)
		case "exit":
			exited = append(exited, violationID)
		case "pending":
			pending = append(pending, restriction.ID)
		}
	}
	return map[string]any{"activeRestrictionIds": inside, "createdViolationIds": created, "exitedViolationIds": exited, "pendingRestrictionIds": pending, "locationTimestamp": location["timestamp"]}, nil
}

func (store *Store) observeRestriction(ctx context.Context, principal app.Principal, driver map[string]any, restriction core.Restriction, location map[string]any, inside bool, bookingID string) (string, string, error) {
	stateRef := store.firestore.Collection("driverRestrictionStates").Doc(principal.UID + "_" + restriction.ID)
	result, violationID := "", ""
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, readErr := tx.Get(stateRef)
		state := map[string]any{}
		if readErr == nil {
			state = snapshot.Data()
		} else if !isNotFound(readErr) {
			return readErr
		}
		if number(state, "lastSequence") >= number(location, "sampleSequence") {
			return nil
		}
		previousInside := booleanDefault(state, false, "inside")
		candidateInside := booleanDefault(state, false, "candidateInside")
		candidateCount := integer(state, "candidateCount")
		if candidateInside != inside {
			candidateCount = 0
		}
		candidateCount++
		now := time.Now().UTC()
		updates := map[string]any{"driverId": principal.UID, "restrictionId": restriction.ID, "candidateInside": inside, "candidateCount": candidateCount, "lastSequence": location["sampleSequence"], "updatedAt": now}
		if candidateCount >= 2 && previousInside != inside {
			updates["inside"], updates["candidateCount"] = inside, 0
			if inside {
				violationID = "violation_" + strings.ReplaceAll(uuid.NewString(), "-", "")
				updates["activeViolationId"] = violationID
				violationRef := store.firestore.Collection("driverViolations").Doc(violationID)
				tx.Create(violationRef, map[string]any{
					"schemaVersion": 1, "violationId": violationID, "driverId": principal.UID,
					"ownerTodaId": text(driver, "todaId"), "bookingId": bookingID, "status": "open",
					"eventClass": "restricted_area_entry", "restrictionId": restriction.ID, "restrictionName": restriction.Name,
					"eventLocation": map[string]any{"latitude": pointNumber(location, "latitude"), "longitude": pointNumber(location, "longitude"), "accuracy": pointNumber(location, "accuracy")},
					"occurredAt":    now, "createdAt": now, "updatedAt": now,
				})
				writeOutbox(tx, store, "violation.created", violationID, map[string]any{"violationId": violationID, "driverId": principal.UID})
				result = "enter"
			} else {
				violationID = text(state, "activeViolationId")
				updates["activeViolationId"] = nil
				if violationID != "" {
					tx.Set(store.firestore.Collection("driverViolations").Doc(violationID), map[string]any{"exitedAt": now, "updatedAt": now}, firestore.MergeAll)
				}
				result = "exit"
			}
		} else if previousInside != inside {
			result = "pending"
		}
		tx.Set(stateRef, updates, firestore.MergeAll)
		return nil
	})
	return result, violationID, err
}

func (store *Store) listMyDriverViolations(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	documents, err := store.firestore.Collection("driverViolations").Where("driverId", "==", principal.UID).OrderBy("occurredAt", firestore.Desc).Limit(100).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	includeClosed := booleanDefault(payload, false, "includeClosed")
	items := make([]map[string]any, 0, len(documents))
	for _, document := range documents {
		data := document.Data()
		status := text(data, "status")
		if !includeClosed && (status == "resolved" || status == "dismissed") {
			continue
		}
		data["id"], data["violationId"] = document.Ref.ID, document.Ref.ID
		items = append(items, data)
	}
	return map[string]any{"items": items}, nil
}

func (store *Store) sendDriverViolationMessage(ctx context.Context, principal app.Principal, command app.OperationCommand) (map[string]any, error) {
	violationID, body := text(command.Payload, "violationId"), truncate(firstText(command.Payload, command.Payload, "message", "body"), 2000)
	messageID := text(command.Payload, "messageId")
	if messageID == "" {
		messageID = command.CommandID
	}
	if violationID == "" || messageID == "" || body == "" {
		return nil, fmt.Errorf("%w: violationId, messageId, and message are required", app.ErrInvalidArgument)
	}
	violationRef := store.firestore.Collection("driverViolations").Doc(violationID)
	messageRef := violationRef.Collection("messages").Doc(messageID)
	idempotent := false
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		violation, violationErr := tx.Get(violationRef)
		existing, existingErr := tx.Get(messageRef)
		if violationErr != nil {
			return fmt.Errorf("%w: violation not found", app.ErrPrecondition)
		}
		data := violation.Data()
		if text(data, "driverId") != principal.UID && !adminPrincipal(principal) {
			return fmt.Errorf("%w: violation is not visible to user", app.ErrPrecondition)
		}
		if existingErr == nil {
			if text(existing.Data(), "senderId") == principal.UID {
				idempotent = true
				return nil
			}
			return fmt.Errorf("%w: messageId is already used", app.ErrPrecondition)
		}
		if !isNotFound(existingErr) {
			return existingErr
		}
		now := time.Now().UTC()
		tx.Create(messageRef, map[string]any{"messageId": messageID, "violationId": violationID, "senderId": principal.UID, "senderRole": participantViolationRole(data, principal), "body": body, "seenBy": []string{principal.UID}, "sentAt": now, "createdAt": now})
		tx.Set(violationRef, map[string]any{"lastMessage": truncate(body, 240), "lastMessageAt": now, "lastMessageBy": principal.UID, "messageCount": integer(data, "messageCount") + 1, "updatedAt": now}, firestore.MergeAll)
		writeOutbox(tx, store, "violation.message.created", messageID, map[string]any{"violationId": violationID, "messageId": messageID})
		return nil
	})
	return map[string]any{"violationId": violationID, "messageId": messageID, "idempotent": idempotent}, err
}

func (store *Store) markDriverViolationMessagesRead(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	violationID := text(payload, "violationId")
	violation, err := store.firestore.Collection("driverViolations").Doc(violationID).Get(ctx)
	if err != nil || text(violation.Data(), "driverId") != principal.UID && !adminPrincipal(principal) {
		return nil, fmt.Errorf("%w: violation not available", app.ErrPrecondition)
	}
	documents, err := violation.Ref.Collection("messages").OrderBy("sentAt", firestore.Desc).Limit(100).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	batch, changed := store.firestore.Batch(), 0
	for _, document := range documents {
		if !contains(stringSlice(document.Data()["seenBy"]), principal.UID) {
			batch.Set(document.Ref, map[string]any{"seenBy": firestore.ArrayUnion(principal.UID)}, firestore.MergeAll)
			changed++
		}
	}
	if changed > 0 {
		_, err = batch.Commit(ctx)
	}
	return map[string]any{"markedRead": changed}, err
}

func pointNumber(data map[string]any, key string) float64 { return number(data, key) }

func participantViolationRole(violation map[string]any, principal app.Principal) string {
	if text(violation, "driverId") == principal.UID {
		return "driver"
	}
	return strings.ToLower(text(principal.Claims, "role"))
}

func writeOutbox(tx *firestore.Transaction, store *Store, eventType, aggregateID string, payload map[string]any) {
	ref := store.firestore.Collection("outbox").Doc(uuid.NewString())
	tx.Set(ref, map[string]any{"eventId": ref.ID, "type": eventType, "aggregateId": aggregateID, "payload": payload, "createdAt": time.Now().UTC(), "consumers": []string{"notifications"}})
}

func participantRole(booking map[string]any, uid string) string {
	if text(booking, "passengerId", "passengerID") == uid {
		return "passenger"
	}
	return "driver"
}

func truncate(value string, maximum int) string {
	value = strings.TrimSpace(value)
	if len(value) > maximum {
		return value[:maximum]
	}
	return value
}

func valueOr(data map[string]any, key, fallback string) string {
	if value := text(data, key); value != "" {
		return value
	}
	return fallback
}

func mathRound(value float64, places int) float64 {
	factor := 1.0
	for range places {
		factor *= 10
	}
	return float64(int64(value*factor+0.5)) / factor
}
