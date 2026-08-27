function initFirebase(){
if (isIframe){
db=null; sessionsRef=_noopRef(); globalPlayersRef=_noopRef(); versionRef=_noopRef(); globalSettingsRef=_noopRef(); userIdentitiesRef=_noopRef(); userProfilesRef=_noopRef(); userProfileRef=null; adminListRef=_noopRef();
startApp();
return; }
if (typeof firebase === 'undefined'){ setTimeout(initFirebase, 50); return; }
const firebaseConfig ={apiKey:"AIzaSyCRkK3IpRXeQC9JH73iC0tC-mjq5nulaAo",authDomain:"hse-quiz-bowl.firebaseapp.com",databaseURL:"https://hse-quiz-bowl-default-rtdb.firebaseio.com",projectId:"hse-quiz-bowl",storageBucket:"hse-quiz-bowl.firebasestorage.app",messagingSenderId:"676670239956",appId:"1:676670239956:web:9c569fc74ecf21de25f741"};
try{ firebase.app(); } catch(e){ firebase.initializeApp(firebaseConfig); }
db=firebase.database();
sessionsRef=db.ref('sessions'); globalPlayersRef=db.ref('globalPlayers'); versionRef=db.ref('appVersion');
globalSettingsRef=db.ref('globalSettings'); userIdentitiesRef=db.ref('userIdentities'); userProfilesRef=db.ref('userProfiles'); adminListRef=db.ref('adminList');
setupDeviceThemeListener();
restoreVisualSettings();
adminListRef.on('value', snap =>{ adminList=snap.val()||[]; recomputeAdmin(); });
initAuth(); }
function startApp(){
versionRef.on('value', snap =>{
const data = snap.val();
if (!data){ checkReleasePrompt(''); return; }
// Support both old string format and new object format
const remoteBuild = (typeof data === 'object') ? (data.buildId || '')      :'';
const downloadUrl = (typeof data === 'object') ? (data.downloadUrl || '')  :'';
const releaseNotes= (typeof data === 'object') ? (data.releaseNotes || '') :'';
const remoteLabel = (typeof data === 'object') ? (data.label || '')         :'';
// Badge always reflects FILE_VERSION — intentionally not set from Firebase
// Pre-fill URL, version label, and release notes inputs if admin hasn't typed in them yet
const rnInput = $('releaseNotesInput');
if (rnInput && document.activeElement !== rnInput && !rnInput.value) rnInput.value = releaseNotes;
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
// Only check for updates if the user is running a local file, not the live GitHub Pages site or online deployment
const isGitHubPages = window.location.hostname === 'ajani190819-ops.github.io';
const isLocalFile = window.location.protocol === 'file:';
const isOtherOnline = window.location.protocol === 'https:' || window.location.protocol === 'http:';
const shouldCheckUpdates = isLocalFile && !isGitHubPages;
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
showUpdateBanner(remoteLabel, downloadUrl, releaseNotes);
} else if (shouldCheckUpdates && (localIsNewer || !remoteBuild)){
showDevBanner();
} else{
hideUpdateBanner(); }
// Store loading source for help menu
const loadingSource = isLocalFile ? 'Local File' :isGitHubPages ? 'GitHub Pages' :isOtherOnline ? 'Online' :'Unknown';
localStorage.setItem('qb_loadingSource', loadingSource); });
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
