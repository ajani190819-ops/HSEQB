# ROADMAP.md — where we are going

Read before planning work; update as part of the work. Keep the open
questions honest — they are decisions the owner has NOT made yet.

## In flight

* **PR #18 — the monorepo restructure.** HSE → `apps/hse/` (v3.12.1) with a
  root redirect, plus `apps/template/` and `apps/famu/` (FAMU HCASC).
  Awaiting owner review/merge. On merge, GitHub Pages redeploys: root starts
  redirecting to `apps/hse/`, and `/apps/template/` + `/apps/famu/` become
  publicly reachable (they double as live offline demos).

## Planned next

1. **Publish HSE v3.12.1** via the in-app Updates panel right after the
   merge, so local-file users pick up the new `DOWNLOAD_URL` fallback.
2. **FAMU Firebase connection** (owner-triggered, when cross-device sync is
   wanted): create a free Firebase project, enable Email/Password +
   Anonymous auth, create the Realtime Database with the rules from
   `apps/famu/firebase.database.rules.json`, paste the config with the
   `// fork-configured` marker, seed the owner's UID in `adminUids`, set
   `ADMIN_RESET_PASSWORD`. Full steps in `apps/famu/README.md`.
3. **FAMU's long-term home** — recommendation on record: move to its own
   repository once FAMU students run it themselves (completely separate
   origin, own Pages, no shared anything). Owner has not decided.
4. **Port future features** HSE → template → forks by module file copies
   (the shared paint-slot names and identical module structure exist exactly
   for this). After any port: rebuild + check + guard in every touched app.

## Open questions (ask, don't assume)

* **HSE rules hardening.** Today any signed-in user can read/write
  `sessions`/`globalPlayers` (rules say `auth != null`), and anonymous
  sign-up is enabled. Tightening options: email-domain allowlist, disable
  anonymous auth, or per-node admin-only writes. Tradeoff: every option adds
  friction for new legit team members. Owner is aware; no decision yet.
* **FAMU theming extras.** Possible second official palette with orange as
  the structural color and green as accent (one-line theme entry + palette
  recompute). Not requested yet.
* **More forks.** Process is proven (template copy → brand → guard → deploy).
  When another school asks, decide per-fork: folder in this monorepo vs own
  repo. Default answer per MEMORY.md: own repo for real deployments.
* **Icon refinement.** FAMU/template icons are AI-generated monograms; the
  owner may want custom artwork later. Regenerating is cheap (keep 512×512).

## Not planned / won't do

* Renaming the `--hse-*` CSS paint slots in template/forks — they are the
  shared portability layer; renaming would break module ports from HSE.
* "Fixing" HSE's slightly-stale pre-boot palette CSS — invisible at runtime,
  and touching it risks the byte-stability promise for zero user benefit.
* Renaming localStorage keys to namespace the apps — existing HSE users'
  preferences depend on the current keys; same-origin cosmetic sharing is
  benign and has fallbacks.
* Any automated browser test harness — the invariants are mechanical
  (check/parse/guard) and manual smoke-testing is documented per app. Revisit
  only if regressions slip through.
