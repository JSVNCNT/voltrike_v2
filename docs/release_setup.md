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
firebase deploy --only "functions,firestore:rules,database,storage"
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
prompts during deploy. `createBookingCallToken` issues a two-minute token
only to the assigned driver or passenger of an active booking. At two minutes,
the client calls `endBookingCall`, which deletes the LiveKit room and
disconnects both participants. Never place the LiveKit secret or a long-lived
token in Flutter source.
