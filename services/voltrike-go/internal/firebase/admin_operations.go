package firebase

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

type adminIdentity struct {
	UID    string
	Role   string
	TodaID string
}

func (store *Store) loadAdmin(ctx context.Context, principal app.Principal) (adminIdentity, error) {
	snapshot, err := store.firestore.Collection("users").Doc(principal.UID).Get(ctx)
	if err != nil {
		return adminIdentity{}, fmt.Errorf("%w: administrator profile is required", app.ErrPrecondition)
	}
	return adminIdentityFromProfile(principal, snapshot.Data())
}

func adminIdentityFromProfile(principal app.Principal, data map[string]any) (adminIdentity, error) {
	role := canonicalAdminRole(text(data, "role"))
	if role != "developer_admin" && role != "developer" && role != "admin" && role != "toda_admin" {
		return adminIdentity{}, fmt.Errorf("%w: administrator access is required", app.ErrPrecondition)
	}
	if !booleanDefault(data, false, "isActive") {
		return adminIdentity{}, fmt.Errorf("%w: administrator account is inactive", app.ErrPrecondition)
	}
	claimRole := canonicalAdminRole(claimText(principal.Claims, "adminRole"))
	if claimRole == "" {
		// Temporary compatibility for tokens issued before adminRole became the
		// canonical claim. Every new claim write includes both fields.
		claimRole = canonicalAdminRole(claimText(principal.Claims, "role"))
	}
	if claimRole != role {
		return adminIdentity{}, fmt.Errorf("%w: administrator claim and profile do not match", app.ErrPrecondition)
	}
	todaID := text(data, "todaId")
	if role == "toda_admin" && (todaID == "" || claimText(principal.Claims, "todaId") != todaID) {
		return adminIdentity{}, fmt.Errorf("%w: TODA administrator claim is invalid", app.ErrPrecondition)
	}
	return adminIdentity{UID: principal.UID, Role: role, TodaID: todaID}, nil
}

func canonicalAdminRole(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "developer", "admin", "developer_admin":
		return "developer_admin"
	case "toda_admin":
		return "toda_admin"
	default:
		return ""
	}
}

func claimText(claims map[string]any, key string) string {
	value, _ := claims[key].(string)
	return strings.TrimSpace(value)
}

func (identity adminIdentity) developer() bool { return identity.Role != "toda_admin" }
func (identity adminIdentity) canAccessToda(todaID string) bool {
	return identity.developer() || identity.TodaID != "" && identity.TodaID == todaID
}

func (store *Store) canAdminAccessToda(ctx context.Context, principal app.Principal, todaID string) bool {
	actor, err := store.loadAdmin(ctx, principal)
	return err == nil && actor.canAccessToda(todaID)
}

