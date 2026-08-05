package firebase

import (
	"context"
	"crypto/sha256"
	"fmt"
	"sort"
	"strconv"
	"strings"

	"cloud.google.com/go/firestore"
	firebaseadmin "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/appcheck"
	"firebase.google.com/go/v4/auth"
	"firebase.google.com/go/v4/db"
	"github.com/voltrike/voltrike-go/internal/app"
	"github.com/voltrike/voltrike-go/internal/config"
	"github.com/voltrike/voltrike-go/internal/core"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Store struct {
	firestore *firestore.Client
	realtime  *db.Client
	auth      *auth.Client
	appCheck  *appcheck.Client
	cfg       config.Config
}

func Open(ctx context.Context, cfg config.Config) (*Store, func(), error) {
	admin, err := firebaseadmin.NewApp(ctx, &firebaseadmin.Config{ProjectID: cfg.ProjectID, DatabaseURL: cfg.DatabaseURL})
	if err != nil {
		return nil, nil, fmt.Errorf("initialize Firebase Admin: %w", err)
	}
	firestoreClient, err := admin.Firestore(ctx)
	if err != nil {
		return nil, nil, fmt.Errorf("initialize Firestore: %w", err)
	}
	realtimeClient, err := admin.Database(ctx)
	if err != nil {
		_ = firestoreClient.Close()
		return nil, nil, fmt.Errorf("initialize Realtime Database: %w", err)
	}
	authClient, err := admin.Auth(ctx)
	if err != nil {
		_ = firestoreClient.Close()
		return nil, nil, fmt.Errorf("initialize Firebase Auth: %w", err)
	}
	appCheckClient, err := admin.AppCheck(ctx)
	if err != nil {
		_ = firestoreClient.Close()
		return nil, nil, fmt.Errorf("initialize Firebase App Check: %w", err)
	}
	store := &Store{
		firestore: firestoreClient,
		realtime:  realtimeClient,
		auth:      authClient,
		appCheck:  appCheckClient,
		cfg:       cfg,
	}
	return store, func() { _ = firestoreClient.Close() }, nil
}

func (store *Store) VerifyIDToken(ctx context.Context, token string) (app.Principal, error) {
	if store.auth == nil {
		return app.Principal{}, fmt.Errorf("Firebase Auth verifier is unavailable")
	}
	decoded, err := store.auth.VerifyIDToken(ctx, token)
	if err != nil {
		return app.Principal{}, err
	}
	return app.Principal{UID: decoded.UID, Claims: decoded.Claims}, nil
}

func (store *Store) VerifyAppCheck(token string) error {
	if store.appCheck == nil {
		return fmt.Errorf("Firebase App Check verifier is unavailable")
	}
	_, err := store.appCheck.VerifyToken(token)
	return err
}

func (store *Store) LoadPolicy(ctx context.Context) (app.Policy, error) {
	fareDoc, err := store.firestore.Collection("settings").Doc("fare_config").Get(ctx)
	if err != nil && !isNotFound(err) {
		return app.Policy{}, fmt.Errorf("read fare config: %w", err)
	}
	fareData := map[string]any{}
	revisionParts := make([]string, 0, 704)
	if err == nil {
		fareData = fareDoc.Data()
		revisionParts = append(revisionParts, "fare:"+fareDoc.UpdateTime.UTC().String())
	} else {
		revisionParts = append(revisionParts, "fare:default")
	}

	geofences, geofenceRevisions, err := store.readGeofences(ctx)
	if err != nil {
		return app.Policy{}, err
	}
	restrictions, restrictionRevisions, err := store.readRestrictions(ctx)
	if err != nil {
		return app.Policy{}, err
	}
	revisionParts = append(revisionParts, geofenceRevisions...)
	revisionParts = append(revisionParts, restrictionRevisions...)
	sort.Strings(revisionParts)
	hash := sha256.Sum256([]byte(strings.Join(revisionParts, "|")))
	return app.Policy{
		Fare:         parseFare(fareData),
		Geofences:    geofences,
		Restrictions: restrictions,
		Revision:     fmt.Sprintf("%x", hash),
	}, nil
}

func (store *Store) ReadDispatchCell(ctx context.Context, cell string) (map[string]app.DispatchPresence, error) {
	if strings.ContainsAny(cell, "/.#$[]") {
		return nil, fmt.Errorf("invalid dispatch cell")
	}
	entries := map[string]app.DispatchPresence{}
	if err := store.realtime.NewRef("dispatchCells/"+cell).Get(ctx, &entries); err != nil {
		return nil, err
	}
	return entries, nil
}

func (store *Store) readGeofences(ctx context.Context) ([]core.Geofence, []string, error) {
	documents := store.firestore.Collection("geofences").Limit(500).Documents(ctx)
	defer documents.Stop()
	result := make([]core.Geofence, 0)
	revisions := make([]string, 0)
	for {
		doc, err := documents.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, nil, fmt.Errorf("read geofences: %w", err)
		}
		data := doc.Data()
		item := core.Geofence{
			ID:               doc.Ref.ID,
			TodaID:           text(data, "todaId", "todaID"),
			IsActive:         booleanDefault(data, true, "isActive"),
			CoverageRevision: integer(data, "coverageRevision"),
			Areas:            parseAreas(data),
		}
		result = append(result, item)
		revisions = append(revisions, "geofence:"+doc.Ref.ID+":"+doc.UpdateTime.UTC().String())
	}
	return result, revisions, nil
}

