# AGENTS.md — read this before doing anything in this repo

This is the rulebook for any AI assistant (or human contributor) working here.
If you are an AI, everything in this file is an instruction from the repository
owner and it is **high priority**: it outranks your own defaults wherever the
two disagree.

**Start every session by reading `MEMORY.md`.** It is the handoff file: where
the work stands, what was already decided, what was tried and failed, and what
to do next. A new chat has no memory of the last one, so that file is the
memory — and you are expected to **update it before your session ends**
(`MEMORY.md` §9 is the checklist).

Companion documents, also mandatory when relevant:

* `MEMORY.md` — state of the work + session log. Read first, update last.
* `docs/ORCA-PLUGIN-FACTS.md` — hard-won facts about OrcaSlicer's plugin system.
  Do not re-derive them; do not contradict them.
* `docs/ROADMAP.md` — what is planned, what is in flight, and every open
  question. Read it before planning work; update it as part of the work.

The division of labour between the three: `MEMORY.md` is **where we are**,
`docs/ROADMAP.md` is **where we are going**, `docs/ORCA-PLUGIN-FACTS.md` is
**what is already known**. Keep them from contradicting each other.

---

## 1. Who you are working for

The owner of this repo is **a beginner** at both Python and 3D-printing
internals. That is a design constraint, not an apology:

* **Explain plainly.** Short sentences. Define every piece of jargon the first
  time it appears (there is a glossary at the bottom of this file — use and
  extend it). "The .bat reads plugins.json" beats "the installer consumes the
  manifest".
* **Never hide a failure.** If something did not work, or was not tested, say
  so in plain words. A honest "I could not test this because there is no
  Windows here" is worth more than a green checkmark.
* **Beginner-safe defaults.** Tools must never overwrite the user's input
  files, must say exactly what they did, and must refuse (with a plain-English
  fix) rather than produce broken output.

## 2. How to work — the standards

These are the owner's explicit expectations for how AI assistance goes:

1. **Write out what is about to happen, before it happens.** For any task that
   needs more than a couple of minutes of work: post the plan first — what you
   will do, in what order, what you will NOT do, and where the risks are. The
   owner should never watch a 15-minute silent build with no idea what is
   coming. Update `docs/ROADMAP.md` so the plan also lives in the repo.
2. **Ask instead of guessing.** Whenever a decision is user-facing, ambiguous,
   or a matter of taste, ask a clarifying question with concrete options and a
   recommended default — batch the questions so they can all be answered at
   once. Asking one round of good questions is efficient, not annoying.
3. **Work in small, reviewable steps.** One logical change at a time, verified
   before moving on. If a step turns out wrong, it should be cheap to throw
   away.
4. **Verify, then say what you verified.** Run the repo's tests (`python3
   tests/test_installer.py`) after touching the updater, the catalogue, or the
   .bat. After any file edit, confirm the edit actually landed — silent
   no-op edits happen. In your report, separate "verified" from "not tested".
5. **Report in three parts:** what I did / what it means for you / what is
   next. Keep it short enough to actually read.
6. **Be honest about uncertainty.** Label guesses as guesses. If the docs say
   something has never been tested on real hardware, keep saying so.
7. **Leave the next session a memory.** Before you finish, update `MEMORY.md`
   — state, decisions, answered questions, next actions, and a session-log
   entry (its §9 is the checklist). The owner should be able to open a brand
   new chat, point it at this repo, and have it pick up mid-stride.

## 3. Repo map

```
Orca-Plugins.bat            THE ONE FILE A USER DOWNLOADS, the whole updater
                            since 2.0.0, and the ONLY .bat in the repository
                            since 2.1.0: the menu, the build picker (main or
                            the five newest test branches), the OrcaSlicer
                            folder picker, the remembered choices, the
                            install engine and self-update all live in it.
                            It hands over to a newer copy of itself rather
                            than overwriting itself mid-run. The old
                            Update-Orca-Plugins.bat and
                            Choose-Orca-Plugin-Version.bat filenames were
                            removed at 2.1.0 at the owner's request; copies
                            on disk keep working (an old launcher
                            self-updates into this file), so do not
                            reintroduce them without the owner asking.
plugins.json                the catalogue the updater reads (what + where + version)
AGENTS.md                   this rulebook
MEMORY.md                   handoff: state of the work + session log. Read at the
                            start of a session, update at the end of it.
README.md                   human-facing front door / tour
docs/
  ORCA-PLUGIN-FACTS.md      OrcaSlicer plugin-system facts (do not re-derive)
  ROADMAP.md                what's planned and every open question
  reference/                supplied OrcaSlicer wiki/PDF reference snapshots
