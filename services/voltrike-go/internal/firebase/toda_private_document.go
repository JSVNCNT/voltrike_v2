package firebase

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/storage"
	"github.com/voltrike/voltrike-go/internal/app"
)

// todaDocumentURL issues access only after the administrator's active profile,
// claim, and TODA scope were verified by executeAdminOperation.
func (store *Store) todaDocumentURL(ctx context.Context, actor adminIdentity, payload map[string]any) (map[string]any, error) {
	todaID := safeObjectSegment(text(payload, "todaId"))
	reference := strings.TrimSpace(text(payload, "reference"))
	if todaID == "" || !actor.canAccessToda(todaID) {
		return nil, fmt.Errorf("%w: TODA document access is not allowed", app.ErrPrecondition)
	}
	application, err := store.firestore.Collection("todaApplications").Doc(todaID).Get(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: TODA application was not found", app.ErrPrecondition)
	}
	documents, _ := application.Data()["documents"].(map[string]any)
	registered := false
	for _, value := range documents {
		if strings.TrimSpace(fmt.Sprint(value)) == reference {
			registered = true
			break
		}
	}
	if !registered || !strings.HasPrefix(reference, "final/todas/"+todaID+"/") || strings.Contains(reference, "..") {
		return nil, fmt.Errorf("%w: TODA document reference is invalid", app.ErrPrecondition)
	}
	if _, err := store.bucket.Object(reference).Attrs(ctx); err != nil {
		return nil, fmt.Errorf("%w: TODA document was not found", app.ErrPrecondition)
	}
	expiresAt := time.Now().Add(5 * time.Minute)
	signedURL, err := store.bucket.SignedURL(reference, &storage.SignedURLOptions{
		Scheme: storage.SigningSchemeV4, Method: "GET", Expires: expiresAt,
	})
	if err != nil {
		return nil, fmt.Errorf("create short-lived TODA document URL: %w", err)
	}
	return map[string]any{"url": signedURL, "expiresAt": expiresAt}, nil
}
