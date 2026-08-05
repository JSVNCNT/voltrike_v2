# VolTrike Full Rewrite Transition

> Status: architecture decision complete; implementation has not started.
>
> Last updated: 2026-08-05.
>
> This document is the source of truth for the rewrite. Every implementation
> session must read it first and update the progress checklist and handoff
> section before stopping.

## 1. Read this first

VolTrike has no active users. It is a capstone application, its current code is
committed, and test data does not require a production migration. The rewrite
may therefore break the old callable API and reset development data.

The rewrite is deliberately radical at the architecture boundary:

- Go becomes the sole authoritative backend.
- Node.js becomes a small Firebase and external-integration worker.
- Rust becomes a portable device-local compute kernel.
- Flutter and React/TypeScript remain presentation clients.
- Firebase Auth, Firestore, Realtime Database, Storage, FCM, and the existing
  third-party integrations remain infrastructure.

This is not a visual redesign and not a database-platform migration. Existing
Flutter screens, admin presentation, maps, navigation, call, chat, and safety
features should be retained unless they prevent the new boundary.

This document supersedes the architectural ownership described in:

- go_todo.md
- services/voltrike-go/README.md
- services/voltrike-go/DEPLOYMENT.md
- NEXT.md

Those files remain useful as historical and operational references until they
are updated or removed. If they conflict with this file, this file wins.

## 2. Rewrite premise and constraints

### Confirmed assumptions

- There are no active users.
- No installed client version needs backward compatibility.
- Existing Firebase data is development/capstone data.
- A source rollback point exists in Git.
- The user-visible application already works and should remain recognizable.
- The first defense-ready vertical slice is expected to take focused hours.
  Completing every feature-parity and multiplatform gate in this document may
  take several focused sessions or days.
- Android is the current strongest platform, but the new boundaries must allow
  iOS, web, and desktop capabilities without another backend rewrite.

### What may break

- Firebase callable names and payloads.
- Existing development Firestore and RTDB document shapes.
- Legacy decimal money fields.
- Legacy parsing aliases and compatibility helpers.
- Node-to-Go feature modes and proxy endpoints.
- Existing direct client mutation paths.

### What must stay working

- Firebase sign-in and role checks.
- Passenger quote and booking creation.
- Driver online state, dispatch, acceptance, and ride lifecycle.
- Fare, TODA, restriction, settlement, and commission behavior.
- Passenger/driver live tracking.
- Chat, call, notifications, reports, safety, rating, and receipts.
- Admin review, search, policy, safety, and reporting workflows.
- Current map and navigation experience on supported platforms.

### Scope guardrails

Do not add these during the rewrite:

- PostgreSQL/PostGIS unless a measured Firestore limitation blocks completion.
- Kubernetes or a fleet of microservices.
- Go embedded in Flutter.
- Rust on the server through cgo.
- A new Flutter state-management framework.
- A new map/navigation provider.
- A complete UI redesign.
- A second authoritative writer or a dual-write migration path.

The hours-scale first slice is plausible only because the existing UI,
Firebase project, third-party services, and proven policy code are being
reused. Do not represent full feature parity as an hours-only guarantee.

## 3. Baseline and rollback

### Source baseline

- Branch before this document: main
- Remote: origin/main
- Baseline commit:
  3419d76dd9c5cd14c9cc6fe65de904de65c1496d
- Baseline subject: Commit cache from go
- Baseline date: 2026-08-05
- Worktree was clean before transition.md was created.

The preferred implementation branch is:

~~~powershell
git switch -c rewrite/go-authority
~~~

Commit this transition file as the first rewrite checkpoint. Before switching
branches, checkpoint intentional work and verify git status. Untracked files
follow branch switches, and dirty tracked changes may block a switch.

Do not use a destructive reset as the normal rollback. After the rewrite work
is safely checkpointed, source rollback is:

~~~powershell
git switch main
~~~

The rewrite branch should keep the old implementation available until the new
end-to-end flow passes. Git is the fallback; the running application will not
contain a legacy backend mode. Returning to baseline main also restores its
tracked environment/cache problems, so it is an emergency source baseline,
not the desired final repository state.

### Baseline verification evidence

Before this document was written:

- Node Functions tests: 93 passed.
- Rust tests: 25 passed.
- Selected Flutter bridge/parity tests: 26 passed.
- Targeted Go core/application tests passed.
- Admin TypeScript compilation passed.
- A full Flutter test run exceeded the available three-minute window and is
  unverified rather than failed.
- A full Go test run previously exceeded a short timeout; targeted packages
  passed and the full suite remains a rewrite gate.

### Cloud rollback is separate

Git rollback does not roll back:

- Cloud Run revisions.
- Firebase Functions deployments.
- Firestore/RTDB/Storage rules.
- Firestore indexes.
- IAM bindings and secrets.
- Mutated cloud data.

Until the rewrite passes locally, use the Firebase Emulator Suite and local Go
service. Before any real deployment:

1. Record the current Cloud Run revision and Functions release.
2. export or otherwise back up any Firebase data worth preserving;
3. save the current rules, indexes, environment, and IAM configuration;
4. deploy the public API under a new service name, voltrike-api-v2;
5. keep preceding compatible V2 revisions available for traffic rollback; and
6. do not reset cloud data without an explicit target review.

The old private voltrike-go service is not a compatible V2 API rollback: its
routes and IAM model differ. Initial-cutover rollback requires the entire
baseline set: Functions, rules/indexes, Admin artifact/hosting configuration,
Flutter artifact, and compatible seeded/data snapshot.

No destructive Firebase reset is authorized by this document alone.

## 4. Current architecture snapshot

The current repository contains approximately:

- 343 Dart files and about 45,000 lines of Dart.
- An approximately 8,000-line functions/index.js with 74 Firebase exports,
  including roughly 63 callable functions.
