# VolTrike Android release setup

Add this to `android/local.properties` on each developer or CI machine:

```text
MAPS_API_KEY=your_restricted_google_maps_android_key
```

Restrict the key to the VolTrike Android package and signing certificate. Do not commit this file.

Before release, deploy Firebase Functions after setting LiveKit server credentials as Function secrets, configure Firestore/RTDB rules, and run `flutter test` plus a physical-device booking smoke test.

## Firebase deployment

```cmd
cd functions
npm install
cd ..
firebase deploy --only "functions,firestore:rules,firestore:indexes,database,storage"
```

The Functions runtime is Node 22. Re-deploy after any `functions/index.js` change.

## LiveKit voice calls

Run a self-hosted LiveKit server plus Coturn, then configure:

```cmd
firebase functions:secrets:set LIVEKIT_API_KEY
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY
firebase functions:secrets:set LIVEKIT_API_SECRET
```

Set the `LIVEKIT_URL` function parameter to your WebSocket URL when the CLI
prompts during deploy. The call lifecycle is coordinated by
`startBookingCall`, `respondBookingCall`, `createBookingCallToken`, and
`endBookingCall`. A recipient has 30 seconds to accept, and only an accepted
call receives a LiveKit token. The server limits the accepted call to two
minutes and `expireBookingCalls` closes stale invitations and rooms even if a
client disconnects without cleanup. Firestore remains the shared source of
truth for passenger and driver state. Never place the LiveKit secret or a
long-lived token in Flutter source.
