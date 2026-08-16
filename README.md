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
  reports, chat-safety incidents, settlements, and real-data operational
  dashboards.
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

The mobile design supports light and dark themes, high-contrast card and row
boundaries for LED/projector visibility, consistent passenger/driver navigation,
and a branded launch/session-restoration experience using the VolTrike identity.

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
GL for interactive operations maps. Its overview charts use real Firestore
booking and settlement records rather than placeholder datasets, with exact
values available for pointer and touch users.

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
| Firebase Storage | Registration documents and access-controlled ride-chat photos | Managed uploads, participant-only access, evidence preservation, and lifecycle expiry. |
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
| Sentry | Separate Flutter, admin, Go, and Functions error/trace projects | Correlates production failures with the deployed code release without placing private auth secrets in source. |
| Render Static Site | Hosting for the React administration portal | Simple Git-connected web deployment for operators. |
| Flutter Rust Bridge | Dart-to-Rust native bridge | Lets the Flutter client use Rust selectively without a separate mobile codebase. |

## Android baseline and device reach

VolTrike’s Android configuration uses:

| Configuration | Value | Meaning |
| --- | --- | --- |
| Minimum/required phone SDK | **API 24 — Android 7.0 Nougat** | Android 7.0 and later can install the APK. Phones below API 24 are unsupported. |
| Target SDK | **API 36 — Android 16** | The current Flutter Android toolchain applies Android 16 platform behavior and security expectations. |
| Compile SDK | **API 37 — Android 17** | Allows dependencies to compile against current Android APIs; it does **not** require the phone to run Android 17. |
| Java / Kotlin target | **Java 17** | Required by the current Android/Flutter dependency toolchain. |
| Verified physical device | **Android 16 — API 36, arm64** | The login, map, Navigation, location, and LiveKit/WebRTC startup path is tested on the connected SM A566B. |
| Additional test environment | **Android 17 — API 37 emulator** | Used for forward-platform compatibility checks; two real phones remain required for end-to-end ride and call testing. |

In short, the APK requires **Android 7.0/API 24 or newer**. Target SDK and
compile SDK describe how the app is built and governed by newer Android
behavior; they do not change the minimum installable Android version. Google
Play services, GPS, internet access, camera/microphone permissions, and enough
RAM/storage are still required for the corresponding VolTrike features.

Android 7+ is a broad practical baseline for a community mobility project and
includes many older Android devices. Real-world suitability still depends on
available RAM, GPS quality, network coverage, storage, microphone/speaker
hardware, and Google Play services; no app can make a severely constrained or
offline handset provide reliable live tracking or calls. The compiled Rust
module and selective caching help keep compute-heavy local work efficient, but
they do not replace those hardware and network requirements.

## Geofencing, route regulation, and booking dispatch

VolTrike uses two related but intentionally different kinds of operating-area
data:

| Policy data | What it does |
| --- | --- |
| TODA coverage geofences | Classify whether pickup and destination share a TODA, cross TODA boundaries, or sit outside configured coverage. This classification controls TODA dispatch preference and the configured outside-TODA fare surcharge. A coverage boundary is not automatically a no-service boundary. |
| Route-restriction polygons | Active `no_service_area`, `restricted_crossing`, and legacy `restricted_driving_area` polygons prohibit pickup, drop-off, and route travel through the polygon. |
| Prohibited-highway corridors | Active `prohibited_highway` centre lines plus their configured buffer and minimum aligned-travel distance prevent sustained travel along a prohibited highway. A short, approximately perpendicular road crossing is not treated as travelling on the highway. |

Passenger and driver maps render active restricted-access polygons with a red
fill/border and a **Restricted area** legend. That display and the Flutter/Rust
geometry pre-check provide immediate guidance, but they are not the security
boundary. The Go quote service repeats the checks using the current server
policy before it issues a usable quote:

1. Pickup and destination are rejected if either is inside an enforced
   restriction polygon.
2. Google Routes is requested with highway avoidance and alternative routes.
3. Every returned route polyline is decoded and rejected if it enters/crosses
   an enforced polygon or travels parallel inside a prohibited-highway corridor
   for at least the configured threshold.
4. The first fully permitted alternative is used. If Google reports that an
   avoidance preference may have been partially ignored but the route does not
   conflict with VolTrike's configured geometry, the app displays a warning to
   follow posted E-Trike restrictions.
5. If no permitted route remains, no quote is issued and the booking is
   blocked.

The encrypted quote token is valid for 75 seconds and is bound to the
authenticated user, exact ordered pickup/drop-off list, passenger count, baggage count,
authoritative route, fare, and policy revision. Booking creation rejects an
expired/reused token, changed inputs, or a policy revision that changed after
quotation. This prevents a modified phone from obtaining an allowed quote and
then substituting a restricted route.

### One or two drop-offs

