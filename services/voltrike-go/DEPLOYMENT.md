# VolTrike V2 deployment

This runbook deploys the public Go V2 API, Firebase integration workers, and
the existing Render-hosted Admin. The API is network-invokable because Flutter
and Admin present Firebase ID and App Check tokens directly; authorization is
enforced by Go, not Cloud Run IAM.

Do not run the production commands until the V2 cutover features required for
your release are implemented and reviewed in `../../transition.md`.

## 1. Select the project and deployment values

Run from the repository root. Replace each placeholder before execution.

```powershell
$projectId = "voltrike-v2"
$region = "asia-southeast1"
$service = "voltrike-api-v2"
$databaseUrl = "https://voltrike-v2-default-rtdb.asia-southeast1.firebasedatabase.app"
$renderOrigin = "https://YOUR-ADMIN.onrender.com"
$runtimeServiceAccount = "voltrike-api-v2@$projectId.iam.gserviceaccount.com"

gcloud auth login
gcloud config set project $projectId
firebase use $projectId
```

Enable the required Google APIs:

```powershell
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com firestore.googleapis.com firebasedatabase.googleapis.com firebaseappcheck.googleapis.com routes.googleapis.com
```

## 2. Create the API runtime identity and secrets

Create the service account once, then grant only the Firebase data permissions
needed by the current V2 API. Review these bindings in Google Cloud Console for
your organization before applying them.

```powershell
gcloud iam service-accounts create voltrike-api-v2 --display-name="VolTrike V2 API"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/datastore.user"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/firebasedatabase.admin"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/firebaseappcheck.tokenVerifier"
```

The API requires a Google Routes key and a stable 32-byte quote encryption key.
Store both in Secret Manager; never add either to Render, Flutter, or Git.

```powershell
gcloud secrets describe GOOGLE_ROUTES_API_KEY
gcloud secrets describe GO_QUOTE_ENCRYPTION_KEY
```

If the quote key does not exist, create it once:

```powershell
$quoteKeyBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($quoteKeyBytes)
$quoteKey = [Convert]::ToBase64String($quoteKeyBytes)
$quoteKey | gcloud secrets create GO_QUOTE_ENCRYPTION_KEY --replication-policy=automatic --data-file=-
```

Grant the runtime identity secret access:

```powershell
gcloud secrets add-iam-policy-binding GOOGLE_ROUTES_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_QUOTE_ENCRYPTION_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
```

## 3. Deploy the Go API

The service is intentionally public at the network layer. Every `/api/v2/**`
request requires a Firebase ID token and, in production, an App Check token.

```powershell
gcloud run deploy $service --source services/voltrike-go --region $region --project $projectId --service-account $runtimeServiceAccount --allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 40 --timeout 15s --set-env-vars "GOOGLE_CLOUD_PROJECT=$projectId,FIREBASE_DATABASE_URL=$databaseUrl,GO_ALLOWED_ORIGINS=$renderOrigin,GO_REQUIRE_APP_CHECK=true,POLICY_CACHE_TTL_SECONDS=60,REQUEST_TIMEOUT_SECONDS=10,MAX_DISPATCH_RESULTS=40" --set-secrets "GOOGLE_ROUTES_API_KEY=GOOGLE_ROUTES_API_KEY:latest,GO_QUOTE_ENCRYPTION_KEY=GO_QUOTE_ENCRYPTION_KEY:latest"
$apiUrl = gcloud run services describe $service --region $region --project $projectId --format="value(status.url)"
$apiUrl
```

Verify only the unauthenticated health endpoints from a terminal:

```powershell
curl.exe "$apiUrl/healthz"
curl.exe "$apiUrl/readyz"
```

## 4. Configure Firebase App Check and Render

In Firebase Console:

1. **Security → App Check:** register Android with Play Integrity, Apple with
   App Attest/DeviceCheck fallback, and the Render Admin web app with your
   reCAPTCHA v3 site key.
2. **Authentication → Settings → Authorized domains:** add the Render Admin
   hostname.
3. Do not enable Firebase-product enforcement until the new builds have sent
   valid tokens and the validation pass is complete.

In Render, open the existing `voltrike-admin` Static Site and set these build
environment variables:

```text
VITE_VOLTRIKE_API_BASE_URL=<the apiUrl printed above>
VITE_FIREBASE_APP_CHECK_SITE_KEY=<public reCAPTCHA v3 site key>
VITE_MAPBOX_ACCESS_TOKEN=<public URL-restricted Mapbox token>
VITE_FIREBASE_VAPID_KEY=<public Firebase web-push key>
```

Render uses `render.yaml`: build command `npm ci && npm run build`, publish
directory `admin/dist`, and SPA rewrite `/* -> /index.html`.

## 5. Deploy Firebase integration infrastructure

Deploy rules, indexes, and Functions. The Functions deployment includes the
Go outbox notification worker. Set `GO_V2_AUTHORITY=on` in the Functions
environment only when the V2 notification path is ready to replace the legacy
lifecycle notifier.

```powershell
firebase deploy --only "firestore:rules,firestore:indexes,database,storage,functions" --project $projectId
```

## 6. Build clients

Admin builds in Render. For Flutter production builds, pass the public API
origin and the web App Check key only for web targets:

```powershell
flutter build appbundle --dart-define=VOLTRIKE_API_BASE_URL=$apiUrl
flutter build web --dart-define=VOLTRIKE_API_BASE_URL=$apiUrl --dart-define=FIREBASE_APP_CHECK_WEB_SITE_KEY=YOUR_PUBLIC_RECAPTCHA_SITE_KEY
```

Do not use emulator defines in a release build.

## Rollback

- Render: redeploy the previous successful Admin release and restore its V2 API
  build variable.
- Cloud Run: route traffic back to the prior verified revision with
  `gcloud run services update-traffic`.
- Firebase: redeploy the baseline Functions/rules only if the matching Flutter
  and Admin releases are restored together.
- Never rotate `GO_QUOTE_ENCRYPTION_KEY` as an outage workaround; it invalidates
  still-live signed quotes.
