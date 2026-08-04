# VolTrike Documentation Revision TODO

Status: implemented and verified after the user's explicit **go**. This file remains the scope contract, evidence record, and delivery checklist.

Last planning update: 2026-08-04

## 1. Scope contract

- Treat `VolTRrike 3 (1) (1).docx` as the editable master and `VolTRrike 3 (1).pdf` as the fixed visual/page-reference baseline.
- Preserve the originals. Implementation must begin from a copy in the repository output folder.
- Revise only Chapters I, II, III, and VI, plus the Glossary and References.
- Allow only the dependent document maintenance needed to keep those revisions usable: table of contents, list of figures, list of tables, captions, numbering, cross-references, and pagination.
- Do not rewrite or add unrelated Chapters IV and V.
- Preserve the proposal's academic voice, sequence, typography, tables, and activity-flow style. Prefer precise local edits over wholesale rewriting.
- Keep proposal/future tense where the document is describing the proposed system. Do not turn the proposal into a completed-study report.
- Use the implementation as the truth source for technical design. Remove, qualify as future work, or cite any statement that is not supported by the code.
- Documentation work does not authorize application-code changes. If a documented recommendation is not actually implemented, report it honestly instead of modifying code or inventing proof.
- Correct all in-scope occurrences of **Quezon City** to **Bacolod City**.
- Correct the mobile technology from **React Native** to **Flutter with Dart**. React remains valid only when describing the separate web administration portal.
- Keep System Admin and TODA Admin as distinct authorization roles even though they use one role-aware admin portal.
- Build a separate appendix response-matrix Word file using only the example's table format. Do not copy its research content, names, minutes, signatures, or metadata.
- Do not guess the proponents. The new matrix will have only the four requested columns and no Proponent column.

## 2. Frozen source baseline

| Source | Purpose | Baseline details |
|---|---|---|
| `C:\Users\Vincent\Downloads\VolTRrike 3 (1) (1).docx` | Primary editable proposal | Latest readable baseline used for implementation: 7 tables; 111 sections; SHA-256 `FF9A6EC848E6586DA579D8DB053EB04821B44B7761BBA1C922A5EED2493729BE` |
| `C:\Users\Vincent\Downloads\VolTRrike 3 (1).pdf` | Visual and page-reference baseline | 78 pages; SHA-256 `DA5AB1083F6B4615B75E4C4701C98CEFEA2488A9775BD2ACC753230BF186ADCE` |
| `C:\Users\Vincent\Downloads\Example appendix(no do unrelated take format).docx` | Format reference only | 2 pages; SHA-256 `6418036E08BC54FB73E22E0F3BF7DB100A47DB8D93FEEB8840FB38AFEF23C83E` |
| Current repository `HEAD` | Implementation truth after defense | `619967a` on 2026-08-04 when audited |
| Defense repository version | Before/after comparison | `3704982380b8884a756c33a1df389ce78bbbd23f`, dated 2026-07-28 |

Recheck all hashes and the current `HEAD` immediately before implementation. The Word source may be open in Microsoft Word; never force-close an unknown user process. Copy it only when it is readable without interfering with the user's session.

### Proposal page map

| Content | Physical PDF pages | Printed document pages |
|---|---:|---:|
| Chapter I | 9-19 | 1-11 |
| Chapter II | 20-33 | 12-25 |
| Chapter III | 34-57 | 26-49 |
| Chapter VI | 58-66 | 50-58 |
| Glossary | 67-70 | 59-62 |
| References | 75-77 | 67-69 |

## 3. Implemented deliverables

Create two separate Word files; never overwrite the supplied documents.

1. `output/docs/VolTrike_Proposal_Implementation_Aligned.docx`
   - Full proposal copy with only the authorized chapters, glossary/references, and dependent navigation fields revised.
   - Existing cover, front matter, chapter order, and overall visual identity retained.
2. `output/docs/VolTrike_Recommendations_Actions_Proof.docx`
   - Table only.
   - Four columns: Chapter/Section, Recommendations/Suggestions, Actions Taken, Proof.
   - Exactly the five defense recommendations listed in section 9 of this plan.

Working renders and temporary inspection artifacts may be produced during verification, but only the two polished `.docx` files are final deliverables.

## 4. Code-backed system truth sheet

Use this sheet to reconcile repeated claims before editing prose, tables, and diagrams.

### 4.1 Architecture and technology

Canonical short description to adapt throughout the manuscript:

> VolTrike consists of a Flutter/Dart mobile application for passengers and drivers, a React/TypeScript/Vite web portal shared by System and TODA administrators, Node.js Firebase Cloud Functions for trusted backend operations, Firebase managed services for authentication and data, and an optional Rust native performance layer with Dart fallbacks.

