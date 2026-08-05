# VolTrike capstone deployment (`flutter run` mobile clients)

There is no Play Store or mobile release in this deployment model. Deploy only
the shared services that must be reachable by multiple phones:

- Go V2 API: Google Cloud Run.
- Auth, Firestore, RTDB, Storage, rules, indexes, and integration Functions:
  Firebase.
- React/TypeScript Admin: the existing Render Static Site.
- Voice infrastructure: LiveKit Cloud or an equivalent LiveKit server.

The passenger and driver apps remain normal debug sessions started with
`flutter run`. Each phone talks to the same Cloud Run and Firebase resources,
so multi-phone testing works without publishing an APK, AAB, or store release.

This is a shared capstone environment, not a public production release. It can
still incur cloud/provider usage, so configure budgets and never commit secret
values or App Check debug tokens.

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
gcloud secrets describe DEVELOPER_BOOTSTRAP_CODE
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
gcloud secrets create DEVELOPER_BOOTSTRAP_CODE --replication-policy=automatic --data-file=-
```

Grant the runtime identity secret access:

```powershell
gcloud secrets add-iam-policy-binding GOOGLE_ROUTES_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_QUOTE_ENCRYPTION_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_LOCAL_INTERNAL_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding LIVEKIT_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding LIVEKIT_API_SECRET --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding DEVELOPER_BOOTSTRAP_CODE --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
```

## 3. Deploy the Go API

The service is intentionally public at the network layer. Every `/api/v2/**`
request requires a Firebase ID token and, in production, an App Check token.

```powershell
gcloud run deploy $service --source services/voltrike-go --region $region --project $projectId --service-account $runtimeServiceAccount --allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 40 --timeout 30s --set-env-vars "GOOGLE_CLOUD_PROJECT=$projectId,FIREBASE_DATABASE_URL=$databaseUrl,FIREBASE_STORAGE_BUCKET=$storageBucket,GO_ALLOWED_ORIGINS=$renderOrigin,GO_REQUIRE_APP_CHECK=true,POLICY_CACHE_TTL_SECONDS=60,REQUEST_TIMEOUT_SECONDS=10,MAX_DISPATCH_RESULTS=40,LIVEKIT_SERVER_URL=$liveKitServerUrl" --set-secrets "GOOGLE_ROUTES_API_KEY=GOOGLE_ROUTES_API_KEY:latest,GO_QUOTE_ENCRYPTION_KEY=GO_QUOTE_ENCRYPTION_KEY:latest,GO_LOCAL_INTERNAL_KEY=GO_LOCAL_INTERNAL_KEY:latest,LIVEKIT_API_KEY=LIVEKIT_API_KEY:latest,LIVEKIT_API_SECRET=LIVEKIT_API_SECRET:latest,DEVELOPER_BOOTSTRAP_CODE=DEVELOPER_BOOTSTRAP_CODE:latest"
$apiUrl = gcloud run services describe $service --region $region --project $projectId --format="value(status.url)"
$apiUrl
```

Verify only the unauthenticated health endpoints from a terminal:

```powershell
curl.exe "$apiUrl/health"
curl.exe "$apiUrl/ready"
```

## 4. Configure App Check for `flutter run`

In Firebase Console:

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
6. Firebase-product enforcement can remain disabled during initial setup. Go
   still validates App Check on protected V2 requests, and the retained
   callable integration Functions enforce it as well.

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

In Render, open the existing `voltrike-admin` Static Site and set these build
environment variables:

```text
VITE_VOLTRIKE_API_BASE_URL=<the apiUrl printed above>
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
firebase deploy --only "firestore,database,storage,functions" --project $projectId
```

When Firebase prompts for the `VOLTRIKE_API_BASE_URL` parameter, enter the
printed `$apiUrl`. Firebase Hosting is not deployed; Render remains the only
Admin frontend host.

## 7. Run the final capstone mobile clients

There is no mobile deployment command. In each new PowerShell terminal, load
the Cloud Run URL and start the chosen device with a normal debug run:

```powershell
$projectId = "voltrike-v2"
$region = "asia-southeast1"
$service = "voltrike-api-v2"
$apiUrl = gcloud run services describe $service --region $region --project $projectId --format="value(status.url)"

flutter devices
flutter run -d DEVICE_ID --dart-define=VOLTRIKE_API_BASE_URL=$apiUrl
```

For passenger and driver phones simultaneously, open two terminals and run the
last command once per device ID. Register the App Check debug token from each
device before testing registration or booking. Stopping `flutter run` stops
only that phone client; Cloud Run, Firebase, Functions, and Render stay online.

Do not add `--release`. This capstone deliberately uses the debug App Check
provider for its `flutter run` lifecycle.

## 8. What must be redeployed after a change

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
