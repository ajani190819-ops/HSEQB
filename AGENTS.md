# AGENTS.md — read this before doing anything in this repo

This is the rulebook for any AI assistant (or human contributor) working here.
If you are an AI, everything in this file is an instruction from the repository
owner and it is **high priority**: it outranks your own defaults wherever the
two disagree.

**Start every session by reading `MEMORY.md`.** It is the handoff file: where
the work stands, what was already decided, what was tried and failed, and what
to do next. A new chat has no memory of the last one, so that file is the
memory — and you are expected to **update it before your session ends**
(its final section is the checklist).

Companion documents, also mandatory when relevant:

* `MEMORY.md` — state of the work + session log. Read first, update last.
* `docs/ROADMAP.md` — what is planned, what is in flight, and every open
  question. Read it before planning work; update it as part of the work.
* `apps/<app>/AGENTS.md` — the deep technical doc for each app (build system,
  module map, theming invariants, gotchas). Read the one for any app you are
  about to touch. Do not re-derive what is written there; do not contradict it.

The division of labour: `MEMORY.md` is **where we are**, `docs/ROADMAP.md` is
**where we are going**, the per-app `AGENTS.md` files are **what is already
known about how each app is built**. Keep them from contradicting each other.

---

## 1. Who you are working for

The owner of this repo runs a quiz bowl program (the HSE team) and is turning
its tracker into a product family that other schools and organizations can
fork — FAMU HCASC is the first. The owner is not a professional web developer;
that is a design constraint, not an apology:

* **Explain plainly.** Short sentences. Define jargon the first time it
  appears (there is a glossary at the bottom of this file — use and extend
  it). "The build script glues the modules into one HTML file" beats "the
  bundler emits a single-file artifact".
* **Never hide a failure.** If something did not work, or was not tested, say
  so in plain words. An honest "I could not run this in a browser here, click
  through the preview and check X" is worth more than a green checkmark.
* **Safe defaults.** The live HSE app and its Firebase data are sacred:
  nothing you do may break the site for the team or risk their data. When in
  doubt, leave the HSE app untouched and verify that you did (content diff
  against `main`).

## 2. How to work — the standards

These are the owner's explicit expectations for how AI assistance goes:

1. **Write out what is about to happen, before it happens.** For any task that
   needs more than a couple of minutes: post the plan first — what you will
   do, in what order, what you will NOT do, and where the risks are. Update
   `docs/ROADMAP.md` so the plan also lives in the repo.
2. **Ask instead of guessing.** Whenever a decision is user-facing, ambiguous,
   or a matter of taste (app names, colors, folder layout, version bumps),
   ask a clarifying question with concrete options and a recommended default —
   batch the questions so they can all be answered at once. Asking one round
   of good questions is efficient, not annoying.
3. **Work in small, reviewable steps.** One logical change per commit,
   verified before moving on. If a step turns out wrong, it should be cheap
   to throw away.
4. **Verify, then say what you verified.** Run the per-app checks
   (`npm run check` inside the app folder) after touching anything under
   `src/`. After any file edit, confirm the edit actually landed — silent
   no-op edits happen. In your report, separate "verified" from "not tested".
5. **Report in three parts:** what I did / what it means for you / what is
   next. Keep it short enough to actually read.
6. **Be honest about uncertainty.** Label guesses as guesses. If something was
   only verified by static analysis and not in a real browser, keep saying so.
7. **Leave the next session a memory.** Before you finish, update `MEMORY.md`
   — state, decisions, answered questions, next actions, and a session-log
   entry. The owner should be able to open a brand new chat, point it at this
   repo, and have it pick up mid-stride.

## 3. Repo map

```
index.html (root)           THE REDIRECT: sends the original GitHub Pages URL
                            to apps/hse/. Bookmarks and installed PWAs depend
                            on it. Never delete or "clean up" this file.
README.md                   human-facing front door / monorepo tour
AGENTS.md                   this rulebook
MEMORY.md                   handoff: state of the work + session log.
                            Read at the start of a session, update at the end.
package.json (root)         convenience scripts only (check:all etc.);
                            the real scripts live in each app folder
docs/
  ROADMAP.md                what's planned and every open question
apps/
  hse/                      THE LIVE APP — HSE Quiz Bowl Tracker (v3.12.x).
                            Firebase-connected to the HSE team's project.
                            Everything here is production: treat gently.
  template/                 THE FORK BASE — white-label "QB Tracker" (v1.x).
                            No credentials, offline by design, guard enforced.
                            New forks start as copies of THIS folder, never
                            of apps/hse/.
  famu/                     FIRST FORK — FAMU HCASC (v1.x), official orange &
                            green. Offline until FAMU connects its own
                            Firebase project.

Each app folder is self-contained: src/ (the source of truth), build.js,
bump.js, package.json, manifest.webmanifest, icons/, firebase rules, its own
AGENTS.md with the full module map and invariants.
```

