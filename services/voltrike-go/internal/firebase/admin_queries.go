package firebase

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/voltrike/voltrike-go/internal/app"
)

func (store *Store) adminList(ctx context.Context, actor adminIdentity, collectionName string, payload map[string]any) (map[string]any, error) {
	pageSize := integer(payload, "pageSize", "limit")
	if pageSize < 1 || pageSize > 100 {
		pageSize = 25
	}
	query := store.firestore.Collection(collectionName).OrderBy(firestore.DocumentID, firestore.Asc).Limit(201)
	documents, err := query.Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	cursor, search := text(payload, "cursor"), strings.ToLower(text(payload, "search"))
	items := make([]map[string]any, 0, pageSize)
	started := cursor == ""
	for _, document := range documents {
		if !started {
			if document.Ref.ID == cursor {
				started = true
			}
			continue
		}
		data := document.Data()
		todaID := text(data, "todaId", "ownerTodaId", "driverTodaId")
		if !actor.canAccessToda(todaID) {
			continue
		}
		if search != "" && !strings.Contains(strings.ToLower(document.Ref.ID+" "+text(data, "name", "driverName", "passengerName", "email", "status")), search) {
			continue
		}
		data["id"] = document.Ref.ID
		items = append(items, data)
		if len(items) == pageSize {
			break
		}
	}
	next := ""
	if len(items) == pageSize {
		next, _ = items[len(items)-1]["id"].(string)
	}
	return map[string]any{"items": items, "nextCursor": next}, nil
}

// adminListRatings hydrates immutable rating records with the current readable
// driver/passenger names. Older rating records were created before all booking
// name snapshots were enforced, so treating the stored name as the only source
// made otherwise valid feedback look anonymous in the TODA portal.
func (store *Store) adminListRatings(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	pageSize := integer(payload, "pageSize", "limit")
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}
	documents, err := store.firestore.Collection("ratings").Limit(500).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	driverDirectory, err := store.adminDriverDirectory(ctx, actor)
	if err != nil {
		return nil, err
	}
	profiles, err := store.adminUserProfiles(ctx)
	if err != nil {
		return nil, err
	}
	type ratingDocument struct {
		document *firestore.DocumentSnapshot
		created  time.Time
	}
	ratings := make([]ratingDocument, 0, len(documents))
	for _, document := range documents {
		ratings = append(ratings, ratingDocument{document: document, created: reportTimestamp(document.Data())})
	}
	sort.Slice(ratings, func(i, j int) bool { return ratings[i].created.After(ratings[j].created) })
	cursor := text(payload, "cursor")
	started := cursor == ""
	items := make([]map[string]any, 0, pageSize)
	for _, rating := range ratings {
		if !started {
			if rating.document.Ref.ID == cursor {
				started = true
			}
			continue
		}
		data := copyMap(rating.document.Data())
		driverID := text(data, "driverId", "driverID")
		driver := driverDirectory[driverID]
		todaID := text(data, "todaId", "driverTodaId")
		if todaID == "" {
			todaID = text(driver, "todaId", "ownerTodaId", "driverTodaId")
		}
		if !actor.canAccessToda(todaID) {
			continue
		}
		if name := text(data, "driverName"); name == "" {
			data["driverName"] = preferredAdminDriverName(driver, driverID)
		}
		passengerID := text(data, "passengerId", "passengerID")
		if name := text(data, "passengerName"); name == "" {
			data["passengerName"] = passengerDisplayName(profiles[passengerID])
		}
		data["id"], data["driverId"], data["passengerId"], data["todaId"] = rating.document.Ref.ID, driverID, passengerID, todaID
		items = append(items, data)
		if len(items) == pageSize {
			break
		}
	}
	next := ""
	if len(items) == pageSize {
		next = text(items[len(items)-1], "id")
	}
	return map[string]any{"items": items, "nextCursor": next}, nil
}