plugins/
  wave-overhangs/           OrcaSlicer pipeline plugin: support-free steep overhangs
  unlayered-infill/         OrcaSlicer pipeline plugin: non-planar interlocking infill
archive/                    NOT shipped: work kept for reference, with its own
                            README explaining why and how to revive it.
                            wave-overhangs-geometry/ lives here (archived 2026-10-02)
tools/
  nonplanar-infill-tool/    standalone double-click tool (the predecessor of the
                            unlayered-infill plugin; kept as reference, GPL-3.0)
  sync_engine.py            copy the shared engine between its two homes (--check)
  sync_changelog.py         push the newest release notes into the plugin files
keyboard-lighting/          unrelated personal project; DO NOT reorganize or "fix" it
tests/
  fake_orca.py              minimal stand-in for Orca's `orca` module
  fixtures/                 supplied STL and captured real G-code regression input
  test_installer.py         contract test: catalogue / .bat / files must agree
  test_post_script.py       functional test: the engine really rewrites G-code
  test_plugin_runtime.py    runtime test: the PLUGIN loads, runs and logs
  test_plugin_audit.py      imports all shipped plugins under Orca's audit hook
  test_wave_gcode.py        captured real-export Wave replacement regression
  test_unlayered_waves.py   Unlayered Infill wave shaping: pattern, angle,
                            shape, layer phase, Z ceiling, and that the
                            defaults still reproduce the previous release
  wave_cases.py             the synthetic Wave exports the Wave tests slice
```

The `plugins.json` entry `path` is a URL path into this repo (forward slashes,
relative to the repo root). The updater downloads
`https://raw.githubusercontent.com/ajani190819-ops/Tests/main/<path>`, so after
moving a plugin file you must update `path` in `plugins.json` **and** the
hardcoded fallback list inside the .bat — `tests/test_installer.py` fails if
you forget, and it is the safety net for exactly this.

## 4. Hard rules — breaking these breaks real users

1. **The repo must stay public.** The updater makes unauthenticated
   raw.githubusercontent.com downloads; a private repo 404s every file.
2. **`Orca-Plugins.bat` must stay CRLF.** All lines, byte-exact.
   `*.bat -text` in `.gitattributes` keeps git from re-normalizing it. Never
   edit it with tools that convert line endings (Python `Path.write_text`
   does — use binary mode). After editing, assert the CRLF count. It is the
   only .bat in the repository; `tests/test_installer.py` fails if a second
   top-level .bat appears.
3. **Version bumps take edits in lockstep.** Update the plugin's PEP 723
   `# version = "..."` header, its module-level `PLUGIN_VERSION`, the catalogue
   entry, and the .bat fallback row. For Unlayered Infill also update
   `TOOL_VERSION` and the standalone engine marker, then run
   `python3 tools/sync_engine.py` so both engine copies move together. The
   tests enforce every version surface, including exported G-code stamps.
   **Never change the PEP 723 `name` casually.** The Plugin Development PDF
   says Orca saves `plugin_name` inside preset/config identities. Both package
   and capability names are permanently version-free: `Wave Overhangs` and
   `Unlayered Infill`. Release numbers belong only in explicit version fields,
   logs, Check setup, changelogs, tools and G-code stamps. The updater writes
   that stable package name to its sidecar; it does not append the release
   number to the identity. `tests/test_installer.py` enforces this — run it.
   **Every bump also needs a changelog entry.** Add a `## <version> — <date>`
   section at the top of `plugins/<id>/CHANGELOG.md` describing what the owner
   will notice, add a dated entry to the root `CHANGELOG.md`, then run
   `python3 tools/sync_changelog.py`. The generator copies the newest three
   plugin releases into `CHANGELOG_RECENT` and refreshes the PEP 723 description.
   `tests/test_installer.py` fails if the newest entry does not match the file.
   **The version must never go into a capability name** — a process preset
   stores that name as its value, so renaming it orphans the preset. See
   `docs/ORCA-PLUGIN-FACTS.md`.
4. **No `|`, `^`, `%`, `!` in any catalogue field** — they corrupt the .bat's
   pipe-delimited plan or cmd.exe parsing.
5. **Exactly two capabilities per plugin** in the catalogue — the .bat's plan
   has two capability slots.
6. **Never delete or rewrite `keyboard-lighting/`** — it is here for storage,
   not review.
7. **GPL-3.0 attribution must survive.** `unlayered-infill` and
   `tools/nonplanar-infill-tool` derive from Roman Tenger's NonPlanarInfill
   (GPL-3.0). Keep the copyright headers; keep the licence when distributing.
