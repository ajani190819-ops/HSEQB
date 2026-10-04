function addToPlayerPool(){
const input  = $('playerInput');
const player = input.value.trim();
if (!player){ showToast('Please enter a player name.'); return; }
const id = state.currentSessionId;
if (!id) return;
updateSessionAtomic(id, s =>{
if (!s.players) s.players ={};
if (!s.players[player]) s.players[player] ={ name:player, points:0, answers:[] };
}).then(() =>{
input.value = '';
saveGlobalPlayers([player]); });
withWriteLock(id, () =>{
const s = getCurrentSession();
if (!s.players) s.players ={};
if (!s.players[player]) s.players[player] ={ name:player, points:0, answers:[] };
});
renderPlayerPool();
renderPlayerButtons();
renderSubPanel();
renderTeams(); }
function removeFromPlayerPool(player){
const id = state.currentSessionId;
if (!id) return;
updateSessionAtomic(id, s =>{
if (s.players) delete s.players[player];
(s.teams || []).forEach(t =>{ t.playerMembers = (t.playerMembers || []).filter(p => p !== player); });
});
removeGlobalPlayer(player);
withWriteLock(id, () =>{
const s = getCurrentSession();
if (!s) return;
if (s.players) delete s.players[player];
(s.teams || []).forEach(t =>{ t.playerMembers = (t.playerMembers || []).filter(p => p !== player); });
});
renderPlayerPool();
renderPlayerButtons();
renderSubPanel();
renderTeams(); }
function clearPlayerPool(){
showConfirm('Clear all players?', 'Clear').then(ok =>{
if (!ok) return;
const id = state.currentSessionId;
if (!id) return;
const reset = s =>{
s.players  ={};
(s.teams || []).forEach(t =>{ t.playerMembers = []; });
s.answerLog = [];
s.answers   = []; };
updateSessionAtomic(id, reset);
withWriteLock(id, () =>{ const s = getCurrentSession(); if (s) reset(s); });
renderPlayerPool();
renderPlayerButtons();
renderSubPanel();
renderTeams();
renderAnswerLog();
renderStatistics();
renderSessionInfo(); });
}
function renderPlayerMgmt(){
const s = getCurrentSession();
const el = $('playerMgmtContainer');
if(!el || !s) return;
const players = Object.keys(s.players || {});
if(players.length === 0){
el.innerHTML = '<p class="text-2" style="font-size:.8em;">Add players first.</p>';
return; }
let html = '';
players.forEach(player => {
const safe = player.replace(/'/g, "\\'");
html += `<div style="display:flex;gap:6px;align-items:center;">
<span style="flex:1;font-size:.82em;overflow:hidden;text-overflow:ellipsis;">${player}</span>
<button class="button" onclick="startRenamePlayer('${safe}')" style="width:70px;padding:4px 8px;font-size:.75em;">Rename</button>
<button class="button" onclick="startMergePlayer('${safe}')" style="width:70px;padding:4px 8px;font-size:.75em;">Merge</button>
</div>`;
});
el.innerHTML = html; }
function startRenamePlayer(oldName){
const modal = $('playerActionModal');
const title = $('pamTitle');
const body  = $('pamBody');
if(!modal||!title||!body) return;
title.textContent = 'Rename Player';
body.innerHTML = `
<p style="font-size:.85em;color:var(--text2);margin-bottom:12px;">Renaming <strong>${oldName}</strong> will update their name everywhere in this session.</p>
<label style="font-size:.85em;font-weight:600;color:var(--text2);display:block;margin-bottom:6px;">New Name</label>
<input id="pamRenameInput" type="text" value="${oldName.replace(/"/g,'&quot;')}"
style="width:100%;padding:9px 12px;border:1.5px solid var(--input-border);border-radius:var(--radius-sm);font-size:.95em;font-family:inherit;background:var(--input-bg);color:var(--input-text);box-sizing:border-box;margin-bottom:14px;"
onkeydown="if(event.key==='Enter')confirmRenamePlayer('${oldName.replace(/'/g,"\'")}')"/>
<div style="display:flex;gap:8px;">
<button class="button button-success" style="flex:1;" onclick="confirmRenamePlayer('${oldName.replace(/'/g,"\'")}')">Rename</button>
<button class="button" style="flex:1;background:var(--sec-bg);color:var(--text2);" onclick="closePlayerActionModal()">Cancel</button>
</div>`;
modal.style.display = 'flex';
setTimeout(()=>{ const inp=$('pamRenameInput'); if(inp){inp.focus();inp.select();} },50); }
function confirmRenamePlayer(oldName){
const inp = $('pamRenameInput');
if(!inp) return;
const newName = inp.value.trim();
if(!newName){ showToast('Name cannot be empty.','warn'); return; }
if(newName === oldName){ closePlayerActionModal(); return; }
closePlayerActionModal();
renamePlayer(oldName, newName); }
function renamePlayer(oldName, newName){
const newNameTrimmed = newName.trim();
if(!newNameTrimmed){ showToast('Player name cannot be empty.','warn'); return; }
const id = state.currentSessionId;
if(!id) return;
const s = getCurrentSession();
if(!s?.players?.[oldName]){ showToast('Player not found.','warn'); return; }
// Mutate local state immediately
const oldData = JSON.parse(JSON.stringify(s.players[oldName]));
oldData.name = newNameTrimmed;
s.players[newNameTrimmed] = oldData;
delete s.players[oldName];
(s.teams || []).forEach(t =>{
if(t.playerMembers){
const idx = t.playerMembers.indexOf(oldName);
if(idx !== -1) t.playerMembers[idx] = newNameTrimmed; }
});
(s.answerLog || []).forEach(a =>{ if(a.player === oldName) a.player = newNameTrimmed; });
if(s.answers) Object.values(s.answers).forEach(a =>{ if(a.player === oldName) a.player = newNameTrimmed; });
s.lastUpdated = new Date().toISOString();
s.updatedBy = clientId;
// Hold writeInFlight for 2s — long enough to block applyGlobalPlayersToSession
// from re-adding the old name before globalPlayersRef is updated
writeInFlight.add(id);
notifySaveStart();
Promise.all([
sessionsRef.child(id).set(s),
globalPlayersRef.child(newNameTrimmed).set(true),
globalPlayersRef.child(oldName).remove()
])
.then(()=>{
notifySaveComplete();
setTimeout(()=>writeInFlight.delete(id), 2000);
showToast(`Renamed "${oldName}" → "${newNameTrimmed}"`, 'success', 3000, () => renamePlayer(newNameTrimmed, oldName));
})
.catch(e =>{
notifySaveComplete();
writeInFlight.delete(id);
showFirebaseError('Rename failed: ' + e.message);
});
renderPlayerPool(); renderPlayerMgmt(); renderPlayerButtons(); renderTeams(); renderAnswerLog(); renderStatistics(); }
function startMergePlayer(player1){
const s = getCurrentSession();
if(!s?.players) return;
const otherPlayers = Object.keys(s.players).filter(p => p !== player1).sort();
if(otherPlayers.length === 0){ showToast('No other players to merge with.','warn'); return; }
const modal = $('playerActionModal');
const title = $('pamTitle');
const body  = $('pamBody');
if(!modal||!title||!body) return;
title.textContent = 'Merge Players';
const opts = otherPlayers.map(p => `<option value="${p.replace(/"/g,'&quot;')}">${p}</option>`).join('');
body.innerHTML = `
<p style="font-size:.85em;color:var(--text2);margin-bottom:12px;">
Merge <strong>${player1}</strong> into another player. All answers and points will be combined. This can be undone.
</p>
<label style="font-size:.85em;font-weight:600;color:var(--text2);display:block;margin-bottom:6px;">Search &amp; select player to merge into</label>
<input id="pamMergeSearch" type="text" placeholder="Type to filter..."
style="width:100%;padding:8px 12px;border:1.5px solid var(--input-border);border-radius:var(--radius-sm) var(--radius-sm) 0 0;border-bottom:none;font-size:.9em;font-family:inherit;background:var(--input-bg);color:var(--input-text);box-sizing:border-box;"
oninput="filterMergeList()" />
<select id="pamMergeSelect" size="5"
style="width:100%;padding:4px;border:1.5px solid var(--input-border);border-radius:0 0 var(--radius-sm) var(--radius-sm);font-size:.9em;font-family:inherit;background:var(--input-bg);color:var(--input-text);box-sizing:border-box;margin-bottom:14px;">${opts}</select>
<div style="display:flex;gap:8px;">
<button class="button button-success" style="flex:1;" onclick="confirmMergePlayer('${player1.replace(/'/g,"\'")}')">Merge</button>
<button class="button" style="flex:1;background:var(--sec-bg);color:var(--text2);" onclick="closePlayerActionModal()">Cancel</button>
</div>`;
modal.style.display = 'flex';
setTimeout(()=>$('pamMergeSearch')?.focus(), 50); }
function filterMergeList(){
const q = ($('pamMergeSearch')?.value || '').toLowerCase();
const sel = $('pamMergeSelect');
if(!sel) return;
Array.from(sel.options).forEach(o =>{
o.style.display = o.text.toLowerCase().includes(q) ? '' : 'none'; }); }
function confirmMergePlayer(player1){
const sel = $('pamMergeSelect');
if(!sel) return;
const player2 = sel.value;
if(!player2){ showToast('Select a player to merge into.','warn'); return; }
closePlayerActionModal();
mergePlayers(player1, player2); }
function closePlayerActionModal(){
const m = $('playerActionModal');
if(m) m.style.display = 'none'; }
function fuzzyPlayerMatch(name, candidates){
// Exact match first
if(candidates.includes(name)) return name;
const nl = name.toLowerCase().trim();
// Case-insensitive exact
const ci = candidates.find(c => c.toLowerCase().trim() === nl);
if(ci) return ci;
// First name match
const firstName = nl.split(/\s+/)[0];
const fnMatch = candidates.find(c => c.toLowerCase().trim().split(/\s+/)[0] === firstName);
if(fnMatch) return fnMatch;
// One contains the other
const containsMatch = candidates.find(c => c.toLowerCase().includes(nl) || nl.includes(c.toLowerCase().trim()));
if(containsMatch) return containsMatch;
return null; }
function mergePlayers(player1, player2){
const id = state.currentSessionId;
if(!id) return;
const s = getCurrentSession();
const allPlayers = Object.keys(s?.players || {});
const resolved1 = fuzzyPlayerMatch(player1, allPlayers) || player1;
const resolved2 = fuzzyPlayerMatch(player2, allPlayers) || player2;
const p1Data = s?.players?.[resolved1];
const p2Data = s?.players?.[resolved2];
if(!p1Data || !p2Data){ showToast('Could not find both players to merge.','warn'); return; }
const mergedData = {
name: resolved2,
answers: [...(p1Data.answers || []), ...(p2Data.answers || [])]
.filter(isPlayerPerformanceAnswer),
points: [...(p1Data.answers || []), ...(p2Data.answers || [])].filter(isPlayerPerformanceAnswer).reduce((sum, a) => sum + (a.points || 0), 0)
};
// Mutate local state immediately
s.players[resolved2] = JSON.parse(JSON.stringify(mergedData));
delete s.players[resolved1];
(s.teams || []).forEach(t =>{
if(t.playerMembers){
const idx = t.playerMembers.indexOf(resolved1);
if(idx !== -1){
t.playerMembers.splice(idx, 1);
if(!t.playerMembers.includes(resolved2)) t.playerMembers.push(resolved2); }
}
});
(s.answerLog || []).forEach(a =>{ if(a.player === resolved1) a.player = resolved2; });
if(s.answers) Object.values(s.answers).forEach(a =>{ if(a.player === resolved1) a.player = resolved2; });
s.lastUpdated = new Date().toISOString();
s.updatedBy = clientId;
writeInFlight.add(id);
notifySaveStart();
Promise.all([
sessionsRef.child(id).set(s),
globalPlayersRef.child(resolved1).remove()
])
.then(()=>{
notifySaveComplete();
setTimeout(()=>writeInFlight.delete(id), 2000);
showToast(`Merged "${resolved1}" into "${resolved2}"`, 'success', 4000, () => splitPlayers(resolved1, resolved2, p1Data, p2Data));
})
.catch(e =>{
notifySaveComplete();
writeInFlight.delete(id);
showFirebaseError('Merge failed: ' + e.message);
});
renderPlayerPool(); renderPlayerMgmt(); renderPlayerButtons(); renderTeams(); renderAnswerLog(); renderStatistics(); }
function splitPlayers(player1, player2, p1Data, p2Data){
const id = state.currentSessionId;
if(!id) return;
updateSessionAtomic(id, s =>{
if(s.players?.[player2]){
s.players[player1] = p1Data;
s.players[player2] = p2Data;
(s.answerLog || []).forEach(a =>{
if(a.player === player2 && p1Data.answers.some(ans => ans === a)) a.player = player1;
});
if(s.answers){
Object.keys(s.answers).forEach(key =>{
if(s.answers[key].player === player2 && p1Data.answers.some(ans => ans === s.answers[key])){
s.answers[key].player = player1; }
}); }
}
});
withWriteLock(id, () =>{
const s = getCurrentSession();
if(!s?.players) return;
s.players[player1] = p1Data;
s.players[player2] = p2Data; });
renderPlayerPool();
renderPlayerMgmt();
renderPlayerButtons();
renderTeams();
renderAnswerLog();
renderStatistics(); }
function renderPlayerPool(){
const s  = getCurrentSession();
const el = $('playerPoolDisplay');
if (!el || !s) return;
const players = Object.keys(s.players ||{});
el.innerHTML = players.length
? players.map(p =>
`<span class="player-pool-item">${p}<span class="remove" onclick="removeFromPlayerPool('${p}')">&#215;</span></span>`
).join('') :'<p class="text-2">No players added yet.</p>'; }
function getDisplayName(full,all){
const parts=full.trim().split(/\s+/),first=parts[0];
return (all.some(n=>n!==full&&n.trim().split(/\s+/)[0]===first)&&parts.length>1)?first+' '+parts[parts.length-1][0]+'.':first;
}
function renderPlayerButtons(){
const s = getCurrentSession();
const el = $('playerButtonsContainer');
if (!el || !s) return;
const teams = (s.teams || []).filter(t => (t.playerMembers || []).length > 0);
if (!teams.length){ el.innerHTML = '<p class="text-2">No teams configured yet.</p>'; return; }
const allPlayers = Object.keys(s.players || {});
const isBonus = state.selectedPointType === 'Bonus';
let html = '';
teams.forEach(team =>{
const teamSentinel = '__team__' + team.id;
if (isBonus){
const teamSel = state.selectedPlayer === teamSentinel;
html += `<button class="button-player${teamSel ? ' selected' : ''}" onclick="selectPlayer('${teamSentinel.replace(/'/g,"\\'")}');" style="font-weight:800;width:100%;text-align:left;opacity:1;border-style:dashed;" title="Record this bonus for ${team.name}">${team.name} — Team Bonus</button>`;
return;
}
html += `<div class="fs-7-fw8-upper">${team.name}</div>`;
(team.playerMembers || []).forEach(player =>{
const disp = getDisplayName(player, allPlayers);
const sel = state.selectedPlayer === player ? ' selected' : '';
html += `<button class="button-player${sel}" onclick="selectPlayer('${player.replace(/'/g,"\\'")}');" title="${player}">${disp}</button>`;
});
});
el.innerHTML = html;
}