func (store *Store) getTodaCommission(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	if actor.TodaID == "" {
		return map[string]any{"percent": 0, "todaId": ""}, nil
	}
	doc, err := store.firestore.Collection("todas").Doc(actor.TodaID).Get(ctx)
	if err != nil {
		return nil, err
	}
	return map[string]any{"percent": normalizedCommission(number(doc.Data(), "driverCommissionPercent")), "todaId": actor.TodaID, "updatedAt": doc.Data()["commissionUpdatedAt"]}, nil
}

func (store *Store) setTodaCommission(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	todaID := actor.TodaID
	if actor.developer() && text(payload, "todaId") != "" {
		todaID = text(payload, "todaId")
	}
	percent := number(payload, "percent")
	if todaID == "" || percent < 0 || percent > 30 {
		return nil, fmt.Errorf("%w: valid TODA and commission are required", app.ErrInvalidArgument)
	}
	now := time.Now().UTC()
	_, err := store.firestore.Collection("todas").Doc(todaID).Set(ctx, map[string]any{"driverCommissionPercent": mathRound(percent, 2), "commissionUpdatedBy": actor.UID, "commissionUpdatedAt": now, "updatedAt": now}, firestore.MergeAll)
	return map[string]any{"percent": mathRound(percent, 2), "todaId": todaID, "updatedAt": now}, err
}

