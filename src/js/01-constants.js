const VERSION = '3.7.0'; // auto-managed by bump.js
const DOWNLOAD_URL = 'https://raw.githubusercontent.com/ajani190819-ops/HSEQB/main/index.html';
const DISPLAY_VERSION = VERSION; const INTERNAL_BUILD = VERSION;
const FILE_VERSION    = VERSION; const FILE_BUILD_ID  = VERSION;
var db, sessionsRef, globalPlayersRef, versionRef, releaseHtmlRef, globalSettingsRef, userIdentitiesRef, userProfilesRef, userProfileRef, adminListRef, adminList = [];
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
return{ on:noop, off:noop, once:p, set:p, update:p, remove:p, child:noop, transaction:p };
}
let authUser = null; let authStarted = false; let appStarted = false;
const THEME_MODES = ['light', 'dark', 'device'];
let themeMode = 'device';
let _deviceThemeQuery = null;
let _profileSaveTimer = null;
let _profileLoadSequence = 0;