func (store *Store) readRestrictions(ctx context.Context) ([]core.Restriction, []string, error) {
	documents := store.firestore.Collection("routeRestrictions").Limit(200).Documents(ctx)
	defer documents.Stop()
	result := make([]core.Restriction, 0)
	revisions := make([]string, 0)
	for {
		doc, err := documents.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, nil, fmt.Errorf("read restrictions: %w", err)
		}
		data := doc.Data()
		item := core.Restriction{
			ID:                         doc.Ref.ID,
			Name:                       text(data, "name"),
			Type:                       text(data, "type", "restrictionType"),
			IsActive:                   booleanDefault(data, true, "isActive"),
			GeometryType:               text(data, "geometryType"),
			BufferMeters:               number(data, "bufferMeters"),
			MinimumAlignedTravelMeters: number(data, "minimumAlignedTravelMeters"),
			Areas:                      parseAreas(data),
		}
		result = append(result, item)
		revisions = append(revisions, "restriction:"+doc.Ref.ID+":"+doc.UpdateTime.UTC().String())
	}
	return result, revisions, nil
}

func parseFare(data map[string]any) core.FareConfig {
	result := core.DefaultFare
	applyInt(data, &result.Version, "version", "fareVersion")
	applyFloat(data, &result.BaseFare, "baseFare")
	applyInt(data, &result.IncludedMeters, "includedMeters")
	applyInt(data, &result.DistanceStepMeters, "distanceStepMeters")
	applyFloat(data, &result.DistanceStepPrice, "distanceStepPrice")
	applyFloat(data, &result.AdditionalPassengerFee, "additionalPassengerFee")
	applyFloat(data, &result.BaggageFee, "baggageFee")
	applyFloat(data, &result.OutsideTodaSurcharge, "outsideTodaSurcharge")
	if value := text(data, "currency"); value == "PHP" {
		result.Currency = value
	}
	return core.SnapshotFare(result)
}

func parseAreas(data map[string]any) []core.Area {
	if raw, ok := data["areas"]; ok {
		if areas := areaList(raw); len(areas) > 0 {
			return areas
		}
	}
	for _, key := range []string{"polygon", "coordinates", "points", "path"} {
		if raw, ok := data[key]; ok {
			if points := pointList(raw); len(points) > 0 {
				return []core.Area{{Points: points}}
			}
		}
	}
	return nil
}

func areaList(raw any) []core.Area {
	values, ok := raw.([]any)
	if !ok {
		return nil
	}
	result := make([]core.Area, 0, len(values))
	for _, value := range values {
		object, ok := value.(map[string]any)
		if !ok {
			continue
		}
		for _, key := range []string{"points", "polygon", "coordinates", "path"} {
			if points := pointList(object[key]); len(points) > 0 {
				result = append(result, core.Area{Points: points})
				break
			}
		}
	}
	return result
}

func pointList(raw any) []core.Coordinate {
	values, ok := raw.([]any)
	if !ok {
		return nil
	}
	result := make([]core.Coordinate, 0, len(values))
	for _, value := range values {
		object, ok := value.(map[string]any)
		if !ok {
			continue
		}
		point := core.Coordinate{
			Latitude:  firstNumber(object, "latitude", "lat"),
			Longitude: firstNumber(object, "longitude", "lng", "lon"),
		}
		if point.Valid() {
			result = append(result, point)
		}
	}
	return result
}

func text(data map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := data[key].(string); ok {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func booleanDefault(data map[string]any, fallback bool, keys ...string) bool {
	for _, key := range keys {
		if value, ok := data[key].(bool); ok {
			return value
		}
	}
	return fallback
}

func number(data map[string]any, keys ...string) float64 {
	for _, key := range keys {
		if result, ok := numeric(data[key]); ok {
			return result
		}
	}
	return 0
}

func firstNumber(data map[string]any, keys ...string) float64 { return number(data, keys...) }

func integer(data map[string]any, keys ...string) int { return int(number(data, keys...)) }

func applyFloat(data map[string]any, target *float64, keys ...string) {
	for _, key := range keys {
		if value, ok := numeric(data[key]); ok {
			*target = value
			return
		}
	}
}

func applyInt(data map[string]any, target *int, keys ...string) {
	for _, key := range keys {
		if value, ok := numeric(data[key]); ok {
			*target = int(value)
			return
		}
	}
}

func numeric(value any) (float64, bool) {
	switch typed := value.(type) {
	case float64:
		return typed, true
	case float32:
		return float64(typed), true
	case int:
		return float64(typed), true
	case int64:
		return float64(typed), true
	case int32:
		return float64(typed), true
	case jsonNumber:
		parsed, err := strconv.ParseFloat(string(typed), 64)
		return parsed, err == nil
	default:
		return 0, false
	}
}

type jsonNumber string

func isNotFound(err error) bool { return status.Code(err) == codes.NotFound }
