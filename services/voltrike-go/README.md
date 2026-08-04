# VolTrike private Go service

This service is a private compute/read plane behind Firebase Functions. Mobile
and admin clients must never call it directly.

It owns cached fare/coverage/restriction reads, Google Routes computation,
opaque short-lived booking quote tokens, and spatial dispatch candidate reads.
Firebase Functions remains authoritative for authentication, booking and ride
state transitions, dispatch eligibility, settlements, commissions, and all
durable writes.

Required runtime configuration:

- `GOOGLE_CLOUD_PROJECT`
- `FIREBASE_DATABASE_URL`
- `GOOGLE_ROUTES_API_KEY` (use Secret Manager in production)
- `GO_QUOTE_ENCRYPTION_KEY` (base64-encoded 32 bytes; use Secret Manager)

Optional bounds include `POLICY_CACHE_TTL_SECONDS`,
`REQUEST_TIMEOUT_SECONDS`, `DISPATCH_RADIUS_METERS`, and
`MAX_DISPATCH_RESULTS`.

See [DEPLOYMENT.md](DEPLOYMENT.md) for the private Cloud Run, IAM, staged
Firebase Functions, Render Admin, and manual Flutter rollout commands.