func (store *Store) commissionReport(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	location, err := time.LoadLocation("Asia/Manila")
	if err != nil {
		return nil, err
	}
	start, err := time.ParseInLocation("2006-01-02", text(payload, "startDate"), location)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid start date", app.ErrInvalidArgument)
	}
	end, err := time.ParseInLocation("2006-01-02", text(payload, "endDate"), location)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid end date", app.ErrInvalidArgument)
	}
	end = end.AddDate(0, 0, 1)
	driverDirectory, err := store.adminDriverDirectory(ctx, actor)
	if err != nil {
		return nil, err
	}
	query := store.firestore.Collection("settlements").Limit(500)
	documents, err := query.Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	type reportEntry struct {
		item map[string]any
		at   time.Time
	}
	entries := make([]reportEntry, 0)
	driverTotals := make(map[string]map[string]any, len(driverDirectory))
	for driverID, driver := range driverDirectory {
		driverTotals[driverID] = map[string]any{
			"driverId": driverID, "driverName": preferredAdminDriverName(driver, driverID),
			"completedRides": 0, "grossFare": 0.0, "commissionAmount": 0.0, "commissionDue": 0.0, "commissionSettled": 0.0, "driverNetEarnings": 0.0,
		}
	}
	var gross, commission, commissionDue, commissionSettled, net float64
	completed, pending, settled, disputed := 0, 0, 0, 0
	for _, document := range documents {
		data := document.Data()
		driverID := text(data, "driverId")
		settlementTodaID := text(data, "todaId", "driverTodaId")
		if settlementTodaID == "" {
			settlementTodaID = text(driverDirectory[driverID], "todaId", "ownerTodaId", "driverTodaId")
		}
		if !actor.canAccessToda(settlementTodaID) {
			continue
		}
		occurredAt := reportTimestamp(data)
		if occurredAt.IsZero() || occurredAt.Before(start) || !occurredAt.Before(end) {
			continue
		}
		settlementStatus := text(data, "status", "settlementStatus")
		adjustmentStatus := text(data, "adjustmentStatus")
		if settlementStatus == "awaiting_confirmation" || settlementStatus == "pending" {
			pending++
		}
		if settlementStatus == "settled" {
			settled++
			completed++
		}
		if adjustmentStatus == "disputed" || settlementStatus == "disputed" {
			disputed++
		}
		if settlementStatus != "settled" {
			continue
		}
		driverTotal, knownDriver := driverTotals[driverID]
		if !knownDriver {
			driverTotal = map[string]any{
				"driverId": driverID, "driverName": preferredAdminDriverName(data, driverID),
				"completedRides": 0, "grossFare": 0.0, "commissionAmount": 0.0, "commissionDue": 0.0, "commissionSettled": 0.0, "driverNetEarnings": 0.0,
			}
			driverTotals[driverID] = driverTotal
		}
		driverName := text(driverTotal, "driverName")
		if driverName == "" {
			driverName = preferredAdminDriverName(data, driverID)
			driverTotal["driverName"] = driverName
		}
		grossFare := number(data, "grossFare", "amountDue")
		commissionAmount := number(data, "commissionAmount")
		driverNetEarnings := number(data, "driverNetEarnings")
		commissionSettlementStatus := text(data, "commissionSettlementStatus")
		if commissionSettlementStatus != "settled" {
			commissionSettlementStatus = "due"
		}
		driverTotal["completedRides"] = integer(driverTotal, "completedRides") + 1
		driverTotal["grossFare"] = number(driverTotal, "grossFare") + grossFare
		driverTotal["commissionAmount"] = number(driverTotal, "commissionAmount") + commissionAmount
		if commissionSettlementStatus == "settled" {
			driverTotal["commissionSettled"] = number(driverTotal, "commissionSettled") + commissionAmount
			commissionSettled += commissionAmount
		} else {
			driverTotal["commissionDue"] = number(driverTotal, "commissionDue") + commissionAmount
			commissionDue += commissionAmount
		}
		driverTotal["driverNetEarnings"] = number(driverTotal, "driverNetEarnings") + driverNetEarnings
		item := map[string]any{
			"bookingId":                  text(data, "bookingId"),
			"receiptNumber":              text(data, "receiptNumber"),
			"driverId":                   driverID,
			"driverName":                 driverName,
			"completedAt":                occurredAt,
			"grossFare":                  grossFare,
			"commissionPercent":          number(data, "commissionPercent"),
			"commissionAmount":           commissionAmount,
			"commissionSettlementStatus": commissionSettlementStatus,
			"commissionSettledAt":        data["commissionSettledAt"],
			"driverNetEarnings":          driverNetEarnings,
			"settlementStatus":           settlementStatus,
			"adjustmentStatus":           adjustmentStatus,
			"disputeReason":              text(data, "disputeReason"),
		}
		entries = append(entries, reportEntry{item: item, at: occurredAt})
		gross += grossFare
		commission += commissionAmount
		net += driverNetEarnings
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].at.After(entries[j].at) })
	items := make([]map[string]any, 0, len(entries))
	for _, entry := range entries {
		items = append(items, entry.item)
	}
	driverSummaries := make([]map[string]any, 0, len(driverTotals))
	for _, driver := range driverTotals {
		driverSummaries = append(driverSummaries, driver)
	}
	sort.Slice(driverSummaries, func(i, j int) bool {
		return strings.ToLower(text(driverSummaries[i], "driverName")) < strings.ToLower(text(driverSummaries[j], "driverName"))
	})
	result := map[string]any{"summary": map[string]any{"grossFare": gross, "commissionAmount": commission, "commissionDue": commissionDue, "commissionSettled": commissionSettled, "driverNetEarnings": net, "completedRides": completed, "pendingSettlements": pending, "settledSettlements": settled, "disputedSettlements": disputed}, "items": items, "driverSummaries": driverSummaries, "nextCursor": ""}
	if booleanDefault(payload, false, "summaryOnly") {
		result["items"] = []map[string]any{}
		result["driverSummaries"] = []map[string]any{}
	}
	return result, nil
}

