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
	if !actor.canAccessToda(todaID) {
		return nil, fmt.Errorf("%w: TODA is outside administrator scope", app.ErrPrecondition)
	}
	id := "zone_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	now := time.Now().UTC()
	_, err := store.firestore.Collection("zoneRequests").Doc(id).Create(ctx, map[string]any{"zoneRequestId": id, "todaId": todaID, "polygon": payload["polygon"], "areas": payload["areas"], "notes": truncate(text(payload, "notes"), 1000), "status": "pending", "geometryVersion": 1, "submittedBy": actor.UID, "createdAt": now, "updatedAt": now})
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
	_, err = ref.Set(ctx, map[string]any{"polygon": payload["polygon"], "areas": payload["areas"], "notes": truncate(text(payload, "notes"), 1000), "status": "pending", "geometryVersion": integer(doc.Data(), "geometryVersion") + 1, "updatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) createRestriction(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	id := "restriction_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	now := time.Now().UTC()
	data := copyMap(payload)
	data["restrictionId"], data["isActive"], data["geometryVersion"], data["createdBy"], data["createdAt"], data["updatedAt"] = id, true, 1, actor.UID, now, now
	_, err := store.firestore.Collection("routeRestrictions").Doc(id).Create(ctx, data)
	return map[string]any{"restrictionId": id}, err
}

func (store *Store) setRestrictionStatus(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	_, err := store.firestore.Collection("routeRestrictions").Doc(text(payload, "restrictionId")).Set(ctx, map[string]any{"isActive": booleanDefault(payload, false, "isActive"), "updatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}
