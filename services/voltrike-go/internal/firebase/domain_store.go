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
	command.PassengerNote = strings.TrimSpace(command.PassengerNote)
	if command.PassengerNote != "" {
		moderatedNote, moderationErr := store.ModerateChatText(ctx, command.PassengerNote)
		if moderationErr != nil {
			return app.BookingRecord{}, fmt.Errorf("moderate passenger note: %w", moderationErr)
		}
		if moderatedNote.Blocked {
			return app.BookingRecord{}, fmt.Errorf("%w: passenger note is blocked by the ride safety policy", app.ErrPrecondition)
		}
		command.PassengerNote = strings.TrimSpace(moderatedNote.DisplayText)
	}
	ref := store.firestore.Collection("bookings").Doc(command.BookingID)
	lockRef := store.firestore.Collection("activePassengerBookings").Doc(principal.UID)
	passengerRef := store.firestore.Collection("users").Doc(principal.UID)
	commandPayloadHash := createBookingPayloadHash(command)
	quoteReceiptRef := store.firestore.Collection("quote_receipts").Doc(fmt.Sprintf("%x", sha256.Sum256([]byte(command.QuoteToken))))
	result := app.BookingRecord{ID: command.BookingID}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snapshot, err := tx.Get(ref)
		if err == nil {
			data := snapshot.Data()
			if text(data, "passengerId", "passengerID") != principal.UID {
				return fmt.Errorf("%w: booking belongs to another user", app.ErrPrecondition)
			}
			if recordedHash := text(data, "createPayloadHash"); recordedHash != "" && recordedHash != commandPayloadHash {
				return fmt.Errorf("%w: bookingId was already used with a different payload", app.ErrPrecondition)
			}
			result.Data = data
			return nil
		}
		if !isNotFound(err) {
			return fmt.Errorf("read booking: %w", err)
		}
		passengerSnapshot, passengerErr := tx.Get(passengerRef)
		if passengerErr != nil && !isNotFound(passengerErr) {
			return fmt.Errorf("read passenger profile: %w", passengerErr)
		}
		passenger := map[string]any{}
		if passengerErr == nil && passengerSnapshot.Exists() {
			passenger = passengerSnapshot.Data()
		}
		if text(passenger, "role") != "passenger" || !booleanDefault(passenger, true, "isActive") {
			return fmt.Errorf("%w: an active passenger account is required", app.ErrPrecondition)
		}
		activeLock, lockErr := tx.Get(lockRef)
		if lockErr == nil && activeLock.Exists() && text(activeLock.Data(), "bookingId") != command.BookingID {
			return fmt.Errorf("%w: passenger already has an active booking", app.ErrPrecondition)
		}
		if lockErr != nil && !isNotFound(lockErr) {
			return fmt.Errorf("read active booking lock: %w", lockErr)
		}
		quoteReceipt, err := tx.Get(quoteReceiptRef)
		if err == nil && quoteReceipt.Exists() {
			return fmt.Errorf("%w: quote token has already been consumed", app.ErrPrecondition)
		}
		if err != nil && !isNotFound(err) {
			return fmt.Errorf("read quote receipt: %w", err)
		}
		now := time.Now().UTC()
		// Dispatch is retried by the scheduled maintenance worker. A one-minute
		// search window can expire before a nearby driver finishes coming online,
		// especially while GPS/App Check starts on a cold app launch. Keep a
		// short but practical retry window so a newly available driver can still
		// receive the passenger's pending request.
		searchExpiresAt := now.Add(5 * time.Minute)
		fareSnapshot := jsonMap(quote.FareSnapshot)
		fareBreakdown := jsonMap(quote.FareBreakdown)
		routeStops := make([]map[string]any, 0, len(command.RouteStops))
		for index, stop := range command.RouteStops {
			name, address := strings.TrimSpace(stop.Name), strings.TrimSpace(stop.Address)
			if index == 0 {
				if name == "" {
					name = strings.TrimSpace(command.PickupName)
				}
				if address == "" {
					address = strings.TrimSpace(command.PickupAddress)
				}
			} else if index == len(command.RouteStops)-1 {
				if name == "" {
					name = strings.TrimSpace(command.DestinationName)
				}
				if address == "" {
					address = strings.TrimSpace(command.DestinationAddress)
				}
			}
			routeStops = append(routeStops, map[string]any{
				"sequence": index, "type": stop.Type, "location": map[string]float64{"latitude": stop.Location.Latitude, "longitude": stop.Location.Longitude},
				"name": name, "address": address, "final": index == len(command.RouteStops)-1, "status": "pending",
			})
		}
		booking := map[string]any{
			"schemaVersion":              3,
			"bookingId":                  command.BookingID,
			"revision":                   1,
			"status":                     "pending",
			"passengerId":                principal.UID,
			"passengerName":              passengerDisplayName(passenger),
			"passengerPhone":             text(passenger, "phoneNumber", "phone"),
			"passengerPhotoUrl":          firstText(passenger, nil, "profileImage", "profilePhotoUrl"),
			"pickup":                     map[string]float64{"latitude": command.Pickup.Latitude, "longitude": command.Pickup.Longitude},
			"destination":                map[string]float64{"latitude": command.Destination.Latitude, "longitude": command.Destination.Longitude},
			"pickupName":                 strings.TrimSpace(command.PickupName),
			"destinationName":            strings.TrimSpace(command.DestinationName),
			"pickupAddress":              strings.TrimSpace(command.PickupAddress),
			"destinationAddress":         strings.TrimSpace(command.DestinationAddress),
			"routeStops":                 routeStops,
			"routeLegs":                  jsonMapSlice(quote.RouteLegs),
			"dropoffCount":               len(command.RouteStops) - 1,
			"activeStopIndex":            0,
			"passengerNote":              command.PassengerNote,
			"distanceMeters":             quote.DistanceMeters,
			"estimatedDuration":          quote.EstimatedDuration,
			"estimatedFare":              quote.EstimatedFare,
			"amountDue":                  quote.EstimatedFare,
			"additionalPassengers":       command.AdditionalPassengers,
			"baggageCount":               command.BaggageCount,
			"fareSnapshot":               fareSnapshot,
			"fareBreakdown":              fareBreakdown,
			"fareVersion":                quote.FareVersion,
			"isOutsideToda":              quote.IsOutsideToda,
			"coverage":                   jsonMap(quote.Coverage),
			"coverageClass":              quote.Coverage.CoverageClass,
			"primaryTodaIds":             quote.Coverage.PrimaryTodaIDs,
			"secondaryTodaIds":           quote.Coverage.SecondaryTodaIDs,
			"eligibleTodaIds":            quote.Coverage.EligibleTodaIDs,
			"allowAnyActiveToda":         quote.Coverage.AllowAnyActiveToda,
			"authoritativeRoutePolyline": quote.AuthoritativeRoutePolyline,
			"routePolicy":                jsonMap(quote.HighwayRouteAdvisory),
			"policyRevision":             quote.PolicyRevision,
			"quoteExpiresAt":             quote.ExpiresAt,
			"operationId":                command.OperationID,
			"createPayloadHash":          commandPayloadHash,
			"offerRound":                 0,
			"searchExpiresAt":            searchExpiresAt,
			"createdAt":                  now,
			"updatedAt":                  now,
		}
		tx.Set(ref, booking)
		tx.Set(lockRef, map[string]any{"bookingId": command.BookingID, "createdAt": now, "updatedAt": now})
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
				"payloadHash": commandPayloadHash,
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

