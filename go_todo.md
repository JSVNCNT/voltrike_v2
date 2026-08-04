# VolTrike Go Architecture and Implementation TODO

> Status: architecture plan only. No Go source, Go module, Firebase Function change, client change, deployment, or production resource has been created.
>
> Audit date: 2026-08-04
>
> Safety rule: the currently working Flutter app, Admin app, Firebase callable names, Firestore/Realtime Database records, and Node transaction rules must continue to work throughout the rollout.

## 1. Verified starting point

- [x] Go is installed at `C:\Program Files\Go\bin\go.exe`.
- [x] Direct verification reports `go version go1.26.5 windows/amd64`.
- [x] The machine PATH contains `C:\Program Files\Go\bin`.
- [x] The current VS Code/Codex process PATH does not contain that entry, so this is a stale-process environment issue, not a failed Go installation.
- [x] The repository currently contains no `.go` file and no `go.mod`.
- [x] The current Firebase Functions codebase uses Node 22 and Firebase Functions v2.
- [x] Flutter, Admin, Firebase Functions, Firebase rules, and the existing Rust bridge were audited for Go boundaries.
- [x] No App Check package or callable enforcement was found in Flutter, Admin, or Functions.

To make `go` visible in VS Code, run **Developer: Reload Window**, close the existing integrated terminal, and open a new one. If a temporary fix is needed for only the current PowerShell session, use:

```powershell
$env:Path += ';C:\Program Files\Go\bin'
go version
```

Do not reinstall Go or edit the machine PATH first; the installation and machine PATH are already correct.

## 2. Architecture decision

Add a private Go service as VolTrike's **server compute and read plane**. Keep the existing Node Firebase Functions as the **public compatibility, authentication, command, transaction, and event plane**.

```text
Flutter / React Admin
        |
        | existing Firebase callable protocol
        v
Node Firebase Functions (public gateway and transaction authority)
        |
        | private IAM-authenticated HTTP, versioned JSON contract
        v
Go Cloud Run service (networking, bounded concurrency, caches, read models)
        |
        +--> Google Routes and other external APIs
        +--> carefully scoped Firebase reads
        +--> advisory indexes and materialized read models
```

This is a radical backend addition without a risky rewrite. Over time, Go can own most expensive server-side reads, external networking, cached policy evaluation, spatial indexing, and batch work. Node becomes thinner, but remains the stable Firebase-facing gateway and the final authority for security-sensitive writes.

Go must not be placed inside Flutter's `lib/`, Admin's `src/`, the existing `rust/` crate, or the Node `functions/` source directory. The planned location is:

```text
services/
  voltrike-go/
    go.mod
    go.sum
    cmd/api/main.go
    internal/config/
    internal/httpapi/
    internal/contracts/
    internal/quote/
    internal/routes/
    internal/policycache/
    internal/dispatch/
    internal/readmodels/
    internal/observability/
    testdata/
```

The future Node adapter belongs in `functions/go-service-client.js`. Shared language-neutral JSON fixtures and schemas should live under `contracts/`, not be copied independently into every language.

## 3. Why Go is useful here

Go is a strong fit for long-lived server processes that perform many independent network calls, bounded concurrent reads, spatial-index queries, cache refreshes, background reconciliation, and streaming or batch work. It gives VolTrike a small deployable binary, predictable memory use, simple concurrency, strong cancellation through contexts, and a clean Cloud Run service boundary.

Go does **not** automatically make Firebase, Google Routes, or LiveKit faster. A rewrite that performs the same remote reads in the same order can be slower because it adds another network hop. Every Go move therefore needs one of these concrete wins:

- remove a duplicated external request;
- replace an unbounded scan with a bounded query or index;
- reuse an immutable, versioned cache safely across requests;
- execute independent I/O concurrently with strict limits;
- build a durable read model that avoids repeated joins;
- move expensive batch work away from latency-sensitive callables.

## 4. Current codebase findings and Go fit

### 4.1 Booking route and quote path — high-value networking pilot

- Flutter requests Google Routes while building the passenger preview in `lib/features/passenger/presentation/screens/passenger_home_screen.dart`.
- The Node `createBookingLifecycle` callable requests Google Routes again, reloads fare configuration, as many as 500 geofences, and as many as 200 active route restrictions, then writes the authoritative booking in a Firestore transaction.
- R3 correctly returns the authoritative server polyline and fare snapshot, but the preview and booking still involve two route computations for an ordinary new booking.

Go opportunity: create one authoritative server quote flow that performs the external route request once, applies cached versioned policy data, and supplies a short-lived trusted quote that Node can consume during booking creation.

### 4.2 Dispatch — highest scalability and Firebase-read opportunity

- `rankedDispatchDrivers` can load 500 driver documents.
- It reads the complete Realtime Database `driver_locations` root.
- It then joins user, TODA, and vehicle documents for nearby candidates.
- Scheduled redispatch can repeat the same scan and joins.

