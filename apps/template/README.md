# QB Tracker — the forkable template

A complete, single-file quiz bowl tracker: live scoring, player/team
management, sessions, and deep analytics. This folder is the **white-label
base for new forks** — every feature of the HSE app, none of the HSE
branding, and **zero credentials**.

**It works the moment you open `index.html`.** With no Firebase project
configured the app runs in **offline mode**: fully functional, with all data
stored in your browser (localStorage). Connect your own Firebase project
whenever you're ready to sync across devices.

---

## Fork guide (for a school or organization)

### 1. Copy the app

Copy this entire folder into its own repository (or a sibling folder in this
monorepo) and rename it to your organization. Everything below happens
inside that copy.

### 2. Brand it — the checklist

| Where | What to change |
| --- | --- |
| `src/js/01-constants.js` | `APP_NAME`, `APP_FILE_BASENAME`, `ADMIN_RESET_PASSWORD` (fork config block at the top — the only JS file you normally need to touch) |
| `src/index.template.html` | `<title>`, `apple-mobile-web-app-title`, the auth-card `<h2>`, the header `<h1>` and its `data-short` / `data-medium` attributes, welcome toast title, help-modal intro line, updates-modal subtitle |
| `manifest.webmanifest` | `name`, `short_name`, `id`, `theme_color` |
| `icons/icon.png` | your icon (512×512 PNG) |
| `package.json` | `name`, `description` |
| Default colors (optional) | pick a default theme in `01-constants.js` (`DEFAULT_COLOR_THEME`, `DEFAULT_ACCENT`), then recompute the pre-boot CSS values per `AGENTS.md` → *Theming* |

After any change under `src/`, rebuild and commit both:

```sh
npm run build     # regenerates index.html from src/
npm run check     # byte-exact rebuild + version agreement + branding guard
```

The included **branding guard** (`guard.js`, part of `npm run check`) fails
the build if any HSE identifier — names, repo URLs, API keys, the legacy
admin password — ever finds its way back in. It also enforces that this
repository's template ships with `firebaseConfig = null`.

### 3. Connect Firebase (enables sync, accounts, admin, updates)

1. Create a project at <https://console.firebase.google.com> (the free
   Spark tier is plenty).
2. **Authentication → Sign-in method:** enable *Email/Password* and
   *Anonymous*.
3. **Realtime Database:** create a database (locked mode is fine) and paste
   the rules from `firebase.database.rules.json`, or write stricter ones.
4. **Project settings → Your apps → Web app:** copy the config object.
5. In `src/js/01-constants.js`, replace `const firebaseConfig = null;` with
   your config and append the marker comment so the guard knows it's
   intentional:
   ```js
   const firebaseConfig = { apiKey:"…", authDomain:"…", databaseURL:"…", … }; // fork-configured
   ```
6. Rebuild (`npm run build`) and open the app — you'll get the sign-in gate
   instead of offline mode.
7. **Make yourself admin:** sign in once, then in the Realtime Database
   console add your UID under `adminUids` with value `true`
   (`.info/auth` isn't needed; you can grab your UID from the app's
   *Settings → User ID* panel). The admin panel, category defaults, release
   publishing, and user management unlock for you.

Every fork uses **its own** Firebase project — data is isolated by
construction, and the template physically cannot reach the HSE team's
database.

### 4. Wire up GitHub (optional — enables deploy badge + update downloads)

Still in `src/js/01-constants.js`:

- `GITHUB_REPO_URL` — your fork's repo (unlocks the repository/issues/releases
  buttons and the header version badge deploy status)
- `DOWNLOAD_URL` — raw URL of your deployed `index.html`
- `DEPLOY_HOSTNAMES` — e.g. `['your-org.github.io']`, so visitors of the
  live site never see local-file update banners

### 5. Deploy

`index.html`, `manifest.webmanifest`, and `icons/` are the entire runtime —
host them anywhere static:

- **GitHub Pages:** push to a repo and enable Pages on that branch. The
  `firebase.database.rules.json` file is not needed in production (you
  deploy rules via the Firebase console or CLI).
- Or Netlify / Cloudflare Pages / any web server / a shared drive — the app
  also runs fine opened directly from disk (that's what local-file update
  checks are for).

### 6. Set an admin reset password (recommended)

The danger-zone *"reset all data"* action is disabled until you set
`ADMIN_RESET_PASSWORD` in `src/js/01-constants.js`. Choose something only
your admins know — it is a second confirmation, not a substitute for
Firebase rules.

---

## Versioning

Same system as the upstream app: `VERSION` in `src/js/01-constants.js` is
the single source of truth, kept in sync with `package.json` and the built
`index.html` by `bump.js`.

```sh
npm run bump             # patch; add -- minor / -- major
npm run check            # gate before every push
```

This template starts at **v1.0.0** (feature parity with HSE v3.12.x).

## Differences from the HSE app (`../hse/`)

- **Offline mode** — localStorage-backed database shim
  (`createLocalDatabase()` in `src/js/04-firebase-init.js`) powers the whole
  app until `firebaseConfig` is set. Admin is granted locally so the app can
  be fully evaluated; the sync indicator reads *"Saved locally"*.
- **Standard themes only** — Indigo (default), Teal, Crimson, Purple,
  Sunset, Slate, Forest. The HSE-branded palettes (Tricolor, Royal) are not
  present.
- **No bundled credentials or repo URLs** — all external wiring is opt-in
  via the fork config block.
- **Hardcoded admin reset password removed** — replaced by the configurable
  (initially disabled) `ADMIN_RESET_PASSWORD`.
- **`guard.js`** — the branding firewall described above.

Internal identifiers shared with the upstream app (for example the
`--hse-blue` CSS paint-slot names) are deliberately kept so modules can be
ported between the two apps by simple file copies; they are invisible to
end users.

## Building & developing

See **AGENTS.md** in this folder for the full architecture notes: module
map, byte-exact build invariants, theming rules, gotchas, and the testing
pattern.