8. **Git discipline:** all work happens on **the session branch you were
   handed** (`arena/<id>-tests` — it is a different one every chat; session 1
   was `arena/01a0f42b-tests`). Push only to that branch, open PRs only from
   it, never commit straight to `main`, never force-push, never commit
   credentials or generated junk. Don't trust a branch name hardcoded in a
   doc — the current branch is whatever this session was given.
9. **Orca plugin facts live in `docs/ORCA-PLUGIN-FACTS.md`** and they are
   binding: e.g. import third-party deps at module load (never inside a
   capability), never read `post_process_plugin` from config, G-code
   transforms must be idempotent because the export step can run twice.
10. **The shared engine exists twice, verbatim.** `nonplanar_core` lives as
    plain source between the `BEGIN/END nonplanar_core` markers in
    `plugins/unlayered-infill/unlayered_infill_post.py` (**edit this one**) and
    as an escaped string literal in `unlayered_infill_orca.py`. After editing,
    run `python3 tools/sync_engine.py` to push it across;
    `tests/test_post_script.py` fails if they drift. Two front ends, one
    engine; that is the whole point of decision C1.
11. **Logging must never be able to break a print.** Every `_log()` call is
    wrapped so that a full disk, a read-only folder or a missing Downloads
    directory can only lose the log line, never fail the export. The log goes
    to `<Downloads>/orca-plugins.log` because the owner has to be able to find
    it; all plugins share the one file. Keep the step trace bounded (log each
    pipeline step once) or it will fill their Downloads folder.
12. **Never make the .bat overwrite itself while it runs.** `cmd.exe` streams
    a batch file from disk by byte offset as it executes, so a self-overwrite
    can jump into garbage mid-run, and a bad download would leave the owner
    with no working updater. `:self_update` downloads the new copy to `%TEMP%`,
    verifies it, and hands over to it; the file on disk is never touched.
    `tests/test_installer.py` enforces this.
13. **Never touch the filesystem at plugin import time.** Module level does
    metadata, constants and `import` statements — nothing else. No log line,
    no state file, no `open()`, no `print()`. OrcaSlicer installs a CPython
    audit hook *before* it imports any plugin, and a write during import has
    no plugin identity attached: it can throw a permission prompt in the
    owner's face mid-install, or fail the load outright. A failed load is
    invisible except in the Plugins dialog's **Diagnostics** tab, so it looks
    to the owner like "it won't install". Log lazily instead — a
    `_LOADED_LOGGED` flag plus `_log_loaded_once()` as the first statement of
    every capability's `execute()`. v0.3.0 / v0.0.5 shipped this bug;
    `tests/test_plugin_audit.py` is the regression guard and imports each
    plugin under a hook that denies every write.
14. **One entry file per plugin folder.** Orca picks a plugin's entry point by
    scanning its folder for a single `.py` (or `.whl`). A second `.py` beside
    it makes the entry ambiguous. This is why the standalone tools stage to
    `Downloads\OrcaPlugins\tools\` (`%TOOLDIR%`) and never beside the plugin
    copies.

## 5. How to verify your work

```bash
python3 tests/test_installer.py        # catalogue / .bat / files agree
python3 tests/test_post_script.py      # the engine really rewrites G-code
python3 tests/test_plugin_runtime.py   # the plugin loads, runs, and logs
python3 tests/test_plugin_audit.py     # it imports under Orca's audit hook
python3 tests/test_unlayered_waves.py  # Unlayered Infill wave shaping
python3 tests/test_wave_gcode.py       # captured export; needs numpy + shapely
                                      # -- it SKIPS without them. A skip is not
                                      # a pass; install them before claiming it.
