# VolTrike Google Maps to Mapbox transition

Status: architecture gate only  
Created: 2026-07-27  
Implementation authorization: not granted yet

This tracker is the source of truth for the migration. No existing application,
admin, Firebase, Android, or iOS source is to be changed until the owner sends
an explicit `GO MAPBOX MIGRATION` signal.

## 1. Current repository findings

- [x] Confirm this is one Flutter application package with passenger and driver
  routes selected after Firebase authentication.
- [x] Confirm the stored role is currently a string (`passenger`, `driver`,
  `developer_admin`, or `toda_admin`), exposed through `AppUser.isPassenger`
  and `AppUser.isDriver`; the current schema is not an `is_driver` boolean.
- [x] Confirm passenger and driver shells are separate, but `AppShellScreen`
  uses an `IndexedStack`, which keeps every tab alive and can retain a map even
  while another tab is visible.
- [x] Find 35 Dart files importing `google_maps_flutter`.
- [x] Find direct Google Places, Geocoding, Roads, and Routes HTTP calls in the
  mobile app.
- [x] Find a server-side Google Routes call in `functions/index.js` used as the
  trusted booking distance and duration authority.
- [x] Find Google Maps Android manifest metadata and external Google Navigation
  URI declarations on Android and iOS.
- [x] Confirm the admin polygon editor already uses Mapbox GL JS and reads
  `VITE_MAPBOX_ACCESS_TOKEN` from `admin/.env`.
- [x] Confirm the current admin editor saves route-restriction corridors and
  polygons, but does **not** publish an approved, versioned Polyline5 route
  payload for a booking.
- [x] Confirm the current booking model contains pickup and destination
  coordinates but no authoritative route assignment, route version, checksum,
  maneuver bundle, or route provenance.
- [x] Confirm current driver navigation repeatedly asks Google Routes for a
  route and reads Google navigation steps; it does not yet perform native
  active guidance.

## 2. Decisions fixed by this architecture review

- [x] The final mobile build will contain Mapbox maps only. Passenger maps,
  passenger trip tracking, driver idle maps, and driver active navigation will
  all be migrated.
- [x] Google map packages and APIs will be removed only after Mapbox parity is
  implemented and tested. No intermediate dual-map build will be released.
- [x] A **new mobile public Mapbox token** will be used. The token in
  `admin/.env` will not be reused by the mobile application.
- [x] A separate **secret downloads token** will be used only by Gradle/native
  dependency resolution. It will never be placed in Flutter assets, Dart
  defines, a repository `.env`, Firebase, or the APK.
- [x] The public mobile token is not a secret once compiled into an APK. It
  will receive only required public scopes, separate usage monitoring, and a
  rotation path.
- [x] Mapbox URL restrictions cannot protect a native mobile token. They can
  and should protect the separate admin web token.
- [x] Firebase client configuration is not an application secret. The existing
  FlutterFire files remain canonical; Firebase security continues to come from
  Auth, Security Rules, App Check, and trusted Cloud Functions.
- [x] Map-provider types will be removed from domain models. A VolTrike
  `GeoCoordinate` will own latitude/longitude, with adapters handling Mapbox's
  required longitude/latitude ordering.
- [x] Polyline5 is only an encoding format. Keeping a Google-compatible
  Polyline5 does not mean the application is using a Google service.
- [x] A Polyline5 alone cannot provide safe turn-by-turn instructions, lane
  guidance, voice prompts, road names, route progress, or legal-road metadata.
- [x] Production driver guidance will therefore use the native Mapbox
  Navigation SDK through a first-party Flutter platform bridge. The
  admin-authored Polyline5 will be map-matched at trip start to obtain a
  Mapbox navigation route, then validated against the canonical admin geometry
  before guidance starts.
- [x] Automatic rerouting, alternatives, and route refresh that can replace
  geometry will be disabled during an admin-locked trip.
- [x] Off-route detection remains enabled as an alert only. It must not replace
  the approved route. The driver will be told to safely rejoin the route or
  contact dispatch.
- [x] Mapbox traffic will inform the driver but will never mutate the fixed
  route. Traffic can affect warning presentation and an estimated delay, not
  route authority.

## 3. Credential gate

### Token set

