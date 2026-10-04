/* Offline database shim ─────────────────────────────────────────────────────
 * A miniature Realtime Database backed by localStorage, used only while no
 * firebaseConfig is set in 01-constants.js. It implements the exact API
 * surface this app uses (on/once/get/set/update/remove/child/push/key/
 * transaction; 'value' listeners only), so every feature works with zero
 * network access — sessions, players, analytics, admin settings, everything.
 * Data persists in this browser only and never leaves the device. */
function createLocalDatabase(){
const STORAGE_KEY = 'qb_local_db';
const SAVE_DEBOUNCE_MS = 250;
let data = {};
try{ data = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}') || {}; }catch(e){ data = {}; }
let saveTimer = null;
const listeners = []; // { path, cb }
function persist(){
clearTimeout(saveTimer);
saveTimer = setTimeout(()=>{ try{ localStorage.setItem(STORAGE_KEY, JSON.stringify(data)); }catch(e){ /* storage unavailable — stay in memory */ } }, SAVE_DEBOUNCE_MS); }
function getAt(path){
let node = data;
for (const seg of path.split('/').filter(Boolean)){ if (node == null || typeof node !== 'object') return null; node = node[seg]; }
return node === undefined ? null : node; }
function setAt(path, value){
const segs = path.split('/').filter(Boolean);
if (!segs.length){ data = (value && typeof value === 'object' && !Array.isArray(value)) ? value : {}; persist(); notify(); return; }
let node = data;
for (let i=0; i<segs.length-1; i++){ const s=segs[i]; if (node[s] == null || typeof node[s] !== 'object') node[s] = {}; node = node[s]; }
const last = segs[segs.length-1];
if (value === null || value === undefined) delete node[last]; else node[last] = value;
persist(); notify(); }
// Every listener re-reads its own path after any write, so listeners on
// ancestors AND descendants of the changed node all stay correct.
function notify(){
listeners.forEach(L =>{ try{ L.cb({ val:() => getAt(L.path) }); }catch(e){ /* a broken listener must never break the writer */ } }); }
function makeRef(path){
return {
key: path.split('/').filter(Boolean).pop() || null,
child: (k) => makeRef(path ? path + '/' + k : String(k)),
on: (ev, cb) =>{ if (ev !== 'value' || typeof cb !== 'function') return () => {}; listeners.push({ path, cb }); try{ cb({ val:() => getAt(path) }); }catch(e){} return () => { const i = listeners.findIndex(L => L.cb === cb && L.path === path); if (i >= 0) listeners.splice(i, 1); }; },
off: (ev, cb) => { const i = listeners.findIndex(L => (!cb || L.cb === cb) && L.path === path); if (i >= 0) listeners.splice(i, 1); },
once: () => Promise.resolve({ val:() => getAt(path), exists:() => getAt(path) !== null }),
get:   () => Promise.resolve({ val:() => getAt(path), exists:() => getAt(path) !== null }),
set: (v) => { setAt(path, v === undefined ? null : v); return Promise.resolve(); },
update: (patch) => { Object.entries(patch || {}).forEach(([k, v]) => setAt(path ? path + '/' + k : k, v === undefined ? null : v)); return Promise.resolve(); },
remove: () => { setAt(path, null); return Promise.resolve(); },
push: (v) => { const id = 'loc-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8); const p = path ? path + '/' + id : id; if (v !== undefined) setAt(p, v); return makeRef(p); },
transaction: (fn, onComplete) => { const cur = getAt(path); let next; try{ next = fn(cur); }catch(e){ if (typeof onComplete === 'function'){ try{ onComplete(e); }catch(_){} } return Promise.reject(e); } setAt(path, next === undefined ? cur : next); if (typeof onComplete === 'function'){ try{ onComplete(null); }catch(_){} } return Promise.resolve({ committed:true, snapshot:{ val:() => getAt(path) } }); },
}; }
return { ref: (p) => makeRef(p || '') };
}
function initFirebase(){
if (isIframe){
db=null; sessionsRef=_noopRef(); globalPlayersRef=_noopRef(); versionRef=_noopRef(); releaseHtmlRef=_noopRef(); releaseHistoryRef=_noopRef(); globalSettingsRef=_noopRef(); userIdentitiesRef=_noopRef(); userProfilesRef=_noopRef(); userProfileRef=null; adminListRef=_noopRef(); adminUidsRef=_noopRef();
startApp();
return; }
// OFFLINE MODE — no Firebase project configured yet (01-constants.js).
// The whole app runs from browser storage; there is no sign-in gate and
// nothing leaves the device.
if (isOfflineMode){
db = createLocalDatabase();
sessionsRef=db.ref('sessions'); globalPlayersRef=db.ref('globalPlayers'); versionRef=db.ref('appVersion'); releaseHtmlRef=db.ref('releaseHtml'); releaseHistoryRef=db.ref('releaseHistory');
globalSettingsRef=db.ref('globalSettings'); userIdentitiesRef=db.ref('userIdentities'); userProfilesRef=db.ref('userProfiles'); userProfileRef=null; adminListRef=db.ref('adminList'); adminUidsRef=db.ref('adminUids');
document.body.classList.add('is-offline');
setupDeviceThemeListener();
restoreVisualSettings();
adminListRef.on('value', snap =>{ adminList=snap.val()||[]; recomputeAdmin(); });
adminUidsRef.on('value', snap =>{ adminUids=snap.val()||{}; recomputeAdmin(); });
startApp();
return; }
if (typeof firebase === 'undefined'){ setTimeout(initFirebase, 50); return; }
try{ firebase.app(); } catch(e){ firebase.initializeApp(firebaseConfig); }
db=firebase.database();
sessionsRef=db.ref('sessions'); globalPlayersRef=db.ref('globalPlayers'); versionRef=db.ref('appVersion'); releaseHtmlRef=db.ref('releaseHtml'); releaseHistoryRef=db.ref('releaseHistory');
globalSettingsRef=db.ref('globalSettings'); userIdentitiesRef=db.ref('userIdentities'); userProfilesRef=db.ref('userProfiles'); adminListRef=db.ref('adminList'); adminUidsRef=db.ref('adminUids');
setupDeviceThemeListener();
restoreVisualSettings();
adminListRef.on('value', snap =>{ adminList=snap.val()||[]; recomputeAdmin(); });
adminUidsRef.on('value', snap =>{ adminUids=snap.val()||{}; recomputeAdmin(); });
initAuth(); }
function startApp(){
versionRef.on('value', snap =>{
const data = snap.val();
if (!data){ setLatestReleaseMeta(null); checkReleasePrompt(''); return; }
// Support both old string format and new object format
const remoteBuild = (typeof data === 'object') ? (data.buildId || '')      :'';
const downloadUrl = (typeof data === 'object') ? (data.downloadUrl || '')  :'';
const releaseNotes= (typeof data === 'object') ? (data.releaseNotes || '') :'';
const remoteLabel = (typeof data === 'object') ? (data.label || '')         :'';
const hasFirebasePayload = (typeof data === 'object') ? !!data.hasFirebasePayload : false;
setLatestReleaseMeta(data);
// Badge always reflects FILE_VERSION — intentionally not set from Firebase
// Pre-fill URL, version label, and release notes inputs if admin hasn't typed in them yet
const rnInput = $('releaseNotesInput');
if (rnInput && document.activeElement !== rnInput && !rnInput.value) rnInput.value = releaseNotes;
const titleInput = $('releaseTitleInput');
if (titleInput && document.activeElement !== titleInput && !titleInput.value) titleInput.value = APP_NAME + ' v' + FILE_VERSION;
// Populate version preview label
// Update live build display in admin panel
const liveDisp = $('liveFirebaseBuildDisplay');
if (liveDisp) liveDisp.textContent = remoteBuild || '(none)';
const liveLabelDisp = $('liveFirebaseLabelDisplay');
if (liveLabelDisp) liveLabelDisp.textContent = remoteLabel ? '('+remoteLabel+')' : '';
// GitHub published: file is on GitHub when its build ID matches the Firebase-published build
const ghDisp = $('githubPublishedDisplay');
if (ghDisp){
const onGitHub = remoteBuild && remoteBuild === FILE_BUILD_ID;
ghDisp.textContent = onGitHub ? '✔ Yes' : remoteBuild ? '✗ Not yet' : '—';
ghDisp.style.color = onGitHub ? 'var(--success)' : remoteBuild ? 'var(--danger)' : 'var(--text3)';
}
// Show/hide the release prompt for admins
checkReleasePrompt(remoteBuild);
// Only check for updates if the user is running a local file, not a deployed
// site (DEPLOY_HOSTNAMES in 01-constants.js) — and never in offline mode,
// where there is nothing to update from.
const isDeployedHost = DEPLOY_HOSTNAMES.includes(window.location.hostname);
const isLocalFile = window.location.protocol === 'file:';
const isOtherOnline = window.location.protocol === 'https:' || window.location.protocol === 'http:';
const shouldCheckUpdates = isLocalFile && !isDeployedHost && !isOfflineMode;
// Only show update if remote build is actually published AND is different from local
// Don't show if local build is unpublished (same as remote build but not yet on GitHub)
// Compare versions numerically so "3.1.0" is correctly seen as newer than "1.5.46"
function parseVer(v){ return (v||'').split('.').map(n=>parseInt(n,10)||0); }
function isNewer(remote, local){
const r=parseVer(remote), l=parseVer(local);
for(let i=0;i<Math.max(r.length,l.length);i++){
if((r[i]||0)>(l[i]||0)) return true;
if((r[i]||0)<(l[i]||0)) return false;
}
return false;
}
const remoteIsNewer  = remoteBuild && remoteLabel && isNewer(remoteBuild, FILE_BUILD_ID);
const localIsNewer   = remoteBuild && isNewer(FILE_BUILD_ID, remoteBuild);
const isUnpublishedLocal = !remoteBuild || localIsNewer || FILE_BUILD_ID === remoteBuild;
if (shouldCheckUpdates && remoteIsNewer){
showUpdateBanner(remoteLabel, downloadUrl, releaseNotes, hasFirebasePayload);
} else if (shouldCheckUpdates && (localIsNewer || !remoteBuild)){
showDevBanner();
} else{
hideUpdateBanner(); }
// Store loading source for help menu
const loadingSource = isLocalFile ? 'Local File' :isDeployedHost ? 'Deployed site' :isOtherOnline ? 'Online' :'Unknown';
localStorage.setItem('qb_loadingSource', loadingSource); });
releaseHistoryRef.on('value', snap =>{
releaseHistoryCache = snap.val() || {};
if (updatesModalOpen) renderUpdatesCenter();
});
globalSettingsRef.on('value', snap =>{
const s = snap.val(); if (!s) return;
let changed = false;
if(typeof s.skillThresholdPct==='number'&&s.skillThresholdPct!==skillThresholdPct){skillThresholdPct=s.skillThresholdPct;changed=true;}
if(Array.isArray(s.manuallyIncluded)){const inc=new Set(s.manuallyIncluded);if(inc.size!==manuallyIncluded.size||![...inc].every(n=>manuallyIncluded.has(n))){manuallyIncluded=inc;changed=true;}}
if(s.playerTHeardOverrides&&typeof s.playerTHeardOverrides==='object'){playerTHeardOverrides=s.playerTHeardOverrides;changed=true;}
if(s.sessionInvalidFlags&&typeof s.sessionInvalidFlags==='object'){sessionInvalidFlags=s.sessionInvalidFlags;changed=true;}
if(s.catColors&&typeof s.catColors==='object'){catColors={...catColors,...s.catColors};renderCatColorPickers();changed=true;}
if(s.catFreqs&&typeof s.catFreqs==='object'){catFreqs={...CAT_FREQ_DEFAULTS,...s.catFreqs};renderCatFreqPickers();changed=true;}
if (changed){ updateSkillThresholdUI(); if(analyticsOpen) renderAnalytics(); if($('sessionsModal')?.classList.contains('open')) renderSessionsList(); }
});
restoreVisualSettings();
updateHeaderHeight();
window.addEventListener('resize',()=>{ updateHeaderHeight(); applySidebarState(); updateFadeMasks(); });
['qbScroll','analyticsScroll'].forEach(id=>$(id)?.addEventListener('scroll',updateFadeMasks));
document.querySelector('.sidebar-sections')?.addEventListener('scroll',updateFadeMasks);
setTimeout(() =>{
const qbs = $('qbScroll');
if (qbs){
const saved = parseInt(localStorage.getItem('trackerScroll')||'0', 10);
if (saved) qbs.scrollTop = saved;
qbs.addEventListener('scroll', () => localStorage.setItem('trackerScroll', qbs.scrollTop));
}
}, 400);
loadAllData();
setupGlobalPlayers();
setInterval(() =>{ saveAllData(); }, 5000);
setupSectionToggle();
applySidebarState();
const savedSection=localStorage.getItem('activeSidebarSection')||'sec-session';
const _wasAnalyticsOpen = localStorage.getItem('analyticsOpen') === 'true';
const _savedAnalyticsTab = localStorage.getItem('analyticsTab') || 'overview';
if (_wasAnalyticsOpen){
analyticsOpen = true;
$('trackerView').style.display = 'none';
$('analyticsView').style.display = 'flex';
setToggleSwitchState(true);
currentAnalyticsTab = _savedAnalyticsTab;
document.querySelectorAll('.analytics-tab').forEach(b =>{
const matches = b.getAttribute('onclick')?.includes("'"+_savedAnalyticsTab+"'");
b.classList.toggle('active', !!matches); });
document.querySelectorAll('.analytics-panel').forEach(p => p.classList.remove('active'));
$('an-'+_savedAnalyticsTab)?.classList.add('active');
setTimeout(() =>{
const scrollEl = $('analyticsScroll');
if (scrollEl) scrollEl.scrollTop = parseInt(localStorage.getItem('analyticsScroll_'+_savedAnalyticsTab)||'0', 10);
}, 600); }
$('analyticsScroll')?.addEventListener('scroll',function(){localStorage.setItem('analyticsScroll_'+currentAnalyticsTab,this.scrollTop);});
showSection(savedSection);
document.addEventListener('click',e=>{ const w=$('sidebarJumpWrapper'); if(w&&!w.contains(e.target)) w.classList.remove('open'); ['helpModal','sessionsModal','playerDetailModal'].forEach(id=>{const m=$(id);if(m&&e.target===m)m.classList.remove('open');}); });
loadUserId();
recomputeAdmin();
// Set header version badge to THIS file's version immediately — never reflects Firebase label
const badge = $('versionBadge');
if (badge){
badge.textContent = FILE_VERSION;
badge.title = `Build: ${FILE_BUILD_ID}`;
// Use !important to override CSS media query that hides it on mobile
badge.style.setProperty('display', 'inline', 'important'); }
// Help modal repository link follows the fork's configured repo (01-constants.js)
const ghLink = $('helpGithubLink');
if (ghLink){
if (GITHUB_REPO_URL){ ghLink.href = GITHUB_REPO_URL; ghLink.target = '_blank'; ghLink.rel = 'noopener noreferrer'; ghLink.textContent = GITHUB_REPO_URL.replace(/^https?:\/\//, ''); }
else ghLink.textContent = 'not configured yet — set GITHUB_REPO_URL in 01-constants.js';
}
// Populate version displays in admin panel
const displayVerDisp = $('displayVersionDisplay');
const internalVerDisp = $('internalVersionDisplay');
if (displayVerDisp) displayVerDisp.textContent = DISPLAY_VERSION;
if (internalVerDisp) internalVerDisp.textContent = INTERNAL_BUILD;
// FIX:Check if elements exist before setting onclick
const sidebarOpenBtn = $('sidebarOpenBtn');
if (sidebarOpenBtn) sidebarOpenBtn.onclick = toggleSidebar;
const sidebarOpenBtnMobile = $('sidebarOpenBtnMobile');
if (sidebarOpenBtnMobile) sidebarOpenBtnMobile.onclick = toggleSidebar;
if (!isIframe) maybeShowWelcomeToast();
// Offline notice — make it unmistakable where data lives until Firebase is connected.
if (isOfflineMode) setTimeout(() =>{ try{ showToast('&#128190; <strong>Offline mode</strong> — everything works, and data is stored in this browser only. Connect your own Firebase project (setup guide in the repo README) to sync across devices.', 'info', 7000); }catch(e){} }, 1500);
if (!isIframe) startGhPolling();
if (isIframe){
setTimeout(() =>{
if (_iframeDebugActive) return; // already ran — never run twice
_iframeDebugActive = true;
_adminToken.grant();
applyAdminUI();
applyDebugMenuVisibility();
const sess = getCurrentSession();
if (sess) injectDebugData();
renderAll();
const chartsBtn = document.querySelector('.analytics-tab[onclick*="charts"]');
if (chartsBtn){
if (!analyticsOpen) toggleAnalytics();
chartsBtn.click(); }
}, 0); }
}