- A React admin App.tsx of roughly 1,600 lines.
- An admin-api.ts of roughly 600 lines.
- A working private Go quote/routing/dispatch service.
- A working Flutter Rust Bridge crate for geometry, route state, PSGC lookup,
  health, and registration-image processing.

Current runtime flow:

~~~text
Flutter/Admin
   |
Firebase callable Functions and direct Firebase access
   |
Large Node authoritative backend
   |
Private Go read/compute service

Flutter Android
   |
Rust compute bridge with Dart fallbacks
~~~

Important current problems:

- Node owns almost every domain and integration in one deployment unit.
- Go is useful but subordinate and duplicates some Node decisions.
- Go dispatch can truncate candidates before Node applies every final
  availability/TODA/eligibility filter.
- Go policy-cache invalidation is process-local.
- Flutter repositories and providers construct Firebase dependencies directly.
- Driver location and presence use singleton driver paths, so two phones can
  overwrite or disconnect each other.
- Booking operation IDs are not backed by a durable device outbox.
- Several Flutter navigation routes depend on in-memory route extras.
- Rust packaging is effectively Android-only and web generation is disabled.
- Admin pages poll, join, or scan data in the browser.
- Contracts are manually reproduced across Dart, JavaScript, Go, and Rust.
- App Check is not currently installed/enforced across the clients and Go API.
- There is no tracked CI workflow.
- functions/.env.voltrike-v2 is tracked and must not be copied into this file.
- 247 Go build-cache artifacts are tracked under
  services/voltrike-go/.tmp_go_cache.
- Root and admin Render manifests duplicate hosting intent while Firebase
  Hosting is also configured for admin/dist.

## 5. Final architecture

~~~text
                         Firebase Auth + App Check
                                   |
Flutter passenger/driver ----------+
React admin ------------------------+---- HTTPS /api/v2
Future web/desktop clients ---------+           |
                                                v
                                   voltrike-api-v2
                                  public network service
                                      Go modular monolith
                                      sole domain authority
                                  commands, queries, transactions,
                                  dispatch, sessions, policy,
                                  admin, reconciliation
                                                |
                     +--------------------------+-------------------------+
                     |                          |                         |
                 Firestore                    RTDB                    Storage
              durable state/outbox     live session locations      user media
                     |
              transactional outbox
                     |
               Node.js Functions
           FCM, web push, email, chat,
           Firebase/event integrations
                     |
             IAM/OIDC job invocation
                     |
             voltrike-worker-v2
           private worker entry point

On each Flutter device:

Flutter UI and platform plugins
             |
        Rust device core
 geometry, GPS/route state, PSGC,
 restrictions, and media processing
~~~

### Request flow

1. Flutter or Admin obtains a Firebase ID token and App Check token.
2. The client sends a versioned HTTPS request to Go.
3. Go validates identity, App Check, role, payload, session lease,
   idempotency key, and expected aggregate revision.
4. Go performs the authoritative Firestore transaction.
5. The same transaction writes a domain event/outbox record.
6. Node claims each integration delivery independently and processes it at
   least once. Consumers must tolerate duplicate and out-of-order delivery.
7. Clients observe durable state through authorized Firebase reads or Go query
   endpoints.
8. Live location is submitted to Go under a session lease and observed through
   session-scoped RTDB records.

### Why direct HTTPS

Standard HTTPS makes Go useful as the real backend and allows Flutter, React,
web, desktop, and future clients to share one API. Firebase callable Functions
are no longer the application API.

The public API service must be network-invokable at Cloud Run IAM because an
end-user Firebase token is not a Cloud Run IAM credential. Every non-health
endpoint must nevertheless fail closed in Go middleware without valid Firebase
authentication. App Check is mandatory
for supported production Android, iOS, and web clients. A desktop platform
without a supported attestation provider must remain disabled for production
mutations or use an explicit, narrowly scoped capstone/development exception;
it must never become silently unauthenticated.

## 6. Permanent language ownership

| Concern | Owner | Notes |
| --- | --- | --- |
| UI, accessibility, navigation | Flutter/Dart | No business-state authority |
| Mobile platform APIs | Flutter/Dart | Maps, notification UI, permissions, secure token access |
| Admin presentation | React/TypeScript | Typed Go API; no browser-side joins |
| Backend commands and queries | Go | Sole domain authority |
| Firestore transactions | Go | One writer for domain aggregates |
| Fare, dispatch, restriction policy | Go | Server-authoritative |
| Driver device/session leases | Go | Prevent concurrent-phone corruption |
| Reconciliation and projections | Go | Invoked by Go worker or authenticated scheduled hook |
| FCM, email, web push, Firebase hooks | Node.js | Integration effects only |
| Device geometry and route state | Rust | Local/advisory, never authoritative |
| GPS filtering and compression | Rust | Coarse bridge calls |
| Image preparation | Rust | File-to-file APIs |
| Device durable command outbox | Flutter/Dart | Local persistence and network replay |
| Auth, durable data, live data, files | Firebase | Infrastructure, not domain authority |

### Non-negotiable invariants

1. Only Go changes booking, dispatch, policy, driver-session, settlement, or
   safety aggregate state.
2. Node never decides a domain transition.
3. Flutter and Admin never directly write authoritative domain documents.
4. Direct Storage upload is permitted only to user-scoped staging paths; Go
   finalizes the associated domain record.
5. Rust never owns authentication, HTTP, Firebase, authoritative fare, or
   booking decisions.
6. Every domain command is idempotent. High-frequency location and heartbeat
   PUTs use lease generation plus a monotonic sample sequence.
7. Every mutable domain aggregate has a numeric revision.
8. Every asynchronous post-commit integration effect caused by a domain
   transition originates from a durable outbox event. Synchronous dependencies
   such as Google Routes and LiveKit token issuance have explicit timeout and
   failure behavior instead.
9. No in-memory cache is required for correctness.
10. There is no V1 runtime fallback or dual writer.