- [ ] Create `voltrike-mobile-public` as a new `pk.` token under the same
  Mapbox account if desired. Give it only the public scopes required by Maps,
  Geocoding, Map Matching/Directions, and Navigation.
- [ ] Do not add URL restrictions to the mobile token; native Mapbox Maps and
  Navigation SDK requests do not support that restriction mechanism.
- [ ] Create `voltrike-android-downloads` as a new `sk.` token with
  **Downloads:Read only**.
- [ ] Keep or rotate `voltrike-admin-web` as a separate `pk.` token for
  `admin/.env`. Restrict it to the production admin origin and explicitly
  approved development origins.
- [ ] Enable Mapbox account usage alerts and establish token rotation ownership.
- [ ] Confirm whether iOS active guidance is in the first release. If it is,
  create/configure the equivalent native package-download credential without
  exposing it to the iOS app bundle.

### Planned local locations

These paths are planned but intentionally not created during this analysis pass.

- Mobile public runtime configuration:
  `config/env/.env.mapbox.local`
- Safe committed example:
  `config/env/.env.mapbox.example`
- Android secret download credential:
  `C:\Users\Vincent\.gradle\gradle.properties`
- CI Android secret:
  CI secret store exposed only as `MAPBOX_DOWNLOADS_TOKEN`
- Existing admin public token:
  `admin/.env`

Rules for the planned files:

- `config/env/.env.mapbox.local` must be ignored by Git.
- It may contain `MAPBOX_PUBLIC_TOKEN=pk...`.
- The requested `FIREBASE_CONFIG` example will be documented, but the migration
  must not create a second, conflicting Firebase configuration source. The
  implementation will validate whether this variable has a real consumer.
  Existing `firebase_options.dart`, `google-services.json`, and the iOS Firebase
  plist remain authoritative unless a separate environment build system is
  deliberately introduced.
- `MAPBOX_DOWNLOADS_TOKEN=sk...` belongs only in the user-level Gradle
  properties file or CI secret store.
- No real token value may appear in a committed file, test fixture, log,
  screenshot, crash report, or final response.

### Credential implementation gate

- [ ] After `GO MAPBOX MIGRATION`, create the ignored local environment file
  and committed example first.
- [ ] Pause so the owner can paste only the new mobile `pk.` token locally.
- [ ] Add fail-closed startup validation with redacted diagnostic messages.
- [ ] Add the Mapbox Maven repository credential lookup using
  `MAPBOX_DOWNLOADS_TOKEN`.
- [ ] Verify a release build can resolve Mapbox binaries without embedding the
  secret token in the APK or generated resources.

## 4. External capability corrections

### Philippine search

- [x] Do not make Mapbox Search Box the Philippine search backbone. Its current
  documented supported geographies are the United States, Canada, and Europe.
- [x] Use Mapbox Geocoding v6 for Philippine address, street, locality,
  neighborhood, district, place, region, and reverse-geocoding context.
- [x] Treat `sublocality_level_1` as Google terminology. The Mapbox parser will
  instead consume `neighborhood`, `locality`, `district`, `place`, and `region`.
- [x] Keep hyper-local landmarks in the VolTrike-owned approved POI collection.
- [x] Never persist temporary Mapbox Search/Geocoding response data. Manual
  user text and user-selected coordinates may be stored. Persisting Mapbox
  geocodes requires a permitted permanent-geocoding request and its associated
  account/billing conditions.

### Traffic

- [x] Use `mapbox://mapbox.mapbox-traffic-v1` only during driver active
  navigation unless product requirements later justify broader use.
- [x] Style `moderate`, `heavy`, and `severe` congestion distinctly and include
  road-closure presentation.
- [x] Keep required Mapbox attribution and telemetry opt-out access.
- [x] Do not call traffic "free." It avoids driver-side route recalculation,
  but Maps, traffic tiles, Search/Geocoding, Map Matching, Directions, and
  Navigation remain subject to Mapbox pricing and account limits.
- [x] Validate actual traffic coverage on the Bacolod/TODA test routes. Missing
  traffic features must produce a neutral UI, never a false "clear road" claim.

## 5. Target project tree

The exact filenames may be adjusted to match existing conventions, but the
boundaries below are mandatory.