A passenger may request one normal destination or add exactly one intermediate
drop-off followed by a final destination. Each leg is routed and checked
separately so alternative-route highway avoidance and every configured
restriction polygon still apply. The authoritative quote aggregates both legs'
distance and duration, applies the normal configured distance formula once to
the total distance, and adds the configurable `additionalDropoffFee` once.

The ordered stops, per-leg route snapshots, active stop index, and optional
120-character passenger note are stored on the booking and copied to driver
offers. The driver must confirm the intermediate stop before navigation moves
to the final stop, and the backend refuses payment progression until that first
drop-off is recorded. Legacy bookings without `routeStops` remain readable as
single-destination rides.

These controls are a strong technical aid to regulatory compliance, not a
claim that software alone guarantees compliance with every road rule. System
administrators must keep TODA polygons, no-service areas, restricted crossings,
and prohibited-highway corridors current with the responsible local authority.
Drivers must still follow road signs, enforcement instructions, and applicable
national/local law. GPS error, newly changed roads, incomplete policy geometry,
or a third-party route advisory can never be made impossible by an app.

### Who may create and receive a booking

A booking is created only when all of the following server-side checks pass:

- the caller has an authenticated, active passenger profile;
- coordinates are valid and a current matching quote token passes the route,
  fare, actor, input, expiry, and policy-revision checks;
- the request carries one to four passenger seats in total and at most one
  baggage unit; and
- the passenger does not already hold an active-booking lock.

A driver enters a dispatch candidate set only when all of these checks pass:

- a fresh server-owned online location is available (at most 35 seconds old,
  no more than 10 seconds in the future, and at most 100 metres reported
  accuracy);
- the driver is within the configured dispatch radius (5 km by default), has
  an active driver user profile, is TODA-approved, online, available, and has no
  current booking;
- the assigned TODA is active, the licence number is present and its expiry is
  still in the future; and
- the assigned vehicle is verified and has enough capacity for the requested
  passenger count.

The same eligibility, coverage, offer-round, expiry, and capacity conditions
are checked again inside the Firestore acceptance transaction. A stale client
therefore cannot accept merely because it received an earlier notification.

### Multiple bookings, matching, and priority

Each pending booking can be offered to as many as five eligible drivers in one
55-second offer round. Pending searches are retried by scheduled maintenance
and expire after five minutes if no driver is assigned. Many passengers can
search at the same time, and a currently free driver can briefly see offers
from more than one booking, but:

- one passenger can hold only one active booking;
- one driver can hold only one current booking; and
- one booking can be won by only one driver.

Acceptance is transactional. When drivers accept at nearly the same time, the
first valid Firestore transaction changes the booking from `pending` to
`driverAssigned` and locks that driver. Later acceptance attempts fail because
the booking/offer revision or driver availability is no longer valid.

Candidate selection uses the following order; the lower/higher preference is
shown explicitly:

1. **TODA service tier:** shared/primary TODA first, a secondary endpoint TODA
   second, and another active TODA as mutual-aid fallback third. If no endpoint
   belongs to configured coverage, any active TODA starts at the primary tier.
2. **Distance band:** the nearer 100-metre pickup-distance band first.
3. **Daily accepted assignments:** fewer awards on the current Manila calendar
   day first, to reduce repeated assignment to one driver.
4. **Smoothed reliability:** higher completion versus driver-fault cancellation
   history first.
5. **Smoothed rating quality:** higher rating with rating-count smoothing first.
6. **Exact pickup distance**, then stable driver ID as the final deterministic
   tie-breaker.

When more than five candidates exist, the batch normally follows that ordering
but reserves the nearest available secondary and mutual-aid candidate when
those tiers exist, preventing a dense primary TODA from completely starving
neighbouring service. Priority determines who receives the offer batch; it does
not silently assign a ride. Among offered and still-eligible drivers, the first
valid acceptance wins.

## Security and reliability design

- Firebase ID tokens identify users; App Check can attest client requests.
- The Go API, not a phone, issues and consumes quote tokens and performs booking
  state transitions.
- Booking commands carry revisions and idempotency controls to reduce duplicate
  or stale actions.
- Firestore, Realtime Database, and Storage rules enforce client access limits.
- Cloud Run uses a service account and Secret Manager configuration; secrets are
  not stored in the repository or in the Render public build.
- Flutter, admin, Go, and Firebase Functions report failures to separate Sentry
  projects so an incident can be attributed to the correct runtime and release.
- Outbox-driven Node functions perform side effects after committed data changes
  rather than making notifications, emails, or provider calls part of an
  irreversible booking transaction.
- LiveKit room credentials are server-issued for the specific booking call.
- Ride chat and voice calls are scoped to a specific booking and its passenger
  and driver; they are not global channels shared by unrelated rides.
