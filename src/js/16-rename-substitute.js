function renamePlayer(oldName){
const input = $('renamePlayerInput');
const newName = (input?.value || '').trim();
if (!newName){ showToast('Enter a new name.'); return; }
if (newName === oldName){ showToast('Name is the same.', 'warn'); return; }
Object.values(state.sessions).forEach(sess =>{
if (sess.players?.[oldName]){
sess.players[newName] ={ ...sess.players[oldName], name:newName };
delete sess.players[oldName]; }
(sess.answerLog || []).forEach(a =>{ if (a.player === oldName) a.player = newName; });
(sess.teams || []).forEach(t =>{ t.playerMembers = (t.playerMembers || []).map(p => p === oldName ? newName :p); });
});
saveAllData();
globalPlayersRef.once('value').then(snap =>{
const gp = snap.val() ||{};
if (gp[oldName]){
gp[newName] ={ ...gp[oldName], name:newName };
delete gp[oldName];
globalPlayersRef.set(gp).catch(e => showFirebaseError(e.message)); }
});
renderAll();
closePlayerDetailModal();
showToast('Renamed to ' + newName, 'success'); }
function executeSubstitution(outPlayer, inPlayer){
const id = state.currentSessionId; if (!id) return;
const apply = s =>{
(s.teams||[]).forEach(t =>{
const members = t.playerMembers || [];
const idx = members.indexOf(outPlayer);
if (idx > -1){
members.splice(idx, 1, inPlayer);
t.playerMembers = members; }
});
if (!s.players) s.players ={};
if (!s.players[inPlayer]) s.players[inPlayer] ={ name:inPlayer, points:0, answers:[] };
};
updateSessionAtomic(id, apply);
withWriteLock(id, () =>{ const s = getCurrentSession(); if (s) apply(s); });
if (state.selectedPlayer === outPlayer) state.selectedPlayer = null;
closeSubModal();
renderAll();
const notify = document.createElement('div');
notify.textContent = `✔ ${inPlayer} in for ${outPlayer}`;
notify.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:var(--success);color:#fff;padding:10px 20px;border-radius:10px;font-weight:700;font-size:.92em;z-index:9999;pointer-events:none;box-shadow:0 4px 16px rgba(0,0,0,.25);';
document.body.appendChild(notify);
setTimeout(() => notify.remove(), 2800); }
