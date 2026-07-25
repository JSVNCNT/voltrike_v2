# VolTrike mobile QA checklist

Run this against two Android devices (one passenger and one driver) after
deploying the current Firebase Functions and rules.

## Setup

1. Sign in with one approved driver account and one passenger account.
2. Give the driver location permission and set the driver online.
3. Give both devices notification and microphone permissions.

## Booking and tracking

1. Passenger creates a booking and sees the searching state.
2. Only the offered driver sees the booking offer and accepts it.
3. Confirm a second driver cannot accept the same booking.
4. Passenger receives the driver-assigned update and sees the teal VolTrike
   driver marker move from RTDB location updates.
5. Driver advances: arrived, start trip, drop off.
6. Confirm passenger cancellation is available only before boarding and driver
   cancellation is available only before boarding.
7. Kill and reopen each app during an active booking; verify the appropriate
   tracking screen restores.

## Chat, reports, and ratings

1. During an on-board trip, exchange messages and verify read state/typing
   state update for the other user.
2. Submit a report from each role; verify it is stored with the booking ID and
   reporter identity.
3. Complete the ride. Confirm only the passenger can submit one driver rating.
4. Confirm trip history expands to show receipt, rating, and report actions.

## Notifications and voice

1. Put either app in the background and trigger booking lifecycle changes;
   verify FCM notification tap opens the correct tracking screen.
2. Tap a new driver-offer notification and verify it opens Driver Home, not
   the active-trip tracking screen.
3. Keep the app foreground and verify the local ride-update notification is
   displayed and deep-links correctly.
4. During an on-board trip, start a voice call. Verify microphone permission,
   mute, and manual end work.
5. Keep a call active for two minutes. Verify the timer ends the call and both
   participants are disconnected.

## Data/security checks

1. Confirm driver coordinates are written only under that driver's RTDB node.
2. Confirm passenger/driver profile images upload under their role/UID path.
3. Confirm unapproved or offline drivers do not receive an active offer.