Go opportunity: query a spatial-cell/geohash read model, validate freshness, and rank a small candidate set using bounded concurrency. Node must retain the dispatch lease, offer writes, acceptance arbitration, and final eligibility transaction.

The data-layout change is the main win; translating the existing full-root scan into Go without an index is not an optimization.

### 4.3 Driver restriction monitoring — expensive but safety-sensitive

- Each distinct driver-location observation can load as many as 200 active restrictions and 200 driver restriction-state documents.
- The server normalizes geometry, checks every applicable restriction, and persists enter/exit-cycle state and violation records.
- The current source is a Firebase Realtime Database trigger.

Go opportunity: cached batch geometry evaluation or a later idempotent worker. Initial authority must remain in Node. The Go Admin SDK does not provide Realtime Database event listeners, so the current Node trigger cannot simply be replaced by an in-process Go listener.

### 4.4 Admin dashboards, commissions, and reports — read-model opportunity

- Admin already centralizes privileged operations through Firebase callables.
- Commission math and settlement writes are already inexpensive compared with Firestore queries and joins.
- Rewriting centavo arithmetic in Go would not solve the dashboard bottleneck.

Go opportunity: materialized read models, reconciliation, bulk export, and paginated search. Node remains the financial authority and continues enforcing developer/TODA scope.

### 4.5 PSGC data — optional cold-start and build-data opportunity

- Functions lazily load large nationwide PSGC JSON only for TODA-related work.
- Flutter already has a compact PSGC artifact and an existing Rust/Dart implementation.

Go opportunity: load a compact immutable server artifact or generate web/server shards if measured cold-start or memory data justifies it. This is not a ride hot path and is not an early Go priority.

### 4.6 LiveKit — keep the current boundary

LiveKit media delay is dominated by WebRTC connection setup, ICE/TURN path, network quality, audio configuration, and room lifecycle behavior. Rewriting token issuance from Node to Go will not materially improve call latency. Keep LiveKit authorization and call lifecycle in the existing Firebase Functions unless profiling proves a specific server bottleneck.

### 4.7 Existing Rust — keep it on the device

Rust already owns appropriate mobile CPU work: geometry caches, active-route navigation processing, compact PSGC access, and registration-image preparation through `flutter_rust_bridge`. Do not embed Go in Flutter or duplicate those features in Go. The intended split is:

| Layer | Responsibility |
| --- | --- |
| Dart/Flutter | UI, presentation state, maps, Firebase client SDKs, device permissions |
| Rust | on-device CPU-heavy, offline, low-latency processing without a network hop |
| Node/Firebase Functions | public callables, Firebase triggers, Auth/role checks, transactions, monetary and ride-state authority |
| Go/Cloud Run | server networking, bounded concurrency, caches, spatial indexes, read models, batch and reconciliation work |
| React/TypeScript Admin | browser UI, Mapbox editing/rendering, operator workflows |

## 5. Non-breaking compatibility rules

- [ ] Preserve every existing Firebase callable name and response field used by released clients.
- [ ] Preserve current `HttpsError` codes and user-visible failure behavior.
- [ ] Old app builds must continue working without knowing that Go exists.
- [ ] Do not split one Firestore transaction across Node and Go.
- [ ] Do not make Go's process memory the source of truth for bookings, operations, dispatch awards, ride states, settlements, commissions, violations, or audit logs.
- [ ] Keep all caches bounded, versioned, observable, and disposable.
- [ ] Add an environment-controlled mode for every Go-backed feature:
  - `off`: use only the current Node implementation;
  - `shadow`: execute Go, compare and record the result, but return/use Node's result;
  - `on`: use a validated Go result with a Node fallback where the workload is advisory.
- [ ] The `off` switch must restore current behavior without redeploying Flutter or Admin.
- [ ] Never turn on more than one major Go workload at the same time during rollout.

## 6. Phase G0 — baselines, contracts, and security design

- [ ] Record current p50/p95/p99 and error rates for booking creation, the Google Routes segment, dispatch candidate selection, restriction processing, and key Admin reports.
- [ ] Record Firestore/Realtime Database reads per operation and external API call counts.
- [ ] Confirm the production Firestore, Realtime Database, Functions, and planned Cloud Run regions before deployment. Prefer the existing `asia-southeast1` server boundary when compatible with the actual database locations.
- [ ] Inventory every current callable request/response/error contract used by Flutter and Admin.
- [ ] Add versioned JSON schemas for internal Node-to-Go requests and responses.
- [ ] Add shared golden fixtures for coordinates, encoded polylines, fare centavos, coverage, restrictions, dispatch ranking, malformed input, and error mapping.
- [ ] Define request IDs, trace propagation, deadlines, payload-size limits, maximum collection sizes, and log-redaction rules.
- [ ] Decide measurable promotion and rollback thresholds before implementation.
- [ ] Do not start production Go infrastructure until this phase has been reviewed.

