package firebase

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
)

const cancellationWindow = 24 * time.Hour

func verifiedPickupArrival(booking, location map[string]any, now time.Time) bool {
	if location == nil || !booleanDefault(location, false, "online") || number(location, "accuracy") <= 0 || number(location, "accuracy") > 100 {
		return false
	}
	received := time.UnixMilli(int64(number(location, "receivedAt")))
	observed := time.UnixMilli(int64(number(location, "timestamp")))
	if now.Sub(received) < 0 || now.Sub(received) > time.Minute || now.Sub(observed) < 0 || now.Sub(observed) > time.Minute {
		return false
	}
	pickup, _ := booking["pickup"].(map[string]any)
	if pickup == nil {
		return false
	}
	a := core.Coordinate{Latitude: number(pickup, "latitude"), Longitude: number(pickup, "longitude")}
	b := core.Coordinate{Latitude: number(location, "latitude"), Longitude: number(location, "longitude")}
	return a.Valid() && b.Valid() && core.HaversineMeters(a, b) <= 150
}

// Only explicit passenger-fault reasons qualify automatically. Unknown,
// safety, driver-fault, and no-show claims need review rather than a strike.
func cancellationAssessment(booking map[string]any, actor, action, reason string) string {
	if text(booking, "driverId", "driverID") == "" || !contains([]string{"driverAssigned", "driverArriving"}, text(booking, "status")) {
		return "excluded"
	}
	if action == "noShow" {
		if actor == text(booking, "driverId", "driverID") {
			return "pending_review"
		}
		return "excluded"
	}
	if actor != text(booking, "passengerId", "passengerID") || action != "cancel" {
		return "excluded"
	}
	switch strings.ToLower(strings.TrimSpace(reason)) {
	case "change_of_plans", "booked_by_mistake":
		return "counted"
	default:
		return "pending_review"
	}
}

func activeCancellationStrikes(policy map[string]any, now time.Time) []map[string]any {
	strikes := []map[string]any{}
	for _, strike := range cancellationStrikes(policy) {
		at := storedTime(strike["at"])
		if at.After(now.Add(-cancellationWindow)) && !at.After(now) && at.After(storedTime(policy["strikeResetAt"])) {
			strikes = append(strikes, strike)
		}
	}
	return strikes
}

// Preserve native Firestore timestamps; JSON conversion turns them into text.
func cancellationStrikes(policy map[string]any) []map[string]any {
	switch values := policy["strikes"].(type) {
	case []map[string]any:
		return values
	case []any:
		result := []map[string]any{}
		for _, raw := range values {
			if value, ok := raw.(map[string]any); ok {
				result = append(result, value)
			}
		}
		return result
	}
	return nil
}

func bookingBlockedUntil(policy map[string]any) time.Time {
	automatic, manual := storedTime(policy["blockedUntil"]), storedTime(policy["manualBlockedUntil"])
	if manual.After(automatic) {
		return manual
	}
	return automatic
}

// The booking transaction reads and writes this same policy document, making
// concurrent cancellations, booking creation, and admin decisions serialize.
func addCancellationStrike(policy map[string]any, bookingID string, at, now time.Time) map[string]any {
	result := copyMap(policy)
	strikes := activeCancellationStrikes(policy, now)
	for _, strike := range strikes {
		if text(strike, "bookingId") == bookingID {
			return result
		}
	}
	if !at.After(now.Add(-cancellationWindow)) || at.After(now) || !at.After(storedTime(policy["strikeResetAt"])) {
		return result
	}
	strikes = append(strikes, map[string]any{"bookingId": bookingID, "at": at})
	result["strikes"] = strikes
	if len(strikes) >= 3 && !futureTime(policy["blockedUntil"], now) {
		result["blockedUntil"] = now.Add(cancellationWindow)
		result["originalBlockedUntil"] = now.Add(cancellationWindow)
		basis := []string{}
		for _, strike := range strikes {
			basis = append(basis, text(strike, "bookingId"))
		}
		result["restrictionBookingIds"] = basis
		result["restrictionCount"] = integer(policy, "restrictionCount") + 1
		result["reason"] = "Three qualifying cancellations within 24 hours."
		result["reviewRequired"] = true
	}
	result["updatedAt"] = now
	return result
}

func removeCancellationStrike(policy map[string]any, bookingID string, now time.Time) map[string]any {
	result := copyMap(policy)
	strikes := []map[string]any{}
	for _, strike := range activeCancellationStrikes(policy, now) {
		if text(strike, "bookingId") != bookingID {
			strikes = append(strikes, strike)
		}
	}
	result["strikes"] = strikes
	basis := stringSlice(policy["restrictionBookingIds"])
	if contains(basis, bookingID) {
		result["blockedUntil"] = nil
	}
	result["updatedAt"] = now
	return result
}