| Area | Verified implementation | Stable evidence |
|---|---|---|
| Passenger/driver mobile app | Flutter and Dart | `pubspec.yaml`, `lib/main.dart`, `lib/app/router.dart` |
| State/navigation | Riverpod and `go_router` | `pubspec.yaml`, providers/controllers under `lib/`, `lib/app/router.dart` |
| Authentication | Firebase Authentication | `lib/data/services/auth_service.dart`, Firebase initialization/configuration |
| Durable application data | Cloud Firestore | repository classes under `lib/data/repositories/`, `firestore.rules`, Cloud Functions |
| Live/ephemeral location data | Firebase Realtime Database where used by the location pipeline | location repositories/controllers, `database.rules.json`/Firebase configuration |
| Files | Firebase Storage with role/type/size rules | `storage.rules`, registration upload services |
| Server authority | Firebase Cloud Functions on Node.js 22 | `functions/package.json`, `functions/index.js` |
| Notifications | Firebase Cloud Messaging and local notifications | `pubspec.yaml`, notification services, Cloud Functions |
| Mobile map/navigation | Google Navigation/Maps integration | `pubspec.yaml`, `lib/core/maps/`, route/navigation services |
| Web administration | React, TypeScript, and Vite | `admin/package.json`, `admin/src/App.tsx` |
| Admin map editing | Mapbox GL in the web portal | `admin/package.json`, coverage/restriction map components |
| Native acceleration | Rust through Flutter Rust Bridge | `rust/Cargo.toml`, `rust/src/`, generated bridge code, Dart adapters |
| Authorization | Firebase claims, Firestore rules, and server-side role/scope checks | `firestore.rules`, `storage.rules`, `functions/index.js` |

Do not describe the mobile client as React Native. Do not describe the whole system as React merely because the admin portal uses React.

Email/password authentication is implemented. Although a Google Sign-In dependency and standalone button exist, no active controller/repository uses them; do not document Google login as implemented.

### 4.2 Users and access boundaries

- **Passenger:** self-registers in the Flutter app; provides name, phone, email, password/confirmation, and legal consent; email verification is part of account handling.
- **Driver applicant:** completes a guided five-step Flutter registration flow, submits personal/address/TODA/vehicle information and evidence, then remains pending until review.
- **TODA Admin:** uses the web portal; onboards the organization and administrator, submits legal identifiers/evidence, verifies email, and remains pending until System Admin approval. Once approved, access is limited to the assigned TODA.
- **System Admin:** uses the same web portal but has platform-wide authority. First-time creation is protected by a one-time server-side bootstrap path; it is not a public selectable registration role.
- `developer_admin` is the internal code value. User-facing documentation should call this role **System Admin**, with one parenthetical code-name explanation only if technically necessary.
- The shared portal is a common entry surface, not a merged permission model.

### 4.3 Driver registration and review

The code-backed driver flow requires:

- first, middle, and last name; date of birth; phone; email; and password;
- PSGC-based region, province, city/municipality, and barangay selection;
- TODA selection from active TODAs;
- plate number, vehicle type, brand, model, color, and seating capacity;
- profile photo, driver's-license front and back, government ID, official receipt, certificate of registration, and vehicle photo;
- acceptance of the Terms and Conditions and Privacy Policy;
- an age check of at least 18 years;
- a review/edit screen before “Submit for TODA Review”;
- a pending driver status and unavailable/offline state until approval.

The applicant does not self-certify every reviewed license field. The TODA review can record verified license information after examining the submitted images. Do not claim OCR; the actual image pipeline crops, resizes, compresses, and validates resource limits.

Stable evidence:

- `lib/data/models/driver_registration_data.dart`
- `lib/features/auth/services/driver_registration_review_policy.dart`
- `lib/data/mappers/driver_registration_mapper.dart`
- `lib/features/auth/presentation/screens/driver_registration/`
- `lib/features/auth/services/registration_image_preparer.dart`
- `rust/src/api/registration_image.rs`

### 4.4 Booking lifecycle

Use the exact implemented states in text and activity flows:

`pending -> driverAssigned -> driverArriving -> passengerOnBoard -> paymentConfirmation -> completed`

Cancellation is allowed only in the code-approved pre-onboard states. Booking creation, acceptance/decline, state transitions, cash confirmation, driver receipt acknowledgment, and settlement dispute handling are server-authoritative callable functions.

Stable evidence:

- `lib/data/models/booking.dart`
- `lib/data/models/booking_state_machine.dart`
- `lib/data/repositories/booking_repository.dart`
- lifecycle callables in `functions/index.js`
- booking state-machine and legacy-parsing tests under `test/`

Do not reduce the implemented lifecycle to only `pending -> assigned`. Do not say every available driver is notified simultaneously unless the current dispatch implementation proves that exact behavior.

### 4.5 Driver matching