// settleDriverCommission records a TODA payout separately from the passenger
// cash settlement. It never changes a completed ride's fare, receipt, or the
// immutable commission rate captured at acceptance.
func (store *Store) settleDriverCommission(ctx context.Context, actor adminIdentity, commandID string, payload map[string]any) (map[string]any, error) {
	driverID := text(payload, "driverId")
	if driverID == "" {
		return nil, fmt.Errorf("%w: driverId is required", app.ErrInvalidArgument)
	}
	location, err := time.LoadLocation("Asia/Manila")
	if err != nil {
		return nil, err
	}
	start, err := time.ParseInLocation("2006-01-02", text(payload, "startDate"), location)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid start date", app.ErrInvalidArgument)
	}
	end, err := time.ParseInLocation("2006-01-02", text(payload, "endDate"), location)
	if err != nil {
		return nil, fmt.Errorf("%w: invalid end date", app.ErrInvalidArgument)
	}
	if end.Before(start) {
		return nil, fmt.Errorf("%w: end date must not be before start date", app.ErrInvalidArgument)
	}
	end = end.AddDate(0, 0, 1)
	driverDirectory, err := store.adminDriverDirectory(ctx, actor)
	if err != nil {
		return nil, err
	}
	driver, exists := driverDirectory[driverID]
	if !exists {
		return nil, fmt.Errorf("%w: driver is outside administrator scope", app.ErrPrecondition)
	}
	payoutID := "commission_" + strings.ReplaceAll(commandID, "-", "")
	payoutRef := store.firestore.Collection("commissionPayouts").Doc(payoutID)
	result := map[string]any{}
	err = store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		if existing, existingErr := tx.Get(payoutRef); existingErr == nil && existing.Exists() {
			data := existing.Data()
			if text(data, "settledBy") != actor.UID || text(data, "driverId") != driverID {
				return fmt.Errorf("%w: commandId belongs to another payout", app.ErrPrecondition)
			}
			result = map[string]any{"payoutId": payoutID, "settledBookingCount": integer(data, "settledBookingCount"), "commissionAmount": number(data, "commissionAmount")}
			return nil
		} else if existingErr != nil && !isNotFound(existingErr) {
			return existingErr
		}

		query := store.firestore.Collection("settlements").Where("driverId", "==", driverID).Where("status", "==", "settled").Limit(401)
		documents, queryErr := tx.Documents(query).GetAll()
		if queryErr != nil {
			return queryErr
		}
		if len(documents) > 400 {
			return fmt.Errorf("%w: payout range exceeds 400 settlements; choose a shorter date range", app.ErrPrecondition)
		}
		now := time.Now().UTC()
		bookingIDs := make([]string, 0, len(documents))
		commissionAmount := 0.0
		for _, document := range documents {
			data := document.Data()
			if text(data, "commissionSettlementStatus") == "settled" {
				continue
			}
			settlementTodaID := text(data, "todaId", "driverTodaId")
			if settlementTodaID == "" {
				settlementTodaID = text(driver, "todaId", "ownerTodaId", "driverTodaId")
			}
			if !actor.canAccessToda(settlementTodaID) {
				continue
			}
			occurredAt := reportTimestamp(data)
			if occurredAt.IsZero() || occurredAt.Before(start) || !occurredAt.Before(end) {
				continue
			}
			amount := number(data, "commissionAmount")
			if amount <= 0 {
				continue
			}
			tx.Set(document.Ref, map[string]any{
				"commissionSettlementStatus": "settled", "commissionSettledAt": now,
				"commissionSettledBy": actor.UID, "commissionPayoutId": payoutID, "updatedAt": now,
			}, firestore.MergeAll)
			bookingIDs = append(bookingIDs, text(data, "bookingId", "bookingID", "id"))
			commissionAmount += amount
		}
		if len(bookingIDs) == 0 {
			return fmt.Errorf("%w: no unpaid commission is available for this driver and date range", app.ErrPrecondition)
		}
		payout := map[string]any{
			"payoutId": payoutID, "commandId": commandID, "driverId": driverID,
			"driverName": preferredAdminDriverName(driver, driverID),
			"todaId":     text(driver, "todaId", "ownerTodaId", "driverTodaId"),
			"startDate":  text(payload, "startDate"), "endDate": text(payload, "endDate"),
			"commissionAmount": commissionAmount, "settledBookingCount": len(bookingIDs),
			"bookingIds": bookingIDs, "status": "settled", "settledBy": actor.UID,
			"settledAt": now, "createdAt": now, "updatedAt": now,
		}
		tx.Create(payoutRef, payout)
		result = map[string]any{"payoutId": payoutID, "settledBookingCount": len(bookingIDs), "commissionAmount": commissionAmount}
		return nil
	})
	return result, err
}

func reportTimestamp(data map[string]any) time.Time {
	for _, key := range []string{"settlementTimestamp", "completedAt", "driverReceivedAt", "createdAt"} {
		switch value := data[key].(type) {
		case time.Time:
			return value
		case *time.Time:
			if value != nil {
				return *value
			}
		}
	}
	return time.Time{}
}