## 7. Retain, rewrite, and delete map

### Retain and adapt

- lib/features presentation screens and widgets.
- Riverpod and go_router.
- Google Maps/Navigation and location plugins.
- Firebase Auth, read listeners, Storage, and FCM clients.
- Admin React components, CSS, and login flow.
- Current Go quote, Google Routes, geometry, Firebase-store, and HTTP
  foundations.
- Current Rust geometry, navigation, PSGC, health, and image algorithms.
- Node policy tests and parity fixtures as rewrite oracles.
- Firestore rules/indexes as references.
- Existing Firebase Emulator scripts.

### Rewrite

- Flutter repositories behind one typed VoltrikeApi boundary.
- Admin data access behind one typed API client.
- Go into transport, application, domain, and adapter packages.
- Booking, dispatch, fare, restriction, settlement, safety, and admin authority
  in Go.
- Driver presence/location around explicit session leases.
- Node Functions into small integration modules.
- Firestore/RTDB/Storage rules for the new ownership model.
- Rust bridge into coarse portable APIs.
- Navigation inputs so routes restore from IDs rather than in-memory extras.
- Deployment documentation and root README.

### Delete after the new path passes

- Domain implementation in functions/index.js.
- functions/go-service-client.js.
- GO_QUOTE_MODE and GO_DISPATCH_MODE.
- Flutter GoServiceBridge callable proxy.
- Legacy callable wrappers and error mappings.
- Duplicate client-side authoritative fare and lifecycle decisions.
- Legacy data parsers and schema aliases.
- Direct client booking, driver-state, policy, and admin mutations.
- Obsolete admin legacy components.
- One of the duplicate admin deployment paths.
- services/voltrike-go/.tmp_go_cache from version control.
- Tracked environment files and any committed secret-like values.

Do not delete the old policy implementations until their Go replacements pass
the same fixtures and end-to-end flow. They are temporary test oracles, not a
runtime fallback.

## 8. Contracts

Create contracts/ before porting more behavior.

Minimum contents:

~~~text
contracts/
  openapi.yaml
  schemas/
    command-envelope.schema.json
    error.schema.json
    booking.schema.json
    booking-event.schema.json
    driver-session.schema.json
    quote.schema.json
    device-registration.schema.json
    message.schema.json
    media.schema.json
    admin.schema.json
  fixtures/
    fare/
    booking/
    dispatch/
    restrictions/
~~~

Use JSON over HTTPS. Do not introduce GraphQL or Protobuf during this rewrite.

### Command envelope

~~~json
{
  "commandId": "uuid",
  "deviceId": "stable-installation-id",
  "sessionId": "active-session-id-or-null",
  "expectedRevision": 4,
  "payload": {}
}
~~~

Rules:

- commandId is mandatory for every domain mutation.
- expectedRevision is mandatory when modifying an existing domain aggregate.
- Create operations may omit expectedRevision.
- Driver heartbeat/location PUTs use leaseGeneration and sampleSequence instead
  of durable command receipts for every GPS sample.
- Offline replay never includes heartbeat, location, or expiring dispatch
  offers.
- Money is an integer number of Philippine centavos.
- Coordinates use latitude/longitude decimal degrees.
- Server time is authoritative.
- Stored records contain schemaVersion: 2.
- Identifiers are opaque strings with one validation rule per type.
- Null, missing, and empty values have explicitly different meanings.

### Success response

~~~json
{
  "data": {},
  "revision": 5,
  "requestId": "server-correlation-id"
}
~~~

### Error response

~~~json
{
  "error": {
    "code": "STALE_REVISION",
    "message": "The booking changed. Refresh and retry.",
    "retryable": false,
    "details": {}
  },
  "requestId": "server-correlation-id"
}
~~~

Stable error categories must include:

- UNAUTHENTICATED
- FORBIDDEN
- INVALID_ARGUMENT
- NOT_FOUND
- CONFLICT
- STALE_REVISION
- SESSION_EXPIRED
- POLICY_CHANGED
- OUTSIDE_COVERAGE
- RATE_LIMITED
- DEPENDENCY_UNAVAILABLE
- INTERNAL

STALE_REVISION, POLICY_CHANGED, and semantic CONFLICT errors require a refetch,
requote, or user reconciliation rather than blind automatic retry. Automatic
retry is reserved for transient network/dependency failures and is always
bounded.

### Initial API groups

System:

- GET /healthz
- GET /readyz
- GET /api/v2/capabilities
- GET /api/v2/me
- PUT /api/v2/me/profile
- POST /api/v2/driver-applications
- POST /api/v2/driver-applications/{applicationId}/documents
- POST /api/v2/toda-applications
- POST /api/v2/toda-applications/{applicationId}/documents
- PUT /api/v2/devices/{deviceId}
- DELETE /api/v2/devices/{deviceId}
- POST /api/v2/media/finalize

Passenger/booking:

- POST /api/v2/quotes
- POST /api/v2/bookings
- GET /api/v2/bookings/{bookingId}
- POST /api/v2/bookings/{bookingId}/commands
- POST /api/v2/bookings/{bookingId}/messages
- POST /api/v2/bookings/{bookingId}/messages/{messageId}/read
- POST /api/v2/bookings/{bookingId}/ratings
- POST /api/v2/bookings/{bookingId}/reports

Driver:

- POST /api/v2/driver/sessions
- POST /api/v2/driver/sessions/{sessionId}/takeover
- POST /api/v2/driver/sessions/{sessionId}/heartbeat
- DELETE /api/v2/driver/sessions/{sessionId}
- PUT /api/v2/driver/sessions/{sessionId}/location
- PUT /api/v2/driver/sessions/{sessionId}/availability
- GET /api/v2/driver/offers
- POST /api/v2/driver/offers/{offerId}/commands

Calls, safety, and settlement:

- POST /api/v2/bookings/{bookingId}/calls
- POST /api/v2/calls/{callId}/commands
- POST /api/v2/safety-incidents
- POST /api/v2/safety-incidents/{incidentId}/commands
- POST /api/v2/settlement-disputes

Admin:

- Query and command routes under /api/v2/admin.
- Separate handlers for TODAs, users, drivers, policies, zones,
  restrictions, violations, reports, safety, bookings, settlement, and
  metrics.
- Role/TODA assignment is an explicit Go admin command.
- Cursor pagination is server-owned.
- Search and joins are server-owned.

The exact OpenAPI file is the contract. This list defines required coverage,
not final route spelling.

### Quote integrity

Booking creation must consume a Go-signed, short-lived quote token bound to the
actor, normalized inputs, route result, fare, policy revisions, and expiry.
The client cannot replace distance, polyline, fare, or policy data. Go either
verifies and consumes that token once or fully recomputes the quote during the
booking transaction. Policy revision alone is not proof of quote integrity.

## 9. V2 data model

Firestore collections:

~~~text
users/{uid}
device_registrations/{deviceId}
driver_profiles/{driverId}
driver_applications/{applicationId}
driver_sessions/{sessionId}
todas/{todaId}
toda_applications/{applicationId}
fare_policies/{policyId}
route_restrictions/{restrictionId}
bookings/{bookingId}
booking_events/{eventId}
booking_messages/{messageId}
message_receipts/{receiptId}
dispatch_offers/{offerId}
command_receipts/{commandId}
calls/{callId}
media/{mediaId}
reports/{reportId}
safety_incidents/{incidentId}
settlements/{settlementId}
outbox/{eventId}
outbox_deliveries/{deliveryId}
admin_views/{viewId}
~~~

RTDB:

~~~text
driverLocations/{driverId}/{sessionId}
driverPresence/{driverId}/{sessionId}
dispatchCells/{cellId}/{driverId}
bookingTyping/{bookingId}/{uid}
~~~

Collection names may be adjusted while writing contracts, but the ownership
and session-scoping requirements may not.

Chat message creation/read receipts go through Go. Participant-scoped typing
indicators may use direct ephemeral RTDB writes as a documented infrastructure
exception; they never affect booking authority and expire quickly.

### Booking lifecycle

Retain the current user-visible state sequence to avoid rewriting screens:

~~~text
pending
  -> driverAssigned
  -> driverArriving
  -> passengerOnBoard
  -> paymentConfirmation
  -> completed

pre-onboard states may transition to cancelled under explicit policy
~~~

Each booking stores at least:

- schemaVersion
- revision
- passengerId
- driverId when assigned
- todaId and policyRevision
- integer fare snapshot
- normalized pickup/drop-off coordinates and labels
- current status
- lifecycle timestamps
- settlement snapshot
- createdAt and updatedAt

Only Go interprets allowed transitions.

### Driver session lease

Each session stores:

- sessionId
- driverId
- deviceId
- platform and app version
- leaseGeneration
- status
- heartbeatAt
- expiresAt
- takeover metadata

The driver profile points to the active session ID. Location, availability, and
driver lifecycle commands are rejected when their session is not the active
lease.

Location and presence samples contain sessionId, leaseGeneration,
sampleSequence, observedAt, receivedAt, accuracy, and expiresAt. A takeover is
an atomic Firestore transaction. Go rejects old generations and out-of-order
samples. Every dispatch-cell entry also contains the session/generation,
sequence, updatedAt, and expiry so cleanup from a stale phone cannot remove a
newer's projection.

### Device registration

The device registration API binds FCM/web-push tokens to the authenticated UID,
installation ID, platform, app version, token type, created/updated time, and
revocation state. Go owns registration changes. Node reads only the tokens
needed for an integration event and marks invalid provider tokens for cleanup.
An installation ID is advisory metadata, not proof of identity.

### Command receipts

Receipts are for durable domain commands, not telemetry. Each receipt stores:

- actor UID
- command type
- canonical payload hash
- original result or stable error
- createdAt and expiresAt

Reusing a commandId with another actor, command type, or payload hash is
rejected. Firestore TTL removes expired receipts after the required retry and
audit window.

### Transactional outbox

Every Go domain transaction that requires a side effect also creates:

~~~json
{
  "eventId": "uuid",
  "type": "booking.assigned",
  "aggregateId": "booking-id",
  "aggregateRevision": 5,
  "payload": {},
  "createdAt": "server timestamp",
  "consumers": ["fcm"]
}
~~~

Each consumer/provider has a separate delivery record containing eventId,
consumer, lease owner/expiry, attempts, nextAttemptAt, lastError, terminal
status, provider idempotency key when supported, and expiresAt. A Firestore
trigger claims work transactionally, retries transient failures, and throws
when the platform should retry. A scheduled reconciler recovers expired claims
and moves exhausted deliveries to a dead-letter state.

Node may update integration-delivery metadata, but it may not change the
originating domain aggregate. FCM/email/web-push delivery is at-least-once:
collapse/idempotency keys are used where supported, while notification UX and
consumers remain duplicate tolerant.

## 10. Component rewrite plan

### Go

Target package boundaries:

~~~text
services/voltrike-go/
  cmd/api/
  cmd/worker/
  internal/domain/
    booking/
    dispatch/
    driver/
    fare/
    policy/
    safety/
    settlement/
  internal/application/
    commands/
    queries/
  internal/ports/
  internal/adapters/
    firebase/
    googlemaps/
    livekit/
  internal/transport/http/
~~~

Implementation requirements:

- One composition root.
- Pure domain packages do not import Firebase or HTTP.
- Firestore transaction adapters implement application ports.
- Middleware verifies Firebase ID tokens, App Check, roles, request size,
  content type, deadlines, and request IDs.
- Dispatch applies all eligibility filters before result truncation.
- Policy caches are keyed by durable policy revision.
- Concurrent cache misses use single-flight behavior.
- Retain the proven signed quote-token concept or use a single-use stored quote;
  policy revision alone does not prevent client tampering.
