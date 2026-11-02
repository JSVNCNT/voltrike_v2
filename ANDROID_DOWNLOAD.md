# Download and update Voltrike for Android

The APK and its QR images are hosted on **GitHub Releases**. The QR contains the
permanent latest-APK link, so the same printed QR can download future versions.
No paid QR service or separate QR hosting is needed.

![Scan to download the latest VolTrike APK](assets/download/voltrike-qr.png)

- [Download the latest APK](https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike.apk)
- [Download the QR image (PNG)](https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike-qr.png)
- [Download the QR image (SVG, suitable for printing)](https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike-qr.svg)
- [View releases and release notes](https://github.com/JSVNCNT/voltrike_v2/releases)

## Install on a phone

1. Use an Android phone running **Android 7.0 or later** (minimum SDK 24).
2. Scan the QR with the phone's camera or open the APK link above.
3. Download `voltrike.apk`, then open the downloaded file.
4. If Android asks, allow **Install unknown apps** for the browser or file app
   opening the APK. Confirm installation.
5. Open Voltrike and grant the permissions needed by its features.

Android may show a warning because this APK is distributed outside Google Play.
Check that the download link belongs to `github.com/JSVNCNT/voltrike_v2`.

## Update an installed copy

Scan the **same QR**, download the latest APK, open it, and choose **Update**.
Updates are manual; the app does not automatically install new versions.
Keep the app installed during normal updates to retain its local data.

Android accepts an update when the application ID and signing key match, and the
new version has a higher build number. If installation reports a signature or
version conflict, check those details before changing the installed app.

## Publish the next version without local build commands

The initial release distributes the existing local test APK unchanged. Future
versions can be built and published through GitHub's website:

1. Open [Actions: Build and publish Android APK](https://github.com/JSVNCNT/voltrike_v2/actions/workflows/android-apk.yml).
2. Select **Run workflow** and use the branch containing the intended changes.
3. Enter the `version_name`, for example `1.0.0`, leave **Publish APK** checked
   for an actual release, and select **Run workflow**.
4. Wait for the workflow to finish with a green check. If it fails, open the run
   and read the failed step; a failed run does not mean a new APK was published.
5. Open [Releases](https://github.com/JSVNCNT/voltrike_v2/releases) and confirm the
   new release contains `voltrike.apk`, `voltrike-qr.png`, and `voltrike-qr.svg`.
6. Download and install the new APK on a phone to check the features you use.

For a validation-only build, uncheck **Publish APK**; this builds the app without
changing the public download. The first validation run leaves the original,
unchanged APK as the latest download.

The workflow generates the build number as `1000 + GitHub run number`. Each new
workflow run therefore produces a higher build number. Re-running an old run
keeps that run's number; start a new workflow run for a new update.

Building publishes the code already committed to the selected branch. Changes
to app behavior still require the relevant source changes first.

## Signing and configuration

This distribution preserves the current test app's application ID and existing
debug signing key so compatible installed test copies can be updated. It remains
a debug/test distribution. Keep a private backup of that same keystore; losing
or replacing it prevents normal updates to copies signed with it.

The workflow expects these repository **Settings > Secrets and variables >
Actions** secrets, configured once:

- `ANDROID_DEBUG_KEYSTORE_BASE64`
- `MAPS_API_KEY`
- `VOLTRIKE_API_KEYS_DART_BASE64`

Keep their values out of committed files, screenshots, release notes, and logs.
The first published APK preserves the existing binary. Download/signature checks
do not prove every feature works on every phone; confirm login, maps, location,
notifications, and other needed features on a device with the required services.

## Cost and stable links

For this public repository, the workflow uses a standard GitHub-hosted runner,
which [GitHub makes free for public repositories](https://docs.github.com/en/billing/concepts/product-billing/github-actions).
[GitHub Releases hosts downloadable binaries](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases),
with each asset limited to less than 2 GiB and no release bandwidth limit.
The static QR images are release assets and have no subscription or scan fee.

The QR encodes GitHub's supported
[`releases/latest/download/asset-name` link format](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases).
Keep the repository public and keep the APK filename `voltrike.apk` in each latest
release so the same QR continues to work. The QR itself does not expire.

Free APK building, release hosting, and QR distribution do not include Firebase,
Maps, or other backend/service usage; those services retain their own quotas and
pricing.