func (store *Store) executeAdminOperation(ctx context.Context, principal app.Principal, command app.OperationCommand) (result map[string]any, operationErr error) {
	if command.Name == "bootstrapDeveloperAdmin" {
		return store.bootstrapDeveloper(ctx, principal, command.Payload)
	}
	if command.Name == "registerToda" {
		return store.registerToda(ctx, principal, command.Payload, false)
	}
	if command.Name == "attachTodaRegistrationDocuments" {
		return store.attachRegistrationDocuments(ctx, principal, command.Payload)
	}
	actor, err := store.loadAdmin(ctx, principal)
	if err != nil {
		return nil, err
	}
	if !strings.HasPrefix(command.Name, "adminList") && !strings.HasPrefix(command.Name, "adminGet") {
		defer func() {
			if operationErr == nil {
				store.writeAdminAudit(ctx, actor, command)
			}
		}()
	}
	switch command.Name {
	case "adminCreateToda":
		return store.registerToda(ctx, principal, command.Payload, true)
	case "adminReviewTodaRegistration":
		return store.reviewToda(ctx, actor, command.Payload)
	case "adminAssignTodaAdmin":
		return store.assignTodaAdmin(ctx, actor, command.Payload)
	case "adminSetTodaStatus":
		return store.setTodaStatus(ctx, actor, command.Payload)
	case "adminAttachTodaDocuments":
		return store.attachTodaDocuments(ctx, actor, command.Payload)
	case "adminGetTodaDocumentUrl":
		return store.todaDocumentURL(ctx, actor, command.Payload)
	case "adminUpdateFare":
		return store.updateFare(ctx, actor, command.Payload)
	case "adminSetDriverStatus":
		return store.setDriverStatus(ctx, actor, command.Payload)
	case "adminSetVehicleVerification":
		return store.setVehicleVerification(ctx, actor, command.Payload)
	case "adminSetUserStatus":
		return store.setUserStatus(ctx, actor, command.Payload)
	case "adminResolveReport":
		return store.resolveReport(ctx, actor, command.Payload)
	case "adminResolveSettlementDispute":
		return store.resolveSettlementDispute(ctx, actor, command.Payload)
	case "adminSubmitZoneRequest":
		return store.submitZone(ctx, actor, command.Payload)
	case "adminReviewZoneRequest":
		return store.reviewZone(ctx, actor, command.Payload)
	case "adminUpdateZoneRequest":
		return store.updateZone(ctx, actor, command.Payload)
	case "adminCreateRouteRestriction":
		return store.createRestriction(ctx, actor, command.Payload)
	case "adminSetRouteRestrictionStatus":
		return store.setRestrictionStatus(ctx, actor, command.Payload)
	case "adminGetTodaCommission":
		return store.getTodaCommission(ctx, actor)
	case "adminSetTodaCommission":
		return store.setTodaCommission(ctx, actor, command.Payload)
	case "adminSettleDriverCommission":
		return store.settleDriverCommission(ctx, actor, command.CommandID, command.Payload)
	case "adminGetTodaCommissionReport":
		return store.commissionReport(ctx, actor, command.Payload)
	case "adminGetMetrics":
		return store.adminMetrics(ctx, actor)
	case "adminListDrivers":
		return store.adminListDrivers(ctx, actor, command.Payload)
	case "adminListRatings":
		return store.adminListRatings(ctx, actor, command.Payload)
	case "adminListReports":
		return store.adminList(ctx, actor, "reports", command.Payload)
	case "adminListBookings":
		return store.adminList(ctx, actor, "bookings", command.Payload)
	case "adminListSafetyIncidents":
		return store.adminList(ctx, actor, "safetyIncidents", command.Payload)
	case "adminListLiveDrivers":
		return store.adminLiveDrivers(ctx, actor)
	case "adminListTodas":
		return store.adminListTodas(ctx, actor)
	case "adminListZones":
		return store.adminListZones(ctx, actor, command.Payload)
	case "adminListRouteRestrictions":
		return store.adminListRestrictions(ctx, actor)
	case "adminGetFare":
		return store.adminGetFare(ctx, actor)
	case "adminCancelBookingForSafety":
		return store.cancelBookingForSafety(ctx, actor, command.Payload)
	case "adminUpdateSafetyIncidentResponse":
		return store.updateSafetyResponse(ctx, actor, command.Payload)
	case "adminListDriverViolations":
		return store.adminListViolations(ctx, actor, command.Payload)
	case "adminGetDriverViolation":
		return store.adminGetViolation(ctx, actor, command.Payload)
	case "adminUpdateDriverViolation":
		return store.adminUpdateViolation(ctx, actor, command.Payload)
	default:
		return nil, fmt.Errorf("%w: unsupported admin operation %q", app.ErrInvalidArgument, command.Name)
	}
}

func (store *Store) writeAdminAudit(ctx context.Context, actor adminIdentity, command app.OperationCommand) {
	payload, _ := json.Marshal(command.Payload)
	digest := sha256.Sum256(payload)
	targets := map[string]string{}
	for _, key := range []string{"todaId", "uid", "driverId", "bookingId", "reportId", "zoneRequestId", "restrictionId"} {
		if value := text(command.Payload, key); value != "" {
			targets[key] = value
		}
	}
	now := time.Now().UTC()
	_, err := store.firestore.Collection("adminAuditLogs").Doc(uuid.NewString()).Create(ctx, map[string]any{
		"actorUid": actor.UID, "actorRole": actor.Role, "actorTodaId": actor.TodaID,
		"operation": command.Name, "commandId": command.CommandID, "targets": targets,
		"payloadSha256": hex.EncodeToString(digest[:]), "createdAt": now,
	})
	if err != nil {
		slog.Error("write administrator audit log", "operation", command.Name, "actorUid", actor.UID, "error", err)
	}
}

