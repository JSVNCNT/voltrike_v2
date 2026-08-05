# VolTrike V2

VolTrike is a multi-platform tricycle booking and TODA operations system.
The existing Flutter passenger/driver experience and React Admin interface are
retained while the application authority moves to the Go V2 API.

## Runtime ownership

- **Flutter/Dart:** mobile and desktop presentation, platform permissions,
  secure Firebase token access, and durable client command replay.
- **React/TypeScript:** Render-hosted Admin presentation and typed V2 API
  client.
- **Go:** sole authority for bookings, dispatch, policy, driver sessions,
  safety, settlement, and Admin commands.
- **Node.js Functions:** post-commit integrations only: notifications, email,
  chat/call providers, and scheduled work driven by the transactional outbox.
- **Rust:** device-local geometry, navigation, PSGC lookup, and media work;
  never authoritative business state.
- **Firebase:** Auth, App Check, Firestore, Realtime Database, Storage, FCM,
  and Functions infrastructure.

## Repository layout

- `lib/` — Flutter application.
- `admin/` — React/Vite Admin, deployed as a Render Static Site.
- `services/voltrike-go/` — V2 API and Firebase adapters.
- `functions/` — Node notification, email, web-push, and scheduled integration
  workers; it contains no domain authority.
- `rust/` — Flutter Rust Bridge/native compute.
- `contracts/openapi.yaml` — V2 public API contract.
- `transition.md` — architecture decisions, migration status, cutover rules,
  validation gates, and deployment handoff.

## Deployment

Do not copy secret values into source control. Deploy the Go API with its
runtime service account and Secret Manager values, deploy Node Functions and
Firebase rules separately, then deploy Admin through Render with public build
variables only. The mobile capstone is not published to an app store: start
each passenger/driver phone with `flutter run`, the Cloud Run API URL, and its
registered App Check debug token. The command sequence and console settings are in
[services/voltrike-go/DEPLOYMENT.md](services/voltrike-go/DEPLOYMENT.md).

Before a cutover, review every unchecked validation/operator item in
[transition.md](transition.md). There is no V1 runtime fallback: deploy the Go
API, integration manifest, rules, Admin artifact, and matching Flutter source
checkpoint as one versioned environment after the defense flow passes.
