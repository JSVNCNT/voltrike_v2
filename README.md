# VolTrike

**VolTrike** is a Bacolod-focused community-mobility and electric-tricycle
booking system for passengers, drivers, System Administrators, and Tricycle
Operators and Drivers Association (TODA) Administrators. It supports E-Trike
and E-Tuktuk ride selection through one Flutter passenger/driver application,
a React administration portal, and a server-authoritative Go backend.

The implementation covers the end-to-end ride lifecycle—registration, approval,
fare quotation, booking,
dispatch, live tracking, chat, voice calling, cash settlement, ratings,
reports, SOS, restrictions, and TODA operations—without requiring a separate
passenger and driver application package. By supporting the practical use and
coordination of electric tricycles, VolTrike uses **United Nations Sustainable
Development Goal 13: Climate Action** as project context, not as evidence of
measured emissions savings. Configured route restrictions assist transport
operations; the application does not issue licences, franchises, government
approval, or Transport Network Vehicle Service (TNVS) accreditation. Land
Transportation Office (LTO) and local-government requirements remain external
to application authorization.

## Capstone information

| Item | Details |
| --- | --- |
| Project | VolTrike — Clean Community Mobility |
| Type | Capstone Project |
| Institution | University of Negros Occidental – Recoletos |
| Team | Tracelogy |
| Team member | Jose Vincent Bayoguing III |
| Team member | Denro S. Maban |

## What the system does

- Lets passengers register, verify their account, receive fare quotes, request
  rides, track a matched driver, chat, call, report issues, use SOS, pay cash,
  view receipts, and rate completed trips.
- Lets drivers submit registration documents, be reviewed by TODA operations,
  go online, receive and accept offers, navigate to pickup and destination,
  update trip stages, confirm cash receipt, view completed ride fares, and communicate with
  the passenger.
- Provides separate System Administrator and TODA Administrator permissions
  within one portal for driver review, ride operations, coverage, safety,
  reports, and count-only dashboards. City fare policy, route restrictions,
  and platform moderation rules remain System Administrator responsibilities.
- Keeps sensitive business decisions on the server while using realtime Firebase
  data for responsive tracking and operational views.

### Ride types and cash settlement

| Ride selection | API value | Passenger capacity |
| --- | --- | --- |
| E-Trike | `e_trike` | Up to 2 riders |
| E-Tuktuk | `electric_tuktuk` | Up to 4 riders, subject to the approved vehicle capacity |

The quote and booking include the selected ride type, total riders, and zero
or one baggage unit. Dispatch requires an approved vehicle of the same ride
type with sufficient capacity. E-Trike registration records two seats;
E-Tuktuk registration accepts three or four. Administrator-controlled fare
policy enables each ride type and configures its surcharge alongside distance,
additional-passenger, baggage, coverage, and additional-drop-off charges.

Payment is cash. The accepted quote supplies the fare snapshot, and final
cash confirmation creates a receipt for the full ride price. Current settlement
does not deduct TODA/platform commission or split driver net earnings. There
is no passenger digital wallet, subscription billing, or payment-gateway
checkout. Legacy commission fields in compatibility models are not active
fare or settlement features; the portal has no dedicated commission-management
page. Operational overview charts show counts, not revenue or payout totals.

### Account and administrator scope

| Role | Implemented scope |
| --- | --- |
| Passenger | Own profile, quote, booking, assigned-ride communication, cash payment, receipt review, ratings, and reports. |
| Driver | Registration evidence, approved vehicle and TODA membership, availability, eligible offers, assigned-trip progression, cash receipt, and own ride-fare summary. |
| TODA Administrator | Permitted drivers, rides, ratings, reports, coverage requests, and driver-caused safety/moderation incidents within the assigned association. |
| System Administrator | Platform-wide TODA review, city fare policy, coverage approval, route restrictions, moderation rules, permitted incidents, account actions, and audit review. |

Public registration does not create a System Administrator. The code retains
`developer_admin` as the internal identifier for that role. Protected portal
operations compare authenticated claims, active profile, role, and TODA scope;
showing or hiding a page is not the authorization boundary. Passenger-caused
incidents and other associations remain outside TODA Administrator authority.