func (store *Store) adminMetrics(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	collections := []string{"drivers", "bookings", "reports", "safetyIncidents", "zoneRequests"}
	result := map[string]any{"drivers": 0, "bookings": 0, "reports": 0, "safetyIncidents": 0, "zones": 0, "trips": 0}
	for _, name := range collections {
		documents, err := store.firestore.Collection(name).Limit(2000).Documents(ctx).GetAll()
		if err != nil {
			return nil, err
		}
		for _, document := range documents {
			data := document.Data()
			if !actor.canAccessToda(text(data, "todaId", "ownerTodaId", "driverTodaId")) {
				continue
			}
			switch name {
			case "drivers":
				result["drivers"] = integer(result, "drivers") + 1
			case "bookings":
				result["bookings"] = integer(result, "bookings") + 1
				if text(data, "status") == "completed" {
					result["trips"] = integer(result, "trips") + 1
				}
			case "reports":
				if adminMetricStatusOpen(data, "open") {
					result["reports"] = integer(result, "reports") + 1
				}
			case "safetyIncidents":
				if adminMetricStatusOpen(data, "open", "reported", "acknowledged", "responding") {
					result["safetyIncidents"] = integer(result, "safetyIncidents") + 1
				}
			case "zoneRequests":
				if adminMetricStatusOpen(data, "pending") {
					result["zones"] = integer(result, "zones") + 1
				}
			}
		}
	}
	result["scope"] = "platform"
	if !actor.developer() {
		result["scope"] = actor.TodaID
	}
	return result, nil
}

func adminMetricStatusOpen(data map[string]any, openStatuses ...string) bool {
	status := strings.ToLower(text(data, "responseStatus", "status"))
	if status == "" {
		return true // Legacy records without a terminal status still require review.
	}
	for _, openStatus := range openStatuses {
		if status == openStatus {
			return true
		}
	}
	return false
}

func (store *Store) adminLiveDrivers(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	drivers, err := store.firestore.Collection("drivers").Where("isOnline", "==", true).Limit(200).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	profiles, vehicles, err := store.adminDriverLookups(ctx)
	if err != nil {
		return nil, err
	}
	locations := map[string]map[string]any{}
	_ = store.realtime.NewRef("driver_locations").Get(ctx, &locations)
	items := make([]map[string]any, 0)
	for _, driver := range drivers {
		data := driver.Data()
		if text(data, "driverStatus", "status") != "approved" {
			continue
		}
		location, ok := freshAdminDriverLocation(locations[driver.Ref.ID], time.Now().UTC())
		if !ok {
			continue
		}
		item := hydrateAdminDriver(data, driver.Ref.ID, profiles[driver.Ref.ID], vehicles[driver.Ref.ID])
		if !actor.canAccessToda(text(item, "todaId", "ownerTodaId", "driverTodaId")) {
			continue
		}
		item["id"], item["driverId"], item["location"] = driver.Ref.ID, driver.Ref.ID, location
		items = append(items, item)
	}
	return map[string]any{"items": items}, nil
}

func freshAdminDriverLocation(location map[string]any, now time.Time) (map[string]any, bool) {
	latitude, longitude := number(location, "latitude", "lat"), number(location, "longitude", "lng", "lon")
	if latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 || (latitude == 0 && longitude == 0) {
		return nil, false
	}
	timestamp := number(location, "timestamp", "updatedAt", "lastUpdated")
	if timestamp > 0 && timestamp < 100000000000 { // legacy RTDB clients reported Unix seconds.
		timestamp *= 1000
	}
	if timestamp <= 0 || now.Sub(time.UnixMilli(int64(timestamp))) > 5*time.Minute {
		return nil, false
	}
	result := copyMap(location)
	result["latitude"], result["longitude"], result["timestamp"] = latitude, longitude, timestamp
	return result, true
}

