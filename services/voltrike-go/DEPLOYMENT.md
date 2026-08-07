# VolTrike hosted private deployment

There is no Google Play release in this deployment model. Deploy only
the shared services that must be reachable by multiple phones:

- Go V2 API: Google Cloud Run.
- Auth, Firestore, RTDB, Storage, rules, indexes, and integration Functions:
  Firebase.
- React/TypeScript Admin: the existing Render Static Site.
- Voice infrastructure: LiveKit Cloud or an equivalent LiveKit server.

Passenger and driver phones use a privately distributed APK. Each phone talks
to the same Cloud Run and Firebase resources, so the system continues running
when the development PC, Flutter, VS Code, or ADB is off. `flutter run` is only
for development and is never part of the hosted runtime.

This is a production-like private environment, not a public app-store release.
It can incur cloud/provider usage even with scale-to-zero, so configure budgets
and never commit secret values or App Check debug tokens.

```text
flutter run on passenger phone ─┐
flutter run on driver phone ────┼─> Cloud Run Go API ─> Firebase
Render Admin ───────────────────┘             └───────> LiveKit
Firebase Functions <──────────── Go transactional outbox
```

The Firebase project must support second-generation Functions and Cloud Run-
backed resources. Authenticate the `gcloud` and Firebase CLIs before starting.

## 1. Select the project and deployment values

Run from the repository root. Replace each placeholder before execution.

```powershell
$projectId = "voltrike-v2"
$region = "asia-southeast1"
$service = "voltrike-api-v2"
$databaseUrl = "https://voltrike-v2-default-rtdb.asia-southeast1.firebasedatabase.app"
$storageBucket = "voltrike-v2.firebasestorage.app"
$renderOrigin = "https://voltrike-admin.onrender.com"
$liveKitServerUrl = "wss://voltrike-6c5lg2hv.livekit.cloud"
$runtimeServiceAccount = "voltrike-go-runtime@$projectId.iam.gserviceaccount.com"

gcloud auth login
gcloud config set project $projectId
firebase use $projectId
```

Enable the required Google APIs:

```powershell
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com firestore.googleapis.com firebasedatabase.googleapis.com firebaseappcheck.googleapis.com routes.googleapis.com
```

## 2. Configure the API runtime identity and secrets

The project reuses its existing `voltrike-go-runtime` service account. Grant
only the Firebase data permissions needed by the current V2 API. Review these
bindings in Google Cloud Console before applying them.

```powershell
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/datastore.user"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/firebasedatabase.admin"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/firebaseappcheck.tokenVerifier"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/firebaseauth.admin"
gcloud storage buckets add-iam-policy-binding "gs://$storageBucket" --member="serviceAccount:$runtimeServiceAccount" --role="roles/storage.objectAdmin"
gcloud iam service-accounts add-iam-policy-binding $runtimeServiceAccount --member="serviceAccount:$runtimeServiceAccount" --role="roles/iam.serviceAccountTokenCreator"
```

The API requires Google Routes and LiveKit credentials, a stable 32-byte quote
encryption key, a random internal scheduler key, and a one-time developer-admin
bootstrap code. Store all private values in Secret Manager; never add them to
Render, Flutter, or Git.

```powershell
gcloud secrets describe GOOGLE_ROUTES_API_KEY
gcloud secrets describe GO_QUOTE_ENCRYPTION_KEY
gcloud secrets describe GO_LOCAL_INTERNAL_KEY
gcloud secrets describe LIVEKIT_API_KEY
gcloud secrets describe LIVEKIT_API_SECRET
gcloud secrets describe ADMIN_BOOTSTRAP_CODE
```

If the quote key does not exist, create it once:

```powershell
$quoteKeyBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($quoteKeyBytes)
$quoteKey = [Convert]::ToBase64String($quoteKeyBytes)
$quoteKey | gcloud secrets create GO_QUOTE_ENCRYPTION_KEY --replication-policy=automatic --data-file=-
```

Create each remaining missing secret interactively so its value is not written
to shell history. Existing secrets should be updated with
`gcloud secrets versions add SECRET_NAME --data-file=-` instead.

```powershell
gcloud secrets create GOOGLE_ROUTES_API_KEY --replication-policy=automatic --data-file=-
gcloud secrets create GO_LOCAL_INTERNAL_KEY --replication-policy=automatic --data-file=-
gcloud secrets create LIVEKIT_API_KEY --replication-policy=automatic --data-file=-
gcloud secrets create LIVEKIT_API_SECRET --replication-policy=automatic --data-file=-
gcloud secrets create ADMIN_BOOTSTRAP_CODE --replication-policy=automatic --data-file=-
```

