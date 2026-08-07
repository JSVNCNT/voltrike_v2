# VolTrike

**VolTrike** is a clean community-mobility and e-tricycle booking system built
for passengers, drivers, Transport Network Vehicle Service (TNVS) operations,
and TODA administrators. It promotes electric tricycles (E-Trikes) as a more
sustainable, lower-emission community transport option through a single Flutter
mobile application, a web-based operations console, and a cloud-hosted,
server-authoritative backend.

The project is designed around a practical capstone goal: deliver a credible
end-to-end ride lifecycle—registration, approval, fare quotation, booking,
dispatch, live tracking, chat, voice calling, cash settlement, ratings,
reports, SOS, restrictions, and TODA operations—without requiring a separate
passenger and driver application package. By supporting the practical use and
coordination of E-Trikes, VolTrike also aims to contribute to **United Nations
Sustainable Development Goal 13: Climate Action**. It is also designed to
support alignment with applicable local E-Trike, TODA, and transport operating
requirements as those regulations and local policies evolve.

## Capstone information

| Item | Details |
| --- | --- |
| Project | VolTrike — Clean Community Mobility |
| Type | Capstone Project |
| Institution | University of Negros Occidental – Recoletos |
| Team | Tracelogy |
| Team member | Jose Vincent III Bayoguing |
| Team member | Denro Maban |

## What the system does

- Lets passengers register, verify their account, receive fare quotes, request
  rides, track a matched driver, chat, call, report issues, use SOS, pay cash,
  view receipts, and rate completed trips.
- Lets drivers submit registration documents, be reviewed by TODA operations,
  go online, receive and accept offers, navigate to pickup and destination,
  update trip stages, confirm cash receipt, view earnings, and communicate with
  the passenger.
- Lets system and TODA administrators manage drivers, ride operations, TODA
  coverage and zones, fares, commissions, route restrictions, safety incidents,
  reports, settlements, and operational dashboards.
- Keeps sensitive business decisions on the server while using realtime Firebase
  data for responsive tracking and operational views.

## Architecture at a glance

```text
Flutter passenger/driver client ── Firebase Auth + App Check ──┐
          │                                                     │
          │ REST commands / quotes / booking state              ▼
          └────────────────────────────────────────────── Go V2 API (Cloud Run)
                                                              │
                                                   authoritative transactions
                                                              │
      React + TypeScript admin (Render) ──────────────────────┤
                                                              ▼
     Firebase: Firestore • Realtime Database • Storage • FCM • Functions
                                                              │
                       Node.js Functions ── notifications, email, schedules,
                                             LiveKit token/integration work

Flutter Android client ── Flutter Rust Bridge ── Rust local compute
```

### Runtime ownership

| Layer | Authority and responsibility |
| --- | --- |
| Flutter/Dart | Client UI, accessibility, maps, permissions, local state, secure token attachment, device location, and realtime presentation. |
| Go | Source of truth for quotes, bookings, lifecycle transitions, dispatch, eligibility, policy, settlement, safety, and administrator commands. |
| Firebase | Managed identity, trusted client attestation, realtime stores, document storage, push delivery, serverless integration triggers, and security rules. |
| Node.js Functions | Non-authoritative integrations after committed domain changes: notifications, scheduled maintenance, branded email, web push, and provider orchestration. |
| React/TypeScript | Browser-based system/TODA administration with typed data normalization and API calls. |
| Rust | Fast, bounded, local computation only; it never decides authoritative fares, booking state, or permissions. |

This separation avoids an important ride-hailing failure mode: a phone cannot
become the authority for a fare, booking, or payment simply because it is
offline, stale, or modified. The Go API validates Firebase identity and App
Check before performing protected V2 operations.

## Languages and why each one is used

### Dart and Flutter — passenger and driver experience

Flutter is the main application layer in `lib/`. One codebase renders the
passenger and driver experiences and can target Android, iOS, web, Windows,
macOS, and Linux. Android is the primary tested and deployed mobile target.

It is responsible for the screens users see and touch: authentication,
registration, booking, driver availability, live ride tracking, receipts,
ratings, dashboards, chat, SOS, and voice-call controls. Riverpod provides
structured state management, `go_router` handles navigation, and Dart keeps the
UI and client models strongly typed while remaining productive for a small
capstone team.

**Why it benefits VolTrike:** one shared codebase reduces duplicated work and
keeps passenger and driver workflows visually consistent. Flutter also offers a
highly responsive interface on a wide range of Android phones while native
plugins provide access to GPS, camera, notifications, maps, audio, Bluetooth,
and secure storage.

### TypeScript and React (TSX) — administration portal

The `admin/` directory is a React 18 + TypeScript + Vite single-page web
application. TSX combines React components with TypeScript types, which is why
it is well suited to dense operations screens containing tables, forms, maps,
filters, role-aware actions, and charts.

