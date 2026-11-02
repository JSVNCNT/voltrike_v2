# VolTrike hosted private deployment

Passenger/driver Flutter APKs and the existing Render Static Site share Firebase
Auth, Firestore, RTDB, Storage and FCM. Two services built from
`services/voltrike-go` run on Cloud Run:

```text
Flutter / Render Admin -> public Go API -> Firebase / LiveKit / Brevo
                                      -> transactional outbox
Firestore Eventarc -> private Go worker -> FCM / Brevo
Cloud Scheduler -- OIDC every minute --> private Go worker
```

The public API requires Firebase ID tokens on protected routes. Cloud Run IAM
protects worker routes. App Check is disabled for the private Quick Share
APK (`GO_REQUIRE_APP_CHECK=false`); no per-phone debug-token registration is
introduced. Firebase rules and all server authorization continue to apply.
Neither local Flutter nor a development PC is needed to operate these services.

## Existing project, identities and secrets

Run commands from the repository root with the existing authenticated `gcloud`
and Firebase CLI sessions. Use the selected staging/production project values.

```powershell
$projectId = 'voltrike-v2'
$region = 'asia-southeast1'
$apiService = 'voltrike-api-v2'
$workerService = 'voltrike-integrations'
$databaseUrl = 'https://voltrike-v2-default-rtdb.asia-southeast1.firebasedatabase.app'
$storageBucket = 'voltrike-v2.firebasestorage.app'
$adminOrigin = 'https://voltrike-admin.onrender.com'
$emailAdminPortalUrl = 'https://voltrike-v2.web.app'
$emailLogoUrl = 'https://voltrike-v2.web.app/images/appLogo.png'
$liveKitUrl = 'wss://voltrike-6c5lg2hv.livekit.cloud'
$runtimeAccount = "voltrike-go-runtime@$projectId.iam.gserviceaccount.com"
$eventarcAccount = "voltrike-eventarc-invoker@$projectId.iam.gserviceaccount.com"
$schedulerAccount = "voltrike-scheduler-invoker@$projectId.iam.gserviceaccount.com"
$eventLocation = gcloud firestore databases describe --database='(default)' --project $projectId --format='value(locationId)'

gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com firestore.googleapis.com firebasedatabase.googleapis.com firebaseappcheck.googleapis.com routes.googleapis.com fcm.googleapis.com eventarc.googleapis.com pubsub.googleapis.com cloudscheduler.googleapis.com --project $projectId
```

Reuse all existing secrets. The working Brevo credentials already exist in
Secret Manager as `BREVO_SMTP_LOGIN`, `BREVO_SMTP_KEY` and `BREVO_SENDER_EMAIL`.
The confirmed enabled versions at migration preparation were 4, 3 and 2,
respectively. Resolving metadata below selects the latest enabled version; an
operator may instead pin those known numeric versions. No secret payload is
read or printed and no `functions:secrets:set` or credential re-entry is needed.

```powershell
$secretNames = @('GOOGLE_ROUTES_API_KEY', 'GO_QUOTE_ENCRYPTION_KEY', 'GO_LOCAL_INTERNAL_KEY', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET', 'ADMIN_BOOTSTRAP_CODE', 'BREVO_SMTP_LOGIN', 'BREVO_SMTP_KEY', 'BREVO_SENDER_EMAIL')
$bindings = foreach ($secretName in $secretNames) {
    $versionName = gcloud secrets versions list $secretName --project $projectId --filter='state=ENABLED' --sort-by='~createTime' --limit=1 --format='value(name)'
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($versionName)) { throw "No enabled version for $secretName" }
    $version = ($versionName.Trim() -split '/')[-1]
    if ($version -notmatch '^\d+$') { throw "Invalid secret version for $secretName" }
    $target = if ($secretName -eq 'ADMIN_BOOTSTRAP_CODE') { 'DEVELOPER_BOOTSTRAP_CODE' } else { $secretName }
    gcloud secrets add-iam-policy-binding $secretName --project $projectId --member="serviceAccount:$runtimeAccount" --role=roles/secretmanager.secretAccessor --condition=None --quiet | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Secret access binding failed for $secretName" }
    "$target=$($secretName):$version"
}
$secretBindings = $bindings -join ','
```

The existing runtime keeps its Firestore, RTDB, Auth, App Check and Storage
permissions. Add `roles/firebasecloudmessaging.admin` for FCM sending. Secret
access is scoped to each secret; no service-account key download is needed.
Create the two invocation accounts if missing, give Eventarc's account project
`roles/eventarc.eventReceiver`, and give both accounts `roles/run.invoker` on
the private worker after it exists. They do not need Brevo secret access.