Grant the runtime identity secret access:

```powershell
gcloud secrets add-iam-policy-binding GOOGLE_ROUTES_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_QUOTE_ENCRYPTION_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_LOCAL_INTERNAL_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding LIVEKIT_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding LIVEKIT_API_SECRET --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding ADMIN_BOOTSTRAP_CODE --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
```

## 3. Deploy the Go API

The service is intentionally public at the network layer. Every `/api/v2/**`
request requires a Firebase ID token and a registered App Check token. Private
debug APKs use individually registered debug tokens; this does not require Play
Console or Google Play distribution.

```powershell
gcloud run deploy $service --source services/voltrike-go --region $region --project $projectId --service-account $runtimeServiceAccount --allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 40 --timeout 30s --set-env-vars "GOOGLE_CLOUD_PROJECT=$projectId,FIREBASE_DATABASE_URL=$databaseUrl,FIREBASE_STORAGE_BUCKET=$storageBucket,GO_ALLOWED_ORIGINS=$renderOrigin,GO_REQUIRE_APP_CHECK=true,POLICY_CACHE_TTL_SECONDS=60,REQUEST_TIMEOUT_SECONDS=10,MAX_DISPATCH_RESULTS=40,LIVEKIT_SERVER_URL=$liveKitServerUrl,SENTRY_DSN=$env:SENTRY_GO_DSN,SENTRY_ENVIRONMENT=production,SENTRY_TRACES_SAMPLE_RATE=0.05" --set-secrets "GOOGLE_ROUTES_API_KEY=GOOGLE_ROUTES_API_KEY:latest,GO_QUOTE_ENCRYPTION_KEY=GO_QUOTE_ENCRYPTION_KEY:latest,GO_LOCAL_INTERNAL_KEY=GO_LOCAL_INTERNAL_KEY:latest,LIVEKIT_API_KEY=LIVEKIT_API_KEY:latest,LIVEKIT_API_SECRET=LIVEKIT_API_SECRET:latest,DEVELOPER_BOOTSTRAP_CODE=ADMIN_BOOTSTRAP_CODE:latest"
$apiUrl = gcloud run services describe $service --region $region --project $projectId --format="value(status.url)"
$apiUrl
```

Verify only the unauthenticated health endpoints from a terminal:

```powershell
curl.exe "$apiUrl/health"
curl.exe "$apiUrl/ready"
```

## 4. App Check for private APKs

Register every private test device before enabling the hosted environment.

1. Open **Build/Security → App Check** and register the Android Firebase app.
   A normal `flutter run` automatically uses the Android debug provider, so
   Play Integrity and Play Console are not required for this capstone.
2. Run the app once on every emulator or physical phone. Copy the App Check
   debug secret printed by `DebugAppCheckProvider` in the Flutter/Android log.
3. For the Android app in App Check, open **Manage debug tokens** and register
   each token with a label such as `passenger-phone` or `driver-phone`.
4. Register the Admin web app with reCAPTCHA v3, allow the Render hostname, and
   save its public site key for the Render configuration below.
5. Under **Authentication → Settings → Authorized domains**, add the Render
   Admin hostname.
6. Enable App Check enforcement after every active test device is registered.
   The Go API already rejects missing or invalid App Check tokens.

If the capstone later runs from an Apple device or simulator, register the
Apple Firebase app and its debug token in the same App Check screen. Building
that client still requires macOS/Xcode; it does not require App Store release.

