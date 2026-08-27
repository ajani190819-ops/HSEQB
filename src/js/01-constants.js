const VERSION = '3.9.0'; // auto-managed by bump.js
const DOWNLOAD_URL = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/main/index.html';
const DEFAULT_ACCENT = '#0b41a8'; // Royal — HSE High School royal blue
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
let _deviceThemeQuery = null;
let _profileSaveTimer = null;
let _profileLoadSequence = 0;

