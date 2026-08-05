package firebase

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
)

func (store *Store) CreateBooking(ctx context.Context, principal app.Principal, command app.CreateBookingCommand, quote app.Quote) (app.BookingRecord, error) {
	if !(core.Coordinate{Latitude: command.Pickup.Latitude, Longitude: command.Pickup.Longitude}).Valid() {
		return app.BookingRecord{}, fmt.Errorf("%w: pickup is invalid", app.ErrInvalidArgument)
	}
	ref := store.firestore.Collection("bookings").Doc(command.BookingID)
	quoteReceiptRef := store.firestore.Collection("quote_receipts").Doc(fmt.Sprintf("%x", sha256.Sum256([]byte(command.QuoteToken))))
	result := app.BookingRecord{ID: command.BookingID}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err == nil {
			data := snapshot.Data()
			if text(data, "passengerId", "passengerID") != principal.UID {
				return fmt.Errorf("%w: booking belongs to another user", app.ErrPrecondition)
			}
			result.Data = data
			return nil
		}
		if !isNotFound(err) {
			return fmt.Errorf("read booking: %w", err)
		}
		quoteReceipt, err := tx.Get(quoteReceiptRef)
		if err == nil && quoteReceipt.Exists() {
			return fmt.Errorf("%w: quote token has already been consumed", app.ErrPrecondition)
		}
		if err != nil && !isNotFound(err) {
			return fmt.Errorf("read quote receipt: %w", err)
		}
		now := time.Now().UTC()
		fareSnapshot := jsonMap(quote.FareSnapshot)
		fareBreakdown := jsonMap(quote.FareBreakdown)
		booking := map[string]any{
			"schemaVersion":              2,
			"bookingId":                  command.BookingID,
			"revision":                   1,
			"status":                     "pending",
			"passengerId":                principal.UID,
			"pickup":                     map[string]float64{"latitude": command.Pickup.Latitude, "longitude": command.Pickup.Longitude},
			"destination":                map[string]float64{"latitude": command.Destination.Latitude, "longitude": command.Destination.Longitude},
			"pickupAddress":              strings.TrimSpace(command.PickupAddress),
			"destinationAddress":         strings.TrimSpace(command.DestinationAddress),
			"distanceMeters":             quote.DistanceMeters,
			"estimatedDuration":          quote.EstimatedDuration,
			"estimatedFare":              quote.EstimatedFare,
			"fareSnapshot":               fareSnapshot,
			"fareBreakdown":              fareBreakdown,
			"fareVersion":                quote.FareVersion,
			"isOutsideToda":              quote.IsOutsideToda,
			"coverage":                   jsonMap(quote.Coverage),
			"authoritativeRoutePolyline": quote.AuthoritativeRoutePolyline,
			"routePolicy":                jsonMap(quote.HighwayRouteAdvisory),
			"policyRevision":             quote.PolicyRevision,
			"quoteExpiresAt":             quote.ExpiresAt,
			"operationId":                command.OperationID,
			"createdAt":                  now,
			"updatedAt":                  now,
		}
		tx.Set(ref, booking)
		tx.Set(quoteReceiptRef, map[string]any{
			"bookingId":  command.BookingID,
			"actorUid":   principal.UID,
			"consumedAt": now,
			"expiresAt":  quote.ExpiresAt,
		})
		eventRef := store.firestore.Collection("outbox").Doc(uuid.NewString())
		tx.Set(eventRef, map[string]any{
			"eventId":           eventRef.ID,
			"type":              "booking.created",
			"aggregateId":       command.BookingID,
			"aggregateRevision": 1,
			"payload":           map[string]any{"bookingId": command.BookingID, "passengerId": principal.UID},
			"createdAt":         now,
			"consumers":         []string{"notifications", "dispatch"},
		})
		if command.OperationID != "" {
			receipt := store.firestore.Collection("command_receipts").Doc(command.OperationID)
			tx.Set(receipt, map[string]any{
				"actorUid":    principal.UID,
				"commandType": "booking.create",
				"payloadHash": fmt.Sprintf("%x", sha256.Sum256([]byte(command.BookingID+"|"+principal.UID+"|"+command.QuoteToken))),
				"result":      map[string]any{"bookingId": command.BookingID},
				"createdAt":   now,
				"expiresAt":   now.Add(24 * time.Hour),
			})
		}
		result.Data = booking
		return nil
	})
	if err != nil {
		return app.BookingRecord{}, err
	}
	return result, nil
}

