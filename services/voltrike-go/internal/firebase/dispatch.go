package firebase

import (
	"context"
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
		result = append(result, candidate)
	}
	return result, nil
}

func (store *Store) PublishBookingOffers(ctx context.Context, bookingID string, candidates []app.DispatchCandidate, expiresAt time.Time) error {
	bookingRef := store.firestore.Collection("bookings").Doc(bookingID)
	batch := store.firestore.Batch()
	ids := make([]string, 0, len(candidates))
	now := time.Now().UTC()
	for _, candidate := range candidates {
		ids = append(ids, candidate.DriverID)
		offer := store.firestore.Collection("drivers").Doc(candidate.DriverID).Collection("bookingOffers").Doc(bookingID)
		batch.Set(offer, map[string]any{"bookingId": bookingID, "driverId": candidate.DriverID, "todaId": candidate.TodaID, "status": "offered", "offerRound": 1, "distanceMeters": candidate.DistanceMeters, "servicePriority": candidate.ServicePriority, "dispatchPolicyVersion": 3, "expiresAt": expiresAt, "createdAt": now, "updatedAt": now})
	}
	batch.Set(bookingRef, map[string]any{"offerRound": 1, "currentOfferDriverIds": ids, "offeredDriverIds": ids, "nextDispatchAt": expiresAt, "updatedAt": now}, firestore.MergeAll)
	_, err := batch.Commit(ctx)
	return err
}
