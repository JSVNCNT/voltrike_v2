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
	start, err := time.Parse("2006-01-02", text(payload, "startDate"))
	if err != nil {
		return nil, fmt.Errorf("%w: invalid start date", app.ErrInvalidArgument)
	}
	end, err := time.Parse("2006-01-02", text(payload, "endDate"))
	if err != nil {
		return nil, fmt.Errorf("%w: invalid end date", app.ErrInvalidArgument)
	}
	end = end.AddDate(0, 0, 1)
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
	var gross, commission, net float64
	completed, pending, settled, disputed := 0, 0, 0, 0
	for _, document := range documents {
		data := document.Data()
		if !actor.canAccessToda(text(data, "todaId")) {
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
		item := map[string]any{
			"bookingId":         text(data, "bookingId"),
			"receiptNumber":     text(data, "receiptNumber"),
			"driverId":          text(data, "driverId"),
			"driverName":        text(data, "driverName"),
			"completedAt":       occurredAt,
			"grossFare":         number(data, "grossFare", "amountDue"),
			"commissionPercent": number(data, "commissionPercent"),
			"commissionAmount":  number(data, "commissionAmount"),
			"driverNetEarnings": number(data, "driverNetEarnings"),
			"settlementStatus":  settlementStatus,
			"adjustmentStatus":  adjustmentStatus,
			"disputeReason":     text(data, "disputeReason"),
		}
		entries = append(entries, reportEntry{item: item, at: occurredAt})
		gross += number(data, "grossFare")
		commission += number(data, "commissionAmount")
		net += number(data, "driverNetEarnings")
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].at.After(entries[j].at) })
	items := make([]map[string]any, 0, len(entries))
	for _, entry := range entries {
		items = append(items, entry.item)
	}
	result := map[string]any{"summary": map[string]any{"grossFare": gross, "commissionAmount": commission, "driverNetEarnings": net, "completedRides": completed, "pendingSettlements": pending, "settledSettlements": settled, "disputedSettlements": disputed}, "items": items, "nextCursor": ""}
	if booleanDefault(payload, false, "summaryOnly") {
		result["items"] = []map[string]any{}
	}
	return result, nil
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
	collections := []string{"users", "drivers", "todas", "bookings", "reports", "safetyIncidents", "driverViolations", "zoneRequests"}
	result := map[string]any{}
	completedTrips := 0
	for _, name := range collections {
		documents, err := store.firestore.Collection(name).Limit(2000).Documents(ctx).GetAll()
		if err != nil {
			return nil, err
		}
		count := 0
		for _, document := range documents {
			if actor.canAccessToda(text(document.Data(), "todaId", "ownerTodaId", "driverTodaId")) {
				count++
				if name == "bookings" && text(document.Data(), "status") == "completed" {
					completedTrips++
				}
			}
		}
		result[name] = count
	}
	result["activeDrivers"] = result["drivers"]
	result["trips"] = completedTrips
	result["zones"] = result["zoneRequests"]
	result["openReports"] = result["reports"]
	result["openSafetyIncidents"] = result["safetyIncidents"]
	return result, nil
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
		if !actor.canAccessToda(text(data, "todaId", "ownerTodaId", "driverTodaId")) {
			continue
		}
		if text(data, "driverStatus", "status") != "approved" {
			continue
		}
		location, ok := freshAdminDriverLocation(locations[driver.Ref.ID], time.Now().UTC())
		if !ok {
			continue
		}
		item := hydrateAdminDriver(data, driver.Ref.ID, profiles[driver.Ref.ID], vehicles[driver.Ref.ID])
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
		if !actor.canAccessToda(text(data, "todaId", "ownerTodaId", "driverTodaId")) {
			continue
		}
		item := hydrateAdminDriver(data, document.Ref.ID, profiles[document.Ref.ID], vehicles[document.Ref.ID])
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
	userDocuments, err := store.firestore.Collection("users").Limit(2000).Documents(ctx).GetAll()
	if err != nil {
		return nil, nil, err
	}
	profiles := make(map[string]map[string]any, len(userDocuments))
	for _, document := range userDocuments {
		data := document.Data()
		if text(data, "role") == "driver" || text(data, "driverId", "uid") != "" {
			profiles[document.Ref.ID] = data
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
		return map[string]any{"fare": map[string]any{"baseFare": 20, "includedMeters": 1000, "distanceStepMeters": 500, "distanceStepPrice": 5, "additionalPassengerFee": 40, "baggageFee": 20, "outsideTodaSurcharge": 20}}, nil
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