```powershell
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$runtimeAccount" --role=roles/firebasecloudmessaging.admin --condition=None --quiet
gcloud iam service-accounts create voltrike-eventarc-invoker --project $projectId
gcloud iam service-accounts create voltrike-scheduler-invoker --project $projectId
gcloud projects add-iam-policy-binding $projectId --member="serviceAccount:$eventarcAccount" --role=roles/eventarc.eventReceiver --condition=None --quiet
```

Skip service-account creation when the accounts already exist. The deployment
identity needs permission to deploy Cloud Run, configure Eventarc/Scheduler,
attach these service accounts (`iam.serviceAccounts.actAs`), and manage the
listed IAM bindings. Retain Google-managed Eventarc, Pub/Sub and Scheduler
service-agent roles. These setup permissions belong to the deployment identity,
not to callers of the application.

## Initial deployment with the new sender disabled

Record current API revisions, old integration exports, triggers, schedules and
their numeric secret bindings before migration. Include auxiliary jobs such as
the legacy Node demo-activation job in the retirement inventory. Do not run the
steady-state workflow with notifications enabled before the coordinated
one-sender cutover below.

Deploy the worker first with sending disabled. Its Cloud Run timeout must be
120 seconds; the binary configures a 110-second HTTP write timeout and
100-second event/maintenance budgets. `REQUEST_TIMEOUT_SECONDS=10` bounds
individual upstream operations, not the worker's entire request.

```powershell
$sharedEnv = "GOOGLE_CLOUD_PROJECT=$projectId,FIREBASE_DATABASE_URL=$databaseUrl,FIREBASE_STORAGE_BUCKET=$storageBucket,GO_REQUIRE_APP_CHECK=false,REQUEST_TIMEOUT_SECONDS=10,LIVEKIT_SERVER_URL=$liveKitUrl,ADMIN_PORTAL_URL=$emailAdminPortalUrl,EMAIL_LOGO_URL=$emailLogoUrl,SENTRY_ENVIRONMENT=production,SENTRY_TRACES_SAMPLE_RATE=0.05"
gcloud run deploy $workerService --source services/voltrike-go --set-build-env-vars GOOGLE_BUILDABLE=. --region $region --project $projectId --service-account $runtimeAccount --no-allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 10 --timeout 120s --update-env-vars "$sharedEnv,GO_INTEGRATION_WORKER=true,GO_NOTIFICATIONS_ENABLED=false,GO_AUTOMATIC_RESTRICTION_MONITORING=false,SENTRY_DSN=$env:SENTRY_GO_DSN" --update-secrets $secretBindings
$workerUrl = gcloud run services describe $workerService --region $region --project $projectId --format='value(status.url)'
gcloud run services add-iam-policy-binding $workerService --region $region --project $projectId --member="serviceAccount:$eventarcAccount" --role=roles/run.invoker --condition=None
gcloud run services add-iam-policy-binding $workerService --region $region --project $projectId --member="serviceAccount:$schedulerAccount" --role=roles/run.invoker --condition=None
```

The worker must have neither `allUsers` nor `allAuthenticatedUsers` invoker
bindings. Check its IAM policy and confirm an anonymous request returns HTTP
403. Worker routes exist only when `GO_INTEGRATION_WORKER=true`; the public
API must not expose them.

Stage the API with the new automatic restriction-event producer disabled.
Keep existing settings and secret bindings using update flags. Its protected
`/api/v2/**` routes use Firebase identity, while `POST /auth/password-reset`
is public so a signed-out user can recover an account.

```powershell
gcloud run deploy $apiService --source services/voltrike-go --set-build-env-vars GOOGLE_BUILDABLE=. --region $region --project $projectId --service-account $runtimeAccount --allow-unauthenticated --min-instances 0 --max-instances 3 --cpu 1 --memory 512Mi --concurrency 40 --timeout 30s --update-env-vars "$sharedEnv,GO_ALLOWED_ORIGINS=$adminOrigin,GO_INTEGRATION_WORKER=false,GO_AUTOMATIC_RESTRICTION_MONITORING=false,POLICY_CACHE_TTL_SECONDS=60,MAX_DISPATCH_RESULTS=40,RATE_LIMIT_PER_MINUTE=240,SENTRY_DSN=$env:SENTRY_GO_DSN" --update-secrets $secretBindings
$apiUrl = gcloud run services describe $apiService --region $region --project $projectId --format='value(status.url)'
curl.exe --fail "$apiUrl/health"
curl.exe --fail "$apiUrl/ready"
```

