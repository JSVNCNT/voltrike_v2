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
	query := store.firestore.Collection("settlements").Where("settlementTimestamp", ">=", start).Where("settlementTimestamp", "<", end).OrderBy("settlementTimestamp", firestore.Desc).Limit(500)
	documents, err := query.Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	items := make([]map[string]any, 0)
	var gross, commission, net float64
	for _, document := range documents {
		data := document.Data()
		if !actor.canAccessToda(text(data, "todaId")) {
			continue
		}
		data["id"] = document.Ref.ID
		items = append(items, data)
		gross += number(data, "grossFare")
		commission += number(data, "commissionAmount")
		net += number(data, "driverNetEarnings")
	}
	result := map[string]any{"summary": map[string]any{"grossFare": gross, "commissionAmount": commission, "driverNetEarnings": net, "tripCount": len(items)}, "items": items, "nextCursor": ""}
	if booleanDefault(payload, false, "summaryOnly") {
		result["items"] = []map[string]any{}
	}
	return result, nil
}

func (store *Store) adminMetrics(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	collections := []string{"users", "drivers", "todas", "bookings", "reports", "safetyIncidents", "driverViolations"}
	result := map[string]any{}
	for _, name := range collections {
		documents, err := store.firestore.Collection(name).Limit(2000).Documents(ctx).GetAll()
		if err != nil {
			return nil, err
		}
		count := 0
		for _, document := range documents {
			if actor.canAccessToda(text(document.Data(), "todaId", "ownerTodaId", "driverTodaId")) {
				count++
			}
		}
		result[name] = count
	}
	result["activeDrivers"] = result["drivers"]
	result["openReports"] = result["reports"]
	result["openSafetyIncidents"] = result["safetyIncidents"]
	return result, nil
}

func (store *Store) adminLiveDrivers(ctx context.Context, actor adminIdentity) (map[string]any, error) {
	drivers, err := store.firestore.Collection("drivers").Where("isOnline", "==", true).Limit(200).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	locations := map[string]map[string]any{}
	_ = store.realtime.NewRef("driver_locations").Get(ctx, &locations)
	items := make([]map[string]any, 0)
	for _, driver := range drivers {
		data := driver.Data()
		if !actor.canAccessToda(text(data, "todaId")) {
			continue
		}
		item := copyMap(data)
		item["id"], item["driverId"], item["location"] = driver.Ref.ID, driver.Ref.ID, locations[driver.Ref.ID]
		items = append(items, item)
	}
	return map[string]any{"items": items}, nil
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