Driver registration associates seven finalized evidence images with the
authenticated applicant and creates pending records. TODA review controls
approval; a submitted image is not automatic identity or licence verification.
TODA registration is a separate reviewed portal workflow.

## Architecture at a glance

```text
Flutter passenger/driver + React admin (Render)
          │ Firebase Auth ID tokens + HTTPS commands
          ▼
Public Go V2 API: voltrike-api-v2 (Cloud Run)
          ├── authoritative Firestore / Realtime Database transactions
          ├── Firebase Storage staging and media finalization
          ├── account email through Firebase action links + Brevo SMTP
          └── booking-scoped call authorization/tokens ── LiveKit

Committed Firestore outbox ── Eventarc ──┐
Cloud Scheduler ── IAM/OIDC ─────────────┤
                                       ▼
Private Go worker: voltrike-integrations (Cloud Run)
          ├── FCM / browser push and Brevo email delivery
          └── scheduled domain maintenance and outbox retry recovery

Flutter Android ── Flutter Rust Bridge ── Rust local compute
Node/npm ── Admin build, Firebase CLI, and retained legacy Functions tests
```

### Runtime ownership

| Layer | Authority and responsibility |
| --- | --- |
| Flutter/Dart | Client UI, accessibility, maps, permissions, local state, secure token attachment, device location, and realtime presentation. |
| Public Go API | Source of truth for quotes, bookings, lifecycle transitions, dispatch, eligibility, policy, settlement, safety, administrator commands, account email, and browser push registration. |
| Private Go worker | IAM-protected Eventarc and Scheduler receiver; delivers committed notification/email work and runs maintenance and retry recovery. |
| Firebase | Managed identity, realtime stores, document and object storage, FCM push delivery, configurable App Check, and security rules. |
| JavaScript/Node.js | Admin build and Firebase CLI tooling; retained legacy Functions source and regression helpers remain in `functions/`. |
| React/TypeScript | Browser-based system/TODA administration with typed data normalization and API calls. |
| Rust | Fast, bounded, local computation only; it never decides authoritative fares, booking state, or permissions. |

This separation avoids an important ride-hailing failure mode: a phone cannot
become the authority for a fare, booking, or payment simply because it is
offline, stale, or modified. The Go API validates Firebase identity before
protected V2 operations. App Check attestation is an additional,
deployment-controlled check. It is disabled in the private mobile/Admin setup
and the current Go deployment configuration; identity, account, role, TODA,
participant, and workflow checks still apply. See the configuration notes below.

## Languages and why each one is used

### Dart and Flutter — passenger and driver experience

Flutter is the main application layer in `lib/`. One codebase renders the
passenger and driver experiences. Android is the primary mobile target; other
platform folders do not establish equivalent feature coverage or device testing.

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

The portal has Render Static Site deployment configuration. It uses Firebase
for identity, polls Go read models for operational views, calls Go for
authoritative commands, and uses Mapbox GL for interactive maps. Go returns
role-scoped, count-only overview analytics across a 14-day window, including a
truncation indicator when query limits apply. The browser does not download
raw bookings and settlements to calculate financial charts.

**Why it benefits VolTrike:** administrators need a desktop-friendly browser
workspace rather than a second mobile app. TypeScript helps protect the many
admin data shapes—drivers, TODAs, zones, restrictions, reports,
and booking operations—from common JavaScript runtime mistakes.

### Go — authoritative cloud backend

`services/voltrike-go/` builds the public `voltrike-api-v2` API and the private
`voltrike-integrations` worker for Cloud Run. The API exposes health/readiness
endpoints and authenticated `/api/v2/` endpoints for capabilities, profiles,
quotes, bookings, lifecycle commands, driver sessions, heartbeats, locations,
and operations. Signed-out recovery uses `POST /auth/password-reset`.

Go owns the rules that must not be trusted to a client: quote-token integrity,
fare calculation, booking revision checks, idempotency, driver eligibility,
dispatch selection, TODA policy, settlement, safety workflows, and
administrator mutations. It uses Firebase Admin/Google Cloud SDKs to transact
against Firestore and Realtime Database, and records outbox work for reliable
post-commit integrations. Go also creates Firebase account action links and
sends branded account email through Brevo SMTP. Firebase Auth remains the
authority for verification and password reset.