python3 tools/sync_engine.py --check   # the two engine copies are identical
python3 tools/sync_changelog.py --check  # changelogs match the plugins
python3 tools/dump_default_config.py --check  # docs/config-reference is current
python3 tools/check_all.py            # ALL of the above, both dependency states
git ls-files --eol Orca-Plugins.bat   # must say i/crlf; it is the only .bat
```

The .bat itself is Windows-only and cannot be executed in this sandbox. When
you change it: keep it one logical change at a time, re-read the whole file
afterwards, and simulate the pieces you can (the repo test already simulates
the `for /f` tokenization the .bat performs — extend it rather than trusting
your eyes).

Anything touching real slicing behaviour is verified against a fake harness at
best. Say so in the PR. The first real slice on real OrcaSlicer is the real
test; `data_dir()/log/python_*.log` holds the traceback if it fails.

## 5a. The release playbook — do a version bump THIS way

Shipping a change touches ten files that must agree, and discovering the
disagreement one failing test at a time is what makes a small change take an
hour. Do it in this order, in as few tool calls as possible.

**Before writing code**
1. If anything about the request is ambiguous -- how aggressive a default
   should be, which plugin first, whether a behaviour change is wanted --
   **ask**. One round of 2-4 questions costs a minute. Guessing wrong costs a
   rewrite, and the owner has said plainly that they want to be asked.
2. Decide the version numbers now, not at the end.

**Environment, once per session**
```bash
pip install --break-system-packages -q shapely numpy   # test_wave_gcode needs these
mkdir -p /tmp/nodeps && printf 'raise ImportError("blocked")\n' > /tmp/nodeps/numpy.py \
  && cp /tmp/nodeps/numpy.py /tmp/nodeps/shapely.py    # for the deps-absent path
```
The sandbox can be reset between turns and lose both. If a geometry test
suddenly reports `'NoneType' object has no attribute 'geometry'`, shapely is
gone -- reinstall, do not debug the plugin.

**The bump itself**: one script, not ten edits. `tools/bump_version.py NAME
VERSION` does every file below and refuses to half-finish:

| file | what must change |
| --- | --- |
| `plugins/<p>/<p>_orca.py` | PEP 723 `# version`, `PLUGIN_VERSION` |
| `plugins/<p>/<p>_post.py` | `TOOL_VERSION`, `MARKER_VERSION` (Unlayered only) |
| `plugins.json` | the catalogue entry |
| `Orca-Plugins.bat` | the `^|`-joined fallback line |
| `plugins/<p>/CHANGELOG.md` | a new entry, bullets FIRST |
| `CHANGELOG.md` | one dated entry covering the release |

**Then, in one command:**
```bash
python3 tools/sync_engine.py && python3 tools/sync_changelog.py \
  && python3 tools/dump_default_config.py && python3 tools/check_all.py
```
`tools/check_all.py` runs every test in both dependency states and prints one
line per check. Use it instead of running six test files by hand.

**Traps that have cost real time here, all now avoidable**
* **Never write `Orca-Plugins.bat` with Python text mode.** `write_text`
  converts CRLF to LF and the installer test fails with five errors at once.
  Use `read_bytes`/`write_bytes`, or `sed -i` on a line number.
* **`tools/sync_changelog.py` rewrites the PEP 723 `description`** from the
  FIRST bullet of the new changelog entry. Write that bullet as a one-line
  summary and the description comes out right with no hand-editing.
* **Changelog entries must lead with `*` bullets**, prose after. The
  generator reads the bullets.
* **Test files are standalone scripts.** `python3 tests/test_x.py`. Never
  pytest -- it dies with INTERNALERROR because they `sys.exit` at module
  scope.
* **A pinned geometry count in `test_wave_gcode.py` is measuring geometry,
  not defaults.** If you change a default, run the fixture against the
  explicit `LEGACY` config and give the new behaviour its own assertions;
  do not just edit the pinned number.
* **One edit, one verification.** Batch independent edits into a single
  patch script and verify once, rather than edit-test-edit-test.

## 6. Glossary (extend as needed)

* **catalogue** — `plugins.json`: the list of plugins the updater can install.
* **updater** — `Orca-Plugins.bat`. Double-clickable Windows script; menu,
  build picker, folder picker and install engine in one file since 2.0.0,
  and the only .bat in the repository since 2.1.0 (the old chooser/updater
  filenames were removed then; copies already on disk keep working).
* **PEP 723 header** — the `# /// script` comment block at the top of a
  plugin file; carries the plugin's name/version/dependencies.
* **sidecar** — Orca's `.install_state.json` next to a plugin; says it is
  installed, enabled, and which capabilities are on. The updater writes it so
  plugins appear already enabled.
* **pipeline plugin** — an OrcaSlicer plugin that hooks into slicing steps
  (e.g. `posSlice`, `psGCodePostProcess`). Needs Orca newer than 2.4.2 or a
  nightly.
* **post-processing script** — a plain script run on the finished G-code,
  either by hand or via Orca's *Post-processing scripts* setting. Works on any
  Orca version; this is what `tools/nonplanar-infill-tool` is.
* **CRLF** — Windows line endings (`\r\n`). The .bat needs them.
* **raw.githubusercontent.com** — GitHub's "give me this file as-is" URL
  service; how the updater downloads.
* **GPL-3.0** — a copyleft licence; derived code must keep attribution and the
  same licence.
