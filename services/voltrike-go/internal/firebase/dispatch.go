package firebase

import (
	"context"
	"fmt"
	"math"
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
	userRefs, vehicleRefs, todaRefs := []*firestore.DocumentRef{}, []*firestore.DocumentRef{}, []*firestore.DocumentRef{}
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
		userRefs = append(userRefs, store.firestore.Collection("users").Doc(id))
		vehicleRefs = append(vehicleRefs, store.firestore.Collection("vehicles").Doc(text(data, "vehicleId")))
		todaRefs = append(todaRefs, store.firestore.Collection("todas").Doc(text(data, "todaId")))
	}
	if len(driverData) == 0 {
		return []app.DispatchCandidate{}, nil
	}
	users, err := store.firestore.GetAll(ctx, userRefs)
	if err != nil {
		return nil, err
	}
	vehicles, err := store.firestore.GetAll(ctx, vehicleRefs)
	if err != nil {
		return nil, err
	}
	todas, err := store.firestore.GetAll(ctx, todaRefs)
	if err != nil {
		return nil, err
	}
	userByID, vehicleByID, todaByID := map[string]map[string]any{}, map[string]map[string]any{}, map[string]map[string]any{}
	for _, document := range users {
		if document.Exists() {
			userByID[document.Ref.ID] = document.Data()
		}
	}
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
		user := userByID[id]
		vehicle, toda := vehicleByID[text(data, "vehicleId")], todaByID[text(data, "todaId")]
		if text(user, "role") != "driver" || !booleanDefault(user, true, "isActive") ||
			!booleanDefault(vehicle, false, "isVerified") || !vehicleCanServe(vehicle, requiredSeats) ||
			!booleanDefault(toda, false, "isActive") || text(data, "licenseNumber") == "" || !futureTime(data["licenseExpiry"], now) {
			continue
		}
		candidate := byID[id]
		candidate.TodaID = text(data, "todaId")
		candidate.ServicePriority = dispatchServicePriority(candidate.TodaID, request)
		if candidate.ServicePriority >= 3 {
			continue
		}
		candidate.DailyAwards, candidate.ReliabilityScore, candidate.QualityScore = dispatchRankingMetrics(data, now)
		result = append(result, candidate)
	}
	return result, nil
}

func dispatchRankingMetrics(driver map[string]any, now time.Time) (int, float64, float64) {
	stats := jsonMap(driver["dispatchStats"])
	manila := time.FixedZone("Asia/Manila", 8*60*60)
	dailyAwards := 0
	if text(stats, "dailyAwardDate") == now.In(manila).Format("2006-01-02") {
		dailyAwards = max(0, integer(stats, "dailyAwardCount"))
	}
	completed := max(0, integer(stats, "completedAssignments"))
	driverFaults := max(0, integer(stats, "driverFaultCancellations"))
	reliability := float64(9+completed) / float64(10+completed+driverFaults)
	ratingCount := max(0, integer(driver, "ratingCount"))
	rating := number(driver, "rating")
	if rating < 0 {
		rating = 0
	} else if rating > 5 {
		rating = 5
	}
	if ratingCount == 0 {
		rating = 4.5
	}
	quality := (4.5*10 + rating*float64(ratingCount)) / float64(10+ratingCount)
	return dailyAwards, math.Round(reliability*1e6) / 1e6, math.Round(quality*1e6) / 1e6
}

func nextDriverDispatchStats(driver map[string]any, outcome string, now time.Time) map[string]any {
	stats := jsonMap(driver["dispatchStats"])
	manila := time.FixedZone("Asia/Manila", 8*60*60)
	date := now.In(manila).Format("2006-01-02")
	dailyAwards := 0
	if text(stats, "dailyAwardDate") == date {
		dailyAwards = max(0, integer(stats, "dailyAwardCount"))
	}
	result := map[string]any{
		"dailyAwardDate":           date,
		"dailyAwardCount":          dailyAwards,
		"assignmentCount":          max(0, integer(stats, "assignmentCount")),
		"completedAssignments":     max(0, integer(stats, "completedAssignments")),
		"cancellationCount":        max(0, integer(stats, "cancellationCount")),
		"driverFaultCancellations": max(0, integer(stats, "driverFaultCancellations")),
	}
	switch outcome {
	case "assigned":
		result["dailyAwardCount"] = result["dailyAwardCount"].(int) + 1
		result["assignmentCount"] = result["assignmentCount"].(int) + 1
	case "completed":
		result["completedAssignments"] = result["completedAssignments"].(int) + 1
	case "cancelled":
		result["cancellationCount"] = result["cancellationCount"].(int) + 1
	case "driver_fault_cancelled":
		result["cancellationCount"] = result["cancellationCount"].(int) + 1
		result["driverFaultCancellations"] = result["driverFaultCancellations"].(int) + 1
	}
	return result
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
		for _, previousDriverID := range stringSlice(bookingData["currentOfferDriverIds"]) {
			if previousDriverID == "" || contains(ids, previousDriverID) {
				continue
			}
			previousOffer := store.firestore.Collection("drivers").Doc(previousDriverID).Collection("bookingOffers").Doc(bookingID)
			tx.Set(previousOffer, map[string]any{"status": "superseded", "closedAt": now, "updatedAt": now}, firestore.MergeAll)
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
		"routeStops", "routeLegs", "dropoffCount", "activeStopIndex", "passengerNote",
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