func (store *Store) FindExistingBookingForCreate(ctx context.Context, principal app.Principal, command app.CreateBookingCommand) (app.BookingRecord, bool, error) {
	document, err := store.firestore.Collection("bookings").Doc(command.BookingID).Get(ctx)
	if err != nil {
		if isNotFound(err) {
			return app.BookingRecord{}, false, nil
		}
		return app.BookingRecord{}, false, fmt.Errorf("read existing booking create result: %w", err)
	}
	data := document.Data()
	if text(data, "passengerId", "passengerID") != principal.UID {
		return app.BookingRecord{}, false, fmt.Errorf("%w: booking belongs to another user", app.ErrPrecondition)
	}
	if recordedHash := text(data, "createPayloadHash"); recordedHash != "" && recordedHash != createBookingPayloadHash(command) {
		return app.BookingRecord{}, false, fmt.Errorf("%w: bookingId was already used with a different payload", app.ErrPrecondition)
	}
	return app.BookingRecord{ID: command.BookingID, Data: data}, true, nil
}

func createBookingPayloadHash(command app.CreateBookingCommand) string {
	payload, _ := json.Marshal(command)
	return fmt.Sprintf("%x", sha256.Sum256(payload))
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
	if owner != principal.UID && driver != principal.UID && !store.canAdminAccessToda(ctx, principal, text(data, "todaId", "driverTodaId", "ownerTodaId")) {
		return app.BookingRecord{}, fmt.Errorf("%w: booking is not visible to this user", app.ErrPrecondition)
	}
	return app.BookingRecord{ID: bookingID, Data: data}, nil
}