## 7. Phase G1 — private Go service foundation

- [ ] Create `services/voltrike-go` using Go 1.26.5.
- [ ] Pin the module/toolchain and CI version rather than relying on whichever Go happens to be installed later.
- [ ] Create a standard HTTP server that obeys Cloud Run's `PORT` environment variable.
- [ ] Add `/healthz`, `/readyz`, and a version/build endpoint with no sensitive data.
- [ ] Add graceful shutdown, context cancellation, request timeouts, response-size limits, panic recovery, and structured JSON logs.
- [ ] Add strict JSON decoding that rejects unknown fields for internal contracts.
- [ ] Add typed internal errors and a stable Node mapping to Firebase callable errors.
- [ ] Use Application Default Credentials in Google Cloud; do not commit or download a service-account JSON key for production.
- [ ] Create a dedicated least-privilege Go runtime service account.
- [ ] Deploy the service privately with unauthenticated access disabled.
- [ ] Grant Cloud Run Invoker only to the selected Node Functions service identity.
- [ ] Have Node obtain a Google-signed OIDC ID token whose audience is the Go service URL.
- [ ] Add `functions/go-service-client.js` with connection reuse, a deadline shorter than the callable deadline, bounded retry only for safe idempotent requests, and circuit breaking.
- [ ] Add local emulator configuration that can call localhost only when the project is the protected demo project.
- [ ] Keep `VOLTRIKE_GO_MODE=off` after the first deployment.

No business path is switched in G1. Completion means the private boundary is secure, observable, tested, and removable.

## 8. Phase G2 — authoritative booking quote and policy cache

This is the recommended first user-visible Go workload because it can remove duplicated route networking without transferring booking transaction authority.

### Go work

- [ ] Add a versioned `/v1/booking/quote` internal endpoint.
- [ ] Add a reusable Google Routes client with keep-alive connections, deadlines, response limits, and bounded retries for safe provider failures.
- [ ] Load fare, geofence, and active-restriction snapshots through immutable revision-aware caches.
- [ ] Coalesce concurrent cache refreshes so one update does not cause a request stampede.
- [ ] Decode and evaluate all returned route alternatives in one bounded request.
- [ ] Return distance, duration, encoded polyline, coverage decision, restriction decisions, fare candidate, fare version, policy versions, and source revisions.
- [ ] Never treat an in-memory quote as durable booking authority.

### Node/Firebase work

- [ ] First run the Go result in shadow mode against the existing Node route, geometry, coverage, and fare path.
- [ ] Compare exact integer-centavo fare values and normalized policy decisions using shared fixtures and production-safe shadow telemetry.
- [ ] Add a backward-compatible `createBookingQuote` callable; Node performs Firebase Auth, profile/role, input, and later App Check validation before calling Go.
- [ ] Store a short-lived server-owned quote record with passenger UID, expiry, input hash, policy/fare revisions, and the authoritative route result.
- [ ] Allow `createBookingLifecycle` to accept an optional `quoteId`.
- [ ] When `quoteId` is valid, owned by the caller, unexpired, and revision-compatible, reuse its trusted route result and let Node perform the final fare/invariant check and Firestore transaction.
- [ ] When no `quoteId` is supplied, keep the current complete Node path for old clients.
- [ ] Reject or refresh a quote if security-sensitive policy or fare versions changed.
- [ ] Add quote expiry cleanup and idempotency.

### Flutter work

- [ ] Add a server-quote repository method behind a feature flag.
- [ ] In shadow/off modes, preserve the current local preview path.
- [ ] In on mode, display the authoritative quote/polyline and submit its `quoteId` during booking creation.
- [ ] Keep the existing `RoutesService` as a bounded rollout fallback until old-version compatibility and server availability are proven.
- [ ] Never fall back from a server policy denial to an unchecked client route.

### G2 promotion gate

- [ ] Node/Go parity fixtures pass for fare, geometry, coverage, policy, and errors.
- [ ] Shadow mismatches are understood and zero for authoritative fields before cutover.
- [ ] One normal booking creates no duplicate Google Routes request in on mode.
- [ ] Old clients still complete the current booking flow.
- [ ] Turning the feature off immediately restores the current Node behavior.

## 9. Phase G3 — dispatch presence index and candidate planner

This is the highest-potential scaling change, but it requires a data-layout redesign before Go can help.

