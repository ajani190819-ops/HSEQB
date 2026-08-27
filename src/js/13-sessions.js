function createNewSession(){
const id=Date.now().toString();
const nameInput=$('newSessionName');
const name=nameInput?.value.trim()||('Session '+new Date().toLocaleDateString());
const session={id,name,created:new Date().toISOString(),lastUpdated:new Date().toISOString(),updatedBy:clientId,players:{},teams:[],categories:[...DEFAULT_CATEGORIES],answers:[],answerLog:[]};
state.sessions[id]=session; state.currentSessionId=id; loadSessionData();
globalPlayersRef.once('value').then(snap=>{
Object.keys(snap.val()||{}).forEach(n=>{if(!session.players[n]) session.players[n]={name:n,points:0,answers:[]};});
setSessionNonAtomic(id,session).catch(e=>showFirebaseError(e.message));
localStorage.setItem(CURRENT_SESSION_KEY,id);
if(nameInput) nameInput.value='';
closeSessionsModal(); renderAll();
showToast(`Session "${name}" created and loaded`, 'success');
}).catch(()=>{ setSessionNonAtomic(id,session).catch(e=>showFirebaseError(e.message)); localStorage.setItem(CURRENT_SESSION_KEY,id); if(nameInput) nameInput.value=''; closeSessionsModal(); renderAll(); showToast(`Session "${name}" created and loaded`, 'success'); });
}
function openSessionsModal() {
$('sessionsModal').classList.add('open');
$('sessionsSearchInput').value = '';
$('sessionsSortSelect').value = 'date-desc';
renderSessionsList();
// Add event listeners for search and sort
$('sessionsSearchInput').addEventListener('input', renderSessionsList);
$('sessionsSortSelect').addEventListener('change', renderSessionsList);
}
function closeSessionsModal(){ $('sessionsModal').classList.remove('open'); }
function openHelpModal(){
const loadingSource = localStorage.getItem('qb_loadingSource') || 'Unknown';
const sourceEl = $('helpLoadingSource');
if (sourceEl) sourceEl.textContent = loadingSource;
$('helpModal').classList.add('open'); }
function closeHelpModal()    { $('helpModal').classList.remove('open'); }
function openExternalLink(url){
try { const w = window.open(url, '_blank', 'noopener,noreferrer'); if (w) { w.opener = null; return; } } catch(e) {}
try { if (typeof showToast === 'function') showToast('Popup blocked — open manually: ' + url, 'warning', 6000); else window.location.href = url; } catch(e) {}
}
function openGitHubRepo()     { openExternalLink(GITHUB_REPO_URL); }
function openGitHubIssues()   { openExternalLink(GITHUB_ISSUES_URL); }
function openGitHubReleases() { openExternalLink(GITHUB_RELEASES_URL); }
var sessionSelection = new Set();
function renderSessionsList(){
const list = $('sessionsList');
const searchInput = $('sessionsSearchInput');
const sortSelect = $('sessionsSortSelect');
let sessions = Object.values(state.sessions);
const searchTerm = (searchInput?.value || '').toLowerCase().trim();
const sortMode = sortSelect?.value || 'date-desc';
// Filter by search term
if (searchTerm){
sessions = sessions.filter(s =>
s.name.toLowerCase().includes(searchTerm) ||
(s.created && new Date(s.created).toLocaleString().toLowerCase().includes(searchTerm))
); }
// Sort sessions
sessions.sort((a, b) =>{
switch(sortMode){
case 'date-asc':
return new Date(a.created) - new Date(b.created);
case 'name':
return a.name.localeCompare(b.name);
case 'answers-desc':
return ((b.answerLog||[]).length) - ((a.answerLog||[]).length);
case 'answers-asc':
return ((a.answerLog||[]).length) - ((b.answerLog||[]).length);
case 'date-desc':
default:
return new Date(b.created) - new Date(a.created); }
});
if(!sessions.length){
list.innerHTML = searchTerm
? `<p class="text-2-p16">No sessions match "${searchTerm}".`
:'<p class="text-2-p16">No sessions found.</p>';
updateSessionBulkBar();
return; }
list.innerHTML = sessions.map(s=>{
const isInvalid = !!sessionInvalidFlags[s.id];
const isCurrent = s.id === state.currentSessionId;
const isSelected = sessionSelection.has(s.id);
return `
<div class="session-card${isSelected ? ' selected' :''}" style="${isSelected ? '' : (isInvalid ? 'opacity:.6;border-color:var(--danger);' : '')}">
<div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;">
<div style="display:flex;gap:9px;flex:1;min-width:0;">
<input type="checkbox" class="session-select-cb" ${isSelected ? 'checked' :''} onchange="toggleSessionSelect('${s.id}', this.checked)" title="Select for bulk actions" aria-label="Select ${s.name}">
<div style="min-width:0;flex:1;">
<div class="session-card-title" style="${isInvalid ? 'text-decoration:line-through;color:var(--text2);' :''}">${s.name}${isCurrent ? ' <span style="font-size:.7em;background:var(--primary);color:#fff;padding:2px 7px;border-radius:8px;font-weight:700;vertical-align:middle;">Active</span>' :''}</div>
<div class="session-card-details">
<div>Created:${new Date(s.created).toLocaleString()}</div>
<div>${(s.answerLog||[]).length} Answers &bull; ${s.tHeard||0} Questions Heard</div>
</div>
${isInvalid ? '<div style="font-size:.78em;color:var(--danger);font-weight:700;margin-top:4px;">! Excluded From Analytics</div>' :''}
</div>
</div>
<div style="display:flex;flex-direction:column;align-items:center;gap:4px;flex-shrink:0;padding-top:2px;">
<span style="font-size:.7em;font-weight:700;color:var(--text2);">Analytics</span>
<div onclick="toggleSessionInvalid('${s.id}')" style="width:38px;height:20px;background:${isInvalid ? 'var(--danger)' :'var(--success)'};border-radius:10px;cursor:pointer;position:relative;transition:background .2s;" title="${isInvalid ? 'Session Excluded — click to include' :'Session Included — click to exclude'}">
<div style="width:14px;height:14px;background:#fff;border-radius:50%;position:absolute;top:3px;${isInvalid ? 'left:3px' :'left:21px'};transition:left .2s;box-shadow:0 1px 3px rgba(0,0,0,.3);"></div>
</div>
<span style="font-size:.68em;font-weight:700;color:${isInvalid ? 'var(--danger)' :'var(--success)'};">${isInvalid ? 'OFF' :'ON'}</span>
</div>
</div>
<div class="session-card-actions" class="mt-10">
<button class="button" onclick="loadSession('${s.id}')">Load</button>
<button class="button button-danger" onclick="deleteSession('${s.id}')">Delete</button>
</div>
</div>`;
}).join('');
updateSessionBulkBar(); }
function toggleSessionInvalid(id){
const s = state.sessions[id]; if (!s) return;
if (sessionInvalidFlags[id]) delete sessionInvalidFlags[id]; else sessionInvalidFlags[id]=true;
globalSettingsRef.child('sessionInvalidFlags').set(sessionInvalidFlags).catch(e=>showFirebaseError('Analytics toggle failed:'+e.message));
renderSessionsList();
if (analyticsOpen) renderAnalytics(); }
function toggleSessionSelect(id, on){
if (on) sessionSelection.add(id); else sessionSelection.delete(id);
renderSessionsList();
}
function toggleSelectAllSessions(on){
const searchInput = $('sessionsSearchInput');
const searchTerm = (searchInput?.value || '').toLowerCase().trim();
Object.values(state.sessions).forEach(s =>{
if (searchTerm && !(s.name.toLowerCase().includes(searchTerm) || (s.created && new Date(s.created).toLocaleString().toLowerCase().includes(searchTerm)))) return;
if (on) sessionSelection.add(s.id); else sessionSelection.delete(s.id);
});
renderSessionsList();
}
function updateSessionBulkBar(){
const bar = $('sessionBulkBar');
if (!bar) return;
const n = sessionSelection.size;
bar.style.display = n ? 'flex' : 'none';
const count = $('sessionBulkCount');
if (count) count.textContent = n + ' selected';
const all = $('sessionSelectAll');
if (all){
const ids = Object.keys(state.sessions);
all.checked = ids.length > 0 && ids.every(id => sessionSelection.has(id));
}
}
function bulkSetAnalytics(include){
const ids = [...sessionSelection].filter(id => state.sessions[id]);
if (!ids.length) return;
ids.forEach(id => { if (include) delete sessionInvalidFlags[id]; else sessionInvalidFlags[id] = true; });
globalSettingsRef.child('sessionInvalidFlags').set(sessionInvalidFlags).catch(e=>showFirebaseError('Analytics update failed:'+e.message));
sessionSelection = new Set();
renderSessionsList();
if (analyticsOpen) renderAnalytics();
showToast(ids.length + (ids.length > 1 ? ' sessions' : ' session') + (include ? ' added to analytics.' : ' excluded from analytics.'), 'success');
}
function bulkDeleteSessions(){
const ids = [...sessionSelection].filter(id => state.sessions[id]);
if (!ids.length) return;
const label = ids.length === 1 ? 'session "' + state.sessions[ids[0]].name + '"' : ids.length + ' sessions';
showConfirm('Delete ' + label + '? This cannot be undone.', 'Delete', 'warn').then(ok =>{
if (!ok) return;
ids.forEach(id =>{
sessionsRef.child(id).remove().catch(e=>showFirebaseError(e.message));
delete state.sessions[id];
});
if (state.currentSessionId && ids.includes(state.currentSessionId)){
state.currentSessionId = Object.keys(state.sessions)[0] || null;
if (!state.currentSessionId) createNewSession(); else { localStorage.setItem(CURRENT_SESSION_KEY, state.currentSessionId); loadSessionData(); }
}
sessionSelection = new Set();
renderSessionsList(); renderAll();
showToast(ids.length + (ids.length > 1 ? ' sessions' : ' session') + ' deleted.', 'success');
});
}
function loadSession(id){ state.currentSessionId=id; loadSessionData(); globalPlayersRef.once('value').then(s=>applyGlobalPlayersToSession(s.val()||{})); saveAllData(); renderAll(); closeSessionsModal(); }
function deleteSession(id){
showConfirm('Delete session "'+state.sessions[id].name+'"?', 'Delete').then(ok =>{
if (!ok) return;
sessionsRef.child(id).remove().catch(e=>showFirebaseError(e.message));
delete state.sessions[id];
if(state.currentSessionId===id){
state.currentSessionId=Object.keys(state.sessions)[0]||null;
if(!state.currentSessionId) createNewSession(); else{localStorage.setItem(CURRENT_SESSION_KEY,state.currentSessionId);loadSessionData();}
}
renderSessionsList(); renderAll(); });
}
