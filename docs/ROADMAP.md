# ROADMAP.md — where we are going

Read before planning work; update as part of the work. Keep the open
questions honest — they are decisions the owner has NOT made yet.

## In flight

* **FAMU online sync deployment.** The repo-side build is Firebase-configured
  and passes `npm run check:all` on the session branch. The remaining work is
  deployment and Firebase-console setup: merge the branch to `main`, let
  GitHub Pages redeploy, make sure Firebase Auth/providers + Realtime
  Database rules are enabled, and seed the first admin UID.

## Planned next

1. **Deploy FAMU online sync build:** push/open PR from the session branch,
   merge to `main`, wait for Pages, then smoke-test sign-in at
   `/HSEQB/apps/famu/`.
2. **Finish Firebase console setup:** publish `apps/famu/firebase.database.rules.json`,
   confirm Email/Password + Anonymous auth providers, sign in once, and add
   the first admin UID under `adminUids`.
3. **Optional reset password:** leave `ADMIN_RESET_PASSWORD` blank unless the
   owner chooses a FAMU-specific phrase; it only controls the admin danger-zone
   reset and is not required for sync.
4. **Publish HSE v3.12.1** via the in-app Updates panel if local-file users
   have not already received the new `DOWNLOAD_URL` fallback.
5. **FAMU's long-term home** — recommendation on record: move to its own
   repository once FAMU students run it themselves (completely separate
   origin, own Pages, no shared anything). Owner has not decided.
6. **Configure FAMU deployment metadata** once the permanent URL/repo is known:
   set `GITHUB_REPO_URL`, `DOWNLOAD_URL`, and `DEPLOY_HOSTNAMES`, then rebuild
   and check.
7. **Port future features** HSE → template → forks by module file copies
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