// adminListDrivers returns a presentation-safe driver record. V2 deliberately
// keeps account identity, driver eligibility, and vehicle information in their
// respective collections; legacy admin screens expect those values together.
func (store *Store) adminListDrivers(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	pageSize := integer(payload, "pageSize", "limit")
	if pageSize < 1 || pageSize > 100 {
		pageSize = 25
	}
	documents, err := store.firestore.Collection("drivers").OrderBy(firestore.DocumentID, firestore.Asc).Limit(201).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	profiles, vehicles, err := store.adminDriverLookups(ctx)
	if err != nil {
		return nil, err
	}
	cursor, search := text(payload, "cursor"), strings.ToLower(text(payload, "search"))
	started := cursor == ""
	items := make([]map[string]any, 0, pageSize)
	for _, document := range documents {
		if !started {
			if document.Ref.ID == cursor {
				started = true
			}
			continue
		}
		data := document.Data()
		item := hydrateAdminDriver(data, document.Ref.ID, profiles[document.Ref.ID], vehicles[document.Ref.ID])
		if !actor.canAccessToda(text(item, "todaId", "ownerTodaId", "driverTodaId")) {
			continue
		}
		if search != "" && !strings.Contains(strings.ToLower(document.Ref.ID+" "+text(item, "name", "driverName", "email", "todaId", "driverStatus")), search) {
			continue
		}
		item["id"] = document.Ref.ID
		items = append(items, item)
		if len(items) == pageSize {
			break
		}
	}
	next := ""
	if len(items) == pageSize {
		next = text(items[len(items)-1], "id")
	}
	return map[string]any{"items": items, "nextCursor": next}, nil
}

func (store *Store) adminDriverLookups(ctx context.Context) (map[string]map[string]any, map[string]map[string]any, error) {
	allProfiles, err := store.adminUserProfiles(ctx)
	if err != nil {
		return nil, nil, err
	}
	profiles := make(map[string]map[string]any, len(allProfiles))
	for id, data := range allProfiles {
		if text(data, "role") == "driver" || text(data, "driverId", "uid") != "" {
			profiles[id] = data
		}
	}
	vehicleDocuments, err := store.firestore.Collection("vehicles").Limit(2000).Documents(ctx).GetAll()
	if err != nil {
		return nil, nil, err
	}
	vehicles := make(map[string]map[string]any, len(vehicleDocuments))
	for _, document := range vehicleDocuments {
		data := copyMap(document.Data())
		data["id"] = document.Ref.ID
		if driverID := text(data, "driverId", "uid"); driverID != "" {
			vehicles[driverID] = data
		}
	}
	return profiles, vehicles, nil
}

func (store *Store) adminUserProfiles(ctx context.Context) (map[string]map[string]any, error) {
	userDocuments, err := store.firestore.Collection("users").Limit(2000).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	profiles := make(map[string]map[string]any, len(userDocuments))
	for _, document := range userDocuments {
		profiles[document.Ref.ID] = document.Data()
	}
	return profiles, nil
}

// adminDriverDirectory is the canonical presentation lookup for TODA-facing
// reports. It includes all registered drivers in scope, even if they have no
// settlements in the currently selected date range.
func (store *Store) adminDriverDirectory(ctx context.Context, actor adminIdentity) (map[string]map[string]any, error) {
	documents, err := store.firestore.Collection("drivers").Limit(2000).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	profiles, vehicles, err := store.adminDriverLookups(ctx)
	if err != nil {
		return nil, err
	}
	directory := make(map[string]map[string]any, len(documents))
	for _, document := range documents {
		item := hydrateAdminDriver(document.Data(), document.Ref.ID, profiles[document.Ref.ID], vehicles[document.Ref.ID])
		if !actor.canAccessToda(text(item, "todaId", "ownerTodaId", "driverTodaId")) {
			continue
		}
		item["id"] = document.Ref.ID
		directory[document.Ref.ID] = item
	}
	return directory, nil
}