The portal is hosted as a Render Static Site. It uses Firebase for session and
realtime reads, calls the Go V2 API for authoritative commands, and uses Mapbox
GL for interactive operations maps.

**Why it benefits VolTrike:** administrators need a desktop-friendly browser
workspace rather than a second mobile app. TypeScript helps protect the many
admin data shapes—drivers, TODAs, zones, restrictions, reports, settlements,
and booking operations—from common JavaScript runtime mistakes.

### Go — authoritative cloud backend

`services/voltrike-go/` is the public Go V2 API deployed to Google Cloud Run.
It exposes health/readiness endpoints and authenticated `/api/v2/` endpoints
for capabilities, profiles, quotes, bookings, lifecycle commands, driver
sessions, heartbeats, locations, and operations.

Go owns the rules that must not be trusted to a client: quote-token integrity,
fare calculation, booking revision checks, idempotency, driver eligibility,
dispatch selection, TODA policy, settlement, safety workflows, and
administrator mutations. It uses Firebase Admin/Google Cloud SDKs to transact
against Firestore and Realtime Database, and records outbox work for reliable
post-commit integrations.

**Why it benefits VolTrike:** Go produces small, fast, statically linked
services with predictable concurrency and low memory overhead—excellent for a
Cloud Run API handling many independent booking and location requests. Its
strict types and transaction-oriented service layer are a strong fit for money,
ride state, and multi-user consistency.

### JavaScript and Node.js — Firebase integration workers

The `functions/` directory uses Node.js 22 with Firebase Functions v2. These
functions are deliberately not the business authority. They react to already
committed events and perform integration work such as:

- Firebase Cloud Messaging and admin web-push token management;
- branded verification and password-reset email through SMTP/Nodemailer;
- LiveKit server-side token/integration support;
- Firestore outbox processing; and
- scheduled Go maintenance triggers.

**Why it benefits VolTrike:** Node.js is a natural fit for Firebase Functions
and third-party JavaScript SDKs. Keeping it behind the Go transaction boundary
makes asynchronous notifications and emails retryable without risking duplicate
fares or conflicting booking state.

### Rust — efficient device-local compute

The `rust/` crate is bridged to Flutter through `flutter_rust_bridge`. It is
used only where compact, predictable native computation materially helps the
mobile client:

- cached polygon/geofence and route-restriction conflict analysis;
- point-to-restriction proximity calculations;
- active-route navigation/GPS sample processing;
- Philippine Standard Geographic Code (PSGC) index lookup; and
- registration image preparation on supported native builds.

The Rust crate rejects unsafe code and enables release optimizations including
thin LTO and symbol stripping. Dart fallback paths remain available when a Rust
feature is unavailable or fails.

**Why it benefits VolTrike:** repeated geometry and route checks can be costly
on lower-powered phones. Rust performs this bounded work efficiently with strong
memory-safety guarantees, lowering Dart-side allocation and keeping the UI more
responsive. It is intentionally *not* used to replace LiveKit/WebRTC audio or
the cloud business backend: those systems already depend on mature platform
media and server infrastructure.

## Major APIs, SDKs, and services

| Service / SDK | Used for | Benefit to VolTrike |
| --- | --- | --- |
| Firebase Authentication | Email/password and Google sign-in identity | One trusted identity across mobile, admin, API, and rules. |
| Firebase App Check | Attestation token sent with protected API requests | Reduces abuse from unauthorised app clients. |
| Cloud Firestore | Profiles, booking views, operational documents, reports, outbox | Realtime document data with rules and transactional support. |
| Firebase Realtime Database | Low-latency driver/session/location presence | Responsive online-driver and trip-tracking updates. |
| Firebase Storage | Registration and vehicle documents/media | Managed, access-controlled uploads and retrieval. |
| Firebase Cloud Messaging | Mobile push notifications | Wake and notify drivers/passengers about ride events. |
| Firebase Functions v2 | Event-driven Node.js integrations and schedules | Serverless notifications, email, and maintenance processing. |
| Google Cloud Run | Go V2 API hosting | Public, scalable backend independent of the developer PC. |
| Google Secret Manager | Go runtime credentials and keys | Keeps server secrets outside source control. |
| Google Routes API | Server-side route distance/duration and fare inputs | Consistent quote computation without trusting client distances. |
| Google Navigation for Flutter | Driver turn-by-turn map experience | Native navigation-oriented driver workflow. |
| Geolocator / Geocoding | Device position and human-readable addresses | Pickup, destination, proximity, and live location features. |
| Mapbox GL | Web-admin maps and operational map layers | Flexible visualization of drivers, zones, and restrictions. |
| LiveKit Client + Server SDK | Secure in-ride voice rooms and tokens | Real-time passenger-driver calling without exposing provider credentials to clients. |
| WebRTC through LiveKit | Native audio capture/playback, echo cancellation, noise suppression, gain control | Reliable cross-device voice transport and platform audio handling. |
| Nodemailer / SMTP provider | Branded verification and password-reset email | Delivers app-branded account communications. |
| Render Static Site | Hosting for the React administration portal | Simple Git-connected web deployment for operators. |
| Flutter Rust Bridge | Dart-to-Rust native bridge | Lets the Flutter client use Rust selectively without a separate mobile codebase. |

