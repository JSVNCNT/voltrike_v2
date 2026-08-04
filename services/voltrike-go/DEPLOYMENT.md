# VolTrike Go/Firebase deployment

This deploys the Go read/compute plane as a private Cloud Run service. Flutter
and the Render-hosted Admin site continue to call Firebase Functions; neither
client receives Cloud Run credentials or calls the Go URL directly.

Run these commands from the repository root in PowerShell. They intentionally
do not deploy Firebase Hosting.

## 1. Select the production project

```powershell
$projectId = "voltrike-v2"
$region = "asia-southeast1"
$service = "voltrike-go"
$databaseUrl = "https://voltrike-v2-default-rtdb.asia-southeast1.firebasedatabase.app"
$runtimeServiceAccount = "voltrike-go-runtime@$projectId.iam.gserviceaccount.com"

gcloud auth login
gcloud config set project $projectId
firebase use $projectId
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com firestore.googleapis.com firebasedatabase.googleapis.com routes.googleapis.com
```

## 2. Create the read-only Go runtime identity

Create this service account once:

```powershell
gcloud iam service-accounts create voltrike-go-runtime --display-name="VolTrike Go runtime"
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeServiceAccount" --role="roles/viewer"
```

The project Viewer role is used because Firebase Realtime Database server
access currently documents its read-only service-account level as the project
Reader/Viewer role. The Go process itself exposes no write operation. Firestore
reads are also read-only under this role.

## 3. Prepare secrets

The existing `GOOGLE_ROUTES_API_KEY` Firebase secret can be reused. Confirm it
exists:

```powershell
gcloud secrets describe GOOGLE_ROUTES_API_KEY
```

If it does not exist, create it with the same Google Routes API key already
used by Functions:

```powershell
firebase functions:secrets:set GOOGLE_ROUTES_API_KEY
```

Create the quote encryption key once. If `describe` shows that it already
exists, do not recreate or rotate it during an active rollout because existing
short-lived quote tokens would stop decrypting.

```powershell
gcloud secrets describe GO_QUOTE_ENCRYPTION_KEY
$quoteKeyBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($quoteKeyBytes)
$quoteKey = [Convert]::ToBase64String($quoteKeyBytes)
$quoteKey | gcloud secrets create GO_QUOTE_ENCRYPTION_KEY --replication-policy=automatic --data-file=-
```

Permit only the Go runtime identity to read the two secret payloads:

```powershell
gcloud secrets add-iam-policy-binding GOOGLE_ROUTES_API_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
gcloud secrets add-iam-policy-binding GO_QUOTE_ENCRYPTION_KEY --member="serviceAccount:$runtimeServiceAccount" --role="roles/secretmanager.secretAccessor"
```

## 4. Deploy the private Go service

```powershell
gcloud run deploy $service --source services/voltrike-go --region $region --project $projectId --service-account $runtimeServiceAccount --no-allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 40 --timeout 15s --set-env-vars "GOOGLE_CLOUD_PROJECT=$projectId,FIREBASE_DATABASE_URL=$databaseUrl,POLICY_CACHE_TTL_SECONDS=60,REQUEST_TIMEOUT_SECONDS=10,MAX_DISPATCH_RESULTS=40" --set-secrets "GOOGLE_ROUTES_API_KEY=GOOGLE_ROUTES_API_KEY:latest,GO_QUOTE_ENCRYPTION_KEY=GO_QUOTE_ENCRYPTION_KEY:latest"
$goServiceUrl = gcloud run services describe $service --region $region --project $projectId --format="value(status.url)"
$goServiceUrl
```

The service remains IAM-private. Do not add `allUsers` as an invoker.

## 5. Allow Firebase Functions to invoke Go

Read the runtime identity of the already-deployed second-generation booking
function, then grant that identity only the Cloud Run Invoker role:

```powershell
$functionsServiceAccount = gcloud functions describe createBookingLifecycle --gen2 --region $region --project $projectId --format="value(serviceConfig.serviceAccountEmail)"
$functionsServiceAccount
gcloud run services add-iam-policy-binding $service --region $region --project $projectId --member="serviceAccount:$functionsServiceAccount" --role="roles/run.invoker"
```

If the first command returns nothing, inspect the function in Google Cloud
Console before continuing; do not guess a service-account identity.

## 6. Configure Functions with Go initially off

Open `functions/.env.voltrike-v2` and add or update these lines without deleting
any existing environment values:

```dotenv
GO_SERVICE_URL=https://THE-URL-PRINTED-IN-STEP-4
GO_QUOTE_MODE=off
GO_DISPATCH_MODE=off
```

Deploy rules, indexes, and Functions. This also deploys the TODA commission
report correction and the dispatch-cell maintenance trigger. It does not deploy
the Render frontend or Firebase Hosting.

```powershell
firebase deploy --only "firestore:indexes,database,functions" --project $projectId
```

With an online driver sending locations, allow the trigger to warm the compact
index, then inspect it:

```powershell
firebase database:get /dispatchCells --project $projectId
```

## 7. Verify and enable in two controlled steps

Test the private health endpoint through an authenticated local proxy:

```powershell
gcloud run services proxy $service --region $region --project $projectId --port 8085
```

In a second terminal:

```powershell
curl.exe http://127.0.0.1:8085/healthz
```

First change only `GO_QUOTE_MODE=on` in `functions/.env.voltrike-v2`, redeploy
Functions, and manually test passenger quote/booking creation:

```powershell
firebase deploy --only functions --project $projectId
```

After quote and booking tests pass, change `GO_DISPATCH_MODE=on`, redeploy
Functions again, and manually test passenger/driver dispatch. Off/on are the
only planned production modes; temporary legacy fallback is retained for a Go
outage, while invalid supplied quote tokens fail closed.

## 8. Admin and Flutter deployment behavior

- Admin remains on Render and keeps calling Firebase callable Functions. No TSX
  Cloud Run URL or Go credential is added.
- The commission report correction becomes active with the Functions/index
  deployment above; no Render rebuild is required for that correction.
- Flutter uses `GoServiceBridge` through `createBookingQuote`; there is no
  `go_bridge` pub dependency.
- After backend deployment, run the app manually with `flutter run -d DEVICE_ID`.
- Do not deploy Firebase Hosting while Render is the chosen Admin host.

