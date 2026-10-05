# MEMORY.md — where the work stands

The handoff file. Read it at the start of a session; **update it before your
session ends** (checklist at the bottom). Keep entries short and factual.

## What this repo is

The HSEQB monorepo: a family of single-file quiz bowl tracker apps.
`apps/hse/` is the live production app for the HSE team (Firebase-connected).
`apps/template/` is the white-label fork base (offline, credential-free,
guard-enforced). New schools/organizations fork from the template —
`apps/famu/` (FAMU HCASC) is the first.

## Current state (2026-10-05)

* The monorepo restructure is present on `origin/main` / current branch:
  root redirects to `apps/hse/`, with `apps/template/` and `apps/famu/`
  included. `gh pr list --head arena/01a10c0b-hseqb --base main --state all`
  returned no PRs for the current session branch.
* `npm run check:all` passes after the FAMU sync build fix.
* FAMU HCASC is Firebase-configured in source and built artifact on this
  branch: `apps/famu/src/js/01-constants.js` and `apps/famu/index.html` both
  contain the FAMU Firebase config with the sanctioned `// fork-configured`
  marker. `ADMIN_RESET_PASSWORD` is blank, so the danger-zone reset remains
  disabled until the owner chooses a FAMU-specific value.
* The public GitHub Pages URL may still serve the previous offline build until
  this branch is merged to `main` and Pages redeploys.
* Official FAMU colors remain green `#008344` (structural) + orange
  `#F4811F` (accent), default theme id `famu`. Template default theme remains
  Indigo (`#667eea`/`#764ba2`).
* If GitHub Pages is enabled from `main`, the intended monorepo URL for FAMU
  is `https://ajani190819-ops.github.io/HSEQB/apps/famu/`; for production,
  the recommended long-term option is still a separate FAMU-owned repo.

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

* **2026-10-05 (session 4 — FAMU setup audit):** repo check only. Fetched latest `origin/main` and fast-forwarded the session branch. No PR
  exists for the session branch. Verified HSE and template checks pass. FAMU
  check failed because the built `index.html` was stale versus configured
  Firebase source; the check command temporarily rebuilt `apps/famu/index.html`
  and it was reverted before doc updates.
* **2026-10-05 (session 5 — FAMU online sync build):** finished the repo-side
  Firebase sync build for FAMU: moved the `// fork-configured` marker onto the
  actual `const firebaseConfig = …` line, rebuilt `apps/famu/index.html`, and
  blanked `ADMIN_RESET_PASSWORD` rather than publishing an HSE-looking reset
  phrase. Verified with `npm run check:all` (HSE, template, FAMU all green).

## Next actions

1. Merge/deploy the FAMU sync build: push/open PR from the session branch,
   merge to `main`, then wait for GitHub Pages to redeploy
   `https://ajani190819-ops.github.io/HSEQB/apps/famu/`.
2. In Firebase, ensure Email/Password + Anonymous auth are enabled, publish
   `apps/famu/firebase.database.rules.json`, create/sign into the first FAMU
   account, then seed `adminUids/<uid> = true`.
3. Optional: choose a FAMU-specific `ADMIN_RESET_PASSWORD` if the admin
   danger-zone reset should be enabled; rebuild/check after setting it.
4. Configure FAMU deployment metadata once its permanent URL/repo is chosen:
   `GITHUB_REPO_URL`, `DOWNLOAD_URL`, and `DEPLOY_HOSTNAMES` in
   `apps/famu/src/js/01-constants.js`, then rebuild/check.
5. If HSE v3.12.1 has not yet been announced to local-file users, an admin
   should publish it through the in-app Updates panel.
6. Decide FAMU's long-term home: stay at `apps/famu/` or move to its own
   repository (recommended once FAMU students run it themselves).
7. Optional hardening (owner aware, not decided): HSE/FAMU Firebase rules
   allow any signed-in user to read/write shared data; an email-domain
   allowlist or disabled anonymous auth would tighten that. Tradeoff: new
   legit users must be pre-approved.

## Before you finish a session (checklist)

- [ ] `npm run check` (or `check:all`) green in every app you touched?
- [ ] Built `index.html` committed together with the `src/` changes?
- [ ] PR description states what was verified vs. not tested in a browser?
- [ ] `docs/ROADMAP.md` updated (plans + open questions)?
- [ ] This file updated (state, decisions, session log, next actions)?
