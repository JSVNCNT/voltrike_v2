# VolTrike marketing website

A standalone React + Vite + Bootstrap site for the VolTrike capstone. It uses the app's Poppins/teal identity, actual app screens, SDG 13, the existing Android QR, and directly hosted MP4 videos. No YouTube, database, Supabase project, API credentials, or connection to the ride backend is required for the website.

## Preview on your computer

Use Node.js 22.12 or later (Node 24 LTS recommended). In PowerShell:

```powershell
cd C:\Users\Vincent\Documents\voltrike_v2\voltrike-marketing
npm.cmd ci
npm.cmd run dev
```

Open the printed address, normally **http://127.0.0.1:5178/**. Use Chrome's device toolbar to review phone sizes as well as the desktop layout. `npm.cmd` avoids PowerShell's restriction on `npm.ps1`.

## Deploy free on Vercel

1. Commit and push **the `voltrike-marketing` folder and the root `.gitignore`** to your GitHub repository. Include `public/videos/`, `public/fonts/`, screenshots, QR, and `package-lock.json`. The project is self-contained: Vercel does not need the ignored `tmp` or `output` folders or the master videos in `assets/videos`.
2. Sign in to Vercel using your GitHub account. Select **Add New → Project**, then import the repository.
3. Set **Root Directory** to **`voltrike-marketing`**. Use the **Vite** framework preset and **Node.js 24.x**. Build command is **`npm run build`**; output directory is **`dist`**. `vercel.json` supplies these defaults. Leave environment variables empty.
4. Click **Deploy**. Use the supplied `*.vercel.app` address to avoid buying a domain. The exact name depends on availability.
5. Open that address on both a computer and an Android phone. Check the navigation, all three role buttons, FAQ answers, both video players/fullscreen/seeking, QR scanning, and APK download. The ad has its original audio; the approved demo remains completely silent.

If you deploy this folder as its own separate repository, use the repository root instead of `voltrike-marketing` in step 3. GitHub/Vercel sign-in and authorizing repository access are done in your own account. No deployment has been performed automatically.

Vercel Hobby is for personal/non-commercial projects and has usage limits. Keep this a non-commercial capstone showcase while using Hobby. Video playback uses the site's transfer allowance; monitor Usage in Vercel. Current published allowances and terms:

- https://vercel.com/docs/plans/hobby
- https://vercel.com/legal/terms
- https://vercel.com/docs/limits#static-file-uploads
- https://vite.dev/guide/static-deploy.html#vercel

## Build and verify

```powershell
npm.cmd run build
npm.cmd run check
npm.cmd run preview
```

The build prerenders the three pages for readable HTML/search indexing and hydrates them with React for interactions. On Vercel, the production hostname automatically supplies canonical and social-image URLs when available. `npm run preview` serves the production build at **http://127.0.0.1:4178/**.

With that preview running, a second terminal can verify HTTP assets and MP4 seeking:

```powershell
npm.cmd run check -- http://127.0.0.1:4178
```

Checks cover prerendered content, section links, local assets, the preserved QR, both MP4 durations/fast-start metadata, silent demo integrity, and HTTP byte ranges. The approved QR/demo hashes are recorded in `scripts/media-baseline.json`, so the checks require no master files outside this folder. These checks do not replace a visual browser review.

## Content and media

- Main content, Android link, FAQs, and website notices: `src/App.jsx`.
- Theme and responsive layout: `src/styles.css`.
- Titles and sharing description: `index.html`; supporting pages: `privacy.html`, `terms.html`.
- Advertisement: `public/videos/voltrike-ad.mp4` (web-optimized copy, about 31 MB, 1:29).
- Approved silent demo: `public/videos/voltrike-demo.mp4` (about 13 MB, 2:51).
- Thumbnails: `public/images/ad-poster.jpg`, `demo-poster.jpg`.
- Download QR: `public/images/app-qr.svg`. Preserves `assets/download/voltrike-qr.svg` exactly.

Video files are requested only after pressing Play. They use native browser controls and can be viewed inline on mobile or fullscreen. Directly hosted public videos are not copy-protected. Originals in `assets/videos` were not overwritten. If replacing a video, keep MP4/H.264 compatibility and fast-start metadata, update its thumbnail/caption, and run the checks. The demo check intentionally detects replacement of the approved edit; update it deliberately when approving a new demo.

Download destination: `https://github.com/JSVNCNT/voltrike_v2/releases/latest/download/voltrike.apk`. Keep the release asset named `voltrike.apk` so this link and the QR continue to work. The current copy clearly identifies Android 7.0+, cash payment, and capstone/test status.

## Assets and attribution

VolTrike logo, vehicle illustrations, advertisement, and app screens reuse the supplied project material. Screens show demonstration data; older documented screens may differ from subsequent app updates. Poppins is self-hosted with its license at `public/fonts/OFL.txt`. Decorative line art and interface SVG icons are defined in the website source. SDG 13 artwork comes from the existing presentation assets; official information is linked at https://sdgs.un.org/goals/goal13. The site makes no measured carbon-savings or UN-endorsement claim.

## Git exclusions

The root `.gitignore` now ignores **all of `/output/`**, including documents, spreadsheets, PDFs, presentations, and videos. It also excludes this site's `dist/`, `node_modules/`, `.vercel/`, and local `.env` files. No output files were tracked when this change was made, so no index removal was needed. Keep website `public/` assets tracked: those are deployment inputs.
