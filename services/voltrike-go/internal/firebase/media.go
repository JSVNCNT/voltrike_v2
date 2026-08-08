package firebase

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"cloud.google.com/go/storage"
	"github.com/google/uuid"
	"github.com/voltrike/voltrike-go/internal/app"
)

const maximumMediaBytes int64 = 10 * 1024 * 1024

// finalizeMedia turns an authenticated, user-scoped staging upload into a
// server-controlled immutable object. Client download URLs are never trusted.
func (store *Store) finalizeMedia(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	stagingPath := strings.TrimSpace(text(payload, "stagingPath"))
	targetType := strings.TrimSpace(text(payload, "targetType"))
	targetID := strings.TrimSpace(text(payload, "targetId"))
	field := safeObjectSegment(text(payload, "field"))
	if stagingPath == "" || targetID == "" || field == "" ||
		(targetType != "toda_document" && targetType != "profile_image" && targetType != "driver_document" && targetType != "chat_image") {
		return nil, fmt.Errorf("%w: valid stagingPath, targetType, targetId, and field are required", app.ErrInvalidArgument)
	}
	prefix := "staging/" + principal.UID + "/"
	if !strings.HasPrefix(stagingPath, prefix) || strings.Contains(stagingPath, "..") {
		return nil, fmt.Errorf("%w: staging object is not owned by this account", app.ErrPrecondition)
	}
	if targetType == "toda_document" {
		if err := store.authorizeTodaMedia(ctx, principal, targetID); err != nil {
			return nil, err
		}
	} else if targetType == "chat_image" {
		booking, bookingErr := store.participantBooking(ctx, principal, targetID)
		if bookingErr != nil || (principal.UID != text(booking, "passengerId", "passengerID") && principal.UID != text(booking, "driverId", "driverID")) {
			return nil, fmt.Errorf("%w: chat media must belong to a ride participant", app.ErrPrecondition)
		}
	} else if targetID != principal.UID {
		return nil, fmt.Errorf("%w: profile media must belong to the caller", app.ErrPrecondition)
	}
	source := store.bucket.Object(stagingPath)
	attrs, err := source.Attrs(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: staging object was not found", app.ErrPrecondition)
	}
	if attrs.Size < 1 || attrs.Size > maximumMediaBytes || !allowedDocumentType(attrs.ContentType) {
		return nil, fmt.Errorf("%w: unsupported media type or size", app.ErrInvalidArgument)
	}
	if (targetType == "profile_image" || targetType == "driver_document") && !strings.HasPrefix(attrs.ContentType, "image/") {
		return nil, fmt.Errorf("%w: profile media must be an image", app.ErrInvalidArgument)
	}
	if targetType == "chat_image" && (!strings.HasPrefix(attrs.ContentType, "image/") || attrs.Size > 2*1024*1024) {
		return nil, fmt.Errorf("%w: chat images must be compressed images no larger than 2 MB", app.ErrInvalidArgument)
	}
	if expected := int64(integer(payload, "generation")); expected > 0 && attrs.Generation != expected {
		return nil, fmt.Errorf("%w: staging object generation changed", app.ErrPrecondition)
	}
	reader, err := source.NewReader(ctx)
	if err != nil {
		return nil, fmt.Errorf("open staging object: %w", err)
	}
	hasher := sha256.New()
	if _, err := io.Copy(hasher, reader); err != nil {
		_ = reader.Close()
		return nil, fmt.Errorf("hash staging object: %w", err)
	}
	_ = reader.Close()
	digest := hex.EncodeToString(hasher.Sum(nil))
	if expected := strings.ToLower(text(payload, "sha256")); expected != "" && expected != digest {
		return nil, fmt.Errorf("%w: staging object hash does not match", app.ErrPrecondition)
	}
	extension := safeExtension(path.Ext(stagingPath))
	finalRoot := "final/todas"
	if targetType == "profile_image" {
		finalRoot = "final/profiles"
	} else if targetType == "driver_document" {
		finalRoot = "final/drivers"
	} else if targetType == "chat_image" {
		finalRoot = "final/chat"
	}
	finalPath := fmt.Sprintf("%s/%s/%s/%s%s", finalRoot, safeObjectSegment(targetID), field, uuid.NewString(), extension)
	destination := store.bucket.Object(finalPath)
	copier := destination.CopierFrom(source)
	copier.ContentType = attrs.ContentType
	metadata := map[string]string{
		"sha256":      digest,
		"ownerUid":    principal.UID,
		"finalizedAt": time.Now().UTC().Format(time.RFC3339Nano),
	}
	if targetType == "chat_image" {
		metadata["targetType"] = targetType
		metadata["bookingId"] = targetID
		metadata["messageId"] = field
	}
	// Legal evidence is private and gets no permanent bearer download token.
	downloadToken := ""
	if targetType == "profile_image" || targetType == "driver_document" {
		downloadToken = uuid.NewString()
		metadata["firebaseStorageDownloadTokens"] = downloadToken
	}
	copier.Metadata = metadata
	finalAttrs, err := copier.Run(ctx)
	if err != nil {
		return nil, fmt.Errorf("finalize staged object: %w", err)
	}
	if err := source.Delete(ctx); err != nil && err != storage.ErrObjectNotExist {
		// The immutable final object is already valid. A cleanup job may safely
		// remove an abandoned staging copy later.
	}
	downloadURL := ""
	if downloadToken != "" {
		downloadURL = fmt.Sprintf(
			"https://firebasestorage.googleapis.com/v0/b/%s/o/%s?alt=media&token=%s",
			store.bucketName,
			url.PathEscape(finalPath),
			downloadToken,
		)
	}
	if targetType == "profile_image" {
		_, profileErr := store.firestore.Collection("users").Doc(principal.UID).Get(ctx)
		if profileErr == nil {
			if err := store.attachProfileImage(ctx, principal.UID, downloadURL); err != nil {
				return nil, fmt.Errorf("attach finalized profile image: %w", err)
			}
		} else if !isNotFound(profileErr) {
			return nil, fmt.Errorf("check profile before media attachment: %w", profileErr)
		}
	}
	return map[string]any{
		"path":        finalPath,
		"reference":   finalPath,
		"downloadUrl": downloadURL,
		"generation":  finalAttrs.Generation,
		"size":        finalAttrs.Size,
		"contentType": finalAttrs.ContentType,
		"sha256":      digest,
	}, nil
}