The verified dispatch ranking uses:

1. service/TODA priority;
2. a 100-meter distance band;
3. the driver's daily award count for fairness;
4. smoothed reliability;
5. smoothed quality/rating;
6. exact distance;
7. deterministic time/driver-ID tie breakers.

Evidence: `functions/dispatch-policy.js` and its tests.

Do not claim battery percentage is a matching factor. Remove the hard-coded “within 5 km” wording unless the exact currently configured candidate policy is verified at implementation time.

### 4.6 Fare, cash payment, and settlement

The current default configurable fare policy is:

- base fare: PHP 20;
- first 1,000 meters included;
- PHP 5 per additional 500 meters;
- PHP 40 per additional passenger;
- PHP 20 per baggage item;
- PHP 20 outside-TODA surcharge.

Evidence: `functions/fare-policy.js`; the portal's fare configuration; booking fare snapshots and breakdowns.

The implemented payment lifecycle is cash-based, with confirmation, receipt acknowledgment, commission/settlement snapshots, and dispute support. Do not claim GCash, Maya, PayMongo, Xendit, card processing, or multiple active payment methods unless code is added later. Describe configured values as defaults, not immutable legal fares.

### 4.7 Maps, service areas, and route restrictions

- TODA coverage is polygon-based and used to classify pickup/destination relationships.
- Developer-managed restrictions can be polygons or corridors and are enforced through local/server route policy logic.
- Google highway avoidance is advisory; the routing provider may not always honor it completely.
- Local point, polygon, corridor, endpoint, and route-intersection checks provide additional enforcement.
- The current mobile map renders red route-restriction polygons with visible borders.
- The audit did **not** yet prove that the approved TODA coverage polygon itself is drawn as a visible border on passenger and driver maps.
- Mobile in-app turn-by-turn guidance is an Android pilot. Do not present it as a fully equivalent cross-platform feature.

Evidence:

- `lib/core/maps/restriction_polygons.dart`
- `lib/core/maps/voltrike_map.dart`
- `lib/features/passenger/presentation/widgets/map_view.dart`
- `lib/features/driver/presentation/widgets/driver_map_view.dart`
- `lib/core/services/toda_coverage_service.dart`
- `lib/core/services/route_restriction_service.dart`
- `functions/service-area-policy.js`
- `functions/routes-policy.js`

Documentation must distinguish a **TODA service-area boundary** from a **route-restriction border**. Do not use the two terms interchangeably merely to satisfy the appendix.

### 4.8 Administration, safety, and communication

- One React/Vite admin portal authenticates both roles.
- System Admin sees platform-wide TODAs, fares, drivers, ride operations, safety, violations, reports, coverage areas, and route restrictions.
- TODA Admin sees only authorized TODA-scoped drivers, live operations, commission, ratings, rides, safety, violations, reports, and coverage requests.
- Firestore rules and Cloud Functions enforce role/scope boundaries; the distinction is not only visual navigation.
- Reports, SOS/safety incidents, violation cases, ratings, in-app chat, and voice-call support exist in code.
- External emergency dispatch remains a development placeholder and must not be described as an integrated public emergency service.

Evidence: `admin/src/App.tsx`, `firestore.rules`, `functions/index.js`, safety/report repositories and screens, chat/call services.

### 4.9 Optimization

Code-backed optimization evidence includes:

- Rust-accelerated registration-image work with a Dart fallback;
- Rust route-geometry/navigation work;
- compact PSGC indexing and cached lookup data;
- cached TODA coverage and route-restriction data;
- lazy-loaded heavy admin map/violation components;
- focused unit, integration, policy, and benchmark/performance tests.

Use measured results only where a reproducible benchmark or test output is available. Do not retain unsourced claims such as an APK under 25 MB, a universal 1 GB/4 GB RAM threshold, exact update intervals, or percentage speedups.

Recorded proof candidates, to be rerun or clearly labeled by device/build before use:

- `test/fixtures/psgc_benchmark_sm_a566b_profile.json`
- `test/fixtures/geometry_v2_benchmark_sm_a566b_profile.json`
- detailed recorded results in `done.md` around its performance-evidence section
- recorded compact PSGC artifact: 3,474,156 bytes versus 11,383,135 bytes of legacy JSON, approximately 69.5% smaller;
- recorded SM-A566B compact-Dart PSGC initialization: 37,466 microseconds versus 193,116 microseconds for legacy JSON decode;
- recorded SM-A566B registration-image median: Rust 132,184 microseconds versus Dart 1,805,448 microseconds.

These are profile-specific results, not universal guarantees. Geometry, PSGC, and navigation Rust rollout modes default to `off`; compact Dart remains the normal PSGC path/fallback. Registration-image preparation uses native `auto` where supported with a Dart isolate fallback.