func (store *Store) ListAdminBookings(ctx context.Context, principal app.Principal, cursor, search string, pageSize int) (app.AdminPage, error) {
	actor, err := store.loadAdmin(ctx, principal)
	if err != nil {
		return app.AdminPage{}, err
	}
	query := store.firestore.Collection("bookings").Query
	if !actor.developer() {
		query = query.Where("todaId", "==", actor.TodaID)
	}
	query = query.OrderBy(firestore.DocumentID, firestore.Asc).Limit(pageSize)
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
	payload, _ := json.Marshal(command)
	payloadHash := fmt.Sprintf("%x", sha256.Sum256(payload))
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
			receiptData := receiptSnapshot.Data()
			if text(receiptData, "actorUid") != principal.UID {
				return fmt.Errorf("%w: commandId belongs to another user", app.ErrPrecondition)
			}
			if recordedHash := text(receiptData, "payloadHash"); recordedHash != "" && recordedHash != payloadHash {
				return fmt.Errorf("%w: commandId was already used with a different payload", app.ErrPrecondition)
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
		adminAllowed := false
		if owner != principal.UID && driver != principal.UID && command.Action != "accept" && command.Action != "decline" {
			adminSnapshot, adminErr := tx.Get(store.firestore.Collection("users").Doc(principal.UID))
			if adminErr == nil {
				if actor, actorErr := adminIdentityFromProfile(principal, adminSnapshot.Data()); actorErr == nil {
					adminAllowed = actor.canAccessToda(text(data, "todaId", "driverTodaId", "ownerTodaId"))
				}
			}
		}
		var acceptingDriverRef, acceptingOfferRef *firestore.DocumentRef
		var acceptingUser, acceptingDriver, acceptingVehicle, acceptingToda map[string]any
		if command.Action == "accept" || command.Action == "decline" {
			if owner == principal.UID {
				return fmt.Errorf("%w: an offered driver is required", app.ErrPrecondition)
			}
			acceptingDriverRef = store.firestore.Collection("drivers").Doc(principal.UID)
			acceptingOfferRef = acceptingDriverRef.Collection("bookingOffers").Doc(command.BookingID)
			userSnapshot, userErr := tx.Get(store.firestore.Collection("users").Doc(principal.UID))
			driverSnapshot, driverErr := tx.Get(acceptingDriverRef)
			offerSnapshot, offerErr := tx.Get(acceptingOfferRef)
			if userErr != nil || driverErr != nil || offerErr != nil {
				return fmt.Errorf("%w: an active booking offer is required", app.ErrPrecondition)
			}
			acceptingUser, acceptingDriver = userSnapshot.Data(), driverSnapshot.Data()
			offer := offerSnapshot.Data()
			if text(acceptingUser, "role") != "driver" || !booleanDefault(acceptingUser, true, "isActive") || text(acceptingDriver, "driverStatus") != "approved" || !booleanDefault(acceptingDriver, false, "isOnline") || !booleanDefault(acceptingDriver, false, "isAvailable") || text(acceptingDriver, "currentBookingId") != "" {
				return fmt.Errorf("%w: driver is not currently eligible", app.ErrPrecondition)
			}
			if text(offer, "status") != "offered" || integer(offer, "offerRound") != integer(data, "offerRound") || !futureTime(offer["expiresAt"], time.Now().UTC()) {
				return fmt.Errorf("%w: booking offer is no longer active", app.ErrPrecondition)
			}
			if command.Action == "accept" {
				vehicleID, todaID := text(acceptingDriver, "vehicleId"), text(acceptingDriver, "todaId")
				if vehicleID == "" || todaID == "" || !bookingAllowsToda(data, todaID) {
					return fmt.Errorf("%w: driver cannot serve this booking coverage", app.ErrPrecondition)
				}
				vehicleSnapshot, vehicleErr := tx.Get(store.firestore.Collection("vehicles").Doc(vehicleID))
				todaSnapshot, todaErr := tx.Get(store.firestore.Collection("todas").Doc(todaID))
				if vehicleErr != nil || todaErr != nil {
					return fmt.Errorf("%w: driver vehicle or TODA is unavailable", app.ErrPrecondition)
				}
				acceptingVehicle, acceptingToda = vehicleSnapshot.Data(), todaSnapshot.Data()
				if !booleanDefault(acceptingVehicle, false, "isVerified") || !vehicleCanServe(acceptingVehicle, integer(data, "additionalPassengers")+1) || !booleanDefault(acceptingToda, false, "isActive") || text(acceptingDriver, "licenseNumber") == "" || !futureTime(acceptingDriver["licenseExpiry"], time.Now().UTC()) {
					return fmt.Errorf("%w: driver vehicle, TODA, or license is not eligible", app.ErrPrecondition)
				}
			}
		} else if owner != principal.UID && driver != principal.UID && !adminAllowed {
			return fmt.Errorf("%w: booking is not owned by this user", app.ErrPrecondition)
		}
		if command.Action == "arrived" || command.Action == "start" || command.Action == "advanceStop" || command.Action == "payment" || command.Action == "complete" || command.Action == "receipt" {
			if driver != principal.UID {
				return fmt.Errorf("%w: only the assigned driver can perform this action", app.ErrPrecondition)
			}
		}
		current := text(data, "status")
		next := ""
		switch command.Action {
		case "accept":
			if current != "pending" {
				return fmt.Errorf("%w: booking is not pending", app.ErrPrecondition)
			}
			next = "driverAssigned"
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
		case "advanceStop":
			if current != "passengerOnBoard" {
				return fmt.Errorf("%w: booking is not travelling to a drop-off", app.ErrPrecondition)
			}
			stops := jsonMapSlice(data["routeStops"])
			activeStopIndex := integer(data, "activeStopIndex")
			if len(stops) < 3 || activeStopIndex < 1 || activeStopIndex >= len(stops)-1 {
				return fmt.Errorf("%w: booking has no intermediate drop-off to complete", app.ErrPrecondition)
			}
			if command.StopIndex != activeStopIndex {
				return fmt.Errorf("%w: drop-off sequence is stale", app.ErrPrecondition)
			}
			next = current
		case "payment":
			if current != "passengerOnBoard" && current != "paymentConfirmation" {
				return fmt.Errorf("%w: booking is not awaiting payment", app.ErrPrecondition)
			}
			if current == "passengerOnBoard" {
				stops := jsonMapSlice(data["routeStops"])
				if len(stops) > 2 && integer(data, "activeStopIndex") < len(stops)-1 {
					return fmt.Errorf("%w: intermediate drop-off must be completed first", app.ErrPrecondition)
				}
				next = "paymentConfirmation"
			} else {
				// The driver's single cash-confirmation action is the receipt.
				// It atomically records receipt and completes the ride so the UI
				// never asks for an impossible second confirmation.
				next = "completed"
			}
		case "complete":
			if current != "paymentConfirmation" {
				return fmt.Errorf("%w: booking is not awaiting completion", app.ErrPrecondition)
			}
			if _, confirmed := data["driverReceivedAt"]; !confirmed {
				return fmt.Errorf("%w: cash receipt must be confirmed before completion", app.ErrPrecondition)
			}
			next = "completed"
		case "cancel", "noShow":
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
		var activeLockRef *firestore.DocumentRef
		var terminalDriverRef *firestore.DocumentRef
		var terminalDriverData map[string]any
		if next == "completed" || next == "cancelled" {
			activeLockRef = store.firestore.Collection("activePassengerBookings").Doc(owner)
			if lockSnapshot, lockErr := tx.Get(activeLockRef); lockErr == nil {
				if text(lockSnapshot.Data(), "bookingId") != command.BookingID {
					activeLockRef = nil
				}
			} else if !isNotFound(lockErr) {
				return fmt.Errorf("read active booking lock: %w", lockErr)
			} else {
				activeLockRef = nil
			}
			if driver != "" {
				terminalDriverRef = store.firestore.Collection("drivers").Doc(driver)
				if driverSnapshot, driverErr := tx.Get(terminalDriverRef); driverErr != nil {
					terminalDriverRef = nil
				} else {
					terminalDriverData = driverSnapshot.Data()
				}
			}
		}
		now := time.Now().UTC()
		updates := map[string]any{"status": next, "revision": revision + 1, "updatedAt": now}
		if command.Action == "accept" {
			// Every driver in the current dispatch round watches only their own
			// bookingOffers collection. Closing the non-winning offer documents in
			// this transaction makes their cards disappear immediately instead of
			// leaving a stale Accept/Decline prompt for an already assigned ride.
			setCurrentBookingOfferStatus(tx, store, data, command.BookingID, "accepted_elsewhere", principal.UID, now)
			updates["currentOfferDriverIds"] = []string{}
			updates["nextDispatchAt"] = now
		}
		if next == "cancelled" {
			// Booking state and dispatched offers form one observable state change.
			// Without these writes, a passenger cancellation changes only the
			// booking document while driver listeners continue showing cached offers.
			setCurrentBookingOfferStatus(tx, store, data, command.BookingID, "cancelled", "", now)
			updates["currentOfferDriverIds"] = []string{}
			updates["nextDispatchAt"] = now
		}
		if command.Action == "start" {
			updates["activeStopIndex"] = 1
		}
		if command.Action == "advanceStop" {
			stops := jsonMapSlice(data["routeStops"])
			activeStopIndex := integer(data, "activeStopIndex")
			stops[activeStopIndex]["status"] = "completed"
			stops[activeStopIndex]["completedAt"] = now
			updates["routeStops"] = stops
			updates["activeStopIndex"] = activeStopIndex + 1
		}
		if command.Action == "payment" && current == "passengerOnBoard" {
			stops := jsonMapSlice(data["routeStops"])
			activeStopIndex := integer(data, "activeStopIndex")
			if activeStopIndex >= 0 && activeStopIndex < len(stops) {
				stops[activeStopIndex]["status"] = "completed"
				stops[activeStopIndex]["completedAt"] = now
				updates["routeStops"] = stops
			}
		}
		if command.Action == "payment" && current == "paymentConfirmation" {
			updates["driverReceivedAt"] = now
		}
		if driver != "" {
			updates["driverId"] = driver
		}
		if command.Action == "accept" {
			updates["driverName"] = personName(acceptingUser)
			updates["driverPhotoUrl"] = firstText(acceptingUser, acceptingDriver, "profileImage", "profilePhotoUrl")
			updates["driverRating"] = number(acceptingDriver, "rating")
			updates["vehicleNumber"] = firstText(acceptingVehicle, acceptingVehicle, "vehicleNumber", "model")
			updates["plateNumber"] = text(acceptingVehicle, "plateNumber")
			updates["todaId"] = text(acceptingDriver, "todaId")
			updates["driverTodaId"] = text(acceptingDriver, "todaId")
			updates["todaName"] = text(acceptingToda, "name")
			updates["commissionPercent"] = normalizedCommission(number(acceptingToda, "driverCommissionPercent"))
			updates["assignedAt"] = now
			tx.Set(acceptingDriverRef, map[string]any{
				"currentBookingId": command.BookingID,
				"isAvailable":      false,
				"dispatchStats":    nextDriverDispatchStats(acceptingDriver, "assigned", now),
				"updatedAt":        now,
			}, firestore.MergeAll)
			tx.Set(acceptingOfferRef, map[string]any{"status": "accepted", "acceptedAt": now, "updatedAt": now}, firestore.MergeAll)
		}
		if next == "completed" {
			settlement, settlementErr := settlementSnapshot(data, command.BookingID, now)
			if settlementErr != nil {
				return fmt.Errorf("%w: %v", app.ErrPrecondition, settlementErr)
			}
			updates["completedAt"] = now
			updates["settlementStatus"] = "settled"
			updates["settlementTimestamp"] = now
			updates["receiptNumber"] = settlement["receiptNumber"]
			updates["grossFare"] = settlement["grossFare"]
			updates["commissionPercent"] = settlement["commissionPercent"]
			updates["commissionAmount"] = settlement["commissionAmount"]
			updates["driverNetEarnings"] = settlement["driverNetEarnings"]
			tx.Set(store.firestore.Collection("settlements").Doc(command.BookingID), settlement, firestore.MergeAll)
		}
		if next == "cancelled" {
			updates["cancelledAt"] = now
			cancellationCode := command.ReasonCode
			if command.Action == "noShow" {
				if driver == principal.UID {
					cancellationCode = "passenger_no_show"
				} else {
					cancellationCode = "driver_no_show"
				}
			}
			updates["cancellationCode"] = cancellationCode
			updates["cancellationDetail"] = strings.TrimSpace(command.ReasonDetail)
			updates["cancelledBy"] = principal.UID
		}
		if command.Action == "dispute" {
			updates["settlementDispute"] = map[string]any{
				"reason":      strings.TrimSpace(command.ReasonDetail),
				"submittedBy": principal.UID,
				"submittedAt": now,
				"status":      "open",
			}
			tx.Set(store.firestore.Collection("settlements").Doc(command.BookingID), map[string]any{
				"adjustmentStatus": "disputed", "disputeReason": strings.TrimSpace(command.ReasonDetail),
				"disputedBy": principal.UID, "disputedAt": now, "updatedAt": now,
			}, firestore.MergeAll)
		}
		if command.Action == "receipt" {
			updates["driverReceiptAcknowledgedAt"] = now
			updates["driverReceiptAcknowledgedBy"] = principal.UID
			// Clear the assigned driver's durable receipt prompt. Delete the field
			// rather than storing null so a newly installed app cannot restore an
			// obsolete receipt from a cached/null-mapped driver record. Use the
			// booking's driver, not the acting principal, so an authorized admin
			// acknowledgement is also correct.
			if driver != "" {
				driverRef := store.firestore.Collection("drivers").Doc(driver)
				tx.Set(driverRef, map[string]any{"pendingReceiptBookingId": firestore.Delete, "updatedAt": now}, firestore.MergeAll)
			}
		}
		if command.Action == "decline" {
			updates["lastOfferDeclinedBy"] = principal.UID
			updates["lastOfferDeclinedAt"] = now
			remainingOfferDriverIDs := withoutString(stringSlice(data["currentOfferDriverIds"]), principal.UID)
			updates["currentOfferDriverIds"] = remainingOfferDriverIDs
			if len(remainingOfferDriverIDs) == 0 {
				// Let maintenance dispatch another eligible round promptly when the
				// final driver in this round declines.
				updates["nextDispatchAt"] = now
			}
			tx.Set(acceptingOfferRef, map[string]any{"status": "declined", "declinedAt": now, "updatedAt": now}, firestore.MergeAll)
		}
		if terminalDriverRef != nil {
			driverUpdates := map[string]any{
				"currentBookingId": nil,
				"isAvailable":      booleanDefault(terminalDriverData, false, "isOnline") && text(terminalDriverData, "driverStatus") == "approved",
				"updatedAt":        now,
			}
			switch next {
			case "completed":
				driverUpdates["dispatchStats"] = nextDriverDispatchStats(terminalDriverData, "completed", now)
				driverUpdates["pendingReceiptBookingId"] = command.BookingID
				driverUpdates["completedTrips"] = integer(terminalDriverData, "completedTrips") + 1
				driverUpdates["totalEarnings"] = number(terminalDriverData, "totalEarnings") + number(updates, "driverNetEarnings")
			case "cancelled":
				outcome := "cancelled"
				if principal.UID == driver || text(updates, "cancellationCode") == "driver_no_show" {
					outcome = "driver_fault_cancelled"
				}
				driverUpdates["dispatchStats"] = nextDriverDispatchStats(terminalDriverData, outcome, now)
			}
			tx.Set(terminalDriverRef, driverUpdates, firestore.MergeAll)
		}
		if activeLockRef != nil {
			tx.Delete(activeLockRef)
		}
		tx.Set(ref, updates, firestore.MergeAll)
		eventType := "booking." + next
		if command.Action == "decline" || command.Action == "dispute" || command.Action == "receipt" || command.Action == "advanceStop" || command.Action == "payment" && current == "paymentConfirmation" {
			eventType = "booking." + command.Action
		}
		eventRef := store.firestore.Collection("outbox").Doc(uuid.NewString())
		tx.Set(eventRef, map[string]any{
			"eventId":           eventRef.ID,
			"type":              eventType,
			"aggregateId":       command.BookingID,
			"aggregateRevision": revision + 1,
			"payload":           map[string]any{"bookingId": command.BookingID, "status": next, "actorId": principal.UID},
			"createdAt":         now,
			"consumers":         []string{"notifications"},
		})
		tx.Set(receiptRef, map[string]any{
			"actorUid":    principal.UID,
			"commandType": "booking." + command.Action,
			"payloadHash": payloadHash,
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
	passengerID := text(result.Data, "passengerId", "passengerID")
	driverID := text(result.Data, "driverId", "driverID")
	if command.Action == "accept" && passengerID != "" && driverID != "" {
		now := time.Now()
		if err := store.realtime.NewRef("driver_tracking_access/"+passengerID+"/"+driverID).Set(ctx, map[string]any{"bookingId": command.BookingID, "grantedAt": now.UnixMilli(), "expiresAt": now.Add(24 * time.Hour).UnixMilli()}); err != nil {
			return app.BookingRecord{}, fmt.Errorf("write tracking access projection: %w", err)
		}
	}
	if (text(result.Data, "status") == "completed" || text(result.Data, "status") == "cancelled") && passengerID != "" && driverID != "" {
		if err := store.realtime.NewRef("driver_tracking_access/" + passengerID + "/" + driverID).Delete(ctx); err != nil {
			return app.BookingRecord{}, fmt.Errorf("remove tracking access projection: %w", err)
		}
	}
	return result, nil
}

func setCurrentBookingOfferStatus(tx *firestore.Transaction, store *Store, booking map[string]any, bookingID, status, exceptDriverID string, now time.Time) {
	for _, driverID := range stringSlice(booking["currentOfferDriverIds"]) {
		if driverID == "" || driverID == exceptDriverID {
			continue
		}
		offerRef := store.firestore.Collection("drivers").Doc(driverID).Collection("bookingOffers").Doc(bookingID)
		tx.Set(offerRef, map[string]any{"status": status, "closedAt": now, "updatedAt": now}, firestore.MergeAll)
	}
}

func withoutString(values []string, excluded string) []string {
	result := make([]string, 0, len(values))
	for _, value := range values {
		if value != "" && value != excluded {
			result = append(result, value)
		}
	}
	return result
}

func settlementSnapshot(data map[string]any, bookingID string, now time.Time) (map[string]any, error) {
	grossFare := number(data, "amountDue", "estimatedFare")
	commissionPercent := number(data, "commissionPercent")
	if math.IsNaN(grossFare) || math.IsInf(grossFare, 0) || math.IsNaN(commissionPercent) || math.IsInf(commissionPercent, 0) || grossFare < 0 || grossFare > 1_000_000_000 || commissionPercent < 0 || commissionPercent > 30 {
		return nil, fmt.Errorf("invalid settlement amount or commission percentage")
	}
	grossCentavos := int64(math.Round(grossFare * 100))
	percentHundredths := int64(math.Round(commissionPercent * 100))
	commissionCentavos := int64(math.Round(float64(grossCentavos) * float64(percentHundredths) / 10000))
	driverNetCentavos := grossCentavos - commissionCentavos
	if commissionCentavos < 0 || driverNetCentavos < 0 || commissionCentavos+driverNetCentavos != grossCentavos {
		return nil, fmt.Errorf("settlement amounts do not balance")
	}
	receiptNumber := text(data, "receiptNumber")
	if receiptNumber == "" {
		cleanID := strings.Map(func(value rune) rune {
			if value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9' {
				return value
			}
			return -1
		}, bookingID)
		if len(cleanID) > 10 {
			cleanID = cleanID[:10]
		}
		receiptNumber = "VT-" + strings.ToUpper(cleanID)
	}
	return map[string]any{
		"bookingId":           bookingID,
		"passengerId":         text(data, "passengerId", "passengerID"),
		"driverId":            text(data, "driverId", "driverID"),
		"todaId":              text(data, "todaId", "driverTodaId"),
		"paymentMethod":       "cash",
		"amountDue":           float64(grossCentavos) / 100,
		"grossFare":           float64(grossCentavos) / 100,
		"commissionPercent":   float64(percentHundredths) / 100,
		"commissionAmount":    float64(commissionCentavos) / 100,
		"driverNetEarnings":   float64(driverNetCentavos) / 100,
		"currency":            "PHP",
		"status":              "settled",
		"receiptNumber":       receiptNumber,
		"policyRevision":      number(data, "policyRevision"),
		"settlementTimestamp": now,
		"updatedAt":           now,
	}, nil
}

func futureTime(value any, after time.Time) bool {
	switch typed := value.(type) {
	case time.Time:
		return typed.After(after)
	case *time.Time:
		return typed != nil && typed.After(after)
	case int64:
		return time.UnixMilli(typed).After(after)
	case float64:
		return time.UnixMilli(int64(typed)).After(after)
	case string:
		value := strings.TrimSpace(typed)
		if value == "" {
			return false
		}
		if parsed, err := time.Parse(time.RFC3339, value); err == nil {
			return parsed.After(after)
		}
		// Some legacy records came from the JavaScript client as a local ISO
		// datetime (for example, 2027-01-31T00:00:00.000) without an offset.
		// Firestore timestamp values are UTC, so retain that historical meaning.
		if parsed, err := time.Parse("2006-01-02T15:04:05.999999999", value); err == nil {
			return parsed.After(after)
		}
		// Licence dates entered by administrators are calendar dates.  Treat
		// them as valid through the end of that date, rather than midnight at
		// its beginning.  Older registrations persist this format as a string.
		if parsed, err := time.Parse("2006-01-02", value); err == nil {
			return parsed.AddDate(0, 0, 1).After(after)
		}
	default:
		return false
	}
	return false
}

func bookingAllowsToda(booking map[string]any, todaID string) bool {
	primary := stringSlice(booking["primaryTodaIds"])
	secondary := stringSlice(booking["secondaryTodaIds"])
	eligible := stringSlice(booking["eligibleTodaIds"])
	if len(primary) > 0 {
		return contains(primary, todaID) || contains(secondary, todaID) || booleanDefault(booking, false, "allowAnyActiveToda")
	}
	if booleanDefault(booking, false, "allowAnyActiveToda") || len(eligible) == 0 {
		return true
	}
	return contains(eligible, todaID)
}

func stringSlice(value any) []string {
	switch typed := value.(type) {
	case []string:
		return typed
	case []any:
		result := make([]string, 0, len(typed))
		for _, item := range typed {
			if text, ok := item.(string); ok && strings.TrimSpace(text) != "" {
				result = append(result, strings.TrimSpace(text))
			}
		}
		return result
	default:
		return nil
	}
}

func contains(values []string, expected string) bool {
	for _, value := range values {
		if value == expected {
			return true
		}
	}
	return false
}

func vehicleCanServe(vehicle map[string]any, requiredSeats int) bool {
	capacity := integer(vehicle, "capacity")
	if requiredSeats < 1 || requiredSeats > 4 || capacity < requiredSeats {
		return false
	}
	vehicleType := strings.ToLower(firstText(vehicle, vehicle, "vehicleType", "type", "model", "vehicleNumber"))
	vehicleType = strings.Map(func(value rune) rune {
		if value >= 'a' && value <= 'z' {
			return value
		}
		return -1
	}, vehicleType)
	return requiredSeats <= 2 || vehicleType == "electrictuktuk" || vehicleType == "etuktuk" || vehicleType == "electrictricycle"
}

func personName(profile map[string]any) string {
	parts := []string{text(profile, "firstName"), text(profile, "middleName"), text(profile, "lastName")}
	name := strings.TrimSpace(strings.Join(parts, " "))
	if name != "" {
		return strings.Join(strings.Fields(name), " ")
	}
	if email := text(profile, "email"); email != "" {
		return email
	}
	return "Driver"
}

func passengerDisplayName(profile map[string]any) string {
	if name := text(profile, "displayName", "fullName", "name", "passengerName"); name != "" {
		return name
	}
	name := personName(profile)
	if name == "Driver" {
		return "Passenger"
	}
	return name
}

func firstText(primary, secondary map[string]any, keys ...string) string {
	if value := text(primary, keys...); value != "" {
		return value
	}
	return text(secondary, keys...)
}

func normalizedCommission(value float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) || value < 0 || value > 30 {
		return 0
	}
	return math.Round(value*100) / 100
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
		updates := map[string]any{"heartbeatAt": now, "expiresAt": now.Add(45 * time.Second), "sampleSequence": int64(command.SampleSequence), "updatedAt": now}
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
	// Realtime Database is the fast spatial index, but dispatch eligibility is
	// deliberately checked again from Firestore. Keep those projections in sync
	// here so a driver that just went online can actually receive an offer.
	// TODA membership and busy state are server-owned; never accept either from
	// a location payload supplied by a phone.
	driverRef := store.firestore.Collection("drivers").Doc(principal.UID)
	driverSnapshot, err := driverRef.Get(ctx)
	if err != nil {
		return fmt.Errorf("%w: driver profile not found", app.ErrPrecondition)
	}
	driver := driverSnapshot.Data()
	todaID := text(driver, "todaId")
	available := command.Online && command.Available && text(driver, "currentBookingId") == ""
	if _, err = driverRef.Set(ctx, map[string]any{
		"isOnline":          command.Online,
		"isAvailable":       available,
		"currentLatitude":   command.Latitude,
		"currentLongitude":  command.Longitude,
		"locationUpdatedAt": now,
		"updatedAt":         now,
	}, firestore.MergeAll); err != nil {
		return fmt.Errorf("update driver dispatch availability: %w", err)
	}
	updates := map[string]any{
		"driverId":        principal.UID,
		"sessionId":       command.SessionID,
		"leaseGeneration": command.LeaseGeneration,
		"sampleSequence":  int64(command.SampleSequence),
		"latitude":        command.Latitude,
		"longitude":       command.Longitude,
		"accuracy":        command.Accuracy,
		"timestamp":       command.ObservedAt.UnixMilli(),
		"online":          command.Online,
		"available":       available,
		"todaId":          todaID,
		"receivedAt":      now.UnixMilli(),
	}
	cell := dispatchCell(command.Latitude, command.Longitude)
	var previousCell string
	_ = store.realtime.NewRef("dispatchDriverCells/"+principal.UID).Get(ctx, &previousCell)
	cellUpdates := map[string]any{
		"dispatchCells/" + cell + "/" + principal.UID:                updates,
		"dispatchDriverCells/" + principal.UID:                       cell,
		"driverPresence/" + principal.UID + "/" + command.SessionID:  updates,
		"driverLocations/" + principal.UID + "/" + command.SessionID: updates,
		"driver_locations/" + principal.UID:                          updates,
	}
	if previousCell != "" && previousCell != cell {
		cellUpdates["dispatchCells/"+previousCell+"/"+principal.UID] = nil
	}
	if !command.Online {
		cellUpdates["dispatchCells/"+cell+"/"+principal.UID] = nil
		if previousCell != "" {
			cellUpdates["dispatchCells/"+previousCell+"/"+principal.UID] = nil
		}
		cellUpdates["dispatchDriverCells/"+principal.UID] = nil
		cellUpdates["driverPresence/"+principal.UID+"/"+command.SessionID] = nil
	}
	if err := store.realtime.NewRef("").Update(ctx, cellUpdates); err != nil {
		return fmt.Errorf("write driver dispatch projection: %w", err)
	}
	_, err = ref.Update(ctx, []firestore.Update{
		{Path: "sampleSequence", Value: int64(command.SampleSequence)},
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

func jsonMapSlice(value any) []map[string]any {
	raw, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	var result []map[string]any
	if err := json.Unmarshal(raw, &result); err != nil {
		return nil
	}
	return result
}
