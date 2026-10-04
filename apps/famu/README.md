# FAMU HCASC — Quiz Bowl Tracker

The Florida A&M University **Honda Campus All-Star Challenge** tracker: live
scoring, player/team management, sessions, and cross-session analytics.
Forked from the [`apps/template/`](../template/) QB Tracker base — every
feature, FAMU branding, and **zero connection to the HSE app or its data**.

- **App name:** FAMU HCASC
- **Colors:** FAMU orange & green — the default **FAMU** theme uses official
  green `#008344` (structural color) and orange `#F4811F` (accent/highlights);
  7 standard themes remain available
- **Version:** 1.0.0 (feature parity with HSE v3.12.x / template v1.0.0)

**New: full step-by-step guide in [SETUP.md](SETUP.md)** — using the app today (offline) and turning on Firebase sync when ready.

## Current status: offline mode (safe by default)

Until FAMU's own Firebase project is connected, the app is fully usable with
**all data stored in the browser** (localStorage) — perfect for trying it
out, running practice sessions on one device, or demos. Nothing syncs and
nothing leaves the device.

## When you're ready to sync across devices

Follow [the template README's Firebase guide](../template/README.md) —
the short version:

1. Create a Firebase project for FAMU HCASC (free tier is plenty).
2. Enable **Authentication** (Email/Password + Anonymous) and create a
   **Realtime Database** with the rules from `firebase.database.rules.json`.
3. In `src/js/01-constants.js`, replace `const firebaseConfig = null;` with
   your project's config and append `// fork-configured` to the line.
4. `npm run build` — the sign-in gate appears, and data syncs to FAMU's own
   database (which no other school or app can touch).
5. Sign in once, then add your UID under `adminUids` in the database console
   to unlock the admin panel.
6. Set `ADMIN_RESET_PASSWORD` in the same constants file to enable the
   danger-zone reset.

## Everyday development

```sh
npm run build     # regenerate index.html from src/ (required after any src/ change)
npm run check     # byte-exact rebuild + version agreement + branding guard
npm run bump      # ship a new version (patch by default)
```

The **branding guard** runs on every check and fails the build if any HSE
identifier (names, URLs, API keys) ever leaks into this app — keeping the
FAMU install permanently isolated from the HSE one.

## Deploying

`index.html`, `manifest.webmanifest`, and `icons/` are the entire runtime —
host them on GitHub Pages, Netlify, any static host, or run from a local
file. Inside this monorepo it is already reachable at
`…/HSEQB/apps/famu/`. For a production FAMU deployment, this folder can be
copied verbatim into its own repository (see the root README for the
monorepo layout).

See **AGENTS.md** in this folder for full architecture notes, and the
[template README](../template/README.md) for the complete fork guide.