func hydrateAdminDriver(driver map[string]any, uid string, profile, storedVehicle map[string]any) map[string]any {
	item := copyMap(driver)
	legacyApplicant, _ := driver["applicant"].(map[string]any)
	legacyVehicle, _ := driver["vehicle"].(map[string]any)
	applicant := map[string]any{
		"firstName":   firstAdminText(legacyApplicant, driver, profile, "firstName", "givenName"),
		"middleName":  firstAdminText(legacyApplicant, driver, profile, "middleName"),
		"lastName":    firstAdminText(legacyApplicant, driver, profile, "lastName", "familyName", "surname"),
		"email":       firstAdminText(legacyApplicant, driver, profile, "email"),
		"phoneNumber": firstAdminText(legacyApplicant, driver, profile, "phoneNumber", "phone"),
		"dateOfBirth": firstAdminText(legacyApplicant, driver, profile, "dateOfBirth", "birthDate"),
	}
	if photo := firstAdminText(legacyApplicant, driver, profile, "profileImage", "profilePhotoUrl"); photo != "" {
		applicant["profileImage"] = photo
	}
	vehicle := copyMap(storedVehicle)
	for _, key := range []string{"id", "vehicleNumber", "plateNumber", "model", "color", "capacity", "isVerified"} {
		if _, exists := vehicle[key]; !exists {
			if value, ok := legacyVehicle[key]; ok {
				vehicle[key] = value
			}
		}
	}
	if len(vehicle) == 0 {
		vehicle = nil
	}
	name := firstAdminText(driver, profile, nil, "name", "driverName", "displayName", "fullName")
	if name == "" {
		name = personName(applicant)
	}
	item["uid"], item["driverId"], item["applicant"], item["name"], item["driverName"] = uid, uid, applicant, name, name
	if text(item, "todaId", "ownerTodaId", "driverTodaId") == "" && text(profile, "todaId", "driverTodaId") != "" {
		item["todaId"] = text(profile, "todaId", "driverTodaId")
	}
	if vehicle != nil {
		item["vehicle"] = vehicle
		if text(item, "vehicleId") == "" {
			item["vehicleId"] = text(vehicle, "id")
		}
	}
	return item
}

func preferredAdminDriverName(data map[string]any, driverID string) string {
	if name := firstAdminText(data, nil, nil, "driverName", "name", "displayName", "fullName"); name != "" {
		return name
	}
	if applicant, ok := data["applicant"].(map[string]any); ok {
		if name := personName(applicant); name != "Driver" {
			return name
		}
	}
	if driverID != "" {
		if len(driverID) > 8 {
			driverID = driverID[len(driverID)-8:]
		}
		return "Driver " + driverID
	}
	return "Registered driver"
}

func firstAdminText(first, second, third map[string]any, keys ...string) string {
	for _, source := range []map[string]any{first, second, third} {
		if value := text(source, keys...); value != "" {
			return value
		}
	}
	return ""
}

func (store *Store) adminListTodas(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	todas, err := store.firestore.Collection("todas").Limit(500).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	applications, _ := store.firestore.Collection("todaApplications").Limit(500).Documents(ctx).GetAll()
	applicationByID := map[string]map[string]any{}
	for _, application := range applications {
		applicationByID[application.Ref.ID] = application.Data()
	}
	items := make([]map[string]any, 0, len(todas))
	for _, document := range todas {
		if !actor.canAccessToda(document.Ref.ID) {
			continue
		}
		data := copyMap(document.Data())
		for key, value := range applicationByID[document.Ref.ID] {
			data[key] = value
		}
		data["id"] = document.Ref.ID
		items = append(items, data)
	}
	sort.Slice(items, func(i, j int) bool {
		return strings.ToLower(text(items[i], "name")) < strings.ToLower(text(items[j], "name"))
	})
	return map[string]any{"items": items}, nil
}

func (store *Store) adminListZones(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	documents, err := store.firestore.Collection("zoneRequests").Limit(500).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	requestedToda := text(payload, "todaId")
	items := []map[string]any{}
	for _, document := range documents {
		data := document.Data()
		todaID := text(data, "todaId")
		if requestedToda != "" && todaID != requestedToda || !actor.canAccessToda(todaID) {
			continue
		}
		data["id"] = document.Ref.ID
		items = append(items, data)
	}
	return map[string]any{"items": items}, nil
}

