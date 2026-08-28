const VERSION = '3.12.0'; // auto-managed by bump.js
const DOWNLOAD_URL = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/main/index.html';
const DEFAULT_ACCENT = '#0b41a8'; // Royal blue from the default HSE palette
const DEFAULT_COLOR_THEME = 'royal';
// Named color themes. Each palette supplies a primary color, a gradient partner,
// and (where useful) a third decorative color. _paintColors can also route a
// separate accent color into outlines/highlights for the active appearance.
const COLOR_THEMES = [
  { id:'tricolor',name:'Tricolor',sub:'HSE',    primary:'#003da5', secondary:'#c8102e', tertiary:'#ffffff' },
  { id:'royal',   name:'Royal',   sub:'HSE',      primary:'#0b41a8', secondary:'#002b7f', tertiary:'#ffffff' },
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
//  - 'stripes'  : gradients stay in the primary family, header texture stays
//                 light, and the accent color is reserved for outlines,
//                 highlights, and surface pinstripe tinting.
//  - 'gradient' : the classic primary -> gradient-partner two-color blend.
const ACCENT_STYLES = ['stripes', 'gradient'];
const DEFAULT_ACCENT_STYLE = 'gradient';
const GITHUB_REPO_URL     = 'https://github.com/ajani190819-ops/HSEQB';
const GITHUB_ISSUES_URL   = GITHUB_REPO_URL + '/issues';
const GITHUB_RELEASES_URL = GITHUB_REPO_URL + '/releases';
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
let authUser = null; let authStarted = false; let appStarted = false;
const THEME_MODES = ['light', 'dark', 'device'];
let themeMode = 'device';
let colorTheme = DEFAULT_COLOR_THEME;
let accentStyle = DEFAULT_ACCENT_STYLE;
let customThemeColors = { primary:'#0b41a8', secondary:'#002b7f', tertiary:'#ffffff', accent:'#002b7f' };
let advancedThemeColors = { bannerStripe:'', bannerOutline:'' };
let _deviceThemeQuery = null;
let _profileSaveTimer = null;
let _profileLoadSequence = 0;

