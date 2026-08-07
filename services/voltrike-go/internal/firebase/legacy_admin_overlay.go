package firebase

import "github.com/voltrike/voltrike-go/internal/app"

// adminPrincipal exists only so an older unsaved editor overlay fails closed
// instead of breaking package analysis. Persisted authorization must use
// loadAdmin/canAdminAccessToda, which verify the active profile and TODA scope.
// Deprecated: never use in saved application code.
func adminPrincipal(app.Principal) bool { return false }