```text
config/
  env/
    .env.mapbox.example
    .env.mapbox.local                 # ignored; mobile pk token only

lib/
  core/
    config/
      mapbox_config.dart
      runtime_environment.dart
    geo/
      domain/
        geo_coordinate.dart
        geo_bounds.dart
        encoded_route.dart
      adapters/
        mapbox_coordinate_adapter.dart
      algorithms/
        polyline5_codec.dart
        haversine_distance.dart
        route_corridor_matcher.dart
    maps/
      map_runtime_coordinator.dart
      map_runtime_mode.dart
      map_resource_registry.dart
      style/
        voltrike_map_style.dart
        traffic_style.dart
    errors/
      map_failure.dart
      mapbox_error_mapper.dart

  data/
    models/
      approved_poi.dart
      missing_place_candidate.dart
      authoritative_route.dart
      navigation_maneuver.dart
    repositories/
      approved_poi_repository.dart
      missing_place_repository.dart
      authoritative_route_repository.dart

  features/
    passenger/
      search/
        controllers/
          passenger_place_search_controller.dart
          manual_pin_controller.dart
        services/
          local_poi_search_service.dart
          mapbox_geocoding_service.dart
          reverse_anchor_label_parser.dart
        presentation/
          screens/
            passenger_place_search_screen.dart
            manual_pin_screen.dart
      maps/
        passenger_map_screen.dart
        passenger_tracking_map.dart

    driver/
      navigation/
        controllers/
          driver_guidance_controller.dart
        models/
          driver_guidance_state.dart
        services/
          native_navigation_bridge.dart
          locked_route_validator.dart
          off_route_policy.dart
        presentation/
          driver_navigation_screen.dart
          widgets/
            maneuver_banner.dart
            navigation_action_rail.dart
            trip_progress_bar.dart
            route_exception_banner.dart

android/
  app/src/main/kotlin/com/example/voltrike_v2/
    navigation/
      MapboxNavigationPlugin.kt
      MapboxNavigationPlatformView.kt
      NavigationSessionController.kt
      NavigationEventSerializer.kt

functions/
  mapbox/
    authoritative-route.js
    missing-place-moderation.js
    keyword-normalization.js
    geospatial-matching.js

admin/src/
  features/
    routes/
      RouteTemplateEditor.tsx
      RouteValidationPanel.tsx
      RoutePublicationPanel.tsx
    places/
      MissingPlaceReview.tsx
      ApprovedPoiEditor.tsx

mapbox_transition/
  TODO.md
  DONE.md
```

## 6. Role-based map runtime and cleanup

- [ ] Resolve the authenticated user and validated role before mounting either
  role subtree.
- [ ] Replace role routing based on an assumed `is_driver` field with the
  existing canonical `AppUser.isDriver`/`role` model, or perform a versioned
  backend schema migration if a boolean is still desired.
- [ ] Introduce mutually exclusive runtime modes:
  `none`, `passengerBrowse`, `passengerTracking`, `driverIdle`, and
  `driverActiveGuidance`.
- [ ] Mount only the selected role root. Never build both passenger and driver
  shells and hide one with visibility widgets.
- [ ] Remove map pages from the current always-alive `IndexedStack` behavior.
  Non-map tabs may remain cached; a map tab must be disposed when its mode ends.
- [ ] On role/session/mode transition, perform cleanup before mounting the next
  surface:
  cancel Riverpod/location/booking subscriptions; stop trip session; unregister
  Navigation SDK observers; clear active navigation routes; remove traffic and
  route sources/layers; destroy annotation managers; release map controllers;
  detach the native platform view; destroy/disable the native Navigation SDK
  instance when no driver guidance owner remains.
- [ ] Key the new role subtree so Flutter cannot reuse state from the prior
  role.
- [ ] Add lifecycle tests proving only one map surface and only one native
  navigation owner exist at a time.
- [ ] Add logout and account-switch tests proving location and navigation
  events stop after teardown.

Because the final application uses Mapbox for both roles, the lasting reason
for this coordinator is memory, battery, privacy, and correct lifecycle
ownership—not simultaneous Google/Mapbox operation.

## 7. Passenger place-search pipeline

### Query behavior

- [ ] Normalize the typed term without losing the original user text.
- [ ] Debounce input, cancel stale work, and give every interactive search a
  request/session sequence.
