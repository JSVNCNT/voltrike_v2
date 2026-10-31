# Passenger cancellations and administrator privacy

## Registration

The driver entry route displays a preparation checklist before step 1. Its
seven image requirements and icons match document upload. Identity and vehicle
documents require camera capture; portraits and vehicle photos also accept
gallery images. Passenger entry links show a shorter preparation note.

## Cancellation policy

- Count passenger-initiated `change_of_plans` and `booked_by_mistake` only after
  driver acceptance. The first produces a reminder, the second a warning, and
  the third within a rolling 24 hours blocks **new bookings** for 24 hours.
- Pending searches, timeouts, driver cancellations and driver no-show claims
  do not contribute to passenger strikes. Safety, unknown and driver-fault
  claims after acceptance are recorded for review without an automatic strike.
- A driver-reported passenger no-show needs System Admin review. Counting it
  requires an arrival sample within 150 metres of pickup, accuracy at most
  100 metres, observed and received within one minute of arrival, and at least
  five minutes between the server-recorded arrival and cancellation.
- Go records the cancellation event, policy and booking transition in the same
  Firestore transaction. Booking creation reads that policy transactionally.
  Revision checks and command receipts prevent a repeated request from adding
  another strike. Clients cannot write policy or event documents.
- Passengers can appeal each counted cancellation once. Disputed strikes stop
  counting during review. Upholding an appeal resumes its original automatic
  cooldown, rather than extending it or recording another restriction. Other
  disputed or waived strikes must not be counted toward that resumed cooldown.
- System Admin can waive a strike, restore booking access, or impose a reviewed
  restriction of 1–720 hours with a reason. A manual restriction can be appealed
  but stays active during review. TODA Admin cannot administer passenger policy.
- This is separate from account suspension. History, reports and existing
  safety tools remain available. Permanent account suspension remains a manual
  moderation action through the existing account/report workflow.

Policy documents are in `passengerBookingPolicies/{uid}`. Events are in
`passengerCancellationEvents/{bookingId}`; historical bookings are not backfilled
or retroactively penalized. A one-second client timer updates expiry and rolling
window presentation, emitting UI updates only when displayed policy changes.

## Administrator privacy

Both administrator roles receive consistent passenger references instead of
names. Ordinary booking, rating, report, safety, chat and cancellation responses
remove passenger contact details/photos, reduce addresses to barangay labels,
remove passenger route coordinates, and hide unstructured text. Searches operate
on these masked snapshots. Driver registration/review identity remains available
within the existing role and TODA boundaries.

Private case detail access requires a 10–500 character investigation reason and
matching booking/TODA/case scope. A successful audit-log write is required before
details are returned. Retained chat-photo access has the same reason/log rule.
Private detail dialogs keep results only in component memory and discard them
on close. The API already sends `Cache-Control: no-store`.

Direct Firestore reads of passenger profiles, reports, safety incidents,
settlements and driver offers are restricted to their owners/participants;
administrators use scoped Go endpoints. Mobile participants retain the identity
and precise route information needed for their own rides.

## Rollout

Deploy the Go service, Firestore rules, admin bundle and mobile build together.
The UI changes do not activate policy on an older deployed backend. No new
composite indexes are required: cancellation review pages order by `updatedAt`.
Commit/push alone does not deploy these changes.