Both API and worker reuse Brevo SMTP port 587 with required STARTTLS and
TLS 1.2 or later. Preserve sender identity, Firebase-generated action links,
templates, rate limits and delivery records. In particular, keep email links at
`https://voltrike-v2.web.app` and the existing `/images/appLogo.png` logo URL;
the API's allowed browser origin remains the Render Admin origin. SMTP acceptance is not proof of
inbox placement; test actual receipt with an authorized test account.

## Private Eventarc and Scheduler delivery

Create an Eventarc trigger in the Firestore database location, targeting the
private worker's `/events/outbox` route. Use creation events only and match
`outbox/{eventId}`. Eventarc sends binary CloudEvents with `Ce-Id`, `Ce-Type`,
`Ce-Source` and `Ce-Subject` headers and a protobuf document payload. The handler
validates those headers and reloads the stored outbox document.

```powershell
gcloud eventarc triggers create voltrike-outbox-created --location $eventLocation --project $projectId --event-filters='type=google.cloud.firestore.document.v1.created' --event-filters='database=(default)' --event-filters='namespace=(default)' --event-filters-path-pattern='document=outbox/{eventId}' --event-data-content-type=application/protobuf --destination-run-service=$workerService --destination-run-region=$region --destination-run-path=/events/outbox --service-account=$eventarcAccount
gcloud scheduler jobs create http voltrike-go-maintenance --location $region --project $projectId --schedule='* * * * *' --time-zone=Etc/UTC --uri="$workerUrl/tasks/maintenance" --http-method=POST --message-body='{}' --oidc-service-account-email=$schedulerAccount --oidc-token-audience=$workerUrl --attempt-deadline=120s
gcloud scheduler jobs pause voltrike-go-maintenance --location $region --project $projectId
```