- [ ] Measure current full-root location scan time, joined reads, candidate counts, scheduled redispatch load, and booking wait time.
- [ ] Design a spatial-cell/geohash presence record containing only advisory dispatch facts and a strict expiry timestamp.
- [ ] Make index updates atomic or idempotent and ensure stale cell membership is removed.
- [ ] Do not trust a client-maintained cell as final eligibility; Node must re-read authoritative driver, user, TODA, vehicle, booking, and freshness facts before writing offers.
- [ ] Add `/v1/dispatch/candidates` to query only pickup-neighbor cells and return a bounded deterministic candidate list.
- [ ] Apply explicit limits to queried cells, candidates, concurrency, payload size, coordinate age, future timestamps, and accuracy.
- [ ] Preserve the existing service-priority, distance-band, reliability, quality, and fairness ordering through shared fixtures.
- [ ] Keep Node's dispatch lease, offer batches, driver acceptance intent, arbitration window, and booking award transaction unchanged.
- [ ] Add a current-Node fallback for cold caches, index gaps, timeouts, and Go errors.
- [ ] Shadow both planners before using the Go candidate list.
- [ ] Do not promote until the indexed path reduces measured reads/latency without missing eligible fresh drivers.

## 10. Phase G4 — restriction and geometry server optimization

- [ ] Add immutable cached restriction snapshots keyed by revision/update time.
- [ ] Batch endpoint, polyline, corridor, and route-alternative checks in one request.
- [ ] Reuse the same language-neutral geometry fixtures already used for Dart/Rust/Node parity.
- [ ] Keep the Realtime Database `monitorDriverRestrictionPosition` trigger in Node initially.
- [ ] If profiling justifies a Go worker, use durable event IDs, monotonic `observedAt`, idempotent writes, and duplicate/out-of-order delivery tests.
- [ ] Never let a dropped event, expired in-memory cache, or Go restart erase a restriction state transition or violation audit trail.
- [ ] Treat this as safety-sensitive: shadow for an extended period and fail closed.

## 11. Phase G5 — Admin read models, commission visibility, and reconciliation

- [ ] Profile Admin metrics, bookings, drivers, settlements, commission reports, and polling behavior separately.
- [ ] Denormalize stable display fields into settlement/report rows where doing so removes repeated booking/user joins.
- [ ] Build materialized, TODA-scoped read models only for measured expensive dashboards.
- [ ] Add Go bulk export/reconciliation jobs for large asynchronous work, not for ordinary single-page arithmetic.
- [ ] Keep Node as authority for commission configuration, fare configuration, settlement creation, disputes, adjustments, and audit logs.
- [ ] Route Admin requests through the existing callable gateway first so developer-admin and TODA-admin scope remains unchanged.
- [ ] Verify totals against raw settlements and Node's integer-centavo calculations before exposing a read model.
- [ ] Provide rebuild and replay procedures so a read model can be discarded and recreated safely.

## 12. Phase G6 — App Check and optional direct Go reads

The repository currently has no App Check integration. Do not expose the Go service directly to Flutter or Admin before this phase.

- [ ] Add Firebase App Check to Flutter Android/iOS and the Admin web app with correct debug/emulator handling.
- [ ] Monitor valid/invalid/unknown traffic before enforcing.
- [ ] Enable callable App Check enforcement gradually, beginning with non-critical endpoints.
- [ ] Confirm released app versions can still use required endpoints before full enforcement.
- [ ] If direct Go access is still beneficial, verify both Firebase ID tokens and App Check tokens in Go, reapply role/TODA authorization, configure CORS narrowly for Admin, and rate-limit endpoints.
- [ ] Keep ride transitions, payments, commissions, and other commands behind Node even if read/quote endpoints later become direct.
- [ ] Note that App Check replay protection is not equivalently available for every Go path; use durable operation IDs and server-side idempotency for sensitive work.

## 13. Work that should remain out of Go for now

- [ ] Do not move Flutter UI, Riverpod state, maps, device GPS, camera, image picker, permissions, or navigation into Go.
- [ ] Do not add a second native Go runtime to the mobile app; keep on-device performance work in Rust.
- [ ] Do not move booking acceptance, ride transitions, active-booking locks, dispatch awards, cash confirmation, or completion transactions out of Node.
- [ ] Do not move authoritative fare, commission, settlement, dispute, or earnings writes out of Node.
- [ ] Do not rewrite LiveKit token/call lifecycle merely to use Go.
- [ ] Do not replace simple FCM, email, Firestore, Realtime Database, or scheduled triggers without measured evidence.
- [ ] Do not rewrite Admin Mapbox polygon editing or React rendering in Go.
- [ ] Do not use Go to proxy every Firebase read; that would add latency and bypass useful client SDK behavior.

## 14. Cache and concurrency requirements

- [ ] Every cache has a documented key, revision source, TTL, maximum entries, maximum bytes, and invalidation rule.
- [ ] Use immutable snapshots swapped atomically after complete validation.
- [ ] Use single-flight refresh and bounded worker pools; never start an unbounded goroutine per record.
- [ ] Carry request cancellation and deadlines into Firebase and external API calls.
- [ ] Never return expired safety policy merely because it is cached.
- [ ] A last-known-good cache may improve availability only where policy explicitly permits it; it must not override a new authoritative denial.
- [ ] Emit cache hit, miss, stale, refresh, eviction, size, and refresh-failure metrics.
- [ ] Design for multiple Cloud Run instances with separate memories; correctness cannot depend on one instance seeing another instance's cache.