- [ ] Query Firestore `custom_approved_pois` first using normalized search
  tokens plus a geospatial bound around the current/pickup origin.
- [ ] Return approved local hits immediately and label their source as
  VolTrike-approved.
- [ ] If no approved local match exists, call Mapbox Geocoding v6 with
  `country=ph`, proximity, an operational bounding box, supported language
  preferences, a timeout, and explicit response limits.
- [ ] Distinguish an empty success from authentication, quota, connectivity,
  validation, and server failures.
- [ ] If no usable result exists, expose `Pin Location Manually`.
- [ ] Keep the existing 10 km operational search rule unless the fare/coverage
  owners explicitly change it.

### Manual pin

- [ ] Present one Mapbox surface with a draggable visual pin or an equivalent
  accessible center-pin interaction.
- [ ] Reverse geocode only after drag/camera idle, not on every movement frame.
- [ ] Parse the best readable anchor in this order:
  street/address; neighborhood; locality; district; place/city; region.
- [ ] Produce a label such as `Near {street}, {barangay/locality}, {city}` while
  gracefully omitting missing components.
- [ ] If all metadata is absent, show a non-crashing coordinate fallback and
  allow the passenger to type a local landmark description.
- [ ] Keep temporary Mapbox reverse-geocoding data in memory only.
- [ ] Require explicit passenger confirmation before a pin becomes the booking
  pickup or destination.
- [ ] Check coverage geofences and fare eligibility before booking creation.

### Firestore collections and trust boundary

Planned top-level collections:

- `custom_approved_pois/{poiId}`
- `missing_place_logs/{candidateId}`
- `missing_place_logs/{candidateId}/reporters/{uid}`

Planned approved POI fields:

- stable ID, display name, aliases, normalized tokens, user/admin coordinates,
  geohash, city/barangay labels, approval status, source, created/updated audit
  fields, approver ID, and schema version.

Planned missing-place fields:

- representative user coordinates, geohash/bucket keys, original typed term,
  normalized keyword signature, unique reporter count, state, first/last seen
  timestamps, schema version, and moderation audit fields.

Trust and aggregation rules:

- [ ] Clients may not directly increment counts or set approval state.
- [ ] Submit a callable function protected by Firebase Auth and App Check.
- [ ] Normalize text server-side and reject invalid coordinates/oversized text.
- [ ] Query candidate buckets, then enforce a Haversine distance of at most
  20 meters and a documented token/trigram similarity threshold.
- [ ] Count distinct authenticated users, not raw submissions.
- [ ] Use a transaction and idempotency key so retries cannot inflate counts.
- [ ] Set `pending_admin_approval` when the third distinct matching reporter is
  committed.
- [ ] Never auto-promote a public POI. Admin approval publishes a sanitized,
  user/admin-owned label into `custom_approved_pois`.
- [ ] Add abuse rate limits, reporter privacy, retention rules, and an admin
  reject/merge workflow.
- [ ] Add Firestore indexes and Security Rules tests before enabling writes.

## 8. Authoritative route contract

### Existing gap

The present admin dashboard does not generate the route payload described by
the product rule. This must be added before driver guidance can be locked.

### Canonical route fields

- [ ] Add an `authoritativeRoute` assignment to each active booking.
- [ ] Include a route ID, version, route phase (`to_pickup` or
  `pickup_to_destination`), Polyline5 string, precision value fixed to 5,
  start/end coordinates, distance, baseline duration, source/provenance,
  restriction-set version, created/approved timestamps, approver, and a
  checksum/signature.
- [ ] Define whether both phases are admin-authored. A driver-to-pickup route is
  dynamic because the driver's origin changes; it cannot be represented by one
  reusable static route unless the product defines fixed approach corridors.
- [ ] Recommended resolution: the trusted backend freezes both phases for the
  booking. It may select a pre-approved route template or produce a candidate
  for admin/rules validation, but the driver device never chooses a replacement
  path.
- [ ] Version route assignments immutably. A replacement is a new approved
  version with an audit trail, not an in-place geometry mutation.

### Admin route authoring and validation

- [ ] Extend the existing Mapbox polygon editor into a route-template editor.
- [ ] Allow manual road-following control points and show all active prohibited
  corridors/polygons while authoring.
- [ ] Decode/encode Polyline5 deterministically and keep original control-point
  provenance.
