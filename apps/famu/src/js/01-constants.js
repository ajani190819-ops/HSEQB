const VERSION = '1.0.0'; // auto-managed by bump.js
/* ═══════════════════════════════════════════════════════════════════════════
   FORK CONFIGURATION — everything an organization needs to own lives here.
   (Brand strings that live in src/index.template.html and
   manifest.webmanifest are listed in README.md → "Branding checklist".)
   ═══════════════════════════════════════════════════════════════════════════ */
// App identity — FAMU HCASC (Honda Campus All-Star Challenge) tracker.
// Shows up in release titles, admin prefill, and fallback text.
const APP_NAME = 'FAMU HCASC';
// Base name for downloaded files (…-all-sessions-<date>.json / .csv / .xlsx
// and the standalone <name>.html build download).
const APP_FILE_BASENAME = 'famu-hcasc';
// Password for the admin danger-zone "reset all data" action.
// '' disables the action entirely (recommended until you set your own).
const ADMIN_RESET_PASSWORD = 'HSE261781';
// Your own Firebase project config (see README → "Connect Firebase").
// null = OFFLINE MODE: the app is fully usable, data is stored in this
// browser only (localStorage), and nothing ever leaves the device.
const firebaseConfig = {
   // fork-configured
  apiKey: "AIzaSyBRCk1-fLM8GjxUzfCv-AZAOILJbdHnbCg",
  authDomain: "famu-hcasc.firebaseapp.com",
  databaseURL: "https://famu-hcasc-default-rtdb.firebaseio.com",
  projectId: "famu-hcasc",
  storageBucket: "famu-hcasc.firebasestorage.app",
  messagingSenderId: "123248966307",
  appId: "1:123248966307:web:09b316f1d3de1930691d16",
  measurementId: "G-ZZP27L6JSP"
};
// Your fork's GitHub repository (leave '' until you publish the fork).
// Drives the header version badge deploy status, update-download fallbacks,
// and issue/release links.
const GITHUB_REPO_URL     = ''; // e.g. 'https://github.com/your-org/your-repo'
const GITHUB_ISSUES_URL   = GITHUB_REPO_URL ? GITHUB_REPO_URL + '/issues'   : '';
const GITHUB_RELEASES_URL = GITHUB_REPO_URL ? GITHUB_REPO_URL + '/releases' : '';
// Raw URL of this app's deployable index.html — set it together with
// GITHUB_REPO_URL so local-file users can download updates.
const DOWNLOAD_URL = ''; // e.g. 'https://raw.githubusercontent.com/your-org/your-repo/main/index.html'
// Hostnames that serve the live deployed app. Visitors from these hosts are
// never nagged with local-file update banners. Add your GitHub Pages domain
// when you publish (the built-in HSEQB domain is intentionally absent).
const DEPLOY_HOSTNAMES = []; // e.g. ['your-org.github.io']
/* ═══════════════════════════════════════════════════════════════════════════ */
const DEFAULT_ACCENT = '#008344'; // FAMU green from the default palette
const DEFAULT_COLOR_THEME = 'famu';
// Named color themes. Each palette supplies a primary color, a gradient partner,
// and (where useful) a third decorative color. _paintColors can also route a
// separate accent color into outlines/highlights for the active appearance.
const COLOR_THEMES = [
  { id:'famu',    name:'FAMU',    sub:'Official', primary:'#008344', secondary:'#F4811F' },
  { id:'indigo',  name:'Indigo',  sub:'Classic',  primary:'#667eea', secondary:'#764ba2' },
  { id:'teal',    name:'Teal',    sub:'Fresh',    primary:'#11998e', secondary:'#38ef7d' },
  { id:'crimson', name:'Crimson', sub:'Bold',     primary:'#dc3545', secondary:'#8e1b26' },
  { id:'purple',  name:'Purple',  sub:'Deep',     primary:'#764ba2', secondary:'#3f2a63' },
  { id:'sunset',  name:'Sunset',  sub:'Warm',     primary:'#f39c12', secondary:'#e0533d' },
  { id:'slate',   name:'Slate',   sub:'Neutral',  primary:'#4a5568', secondary:'#2d3748' },
  { id:'forest',  name:'Forest',  sub:'Earthy',   primary:'#2f855a', secondary:'#1c4532' }
];
function getColorTheme(id){ return COLOR_THEMES.find(t => t.id === id) || null; }
// How the palette is expressed across the UI:
//  - 'stripes'  : the banner stays a clean primary-family gradient while the
//                 accent color is reserved for outlines/highlights and the
//                 pinstripe treatment moves onto cards and surfaces.
//  - 'gradient' : the classic primary -> gradient-partner two-color blend.
const ACCENT_STYLES = ['stripes', 'gradient'];
const DEFAULT_ACCENT_STYLE = 'stripes';
const DISPLAY_VERSION = VERSION; const INTERNAL_BUILD = VERSION;
const FILE_VERSION    = VERSION; const FILE_BUILD_ID  = VERSION;
var db, sessionsRef, globalPlayersRef, versionRef, releaseHtmlRef, releaseHistoryRef, globalSettingsRef, userIdentitiesRef, userProfilesRef, userProfileRef, adminListRef, adminUidsRef, adminList = [], adminUids = {};
const _adminToken = (()=>{
let _tok = null;
const _secret = Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
return{
grant() { _tok = _secret; },
revoke(){ _tok = null; },
check() { return _tok === _secret; },
};
})();
Object.defineProperty(window, 'isAdmin',{ get:() => _adminToken.check(), set:() =>{}, configurable:false });
function _noopRef(){
const noop = () => _noopRef();
const p = () => Promise.resolve({ val:() => null });
return{ on:noop, off:noop, once:p, set:p, update:p, remove:p, child:noop, push:() => ({ set:p }), transaction:p };
}
// True when no Firebase project is configured: the app then runs entirely
// from localStorage (see createLocalDatabase in 04-firebase-init.js).
const isOfflineMode = !firebaseConfig || !firebaseConfig.apiKey || !firebaseConfig.databaseURL;
let authUser = null; let authStarted = false; let appStarted = false;
const THEME_MODES = ['light', 'dark', 'device'];
let themeMode = 'device';
let colorTheme = DEFAULT_COLOR_THEME;
let accentStyle = DEFAULT_ACCENT_STYLE;
let customThemeColors = { primary:'#008344', secondary:'#F4811F', tertiary:'#ffffff', accent:'#F4811F' };
let _deviceThemeQuery = null;
let _profileSaveTimer = null;
let _profileLoadSequence = 0;