The separate worker receives Firestore creation events for `outbox/{eventId}`
at `/events/outbox` through Eventarc. Cloud Scheduler invokes
`/tasks/maintenance` every minute with IAM/OIDC authentication. Durable event
and recipient/channel leases, delivery receipts, and scheduled retry recovery
support FCM, browser push, and Brevo email after a domain change commits.

**Why it benefits VolTrike:** Go produces small, fast, statically linked
services with predictable concurrency and low memory overhead—excellent for a
Cloud Run API handling many independent booking and location requests. Its
strict types and transaction-oriented service layer are a strong fit for money,
ride state, and multi-user consistency.

### JavaScript and Node.js — build tools and legacy integrations

Node/npm build the static React Admin and run Firebase CLI tooling. The
`functions/` directory retains the earlier Node.js 22 Firebase Functions v2
integrations, export manifest, policy helpers, and tests for migration context
and regression work. Its account email, push registration, outbox delivery,
and maintenance responsibilities have Go replacements in the current clients
and hosted deployment configuration.

`firebase.json` no longer declares a Functions deployment target, and the
hosted workflow does not deploy Node Functions. The retained exports are not
evidence that legacy cloud resources were deleted: sender, trigger, schedule,
and old-client retirement require the coordinated cutover in the deployment
guide. Go remains the authority for bookings, fares, settlement, and calls.

**Why it benefits VolTrike:** the JavaScript toolchain supports the browser
portal and existing regression helpers while the API and hosted integration
worker share the Go implementation and its transaction boundaries.

### Rust — efficient device-local compute

The `rust/` crate is bridged to Flutter through `flutter_rust_bridge`. It is
available for bounded native computation in the mobile client:

- cached polygon/geofence and route-restriction conflict analysis;
- point-to-restriction proximity calculations;
- active-route navigation/GPS sample processing;
- Philippine Standard Geographic Code (PSGC) index lookup; and
- registration image preparation on supported native builds.

The Rust crate rejects unsafe code and enables release optimizations including
thin LTO and symbol stripping. Dart fallback paths remain available when a Rust
feature is unavailable or fails.

Geometry, PSGC, and navigation modes inherit `VOLTRIKE_RUST_MODE`, which
defaults to `off`; proximity has its own default-off switch. These integrations
support `off`, `shadow`, and `on` modes. Registration image preparation uses
the separate `VOLTRIKE_IMAGE_ENGINE=auto` default: native-first on supported
builds with a Dart fallback. Native integration in the repository does not mean
every feature is enabled in a given APK.

**Why it benefits VolTrike:** repeated geometry and route checks can be costly
on lower-powered phones. Rust provides a memory-safe native path for this work;
actual performance gains require device benchmarks. It is intentionally *not*
used to replace LiveKit/WebRTC audio or
the cloud business backend: those systems already depend on mature platform
media and server infrastructure.

## Major APIs, SDKs, and services

| Service / SDK | Used for | Benefit to VolTrike |
| --- | --- | --- |
| Firebase Authentication | Email/password and Google sign-in identity | One trusted identity across mobile, admin, API, and rules. |
| Firebase App Check | Configurable client attestation; disabled for the private APK/Admin and current Go deployment | Can add an abuse-control layer when configured; identity and role checks remain required. |
| Cloud Firestore | Profiles, booking views, operational documents, reports, outbox | Realtime document data with rules and transactional support. |
| Firebase Realtime Database | Low-latency driver/session/location presence | Responsive online-driver and trip-tracking updates. |
| Firebase Storage | Registration documents and access-controlled ride-chat photos | Managed uploads, participant-only access, evidence preservation, and lifecycle expiry. |
| Firebase Cloud Messaging | Mobile and administrator browser push, sent by the Go worker | Notify participants and scoped administrators about committed events. |
| Google Cloud Run | Public Go V2 API, private Go integration worker, and separate synthetic-data job | Hosted application and integration processing independent of the developer PC. |
| Eventarc / Cloud Scheduler | Firestore outbox events and minute-by-minute IAM/OIDC maintenance calls | Invoke the private Go worker without a public worker endpoint. |
| Firebase Functions v2 (legacy) | Retained Node integration source and tests | Migration reference; excluded from the current hosted deployment workflow. |
| Google Secret Manager | Go runtime credentials and keys | Keeps server secrets outside source control. |
| Google Routes API | Server-side route distance/duration and fare inputs | Consistent quote computation without trusting client distances. |
| Google Navigation for Flutter | Driver turn-by-turn map experience | Native navigation-oriented driver workflow. |
| Geolocator / Geocoding | Device position and human-readable addresses | Pickup, destination, proximity, and live location features. |
| Mapbox GL | Web-admin maps and operational map layers | Flexible visualization of drivers, zones, and restrictions. |
| LiveKit / Go-issued tokens | Secure in-ride voice rooms authorized by Go | Real-time passenger-driver calling without exposing server credentials to clients. |
| WebRTC through LiveKit | Native audio capture/playback, echo cancellation, noise suppression, gain control | Reliable cross-device voice transport and platform audio handling. |
| Brevo SMTP through Go | Branded verification, password-reset, TODA-status, and safety email | Delivers account and operational communications using existing server-side secrets. |
| Sentry | Flutter, Admin, Go API, and Go worker DSN/release configuration | Attributes errors and traces to the configured runtime and release; the worker DSN can reuse an existing project. |
| Render Static Site | Hosting for the React administration portal | Simple Git-connected web deployment for operators. |
| Flutter Rust Bridge | Dart-to-Rust native bridge | Lets the Flutter client use Rust selectively without a separate mobile codebase. |