## 5. Claims that require removal, qualification, or proof

Do not carry these forward as implemented facts without fresh code/test/source evidence:

- offline maps or a full offline operating mode;
- battery-based MCDM dispatch;
- carbon-savings calculations or environmental reports;
- GCash, Maya, PayMongo, Xendit, card, or other digital payment integration;
- OCR of registration documents;
- live LGU/LTO database verification;
- generic AWS hosting;
- saved Home/Work addresses;
- five-attempt account lockout;
- fixed five-kilometer matching;
- reverse-geocoded alternative destinations and manual trip approval;
- guaranteed traffic-aware ETA refresh intervals or route-history caching;
- completed Play Store deployment, monetization, pilot evaluation, training videos, or hotline services;
- exact APK-size, RAM, latency, fine, emissions, smartphone-penetration, driver-income, or uptime claims without authoritative evidence.
- Google OAuth/Google Sign-In;
- passenger-side manual selection of nearby drivers;
- a persistent notification inbox or badge;
- saved Home/Work/recent destinations;
- automatic contact with an external emergency-dispatch service (the current app records/escalates an SOS and opens a manual dialer);
- Firebase Crashlytics;
- a Flutter/mobile administrator module—the implemented administration surface is the web portal;
- production Android release signing;
- persistent mobile visualization of approved TODA coverage borders.

If a useful proposal idea is intentionally retained, label it clearly as a recommendation, planned enhancement, or future scope.

## 6. Editing and terminology rules

- Use **VolTrike** consistently for product references because that is the current repository/UI spelling. Preserve an institution-approved cover-title stylization only if it is demonstrably intentional.
- Use **Bacolod City**, **e-trike**, **TODA**, **System Admin**, and **TODA Admin** consistently.
- Use **zero tailpipe emissions**, not “zero emissions.”
- Firebase is a Google application-development/backend platform, not an “open source architecture.”
- Firebase Authentication owns credentials. Firestore may store permitted profile/application data; it does not store user passwords.
- Describe Firestore and Realtime Database as distinct components used for different data needs, not as interchangeable alternatives.
- Describe geofences/coverage areas as polygons when discussing this implementation, not automatically as circles.
- State that server-side validation and security rules enforce sensitive operations; avoid vague absolute claims such as “fully secure.”
- Do not call the mobile app a web app. Identify the Flutter mobile app and React web portal separately.
- Preserve existing citation style only after choosing and applying one consistent convention throughout all edited sections and the reference list.

## 7. Chapter-by-chapter revision plan

### Chapter I — Introduction

- Preserve the Bacolod last-mile mobility problem, e-trike focus, passenger safety, fare transparency, and SDG 13 narrative.
- Correct or cite claims about emissions, oil dependence, job creation, and driver income. Prefer restrained proposal language.
- Retain the related-system comparison, but verify claims about Pedi, Grab, and JoyRide and briefly state why each comparison is relevant.
- Reconcile “mobile application” with the implemented Flutter passenger/driver app plus the separate web administration portal.
- In Section 1.3.1, add one concise role/onboarding paragraph:
  - passenger self-registration;
  - driver application with TODA, vehicle, and document review;
  - TODA Admin web onboarding and System Admin approval;
  - distinct System Admin/TODA Admin permissions.
- Keep registration rationale simple: identity/contact supports accountable accounts; TODA and address data establish operational scope; vehicle and document evidence supports TODA review. Do not turn Chapter I into a field-by-field specification.
- Reconcile scope/deliverables with the verified features. Remove or mark unsupported items as future work.
- Do not claim a completed pilot, fully working production release, training package, or evaluation report unless evidence is supplied.

### Chapter II — Review of Related Technologies / Technical Background

- Reconcile the chapter's six feature groups with Chapter III's function decomposition.
- Make the driver-verification discussion consistent with the actual five-step flow and review status.
- Mention only code-required evidence: profile photo, driver's-license images, government ID, OR, CR, and vehicle photo. Do not claim OCR, insurance/NBI/PNP requirements, automatic expiry monitoring, or direct government-database integration unless separately implemented and evidenced.
- Resolve the 1 GB versus 4 GB hardware contradiction using tested devices or explicitly labeled target/recommended specifications.
- In Section 2.2.2 and Table 3:
  - replace React Native with Flutter;
  - add Dart;
  - separate the React/TypeScript/Vite admin portal from the Flutter mobile app;
  - list Firebase Authentication, Firestore, Realtime Database, Storage, Cloud Functions, and Cloud Messaging only in their actual roles;
  - list Google mobile navigation/maps and Mapbox admin mapping separately;
  - mention Rust/Flutter Rust Bridge only where the optimization discussion needs it.
