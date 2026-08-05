# VolTrike V2 Go API

This service is the public, Firebase-token-authenticated application API.
Flutter and the Render-hosted Admin call `/api/v2/**` directly with Firebase ID
tokens and App Check tokens. Cloud Run is network-invokable; Go verifies both
tokens and owns authoritative domain writes.

It owns quote integrity, booking/session transactions, revisions, idempotency,
outbox records, and the gradual migration of dispatch, policy, settlement,
safety, and Admin operations from Node compatibility code.

Required runtime configuration:

- `GOOGLE_CLOUD_PROJECT`
- `FIREBASE_DATABASE_URL`
- `GOOGLE_ROUTES_API_KEY` (use Secret Manager in production)
- `GO_QUOTE_ENCRYPTION_KEY` (base64-encoded 32 bytes; use Secret Manager)

Optional bounds include `POLICY_CACHE_TTL_SECONDS`,
`REQUEST_TIMEOUT_SECONDS`, `DISPATCH_RADIUS_METERS`, and
`MAX_DISPATCH_RESULTS`.

See [DEPLOYMENT.md](DEPLOYMENT.md) for Cloud Run, Firebase, Render Admin, and
Flutter deployment commands.