Use `triggers update` or `jobs update http` for existing resources. The OIDC
audience is the worker's base service URL; the request URI includes the path.
Disabled outbox handling returns a retryable failure without claiming/sending
the event. Keep the new maintenance job paused while the legacy schedule runs.
Firestore Eventarc delivery is at least once and can arrive out of order;
the worker uses durable claims/receipts and scheduled retry recovery.
See [Firestore Eventarc delivery](https://docs.cloud.google.com/firestore/native/docs/eventarc)
and [Scheduler OIDC options](https://docs.cloud.google.com/sdk/gcloud/reference/scheduler/jobs/create/http).

## Client compatibility and one-sender cutover

1. Deploy and test the disabled worker and staged API, keeping the existing API
   URL, Firebase project, collections, Auth users, push tokens and shared secrets.
2. Rebuild Render Admin with its existing `VITE_VOLTRIKE_API_BASE_URL`, public
   Mapbox/VAPID configuration, and the updated Go calls. Keep App Check disabled. Rebuild and
   distribute the private Flutter APK with the same API URL. Test signed-out
   reset, verification, already-verified refresh, browser push token transfer,
   and existing booking/chat/call flows.
3. Coordinate a short integration cutover. Stop the old outbox sender and old
   maintenance schedules and retire the direct booking/chat/TODA/restriction
   event handlers. Await deletion completion and let in-flight deliveries finish.
   Before enabling the worker, inventory recent outbox records: set
   `notificationRetryAt` on eligible failed/expired-processing legacy records,
   preserving completed receipts. Reset only newly introduced TODA/offer types
   that the old worker completed as unknown during the deployment window;
   never replay completed booking notifications. Then enable
   `GO_NOTIFICATIONS_ENABLED=true` on the worker and
   `GO_AUTOMATIC_RESTRICTION_MONITORING=true` on the API. Resume only the new
   maintenance job. Never leave two active senders or duplicate maintenance
   schedules as the steady state.
4. Confirm a controlled outbox event produces one push/email, completed records
   are not replayed, failed deliveries recover, restriction alerts arrive, and
   maintenance executes once per minute. Watch worker errors and delivery age.
5. Keep legacy callable endpoints only for the verified client migration window.
   Old APKs still call them; old cached Admin pages also need a reload. Confirm
   invocation traffic has stopped before manual retirement. Remove the legacy
   Functions and auxiliary Node jobs only in a separately coordinated operation.
   Keep all shared Secret Manager resources and versions.

The workflow does not delete old Functions, Eventarc triggers or auxiliary jobs.
Retiring the old sender/trigger can be necessary to stop it; record an explicit
restoration procedure before that manual action. Removing shared Brevo secrets
would break the new Go services and is never part of retirement.

Flutter's email flow keeps branded email primary and uses Firebase Auth email
as a fallback for provider/service failures. A rate limit does not trigger a
second send. New Admin verification uses the authenticated Go operation and
does not depend on callable URLs. Rust stays in Flutter for local compute.

## Steady-state deployment and private APK distribution

The manual [hosted workflow](../../.github/workflows/deploy-hosted.yml) uses
Workload Identity Federation and the existing GitHub environment values:
`GCP_PROJECT_ID`, `GCP_REGION`, `FIREBASE_DATABASE_URL`,
`FIREBASE_STORAGE_BUCKET`, `ADMIN_ORIGIN`, `LIVEKIT_SERVER_URL`,
`RUNTIME_SERVICE_ACCOUNT`, `SENTRY_GO_DSN`,
`GCP_WORKLOAD_IDENTITY_PROVIDER`, and `GCP_DEPLOY_SERVICE_ACCOUNT`.

Optional variables are `GO_NOTIFICATIONS_ENABLED` and
`GO_AUTOMATIC_RESTRICTION_MONITORING` (both default to `true`),
`FIRESTORE_EVENT_LOCATION` (otherwise discovered), `SENTRY_WORKER_DSN`
(falls back to the existing Functions DSN or Go DSN), and numeric
`BREVO_SMTP_LOGIN_VERSION`, `BREVO_SMTP_KEY_VERSION`,
`BREVO_SENDER_EMAIL_VERSION` pins. Without pins it resolves enabled version
metadata and deploys numeric bindings, without reading secret payloads.
`EMAIL_ADMIN_PORTAL_URL` and `EMAIL_LOGO_URL` default to the existing web.app
email-link and image URLs above, independently of `ADMIN_ORIGIN`.
For the first staging deployment, explicitly set both switches to `false`;
the notification switch also pauses the new maintenance schedule. After the manual cutover,
use `true` for normal deployments.

The auxiliary hourly demo activation job also runs Go. Retain its existing
schedule, service account and fixed synthetic-data scope. Build the job image
from the same reviewed commit, pause its scheduler while replacing the Node
entrypoint, and clear the obsolete encoded script:

```powershell
$jobImage = "${region}-docker.pkg.dev/$projectId/cloud-run-source-deploy/voltrike-demo-activation-go:$release"
gcloud builds submit services/voltrike-go --config services/voltrike-go/cloudbuild.demo-activation.yaml --region $region --project $projectId --substitutions="_IMAGE=$jobImage"
gcloud scheduler jobs pause voltrike-demo-activation-hourly --location $region --project $projectId
gcloud run jobs update voltrike-demo-activation --image $jobImage --command /demo-activation --args='' --remove-env-vars=SEED_SCRIPT_BASE64 --region $region --project $projectId
gcloud scheduler jobs resume voltrike-demo-activation-hourly --location $region --project $projectId
```

Set `$release` to the deployed commit SHA. The Go job verifies project and
demo tags, preserves existing documents, gates future bookings, recomputes
synthetic driver summaries, and checks integrity. It needs only its existing
Firestore access; Brevo credentials are not attached to this job.

The workflow updates both Go services, dedicated invocation IAM, Eventarc and
Scheduler, then deploys only Firebase rules/indexes/storage configuration:

```powershell
firebase deploy --only firestore,database,storage --project $projectId
flutter build apk --debug --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app --dart-define=VOLTRIKE_ENABLE_APP_CHECK=false
```

Keep the existing Sentry Dart build defines when distributing the APK.
Quick Share `build/app/outputs/flutter-apk/app-debug.apk` to test phones.
Render remains the static Admin host (`npm ci && npm run build`, publish
`admin/dist`, SPA rewrite `/* -> /index.html`). Node/npm and Firebase CLI
remain build/development tools; this workflow never deploys Node Functions.
It preserves existing unmentioned Cloud Run environment variables and secrets.

Retain TTL on `command_receipts`, `communicationDeliveries` and `outbox`
`expiresAt` fields, and existing retention/backups. Monitor Cloud Run,
Eventarc/Pub/Sub, Scheduler, Firebase, Routes, Storage, Brevo and LiveKit usage.

## Rollback

Pause the new Scheduler job and set worker notifications to `false` before
reactivating any legacy sender. Disable the API's new automatic restriction
producer during the handover. Account for in-flight events and preserve
outbox/delivery receipts to avoid duplicate provider sends.

Route API/worker traffic to recorded verified Cloud Run revisions with
`gcloud run services update-traffic`. Restore the prior sender trigger and
maintenance schedule only after the new sender is stopped. Redeploy the
matching prior Render/Flutter clients if returning to callable endpoints;
older API revisions may lack the new public password-reset route.

Retain existing credentials and numeric bindings. Never rotate
`GO_QUOTE_ENCRYPTION_KEY` as an outage workaround, delete shared Brevo secrets,
or recreate Firebase users/collections to roll back application code.