- Rebuild Table 3 so technology names and descriptions align correctly and “Firebase Authentication” is inside the table.
- In Section 2.3.1, document the optimization approach without unverified performance numbers.
- Replace generic AWS/GCP/provider lists and speculative payment providers with the actual Firebase/Google Cloud deployment and cash lifecycle.
- Rewrite the chapter summary only after the stack and feature groups are final.

### Chapter III — Design and Methodology / Functional Design

#### Preserve the existing function-table pattern

Keep the format shown in the supplied “Request and Booking” example:

1. Function Name
2. Function Description
3. Precondition
4. Post Condition
5. Activity Flow
6. Alternate Flow
7. Exception

Retain the table-and-swimlane visual style, typography, borders, and chapter flow. Update actors, decisions, labels, and arrows only where needed to match code. Do not replace these sections with plain prose or a completely different diagram language.

For each activity flow:

- use role-specific lanes appropriate to the function;
- distinguish the Flutter client from server-authoritative Cloud Functions/Firebase where relevant;
- use exact booking/account/review statuses;
- make alternate and exception branches readable without crossing text or clipped captions;
- keep wording brief enough to fit the current table geometry;
- regenerate the figure/table rather than pasting a low-resolution screenshot.

#### Section 3.1 and decomposition chart

- Correct Quezon City to Bacolod City on physical PDF page 35 / printed page 27.
- Remove unsuitable copied language such as “empty space on the bus” and fuel-burning-turn language applied to electric vehicles.
- Update the decomposition chart minimally so it agrees with the functions documented below.
- Normalize “System Decomposition Chart” versus “Application Decomposition Chart.”

#### Section 3.2.1 — User Account Management

- Preserve the current function block, but describe actual passenger, driver, TODA Admin, and System Admin entry/approval paths.
- Do not allow a public user to select an administrator role.
- Use Firebase Authentication for credentials and Firestore for permitted profiles/applications.
- Include email verification and driver/TODA pending-approval gates only as implemented.
- Replace any unsupported five-attempt lockout statement.
- The detailed five-step driver flow may be added as a separate same-format function subsection if fitting it inside 3.2.1 would make the existing flow unreadable.

#### Section 3.2.2 — Request and Booking

- Keep the pictured function table and swimlane structure.
- Correct **Quezon City geofence** to **Bacolod City service area** on physical PDF page 46 / printed page 38.
- Replace the simplified postcondition with the actual pending booking and driver-offer behavior; acceptance leads to `driverAssigned`, not a generic `assigned` value.
- Update the flow to cover fare/route validation, server-side booking creation, eligible-driver offers, acceptance/decline/timeout, assignment, and the no-driver outcome.
- Do not state that all drivers are notified at once or that a fixed five-kilometer rule always applies.
- Express the service-area exception using the actual pickup/destination coverage classification and route restrictions. Do not imply every cross-TODA destination is invalid if the configured policy allows it with a surcharge.

#### Section 3.2.3 — GPS Tracking and Map Display

- Preserve the existing function structure.
- Align location storage/update wording with the actual mobile controller, Realtime Database/Firestore responsibilities, and navigation pipeline.
- Document the current route colors: blue active route and high-contrast yellow passenger preview with a dark casing.
- Remove conflicting exact 5/10/15-second refresh promises unless verified by current constants and tests.
- Do not guarantee traffic behavior beyond what the Google route request/provider supports.

#### Section 3.2.4 — Geofence and Route Compliance

- Preserve the existing function structure.
- Define TODA coverage polygons separately from route-restriction polygons/corridors.
- Explain pickup-outside, same-zone, and cross-boundary handling according to the actual policy.
- Explain that highway avoidance is advisory, while local/server restriction checks can block or warn based on the configured policy.
- Remove “intercountry trips,” reverse-geocoded alternatives, and manual administrator trip approval unless found in current code.
- Only state that the geofence border is visible if the intended TODA coverage boundary is actually rendered. A visible restriction polygon alone is insufficient proof.

#### Section 3.2.5 — Fare Calculation and Payment

- Preserve the existing function structure.
- Replace the proposed zone matrix/PHP 15-per-kilometer fallback with the actual configurable fare snapshot and breakdown.
- Describe the cash confirmation, driver acknowledgment, commission snapshot, settlement, dispute, and receipt behavior at the appropriate level.
- Remove unsupported payment gateways.

#### Same-format additions to consider

Add only the functions needed to reconcile Chapters I, II, and VI with the implementation. Use the same seven-part function table and swimlane format, not a new style.

1. **Driver Registration, Verification, and TODA Approval**
   - Driver Applicant | VolTrike | TODA Admin/Firebase lanes.
   - Five-step submission, validation, evidence upload, pending review, approval/decline, and unavailable-until-approved behavior.
