# VolTrike Mapbox transition completed work

This is an append-only completion log. An item belongs here only after it has
been verified. Planned work stays in `TODO.md`.

## 2026-07-27 — architecture gate

- Completed a read-only audit of the Flutter role routing, passenger and driver
  shells, map widgets, shared ride tracking, navigation controllers, Places,
  Geocoding, Roads, Routes, traffic, polylines, route restrictions, booking
  model/repository, Firebase Functions, Android/iOS map declarations, and the
  admin Mapbox polygon editor.
- Counted 35 Dart files directly coupled to `google_maps_flutter`.
- Identified six source files with direct Google map-service endpoints across
  mobile and Functions.
- Verified that the existing admin dashboard already has a separate Mapbox web
  token but does not yet publish authoritative booking route polylines.
- Verified that the current booking payload does not contain a versioned
  authoritative route contract.
- Verified that the current driver experience renders Google route data but is
  not native Mapbox active guidance.
- Verified official Mapbox token separation, Flutter Maps requirements,
  Navigation SDK lifecycle, custom-route map matching, rerouting controls,
  Traffic v1 behavior, Search Box geography, Geocoding v6 context/storage, and
  attribution requirements.
- Chose a separate mobile public token and separate Downloads:Read secret token;
  the admin web token will not be reused by mobile.
- Chose a first-party native Navigation SDK bridge for real turn-by-turn
  guidance from an admin-locked route.
- Chose approved Firestore POIs plus Mapbox Geocoding v6 plus manual pin for the
  Philippine search failsafe.
- Defined the migration phases, target boundaries, cleanup rules, security
  model, test matrix, and Google-removal inventory in `TODO.md`.

## Source-change declaration

No existing application, admin, Firebase, Android, iOS, dependency, credential,
or generated source file was changed during this architecture gate. Only this
transition documentation folder was added.