func (store *Store) GetBooking(ctx context.Context, principal app.Principal, bookingID string) (app.BookingRecord, error) {
	doc, err := store.firestore.Collection("bookings").Doc(bookingID).Get(ctx)
	if err != nil {
		if isNotFound(err) {
			return app.BookingRecord{}, fmt.Errorf("%w: booking not found", app.ErrPrecondition)
		}
		return app.BookingRecord{}, fmt.Errorf("read booking: %w", err)
	}
	data := doc.Data()
	owner := text(data, "passengerId", "passengerID")
	driver := text(data, "driverId", "driverID")
	if owner != principal.UID && driver != principal.UID && !adminPrincipal(principal) {
		return app.BookingRecord{}, fmt.Errorf("%w: booking is not visible to this user", app.ErrPrecondition)
	}
	return app.BookingRecord{ID: bookingID, Data: data}, nil
}

func (store *Store) ListAdminBookings(ctx context.Context, principal app.Principal, cursor, search string, pageSize int) (app.AdminPage, error) {
	if !adminPrincipal(principal) {
		return app.AdminPage{}, fmt.Errorf("%w: administrator access is required", app.ErrPrecondition)
	}
	query := store.firestore.Collection("bookings").OrderBy(firestore.DocumentID, firestore.Asc).Limit(pageSize)
	if strings.TrimSpace(cursor) != "" {
		query = query.StartAfter(strings.TrimSpace(cursor))
	}
	documents, err := query.Documents(ctx).GetAll()
	if err != nil {
		return app.AdminPage{}, fmt.Errorf("list bookings: %w", err)
	}
	items := make([]map[string]any, 0, len(documents))
	needle := strings.ToLower(strings.TrimSpace(search))
	for _, document := range documents {
		data := document.Data()
		if needle != "" {
			candidate := strings.ToLower(strings.Join([]string{
				document.Ref.ID,
				text(data, "passengerId", "passengerID"),
				text(data, "driverId", "driverID"),
				text(data, "status"),
			}, " "))
			if !strings.Contains(candidate, needle) {
				continue
			}
		}
		data["id"] = document.Ref.ID
		items = append(items, data)
	}
	result := app.AdminPage{Items: items}
	if len(documents) == pageSize {
		result.NextCursor = documents[len(documents)-1].Ref.ID
	}
	return result, nil
}