- Idempotency receipts are durable.
- Readiness verifies required Firebase/secret configuration.
- Structured logs include request ID, actor ID, command ID, aggregate ID, and
  duration without logging tokens or private payloads.

Port proven JavaScript policy behavior using the existing test fixtures. Do not
translate functions/index.js line by line.

Go owns call authorization/lifecycle and synchronous LiveKit token issuance.
Node only delivers call invitations/notifications asynchronously.

The canonical role, suspension, and TODA membership live in Firestore and are
re-read by Go for sensitive commands. Firebase custom claims are cached routing
or UI hints, not authority. A Go admin command changes canonical membership and
emits an event for a privileged integration worker to reconcile custom claims;
clients refresh their ID token after a role change.

Admin search uses bounded prefix queries and materialized normalized search
keys/projections. A bounded capstone-only scan must be explicitly documented;
moving a scan from the browser to Go does not make it indexed.

### Node.js

Node remains a permanent small integration layer because Firebase triggers and
provider SDK integrations are useful there.

Target responsibilities:

- Outbox-created trigger.
- FCM passenger/driver/admin notifications.
- Admin web push.
- Branded email.
- Chat-message notification.
- Storage finalization hooks if needed.
- Scheduled trigger that invokes an IAM-protected Go job endpoint when Cloud
  Scheduler is not configured directly.

Node must not contain:

- Booking state transitions.
- Fare calculation.
- Driver selection or dispatch scoring.
- Restriction decisions.
- Settlement decisions.
- Admin authorization policy beyond validating an integration invocation.

functions/index.js should become an export manifest that imports small modules.
Internal job invocations target the separate IAM-private voltrike-worker-v2
service and verify Google OIDC audience plus the allowed service-account
identity.

### Rust

Keep one Flutter Rust Bridge crate during the hours-scale rewrite; reorganize
modules before considering a multi-crate workspace.

Target modules:

~~~text
rust/src/
  api/
  core/
    geometry.rs
    navigation.rs
    gps.rs
    restrictions.rs
    psgc.rs
    protocol.rs
  device/
    media.rs
~~~

Requirements:

- Coarse calls, not chatty per-point FFI.
- No network, Firebase, or auth dependencies.
- No authoritative server policy.
- No secrets or long-lived auth tokens stored in Rust.
- Android and iOS native targets are first-class.
- Android is the locally verified native target.
- iOS must be source-ready and then validated through macOS CI or a device
  environment; this Windows workspace cannot certify an iOS build.
- Desktop targets are enabled only after the mobile bridge passes.
- WASM is optional for web/admin previews.
- Dart fallback remains only where a target cannot load Rust.
- Geometry/navigation/restriction fixtures must match across Rust and Go where
  they express the same deterministic operation.

Do not move ordinary Flutter networking or screen state into Rust.

### Flutter

Target layers:

~~~text
lib/
  app/
  features/
  domain/
  application/
  infrastructure/
    api/
    firebase_reads/
    local/
  platform/
    maps/
    navigation/
    location/
    notifications/
    native_core/
~~~

Requirements:

- One typed VoltrikeApi interface.
- One authenticated HTTP client that attaches Firebase ID and App Check tokens.
- Repositories depend on interfaces rather than constructing Firebase
  dependencies directly.
- Commands go only to Go.
- Firebase listeners are read-only projections.
- Storage uploads use scoped staging paths and Go finalization.
- Driver location uses a session ID and lease.
- A Dart-owned local outbox queues domain commands while offline and replays
  them idempotently through the authenticated API client.
- Queue entries are bound to Firebase UID and device installation, expire by
  command type, never cross logout/account switches, and exclude telemetry and
  offers. Sensitive payloads use OS-protected local storage where available.
  Stale revision or policy errors surface reconciliation UI instead of looping.
- Route restoration is ID-based, not dependent on state.extra.
- Platform capability checks live behind adapters, not in feature widgets.
- The UI may optimistically preview a Rust result but server state always wins.

Preserve the current screens and Riverpod approach. Do not spend the rewrite
budget moving widgets solely for aesthetic architecture.

### Admin React/TypeScript

Requirements:

- Preserve working components and styles.
- Replace admin-api.ts with a typed API client.
- All mutations, search, joins, pagination, and dashboard aggregation go
  through Go.
- Use Firebase only for authentication, App Check, approved read-only live
  projections, and web-push token acquisition.