## 15. Security requirements

- [ ] Cloud Run is private: deploy with unauthenticated access disabled.
- [ ] Use one dedicated runtime service account with only the Firestore, Realtime Database, Secret Manager, logging, and API permissions actually required by the selected phase.
- [ ] Grant Node only `roles/run.invoker` for the Go service.
- [ ] Use Application Default Credentials and workload identity; never commit a service-account key.
- [ ] Keep Google Routes and other server secrets in Secret Manager and never return them to clients.
- [ ] Node validates user authentication, account activity, role, email-verification rules, TODA scope, operation ID, and client input before forming an internal request.
- [ ] Node sends normalized facts, not a client-provided role or unrestricted authority claim.
- [ ] Do not forward Firebase bearer tokens when workload identity plus normalized scope is sufficient.
- [ ] Go validates all internal fields again, including coordinates, timestamps, list sizes, money units, versions, and enums.
- [ ] Redact tokens, phone numbers, emails, addresses, exact live locations, and raw provider bodies from normal logs.
- [ ] Document that Admin SDK reads/writes bypass Firebase Security Rules; IAM and application authorization are mandatory.

## 16. Testing requirements

- [ ] `go test ./...` passes.
- [ ] `go test -race ./...` passes for cache, index, and concurrent request paths.
- [ ] Fuzz tests cover JSON decoding, polyline decoding, coordinates, geometry, cursors, and malformed provider responses.
- [ ] Node and Go consume the same contract/golden fixtures.
- [ ] Integer-centavo fare and commission fixtures have exact equality, never floating-point tolerance.
- [ ] Geometry tests cover boundaries, holes if supported, overlapping polygons, corridor widths, malformed polygons, maximum sizes, and latitude/longitude order.
- [ ] Firebase Emulator lifecycle tests remain green with Go mode off.
- [ ] Local Node-to-Go integration tests run only against the demo project/emulators.
- [ ] Shadow tests record mismatches without changing user-visible results.
- [ ] Load tests cover cold start, warm cache, cache stampede, external API timeout, partial Firebase failure, high concurrency, and graceful shutdown.
- [ ] Security tests verify unauthenticated Cloud Run access is denied and the wrong service identity cannot invoke it.
- [ ] Flutter manual/device testing is required only when the quote UI/client path is later changed; Go foundation and shadow phases do not require a phone.

## 17. Deployment and rollback plan

- [ ] Add a separate Go build/test/deploy workflow; `firebase deploy --only functions` must not silently deploy or mutate the Go service.
- [ ] Deploy a tested Go revision first, privately and with no production caller.
- [ ] Verify health, IAM, secrets, region, limits, and logging.
- [ ] Deploy the Node adapter with every Go feature still `off`.
- [ ] Enable one feature in `shadow` mode and observe parity, latency, error, and cost metrics.
- [ ] Promote gradually to `on` only after its acceptance gate passes.
- [ ] Keep the old Node implementation during the rollback window.
- [ ] Roll back first by changing the feature mode to `off`; rollback must not require an app release.
- [ ] If needed, restore the previous Cloud Run revision and previous Node adapter independently.
- [ ] Deploy Go contracts before a Node version that requires them; retain at least one compatible prior contract version during rollout.
- [ ] Document manual Cloud Run, IAM, Secret Manager, and Firebase deployment commands only after actual project IDs, service accounts, and regions have been verified.

## 18. Definition of production-ready for a Go workload

A workload is not production-ready merely because its Go tests pass. It is ready only when:

- [ ] the working app behaves identically with the feature off;
- [ ] old and new clients remain compatible;
- [ ] Firebase emulator and existing Node tests pass;
- [ ] Node/Go contract and parity suites pass;
- [ ] shadow results show no unexplained authoritative mismatch;
- [ ] measured latency, reads, cost, or reliability improve enough to justify the new service hop;
- [ ] App Check/IAM/authorization requirements for its exposure level are met;
- [ ] observability, alerting, idempotency, quotas, and data-retention behavior are documented;
- [ ] rollback has been exercised;
- [ ] no booking, financial, safety, or audit authority exists only in ephemeral Go memory.

## 19. Recommended implementation order

1. G0 baselines and contracts.
2. G1 private service foundation with mode `off`.
3. G2 booking quote in shadow, then backward-compatible server quote rollout.
4. G3 dispatch spatial index after the current scan is measured.
5. G4 restriction optimization only after an extended safety shadow.
6. G5 Admin read models and exports based on measured query cost.
7. G6 App Check and optional direct read/quote endpoints.

Implementation should begin with G0/G1 only after an explicit approval signal. Do not start all phases together.

## 20. Official platform constraints used by this plan

