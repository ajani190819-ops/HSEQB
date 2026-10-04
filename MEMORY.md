# MEMORY.md — where the work stands

The handoff file. Read it at the start of a session; **update it before your
session ends** (checklist at the bottom). Keep entries short and factual.

## What this repo is

The HSEQB monorepo: a family of single-file quiz bowl tracker apps.
`apps/hse/` is the live production app for the HSE team (Firebase-connected).
`apps/template/` is the white-label fork base (offline, credential-free,
guard-enforced). New schools/organizations fork from the template —
`apps/famu/` (FAMU HCASC) is the first.

## Current state (2026-10-03)

* **PR #18 is open** from the session branch, containing the whole
  restructure: HSE moved to `apps/hse/` (v3.12.1, download URL updated),
  root redirect added, `apps/template/` (v1.0.0) and `apps/famu/`
  (v1.0.0, FAMU HCASC) created. All checks green in all three apps.
  **Not yet merged. `main` still has the old single-app layout.**
* HSE app is byte-identical to `main` except: `01-constants.js` (version +
  `DOWNLOAD_URL`), `package.json`, rebuilt `index.html`, an AGENTS.md note.
* FAMU HCASC runs in **offline mode** — no Firebase project connected yet.
  Official FAMU colors: green `#008344` (structural) + orange `#F4811F`
  (accent), default theme id `famu`.
* Template default theme: Indigo (`#667eea`/`#764ba2`).
* Live site (until merge): `https://ajani190819-ops.github.io/HSEQB/` serves
  the old root app from `main`. After merge: root redirects to
  `apps/hse/`, and `/apps/template/` + `/apps/famu/` become reachable.

## Decisions already made (do not relitigate without the owner)

* Monorepo layout `apps/<org>/` with a root redirect page (owner chose this
  over keeping HSE at root or a flat layout).
* Forks are created from `apps/template/`, never from `apps/hse/`.
* Template ships `firebaseConfig = null` → offline mode via the localStorage
  shim (`createLocalDatabase()`), 21/21 unit checks passed.
* Branding guard (`guard.js`) runs as part of `npm run check` in
  template/famu; `// fork-configured` is the only opt-out for a real config.
* Pre-boot CSS palette values must be computed with the real `_paintColors`
  helpers — never eyeballed.
* Template default theme: Indigo; app name "QB Tracker"; FAMU app named
  **FAMU HCASC** (official abbreviation; it was briefly "FAMU HASC" before
  the owner corrected it).
* Versioning: each app versions independently (HSE 3.12.x lineage; template
  and forks start at 1.0.0). Parity is noted here: template v1.0.0 ==
  FAMU v1.0.0 == HSE v3.12.x feature set.
* FAMU runs offline until the owner connects FAMU's own Firebase project
  (free tier is plenty — see roadmap).

## Things that are known-and-intentional (do not "fix")

* `--hse-blue` / `--hse-red` / `--hse-white` CSS names exist in ALL apps:
  shared paint slots for module portability. The guard whitelists them.
* HSE's committed pre-boot palette CSS (`core.css`) is slightly stale
  relative to the current `_paintColors` helpers (produced by an older
  helper version). Invisible in practice (theme-init overwrites pre-boot).
  Left byte-stable on purpose; template/famu use fresh computed values.
* `renamePlayer` defined twice, literal `</style>` inside a template literal
  in `20-analytics-charts.js`, `local-settings.js` untracked: all
  intentional. See each app's AGENTS.md gotchas.
* Apps on the same origin share cosmetic localStorage (theme, display name);
  benign, fallbacks exist. Do not rename keys.

## Tools & environment notes

* `gh pr edit <n> --body` silently fails with exit 1 in this sandbox (GraphQL
  quirk); use the REST API instead:
  `gh api repos/ajani190819-ops/HSEQB/pulls/<n> --method PATCH -F body=@file.md`.
* The platform snapshot may reset local git history between sessions while
  keeping working files. If commits are missing locally, `git fetch origin
  arena/<id>-hseqb` and `git reset --hard` to the remote tip after diffing.
* Direct network egress (curl) to firebaseio.com is blocked in the sandbox;
  use the page-fetch tool to probe Firebase REST URLs (e.g. to confirm
  "Permission denied" from the rules).
* ImageMagick `convert` is available for icon resizing; generate icons at
  any square size then resize to 512×512.
* `file` command is absent; read PNG dims via
  `node -e "const b=require('fs').readFileSync(p); b.readUInt32BE(16)+'x'+b.readUInt32BE(20)"`.

## Session log

* **2026-10-03 (session 1 — restructure):** moved HSE to `apps/hse/` with
  `git mv` (history preserved), added root redirect, created `apps/template/`
  (debrand, 7 standard themes, Indigo default, offline shim, guard, docs,
  icon). HSE bumped 3.12.0 → 3.12.1 for the `DOWNLOAD_URL` change. PR #18
  opened. Verified: byte-exact builds, 21/21 shim tests, parse checks, local
  serving, HSE content diff vs main.
* **2026-10-03 (session 2 — verification):** proved Firebase compatibility:
  config/nodes/rules/auth modules byte-identical to main; live RTDB probe
  returns "Permission denied" unauthenticated (rules active). Demonstrated
  fork isolation both ways (own-config fork passes guard; HSE config pasted
  into a fork FAILS the guard). Local git had been reset by the platform;
  re-synced from the pushed branch.
* **2026-10-03 (session 3 — FAMU + rulebook):** created `apps/famu/` from the
  template: FAMU colors (green `#008344` / orange `#F4811F`), FAMU theme as
  default, offline mode, guard retargeted, icon, docs; registered in root
  README/package/launch configs. Renamed **HASC → HCASC** (official
  abbreviation, Honda Campus All-Star Challenge) everywhere including a new
  icon. Adapted the owner's uploaded rulebook (from the Orca plugins repo)
  into this root `AGENTS.md`, and created `MEMORY.md` + `docs/ROADMAP.md`.
  Firebase free-tier question answered: a second (free) project is only
  needed when FAMU wants cross-device sync.

## Next actions

1. Owner reviews and merges **PR #18** (Pages redeploys on merge; root starts
   redirecting).
2. After merge: an admin publishes the **v3.12.1** build via the in-app
   Updates panel so local-file HSE users get the new download URL.
3. FAMU: connect its own Firebase project when cross-device sync is wanted
   (README in `apps/famu/` has the steps; `// fork-configured` marker).
4. Decide FAMU's long-term home: stay at `apps/famu/` or move to its own
   repository (recommended once FAMU students run it themselves).
5. Optional hardening (owner aware, not decided): HSE Firebase rules allow
   any signed-in user to read/write `sessions`; an email-domain allowlist or
   disabled anonymous auth would tighten that. Tradeoff: new legit users
   must be pre-approved.

## Before you finish a session (checklist)

- [ ] `npm run check` (or `check:all`) green in every app you touched?
- [ ] Built `index.html` committed together with the `src/` changes?
- [ ] PR description states what was verified vs. not tested in a browser?
- [ ] `docs/ROADMAP.md` updated (plans + open questions)?
- [ ] This file updated (state, decisions, session log, next actions)?
