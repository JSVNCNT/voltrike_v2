# VolTrike Admin Portal

Role-aware React/TypeScript portal for the existing `voltrike-v2` Firebase project.

## Roles

- **Developer admin**: city fares, TODA registration, TODA-admin assignment, all drivers, reports, account suspension, and coverage-zone approval.
- **TODA admin**: only its own drivers, driver earnings, reports, and Mapbox zone requests. It cannot edit city fares.

All privileged writes are Firebase callable Functions. The browser never receives Firebase Admin credentials, LiveKit secrets, or the administrator bootstrap secret.

## Local setup

```cmd
cd admin
copy .env.example .env
```

Set the value in `.env`:

```text
VITE_MAPBOX_ACCESS_TOKEN=INSERT_YOUR_PUBLIC_MAPBOX_TOKEN
```

Create a Mapbox token restricted to the Admin Portal URL(s), then run:

```cmd
npm install
npm run dev
```

## First developer admin

1. Create a normal Firebase Authentication email/password account for the developer administrator.
2. In the Functions directory, create a strong one-time bootstrap secret:

   ```cmd
   firebase functions:secrets:set ADMIN_BOOTSTRAP_CODE
   ```

3. Deploy the Firebase update from the repository root:

   ```cmd
   firebase deploy --only "functions,firestore:rules,storage"
   ```

4. Sign in at the Admin Portal and enter the same bootstrap code.
5. The portal promotes that account to `developer_admin`; later bootstrap attempts are rejected.

For the test TODA flow, the developer admin creates **Test TODA**, then enters the existing test driver's Firebase Authentication UID in the TODA page. Promotion changes the account to `toda_admin`, assigns its `todaId`, and suspends its former driver profile so it cannot operate as both identities.

## Render

The repository includes `admin/render.yaml`. Create a Render **Blueprint** from this repository, or create a Static Site with:

- Root Directory: `admin`
- Build Command: `npm ci && npm run build`
- Publish Directory: `dist`

Add `VITE_MAPBOX_ACCESS_TOKEN` as a Render environment variable. This is a public browser token, so restrict it by deployed URL in Mapbox; do not put secret Mapbox tokens in it.

Before production use, run `npm install` locally once and commit the generated `admin/package-lock.json`; Render can then use reproducible `npm ci` builds.