func (store *Store) bootstrapDeveloper(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	if store.cfg.DeveloperBootstrapCode == "" || text(payload, "code") != store.cfg.DeveloperBootstrapCode {
		return nil, fmt.Errorf("%w: bootstrap code is invalid", app.ErrPrecondition)
	}
	now := time.Now().UTC()
	if _, err := store.firestore.Collection("users").Doc(principal.UID).Set(ctx, map[string]any{"role": "developer_admin", "isActive": true, "updatedAt": now}, firestore.MergeAll); err != nil {
		return nil, err
	}
	if err := store.auth.SetCustomUserClaims(ctx, principal.UID, map[string]any{"role": "developer_admin", "adminRole": "developer_admin", "admin": true}); err != nil {
		return nil, err
	}
	return map[string]any{"role": "developer_admin"}, nil
}

func (store *Store) registerToda(ctx context.Context, principal app.Principal, payload map[string]any, approved bool) (map[string]any, error) {
	name := text(payload, "name")
	if name == "" {
		return nil, fmt.Errorf("%w: TODA name is required", app.ErrInvalidArgument)
	}
	id := text(payload, "todaId")
	if id == "" {
		id = "toda_" + strings.ReplaceAll(uuid.NewString(), "-", "")
	}
	now, status := time.Now().UTC(), "pending"
	if approved {
		status = "approved"
	}
	publicData := publicTodaData(payload, id, name, status, approved, now)
	applicationData := privateTodaApplicationData(payload, id, principal.UID, status, now)
	userData := map[string]any{
		"role":                      "toda_admin_pending",
		"todaId":                    id,
		"todaApplicationStatus":     status,
		"requiresEmailVerification": true,
		"isActive":                  false,
		"updatedAt":                 now,
	}
	err := store.firestore.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		if err := tx.Create(store.firestore.Collection("todas").Doc(id), publicData); err != nil {
			return err
		}
		if err := tx.Create(store.firestore.Collection("todaApplications").Doc(id), applicationData); err != nil {
			return err
		}
		tx.Set(store.firestore.Collection("users").Doc(principal.UID), userData, firestore.MergeAll)
		return nil
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"todaId": id}, nil
}

func publicTodaData(payload map[string]any, id, name, status string, active bool, now time.Time) map[string]any {
	result := map[string]any{
		"todaId": id, "name": name, "registrationStatus": status,
		"isActive": active, "createdAt": now, "updatedAt": now,
	}
	for _, key := range []string{"regionCode", "regionName", "provinceCode", "provinceName", "cityCode", "cityName", "barangayCode", "barangayName"} {
		if value := text(payload, key); value != "" {
			result[key] = value
		}
	}
	return result
}

func privateTodaApplicationData(payload map[string]any, id, adminUID, status string, now time.Time) map[string]any {
	result := map[string]any{
		"todaId": id, "adminUid": adminUID, "status": status,
		"registration": copyMapValue(payload["registration"]),
		"createdAt":    now, "updatedAt": now,
	}
	for _, key := range []string{"regionCode", "regionName", "provinceCode", "provinceName", "cityCode", "cityName", "barangayCode", "barangayName", "name"} {
		if value := text(payload, key); value != "" {
			result[key] = value
		}
	}
	return result
}

func copyMapValue(value any) map[string]any {
	if source, ok := value.(map[string]any); ok {
		return copyMap(source)
	}
	return map[string]any{}
}