func (store *Store) TransitionBooking(ctx context.Context, principal app.Principal, command app.TransitionBookingCommand) (app.BookingRecord, error) {
	ref := store.firestore.Collection("bookings").Doc(command.BookingID)
	result := app.BookingRecord{ID: command.BookingID}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err != nil {
			return fmt.Errorf("%w: booking not found", app.ErrPrecondition)
		}
		data := snapshot.Data()
		receiptRef := store.firestore.Collection("command_receipts").Doc(command.CommandID)
		receiptSnapshot, receiptErr := tx.Get(receiptRef)
		if receiptErr == nil && receiptSnapshot.Exists() {
			if text(receiptSnapshot.Data(), "actorUid") != principal.UID {
				return fmt.Errorf("%w: commandId belongs to another user", app.ErrPrecondition)
			}
			result.Data = data
			return nil
		}
		if receiptErr != nil && !isNotFound(receiptErr) {
			return fmt.Errorf("read command receipt: %w", receiptErr)
		}
		revision := int(number(data, "revision"))
		if revision != command.ExpectedRevision {
			return fmt.Errorf("%w: expected revision %d but found %d", app.ErrPrecondition, command.ExpectedRevision, revision)
		}
		owner := text(data, "passengerId", "passengerID")
		driver := text(data, "driverId", "driverID")
		if owner != principal.UID && driver != principal.UID && !adminPrincipal(principal) {
			return fmt.Errorf("%w: booking is not owned by this user", app.ErrPrecondition)
		}
		current := text(data, "status")
		next := ""
		switch command.Action {
		case "accept":
			if current != "pending" {
				return fmt.Errorf("%w: booking is not pending", app.ErrPrecondition)
			}
			next = "driverAssigned"
			if command.DriverID != "" && command.DriverID != principal.UID && !adminPrincipal(principal) {
				return fmt.Errorf("%w: driverId does not match caller", app.ErrPrecondition)
			}
			driver = principal.UID
		case "arrived":
			if current != "driverAssigned" {
				return fmt.Errorf("%w: booking is not assigned", app.ErrPrecondition)
			}
			next = "driverArriving"
		case "start":
			if current != "driverArriving" {
				return fmt.Errorf("%w: booking is not ready to start", app.ErrPrecondition)
			}
			next = "passengerOnBoard"
		case "payment":
			if current != "passengerOnBoard" {
				return fmt.Errorf("%w: booking is not awaiting payment", app.ErrPrecondition)
			}
			next = "paymentConfirmation"
		case "complete":
			if current != "paymentConfirmation" {
				return fmt.Errorf("%w: booking is not awaiting completion", app.ErrPrecondition)
			}
			next = "completed"
		case "cancel":
			if current != "pending" && current != "driverAssigned" && current != "driverArriving" {
				return fmt.Errorf("%w: booking cannot be cancelled in its current state", app.ErrPrecondition)
			}
			next = "cancelled"
		case "decline":
			if current != "pending" {
				return fmt.Errorf("%w: booking offer cannot be declined in its current state", app.ErrPrecondition)
			}
			next = current
		case "dispute":
			if current != "paymentConfirmation" && current != "completed" {
				return fmt.Errorf("%w: settlement cannot be disputed in its current state", app.ErrPrecondition)
			}
			next = current
		case "receipt":
			if current != "paymentConfirmation" && current != "completed" {
				return fmt.Errorf("%w: receipt cannot be acknowledged in its current state", app.ErrPrecondition)
			}
			next = current
		}
		now := time.Now().UTC()
		updates := map[string]any{"status": next, "revision": revision + 1, "updatedAt": now}
		if driver != "" {
			updates["driverId"] = driver
		}
		if next == "completed" {
			updates["completedAt"] = now
		}
		if next == "cancelled" {
			updates["cancelledAt"] = now
			updates["cancellationCode"] = command.ReasonCode
			updates["cancelledBy"] = principal.UID
		}
		if command.Action == "dispute" {
			updates["settlementDispute"] = map[string]any{
				"reason":      strings.TrimSpace(command.ReasonDetail),
				"submittedBy": principal.UID,
				"submittedAt": now,
				"status":      "open",
			}
		}
		if command.Action == "receipt" {
			updates["driverReceiptAcknowledgedAt"] = now
			updates["driverReceiptAcknowledgedBy"] = principal.UID
		}
		if command.Action == "decline" {
			updates["lastOfferDeclinedBy"] = principal.UID
			updates["lastOfferDeclinedAt"] = now
		}
		tx.Set(ref, updates, firestore.MergeAll)
		eventRef := store.firestore.Collection("outbox").Doc(uuid.NewString())
		tx.Set(eventRef, map[string]any{
			"eventId":           eventRef.ID,
			"type":              "booking." + next,
			"aggregateId":       command.BookingID,
			"aggregateRevision": revision + 1,
			"payload":           map[string]any{"bookingId": command.BookingID, "status": next, "actorId": principal.UID},
			"createdAt":         now,
			"consumers":         []string{"notifications"},
		})
		tx.Set(receiptRef, map[string]any{
			"actorUid":    principal.UID,
			"commandType": "booking." + command.Action,
			"result":      map[string]any{"bookingId": command.BookingID, "status": next, "revision": revision + 1},
			"createdAt":   now,
			"expiresAt":   now.Add(24 * time.Hour),
		})
		for key, value := range updates {
			data[key] = value
		}
		result.Data = data
		return nil
	})
	if err != nil {
		return app.BookingRecord{}, err
	}
	return result, nil
}

func (store *Store) CreateDriverSession(ctx context.Context, principal app.Principal, command app.CreateDriverSessionCommand) (app.DriverSessionRecord, error) {
	ref := store.firestore.Collection("driver_sessions").Doc(command.SessionID)
	profileRef := store.firestore.Collection("driver_profiles").Doc(principal.UID)
	result := app.DriverSessionRecord{ID: command.SessionID}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		profile, err := tx.Get(profileRef)
		if err != nil && !isNotFound(err) {
			return err
		}
		if err == nil && !command.Takeover {
			active := text(profile.Data(), "activeSessionId")
			if active != "" && active != command.SessionID {
				return fmt.Errorf("%w: another driver session is active", app.ErrPrecondition)
			}
		}
		now := time.Now().UTC()
		data := map[string]any{
			"schemaVersion":   2,
			"sessionId":       command.SessionID,
			"driverId":        principal.UID,
			"deviceId":        command.DeviceID,
			"platform":        command.Platform,
			"appVersion":      command.AppVersion,
			"leaseGeneration": 1,
			"sampleSequence":  0,
			"status":          "active",
			"heartbeatAt":     now,
			"expiresAt":       now.Add(45 * time.Second),
			"createdAt":       now,
			"updatedAt":       now,
		}
		tx.Set(ref, data)
		tx.Set(profileRef, map[string]any{"activeSessionId": command.SessionID, "activeSessionChangedAt": now}, firestore.MergeAll)
		result.Data = data
		return nil
	})
	if err != nil {
		return app.DriverSessionRecord{}, err
	}
	return result, nil
}