- Firebase CLI Functions initialization officially offers JavaScript, TypeScript, and Python, so Go should be a separately deployed Cloud Run service rather than inserted into the current Firebase Functions codebase: <https://firebase.google.com/docs/functions/get-started>
- Cloud Run supports deploying Go services from source: <https://docs.cloud.google.com/run/docs/quickstarts/build-and-deploy/deploy-go-service>
- Go 1.26 is a supported Cloud Run functions runtime, so the installed Go 1.26.5 toolchain is current and usable: <https://docs.cloud.google.com/functions/docs/runtime-support>
- Firebase Admin SDK for Go supports server Firebase integration, but its Realtime Database API does not provide realtime event listeners: <https://firebase.google.com/docs/admin/setup>
- Private Cloud Run service-to-service calls should use IAM and Google-signed ID tokens: <https://docs.cloud.google.com/run/docs/authenticating/service-to-service>
- Firebase ID tokens can be verified by the Go Admin SDK if a future direct backend endpoint is introduced: <https://firebase.google.com/docs/auth/admin/verify-id-tokens>
- App Check tokens can be verified in a custom Go backend: <https://firebase.google.com/docs/app-check/custom-resource-backend>
- Firestore events can be routed to Cloud Run through Eventarc for a later read-model worker: <https://docs.cloud.google.com/eventarc/standard/docs/run/route-trigger-cloud-firestore>

## 21. Radical Firebase-usage reduction addendum

The earlier phases reduce duplicated work and expensive reads while Firebase remains the main database. A more radical end state is possible, but the goal must be precise:

- Firestore charges for document and index-entry reads and for each document write/delete. Realtime listeners also generate reads when result documents are added or updated.
- Realtime Database is primarily billed by stored and downloaded bytes, not by a Firestore-style per-document operation count. Reading the entire `driver_locations` root is therefore mainly a bandwidth and scalability problem.
- Replacing Firestore with another database moves cost; it does not make storage, backups, compute, networking, or operations free.
- Go by itself saves no Firebase operation. Firebase use falls only when a cache, bounded query, aggregate, new transport, or new source of truth prevents the Firebase operation from happening.

Official billing references:

- <https://firebase.google.com/docs/firestore/pricing>
- <https://firebase.google.com/docs/database/usage/billing>
- <https://firebase.google.com/docs/sql-connect/pricing>

### Compatibility truth

The released Flutter and Admin code contains direct Firestore/Realtime Database listeners. Keeping every old direct listener working forever requires keeping its Firebase data projection updated, which means Firebase writes and reads cannot fall to near zero.

A radical migration can preserve the existing Firebase **Function names and request contracts** throughout the transition. It can also preserve direct-listener compatibility for a defined migration window. It cannot simultaneously retire those Firebase projections and support every old client forever. Before removing a projection, VolTrike must establish a minimum supported app version and a safe upgrade/deprecation policy.

## 22. Phase G7 — reduce Firebase operations without replacing Firebase

Do this before adding PostgreSQL. It is lower risk and may remove enough usage that a second database is economically unnecessary.

### Measure first

- [ ] Export daily Firestore reads, writes, deletes, listener counts, query shapes, and rule-dependent reads.
- [ ] Record Realtime Database downloads, active connections, hot paths, and whole-root reads.
- [ ] Tag operations by screen/workflow so optimization is based on real traffic rather than collection size alone.
- [ ] Calculate read-to-write ratios before adding materialized counters; a counter that is written frequently but viewed rarely can cost more than the query it replaces.

### Remove current unbounded client reads

- [ ] Replace passenger and driver history streams that load complete booking histories with cursor-based pages and explicit limits.
- [ ] Replace the driver's full completed-booking download for today/week/month/total earnings with server-maintained period aggregates plus paginated ride details.
- [ ] Paginate driver/passenger ratings and use the existing authoritative rating summary instead of downloading every rating to calculate an average.
- [ ] Denormalize the safe display snapshot needed by a driver offer into the offer record, eliminating the current additional booking read per displayed offer.
- [ ] Paginate Admin lists and exports with stable cursors; never use offsets that still bill skipped Firestore documents.
- [ ] Keep active-ride listeners scoped to the existing active pointer and one booking document rather than a user's history query.

### Compile rarely changing policy into immutable bundles

- [ ] Treat fare configuration, geofence revisions, route-restriction revisions, and public TODA metadata as versioned policy inputs.
- [ ] Have a trusted backend build a compact immutable policy bundle after an Admin update.
- [ ] Store the bundle in Cloud Storage or Hosting with a content hash, ETag, cache headers, schema version, and signature/hash verification.
- [ ] Let Go and clients reuse the bundle until its advertised revision changes instead of reading the same Firestore policy documents per request/session.
- [ ] Keep Firestore as the Admin edit authority and retain a fail-closed server validation path for security-sensitive booking decisions.
- [ ] Do not include private user, driver, exact-location, settlement, or audit data in a public/cacheable bundle.