- [ ] Validate a candidate route server-side against prohibited highway
  corridors, no-service polygons, and restricted crossings.
- [ ] Validate coordinate ranges, point count, encoded length, start/end
  tolerances, self-intersections where relevant, route continuity, and minimum
  segment length.
- [ ] Refuse publication when the route crosses an active restriction.
- [ ] Preview the exact mobile geometry and route bounds before approval.
- [ ] Publish only through an authenticated developer-admin Cloud Function.
- [ ] Record audit logs for create, edit, approve, supersede, and disable.

## 9. Driver native active guidance

### Integration

- [ ] Run an Android dependency compatibility spike before changing production
  screens. Pin compatible versions of the official Flutter Maps SDK, native
  Maps SDK, and native Navigation SDK; inspect Gradle dependency resolution.
- [ ] Use the stable official Flutter Maps SDK for passenger/idle surfaces.
- [ ] Embed a native Android Navigation SDK map as a Flutter platform view only
  for `driverActiveGuidance`.
- [ ] Keep booking controls, chat, call, report, status transitions, and the
  bottom trip panel in Flutter above the native map.
- [ ] Stream typed route progress, maneuver, voice/banner instruction, enhanced
  location, arrival, off-route, and failure events from Kotlin to Dart.
- [ ] Expose typed start, stop, overview, recenter, mute, and cleanup commands
  from Dart to Kotlin.

### Locked route startup

- [ ] Fetch the authoritative booking route and verify its checksum/version.
- [ ] Decode Polyline5 with guarded bounds checks and precision 5.
- [ ] Reject empty, malformed, non-finite, out-of-range, or discontinuous
  geometry.
- [ ] Convert domain latitude/longitude to Mapbox longitude/latitude only at
  the adapter boundary.
- [ ] Request Map Matching with steps, banner instructions, voice instructions,
  metric units, and the required language.
- [ ] Compare returned matched geometry to the canonical admin route using a
  corridor/deviation tolerance.
- [ ] Reject guidance if matching changes the route beyond tolerance or places
  it inside an active prohibited area.
- [ ] Render the admin Polyline5 as the canonical fixed route line.
- [ ] Set the validated Mapbox navigation route for progress and instructions.
- [ ] Disable automatic rerouting, alternative route switching, and
  geometry-changing refresh.
- [ ] Retain off-route observation as a warning state.
- [ ] Fit the route using camera geometry/bounds with padding for the maneuver
  banner, action rail, and bottom trip panel.
- [ ] Switch from overview camera to following camera when active guidance
  starts; allow an explicit overview/recenter toggle.

### Driver UI behavior

- [ ] During an active booking, route the driver directly to the dedicated
  navigation screen and keep it active through the entire applicable phase.
- [ ] Show a large top maneuver banner with icon, distance, primary road/street
  text, secondary instruction, and safe missing-text fallbacks.
- [ ] Show current location puck, fixed route, pickup/destination markers,
  traffic overlay, recenter, route overview, mute/unmute, report, and exit/end
  controls.
- [ ] Keep bottom ETA, remaining distance, arrival time, booking stage, and
  passenger/service actions.
- [ ] At pickup confirmation, atomically stop the approach route and load the
  approved pickup-to-destination route.
- [ ] At trip completion/cancellation/logout, fully stop and destroy the
  navigation session before returning to the shell.
- [ ] Never let search results silently replace the active route. Driver search
  during a trip may inspect/report places or add an admin-approved stop only
  through a new authoritative route version.

## 10. Traffic visualization on a fixed route

- [ ] Add the Mapbox Traffic v1 vector source after the style loads.
- [ ] Use source layer `traffic` and style congestion/closure classes at useful
  navigation zoom levels.
- [ ] Draw a casing for the prescribed route and choose route opacity/width so
  traffic remains visible without making the approved geometry ambiguous.
- [ ] Baseline implementation: show traffic on the nearby road network beneath
  and around the fixed route.
- [ ] Route-specific implementation: evaluate visible traffic features against
  a narrow corridor around the prescribed route and produce cached, clipped
  congestion segments. Do this only if device profiling shows acceptable CPU,
  memory, and frame time.
- [ ] Refresh visual traffic on a bounded interval/style update, not on every
  GPS sample.