- Remove five-second full-page reloads.
- Choose Firebase Hosting as the sole admin deployment owner for this rewrite.
- Remove Render manifests only after Firebase Hosting and the API route work.
- Configure a Firebase Hosting /api/** rewrite to voltrike-api-v2 before the
  existing SPA catch-all rewrite. Flutter may use the direct API origin;
  browser Admin uses the same-origin Hosting route.
- Split App.tsx by feature only after functional API cutover; it is not a
  blocker for the first vertical slice.

Media finalization verifies the authenticated staging owner/path, object
generation, size, content type, and content hash. Go moves or copies the object
to a server-controlled final path, writes the domain reference, and schedules
cleanup for abandoned staging objects. A client-supplied download URL is never
trusted as proof of ownership.

## 11. Execution order and progress checklist

Implementation should happen on one rewrite branch in this order.

### Phase 0 — baseline and hygiene

- [x] Record the source rollback commit.
- [x] Select the final ownership model.
- [x] Create transition.md.
- [ ] Create the rewrite branch (blocked because this workspace exposes .git as
  read-only; implementation is proceeding on main with the baseline commit
  unchanged).
- [ ] Add the correct ignore rule for the Go build cache.
- [ ] Remove tracked Go cache artifacts from the rewrite branch.
- [ ] Stop tracking environment files.
- [ ] Rotate any committed secret-like value and move it to Secret Manager.
- [ ] Choose and document local emulator environment values.
- [ ] Add minimal CI for Go, Node, Rust, Admin, and Flutter static/unit gates.

Checkpoint: repository is clean apart from intentional rewrite files and no
secret value is introduced into documentation or logs.

### Phase 1 — contracts

- [x] Create contracts/openapi.yaml.
- [ ] Define the command, response, and error envelopes.
- [ ] Freeze booking status and transition fixtures.
- [ ] Freeze fare, dispatch, restriction, and settlement fixtures.
- [ ] Define V2 Firestore and RTDB documents.
- [ ] Define Firebase ID token, App Check, and role semantics.
- [ ] Configure Android, Apple, and web App Check providers plus local debug
  tokens; client token acquisition is implemented, while Firebase Console
  registration/debug-token setup remains an operator task.
- [ ] Generate or implement typed Dart and TypeScript clients.

Checkpoint: Go, Dart, and TypeScript can compile against the same contract.

### Phase 2A — Go defense vertical slice

- [ ] Reorganize the Go service by domain/application/adapter layers.
- [x] Add public authenticated API middleware.
- [ ] Add Firebase Auth and App Check verification tests, including rejection
  and local-emulator-only bypass tests.
- [ ] Implement durable policy revisions.
- [x] Port authoritative fare and quote creation through /api/v2/quotes.
- [x] Port coverage/restriction validation required by quoting and booking.
- [x] Port booking creation and core lifecycle transactions.
- [ ] Port core cash completion and settlement snapshot calculation.
- [x] Implement idempotency receipts and aggregate revisions for the V2
  booking/session slice.
- [x] Implement driver sessions, heartbeat, takeover, and session-scoped
  location.
- [x] Fix dispatch filtering before candidate truncation.
- [x] Implement the minimal admin booking query needed to inspect the defense
  ride through `/api/v2/admin/bookings` (with an invisible callable fallback
  until the API base URL is configured).
- [x] Write transactional booking outbox events.
- [x] Add readiness and public API health endpoints.

Checkpoint: Go tests and direct API tests complete quote, booking, dispatch,
acceptance, ride lifecycle, and settlement snapshot without Flutter or Node
authority. This is the hours-scale vertical slice.

### Phase 3 — Node integration worker

- [x] Create small integration modules.
- [x] Consume and deduplicate booking outbox events.
- [x] Add `GO_V2_AUTHORITY=on` notification cutover guard; it disables the
  legacy booking lifecycle notifier while preserving the existing dispatch
  compatibility path until Go dispatch is migrated.
- [ ] Send FCM, web push, and branded email.
- [ ] Preserve required chat and Storage hooks.
- [ ] Route scheduled domain work to authenticated Go endpoints.
- [ ] Verify Node cannot mutate booking/domain state.
- [ ] Reduce functions/index.js to an export manifest.

Checkpoint: integration effects are produced from Go events, claims are
recoverable after worker failure, and replay cannot duplicate domain state.
Provider deliveries are at-least-once and duplicate tolerant.

### Phase 4 — Flutter switch

- [x] Add authenticated VoltrikeApi client.
- [x] Replace quote, booking-create, core lifecycle, driver session, and
  location mutations.
- [x] Route booking offer decline, settlement dispute, and driver receipt
  acknowledgement through the Go command endpoint.
- [ ] Make Firebase domain listeners read-only.
- [x] Add device/session lease lifecycle.
- [x] Make locations session-scoped.
- [x] Route driver online/offline and logout cleanup through the session
  controller without changing the existing driver screens.
- [ ] Add durable command replay.
- [ ] Replace in-memory-only route inputs with IDs.
- [x] Preserve current passenger and driver screens; the cutover is transport
  and authority-only.

Checkpoint: passenger and driver complete the core defense lifecycle through
Go.

### Phase 5 — Admin switch

- [ ] Add the typed Go API client.
- [ ] Replace N+1 and scan-based reads with Go queries.
- [ ] Replace polling with projection reads or scoped refresh.
- [ ] Route defense-critical admin mutations through Go.
- [ ] Build and deploy from Firebase Hosting configuration.

Checkpoint: the full admin defense flow works without authoritative browser
writes.

### Phase 6 — Rust portability and useful activation

- [ ] Consolidate coarse geometry/navigation/restriction APIs.
- [ ] Add GPS filtering and trace batching.
- [ ] Keep image processing file-to-file.
- [ ] Enable and verify Android release builds.
- [ ] Prepare iOS source/configuration and validate it through macOS CI or a
  device environment.
- [ ] Prepare desktop targets.
- [ ] Decide whether WASM adds enough capstone value.
- [ ] Retain target-specific Dart fallback only where necessary.

Checkpoint: Rust is required for meaningful native work, not included merely
as a demo health call.

### Phase 7 — remaining feature parity

- [ ] Port restriction and violation authority to Go.
- [ ] Port settlement, commission, and dispute authority to Go.
- [ ] Port safety incidents, reports, and ratings to Go.
- [ ] Port call lifecycle and synchronous LiveKit authorization to Go.
- [ ] Route chat sends/reads through Go and notify through the outbox.
- [ ] Complete onboarding, driver/TODA applications, and role reconciliation.
- [ ] Complete admin search, pagination, commands, and projections.
- [ ] Split App.tsx by feature after the functional cutover.
- [ ] Complete notification, email, and web-push integration coverage.

Checkpoint: every retained feature has one Go authority and the full
passenger/driver/admin defense run passes.

### Phase 8 — rules, cleanup, and end-to-end verification

- [ ] Lock client writes to authoritative Firestore collections.
- [ ] Lock RTDB location writes behind the chosen Go path.
- [ ] Update Storage staging/finalization rules.
- [ ] Delete legacy Node domain code.
- [ ] Delete Node-to-Go proxy modes.
- [ ] Delete legacy Flutter callable bridges.
- [ ] Delete stale schema parsers and duplicate admin code.
- [ ] Replace the generic root README with a project overview.
- [ ] Update deployment documents.
- [ ] Update transition.md with final evidence.

Checkpoint: all definition-of-done items pass and the source tree contains one
authority for each concern.

## 12. Security requirements

- Verify Firebase ID tokens on every protected Go endpoint.
- Verify App Check for supported production platforms. Configure Android
  attestation, Apple attestation, web reCAPTCHA/Enterprise, token refresh, and
  local debug tokens.
- Any emulator bypass requires explicit emulator hosts, a demo Firebase project,
  and loopback/local configuration. Go and Node must abort startup if emulator
  mode points at the production project.
- Resolve current roles server-side; never trust a role from a request body.
- Treat Firestore role, suspension, and TODA membership as canonical. Custom
  claims are cached hints and must be reconciled after canonical changes.
- Recheck TODA/admin scope inside every Go command and sensitive query.
- Reject unknown JSON fields and oversized bodies.
- Apply request deadlines and panic recovery.
- Restrict CORS to the selected admin origin.
- Use Secret Manager for Google Routes, LiveKit, email, and encryption secrets.
- Use separate least-privilege service accounts for Go and Node.
- Replace broad Viewer/runtime roles with explicit required permissions.
- Never log bearer tokens, App Check tokens, password links, private documents,
  or full location histories.
- Use user-scoped Storage staging paths and server-controlled final records.
- Make command receipts and event delivery safe under retry.
- Apply durable per-UID/session/route quotas to quote, location, safety, and
  admin-search endpoints; in-memory limits alone are not multi-instance safe.
- Bound Cloud Run maximum instances and budget for the capstone.
- Limit live-location reads to booking participants/authorized admins and apply
  retention TTL to location history, receipts, outbox, and delivery records.

## 13. Multiplatform capability plan

Do not require identical capabilities on every platform.

| Capability | Android | iOS | Web | Desktop |
| --- | --- | --- | --- | --- |
| Passenger booking | Required | Source-ready; macOS gate | Target | Target |
| Driver booking | Required | Source-ready; device gate | Not promised | Not promised |
| Background driver GPS | Required | External device gate | Unsupported | Unsupported |
| Embedded turn-by-turn | Required | External device gate | Fallback | Fallback |
| Push notifications | Required | External device gate | Admin/passenger web | Adapter-dependent |
| Rust compute | Native | Source-ready; macOS gate | Optional WASM/Dart | Native |
| Live reads | Firebase | Firebase | Firebase | Firebase/Go |
| Commands | Go HTTPS | Go HTTPS | Go HTTPS | Go HTTPS |

The Flutter app must render a clear capability fallback instead of importing an
unsupported plugin from shared feature code.

## 14. Validation gates

### Static and unit commands

From the repository root:

~~~powershell
flutter analyze
flutter test --no-pub
npm.cmd --prefix functions test
npm.cmd --prefix admin run build
~~~

From services/voltrike-go:

~~~powershell
go test ./...
go test -race ./...
go vet ./...
go build .
~~~

From rust:

~~~powershell
cargo fmt --check
cargo clippy --all-targets -- -D warnings
cargo test --locked
~~~

The full Flutter suite may take more than three minutes. A timeout is not a
test failure; rerun with an adequate limit and record the final result.

### Required scenarios

- [ ] Register/sign in as passenger, driver, TODA admin, and developer admin.
- [ ] Quote and create a valid covered booking.
- [ ] Reject invalid coverage/restriction/policy revision.
- [ ] Dispatch only currently eligible drivers.
- [ ] Race two eligible driver accepts and produce exactly one winner.
- [ ] Replay create/accept/transition/payment commands without duplicate state.
- [ ] Reject a stale expectedRevision.
- [ ] Driver arrives, boards passenger, drops off, confirms cash, and completes.
- [ ] Passenger rates and receives the final receipt.
- [ ] Settlement and commission values are correct.
- [ ] Chat and call flows work.
- [ ] Safety incident/report workflows work.
- [ ] Node produces notifications from outbox events.
- [ ] Replaying an outbox event does not duplicate domain state; delivery
  claims, collapse/idempotency keys, and UX minimize provider duplicates.
- [ ] Admin search, pagination, approval, restriction, safety, and metrics work.
- [ ] A second phone cannot update a driver session without takeover.
- [ ] A taken-over/stale phone cannot erase the active phone's location.
- [ ] App restart restores active booking by ID.
- [ ] Offline command survives restart and replays once.
- [ ] Go restart does not lose correctness or require warm process state.
- [ ] Firebase rules reject direct authoritative client writes.

Testing without multiple physical phones:

- Use two isolated Flutter emulator processes for passenger and driver.
- Use two isolated driver sessions for takeover/race tests.
- Use the Firebase Emulator Suite for data and Functions.
- Use a cloud device farm for Android/iOS packaging and push checks.
- Perform at least one real-device or cloud-physical pass for background GPS,
  navigation, battery behavior, and push delivery before the capstone defense.

## 15. Deployment and data reset

Local validation comes first:

1. Start Firebase emulators with the demo project.
2. Run Go locally against emulator configuration.
3. Run Node integration Functions locally.
4. Run Admin in emulator mode.
5. Run passenger and driver clients as isolated processes.
6. Complete every required scenario.

Only then:

1. Deploy voltrike-api-v2 as network-invokable, with Go middleware enforcing
   Firebase Auth and supported-platform App Check.
2. Deploy Node integration Functions and the Go outbox worker.
3. Deploy Firestore indexes/rules plus RTDB and Storage rules.
4. Configure the existing Render Admin service with the public V2 API origin
   and App Check reCAPTCHA site key; retain its SPA rewrite.
5. Build fresh Flutter artifacts with the V2 API origin.
6. Verify health, readiness, auth rejection, App Check rejection, and the
   explicit cutover configuration before serving the new release.

Because there are no users, development collections may be reset instead of
backfilled, but only after the exact Firebase project and collection targets
are reviewed. Preserve Firebase Auth accounts if they are useful for the
capstone unless a reset is explicitly requested.

If deployment fails:

- For a post-cutover V2 failure, route traffic only to a known compatible V2
  revision.
- For initial V1-to-V2 rollback, redeploy the baseline Functions,
  rules/indexes, Hosting/Admin artifact, and Flutter artifact together.
- Restore emulator/test data from seed scripts or the recorded export.
- Switch source back to main.

## 16. Definition of done

The rewrite is complete only when:

- Go is the only authoritative domain writer.
- Flutter and Admin use the V2 HTTPS API for every domain mutation.
- Node contains integrations but no domain decisions.
- Rust performs meaningful native geometry/navigation/media work.
- Driver sessions prevent accidental concurrent-phone ownership.
- Every durable domain command is idempotent and revision checked.
- Every asynchronous post-commit integration effect is backed by a durable
  event and duplicate-tolerant delivery.
- No secret-like value or build cache remains tracked in the rewrite HEAD; any
  previously committed secret-like value has been rotated. Git-history
  rewriting is a separate explicit operation.
- Firebase rules enforce the ownership model.
- Passenger, driver, TODA admin, and developer-admin scenarios pass.
- Android builds locally; iOS is source-ready and is compiled through a
  recorded macOS CI/device gate when that infrastructure is available.
- All language test gates pass.
- Root README and deployment documentation describe the final system.
- transition.md contains final evidence and no unfinished required checkbox.

## 17. Intentionally deferred

These may follow the capstone rewrite:

- PostgreSQL/PostGIS.
- Splitting the Go modular monolith into services.
- Full driver operation on web/desktop.
- Rust WASM if the admin preview does not need it.
- Store-release signing and production-scale SRE work.
- Advanced analytics warehouse.
- Multi-region deployment.

## 18. Decision log

### D-001 — Breaking rewrite

Accepted. There are no active users, so no callable compatibility, rolling
schema migration, or active-booking drain is required.

### D-002 — Go authority

Accepted. Go owns all server domain decisions and transactions.

### D-003 — Node integration worker

Accepted. Node remains permanently for Firebase/event/provider integration but
does not own business state.

### D-004 — Rust device kernel

Accepted. Rust owns portable device-local compute, not networking, local
command persistence, or server authority.

### D-005 — Firebase retained

Accepted. Auth, Firestore, RTDB, Storage, and FCM remain to keep the rewrite
hours-scale and capstone-relevant.

### D-006 — Existing UI retained

Accepted. Flutter and Admin presentation are adapted, not rebuilt.

### D-007 — Controlled compatibility fallback

Accepted. The Git baseline and cloud revision history are the rollback. The
new Go runtime is the target authority; the Admin booking adapter may use its
legacy callable only when `VITE_VOLTRIKE_API_BASE_URL` is unset. Remove that
fallback after emulator cutover verification.

### D-008 — Admin hosting

Accepted for the rewrite: Render Static Site is the Admin frontend owner.
Firebase remains the identity, data, and integration platform; it does not
need to serve the Admin bundle. Configure the Render rewrite rule
`/* -> /index.html` and set `VITE_VOLTRIKE_API_BASE_URL` at build time.

## 19. Live handoff

### 19.1 Invisible cutover matrix

| Surface | New authority boundary | Status | UI impact |
|---|---|---|---|
| Flutter quote/create/lifecycle | Go `/api/v2` + Firestore transaction | Complete for core ride path | None |
| Flutter driver online/location/logout | Go driver-session lease API | Complete | None |
| Flutter decline/dispute/receipt | Go booking command API | Complete | None |
| Admin booking inspection | Go `/api/v2/admin/bookings` with callable fallback | Complete for first admin slice | None |
| Node booking notifications | Go outbox consumer with dedupe | Implemented; enable with cutover config | None |
| Node dispatch scheduler | Existing compatibility Functions path | Not yet replaced | None |
| Admin TODA, safety, violations, reports, settlement actions | Existing callable authority | Not yet replaced | None |
| Flutter safety, reports, ratings, calls, settlement | Existing callable authority | Not yet replaced | None |
| Rust geometry/navigation/media | Existing native compute boundary | Retained and tested | None |

The remaining rows are deliberately explicit: they are not silently marked
complete. The screens remain unchanged while each row is moved behind the Go
contract and covered by an emulator scenario.

- Current phase: Phase 2A/Phase 3/Phase 4 invisible cutover in progress.
- Last completed task: Go V2 booking/session authority, Node outbox notification
  worker, Admin booking query adapter, and Flutter booking mutation boundary.
- Implementation status: core source changes are present; full peripheral
  feature parity is not yet migrated.
- Verification completed: Node Functions 93/93 tests, Rust 22 unit + 3
  integration tests, Admin production build, and targeted Go app/core/Firebase
  tests all pass. An earlier `go vet ./...` and `go build .` pass is recorded;
  the final rerun exceeded the local 120-second tool window. The Dart
  null-aware map lint in `booking_repository.dart` is fixed and the file
  formats cleanly.
- Targeted Flutter verification completed: App Check initialization, the V2
  HTTP client, and `booking_repository.dart` analyze with no issues. Full
  registration/booking/call/safety scenario testing is deliberately deferred
  to the next validation session.
- Deployment handoff completed: Render blueprint variables, root architecture
  README, Cloud Run/Firebase/Render commands, App Check client headers, and
  rollback instructions are documented.
- Exact next task: configure `VITE_VOLTRIKE_API_BASE_URL`, validate the two-device
  defense ride against Firebase emulators, then migrate the remaining
  call/safety/report/settlement commands behind equivalent Go endpoints.
- Rule for the next agent: keep one Go authority, do not restore direct client
  domain writes, and update this handoff after every feature tranche.
