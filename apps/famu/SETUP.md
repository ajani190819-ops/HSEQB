# FAMU HCASC — setup & usage guide

Two ways to run the app. **Nothing below Part A is required to start using
it.**

- **Part A — Use it today (zero setup):** runs offline, data stays in the
  browser you use.
- **Part B — Turn on sync (one-time, ~15 min):** connect FAMU's own free
  Firebase project so accounts and sessions sync across everyone's devices.

---

## Part A — Using it right now (offline mode)

1. **Open the app.** After PR #18 merges it lives at
   `https://ajani190819-ops.github.io/HSEQB/apps/famu/`. Until then, use the
   repo preview or open `apps/famu/index.html` directly — it works the same.
2. **Create a session** (left sidebar → Session → name it → **+ New
   Session**). A session is one practice or match.
3. **Add players** (Players → type a name → Add Player, or import a CSV/TXT
   roster). Rename typos with **Rename**; combine duplicates with **Merge**.
4. **Make teams** (Teams → Team Name → Add Team → click players to assign).
5. **Record answers** in the main area — each player has a row of buttons:
   **Power +15 · Toss-up +10 · Neg −5 · Miss 0 · Bonus +10/team**. Pick the
   category when asked. Keyboard shortcuts exist (see the Help "?" button).
6. **See stats** — flip the **Tracker / Stats** toggle in the header:
   leaderboard, per-player detail, team compositions, charts.
7. **Export** (Export / Import → Excel, JSON, or CSV) — **do this regularly
   in offline mode**: the data lives in this one browser, and clearing
   browser data erases it. An export file is your backup and can be
   re-imported anywhere.
8. **Install it as an app** on iPad/phone: Share → **Add to Home Screen**.
   It runs full-screen like a native app.
9. **Make it yours:** Visual Settings → 8 color themes (FAMU orange & green
   is the default), light/dark mode, accent style.

> While in offline mode the header says **"Saved locally"** — that is the
> reminder that nothing has left the browser and no account is needed.

---

## Part B — Turn on sync (connect Firebase, free)

Do this once, when you want everyone's devices to share the same data.

### B1. Create the project (free)

1. Go to <https://console.firebase.google.com> and sign in with a Google
   account.
2. Click **Add project** (or "Create project").
3. Name it `FAMU HCASC` (any name works). Disable Google Analytics when
   asked. Click **Create project**.
   You are on the free **Spark** plan automatically — nothing here costs
   money (1 GB storage / 10 GB-month downloads / 100 simultaneous
   connections; a season of quiz bowl data is a tiny fraction of that).

### B2. Turn on sign-in

1. Left menu → **Build → Authentication → Get started**.
2. Tab **Sign-in method**:
   - **Email/Password** → Enable → Save.
   - **Anonymous** → Enable → Save (this powers "Continue as guest").

### B3. Create the database + paste the security rules

1. Left menu → **Build → Realtime Database → Create Database**.
2. Choose a location (e.g. `us-central1`) and start in **locked mode**.
3. Open the **Rules** tab, delete what is there, and paste the entire
   contents of this repo's `apps/famu/firebase.database.rules.json`, then
   click **Publish**.
   (Plainly: the rules are the security guard — only signed-in users can
   read/write data, and only admins can publish app updates.)

### B4. Get your config

1. **Project Overview → ⚙ (gear) → Project settings → General** tab.
2. Scroll to **"Your apps"** → click the **`</>`** (web) icon.
3. Nickname `FAMU HCASC` → **Register app** (leave hosting unchecked).
4. Copy the whole `firebaseConfig = { … }` block shown.

### B5. Wire it into the app

Ask your AI assistant to do this (paste them the config — it is safe to
share; it is public in the deployed page anyway, and the rules from B3 are
what actually protect data), or do it yourself:

1. Open `apps/famu/src/js/01-constants.js`.
2. Replace `const firebaseConfig = null;` with your pasted config and append
   the marker comment, e.g.:
   ```js
   const firebaseConfig = { apiKey:"…", authDomain:"…", databaseURL:"…", projectId:"…", storageBucket:"…", messagingSenderId:"…", appId:"…" }; // fork-configured
   ```
3. In the same file, set an admin reset password:
   `const ADMIN_RESET_PASSWORD = 'choose-something-private';`
   (This unlocks the danger-zone "reset all data" button.)
4. Rebuild and verify:
   ```sh
   cd apps/famu
   npm run build
   npm run check     # must end with the green guard line
   ```
5. Commit `src/js/01-constants.js` + `index.html` together and push. The
   sign-in gate now appears in the app.

### B6. Make yourself admin (one-time)

1. Open the app → **Create account** with your email → sign in.
2. Sidebar → **Settings → User ID** → copy the long **UID** shown.
3. Firebase console → **Realtime Database → Data** tab → click `+` at the
   root → key `adminUids` → under it, key *your UID* with value `true` →
   **Publish**.
4. Reload the app — the **Admin Panel** (category colors & frequencies) and
   release publishing are now unlocked for you. Add teammates' UIDs the
   same way to make them admins.

### B7. Optional — GitHub links (deploy badge + update downloads)

Still in `01-constants.js`, when FAMU's copy moves to its own repository:
set `GITHUB_REPO_URL`, `DOWNLOAD_URL`, and add the hosting domain to
`DEPLOY_HOSTNAMES` (e.g. `['your-famu-repo.github.io']`), rebuild, commit.

---

## Everyday flow after setup

- Teammates open the app → **Create account** (or Continue as guest) →
  everyone sees the same sessions and stats instantly.
- Score a match → press the buttons; data autosaves and syncs (~every 5 s
  and on every answer).
- End of practice → **Export to Excel** for records.
- New app version? An admin publishes it in-app via the **Updates** panel
  (`↻` in the header); local-file users get an update banner automatically.

## Troubleshooting quick hits

- **"Permission denied" errors** → you skipped B2 (auth) or B3 (rules), or
  the config's `databaseURL` points at the wrong project.
- **Sign-in gate missing / says offline** → the `firebaseConfig` line is
  missing the `// fork-configured` marker or the app wasn't rebuilt
  (`npm run build`) after editing.
- **Guard fails on commit** → an HSE identifier leaked in; read the guard's
  message, remove what it names, rebuild.
- **Data disappeared** → you were in offline mode in a different browser, or
  browser data was cleared. Re-import your latest export.