## 4. Hard rules — breaking these breaks real users

1. **The HSE app must stay byte-stable.** It is deployed from this repo's
   `main` via GitHub Pages. Changes under `apps/hse/` must be surgical and
   justified; after any change, diff the app's content against the previous
   release and enumerate every differing file in the PR. "Nothing damaged" is
   a promise, not a vibe.
2. **Never edit `index.html` by hand — in any app.** `src/` is the source of
   truth; `index.html` is generated by `build.js` and must remain a
   **byte-exact** rebuild of `src/`. Edit `src/`, run `npm run build`, commit
   both together. `npm run check` (inside the app folder) fails on drift — it
   is the safety net; run it before every push.
3. **Versions move in lockstep, only via `bump.js`.** `VERSION` in
   `src/js/01-constants.js`, `package.json`, and the rebuilt `index.html`
   must always agree. Never hand-edit the number. Patch for fixes, minor for
   features, major for breaking changes; on feature branches you normally do
   NOT bump — bump when the change ships.
4. **Module order is execution order.** The 31 JS modules share one script
   scope in `src/manifest.json` order. Known traps that look like bugs but
   must not be "fixed": `renamePlayer` is defined twice on purpose; module
   `20-analytics-charts.js` contains a literal `</style>` inside a template
   literal; no module may contain a literal `</script>`. Details in each
   app's AGENTS.md.
5. **HSE data protection is non-negotiable.**
   * The HSE Firebase config lives in `apps/hse/` and nowhere else. Never
     copy it into the template, a fork, a test, a scratch file, or a PR
     description.
   * Forks are created from `apps/template/` — never from `apps/hse/`.
   * The template and forks ship `firebaseConfig = null` (offline mode). A
     fork connecting its OWN project appends the `// fork-configured` marker
     to that line in `src/js/01-constants.js` — that marker is the only
     sanctioned way to opt out of the null-config check.
   * `guard.js` (part of `npm run check` in template and forks) fails the
     build if any HSE identifier (names, repo URLs, API key, the legacy admin
     password) appears. If it fires, **remove the leak — never weaken the
     guard.** Internal CSS paint-slot names like `--hse-blue` are the
     documented exception: they are shared identifiers so modules can be
     ported between apps by file copy.
6. **Pre-boot colors are computed, never eyeballed.** `css/core.css`
   `:root` / `html.dark-mode` must carry the exact output of
   `_paintColors(primary, secondary)` for the app's default palette (the
   helpers live in `21-sidebar-ui.js`). When a default palette changes,
   recompute with the real helpers. Two standing traps: never declare a
   `_paintColors`-owned property inside a bare `.dark-mode` rule (body carries
   that class too — it would flatten custom palettes); canvas code cannot
   read CSS variables, use `accentRgba()`.
