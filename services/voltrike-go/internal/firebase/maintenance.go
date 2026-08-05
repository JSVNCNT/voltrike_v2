package firebase

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
	"google.golang.org/api/iterator"
)

func (store *Store) ListMaintenanceBookings(ctx context.Context, _ time.Time) ([]app.MaintenanceBooking, error) {
	documents := store.firestore.Collection("bookings").Where("status", "==", "pending").Limit(100).Documents(ctx)
	defer documents.Stop()
	result := make([]app.MaintenanceBooking, 0)
	for {
		document, err := documents.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("list pending bookings for maintenance: %w", err)
		}
		data := document.Data()
		pickup := coordinate(data["pickup"])
		if !pickup.Valid() {
			continue
		}
		result = append(result, app.MaintenanceBooking{
			BookingID:          document.Ref.ID,
			Pickup:             pickup,
			PrimaryTodaIDs:     stringSlice(data["primaryTodaIds"]),
			SecondaryTodaIDs:   stringSlice(data["secondaryTodaIds"]),
			AllowAnyActiveToda: booleanDefault(data, false, "allowAnyActiveToda"),
			RequiredSeats:      integer(data, "additionalPassengers") + 1,
			SearchExpiresAt:    storedTime(data["searchExpiresAt"]),
			OfferExpiresAt:     storedTime(data["nextDispatchAt"]),
		})
	}
	return result, nil
}

func (store *Store) ExpireBookingSearch(ctx context.Context, bookingID string, now time.Time) (bool, error) {
	changed := false
	bookingRef := store.firestore.Collection("bookings").Doc(bookingID)
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(bookingRef)
		if err != nil {
			return nil
		}
		data := snapshot.Data()
		if text(data, "status") != "pending" || storedTime(data["searchExpiresAt"]).After(now) {
			return nil
		}
		passengerID := text(data, "passengerId")
		revision := integer(data, "revision") + 1
		tx.Set(bookingRef, map[string]any{
			"status": "cancelled", "cancelReasonCode": "search_expired",
			"revision": revision, "cancelledAt": now, "updatedAt": now,
		}, firestore.MergeAll)
		if passengerID != "" {
			tx.Delete(store.firestore.Collection("activePassengerBookings").Doc(passengerID))
		}
		writeOutbox(tx, store, "booking.cancelled", bookingID, map[string]any{
			"bookingId": bookingID, "reasonCode": "search_expired", "revision": revision,
		})
		changed = true
		return nil
	})
	return changed, err
}

func (store *Store) ExpireCallsAndEscalateSafety(ctx context.Context, now time.Time) (map[string]int, error) {
	callsExpired := 0
	for _, query := range []struct {
		status string
		field  string
		next   string
	}{
		{status: "ringing", field: "expiresAt", next: "expired"},
		{status: "accepted", field: "endsAt", next: "ended"},
	} {
		documents := store.firestore.Collection("bookingCalls").Where("status", "==", query.status).Where(query.field, "<=", now).Limit(100).Documents(ctx)
		for {
			document, err := documents.Next()
			if err == iterator.Done {
				break
			}
			if err != nil {
				documents.Stop()
				return nil, err
			}
			updates := map[string]any{"status": query.next, "updatedAt": now}
			if query.next == "expired" {
				updates["expiredAt"] = now
			} else {
				updates["endedAt"], updates["endedBy"] = now, "system"
			}
			if _, err := document.Ref.Set(ctx, updates, firestore.MergeAll); err == nil {
				callsExpired++
			}
		}
		documents.Stop()
	}
	safetyEscalated := 0
	safety := store.firestore.Collection("safetyIncidents").Where("status", "==", "open").Limit(200).Documents(ctx)
	defer safety.Stop()
	for {
		document, err := safety.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		data := document.Data()
		if text(data, "responseStatus") != "reported" && text(data, "responseStatus") != "" {
			continue
		}
		age := now.Sub(storedTime(data["createdAt"]))
		target := 0
		if age >= 5*time.Minute {
			target = 2
		} else if age >= 2*time.Minute {
			target = 1
		}
		if target <= integer(data, "escalationLevel") {
			continue
		}
		batch := store.firestore.Batch()
		batch.Set(document.Ref, map[string]any{"escalationLevel": target, "escalatedAt": now, "updatedAt": now}, firestore.MergeAll)
		eventRef := store.firestore.Collection("outbox").Doc(uuid.NewString())
		batch.Set(eventRef, map[string]any{
			"eventId": eventRef.ID, "type": "safety.escalated", "aggregateId": document.Ref.ID,
			"payload":   map[string]any{"incidentId": document.Ref.ID, "bookingId": text(data, "bookingId"), "todaId": text(data, "todaId"), "escalationLevel": target},
			"createdAt": now, "consumers": []string{"notifications"},
		})
		if _, err := batch.Commit(ctx); err == nil {
			safetyEscalated++
		}
	}
	return map[string]int{"callsExpired": callsExpired, "safetyEscalated": safetyEscalated}, nil
}

func coordinate(value any) core.Coordinate {
	data, _ := value.(map[string]any)
	return core.Coordinate{Latitude: number(data, "latitude", "lat"), Longitude: number(data, "longitude", "lng")}
}

func storedTime(value any) time.Time {
	switch typed := value.(type) {
	case time.Time:
		return typed
	case *time.Time:
		if typed != nil {
			return *typed
		}
	}
	return time.Time{}
}