func (store *Store) adminListRestrictions(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	documents, err := store.firestore.Collection("routeRestrictions").Limit(200).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	items := []map[string]any{}
	for _, document := range documents {
		data := document.Data()
		data["id"] = document.Ref.ID
		items = append(items, data)
	}
	return map[string]any{"items": items}, nil
}

func (store *Store) adminGetFare(ctx context.Context, _ adminIdentity) (map[string]any, error) {
	doc, err := store.firestore.Collection("settings").Doc("fare_config").Get(ctx)
	if isNotFound(err) {
		return map[string]any{"fare": map[string]any{"baseFare": 20, "includedMeters": 1000, "distanceStepMeters": 500, "distanceStepPrice": 5, "additionalPassengerFee": 40, "baggageFee": 20, "outsideTodaSurcharge": 20, "additionalDropoffFee": 10}}, nil
	}
	if err != nil {
		return nil, err
	}
	return map[string]any{"fare": doc.Data()}, nil
}

func (store *Store) cancelBookingForSafety(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	incident, err := store.firestore.Collection("safetyIncidents").Doc(text(payload, "incidentId")).Get(ctx)
	if err != nil || !actor.canAccessToda(text(incident.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: incident unavailable", app.ErrPrecondition)
	}
	bookingID := text(incident.Data(), "bookingId")
	bookingRef := store.firestore.Collection("bookings").Doc(bookingID)
	now := time.Now().UTC()
	_, err = bookingRef.Set(ctx, map[string]any{"status": "cancelled", "cancelledBy": actor.UID, "cancellationCode": "safety_admin", "cancelledAt": now, "updatedAt": now}, firestore.MergeAll)
	return map[string]any{"cancelled": err == nil}, err
}

func (store *Store) updateSafetyResponse(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	ref := store.firestore.Collection("safetyIncidents").Doc(text(payload, "incidentId"))
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: incident unavailable", app.ErrPrecondition)
	}
	action := text(payload, "action")
	statuses := map[string]string{"acknowledge": "acknowledged", "responding": "responding", "resolve": "resolved"}
	status, ok := statuses[action]
	if !ok {
		return nil, fmt.Errorf("%w: invalid safety action", app.ErrInvalidArgument)
	}
	now := time.Now().UTC()
	updates := map[string]any{"responseStatus": status, "responseNote": truncate(text(payload, "note"), 1000), "responseUpdatedBy": actor.UID, "responseUpdatedAt": now, "updatedAt": now}
	if status == "resolved" {
		updates["status"], updates["resolvedAt"] = "resolved", now
	}
	_, err = ref.Set(ctx, updates, firestore.MergeAll)
	return map[string]any{"responseStatus": status}, err
}

func (store *Store) adminListViolations(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	return store.adminList(ctx, actor, "driverViolations", payload)
}
func (store *Store) adminGetViolation(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	doc, err := store.firestore.Collection("driverViolations").Doc(text(payload, "violationId")).Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "ownerTodaId")) {
		return nil, fmt.Errorf("%w: violation unavailable", app.ErrPrecondition)
	}
	data := doc.Data()
	data["id"], data["violationId"] = doc.Ref.ID, doc.Ref.ID
	return map[string]any{"item": data}, nil
}
func (store *Store) adminUpdateViolation(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	ref := store.firestore.Collection("driverViolations").Doc(text(payload, "violationId"))
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "ownerTodaId")) {
		return nil, fmt.Errorf("%w: violation unavailable", app.ErrPrecondition)
	}
	action := text(payload, "action")
	next := map[string]string{"acknowledge": "acknowledged", "respond": "responding", "resolve": "resolved", "dismiss": "dismissed"}[action]
	if next == "" {
		return nil, fmt.Errorf("%w: invalid violation action", app.ErrInvalidArgument)
	}
	now := time.Now().UTC()
	_, err = ref.Set(ctx, map[string]any{"status": next, "response": map[string]any{"status": next, "lastAction": action, "lastActionBy": actor.UID, "lastActionRole": actor.Role, "lastActionAt": now, "note": truncate(text(payload, "note"), 1000)}, "updatedAt": now}, firestore.MergeAll)
	return map[string]any{"violationId": ref.ID, "status": next}, err
}