2. **System Admin and TODA Admin Operations**
   - Administrator | Shared Web Portal | Firebase/Cloud Functions lanes.
   - One portal, role-aware navigation, platform-wide versus TODA scope, and protected actions.
3. **Safety, Reports, and Violations**
   - Passenger/Driver | VolTrike | TODA Admin/System Admin lanes.
   - SOS/report creation, trusted booking context, scoped review, resolution, and restriction/violation handling.

4. **Ride Lifecycle and Completion**, only if Section 3.2.2 and the fare/payment section cannot clearly show it without becoming crowded
   - Passenger | VolTrike/Cloud Functions | Driver lanes.
   - `pending`, `driverAssigned`, `driverArriving`, `passengerOnBoard`, `paymentConfirmation`, `completed`, and valid cancellation branches.
   - Cash confirmation and driver receipt acknowledgment at the correct states.

Integrate ratings and settlement into the existing fare/post-trip function unless a separate diagram is necessary for readability. Mention chat/voice only if it is already within the proposal's intended scope; do not add every coded feature simply because it exists. Architecture, data authority, security, and performance can be explained in Section 3.1/subsections without forcing a full activity table for every technical component.

#### Chapter III numbering/layout repairs

- Reconcile TOC title “User Account Sign-in and Sign-out” with body title “User Account Management.”
- Renumber body Tables 5-9 so they match the list of tables and remove the duplicate Table 9.
- Refresh narrative table references.
- Inspect the activity-flow layouts corresponding to physical PDF pages 38, 40, 42, 46, 49, 52, and 55 for collisions, clipped text, and unclear branch arrows.
- Fix the Password Recovery caption/exception collision around physical PDF page 42.

### Chapter VI — Implementation Plan / Resources and Testing

- Align device requirements with Chapter II and with actual tested/target devices; label minimum, recommended, and tested specifications separately.
- Identify Flutter SDK, Dart, Android/Gradle tooling, Firebase services, Google navigation/maps, the React admin portal, Mapbox admin mapping, and Rust only where each is actually used.
- In Section 6.3, make user classification explicit:
  - Passenger;
  - Driver Applicant/Approved Driver;
  - TODA Admin;
  - System Admin.
- Explain the shared admin portal and separate role permissions. System Admin sets platform restrictions/quality controls; TODA Admin reviews and manages only its assigned operational scope.
- Remove e-bike and gasoline-price scope drift.
- State that Firebase reduces infrastructure management; it does not eliminate security, monitoring, backup, support, or release work.
- Keep monetization, subscriptions, preferred visibility, Play Store rollout, and assisted installation as future recommendations unless evidenced.
- Separate planned testing from completed tests. Any completed claim must point to a reproducible unit/integration test, build artifact, benchmark, or approved usability record.
- Rewrite the chapter summary after the technical and role sections are consistent.

## 8. Glossary and References plan

### Glossary

- Correct the Firebase and Firestore definitions.
- Change e-trike “zero emissions” to “zero tailpipe emissions.”
- Define coverage/geofence polygons accurately.
- Verify TNVS/LTFRB terminology before claiming direct LTFRB management of VolTrike/TODA operations.
- Keep MCDM only if defined using the actual matching factors; remove battery from the definition.
- Remove the exact five-second location-update claim unless proven.
- Consider adding concise entries for Flutter, Dart, System Admin, TODA Admin, driver approval status, and booking status.
- Normalize capitalization across the glossary and body.

### References and registration rationale

- Fix the `[ADB2012]` inline citation versus `{AD2022}` reference-key mismatch.
- Standardize square-bracket/brace conventions and reference formatting.
- Repair broken URLs and incomplete metadata.
- Remove uncited sources or cite them at the exact supported claim.
- Use current official sources for any retained legal/regulatory registration claim:
  - LTO sources for driver's-license and vehicle OR/CR terminology;
  - Bacolod City/BPLO/Sangguniang Panlungsod or other competent local authority for local permits/resolutions;
  - official TODA/LGU policy, if publicly available, for association review requirements.
- Do not call every code-required upload a universal legal requirement. If no authoritative source supports it, describe it as a **VolTrike/TODA verification requirement**.
- Keep the main reference list concise. Put the short “why this is needed” explanation in Chapter I or II next to the registration discussion unless the institution explicitly requires an annotated bibliography.
- If technical stack statements need citations, prefer official Flutter, Firebase, Google Navigation, Mapbox, and Flutter Rust Bridge documentation.
- Because laws and local requirements can change, verify official sources immediately before the Word revision rather than relying on remembered requirements.

## 9. Separate recommendations/actions/proof matrix

### 9.1 Content contract

The final appendix-derived file must contain only one table with these exact headers in this order:

1. `Chapter/Section`
2. `Recommendations/Suggestions`
3. `Actions Taken`
4. `Proof`

