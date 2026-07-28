# Administrator safety notifications

VolTrike's capstone safety workflow uses:

- the Firebase Safety Incidents dashboard with five-second visible-page refresh;
- browser notifications after the administrator grants permission;
- Firebase device notifications when a registered device token is available;
- required Brevo transactional email to the verified administrator account;
- incident location, acknowledgement, responding, resolution, and audit records;
- the explicit device dialer option for calling the Philippine Unified 911
  hotline.

VolTrike does not send SMS and does not claim to dispatch emergency services.

## Firebase prerequisites

1. Open the `voltrike-v2` Firebase project and confirm that it is on the Blaze
   plan. Cloud Functions cannot be deployed on Spark.
2. Create a small Google Cloud billing budget with alerts. Budget alerts do not
   stop usage automatically.
3. From the repository root, sign in and select the project:

   ```powershell
   firebase login
   firebase use voltrike-v2
   ```

## Brevo free email setup

1. Create a free Brevo account.
2. Add and verify a sender email. For a production-like defense, authenticate a
   domain or subdomain and publish the DNS records Brevo supplies.
3. In **SMTP & API**, create an API key. Use an API key, not an SMTP key.
4. Store it in Firebase Secret Manager:

   ```powershell
   firebase functions:secrets:set BREVO_API_KEY
   ```

Never place the API key in source code, Flutter, the admin frontend, Git, or an
environment file.

## Non-secret parameters

This repository already has `functions/.env.voltrike-v2` for `LIVEKIT_URL`.
Do not overwrite or remove the existing LiveKit value.

Open the file:

```powershell
notepad '.\functions\.env.voltrike-v2'
```

Add:

```dotenv
BREVO_SENDER_EMAIL=verified-sender@your-domain.example
BREVO_SENDER_NAME=VolTrike
ADMIN_PORTAL_URL=https://voltrike-v2.web.app
```

If the file is absent in another checkout, copy
`functions/communications-parameters.example` first.

## Verify and deploy

```powershell
npm.cmd --prefix functions install
npm.cmd --prefix functions test
npm.cmd --prefix admin install
npm.cmd --prefix admin run build
firebase deploy --only functions
```

Deploy the admin build through the project's existing host. If Firebase Hosting
is used, initialize it with `admin/dist` as the public SPA directory before
running:

```powershell
firebase deploy --only hosting
```

When Firebase asks to remove the retired
`adminGetSafetyContact` and `adminUpdateSafetyContact` functions, approve the
removal after the new admin build is ready to deploy.

## Capstone operating procedure

1. Every developer or TODA administrator must use a valid Firebase email and
   complete email verification.
2. Keep the Safety Incidents dashboard open on the monitored administrator
   computer during the demonstration.
3. Select **Enable browser SOS alerts** and grant notification permission.
4. Use a controlled test booking. Do not select the real 911 call option.
5. Confirm the incident appears on the map and that the administrator receives
   the transactional email.
6. Acknowledge, start a response, and resolve the incident with an audit note.
7. Explain during the defense that dashboard, browser, device, and email
   notifications are capstone safety-alert layers; calling 911 remains an
   explicit human action.

Existing Firestore phone and SMS preference fields are retained for backward
compatibility but are no longer required, read, displayed, or used.