If the Android debug token is not visible in `flutter run`, inspect logcat:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" logcat -d | Select-String -Pattern "DebugAppCheckProvider|debug secret"
```

Debug tokens grant unverified-device access. Never commit or share them, and
revoke a token in Firebase Console if it is exposed.

## 5. Configure the existing Render Admin

The public Cloud Run URL is pinned in `render.yaml`. In Render, open the
existing `voltrike-admin` Static Site and set the remaining build environment
variables:

```text
VITE_FIREBASE_APP_CHECK_SITE_KEY=<public reCAPTCHA v3 site key>
VITE_MAPBOX_ACCESS_TOKEN=<public URL-restricted Mapbox token>
VITE_FIREBASE_VAPID_KEY=<public Firebase web-push key>
```

Push the checkpoint, then choose **Save, rebuild, and deploy** in Render:

```powershell
git push origin main
```

Render uses `render.yaml`: build command `npm ci && npm run build`, publish
directory `admin/dist`, and SPA rewrite `/* -> /index.html`.

## 6. Deploy Firebase integration infrastructure

Deploy rules, indexes, and the integration-only Functions manifest. Configure
the scheduled integration hook with the same internal key used by Cloud Run;
the key is never shipped to Flutter or Admin.

```powershell
firebase functions:secrets:set GO_LOCAL_INTERNAL_KEY --project $projectId
firebase functions:secrets:set BREVO_SMTP_LOGIN --project $projectId
firebase functions:secrets:set BREVO_SMTP_KEY --project $projectId
firebase functions:secrets:set BREVO_SENDER_EMAIL --project $projectId
firebase deploy --only "firestore,database,storage" --project $projectId
firebase deploy --only "functions:processGoOutbox,functions:requestBrandedPasswordResetEmail,functions:requestBrandedVerificationEmail,functions:registerAdminWebPushToken,functions:unregisterAdminWebPushToken,functions:runGoMaintenance" --project $projectId
```

The selective Functions deployment intentionally leaves older callable
endpoints in place until their invocation logs have been observed for a full
client migration window. Delete them only after confirming that no installed
private APK or external integration still calls them.

When Firebase prompts for the `VOLTRIKE_API_BASE_URL` parameter, enter the
printed `$apiUrl`. Firebase Hosting is not deployed; Render remains the only
Admin frontend host.

## 7. Distribute the final capstone mobile clients

Build the one private APK that can be Quick Shared to each Android phone:

```powershell
flutter build apk --debug --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app --dart-define=SENTRY_DSN=https://39ba2251daffea156fb5d535af5e801c@o4511869752836096.ingest.us.sentry.io/4511869828202496 --dart-define=SENTRY_ENVIRONMENT=production --dart-define=SENTRY_RELEASE=voltrike_v2@1.0.0+1
```

Register that phone's App Check debug token, then Quick Share
`build/app/outputs/flutter-apk/app-debug.apk` to each tester. Each
phone can register or sign in and use Cloud Run and Firebase without Flutter,
ADB, or a connection to the development PC. Stopping a local Flutter session
stops only that local client; Cloud Run, Firebase, Functions, and Render stay
online.

Use `flutter run` only for later development or debugging. It is not required
to operate the shared private deployment. A future public release can replace
debug App Check tokens with Play Integrity and add store signing at that time.

## 8. Retention, backups, and hosted automation

Enable Firestore TTL for short-lived operational records. TTL deletion is
asynchronous; the hosted maintenance worker also removes expired command
receipts and Realtime Database dispatch/tracking projections every minute.

```powershell
gcloud firestore fields ttls update expiresAt --collection-group=command_receipts --enable-ttl --project=$projectId
gcloud firestore fields ttls update expiresAt --collection-group=communicationDeliveries --enable-ttl --project=$projectId
gcloud firestore fields ttls update expiresAt --collection-group=outbox --enable-ttl --project=$projectId
```

Create a scheduled Firestore export to a retention-locked Cloud Storage bucket
before real passenger data is collected. Budget alerts should cover Cloud Run,
Firebase/Firestore, Functions/Scheduler, Routes, Storage, Render, and LiveKit.

The manual `deploy hosted services` GitHub workflow uses Workload Identity
Federation (no JSON service-account key) and has separate `staging` and
`production` environments. Configure each environment's variables listed in
the workflow, require approval for `production`, and use it to deploy Cloud Run
plus Firebase without relying on this PC. Render continues deploying the Admin
site from the repository.

## 9. What must be redeployed after a change

- Flutter/Dart-only change: hot reload/restart, or run `flutter run` again.
- Go change: repeat the Cloud Run deploy command in section 3.
- Rules, indexes, or Node integration change: repeat section 6.
- Admin change: push Git; Render auto-deploys, or use **Manual Deploy**.
- Rust device-kernel change: rebuild through `flutter run`; it is part of the
  local Flutter application, not a separately hosted server.

## Rollback

- Render: redeploy the previous successful Admin release and restore its V2 API
  build variable.
- Cloud Run: route traffic back to the prior verified revision with
  `gcloud run services update-traffic`.
- Firebase: redeploy the baseline Functions/rules only if the matching Flutter
  and Admin releases are restored together.
- Never rotate `GO_QUOTE_ENCRYPTION_KEY` as an outage workaround; it invalidates
  still-live signed quotes.