- The call screen uses native WebRTC audio processing and earpiece/speaker
  routing. Nearby open speakerphones can still cause physical acoustic echo;
  earpieces, Bluetooth headsets, or distance between devices are the dependable
  mitigation.

## Ride communication, moderation, and retention

Ride chat is available only to the passenger and driver assigned to the
booking. The current client provides text messages, camera-only compressed
photos, accessible quick replies, delivery context, and light/dark presentation.
Normal chat photos are limited to 2 MB and automatically expire after two days
to control Storage cost and reduce unnecessary retention.

Chat moderation is server-side and configurable by a system administrator. The
`chatModerationRules` collection supports whole-word or substring matching,
aliases for shortened spellings, repeated-character matching, masking, flagging,
and blocking. The Flutter client never decides whether content is permitted.
Original text is available only as protected moderation evidence and is not
returned to the other ride participant.

Moderation incidents follow role scope:

- System administrators can review incidents involving passengers or drivers,
  manage moderation rules, hide/dismiss/resolve incidents, and apply account
  actions.
- A TODA administrator can review incidents caused by drivers assigned to that
  TODA. Passenger incidents remain system-admin only.
- When a reported chat photo still exists, the Go API copies it to a protected
  evidence path and issues only a short-lived signed URL to an authorized
  administrator. Resolving or dismissing the incident attempts to remove that
  retained copy.

Firestore TTL and Storage lifecycle policies provide the following operational
defaults:

| Data | Retention |
| --- | --- |
| Normal ride-chat photos | 2 days |
| Reported photo evidence fallback | 180 days, or earlier when the incident is closed |
| Ride chat/conversation records | 30 days through `purgeAt` |
| Booking-call records | 7 days through `purgeAt`; LiveKit audio is not recorded by VolTrike |
| Typing-state records | 24 hours through `purgeAt` |
| Moderation incidents | 180 days through `purgeAt` |

The policy definitions and setup instructions are in
[docs/data-retention.md](docs/data-retention.md),
[scripts/configure-chat-retention.ps1](scripts/configure-chat-retention.ps1),
and [storage.lifecycle.json](storage.lifecycle.json).

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
| `scripts/configure-chat-retention.ps1` | Enables Firestore TTL fields and applies the ride-chat Storage lifecycle policy. |
| `storage.lifecycle.json` | Deletes normal chat photos after 2 days and retained moderation evidence after 180 days. |
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

The current private-testing workflow targets newly rebuilt APKs. Remove obsolete
test APKs before installing a new build so every test phone uses the same
Flutter models, Go API contract, chat/call behavior, and Firebase rules. Legacy
APK compatibility is not part of the current capstone deployment target.
Uninstalling an APK does not delete its Firebase Authentication account or
authorized cloud records, so existing approved users can sign in again after
installing the current build.

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
flutter clean
flutter pub get
flutter run `
  --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app
```

### Google Navigation and LiveKit compatibility

The Android client intentionally uses `google_navigation_flutter` 0.9.4 with
the native Google Navigation SDK pinned to 7.6.1. Navigation SDK 7.7 and later
currently package `org.jni_zero` classes that collide with the WebRTC Android
artifact used by LiveKit. Do not remove this pin or suppress Gradle's
duplicate-class validation: doing so can make maps compile while breaking
ride-call JNI loading at runtime.

This large multi-dex application also requires R8 for debug and release builds.
Without the scoped rule in `android/app/proguard-rules.pro`, D8 can omit four
pre-obfuscated Navigation parcelable helpers (`internal.nc.a` through
`internal.nc.d`) even though the Navigation AAR contains them. The resulting
APK builds and installs but crashes when Flutter creates its first Navigation
map view. The R8 rule retains only that helper package.

The first Android build after `flutter clean`, dependency changes, or native
configuration changes may take several minutes while Flutter Rust Bridge, R8,
Navigation, and WebRTC are processed. Dart hot reload remains fast after
`flutter run` attaches. Before upgrading either Navigation or LiveKit, test on
physical phones that the passenger and driver maps both open and that calls
connect in both directions. A successful compatibility run should load both
`libgmm-jni.so` and `libjingle_peerconnection_so.so` without a fatal exception,
missing class, duplicate class, or JNI-link error.

### Deployment verification

The Cloud Run service exposes unauthenticated health endpoints while protected
application commands still require Firebase authentication:

```powershell
curl.exe https://voltrike-api-v2-327670792817.asia-southeast1.run.app/health
curl.exe https://voltrike-api-v2-327670792817.asia-southeast1.run.app/ready
```

After each backend/mobile update, smoke-test with separate passenger and driver
phones: sign in, quote, book, accept, track, exchange text/photo chat, place a
call in both directions, complete the cash ride, rate/report it, and confirm the
expected TODA/system-admin visibility. Health endpoints and automated tests do
not replace this two-device workflow check.

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