func (store *Store) reviewToda(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	id, status := text(payload, "todaId"), text(payload, "status")
	if !actor.developer() || status != "approved" && status != "declined" {
		return nil, fmt.Errorf("%w: invalid TODA review", app.ErrPrecondition)
	}
	application, err := store.firestore.Collection("todaApplications").Doc(id).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: TODA application was not found", app.ErrPrecondition)
	}
	adminUID := text(application.Data(), "adminUid")
	if adminUID == "" {
		return nil, fmt.Errorf("%w: TODA application has no administrator", app.ErrPrecondition)
	}
	if status == "approved" {
		if err := store.auth.SetCustomUserClaims(ctx, adminUID, map[string]any{"role": "toda_admin", "adminRole": "toda_admin", "todaId": id}); err != nil {
			return nil, err
		}
	}
	now := time.Now().UTC()
	batch := store.firestore.Batch()
	batch.Set(store.firestore.Collection("todas").Doc(id), map[string]any{"registrationStatus": status, "isActive": status == "approved", "reviewedBy": actor.UID, "reviewedAt": now, "updatedAt": now}, firestore.MergeAll)
	batch.Set(application.Ref, map[string]any{"status": status, "reviewedBy": actor.UID, "reviewedAt": now, "updatedAt": now}, firestore.MergeAll)
	profile := map[string]any{"todaId": id, "todaApplicationStatus": status, "isActive": status == "approved", "updatedAt": now}
	if status == "approved" {
		profile["role"] = "toda_admin"
	} else {
		profile["role"] = "toda_admin_pending"
	}
	batch.Set(store.firestore.Collection("users").Doc(adminUID), profile, firestore.MergeAll)
	_, err = batch.Commit(ctx)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) assignTodaAdmin(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	uid, todaID := text(payload, "uid"), text(payload, "todaId")
	if !actor.developer() || uid == "" || todaID == "" {
		return nil, fmt.Errorf("%w: developer administrator, uid, and todaId are required", app.ErrPrecondition)
	}
	if err := store.auth.SetCustomUserClaims(ctx, uid, map[string]any{"role": "toda_admin", "adminRole": "toda_admin", "todaId": todaID}); err != nil {
		return nil, err
	}
	_, err := store.firestore.Collection("users").Doc(uid).Set(ctx, map[string]any{"role": "toda_admin", "todaId": todaID, "isActive": true, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"assigned": err == nil}, err
}

func (store *Store) setTodaStatus(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	id := text(payload, "todaId")
	if !actor.canAccessToda(id) {
		return nil, fmt.Errorf("%w: TODA is outside administrator scope", app.ErrPrecondition)
	}
	_, err := store.firestore.Collection("todas").Doc(id).Set(ctx, map[string]any{"isActive": booleanDefault(payload, false, "isActive"), "updatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) attachTodaDocuments(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	id := text(payload, "todaId")
	if !actor.canAccessToda(id) {
		return nil, fmt.Errorf("%w: TODA is outside administrator scope", app.ErrPrecondition)
	}
	_, err := store.firestore.Collection("todaApplications").Doc(id).Set(ctx, map[string]any{"documents": payload["documents"], "documentsUpdatedBy": actor.UID, "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) attachRegistrationDocuments(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	id := text(payload, "todaId")
	snapshot, err := store.firestore.Collection("todaApplications").Doc(id).Get(ctx)
	if err != nil || text(snapshot.Data(), "adminUid") != principal.UID || text(snapshot.Data(), "status") != "pending" {
		return nil, fmt.Errorf("%w: TODA registration is not owned by user", app.ErrPrecondition)
	}
	_, err = snapshot.Ref.Set(ctx, map[string]any{"documents": payload["documents"], "updatedAt": time.Now().UTC()}, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func (store *Store) updateFare(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	if !actor.developer() {
		return nil, fmt.Errorf("%w: developer administrator is required", app.ErrPrecondition)
	}
	fare, ok := payload["fare"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("%w: fare payload is required", app.ErrInvalidArgument)
	}
	fare = copyMap(fare)
	fare["version"], fare["updatedBy"], fare["updatedAt"] = integer(fare, "version")+1, actor.UID, time.Now().UTC()
	_, err := store.firestore.Collection("settings").Doc("fare_config").Set(ctx, fare, firestore.MergeAll)
	return map[string]any{"updated": err == nil}, err
}

func copyMap(source map[string]any) map[string]any {
	result := make(map[string]any, len(source))
	for key, value := range source {
		result[key] = value
	}
	return result
}
