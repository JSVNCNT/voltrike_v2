# VolTrike Android release setup

Add this to `android/local.properties` on each developer or CI machine:

```text
MAPS_API_KEY=your_restricted_google_maps_android_key
```

Restrict the key to the VolTrike Android package and signing certificate. Do not commit this file.

Before release, deploy the Go API and private integration worker to Google Cloud
Run, configure Firebase rules, and run `flutter test` plus a physical-device
booking smoke test. Follow the [hosted deployment guide](../services/voltrike-go/DEPLOYMENT.md)
for existing Secret Manager bindings, invocation IAM, Eventarc, scheduled
maintenance, and the coordinated migration from legacy Firebase Functions.

## Hosted backend and Firebase deployment

The Flutter app and Render Admin call the public `voltrike-api-v2` Go service.
The private `voltrike-integrations` Go service processes committed outbox events
and scheduled maintenance, including Brevo email and FCM delivery. Reuse the
existing Firebase project, users, push tokens, and working Brevo secrets; no
SMTP credential re-entry is required.

Deploy Go changes using the hosted workflow or the commands in the deployment
guide. Firebase deployment updates rules and indexes only:

```cmd
firebase deploy --only firestore,database,storage --project voltrike-v2
```

Node/npm remain build tools for the static Admin site and Firebase CLI. Hosted
backend execution is configured for Go on Cloud Run. The retained `functions/`
source is legacy migration/test material, and removing its deployment target
does not delete previously deployed Functions or schedules. Follow the guide's
coordinated one-sender cutover, preserve shared secrets and data, and verify
retirement separately before treating migration as complete.

## Private Quick Share APK

Keep App Check disabled for the privately distributed APK, Admin, and Go API
(`GO_REQUIRE_APP_CHECK=false`). The Go loader also defaults to `false`;
attestation remains configurable independently of Firebase identity and role
authorization. Build from the repository root:

```cmd
flutter build apk --debug --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app --dart-define=VOLTRIKE_ENABLE_APP_CHECK=false
```

Retain the existing Sentry Dart build defines when needed. Quick Share
`build/app/outputs/flutter-apk/app-debug.apk` to the test phones and install the
updated APK. No App Check debug-token registration is needed. Firebase sign-in,
server role checks, and database rules still apply.

## LiveKit voice calls

Keep the existing LiveKit server and TURN configuration. For a self-hosted
installation, run LiveKit plus Coturn. Bind the existing `LIVEKIT_API_KEY` and
`LIVEKIT_API_SECRET` Secret Manager resources to Cloud Run, and configure
`LIVEKIT_SERVER_URL` with the existing WebSocket URL. The deployment guide
also binds the existing `GOOGLE_ROUTES_API_KEY` for routing.

The Go API coordinates the call lifecycle through
`startBookingCall`, `respondBookingCall`, `createBookingCallToken`, and
`endBookingCall`. A recipient has 30 seconds to accept, and only an accepted
call receives a LiveKit token. The server sets a 30-minute accepted-call
deadline. The private worker's scheduled maintenance expires overdue ringing
records and marks accepted calls ended after that deadline. Maintenance updates
Firestore call state; it does not invoke a LiveKit room-deletion API. Firestore
remains the shared source of truth for passenger and driver call state. Never
place the LiveKit secret or a long-lived token in Flutter source.