## Android baseline and device reach

VolTrike’s Android configuration uses:

| Configuration | Value | Meaning |
| --- | --- | --- |
| Minimum/required phone SDK | **API 24 — Android 7.0 Nougat** | Android 7.0 and later can install the APK. Phones below API 24 are unsupported. |
| Target SDK | `flutter.targetSdkVersion` | Inherited from the installed Flutter Android toolchain rather than hardcoded in the application Gradle file. |
| Compile SDK | **API 37 — Android 17** | Allows dependencies to compile against current Android APIs; it does **not** require the phone to run Android 17. |
| Java / Kotlin target | **Java 17** | Required by the current Android/Flutter dependency toolchain. |

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

1. Pickup and every ordered drop-off are rejected if any is inside an enforced
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
authenticated user, exact ordered pickup/drop-off list, selected ride type,
passenger count, baggage count,
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

The note is a booking-creation input, not part of the fare quote request. Go
validates its length and applies moderation before accepting it.

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
- the selected ride type is enabled, the request fits its rider limit
  (E-Trike: 1–2; E-Tuktuk: 1–4), and baggage is at most one unit; and
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
- the assigned vehicle is verified, matches the requested ride type, and has
  enough capacity for the requested passenger count.

The same eligibility, coverage, offer-round, expiry, and capacity conditions
are checked again inside the Firestore acceptance transaction. A stale client
therefore cannot accept merely because it received an earlier notification.

The normal lifecycle is `pending` → `driverAssigned` → `driverArriving` →
`passengerOnBoard` → `paymentConfirmation` → `completed`. Cancellation is
restricted by role and current state; an intermediate stop is recorded before
payment progression. Client state does not bypass Go command validation.

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
- Flutter, Admin, the Go API, and the Go worker have Sentry runtime/release
  configuration so failures can be traced to the appropriate service. The
  worker DSN may fall back to the existing Functions or Go project.
- The private Go worker performs outbox-driven effects after committed data
  changes. Durable leases and delivery receipts support retries and reduce
  repeated provider sends; provider acceptance is not proof of device receipt
  or inbox delivery.
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
Normal chat photos are limited to 2 MB and have a two-day lifecycle policy
to control Storage cost and reduce unnecessary retention.

Chat moderation is server-side and configurable by a system administrator. The
`chatModerationRules` collection supports whole-word or substring matching,
aliases for shortened spellings, repeated-character matching, masking, flagging,
and blocking. The Flutter client never decides whether content is permitted.
Original text is available only as protected moderation evidence and is not
returned to the other ride participant.

This is deterministic rule matching, not an artificial-intelligence or
natural-language-understanding moderation service.

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

Expiry depends on deploying and enabling the corresponding Firestore
time-to-live (TTL) and Storage lifecycle policies. Merely storing `purgeAt`
does not enable automatic deletion, and scheduled cleanup is not an exact
instant-deletion guarantee.

## Repository map