Do not include a title, appendix heading, minutes, date/time, school/panel information, narrative, closing statement, signatures, names, or Proponent column. If the school later mandates a Proponent field, add it only after the user supplies the names; never infer them.

### 9.2 Planned rows

| Chapter/Section | Recommendations/Suggestions | Draft factual action direction | Proof to capture/verify |
|---|---|---|---|
| Chapter III - 3.2.3 GPS Tracking and Map Display | Change the route direction design from black. | State that the defense-era black default was changed to a blue active route and a yellow passenger preview with dark casing. | Defense `lib/core/maps/voltrike_map.dart` at `3704982`; current `lib/core/theme/app_colors.dart`; `lib/core/maps/voltrike_map.dart`; passenger map screenshot; commit `ffc5546`. |
| Chapter VI - 6.3 User Classification | Combine Admin and TODA on one Admin page. | Mark as **partially adopted/retained by design**: both roles use one login/portal, while System Admin and TODA Admin remain separate roles with different authority. Do not claim the shared portal was newly created after defense because it already existed at `3704982`; say it was retained and expanded. | `admin/src/App.tsx` role-aware navigation/access; `firestore.rules`; server role checks in `functions/index.js`; screenshots of both role views; relevant post-defense admin additions. |
| Chapter III - 3.2.1 User Account Management | Improve the user interface and user experience of the registration form. | State that registration was reorganized into guided steps with validation, cascading PSGC/TODA selection, document capture/preview, review/edit controls, legal consent, and image preparation. | Commits `fb76c17`, `5da8351`, `4c8d4c5`; screens under `lib/features/auth/presentation/screens/driver_registration/`; validation and image-preparation tests; approved screenshots. |
| Chapter III - 3.2.4 Geofence and Route Compliance | Make the geofence border visible on the map. | Do not finalize as completed yet. Current code proves visible red **route-restriction** polygon borders, but not necessarily an approved TODA **coverage-geofence** border. If the panel meant restrictions, describe that precisely. If it meant TODA coverage, mark the action pending unless a current screen/code path proves it. | `lib/core/maps/restriction_polygons.dart`; `lib/core/theme/app_colors.dart`; passenger/driver map integrations; `ffc5546`; final screenshot identifying exactly which polygon is shown. |
| Chapter II - 2.3.1 Optimization of Budget Devices and Scalability | Optimize the application. | State the concrete optimizations only: Rust-backed image/geometry/navigation work with fallbacks, compact PSGC indexing, caches, lazy-loaded admin modules, and tested performance work. | Commits `cd2e3f6` and `5089530`; `rust/`; Dart adapters/services; PSGC/cache code; lazy imports in `admin/src/App.tsx`; reproducible tests/benchmark output. |

Final Actions Taken cells must be short, past tense, and factual. Final Proof cells must point to a precise file/symbol, commit, test result, document page, or approved screenshot. Do not use vague text such as “see the system.”

### 9.3 Table formatting contract distilled from the example

- One Letter-size portrait section.
- 0.55-inch margins, used to keep the five-row matrix on one portrait page.
- One continuous fixed-layout table at the top of the document.
- Total width: 10,656 twips / 7.4 inches.
- Column widths:
  - Chapter/Section: 2,300 twips;
  - Recommendations/Suggestions: 2,940 twips;
  - Actions Taken: 2,900 twips;
  - Proof: 2,516 twips.
- Times New Roman, 9.5 pt, regular, black text on white cells.
- Left-aligned, naturally wrapped text; zero paragraph-after spacing; approximately 1.07 line spacing.
- Black single grid borders, 0.5 pt.
- Approximately 108-twip left/right cell padding and no forced row heights.
- Repeat the header row on later pages.
- Avoid splitting short rows across pages.
- Vertically center a merged Chapter/Section cell only if multiple recommendations later share one section.
- Do not reproduce the source's negative table indent, manual blank paragraphs, split table, non-repeating page-two header, or content-specific fixed heights.

## 10. Bonus defense-version comparison

Use `git diff 3704982..HEAD` as supporting evidence, not as a substitute for current-code inspection.

| Recommendation | At defense commit `3704982` | Current audited state | Documentation status |
|---|---|---|---|
| Route direction color | `VolTrikePolyline` defaulted to `Colors.black`. | Default active route is blue; passenger preview is yellow with dark casing; restriction overlays are red. | Strong before/after proof. |
| Admin/TODA combination | A shared React admin portal and distinct roles already existed. | Shared portal retained and expanded; roles and server-side scopes remain distinct. | Describe as retained/expanded and partially adopting the suggestion, not newly combined. |
| Registration UI/UX | Earlier registration flow existed. | Post-defense commits add the guided/review/edit/upload improvements. | Strong commit and screenshot proof. |
| Visible geofence border | No equivalent current overlay proof was identified at defense. | Red restriction polygons now render, but TODA coverage-boundary rendering is unconfirmed. | Conditional; resolve terminology before claiming completion. |
| Optimization | Earlier baseline lacked the current measured Rust/performance work. | Rust core, compact data/indexing, caching, navigation work, and tests were added. | Strong code/commit proof; only quote measured numbers if reproduced. |