### Separate hot transient state from durable records

- [ ] Keep exact driver presence/location and other high-frequency ephemeral state out of Firestore.
- [ ] Continue using narrowly scoped and indexed Realtime Database paths during the first radical phase; do not read an entire root.
- [ ] Evaluate a compact `activeRide` projection for high-churn UI state while Firestore stores durable booking milestones, audit events, and completion/settlement records.
- [ ] Coalesce harmless repeated presence/location updates, but never drop a required ride transition, payment confirmation, safety event, or audit event.
- [ ] Add sequence/version numbers so reconnecting clients can reject stale state.

### Cache server reads safely

- [ ] Cache fare/geofence/restriction/PSGC snapshots in Go by immutable revision.
- [ ] Use bounded in-process caches first; do not buy a distributed cache until multiple-instance miss rates and actual savings justify its fixed cost.
- [ ] Use Eventarc/Pub/Sub invalidation or a bounded refresh policy for Firestore-backed caches; do not issue a Firestore version read on every request if that cancels the saving.
- [ ] Cache only data whose temporary loss can be reconstructed from an authoritative store.

### Reduce write amplification

- [ ] Audit each lifecycle operation for duplicate merge writes, unchanged fields, redundant timestamps, duplicated notifications, and idempotent retries that still write.
- [ ] Keep immutable audit and financial writes even when optimizing; correctness takes priority over a lower write count.
- [ ] Batch non-critical telemetry and dashboard refresh events.
- [ ] Do not create one aggregate write per event unless that aggregate is read often enough to justify it.
- [ ] Separate operator dashboards from transactional documents so opening a dashboard does not fan out across raw bookings, users, and settlements.

### G7 acceptance gate

- [ ] Compare at least one representative baseline window with the optimized window.
- [ ] Demonstrate lower reads/downloads and no increase in stale or missing user-visible data.
- [ ] Demonstrate that any added aggregate writes have a favorable total cost/read-latency tradeoff.
- [ ] Keep all booking, fare, commission, settlement, safety, and audit invariants green.

## 23. Phase G8 — optional Go + PostgreSQL/PostGIS primary data plane

If G7 is insufficient and measured scale justifies a second database, VolTrike can move from “Go optimization service” to a Go-owned domain platform.

```text
Old clients
  -> existing Firebase callable names
  -> Node compatibility adapter
  -> private Go command/query API

New clients, only after Auth + App Check migration
  -> Go HTTPS + resumable realtime channel

Go domain platform
  -> PostgreSQL transactions and durable idempotency
  -> PostGIS geofences, restrictions, and spatial lookup
  -> transactional outbox
  -> notification/projection workers
  -> optional ephemeral presence/dispatch cache

Firebase retained for
  -> Authentication
  -> App Check
  -> FCM
  -> Storage
  -> Hosting
  -> minimal compatibility projections during migration
```

Firebase SQL Connect or direct Cloud SQL PostgreSQL can eliminate Firestore's per-document-read model for migrated relational queries, but both introduce a Cloud SQL instance and its CPU, memory, storage, backup, networking, and operations costs. At capstone or low production traffic, this fixed database cost can exceed current Firestore usage. Require a real cost model before choosing it.

### G8 data ownership

- [ ] Define bounded contexts before schema work: identity/profile reference, TODA/policy, quote, dispatch, booking lifecycle, communication, safety, fare/commission, settlement, and reporting.
- [ ] Use PostgreSQL tables for bookings, booking events, operation/idempotency keys, fare versions, commission versions, settlements, disputes, policy revisions, and durable outbox events only after their context is explicitly migrated.
- [ ] Use PostGIS indexes for geofences/restrictions and bounded spatial candidate queries.
- [ ] Keep high-frequency live presence outside durable booking tables; choose narrowly scoped RTDB first or an optional ephemeral cache only after measuring.
- [ ] Never make Redis/Memorystore or Go process memory the sole copy of a booking, payment, settlement, violation, or audit event.

### Transactional outbox, not request-path dual writes

- [ ] One Go/PostgreSQL transaction writes the domain change and an outbox row together.
- [ ] An idempotent worker publishes Firebase compatibility projections, notifications, analytics, and downstream events from the outbox.
- [ ] Store event IDs, aggregate versions, retry counts, and delivery status.
- [ ] Make every projection tolerant of duplicate and out-of-order delivery.
- [ ] Add dead-letter handling, replay, reconciliation, and an operator-visible lag metric.
- [ ] Do not let Node synchronously write both PostgreSQL and Firestore as two authorities; that creates an unrecoverable partial-success window.

### Preserve Functions without preserving duplicate authority

