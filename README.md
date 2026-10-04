# HSEQB monorepo

This repository hosts the **Quiz Bowl Tracker** family of single-file web apps
for running live quiz-bowl sessions: real-time scoring, player/team
management, a session library, and cross-session analytics.

## Repository layout

| Path | What it is |
| --- | --- |
| [`apps/hse/`](apps/hse/) | **HSE Quiz Bowl Tracker** — the original HSE-branded app, synced to the HSE team's Firebase project. Deployed at `…/HSEQB/apps/hse/` (the repo root redirects there so legacy links keep working). |
| [`apps/template/`](apps/template/) | **QB Tracker template** — the white-label base for new forks. Identical feature set, standard themes, no HSE branding, no Firebase credentials. Runs fully offline out of the box; plug in your own Firebase project to enable sync. |
| [`apps/famu/`](apps/famu/) | **FAMU HCASC** — the Florida A&M University Honda Campus All-Star Challenge tracker, the first fork built from the template. FAMU orange & green default theme; runs in offline mode until FAMU's own Firebase project is connected. |
| `index.html` (root) | Redirect to `apps/hse/` — keeps the original GitHub Pages URL, bookmarks, and installed PWAs working. |
| `.vscode/` | Shared editor config for the repo. |

Each app folder is **self-contained**: its own `src/`, its own
`package.json`, its own build/version scripts. Run commands from inside the
app folder you are working on:

```sh
cd apps/hse       # or: cd apps/template
npm run build     # regenerate index.html byte-for-byte from src/
npm run check     # version + byte-exact rebuild gate (run before pushing)
npm run bump      # patch/minor/major version bump + rebuild
```

## Creating a fork for another school or organization

Start from `apps/template/` — see its [README](apps/template/README.md) for
the full checklist. (Working example: [`apps/famu/`](apps/famu/README.md).) (branding, themes, Firebase setup, rules, deployment).
The template intentionally ships **without any Firebase credentials**, so a
fork cannot touch the HSE team's data: each fork connects to its own
Firebase project.

`apps/template` also has a branding guard (`node guard.js`, part of
`npm run check`) that fails the build if any HSE identifier — names, repo
URLs, or API keys — ever leaks into the template.

## Working on this repo (humans and AI assistants)

- [`AGENTS.md`](AGENTS.md) — the rulebook: hard rules, verification commands,
  and the release playbook. Read it before changing anything.
- [`MEMORY.md`](MEMORY.md) — where the work stands + session log.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — what's planned and every open question.

## Data protection

- The HSE app's Firebase configuration only ever lives in `apps/hse/`.
- The template and every fork use their own Firebase projects; the template
  defaults to an offline, browser-local mode until configured.
- Realtime Database security rules for the HSE project live in
  `apps/hse/firebase.database.rules.json` (auth-required reads/writes).
