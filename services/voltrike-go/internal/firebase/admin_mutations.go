package firebase

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/auth"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/core"
)

func (store *Store) setDriverStatus(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	uid, next := text(payload, "uid"), text(payload, "status")
	if uid == "" || !contains([]string{"pending", "approved", "declined", "suspended"}, next) {
		return nil, fmt.Errorf("%w: valid driver and status are required", app.ErrInvalidArgument)
	}
	ref := store.firestore.Collection("drivers").Doc(uid)
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: driver is outside administrator scope", app.ErrPrecondition)
	}
	updates := map[string]any{"driverStatus": next, "isAvailable": false, "reviewedBy": actor.UID, "reviewedAt": time.Now().UTC(), "updatedAt": time.Now().UTC()}
	if numberValue := text(payload, "licenseNumber"); numberValue != "" {
		updates["licenseNumber"] = numberValue
	}
	if rawExpiry := text(payload, "licenseExpiry"); rawExpiry != "" {
		if parsed, parseErr := time.Parse(time.RFC3339, rawExpiry); parseErr == nil {
			updates["licenseExpiry"] = parsed
		} else if parsed, parseErr = time.Parse("2006-01-02", rawExpiry); parseErr == nil {
			updates["licenseExpiry"] = parsed
		} else {
			return nil, fmt.Errorf("%w: license expiry is invalid", app.ErrInvalidArgument)
		}
	}
	batch := store.firestore.Batch()
	batch.Set(ref, updates, firestore.MergeAll)
	batch.Set(store.firestore.Collection("users").Doc(uid), map[string]any{"isActive": next == "approved", "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	_, err = batch.Commit(ctx)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) setVehicleVerification(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	driverID := text(payload, "driverId")
	driver, err := store.firestore.Collection("drivers").Doc(driverID).Get(ctx)
	if err != nil || !actor.canAccessToda(text(driver.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: driver is outside administrator scope", app.ErrPrecondition)
	}
	vehicleID := text(driver.Data(), "vehicleId")
	if vehicleID == "" {
		vehicleID = driverID
	}
	_, err = store.firestore.Collection("vehicles").Doc(vehicleID).Set(ctx, map[string]any{"isVerified": booleanDefault(payload, false, "isVerified"), "verifiedBy": actor.UID, "verifiedAt": time.Now().UTC(), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) setUserStatus(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	uid := text(payload, "uid")
	user, err := store.firestore.Collection("users").Doc(uid).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: user not found", app.ErrPrecondition)
	}
	if !actor.developer() && text(user.Data(), "todaId") != actor.TodaID {
		return nil, fmt.Errorf("%w: user is outside administrator scope", app.ErrPrecondition)
	}
	isActive := booleanDefault(payload, false, "isActive")
	_, err = user.Ref.Set(ctx, map[string]any{"isActive": isActive, "statusUpdatedBy": actor.UID, "sourceReportId": text(payload, "sourceReportId"), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	if err == nil {
		_, err = store.auth.UpdateUser(ctx, uid, (&auth.UserToUpdate{}).Disabled(!isActive))
	}
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) resolveReport(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	ref := store.firestore.Collection("reports").Doc(text(payload, "reportId"))
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: report is outside administrator scope", app.ErrPrecondition)
	}
	status := text(payload, "status")
	if status == "" {
		status = "resolved"
	}
	_, err = ref.Set(ctx, map[string]any{"status": status, "resolutionAction": text(payload, "action"), "resolvedBy": actor.UID, "resolvedAt": time.Now().UTC(), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) resolveSettlementDispute(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	ref := store.firestore.Collection("settlements").Doc(text(payload, "bookingId"))
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "todaId")) || text(doc.Data(), "adjustmentStatus") != "disputed" {
		return nil, fmt.Errorf("%w: disputed settlement is unavailable", app.ErrPrecondition)
	}
	_, err = ref.Set(ctx, map[string]any{"adjustmentStatus": "resolved", "disputeResolution": truncate(text(payload, "resolution"), 1000), "disputeResolvedBy": actor.UID, "disputeResolvedAt": time.Now().UTC(), "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) submitZone(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	todaID := text(payload, "todaId")
	if todaID == "" || !actor.canAccessToda(todaID) {
		return nil, fmt.Errorf("%w: TODA is outside administrator scope", app.ErrPrecondition)
	}
	polygon, areas, err := firestoreGeometry(payload, 3)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", app.ErrInvalidArgument, err)
	}
	id := "zone_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	now := time.Now().UTC()
	_, err = store.firestore.Collection("zoneRequests").Doc(id).Create(ctx, map[string]any{"zoneRequestId": id, "todaId": todaID, "polygon": polygon, "areas": areas, "notes": truncate(text(payload, "notes"), 1000), "status": "pending", "geometryVersion": 1, "submittedBy": actor.UID, "createdAt": now, "updatedAt": now})
	return map[string]any{"zoneRequestId": id}, err
}

func (store *Store) reviewZone(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	ref := store.firestore.Collection("zoneRequests").Doc(text(payload, "zoneRequestId"))
	doc, err := ref.Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: zone request not found", app.ErrPrecondition)
	}
	status := text(payload, "status")
	if status != "approved" && status != "declined" {
		return nil, fmt.Errorf("%w: invalid zone decision", app.ErrInvalidArgument)
	}
	now := time.Now().UTC()
	batch := store.firestore.Batch()
	batch.Set(ref, map[string]any{"status": status, "reviewedBy": actor.UID, "reviewedAt": now, "updatedAt": now}, firestore.MergeAll)
	if status == "approved" {
		data := doc.Data()
		batch.Set(store.firestore.Collection("geofences").Doc(text(data, "todaId")), map[string]any{"todaId": text(data, "todaId"), "areas": data["areas"], "polygon": data["polygon"], "isActive": true, "coverageRevision": integer(data, "geometryVersion"), "updatedAt": now}, firestore.MergeAll)
	}
	_, err = batch.Commit(ctx)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) updateZone(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	ref := store.firestore.Collection("zoneRequests").Doc(text(payload, "zoneRequestId"))
	doc, err := ref.Get(ctx)
	if err != nil || !actor.canAccessToda(text(doc.Data(), "todaId")) {
		return nil, fmt.Errorf("%w: zone is outside administrator scope", app.ErrPrecondition)
	}
	polygon, areas, geometryErr := firestoreGeometry(payload, 3)
	if geometryErr != nil {
		return nil, fmt.Errorf("%w: %v", app.ErrInvalidArgument, geometryErr)
	}
	_, err = ref.Set(ctx, map[string]any{"polygon": polygon, "areas": areas, "notes": truncate(text(payload, "notes"), 1000), "status": "pending", "geometryVersion": integer(doc.Data(), "geometryVersion") + 1, "updatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) createRestriction(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	name, restrictionType, geometryType := text(payload, "name"), text(payload, "type"), text(payload, "geometryType")
	if name == "" || !contains([]string{"no_service_area", "restricted_crossing", "prohibited_highway"}, restrictionType) || !contains([]string{"polygon", "corridor"}, geometryType) {
		return nil, fmt.Errorf("%w: restriction name and supported type are required", app.ErrInvalidArgument)
	}
	minimumPoints := 3
	if geometryType == "corridor" {
		minimumPoints = 2
	}
	polygon, areas, err := firestoreGeometry(payload, minimumPoints)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", app.ErrInvalidArgument, err)
	}
	id := "restriction_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	now := time.Now().UTC()
	data := map[string]any{"restrictionId": id, "name": name, "type": restrictionType, "geometryType": geometryType, "polygon": polygon, "areas": areas, "bufferMeters": number(payload, "bufferMeters"), "minimumAlignedTravelMeters": number(payload, "minimumAlignedTravelMeters"), "notes": truncate(text(payload, "notes"), 1000), "isActive": true, "geometryVersion": 1, "createdBy": actor.UID, "createdAt": now, "updatedAt": now}
	_, err = store.firestore.Collection("routeRestrictions").Doc(id).Create(ctx, data)
	return map[string]any{"restrictionId": id}, err
}

// firestoreGeometry converts the Admin's JSON coordinate arrays into maps.
// Firestore permits arrays of maps, but prohibits arrays containing arrays.
func firestoreGeometry(payload map[string]any, minimumPoints int) ([]map[string]any, []map[string]any, error) {
	rawAreas, _ := payload["areas"].([]any)
	if len(rawAreas) == 0 {
		rawAreas = []any{payload["polygon"]}
	}
	if len(rawAreas) == 0 || len(rawAreas) > core.MaxAreas {
		return nil, nil, fmt.Errorf("between 1 and %d geometry areas are required", core.MaxAreas)
	}
	areas := make([]map[string]any, 0, len(rawAreas))
	var polygon []map[string]any
	for _, rawArea := range rawAreas {
		points, err := firestorePoints(rawArea, minimumPoints)
		if err != nil {
			return nil, nil, err
		}
		if polygon == nil {
			polygon = points
		}
		areas = append(areas, map[string]any{"points": points})
	}
	return polygon, areas, nil
}

func firestorePoints(raw any, minimumPoints int) ([]map[string]any, error) {
	values, ok := raw.([]any)
	if !ok {
		if object, objectOK := raw.(map[string]any); objectOK {
			values, ok = object["points"].([]any)
		}
	}
	if !ok || len(values) < minimumPoints || len(values) > core.MaxPoints {
		return nil, fmt.Errorf("each geometry area requires %d to %d valid points", minimumPoints, core.MaxPoints)
	}
	points := make([]map[string]any, 0, len(values))
	for _, rawPoint := range values {
		longitude, latitude, valid := geometryCoordinate(rawPoint)
		if !valid {
			return nil, fmt.Errorf("geometry contains an invalid coordinate")
		}
		points = append(points, map[string]any{"longitude": longitude, "latitude": latitude})
	}
	return points, nil
}

func geometryCoordinate(raw any) (float64, float64, bool) {
	if pair, ok := raw.([]any); ok && len(pair) >= 2 {
		longitude, longitudeOK := numeric(pair[0])
		latitude, latitudeOK := numeric(pair[1])
		return longitude, latitude, longitudeOK && latitudeOK && core.Coordinate{Latitude: latitude, Longitude: longitude}.Valid()
	}
	if point, ok := raw.(map[string]any); ok {
		longitude, longitudeOK := numeric(point["longitude"])
		if !longitudeOK {
			longitude, longitudeOK = numeric(point["lng"])
		}
		latitude, latitudeOK := numeric(point["latitude"])
		if !latitudeOK {
			latitude, latitudeOK = numeric(point["lat"])
		}
		return longitude, latitude, longitudeOK && latitudeOK && core.Coordinate{Latitude: latitude, Longitude: longitude}.Valid()
	}
	return 0, 0, false
}

func (store *Store) setRestrictionStatus(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	_, err := store.firestore.Collection("routeRestrictions").Doc(text(payload, "restrictionId")).Set(ctx, map[string]any{"isActive": booleanDefault(payload, false, "isActive"), "updatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}