func (store *Store) HeartbeatDriverSession(ctx context.Context, principal app.Principal, command app.DriverHeartbeatCommand) (app.DriverSessionRecord, error) {
	ref := store.firestore.Collection("driver_sessions").Doc(command.SessionID)
	result := app.DriverSessionRecord{ID: command.SessionID}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err != nil {
			return fmt.Errorf("%w: driver session not found", app.ErrPrecondition)
		}
		data := snapshot.Data()
		if text(data, "driverId") != principal.UID || int64(number(data, "leaseGeneration")) != command.LeaseGeneration {
			return fmt.Errorf("%w: stale driver session", app.ErrPrecondition)
		}
		if uint64(number(data, "sampleSequence")) >= command.SampleSequence {
			result.Data = data
			return nil
		}
		now := time.Now().UTC()
		updates := map[string]any{"heartbeatAt": now, "expiresAt": now.Add(45 * time.Second), "sampleSequence": command.SampleSequence, "updatedAt": now}
		tx.Set(ref, updates, firestore.MergeAll)
		for key, value := range updates {
			data[key] = value
		}
		result.Data = data
		return nil
	})
	return result, err
}

func (store *Store) UpdateDriverLocation(ctx context.Context, principal app.Principal, command app.DriverLocationCommand) error {
	ref := store.firestore.Collection("driver_sessions").Doc(command.SessionID)
	snapshot, err := ref.Get(ctx)
	if err != nil {
		return fmt.Errorf("%w: driver session not found", app.ErrPrecondition)
	}
	data := snapshot.Data()
	if text(data, "driverId") != principal.UID || int64(number(data, "leaseGeneration")) != command.LeaseGeneration {
		return fmt.Errorf("%w: stale driver session", app.ErrPrecondition)
	}
	if uint64(number(data, "sampleSequence")) >= command.SampleSequence {
		return nil
	}
	now := time.Now().UTC()
	if command.ObservedAt.IsZero() {
		command.ObservedAt = now
	}
	updates := map[string]any{
		"driverId":        principal.UID,
		"sessionId":       command.SessionID,
		"leaseGeneration": command.LeaseGeneration,
		"sampleSequence":  command.SampleSequence,
		"latitude":        command.Latitude,
		"longitude":       command.Longitude,
		"accuracy":        command.Accuracy,
		"timestamp":       command.ObservedAt.UnixMilli(),
		"online":          command.Online,
		"available":       command.Available,
		"todaId":          command.TodaID,
		"receivedAt":      now.UnixMilli(),
	}
	if err := store.realtime.NewRef("driverLocations/"+principal.UID+"/"+command.SessionID).Set(ctx, updates); err != nil {
		return fmt.Errorf("write driver location: %w", err)
	}
	cell := dispatchCell(command.Latitude, command.Longitude)
	cellUpdates := map[string]any{
		"dispatchCells/" + cell + "/" + principal.UID:               updates,
		"dispatchDriverCells/" + principal.UID:                      cell,
		"driverPresence/" + principal.UID + "/" + command.SessionID: updates,
	}
	if !command.Online {
		cellUpdates["dispatchCells/"+cell+"/"+principal.UID] = nil
	}
	if err := store.realtime.NewRef("").Update(ctx, cellUpdates); err != nil {
		return fmt.Errorf("write driver dispatch projection: %w", err)
	}
	_, err = ref.Update(ctx, []firestore.Update{
		{Path: "sampleSequence", Value: command.SampleSequence},
		{Path: "heartbeatAt", Value: now},
		{Path: "expiresAt", Value: now.Add(45 * time.Second)},
		{Path: "updatedAt", Value: now},
	})
	return err
}

func dispatchCell(latitude, longitude float64) string {
	return fmt.Sprintf("%d:%d", int(math.Floor((latitude+90)/0.05)), int(math.Floor((longitude+180)/0.05)))
}

func jsonMap(value any) map[string]any {
	raw, err := json.Marshal(value)
	if err != nil {
		return map[string]any{}
	}
	var result map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		return map[string]any{}
	}
	return result
}

func adminPrincipal(principal app.Principal) bool {
	role, _ := principal.Claims["role"].(string)
	return role == "admin" || role == "developer" || principal.Claims["admin"] == true
}