- [ ] Never request or activate a new route because congestion changes.
- [ ] Calculate any delay estimate separately and label it as estimated. A
  traffic tile color by itself is not an ETA.
- [ ] Provide states for traffic unavailable, stale, unsupported locally, and
  offline.

## 11. Roads, polyline, and geofence equivalents

- [ ] Replace Google `LatLng` throughout domain and Firebase models with
  `GeoCoordinate`.
- [ ] Replace Google Roads single-point snapping during active guidance with
  Navigation SDK enhanced/map-matched location.
- [ ] Use Mapbox Map Matching only for a route trace or authoritative-route
  conversion, not as an unvalidated route author.
- [ ] Keep a provider-independent Polyline5 codec with malformed-input tests.
- [ ] Keep existing polygon/corridor point-in-area logic provider-independent.
- [ ] Move all geofence intersection and route-restriction checks to domain or
  trusted backend geometry modules.
- [ ] Later OS geofences may notify about terminals, zone exits, or restricted
  areas, but they cannot silently reroute a driver.
- [ ] Review whether permanent Android background-location permission is
  genuinely required and provide the required user disclosure/controls.

## 12. Performance requirements for lower-tier Android devices

- [ ] Maintain one map surface and one location/navigation owner.
- [ ] Use a lightweight 2D navigation style; disable terrain, 3D buildings,
  unnecessary pitch effects, and expensive decorative layers.
- [ ] Load traffic only for driver active guidance and only at useful zooms.
- [ ] Prefer style sources/layers for routes and larger feature sets; reserve
  annotations for a small number of interactive markers.
- [ ] Create style sources/layers once and update source data instead of
  repeatedly deleting/recreating the style graph.
- [ ] Cache decoded marker images and avoid per-frame bitmap generation.
- [ ] Throttle Flutter bridge events and UI rebuilds while retaining native
  guidance accuracy.
- [ ] Coalesce camera updates and do not invoke network routing from the GPS
  listener.
- [ ] Bound polyline length/point count and move unusually large geometry work
  off the UI isolate.
- [ ] Cancel stale search/reverse-geocode requests and apply timeouts/backoff.
- [ ] Measure cold start, map-ready time, active memory, dropped frames, battery
  drain, and teardown memory on a low-tier physical Android device.

## 13. Error and observability requirements

- [ ] Use typed failures for missing token, unauthorized token, forbidden
  account, quota/rate limit, bad request, empty result, unsupported geography,
  offline, timeout, server error, malformed route, route mismatch, missing
  address context, style failure, and native SDK failure.
- [ ] Do not collapse an API failure into an empty-result state.
- [ ] Redact tokens, full request URLs, passenger coordinates, and personal
  place text from production logs.
- [ ] Add correlation IDs for search sessions, route versions, navigation
  sessions, and missing-place submissions.
- [ ] Add crash-safe cleanup and recovery after process death.
- [ ] Add a system diagnostics section that reports configured/not configured,
  SDK versions, route version, and last redacted failure—never token values.

## 14. Google removal inventory

Remove only after Mapbox replacements pass acceptance tests:

- [ ] `google_maps_flutter`
- [ ] `google_maps_flutter_platform_interface`
- [ ] `flutter_polyline_points` if no non-Google consumer remains
- [ ] Google Places HTTP calls
- [ ] Google Geocoding HTTP calls
- [ ] Google Roads HTTP calls
- [ ] Google Routes HTTP calls in mobile
- [ ] Google Routes HTTP call and `GOOGLE_ROUTES_API_KEY` secret in Functions
- [ ] Google Maps Android manifest metadata and Gradle placeholders
- [ ] Google Navigation URI queries if external Google navigation is no longer
  a supported fallback
- [ ] iOS `comgooglemaps` query scheme if no longer required
- [ ] Google map configuration and API key Dart files
- [ ] All Google map controller, marker, polyline, polygon, circle, and bitmap
  descriptor types
- [ ] Generated plugin registrant changes produced by dependency removal
- [ ] Documentation and UI copy that still promises Google routes or Google
  traffic

Do not remove Firebase Google Services configuration or Google Sign-In. They are
not Google Maps dependencies.

## 15. Verification matrix

### Automated

- [ ] Polyline5 golden vectors, malformed strings, overflow, coordinate order,
  endpoint tolerance, and checksum tests.