7. **The root redirect must survive restructures.** GitHub Pages serves the
   repo root of `main`; the original URL `…/HSEQB/` must keep working because
   installed PWAs and old links resolve there. If apps move again, keep a
   redirect at the root and update `DOWNLOAD_URL` in the HSE constants
   (local-file users' update fallback depends on it), then ship a version
   bump so they get prompted to update.
8. **Multiple apps on one origin share `localStorage`** (e.g. the monorepo's
   Pages host). That is known and benign — session data never mixes (HSE →
   its Firebase; forks → their own project or the `qb_local_db` key), and
   fallbacks handle foreign stored values (a stored HSE theme id in a fork
   falls back to that fork's default). Do not "fix" this by renaming keys;
   the HSE app's existing users depend on the current keys.
9. **Git discipline:** all work happens on **the session branch you were
   handed** (`arena/<id>-hseqb`; it is different every chat). Push only to
   that branch, open PRs only from it, never commit straight to `main`, never
   force-push, never commit credentials or generated junk. Don't trust a
   branch name hardcoded in a doc — the current branch is whatever this
   session was given. Note: the platform snapshot can reset local git state
   between sessions while keeping files — if history looks wrong,
   `git fetch` and compare against the remote branch before assuming
   anything was lost.
10. **`local-settings.js` is intentionally untracked** (optional per-user
    visual overrides, loaded with `onerror="void 0"`). It is gitignored on
    purpose; do not commit one.

## 5. How to verify your work

From the app folder you touched (`apps/hse`, `apps/template`, `apps/famu`):

```bash
npm run check        # version agreement + byte-exact rebuild (+ branding
                     #   guard in template/famu) — run before every push
npm run build        # regenerate index.html on its own

# every module parses standalone:
for f in src/js/*.js; do
  node -e "new Function(require('fs').readFileSync(process.argv[1],'utf8'))" "$f" \
    || echo "PARSE FAIL: $f"; done

# the concatenated main script parses as the browser will run it:
node -e "const m=require('./src/manifest.json');const f=require('fs');" \
     -e "new Function(m.blocks['@@@JS_MAIN@@@'].map(x=>f.readFileSync(x,'utf8')).join(''))"
```

From the repo root, `npm run check:all` runs every app's check in sequence.

There is no automated browser test. A change to boot/auth/sync behavior is
**not verified** until someone opens the built `index.html` in a real browser:
guest mode, sign-in, rapid-tap scoring, the tablet breakpoints (768 px
portrait drawer, 1024 px+ desktop), light/dark mode. Say clearly in the PR
which of those were and were not done. The offline mode of template/famu has
a shim you can unit-test in Node (see that app's AGENTS.md) — reuse the
existing test approach rather than writing a new harness.

## 5a. The release playbook — shipping a version THIS way

Shipping touches files that must agree; do it in this order:

1. **Before writing code:** if anything about the request is ambiguous —
   branding, default behavior, whether a change should ship to all apps or
   one — **ask** (§2.2). One round of 2–4 questions costs a minute; a wrong
   guess costs a rewrite.
2. **Decide the version number now, not at the end** (patch/minor/major), and
   decide whether it applies to one app or several. Forks and the template
   version independently of HSE — parity is documented in MEMORY.md, not
   encoded in matching numbers.
3. **Make the change in `src/`, never the built file.** Rebuild with
   `npm run build` and commit `src/` + `index.html` together.
4. **Gate:** `npm run check` (and `check:all` at the root if several apps
   changed). A red guard means a leak — remove it, do not bypass it.
5. **Bump when ready to ship:** `npm run bump` (add `-- minor` / `-- major`
   when appropriate) from the app folder — it rewrites `VERSION`,
   `package.json`, and the rebuilt `index.html` in one step — then `npm run
   check` again.
6. **After merge (HSE app):** an admin publishes the build through the
   in-app Updates panel ("Publish"). That uploads the new `index.html` to
   Firebase (`releaseHtml`) and updates `appVersion`, which drives the update
   banner for local-file users. Publishing also records the current
   `DOWNLOAD_URL` — which is why rule 7 (keep it pointing at the real file
   path) matters.

## 6. Glossary (extend as needed)

* **byte-exact build** — `build.js` glues the `src/` modules into one
  `index.html`; rebuilding must reproduce the committed file byte for byte.
  `npm run check` enforces it.
* **marker** — a `@@@NAME@@@` token in `src/index.template.html` that the
  build replaces with the concatenated source files listed in
  `src/manifest.json`.
* **`src/manifest.json` vs `manifest.webmanifest`** — the first is the BUILD
  manifest (which sources glue where); the second is the PWA manifest (app
  name, icon, install behavior). Completely different things.
* **paint slots** — the `--hse-blue` / `--hse-red` / `--hse-white` CSS custom
  properties. Legacy names shared by all apps so modules port cleanly;
  `_paintColors()` writes them. Invisible to users.
* **offline mode** — how template/forks run while `firebaseConfig` is `null`:
  no sign-in gate, everything works, data persists to `localStorage` under
  `qb_local_db` via the local database shim. Nothing leaves the browser.
* **local database shim** — `createLocalDatabase()` in `04-firebase-init.js`
  (template/forks): a miniature Realtime Database implementing the exact
  Firebase API surface the app uses, backed by `localStorage`.
* **guard** — `guard.js` in template/forks: the branding firewall wired into
  `npm run check`. Fails on any HSE identifier and on an unmarked
  `firebaseConfig`.
* **fork-configured** — the `// fork-configured` marker comment appended to
  the `firebaseConfig` line when a fork connects its own Firebase project;
  it opts out of the null-config check while the identifier scans continue.
* **RTDB rules** — `firebase.database.rules.json` per app: server-side
  security rules for the Realtime Database (who may read/write what).
  Deployed via the Firebase console/CLI, not GitHub Pages.
* **`releaseHtml` / `appVersion`** — Firebase nodes where admins publish the
  built file and version metadata; local-file users download updates from
  there, falling back to `DOWNLOAD_URL` on GitHub raw.
* **THeard** — "toss-ups heard", the denominator of the app's normalized
  player metrics; increments on the first outcome of a toss-up.
* **Pages redirect** — the root `index.html` forwarding `…/HSEQB/` to
  `apps/hse/` so pre-restructure URLs, bookmarks, and installed PWAs keep
  working.
* **session branch** — the `arena/<id>-hseqb` branch each AI chat works on.
  Push only to it; PRs target `main`.