func (store *Store) validateFinalizedChatMedia(ctx context.Context, objectPath, bookingID, messageID, ownerUID string) error {
	safeBookingID, safeMessageID := safeObjectSegment(bookingID), safeObjectSegment(messageID)
	if safeBookingID == "" || safeMessageID == "" || safeBookingID != bookingID || safeMessageID != messageID {
		return fmt.Errorf("invalid chat media identifiers")
	}
	expectedPrefix := "final/chat/" + safeBookingID + "/" + safeMessageID + "/"
	if !strings.HasPrefix(objectPath, expectedPrefix) || strings.Contains(objectPath, "..") {
		return fmt.Errorf("invalid chat media path")
	}
	attrs, err := store.bucket.Object(objectPath).Attrs(ctx)
	if err != nil {
		return fmt.Errorf("chat media object not found: %w", err)
	}
	if attrs.Metadata["ownerUid"] != ownerUID || attrs.Metadata["bookingId"] != bookingID || attrs.Metadata["messageId"] != messageID || attrs.Metadata["targetType"] != "chat_image" {
		return fmt.Errorf("chat media ownership proof does not match")
	}
	if attrs.Size < 1 || attrs.Size > 2*1024*1024 || !strings.HasPrefix(attrs.ContentType, "image/") {
		return fmt.Errorf("chat media type or size is invalid")
	}
	return nil
}

func (store *Store) authorizeTodaMedia(ctx context.Context, principal app.Principal, todaID string) error {
	if actor, err := store.loadAdmin(ctx, principal); err == nil && actor.canAccessToda(todaID) {
		return nil
	}
	snapshot, err := store.firestore.Collection("todaApplications").Doc(todaID).Get(ctx)
	if err != nil {
		return fmt.Errorf("%w: TODA application was not found", app.ErrPrecondition)
	}
	data := snapshot.Data()
	if text(data, "adminUid") != principal.UID || text(data, "status") != "pending" {
		return fmt.Errorf("%w: TODA document access is not allowed", app.ErrPrecondition)
	}
	return nil
}

func (store *Store) updateMyProfileImage(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	photoURL := strings.TrimSpace(text(payload, "photoUrl"))
	if photoURL == "" || store.validateFinalizedAccountMedia(ctx, photoURL, principal.UID, "profiles") != nil {
		return nil, fmt.Errorf("%w: profile image must be finalized for this account", app.ErrInvalidArgument)
	}
	if err := store.attachProfileImage(ctx, principal.UID, photoURL); err != nil {
		return nil, err
	}
	return map[string]any{"updated": true, "photoUrl": photoURL}, nil
}

func (store *Store) isFinalizedAccountMediaURL(rawURL, uid, root string) bool {
	_, _, ok := store.finalizedAccountMediaReference(rawURL, uid, root)
	return ok
}