- [ ] Route-restriction polygon/corridor intersection tests.
- [ ] Map-matched route deviation tests.
- [ ] Role-root exclusivity and map-runtime cleanup tests.
- [ ] Passenger search priority and stale-request cancellation tests.
- [ ] Reverse-label parser tests for every missing context combination.
- [ ] 20-meter matching, keyword similarity, third-distinct-user promotion,
  idempotency, and abuse tests.
- [ ] Firestore Rules and callable authorization tests.
- [ ] Booking route version/phase state-machine tests.
- [ ] Native bridge serialization and lifecycle tests.
- [ ] Static audit with zero Google Maps/Places/Roads/Routes references.
- [ ] `flutter analyze`, Flutter tests, Functions tests, admin tests/build, and
  Android release build.

### Physical-device scenarios

- [ ] Passenger login, pickup search, destination search, approved POI hit,
  Mapbox address hit, empty hit, manual pin, and booking creation.
- [ ] Passenger assigned-driver tracking and current-trip screen parity with
  the existing design.
- [ ] Driver login with no booking, assigned booking restore, approach
  navigation, arrival, passenger onboard, destination navigation, payment, and
  completion.
- [ ] Maneuver banner, voice, mute, recenter, overview, traffic, chat, call,
  report, and booking actions.
- [ ] App background/foreground, screen rotation policy, process death,
  network loss/recovery, GPS loss, token failure, and style failure.
- [ ] Off-route warning without reroute.
- [ ] Role/account switch with no retained map, listener, location, or voice
  activity.
- [ ] Bacolod traffic and address coverage validation.
- [ ] Low-memory Android profiling and 30-minute active-guidance soak test.

## 16. Implementation phases

- [ ] Phase 0 — credentials, version compatibility spike, and architecture
  tests.
- [ ] Phase 1 — provider-independent coordinates, Polyline5 codec, errors, and
  runtime coordinator.
- [ ] Phase 2 — Mapbox passenger/idle map primitives and shared tracking.
- [ ] Phase 3 — approved POI search, Geocoding v6, manual pin, and missing-place
  moderation.
- [ ] Phase 4 — admin route authoring, trusted route publication, and booking
  route contract.
- [ ] Phase 5 — Android native Navigation SDK bridge and driver active-guidance
  UI.
- [ ] Phase 6 — traffic visualization, off-route alerts, and geofence hooks.
- [ ] Phase 7 — remove all Google Maps/Places/Roads/Routes dependencies and
  credentials.
- [ ] Phase 8 — regression, security, performance, billing review, staged
  release, and rollback verification.

## 17. Go-signal requirements

Before implementation begins:

- [ ] Owner sends `GO MAPBOX MIGRATION`.
- [ ] Owner creates a new mobile `pk.` token; do not paste it into chat.
- [ ] Owner creates an Android `sk.` downloads token with Downloads:Read only;
  do not paste it into chat or a repository file.
- [ ] Owner confirms whether first-release active guidance is Android-only or
  Android and iOS.
- [ ] Owner confirms the authority model for dynamic driver-to-pickup routes:
  trusted-backend frozen route is the recommended default.
- [ ] Owner acknowledges that Philippine Search Box POI coverage and
  guaranteed-free traffic are not available assumptions.

## Official references used for this gate

- Mapbox Maps SDK for Flutter:
  https://docs.mapbox.com/flutter/maps/guides/
- Flutter SDK installation and public token handling:
  https://docs.mapbox.com/flutter/maps/guides/install/
- Mapbox token scopes and restrictions:
  https://docs.mapbox.com/accounts/guides/tokens/
- Android Navigation SDK installation:
  https://docs.mapbox.com/android/navigation/build-with-nav-sdk/installation/
- Android Navigation SDK guides:
  https://docs.mapbox.com/android/navigation/guides/
- Map Matching API:
  https://docs.mapbox.com/api/navigation/map-matching/
- Mapbox Traffic v1:
  https://docs.mapbox.com/data/tilesets/reference/mapbox-traffic-v1/
- Search Box API geography, limits, and storage:
  https://docs.mapbox.com/api/search/search-box/
- Geocoding v6 storage and reverse context:
  https://docs.mapbox.com/api/search/geocoding-v6/