| Path | Contents |
| --- | --- |
| `lib/` | Flutter passenger/driver application, providers, repositories, UI, maps, and calls. |
| `admin/` | React/TypeScript/Vite system and TODA administrator portal. |
| `services/voltrike-go/` | Public Go V2 API, private integration worker, account email, Firebase adapters, tests, synthetic-data job, and Cloud Run deployment material. |
| `functions/` | Retained legacy Node.js Functions, policy helpers, and regression tests; not a target of the current hosted workflow. |
| `rust/` | Rust native-compute crate exposed through Flutter Rust Bridge. |
| `rust_builder/` | Flutter package/build integration for the Rust crate. |
| `contracts/` | OpenAPI and service contracts. |
| `docs/` | QA, notifications, release, roadmap, and UI documentation. |
| `scripts/configure-chat-retention.ps1` | Enables Firestore TTL fields and applies the ride-chat Storage lifecycle policy. |
| `storage.lifecycle.json` | Deletes normal chat photos after 2 days and retained moderation evidence after 180 days. |
| `firestore.rules`, `database.rules.json`, `storage.rules` | Firebase access-control rules. |
| `transition.md` | Architecture migration/cutover history and handoff context. |

## Deployment model

The configured hosting model does **not** require a development computer to
remain on:

- the public Go API and private Go integration worker are configured for Cloud Run;
- Firebase provides managed authentication, databases, storage, and messaging;
- Eventarc delivers outbox creation events, and Cloud Scheduler invokes private
  worker maintenance every minute;
- LiveKit Cloud provides the voice-room service; and
- the React admin portal is hosted on Render.

For capstone distribution, an Android debug APK can be built and shared directly
to compatible Android phones. This supports supervised testing and defense use;
it is not equivalent to a production-signed Play Store release. The current
Android release configuration also uses debug signing. Release readiness
requires a dedicated signing key, privacy/compliance review, App Check policy,
monitored billing/quotas, incident processes, and device/network test coverage.
Repository configuration is not proof that a hosted release is healthy or that
all infrastructure policies are deployed.

The hosted workflow deploys Go services and Firebase rules/indexes. It does
not delete legacy Functions or auxiliary jobs. Complete and verify the
one-sender cutover before enabling the new worker alongside existing cloud
resources; retain shared users, tokens, data, and Secret Manager resources.

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

The public Cloud Run API exposes unauthenticated health endpoints while
protected application commands still require Firebase authentication:

```powershell
curl.exe https://voltrike-api-v2-327670792817.asia-southeast1.run.app/health
curl.exe https://voltrike-api-v2-327670792817.asia-southeast1.run.app/ready
```

After each backend/mobile update, smoke-test with separate passenger and driver
phones: sign in, quote, book, accept, track, exchange text/photo chat, place a
call in both directions, complete the cash ride, rate/report it, and confirm the
expected TODA/system-admin visibility. Health endpoints and automated tests do
not replace this two-device workflow check.

For current Go infrastructure and environment setup, see
[services/voltrike-go/DEPLOYMENT.md](services/voltrike-go/DEPLOYMENT.md).
[transition.md](transition.md) and older release/roadmap documents retain
migration context; compare historical instructions with active code and export
manifests before using them.

### Configuration boundaries

| Setting | Current behavior |
| --- | --- |
| `VOLTRIKE_API_BASE_URL` | Flutter build-time override; the client also has a configured Cloud Run default. |
| `VOLTRIKE_ENABLE_APP_CHECK` | Mobile default `false` for privately shared builds. |
| `VOLTRIKE_REQUIRE_EMAIL_VERIFICATION` | Mobile default `false`; this does not disable account, role, ownership, or server-side workflow checks. |
| `GO_REQUIRE_APP_CHECK` | Server enforcement is independent of the mobile switch. The loader defaults to `false`, and the private deployment explicitly keeps it disabled. |
| `GO_INTEGRATION_WORKER` | `false` selects the public API; `true` exposes only worker event/maintenance routes and health/readiness routes. Worker network access is restricted through Cloud Run IAM. |
| `GO_NOTIFICATIONS_ENABLED` | Defaults to `true`; set `false` while staging the replacement sender. The deployment workflow also pauses its maintenance schedule while this switch is off. |
| `VOLTRIKE_RUST_MODE` | Default `off` for inherited native migration modes; feature-specific overrides select rollout behavior. |
| `VOLTRIKE_IMAGE_ENGINE` | Default `auto`, with supported native image preparation and Dart fallback. |