func (store *Store) validateFinalizedAccountMedia(ctx context.Context, rawURL, uid, root string) error {
	objectPath, token, ok := store.finalizedAccountMediaReference(rawURL, uid, root)
	if !ok {
		return fmt.Errorf("invalid finalized media URL")
	}
	attrs, err := store.bucket.Object(objectPath).Attrs(ctx)
	if err != nil {
		return fmt.Errorf("finalized media object not found: %w", err)
	}
	if attrs.Metadata["ownerUid"] != uid || attrs.Metadata["firebaseStorageDownloadTokens"] != token {
		return fmt.Errorf("finalized media ownership proof does not match")
	}
	return nil
}

func (store *Store) finalizedAccountMediaReference(rawURL, uid, root string) (string, string, bool) {
	parsed, err := url.Parse(strings.TrimSpace(rawURL))
	if err != nil || parsed.Scheme != "https" || parsed.Host != "firebasestorage.googleapis.com" {
		return "", "", false
	}
	expectedBucketPath := "/v0/b/" + store.bucketName + "/o/"
	if !strings.HasPrefix(parsed.EscapedPath(), expectedBucketPath) || parsed.Query().Get("alt") != "media" || parsed.Query().Get("token") == "" {
		return "", "", false
	}
	encodedPath := strings.TrimPrefix(parsed.EscapedPath(), expectedBucketPath)
	objectPath, err := url.PathUnescape(encodedPath)
	if err != nil {
		return "", "", false
	}
	if !strings.HasPrefix(objectPath, "final/"+root+"/"+uid+"/") {
		return "", "", false
	}
	return objectPath, parsed.Query().Get("token"), true
}

func (store *Store) attachProfileImage(ctx context.Context, uid, photoURL string) error {
	userRef := store.firestore.Collection("users").Doc(uid)
	user, err := userRef.Get(ctx)
	if err != nil {
		return fmt.Errorf("user profile not found: %w", err)
	}
	role := text(user.Data(), "role")
	if role != "passenger" && role != "driver" {
		return fmt.Errorf("%w: account role cannot own a rider profile image", app.ErrPrecondition)
	}
	now := time.Now().UTC()
	batch := store.firestore.Batch()
	batch.Set(userRef, map[string]any{"profileImage": photoURL, "updatedAt": now}, firestore.MergeAll)
	if role == "passenger" {
		batch.Set(store.firestore.Collection("passengers").Doc(uid), map[string]any{"profileImage": photoURL, "updatedAt": now}, firestore.MergeAll)
	} else {
		batch.Set(store.firestore.Collection("drivers").Doc(uid), map[string]any{"profilePhotoUrl": photoURL, "updatedAt": now}, firestore.MergeAll)
	}
	_, err = batch.Commit(ctx)
	return err
}

func (store *Store) deleteMyFinalizedMedia(ctx context.Context, principal app.Principal, payload map[string]any) (map[string]any, error) {
	rawURL := strings.TrimSpace(text(payload, "url"))
	marker := "/o/"
	index := strings.Index(rawURL, marker)
	if index < 0 || !strings.Contains(rawURL, store.bucketName) {
		return nil, fmt.Errorf("%w: finalized media URL is invalid", app.ErrInvalidArgument)
	}
	encodedPath := strings.SplitN(rawURL[index+len(marker):], "?", 2)[0]
	objectPath, err := url.PathUnescape(encodedPath)
	if err != nil {
		return nil, fmt.Errorf("%w: finalized media path is invalid", app.ErrInvalidArgument)
	}
	profilePrefix := "final/profiles/" + principal.UID + "/"
	driverPrefix := "final/drivers/" + principal.UID + "/"
	if !strings.HasPrefix(objectPath, profilePrefix) && !strings.HasPrefix(objectPath, driverPrefix) {
		return nil, fmt.Errorf("%w: finalized media is not owned by this account", app.ErrPrecondition)
	}
	if err := store.bucket.Object(objectPath).Delete(ctx); err != nil && err != storage.ErrObjectNotExist {
		return nil, err
	}
	return map[string]any{"deleted": true}, nil
}

func allowedDocumentType(value string) bool {
	return strings.HasPrefix(value, "image/") || value == "application/pdf"
}

func safeObjectSegment(value string) string {
	value = strings.TrimSpace(value)
	if value == "" || strings.ContainsAny(value, "/\\.#$[]") {
		return ""
	}
	return value
}

func safeExtension(value string) string {
	value = strings.ToLower(value)
	if len(value) > 10 || strings.ContainsAny(value, "/\\") {
		return ""
	}
	return value
}