- [ ] Keep current callable names, Auth checks, request fields, response fields, and error mapping in Node.
- [ ] Migrate one command at a time so the adapter forwards that command to Go.
- [ ] For a migrated command, Go/PostgreSQL is the only writer; Node must not silently fall back to its old Firestore write path.
- [ ] Shadow mode for commands may compare decisions, but the shadow implementation must not write.
- [ ] Use an explicit ownership version/lease for each aggregate type before cutover.
- [ ] Rollback an authoritative command only through a controlled drain, reconciliation, and ownership transfer—not by running two writers.

### Compatibility projections

- [ ] Initially project the minimum booking/current-state fields required by existing Flutter/Admin listeners.
- [ ] Mark every projected document with source version, aggregate version, projection time, and schema version.
- [ ] Ensure projections never accept client writes back into the new authority.
- [ ] Migrate new Flutter/Admin reads to Go endpoints or a resumable realtime channel one screen at a time.
- [ ] Stop maintaining a Firestore projection only after supported clients no longer consume it.
- [ ] Archive or retain durable Firestore history according to a documented legal/audit policy; do not delete financial or safety data merely to lower counts.

### Realtime replacement requirements

- [ ] If active ride state leaves Firebase listeners, implement authenticated WebSocket or server-sent-event subscriptions with sequence numbers and resumable cursors.
- [ ] Verify Firebase ID tokens and App Check tokens at connection creation and reauthenticate long-lived connections before token expiry.
- [ ] Authorize booking membership and TODA/admin scope for every subscription.
- [ ] Support reconnect, missed-event replay, duplicate suppression, slow consumers, bounded queues, server restarts, and mobile background/foreground transitions.
- [ ] Keep a normal HTTPS snapshot endpoint so clients can recover when the realtime channel loses history.
- [ ] Do not proxy LiveKit audio through this channel.

### Recommended G8 migration order

1. Read-only histories, ratings, earnings, Admin reports, and exports.
2. Immutable policy and server quote records.
3. Dispatch spatial index and advisory planner.
4. Low-risk non-financial commands.
5. Booking lifecycle only after exclusive-writer and outbox testing.
6. Fare/commission/settlement last, with reconciliation and audit review.
7. Retire Firebase projections only after the supported-client window closes.

### G8 approval gate

- [ ] G7 measurements prove that data-model/query fixes alone are insufficient.
- [ ] A 12-month cost model includes Cloud Run, SQL/SQL Connect, backups, high availability, storage, egress, monitoring, and engineering/operations time—not only avoided Firestore reads.
- [ ] Recovery point, recovery time, backup, restore, migration, and rollback procedures are tested.
- [ ] The team accepts that a new primary database is a product architecture change, not a language optimization.

## 24. Immediate audited read reductions to prioritize

These are already visible in the current code and should be addressed before assuming a database replacement is needed:

- [ ] `bookingsForPassenger` and `bookingsForDriver` currently stream complete histories; replace them with cursor pages.
- [ ] `DriverEarningsRepository.loadAggregate` currently loads every completed booking; replace it with authoritative daily/monthly/lifetime aggregate documents or a Go/SQL aggregate endpoint.
- [ ] Driver/passenger rating streams and average lookup currently read complete result sets; paginate detail and consume server aggregate fields.
- [ ] `watchDriverOffers` currently performs a booking read for each live offer; snapshot the required safe booking display fields into the offer.
- [ ] `rankedDispatchDrivers` currently reads the complete RTDB driver-location root and up to three eligibility documents per nearby driver; introduce spatial buckets and a server-maintained eligibility snapshot.
- [ ] Booking creation currently reloads fare, geofences, and active restrictions and repeats the client's Google Routes call; implement the G2 authoritative quote and revision cache.

## 25. Mandatory pre-Go protocol correction

The audit found an existing version mismatch unrelated to Go:

- Flutter declares `expectedFunctionsProtocolVersion = 3` in `lib/app/app_config.dart`.
- `getSystemDiagnostics` currently returns `functionsProtocolVersion: 4` in `functions/index.js`.
- `SystemDiagnosticsService` requires exact equality, so it can report an otherwise compatible backend as incompatible.

- [ ] Reconcile and test this existing protocol contract before adding a second Node-to-Go protocol/version layer.
- [ ] Use explicit minimum/maximum compatibility rules for future protocols rather than an undocumented exact-version assumption.

## 26. Revised recommendation for the radical option

1. Implement G7 read/write reduction first; it directly attacks the current billing shapes and does not require a second source of truth.
2. Continue G1/G2 so Go proves its private service, quote, cache, observability, and rollback boundaries.
3. Implement the G3 dispatch index because the current whole-root scan is a concrete bandwidth/read-layout problem.
4. Adopt G8 PostgreSQL/PostGIS only when measurements show that the Firebase-centered design remains too expensive or limiting.

The most aggressive technically sound end state is Go + PostgreSQL/PostGIS with Firebase retained for Auth, App Check, FCM, Storage, Hosting, and temporary compatibility projections. It is also the highest-risk and may cost more at VolTrike's current scale, so it must be a measured architecture decision rather than the first implementation step.