func upholdCancellationStrike(policy map[string]any, bookingID string, at, now time.Time) map[string]any {
	basis := stringSlice(policy["restrictionBookingIds"])
	if !contains(basis, bookingID) {
		result := addCancellationStrike(policy, bookingID, at, now)
		result["disputedBookingIds"] = withoutString(stringSlice(policy["disputedBookingIds"]), bookingID)
		return result
	}
	// Reinstating an appealed strike resumes the original cooldown. It must
	// neither extend its expiry nor count as a second automatic restriction.
	result := copyMap(policy)
	strikes := activeCancellationStrikes(policy, now)
	if at.After(now.Add(-cancellationWindow)) && !at.After(now) {
		strikes = append(strikes, map[string]any{"bookingId": bookingID, "at": at, "appealed": true})
	}
	result["strikes"] = strikes
	disputed := withoutString(stringSlice(policy["disputedBookingIds"]), bookingID)
	result["disputedBookingIds"] = disputed
	canResume := len(basis) >= 3
	for _, id := range basis {
		if contains(disputed, id) {
			canResume = false
		}
	}
	if canResume {
		result["blockedUntil"] = policy["originalBlockedUntil"]
	}
	result["updatedAt"] = now
	return result
}

func (store *Store) appealPassengerCancellation(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	bookingID, reason := text(payload, "bookingId"), strings.TrimSpace(text(payload, "reason"))
	if bookingID == "" || len(reason) < 10 || len(reason) > 1000 {
		return nil, fmt.Errorf("%w: select a cancellation and explain your appeal in 10–1000 characters", app.ErrInvalidArgument)
	}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		eventRef := store.firestore.Collection("passengerCancellationEvents").Doc(bookingID)
		event, err := tx.Get(eventRef)
		if err != nil || text(event.Data(), "passengerId") != principal.UID || text(event.Data(), "status") != "counted" || !storedTime(event.Data()["appealedAt"]).IsZero() {
			return fmt.Errorf("%w: this cancellation is unavailable for appeal or has already been appealed", app.ErrPrecondition)
		}
		policyRef := store.firestore.Collection("passengerBookingPolicies").Doc(principal.UID)
		policy, err := tx.Get(policyRef)
		if err != nil {
			return err
		}
		now := time.Now().UTC()
		updates := removeCancellationStrike(policy.Data(), bookingID, now)
		updates["reviewRequired"] = true
		updates["disputedBookingIds"] = append(withoutString(stringSlice(policy.Data()["disputedBookingIds"]), bookingID), bookingID)
		updates["appealedBookingIds"] = append(withoutString(stringSlice(policy.Data()["appealedBookingIds"]), bookingID), bookingID)
		tx.Set(policyRef, updates)
		tx.Set(eventRef, map[string]any{"status": "disputed", "appealReason": reason, "appealedAt": now, "updatedAt": now}, firestore.MergeAll)
		return nil
	})
	return map[string]any{"submitted": err == nil}, err
}

func (store *Store) appealPassengerBookingRestriction(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	reason := strings.TrimSpace(text(payload, "reason"))
	if len(reason) < 10 || len(reason) > 1000 {
		return nil, fmt.Errorf("%w: explain your appeal in 10–1000 characters", app.ErrInvalidArgument)
	}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		ref := store.firestore.Collection("passengerBookingPolicies").Doc(principal.UID)
		snapshot, err := tx.Get(ref)
		if err != nil {
			return fmt.Errorf("%w: restriction not found", app.ErrPrecondition)
		}
		data := snapshot.Data()
		if !futureTime(data["manualBlockedUntil"], time.Now().UTC()) || text(data, "manualAppealStatus") == "pending" {
			return fmt.Errorf("%w: no restriction is available for a new appeal", app.ErrPrecondition)
		}
		eventRef := store.firestore.Collection("passengerCancellationEvents").Doc(text(data, "manualCaseBookingId"))
		event, err := tx.Get(eventRef)
		if err != nil || text(event.Data(), "passengerId") != principal.UID {
			return fmt.Errorf("%w: restriction case is unavailable", app.ErrPrecondition)
		}
		now := time.Now().UTC()
		tx.Set(ref, map[string]any{"manualAppealStatus": "pending", "reviewRequired": true, "updatedAt": now}, firestore.MergeAll)
		tx.Set(eventRef, map[string]any{"manualAppealReason": reason, "manualAppealStatus": "pending", "updatedAt": now}, firestore.MergeAll)
		return nil
	})
	return map[string]any{"submitted": err == nil}, err
}

