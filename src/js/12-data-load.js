const getCurrentSession = ()=>state.sessions[state.currentSessionId]||null;
function updateFadeMasks(){
const F=28; ['.qb-scroll','.sidebar-sections','.log-container','.analytics-scroll'].forEach(sel=>{
const el=document.querySelector(sel); if(!el) return;
const up=el.scrollTop>2, dn=el.scrollHeight>el.scrollTop+el.clientHeight+2;
const mask=up&&dn?`linear-gradient(to bottom,transparent 0,black ${F}px,black calc(100% - ${F}px),transparent 100%)`:up?`linear-gradient(to bottom,transparent 0,black ${F}px,black 100%)`:dn?`linear-gradient(to bottom,black 0%,black calc(100% - ${F}px),transparent 100%)`:'none';
el.style.webkitMaskImage=el.style.maskImage=mask; });
}
function updateHeaderHeight(){ const h=$('qbHeader'); if(h) document.documentElement.style.setProperty('--header-height',h.offsetHeight+'px'); }
function setupGlobalPlayers(){
if (isIframe) return; // no Firebase in preview
if (playersUnsubscribe) playersUnsubscribe();
playersUnsubscribe = globalPlayersRef.on('value', snap =>{
if (!state.currentSessionId) return;
applyGlobalPlayersToSession(snap.val() ||{});
});
userIdentitiesRef.on('value', snap =>{
userIdentitiesCache = snap.val() ||{};
}); }
function applyGlobalPlayersToSession(data){
const s = getCurrentSession(); if (!s) return;
let changed = false;
Object.keys(data).forEach(name =>{ if (!s.players[name]){ s.players[name] ={ name, points:0, answers:[] }; changed = true; } });
if (changed){
sessionsRef.child(state.currentSessionId).set(s).catch(e => showFirebaseError(e.message));
renderPlayerPool(); renderPlayerButtons(); renderSubPanel(); renderTeams(); }
}
function saveGlobalPlayers(names){
if (isIframe) return;
const updates ={}; names.forEach(n =>{ if (n) updates[n] = true; });
if (Object.keys(updates).length) globalPlayersRef.update(updates).catch(e => showFirebaseError(e.message));
}
function removeGlobalPlayer(name){ globalPlayersRef.child(name).remove().catch(e => showFirebaseError(e.message)); }
function loadAllData(){
if (isIframe){ // In preview:create a bare local session; do NOT renderAll yet —
const id = 'preview-' + Date.now();
state.sessions[id] ={
id, name:'Preview Session',
created:new Date().toISOString(), lastUpdated:new Date().toISOString(),
updatedBy:'preview', players:{}, teams:[],
categories:[...DEFAULT_CATEGORIES], answers:[], answerLog:[], tHeard:0
};
state.currentSessionId = id;
loadSessionData();
return; // renderAll happens after inject, not here
}
setLoadingState();
if (firebaseUnsubscribe) firebaseUnsubscribe();
firebaseUnsubscribe = sessionsRef.on('value', snap =>{
const incoming = snap.val() ||{};
if (state.currentSessionId && writeInFlight.has(state.currentSessionId)){
Object.keys(incoming).forEach(id =>{
if (id !== state.currentSessionId){ state.sessions[id] = normalizeSession(incoming[id]); }
});
} else{
state.sessions = incoming;
Object.keys(state.sessions).forEach(id =>{ state.sessions[id] = normalizeSession(state.sessions[id]); });
}
const savedId = localStorage.getItem(CURRENT_SESSION_KEY);
if (savedId && state.sessions[savedId]){ state.currentSessionId = savedId; } else if (Object.keys(state.sessions).length){
state.currentSessionId = Object.keys(state.sessions)[0];
localStorage.setItem(CURRENT_SESSION_KEY, state.currentSessionId);
} else{
updateAutoSave();
createNewSession();
return; }
loadSessionData();
globalPlayersRef.once('value').then(s => applyGlobalPlayersToSession(s.val() ||{}));
updateAutoSave();
renderAll();
if ($('sessionsModal')?.classList.contains('open')){
renderSessionsList(); }
}, err => showFirebaseError('Connection failed:' + err.message)); }
function loadSessionData(){
const s=getCurrentSession(); if(!s){createNewSession();return;}
state.categories = s.categories = [...DEFAULT_CATEGORIES];
setTimeout(renderCategoryTreeDisplay, 0); }
function saveAllData(){
if (isIframe) return;
const s = getCurrentSession();
if (s){ s.categories = state.categories; s.lastUpdated = new Date().toISOString(); s.updatedBy = clientId; }
localStorage.setItem(CURRENT_SESSION_KEY, state.currentSessionId);
if (s) setSessionNonAtomic(state.currentSessionId, s).catch(e => showFirebaseError(e.message));
}