Configure Firebase project resources, Android Maps credentials, Go credentials,
allowed web origins, and provider integrations before running the relevant
workflow. Quote encryption keys, LiveKit server credentials, internal maintenance
keys, and email-provider secrets belong in server configuration—not Flutter
defines or public Vite variables. Changing a Flutter define requires a rebuilt
APK; enabling client attestation also requires compatible server configuration.

## Code and verification guide

Use active implementation and tests to resolve differences with older diagrams,
roadmaps, compatibility fields, or deployment notes:

| Area | Source |
| --- | --- |
| Ride types and client capacity | [ride_type.dart](lib/data/models/ride_type.dart) |
| Authoritative fare and policy logic | [core.go](services/voltrike-go/internal/core/core.go) |
| Booking commands and quote consumption | [domain.go](services/voltrike-go/internal/app/domain.go) |
| Driver eligibility and dispatch | [dispatch.go](services/voltrike-go/internal/firebase/dispatch.go) |
| Commission-free settlement regression | [settlement_test.go](services/voltrike-go/internal/firebase/settlement_test.go) |
| Public and internal API routing | [http.go](services/voltrike-go/internal/app/http.go), [OpenAPI](contracts/openapi.yaml) |
| Portal role routing and pages | [App.tsx](admin/src/App.tsx) |
| Server-scoped count analytics | [admin_analytics.go](services/voltrike-go/internal/firebase/admin_analytics.go) |
| Go account email and push registration | [auth_integrations.go](services/voltrike-go/internal/firebase/auth_integrations.go) |
| Go outbox delivery and retries | [notifications.go](services/voltrike-go/internal/firebase/notifications.go), [notifications_delivery.go](services/voltrike-go/internal/firebase/notifications_delivery.go) |
| Private Eventarc/Scheduler handlers | [integrations_http.go](services/voltrike-go/internal/app/integrations_http.go) |
| Retained legacy Node exports | [index.js](functions/index.js) |
| Private mobile security defaults | [mobile_security_config.dart](lib/core/config/mobile_security_config.dart) |
| Native rollout modes | [rust_migration_mode.dart](lib/core/native/rust_migration_mode.dart) |

The public API groups cover capabilities, the current profile, quotes,
bookings and commands, driver sessions/heartbeats/location, and named
`/api/v2/operations/{operation}` actions. Operations include registration,
media finalization, chat/calls, ratings, reports, safety, and scoped
administration. Internal `/v1/` maintenance and compatibility routes are not a
mobile fallback around V2 authentication. The separate private worker registers
`/events/outbox` and `/tasks/maintenance`; those paths are not public API routes.

Run checks from the indicated directories after installing the matching
dependencies and toolchains:

| Directory | Checks |
| --- | --- |
| Repository root | `flutter pub get`, `flutter analyze`, `flutter test` |
| `services/voltrike-go/` | `go test ./...` |
| `functions/` (retained legacy helpers) | `npm ci`, `npm test` |
| `admin/` | `npm ci`, `npm run build` (TypeScript and production bundle) |
| Repository root | `cargo test --manifest-path rust/Cargo.toml` |

The repository declares Dart `^3.11.0`, Go `1.26.0`, Node.js `22` for the
retained Functions package, and Rust `1.97.1` as the crate minimum. Check the
manifests and lockfiles when updating dependencies. Native builds also need the
Android and Rust tooling.
Automated checks do not establish live deployment, legal approval, measured
performance, or end-to-end device compatibility. For manual mobile coverage,
see [docs/mobile_qa_checklist.md](docs/mobile_qa_checklist.md).

## Development notes

- Never commit API keys, SMTP credentials, Firebase service-account files, or
  other secret values.
- Render/Vite variables beginning with `VITE_` are public build-time values;
  never put server secrets in them.
- Use the API base URL build-time override when targeting a different backend;
  shared APKs otherwise retain the configured client default.
- Test booking flows with separate passenger and driver accounts, including
  registration, status approval, availability, quote, offer, lifecycle,
  settlement, receipt, rating, chat, call, SOS, report, and cancellation paths.