Relevant post-defense commits already identified:

- `fb76c17` - registration and operations-safety overhaul;
- `5da8351` - driver registration review flow;
- `4c8d4c5` - driver registration upload fix;
- `cd2e3f6` - measured Rust performance core;
- `5089530` - R3 performance and Rust navigation;
- `ffc5546` - restricted-area overlays and yellow route preview;
- `e1ae0dd` - user-facing Developer Admin name changed to System Admin;
- later operations/restriction/admin fixes must be reviewed from the exact final `HEAD` before delivery.

## 11. Global consistency and layout repairs

- Replace the two in-scope Quezon City occurrences identified on physical PDF pages 35 and 46 with Bacolod City, then search the entire final document for any additional variants.
- Replace the mobile React Native occurrence on physical PDF page 26 and update both its paragraph and Table 3.
- Fix TOC Section 2.3.1 printed-page entry from 29 to its regenerated page.
- Fix TOC Section 6.6.3.1 printed-page entry from 67 to its regenerated page.
- Reconcile Section 3.2.1's title between the TOC and body.
- Reconcile Figure 2's name between the list of figures and caption.
- Correct the Chapter III table-number offset and duplicate Table 9.
- Update all captions/cross-references after pagination settles; do not type guessed page numbers early.
- Search the final document for: `Quezon`, `React Native`, `AWS`, `PayMongo`, `Xendit`, `GCash`, `Maya`, `OCR`, `five seconds`, `5 km`, `zero emissions`, `e-bike`, `gasoline`, `open source architecture`, `stores authentication credentials`, and brand/capitalization variants.
- Review every edited page visually for widows/orphans, split table rows, shifted cells, caption collisions, distorted diagrams, and accidental blank pages.

## 12. Completed implementation sequence

1. Recheck `git status`, source hashes, current `HEAD`, and whether the Word source can be safely read.
2. Copy the proposal Word file into `output/docs/`; never edit the Downloads copy.
3. Distill and preserve the proposal's actual styles, sections, tables, page setup, and front matter before changing content.
4. Reconfirm the truth sheet against the then-current code and tests.
5. Apply minimal edits to Chapters I, II, III, and VI.
6. Add only the necessary same-format Chapter III function blocks and activity flows.
7. Update the Glossary and References, using verified official sources for current legal/regulatory claims.
8. Refresh fields, TOC, lists, captions, numbering, and cross-references.
9. Create the separate four-column recommendations/actions/proof Word file from the distilled table contract.
10. Capture or identify exact proof for every appendix row. Leave no unsupported completion claim.
11. Render both Word files to page images/PDF with the document workflow.
12. Inspect every page at readable resolution and iterate until layout is clean.
13. Run text-level QA for forbidden/stale terms, role consistency, geography, statuses, citations, and duplicated numbering.
14. Verify that source files are unchanged and that only intended repository artifacts were created.
15. Deliver both clickable Word files with a concise change summary and clearly disclose any recommendation that remains only partially implemented.

## 13. Acceptance checklist

- [x] User explicitly said “go.”
- [x] Original PDF and example appendix remain unchanged; the proposal source was copied, never edited in place.
- [x] Main deliverable is a separate DOCX.
- [x] Appendix response matrix is a separate table-only DOCX.
- [x] Only Chapters I, II, III, VI, Glossary, References, and dependent navigation/caption fields changed.
- [x] Chapter III retains the existing function-table and swimlane style.
- [x] Added Chapter III functions use the same seven-part format.
- [x] Every Quezon City reference in scope is Bacolod City.
- [x] Flutter/Dart correctly describes the mobile app; React/TypeScript describes only the admin portal.
- [x] System Admin and TODA Admin share a portal but remain separate, enforced roles.
- [x] Registration, approval, booking, dispatch, fare, cash-settlement, geofence, and backend descriptions agree with the audited code.
- [x] No unsupported feature or performance claim is presented as completed.
- [x] Geofence proof distinguishes visible restriction polygons from the still-missing persistent TODA coverage border.
- [x] Appendix contains exactly four columns and five recommendations.
- [x] No proponent/researcher name was guessed or copied from the example.
- [x] Manual TOC, lists, numbering, captions, and page references are synchronized to the final 82-page render.
- [x] All 82 proposal pages and the one-page matrix were rendered; contact sheets and changed pages were visually inspected.
- [x] Final files open in Microsoft Word without repair warnings and contain no intentional tracked changes/comments.