func (store *Store) adminReviewPassengerCancellation(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: only System Admin may review passenger cancellations", app.ErrPrecondition)
	}
	bookingID, decision, reason := text(payload, "bookingId"), text(payload, "decision"), strings.TrimSpace(text(payload, "reason"))
	if bookingID == "" || !contains([]string{"uphold", "waive", "restrict", "restore"}, decision) || len(reason) < 10 || len(reason) > 1000 {
		return nil, fmt.Errorf("%w: a supported decision and a reason of 10–1000 characters are required", app.ErrInvalidArgument)
	}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		eventRef := store.firestore.Collection("passengerCancellationEvents").Doc(bookingID)
		event, err := tx.Get(eventRef)
		if err != nil {
			return fmt.Errorf("%w: cancellation not found", app.ErrPrecondition)
		}
		data := event.Data()
		policyRef := store.firestore.Collection("passengerBookingPolicies").Doc(text(data, "passengerId"))
		policy, err := tx.Get(policyRef)
		if err != nil {
			return err
		}
		now := time.Now().UTC()
		updates, eventUpdates := copyMap(policy.Data()), map[string]any{"reviewedBy": actor.UID, "reviewReason": reason, "reviewedAt": now, "updatedAt": now}
		switch decision {
		case "uphold":
			if !contains([]string{"pending_review", "disputed"}, text(data, "status")) {
				return fmt.Errorf("%w: cancellation is not pending review", app.ErrPrecondition)
			}
			if text(data, "reasonCode") == "passenger_no_show" && (!booleanDefault(data, false, "arrivalVerified") || !booleanDefault(data, false, "waitVerified")) {
				return fmt.Errorf("%w: a no-show requires verified arrival and waiting records", app.ErrPrecondition)
			}
			updates = upholdCancellationStrike(updates, bookingID, storedTime(data["createdAt"]), now)
			if !storedTime(data["appealedAt"]).IsZero() {
				for _, strike := range cancellationStrikes(updates) {
					if text(strike, "bookingId") == bookingID {
						strike["appealed"] = true
					}
				}
			}
			eventUpdates["status"] = "counted"
		case "waive":
			updates = removeCancellationStrike(updates, bookingID, now)
			updates["restrictionBookingIds"] = withoutString(stringSlice(updates["restrictionBookingIds"]), bookingID)
			updates["disputedBookingIds"] = withoutString(stringSlice(updates["disputedBookingIds"]), bookingID)
			eventUpdates["status"] = "waived"
		case "restrict":
			hours := integer(payload, "hours")
			if hours < 1 || hours > 720 {
				return fmt.Errorf("%w: restriction must be between 1 and 720 hours", app.ErrInvalidArgument)
			}
			updates["manualBlockedUntil"], updates["manualReason"] = now.Add(time.Duration(hours)*time.Hour), reason
			updates["manualCaseBookingId"], updates["manualAppealStatus"] = bookingID, ""
			eventUpdates["manualAppealStatus"] = "reviewed"
		case "restore":
			updates["blockedUntil"], updates["manualBlockedUntil"], updates["strikes"] = nil, nil, []map[string]any{}
			updates["restrictionBookingIds"] = []string{}
			updates["originalBlockedUntil"] = nil
			updates["strikeResetAt"] = now
			updates["manualAppealStatus"], eventUpdates["manualAppealStatus"] = "reviewed", "reviewed"
		}
		updates["updatedAt"], updates["reviewedBy"], updates["reviewNote"] = now, actor.UID, reason
		tx.Set(policyRef, updates)
		tx.Set(eventRef, eventUpdates, firestore.MergeAll)
		return nil
	})
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) adminListPassengerCancellations(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: only System Admin may review passenger cancellations", app.ErrPrecondition)
	}
	query := store.firestore.Collection("passengerCancellationEvents").OrderBy("updatedAt", firestore.Desc).Limit(50)
	if cursor := text(payload, "cursor"); cursor != "" {
		doc, err := store.firestore.Collection("passengerCancellationEvents").Doc(cursor).Get(ctx)
		if err != nil {
			return nil, err
		}
		query = query.StartAfter(doc)
	}
	documents, err := query.Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	items := []map[string]any{}
	for _, document := range documents {
		data := document.Data()
		if policy, err := store.firestore.Collection("passengerBookingPolicies").Doc(text(data, "passengerId")).Get(ctx); err == nil {
			data["blockedUntil"] = bookingBlockedUntil(policy.Data())
			data["restrictionCount"] = integer(policy.Data(), "restrictionCount")
			data["strikeCount"] = len(activeCancellationStrikes(policy.Data(), time.Now().UTC()))
		}
		items = append(items, maskAdminPassengerData(data))
	}
	next := ""
	if len(documents) == 50 {
		next = documents[len(documents)-1].Ref.ID
	}
	return map[string]any{"items": items, "nextCursor": next}, nil
}
