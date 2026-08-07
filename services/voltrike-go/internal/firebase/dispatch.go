package firebase

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/voltrike/voltrike-go/internal/app"
)

func (store *Store) FilterEligibleDispatch(ctx context.Context, candidates []app.DispatchCandidate, request app.DispatchRequest) ([]app.DispatchCandidate, error) {
	if len(candidates) == 0 {
		return candidates, nil
	}
	driverRefs := make([]*firestore.DocumentRef, 0, len(candidates))
	byID := map[string]app.DispatchCandidate{}
	for _, candidate := range candidates {
		driverRefs = append(driverRefs, store.firestore.Collection("drivers").Doc(candidate.DriverID))
		byID[candidate.DriverID] = candidate
	}
	drivers, err := store.firestore.GetAll(ctx, driverRefs)
	if err != nil {
		return nil, err
	}
	vehicleRefs, todaRefs := []*firestore.DocumentRef{}, []*firestore.DocumentRef{}
	driverData := map[string]map[string]any{}
	for _, document := range drivers {
		if !document.Exists() {
			continue
		}
		data := document.Data()
		id := document.Ref.ID
		if text(data, "driverStatus") != "approved" || !booleanDefault(data, false, "isOnline") || !booleanDefault(data, false, "isAvailable") || text(data, "currentBookingId") != "" {
			continue
		}
		driverData[id] = data
		vehicleRefs = append(vehicleRefs, store.firestore.Collection("vehicles").Doc(text(data, "vehicleId")))
		todaRefs = append(todaRefs, store.firestore.Collection("todas").Doc(text(data, "todaId")))
	}
	if len(driverData) == 0 {
		return []app.DispatchCandidate{}, nil
	}
	vehicles, err := store.firestore.GetAll(ctx, vehicleRefs)
	if err != nil {
		return nil, err
	}
	todas, err := store.firestore.GetAll(ctx, todaRefs)
	if err != nil {
		return nil, err
	}
	vehicleByID, todaByID := map[string]map[string]any{}, map[string]map[string]any{}
	for _, document := range vehicles {
		if document.Exists() {
			vehicleByID[document.Ref.ID] = document.Data()
		}
	}
	for _, document := range todas {
		if document.Exists() {
			todaByID[document.Ref.ID] = document.Data()
		}
	}
	result := make([]app.DispatchCandidate, 0, len(driverData))
	now := time.Now().UTC()
	requiredSeats := request.RequiredSeats
	if requiredSeats < 1 {
		requiredSeats = 1
	}
	for id, data := range driverData {
		vehicle, toda := vehicleByID[text(data, "vehicleId")], todaByID[text(data, "todaId")]
		if !booleanDefault(vehicle, false, "isVerified") || !vehicleCanServe(vehicle, requiredSeats) || !booleanDefault(toda, false, "isActive") || text(data, "licenseNumber") == "" || !futureTime(data["licenseExpiry"], now) {
			continue
		}
		candidate := byID[id]
		candidate.TodaID = text(data, "todaId")
		candidate.ServicePriority = dispatchServicePriority(candidate.TodaID, request)
		result = append(result, candidate)
	}
	return result, nil
}

// dispatchServicePriority preserves TODA service preference without preventing
// a nearby verified active driver from serving a booking outside configured
// coverage.  Lower values sort first.
func dispatchServicePriority(todaID string, request app.DispatchRequest) int {
	if contains(request.PrimaryTodaIDs, todaID) {
		return 0
	}
	if contains(request.SecondaryTodaIDs, todaID) {
		return 1
	}
	if request.AllowAnyActiveToda {
		return 2
	}
	return 3
}

func (store *Store) PublishBookingOffers(ctx context.Context, bookingID string, candidates []app.DispatchCandidate, expiresAt time.Time) error {
	bookingRef := store.firestore.Collection("bookings").Doc(bookingID)
	return store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		bookingSnapshot, err := tx.Get(bookingRef)
		if err != nil || !bookingSnapshot.Exists() {
			return fmt.Errorf("read booking offer snapshot: %w", err)
		}
		bookingData := bookingSnapshot.Data()
		if text(bookingData, "status") != "pending" {
			return fmt.Errorf("booking is no longer pending")
		}
		nextRound := integer(bookingData, "offerRound") + 1
		ids := make([]string, 0, len(candidates))
		now := time.Now().UTC()
		for _, candidate := range candidates {
			ids = append(ids, candidate.DriverID)
			offer := store.firestore.Collection("drivers").Doc(candidate.DriverID).Collection("bookingOffers").Doc(bookingID)
			payload := bookingOfferSnapshot(bookingData)
			payload["bookingId"], payload["driverId"], payload["todaId"] = bookingID, candidate.DriverID, candidate.TodaID
			payload["status"], payload["offerRound"] = "offered", nextRound
			payload["distanceMeters"], payload["servicePriority"] = candidate.DistanceMeters, candidate.ServicePriority
			payload["dispatchPolicyVersion"], payload["expiresAt"] = 3, expiresAt
			payload["createdAt"], payload["updatedAt"] = now, now
			tx.Set(offer, payload)
		}
		tx.Set(bookingRef, map[string]any{"offerRound": nextRound, "currentOfferDriverIds": ids, "offeredDriverIds": ids, "nextDispatchAt": expiresAt, "updatedAt": now}, firestore.MergeAll)
		return nil
	})
}

// bookingOfferSnapshot gives an offered driver everything required to render a
// request from the offer's Firestore event. It contains only the immutable,
// server-owned booking fields needed before acceptance.
func bookingOfferSnapshot(booking map[string]any) map[string]any {
	payload := map[string]any{"bookingStatus": text(booking, "status")}
	for _, field := range []string{
		"schemaVersion", "passengerId", "passengerName", "passengerPhotoUrl",
		"pickup", "destination", "pickupName", "destinationName", "pickupAddress", "destinationAddress",
		"estimatedFare", "amountDue", "distanceMeters", "additionalPassengers", "baggageCount",
		"isOutsideToda", "routePolicy", "highwayRouteAdvisory", "createdAt", "updatedAt",
	} {
		if value, ok := booking[field]; ok {
			payload[field] = value
		}
	}
	if value, ok := booking["createdAt"]; ok {
		payload["bookingCreatedAt"] = value
	}
	return payload
}
