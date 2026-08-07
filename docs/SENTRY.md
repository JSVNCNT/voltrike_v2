# Sentry monitoring

VolTrike uses one Sentry project per independently deployed runtime:

| Runtime | Sentry project | Runtime DSN setting |
| --- | --- | --- |
| Flutter plus bridged Rust errors | `voltrike-flutter` | `SENTRY_DSN` Dart define |
| React/Vite admin | `voltrike-admin` | `VITE_SENTRY_DSN` Render variable |
| Go Cloud Run API | `voltrike-go` | `SENTRY_DSN` Cloud Run variable |
| Firebase Functions | `voltrike-functions` | `SENTRY_DSN` Functions environment variable |

DSNs are public client identifiers. `SENTRY_AUTH_TOKEN` is private: keep it in
Render or GitHub secrets and never expose it through a `VITE_` or Dart define.

## Privacy and quota defaults

- Default PII collection is disabled.
- Request bodies, cookies, query strings, user details, breadcrumb data, and
  authentication-related headers are removed before events are sent.
- Session Replay, screenshots, and Flutter view hierarchy capture are off.
- Production traces default to five percent and can be changed through
  `SENTRY_TRACES_SAMPLE_RATE` or `VITE_SENTRY_TRACES_SAMPLE_RATE`.
- Expected Firebase callable validation/authentication errors are not reported.
- The SDK is disabled when its runtime DSN is empty.

## Local Flutter build

```powershell
flutter build apk --debug --dart-define=VOLTRIKE_API_BASE_URL=https://voltrike-api-v2-327670792817.asia-southeast1.run.app --dart-define=SENTRY_DSN=https://39ba2251daffea156fb5d535af5e801c@o4511869752836096.ingest.us.sentry.io/4511869828202496 --dart-define=SENTRY_ENVIRONMENT=production --dart-define=SENTRY_RELEASE=voltrike_v2@1.0.0+1
```

For obfuscated release builds, set `SENTRY_AUTH_TOKEN` only in the build
environment, build with `--obfuscate` plus `--split-debug-info`, and then run:

```powershell
dart run sentry_dart_plugin
```

The plugin reads organization/project settings from `pubspec.yaml` and the
token from the environment.

## Render admin variables

`render.yaml` declares the public DSN, environment, organization, and project.
Add only this private build secret in the Render dashboard:

```text
SENTRY_AUTH_TOKEN=<organization auth token>
```

The Vite plugin uploads hidden source maps during a production build and removes
the generated `.map` files from `dist` after upload. Builds still succeed without
the token, but source maps are not generated or uploaded.

## Cloud Run and Firebase Functions

The Go service reads `SENTRY_DSN`, `SENTRY_ENVIRONMENT`, `SENTRY_RELEASE`, and
`SENTRY_TRACES_SAMPLE_RATE`. The Firebase worker reads the same names. The hosted
GitHub workflow configures both runtimes from environment variables and the
current Git commit SHA.

Create these GitHub environment variables in both `staging` and `production`:

```text
SENTRY_GO_DSN=https://af49f7e804ab16f9608c44def16d3aa3@o4511869752836096.ingest.us.sentry.io/4511869837377536
SENTRY_FUNCTIONS_DSN=https://a6db502b1b43a0c8a25194e3422a3e7a@o4511869752836096.ingest.us.sentry.io/4511869848387584
```

The workflow creates the ignored Firebase `.env.<project>` file on its runner;
it does not commit the values.

## Source-map token

Create an organization auth token in Sentry with release/project permissions.
Store it as `SENTRY_AUTH_TOKEN` in Render and in GitHub Actions secrets. It is
only used while building artifacts and must never be present in the app bundle
or a committed `.env` file.
