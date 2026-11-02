# VolTrike Go services

The same source builds two Cloud Run services. Flutter and the static React
Admin use the public API. A separate private worker receives Firestore outbox
events and scheduled maintenance through Cloud Run IAM.

| Service | Runtime configuration | Access and responsibilities |
| --- | --- | --- |
| `voltrike-api-v2` | `GO_INTEGRATION_WORKER=false`, `GO_REQUIRE_APP_CHECK=false`, `GO_AUTOMATIC_RESTRICTION_MONITORING=true` | Public network endpoint; protected commands require Firebase ID tokens. Owns quotes, bookings, sessions, dispatch, policies, settlements, safety, administration, account email and browser push registration. |
| `voltrike-integrations` | `GO_INTEGRATION_WORKER=true`, `GO_NOTIFICATIONS_ENABLED=true` | Private IAM endpoint. Processes `POST /events/outbox` and `POST /tasks/maintenance`; sends FCM and Brevo email after committed domain changes. |

App Check is disabled for the privately shared APK and Admin. Existing
Firebase Auth, role, account, TODA and participant authorization still apply.
The public `POST /auth/password-reset` accepts `{ "email": "..." }` before
sign-in and returns `{ "data": { "accepted": true } }` for unknown accounts
and cooldown repeats. Branded verification and verification-status sync use
authenticated operations. Firebase remains the authority for action links.

Eventarc sends binary CloudEvents for creation of `outbox/{eventId}` to the
worker with Firestore event headers. The worker validates the project/source,
type and document path and reloads the authoritative outbox record. Cloud
Scheduler calls maintenance every minute with an OIDC token whose audience
is the worker service URL. Both callers have dedicated service accounts and
`roles/run.invoker` on the worker; it has no public invoker binding.

The worker platform timeout is 120 seconds; its application write timeout is
110 seconds and each event/maintenance operation has a 100-second budget.
Use `GO_NOTIFICATIONS_ENABLED=false` while staging a replacement sender; that
rejects outbox delivery for retry without sending. Keep its maintenance
schedule paused until the coordinated cutover.

Required shared configuration includes `GOOGLE_CLOUD_PROJECT`,
`FIREBASE_DATABASE_URL`, `GOOGLE_ROUTES_API_KEY`, `GO_QUOTE_ENCRYPTION_KEY`,
`GO_LOCAL_INTERNAL_KEY`, and the existing LiveKit/bootstrap settings.
Account email and worker alerts reuse the existing Secret Manager resources
`BREVO_SMTP_LOGIN`, `BREVO_SMTP_KEY`, and `BREVO_SENDER_EMAIL`. Bind enabled
numeric versions to both services and grant runtime `secretAccessor`; do not
copy, re-enter or rotate the working credentials. Brevo SMTP uses port 587
with required STARTTLS and TLS 1.2 or later.

Optional bounds include `POLICY_CACHE_TTL_SECONDS`, `REQUEST_TIMEOUT_SECONDS`,
`DISPATCH_RADIUS_METERS`, `MAX_DISPATCH_RESULTS`, and `RATE_LIMIT_PER_MINUTE`.
`ADMIN_PORTAL_URL` configures notification links; `EMAIL_LOGO_URL` is optional.
Deployment preserves the current `https://voltrike-v2.web.app` links and its
`/images/appLogo.png` logo, independently of the Render browser origin.

See [DEPLOYMENT.md](DEPLOYMENT.md) for IAM, secret-version resolution,
Eventarc/Scheduler setup, client compatibility, one-sender cutover and rollback.
The hosted workflow deploys Go and Firebase rules/indexes, without deploying
Firebase Functions. Node remains development/build tooling for Firebase CLI
and the static Admin frontend. Device-local Rust stays inside Flutter.
