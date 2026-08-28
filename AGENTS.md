# HSE Quiz Bowl Tracker (HSEQB)

Single-file web app for running live quiz-bowl sessions: real-time scoring,
player/team management, session library, and cross-session analytics.
State syncs through Firebase Realtime Database; the committed **`index.html`
is the deployable artifact** (static GitHub Pages).

## Build system (byte-exact)

`src/` is the source of truth. `index.html` is generated from it and must be
rebuildable **byte-for-byte** at all times.

- `src/index.template.html` — full page skeleton with five unique markers.
- `src/manifest.json` — for each marker, the ordered list of `src/` files
  whose plain concatenation (no separator) replaces the marker.
- `build.js` / `npm run build` — performs the substitution and writes
  `index.html`. No dependencies, no bundler, no transpilation.
- `bump.js` / `npm run check` / `npm run bump` — automatic version
  management and version drift detection (see [Automatic versioning](#automatic-versioning)).

**Workflow (every change to `src/`):**

```sh
npm run build            # regenerate index.html
git diff --exit-code index.html   # must be empty when only src/ moved around
git add -A && git commit          # commit src/ AND index.html together
```

Never edit `index.html` by hand — edit `src/`, rebuild, and commit both.
A non-empty `git diff index.html` after a pure refactor means the split
drifted from the committed output.

### Markers

| Marker in template | Replaced by (manifest order) |
| --- | --- |
| `@@@CSS_CORE@@@` | `src/css/core.css` (minified core styles) |
| `@@@CSS_THEME@@@` | `src/css/theme.css` (auth/appearance + iPad & coarse-pointer accessibility) |
| `@@@JS_THEME_INIT@@@` | `src/js/theme-init.js` (head script: applies cached theme before first paint) |
| `@@@JS_SANDBOX@@@` | `src/js/sandbox-warning.js` (body script: sandbox/iframe warning) |
| `@@@JS_MAIN@@@` | the 31 main modules below, in order |

### Main script modules (execution order)

| # | File | Responsibility |
| --- | --- | --- |
| 00 | `core-utils.js` | `$` helper, iframe detection, global error listeners, `_safe()` |
| 01 | `constants.js` | `VERSION` (auto-managed by `bump.js` — see [Automatic versioning](#automatic-versioning)), Firebase refs, `_adminToken`, `_noopRef` |
| 02 | `theme.js` | light/dark/device theme modes, accent sync, device-theme listener |
| 03 | `auth.js` | Firebase Auth: sign in / guest / create / upgrade / reset, profile customization |
| 04 | `firebase-init.js` | `initFirebase`, `startApp` (wires listeners, version badge, banners) |
| 05 | `releases.js` | global settings saves, version publish, release prompt/update banner |
| 06 | `user-identity.js` | display-name load/save/clear, welcome toast |
| 07 | `write-lock.js` | client id, per-id write locks, atomic session transactions |
| 08 | `session-model.js` | session normalization, category tree, answer-type predicates |
| 09 | `state.js` | the global `state` object and UI flags |
| 10 | `sync-indicators.js` | autosave/connecting indicators, save notifications |
| 11 | `gh-deploy.js` | GitHub Actions poll for the version-badge deploy status |
| 12 | `data-load.js` | global players, load/save all data, fade masks, header height |
| 13 | `sessions.js` | create/load/delete sessions, session modal, bulk operations |
| 14 | `player-detail.js` | player detail modal, score-band modal |
| 15 | `admin-panel.js` | admin list, category colors & frequency defaults |
| 16 | `rename-substitute.js` | first `renamePlayer`, `executeSubstitution` |
| 17 | `analytics.js` | Tracker/Analytics toggle, overview tab, global aggregates |
| 18 | `analytics-players.js` | universal player stats, leaderboard, low-data controls |
| 19 | `analytics-teams.js` | team compositions tab, team filters |
| 20 | `analytics-charts.js` | Chart.js registry, all chart rendering (contains runtime-injected `<style>` in a template literal) |
| 21 | `sidebar-ui.js` | sidebar sections, jump nav, danger zone, mobile drawer, accent/skill-threshold/scrollbar controls |
| 22 | `visual-settings.js` | restore visual settings, master `renderAll`, session info panel |
| 23 | `player-management.js` | player pool CRUD, rename (second def), merge/split, player buttons |
| 24 | `quick-log.js` | per-player quick scoring rows (the main match-time input surface) |
| 25 | `toasts.js` | record/app/confirm toasts, `showConfirm` promise, admin UI refresh |
| 26 | `substitution-panel.js` | in-game substitution panel |
| 27 | `setup-panels.js` | player import, teams panel, category button rendering |
| 28 | `recording-and-stats.js` | point types, `recordAnswer`, keyboard shortcuts, answer log, session stats |
| 29 | `data-io.js` | JSON/CSV/Excel import & export, file download |
| 30 | `debug-boot.js` | debug data injection/clear/reset, `DOMContentLoaded` boot |

## Automatic versioning

The app version is a single semver string, `VERSION` in
`src/js/01-constants.js`. **Never hand-edit the number** — `bump.js` updates
it everywhere in one command, so it can never drift. It keeps three files in
sync; they must always agree:

1. `src/js/01-constants.js` — `const VERSION = 'x.y.z';` (the source of truth)
2. `package.json` — `"version": "x.y.z"`
3. `index.html` — regenerated by `bump.js` (via `build.js`) so the built
   artifact and its header version badge carry the new version

Commands (all dependency-free, cross-platform Node):

```sh
npm run bump             # patch bump (3.7.0 → 3.7.1): rewrite VERSION +
                         # package.json and rebuild index.html in one step
npm run bump -- minor    # minor bump (3.7.0 → 3.8.0)
npm run bump -- major    # major bump (3.7.0 → 4.0.0)
npm run check            # safety gate: versions agree AND index.html is a
                         # byte-exact rebuild of src/ (fails on drift/stale)
node bump.js --check     # same as npm run check
```

**Shipping a new version** (when work is ready to go out — usually the
release PR):

```sh
npm run bump             # picks patch by default; add -- minor / -- major
npm run check            # must pass
git add -A && git commit -m "chore(release): v$(node -p "require('./package.json').version")"
git push                 # then open / merge the PR — main now carries the
                         # new version and rebuilt index.html
```

- A **patch** (`3.7.0 → 3.7.1`) is the normal case for fixes and small
  changes; **minor** for new features; **major** for breaking changes.
- On an in-progress feature branch you normally do **not** bump — leave
  `VERSION` at the current released version and run `npm run check` before
  pushing. Bump once when the change is ready to ship.
- There is no CI bot that bumps for you: the version advances when someone
  runs `npm run bump` as part of a release. `npm run check` is the gate that
  keeps the three files honest before every push.

## Data model

Firebase RTDB (root `qb/…` under the app's nodes):

- **sessions** — `{ id: <Date.now string>, name, teams[], players{}, answers[], answerLog[], categories[], tHeard, … }`
  - `players` is a **map keyed by player name**: `{ powers, tossupsCorrect, negs, misses, tHeard, totalAnswers, answers[], … }`
  - `teams`: `{ id, name, playerMembers[] }`
  - `answerLog`: ordered recording of every outcome (drives the log view and THeard logic)
- **globalPlayers**, **version** (published build info), **releaseHtml** (full
  `index.html` string published by admins so local-file users download updates
  straight from Firebase — no GitHub request), **globalSettings**
  (category frequencies/colors, skill threshold, manual analytics inclusions),
  **userIdentities** (display names), **userProfiles** (per-user visual settings),
  **adminList**, per-user **clientId**.

Answer record shape:

```js
{ id, player, pointType: 'Power'|'Toss-up'|'Neg'|'Miss'|'Dead'|'Bonus',
  category, points, timestamp }
```

Bonuses are recorded against a pseudo-player `__team__<id>` (rendered as
`— Team Name Bonus —`) and are **never** attributed to individuals.

## Scoring model

Point values: Power **+15**, Toss-up **+10**, Neg **−5**, Miss **0**, Dead
**0**, Team Bonus **+10/part (team only)**.

**Toss-Ups Heard (THeard)** increments once on the first outcome of a
toss-up; a correct answer after a Neg/Miss is a follow-up (no new THeard).
Required for all normalized player metrics.

Player metrics (official toss-up decisions only):

- Raw TU/20 `rawImpact = (15·P + 10·T − 5·N) / H × 20`
- Reliability `= (P+T) / (P+T+N+M) × 100`
- Power Rate `= P / (P+T+N+M) × 100` (negs and misses count against it)
- Participation `TU/20 = (P+T+N+M) / H × 20`
- Confidence `= H / (H + k)` — at `H = k` the raw score is 50% trusted
- **Leaderboard Score** `= confidence × rawImpact + (1 − confidence) × teamAverage`

A player is **ranked** only after `RANKED_MIN_TU = 20` toss-ups heard (one
full session); provisional players show diagnostics but get no Leaderboard
Score and are excluded from the team average and automatic `k`.
`k` is auto-derived from the data with a low-data threshold
(`skillThresholdPct`, admin-adjustable).

## Architecture notes

- **Three inline scripts** in the built page: `theme-init` (head, runs before
  paint so the cached theme shows immediately), `sandbox-warning` (body), and
  the main app script (31 modules concatenated in manifest order).
- **Sandbox/iframe mode**: when embedded in a cross-origin iframe (preview
  sandboxes), `isIframe` stubs Firebase with `_noopRef`, swaps
  `localStorage` for an in-memory store, and disables sync — the app remains
  fully usable offline for demos.
- **`isAdmin`** is a non-writable `window` property backed by
  `_adminToken.grant/revoke/check`; never assign `window.isAdmin` directly.
- **Versioning/deploy**: `VERSION` lives in `01-constants.js` and is
  managed with `bump.js` (`npm run bump` / `npm run check` — see
  [Automatic versioning](#automatic-versioning)); never hand-edit the
  number. The header badge polls GitHub Actions runs for deploy status;
  admins publish a build to Firebase (`publishRelease`), which drives the
  update banner shown to local-file users. `publishRelease` uploads the new `index.html` string to
  the `releaseHtml` node and keeps `appVersion` lightweight (label, buildId,
  releaseNotes, downloadUrl fallback, `hasFirebasePayload` flag); regular app
  loads only read `appVersion`, and `downloadUpdate` pulls the HTML payload
  from `releaseHtml` in-memory (Blob download) before falling back to the
  GitHub raw URL for older releases.
- **`local-settings.js`** is an *optional* local-only override file
  (loaded with `onerror="void 0"`); it is intentionally not in the repo.
  `window.LOCAL_SETTINGS` can pre-seed visual settings.
- **iPad / coarse-pointer accessibility** (in `css/theme.css`, marked
  "iPad & coarse-pointer accessibility"): `touch-action: manipulation` on
  all controls, 44 px+ tap targets and 16 px input floors under
  `@media (pointer: coarse)`, `:active` pressed states under
  `@media (hover: none)` (hover never fires on iPad), side-drawer sidebar in
  portrait (641–900 px), slimmer sidebar in landscape (901–1200 px), and
  `env(safe-area-inset-*)` for landscape full-screen (PWA). `manifest.webmanifest`
  + `icons/icon.png` + `apple-touch-icon` support "Add to Home Screen" as a
  standalone app. Pinch-zoom is intentionally left enabled for accessibility.

## Theming (HSE palette)

The default palette is **Royal** (`DEFAULT_COLOR_THEME = 'royal'` in
`01-constants.js`: primary `#0b41a8`, companion `#002b7f`, white). The default
accent style is **Gradient** (`DEFAULT_ACCENT_STYLE = 'gradient'`). These
defaults must agree at three levels or the first frame drifts off-brand:

1. `css/core.css` `:root` / `html.dark-mode` carry the **exact** values
   `_paintColors('#0b41a8','#002b7f','#ffffff')` produces, so the pre-boot
   paint already looks like the default theme. Recompute them with the real
   `_shadeHex` / `_mixHex` / `_hexLum` helpers if a palette value changes —
   never by eye.
2. `restoreVisualSettings()` falls back to `DEFAULT_COLOR_THEME` when nothing
   is stored, and `resetLocalCustomizationForAccountSwitch()` strips the inline
   custom properties back to those same defaults.
3. `css/theme.css` holds the HSE color language (see below).

**Palette tokens** — `_paintColors()` (`21-sidebar-ui.js`) is the only place
that writes inline custom properties: `--primary`, `--primary-light`,
`--primary-dark`, `--secondary`, `--accent-line`, `--tertiary`, `--hse-blue`,
`--hse-red`, `--hse-white`. Everything else is **derived in CSS** from those
palette values with `color-mix()` in `theme.css`, so surfaces, borders, and
highlights all follow the palette and the light/dark mode automatically:

| Token | Role |
| --- | --- |
| `--border` | hairlines and dividers — light companion-color tint over the neutral base |
| `--panel-border` | panels, cards, containers — stronger tint, so outlines are never flat gray |
| `--border-strong` | hover state for panels |
| `--input-border` | inputs, subtlest tint |
| `--highlight` / `--highlight-ink` / `--highlight-wash` | accent emphasis text, its contrast-adjusted hover shade, and a matching wash |

Two rules keep this from breaking:

- **Never declare a `_paintColors`-owned property (`--primary`, `--accent-line`,
  …) inside a bare `.dark-mode` rule.** `body` carries `.dark-mode` too
  (`02-theme.js`), and a stylesheet value there beats the value inherited from
  the inline style on `<html>`, flattening every custom palette back to HSE.
  Pre-paint dark defaults belong on `html.dark-mode`.
- Blue stays the structural/interactive color; the accent color handles
  emphasis (scores, ranks, player links, help headings) and outlines. Canvas
  colors cannot read custom properties — use `accentRgba()` in
  `20-analytics-charts.js` rather than a hardcoded hex.

`core.css` keeps the plain neutral values (`--border:#c9cfdd`,
`--input-border:#dde1ea`, dark `#444e63` / `#2d3340`) ahead of the `color-mix()`
redeclarations in `theme.css`, so a browser without `color-mix()` support
degrades to a gray outline instead of none.

## Gotchas

1. **`renamePlayer` is defined twice** — once in `16-rename-substitute.js`
   (single-arg) and again in `23-player-management.js` (two-arg). The later
   declaration shadows the earlier one at runtime. Do not "fix" or reorder
   this when moving code.
2. **Module order is execution order.** `let`/`const` initialization order
   matters across files (they share one script scope). Keep the manifest
   order stable; renumber filenames only with care.
3. `20-analytics-charts.js` contains a literal `</style>` **inside a
   template literal** (runtime chart styles). Never "clean it up" — the
   main script must also contain no literal `</script>` substring or the
   inline `<script>` block would terminate early.
4. `core.css` is minified, `theme.css` is readable. Both are fine to edit,
   but remember the invariant: rebuild and commit the new `index.html`.
5. The head script must stay dependency-free (it runs before the app and
   before Firebase/Chart.js CDN scripts are needed) and must keep working
   when storage is unavailable (private browsing) — everything is in
   try/catch.

## Testing pattern

There is no test runner; the invariants are mechanical:

```sh
# 1. Byte-exact rebuild + version agreement (run before every push/merge)
npm run check

# 1b. Byte-exact rebuild on its own (must be silent/clean)
npm run build && git diff --exit-code index.html

# 2. Every module parses standalone
for f in src/js/*.js; do
  node -e "new Function(require('fs').readFileSync(process.argv[1],'utf8'))" "$f" \
    || echo "PARSE FAIL: $f"
done

# 3. The concatenated main script parses as the browser will run it
node -e "const m=require('./src/manifest.json');const f=require('fs');new Function(m.blocks['@@@JS_MAIN@@@'].map(x=>f.readFileSync(x,'utf8')).join(''))"
```

Manual smoke test: open `index.html` directly in a browser (guest mode,
iframe-sandboxed in this repo's preview — Firebase is stubbed there), and on
a device/Emulator check the tablet breakpoints (768 px portrait drawer,
1024 px+ desktop layout) and that scoring buttons respond to rapid taps
with no double-tap zoom.
