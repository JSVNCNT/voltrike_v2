# BOOKING FLOW TODO

## STATUS
- GO received.
- Code implementation completed for M01-M08.
- Runtime, build, deployment, and device verification intentionally deferred.

## REQUIRED DURABLE ORDER
`pending -> driverAssigned -> driverArriving -> passengerOnBoard -> paymentConfirmation -> completed`

Terminal alternatives:
- `cancelled_by_passenger`
- `cancelled_by_driver`
- `passenger_no_show`

## MILESTONES

### M09 [ ] Booking-flow regression and deployment
- RUN: Flutter analyze and complete test suite.
- RUN: Functions tests and admin TypeScript build.
- DEPLOY: Functions, Firestore rules/indexes, RTDB, Storage.
- CHECK: System diagnostics on passenger and driver devices.
- RUN: Jung's Townhouse -> Estefania full two-role ride.
- COVER: Accept, arrive, start, payment, complete, skip/rate, receipt.
- COVER: Cancel, no-show, decline, restart, admin live updates.
- DONE: No critical flow failures; evidence recorded in `done.md`.

## KNOWN VERIFICATION RISKS
- New callable functions require deployment before mobile use.
- New status requires deployed Functions before end-to-end testing.
- Searching route needs valid Google Routes configuration.
- Five-second admin polling needs browser smoke verification.

## OUT OF SCOPE
- Renaming stored `driverArriving` documents.
- Passenger-controlled cash confirmation.
- Embedded Google Navigation SDK.
- Polygon editor redesign or validation.
