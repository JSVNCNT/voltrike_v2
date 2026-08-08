param(
  [string]$ProjectId = 'voltrike-v2',
  [string]$StorageBucket = 'voltrike-v2.firebasestorage.app'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$lifecycleFile = Join-Path $repositoryRoot 'storage.lifecycle.json'
$ttlCollectionGroups = @(
  'chat',
  'messages',
  'typing',
  'bookingCalls',
  'chatModerationIncidents'
)

foreach ($collectionGroup in $ttlCollectionGroups) {
  & gcloud firestore fields ttls update purgeAt `
    --collection-group=$collectionGroup `
    --enable-ttl `
    --project=$ProjectId `
    --quiet
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to enable purgeAt TTL for $collectionGroup."
  }
}

& gcloud storage buckets update "gs://$StorageBucket" `
  --lifecycle-file=$lifecycleFile `
  --project=$ProjectId
if ($LASTEXITCODE -ne 0) {
  throw 'Unable to apply the ride-chat photo lifecycle policy.'
}

Write-Host 'VolTrike chat and call retention policies are configured.'