## Android baseline and device reach

VolTrike’s Android configuration uses:

| Configuration | Value | Meaning |
| --- | --- | --- |
| Minimum SDK | **API 24** | Android 7.0 Nougat and later can install the Android build. |
| Compile SDK | **API 37** | Built against a current Android SDK for modern platform compatibility. |
| Java / Kotlin target | **Java 17** | Required by the current Android/Flutter dependency toolchain. |
| Capstone verification | Android 16 physical device and Android 17 emulator | Validated against current Android environments during development. |

Android 7+ is a broad practical baseline for a community mobility project and
includes many older Android devices. Real-world suitability still depends on
available RAM, GPS quality, network coverage, storage, microphone/speaker
hardware, and Google Play services; no app can make a severely constrained or
offline handset provide reliable live tracking or calls. The compiled Rust
module and selective caching help keep compute-heavy local work efficient, but
they do not replace those hardware and network requirements.

## Security and reliability design

- Firebase ID tokens identify users; App Check can attest client requests.
- The Go API, not a phone, issues and consumes quote tokens and performs booking
  state transitions.
- Booking commands carry revisions and idempotency controls to reduce duplicate
  or stale actions.
- Firestore, Realtime Database, and Storage rules enforce client access limits.
- Cloud Run uses a service account and Secret Manager configuration; secrets are
  not stored in the repository or in the Render public build.
- Outbox-driven Node functions perform side effects after committed data changes
  rather than making notifications, emails, or provider calls part of an
  irreversible booking transaction.
- LiveKit room credentials are server-issued for the specific booking call.
- The call screen uses native WebRTC audio processing and earpiece/speaker
  routing. Nearby open speakerphones can still cause physical acoustic echo;
  earpieces, Bluetooth headsets, or distance between devices are the dependable
  mitigation.

## Repository map

| Path | Contents |
| --- | --- |
| `lib/` | Flutter passenger/driver application, providers, repositories, UI, maps, and calls. |
| `admin/` | React/TypeScript/Vite system and TODA administrator portal. |
| `services/voltrike-go/` | Go V2 API, Firebase adapters, domain service, tests, and Cloud Run deployment material. |
| `functions/` | Node.js Firebase Function integration workers. |
| `rust/` | Rust native-compute crate exposed through Flutter Rust Bridge. |
| `rust_builder/` | Flutter package/build integration for the Rust crate. |
| `contracts/` | OpenAPI and service contracts. |
| `docs/` | QA, notifications, release, roadmap, and UI documentation. |
| `firestore.rules`, `database.rules.json`, `storage.rules` | Firebase access-control rules. |
| `transition.md` | Architecture migration/cutover history and handoff context. |

## Deployment model

The deployed system does **not** depend on a development computer remaining on:

- the Go API runs on Cloud Run;
- Firebase provides managed authentication, databases, storage, messaging, and
  functions;
- LiveKit Cloud provides the voice-room service; and
- the React admin portal is hosted on Render.

For capstone distribution, an Android debug APK can be built and shared directly
to compatible Android phones. This supports supervised testing and defense use;
it is not equivalent to a signed Play Store release. A production release would
add a release signing key, formal privacy/compliance review, production App
Check enforcement, monitored billing/quotas, incident processes, and full
device/network test coverage.

### Build a capstone Android APK

```powershell
flutter build apk --debug `
  --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app
```

The resulting APK is written to:

```text
build\app\outputs\flutter-apk\app-debug.apk
```

### Run on a connected device

```powershell
flutter run `
  --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app
```

For full infrastructure and environment setup, see
[services/voltrike-go/DEPLOYMENT.md](services/voltrike-go/DEPLOYMENT.md),
[docs/release_setup.md](docs/release_setup.md), and
[transition.md](transition.md).

## Development notes

- Never commit API keys, SMTP credentials, Firebase service-account files, or
  other secret values.
- Render/Vite variables beginning with `VITE_` are public build-time values;
  never put server secrets in them.
- The API base URL is supplied to Flutter as a build-time `dart-define` so APKs
  can call Cloud Run after being shared to another phone.
- Test booking flows with separate passenger and driver accounts, including
  registration, status approval, availability, quote, offer, lifecycle,
  settlement, receipt, rating, chat, call, SOS, report, and cancellation paths.
