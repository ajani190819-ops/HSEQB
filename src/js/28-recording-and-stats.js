function selectPointType(type){
state.selectedPointType = state.selectedPointType === type ? null :type;
if (state.selectedPointType === 'Bonus' || (state.selectedPlayer && state.selectedPlayer.startsWith('__team__'))) state.selectedPlayer = null;
if (state.selectedPointType === 'Neg' || state.selectedPointType === 'Dead'){
state.selectedCategory = null; _selectedParentCat = null; }
renderPointTypeButtons();
renderPlayerButtons();
renderCategories();
const playerHint = $('playerOptionalHint');
if (playerHint) playerHint.style.display =
(state.selectedPointType === 'Bonus' || state.selectedPointType === 'Dead' || state.selectedPointType === 'Miss') ? 'inline' :'none';
}
function renderPointTypeButtons(){
document.querySelectorAll('.button-point-type').forEach(btn=>{
btn.classList.toggle('selected',!!state.selectedPointType&&btn.getAttribute('onclick').includes("'"+state.selectedPointType+"'"));
}); }
function renderTHeard(){
const el = $('tHeardDisplay');
if (el) el.textContent = (getCurrentSession()?.tHeard) || 0; }
function adjustTHeard(delta){
const id = state.currentSessionId; if (!id) return;
const apply = s =>{ s.tHeard = Math.max(0, (s.tHeard || 0) + delta); };
updateSessionAtomic(id, apply);
withWriteLock(id, () =>{ const s = getCurrentSession(); if (s) apply(s); });
renderTHeard();
if (analyticsOpen) renderAnalytics(); }
function recordAnswer(){
const id = state.currentSessionId; if (!id) return;
const isBonus = state.selectedPointType === 'Bonus';
const isDead  = state.selectedPointType === 'Dead';
const isMiss = state.selectedPointType === 'Miss';
if (!state.selectedPointType){ showToast('Please select a point type.'); return; }
if (isBonus && (!state.selectedPlayer || !state.selectedPlayer.startsWith('__team__'))){ showToast('Select a team for the bonus. Bonuses are recorded for the team, not an individual.'); return; }
if (!state.selectedPlayer && !isBonus && !isDead && !isMiss){ showToast('Please select a player.'); return; }
const isTeamBonus = isBonus && state.selectedPlayer && state.selectedPlayer.startsWith('__team__');
const teamBonusId = isTeamBonus ? state.selectedPlayer.replace('__team__','') :null;
const s0 = getCurrentSession();
const bonusTeam = teamBonusId ? (s0.teams||[]).find(t => t.id === teamBonusId) :null;
const recordedPlayer = isTeamBonus
? ('— ' + (bonusTeam ? bonusTeam.name :'Team') + ' Bonus —')
:(state.selectedPlayer || (isMiss ? '— Miss —' :'— Team Bonus —'));
const pointMap ={'Toss-up':10,'Bonus':10,'Neg':-5,'Power':15,'Miss':0,'Dead':0};
const points   = pointMap[state.selectedPointType];
const isBuzzIn = ['Toss-up','Power','Neg','Miss','Dead'].includes(state.selectedPointType);
const effectiveCategory = state.selectedCategory || _selectedParentCat || '—';
const answer ={id:Date.now().toString(),player:recordedPlayer,pointType:state.selectedPointType,category:effectiveCategory,points,timestamp:new Date().toISOString()};
const applyAnswer = s =>{
s.answerLog = toArray(s.answerLog);
if (isBuzzIn){
const prev = s.answerLog.length > 0 ? s.answerLog[s.answerLog.length - 1] :null;
const prevWasWrong = prev && (prev.pointType === 'Neg' || prev.pointType === 'Miss');
const thisIsFollowup = prevWasWrong && (state.selectedPointType === 'Toss-up' || state.selectedPointType === 'Power');
if (!thisIsFollowup) s.tHeard = (s.tHeard || 0) + 1; }
s.answerLog.push(answer);
if (!s.players) s.players ={};
const realPlayer = isPlayerPerformanceAnswer(answer) && !isTeamBonus && state.selectedPlayer && !state.selectedPlayer.startsWith('— ');
if (realPlayer){
const p = s.players[answer.player] || (s.players[answer.player] ={name:answer.player,points:0,answers:[]});
p.answers = toArray(p.answers); p.answers.push(answer); p.points = (p.points||0) + points;
}
if (isBonus && !realPlayer){ s.teamBonusPoints = (s.teamBonusPoints || 0) + points; }
};
updateSessionAtomic(id, applyAnswer);
withWriteLock(id, () =>{ const s = getCurrentSession(); if (s) applyAnswer(s); });
const allP = Object.keys((s0||{}).players ||{});
const dispName = isTeamBonus
? (bonusTeam ? bonusTeam.name + ' Bonus' :'Team Bonus')
:(state.selectedPlayer ? getDisplayName(state.selectedPlayer, allP) :'Team');
const ptSign   = points > 0 ? '+'+points :(points < 0 ? ''+points :'0');
const toastCls = state.selectedPointType === 'Neg' ? 'neg'
:(state.selectedPointType === 'Miss' || state.selectedPointType === 'Dead') ? 'miss' :points >= 15 ? 'pts' :'';
showRecordToast(dispName + ' — ' + state.selectedPointType + ' (' + ptSign + ' pts)', toastCls);
state.selectedPlayer = null; state.selectedPointType = null; state.selectedCategory = null; _selectedParentCat = null;
const playerHint = $('playerOptionalHint');
if (playerHint) playerHint.style.display = 'none';
renderAll(); }
document.addEventListener('keydown', e =>{
const tag = document.activeElement && document.activeElement.tagName;
if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;
if (document.activeElement && document.activeElement.isContentEditable) return;
const keyMap ={'1':'Power','2':'Toss-up','3':'Bonus','4':'Miss','5':'Neg','6':'Dead'};
if (keyMap[e.key]){
e.preventDefault();
selectPointType(keyMap[e.key]);
} else if (e.key === 'Enter'){
const btn = $('recordAnswerBtn');
if (btn && btn.offsetParent !== null){ e.preventDefault(); recordAnswer(); }
}
});
function recordTeamBonus(teamId){
const id = state.currentSessionId; if (!id) return;
const s0 = getCurrentSession(); if (!s0) return;
const team = (s0.teams||[]).find(t => t.id === teamId);
const label = '— ' + (team ? team.name :'Team') + ' Bonus —';
const answer ={id:Date.now().toString(),player:label,pointType:'Bonus',category:'—',points:10,timestamp:new Date().toISOString()};
const apply = s =>{
s.answerLog = toArray(s.answerLog); s.answerLog.push(answer);
s.teamBonusPoints = (s.teamBonusPoints||0) + 10; };
updateSessionAtomic(id, apply);
withWriteLock(id, () =>{ const s = getCurrentSession(); if (s) apply(s); });
showRecordToast((team ? team.name :'Team') + ' Bonus (+10 pts)', '');
renderAll(); }
function deleteAnswer(answerId){
const id=state.currentSessionId; if(!id) return;
const del=s=>{
s.answerLog=toArray(s.answerLog);
const idx = s.answerLog.findIndex(x=>x.id===answerId);
if(idx === -1) return;
const a = s.answerLog[idx];
const isBuzzIn = ['Toss-up','Power','Neg','Miss','Dead'].includes(a.pointType);
if (isBuzzIn){
const prev = idx > 0 ? s.answerLog[idx - 1] :null;
const prevWasWrong = prev && (prev.pointType === 'Neg' || prev.pointType === 'Miss');
const wasFollowup = prevWasWrong && (a.pointType === 'Toss-up' || a.pointType === 'Power');
if (!wasFollowup){ s.tHeard = Math.max(0, (s.tHeard || 0) - 1); }
}
s.answerLog = s.answerLog.filter(x=>x.id!==answerId);
if (isTeamBonusAnswer(a)){
s.teamBonusPoints = Math.max(0, (s.teamBonusPoints || 0) - (a.points || 0));
// Remove legacy player-attributed bonus rows from the player’s stored mirror too.
if (s.players?.[a.player]){
s.players[a.player].answers = toArray(s.players[a.player].answers).filter(x => x.id !== answerId);
s.players[a.player].points = s.players[a.player].answers.filter(isPlayerPerformanceAnswer).reduce((sum, x) => sum + (x.points || 0), 0);
}
} else if(s.players?.[a.player]){
s.players[a.player].answers=toArray(s.players[a.player].answers).filter(x=>x.id!==answerId);
s.players[a.player].points=s.players[a.player].answers.filter(isPlayerPerformanceAnswer).reduce((sum, x) => sum + (x.points || 0), 0);
}
};
updateSessionAtomic(id,del);
withWriteLock(id,()=>{const s=getCurrentSession();if(s) del(s);});
renderAll(); }
function clearAnswerLog(){
showConfirm('Clear all answers?', 'Clear').then(ok =>{
if (!ok) return;
const id=state.currentSessionId; if(!id) return;
const clear=s=>{s.answerLog=[];s.tHeard=0;s.teamBonusPoints=0;Object.values(s.players||{}).forEach(p=>{p.points=0;p.answers=[];});};
updateSessionAtomic(id,clear);
withWriteLock(id,()=>{const s=getCurrentSession();if(s) clear(s);});
renderAll(); });
}
function renderAnswerLog(){
const s=getCurrentSession(); const el=$('answerLog');
if(!el||!s) return;
const answers=s.answerLog||[];
el.innerHTML=answers.length
?[...answers].reverse().map((a,i)=>`
<div class="log-entry">
<span><strong>${answers.length-i}. ${answerActorLabel(a) === 'Dead TU' ? '<span class="text-3">Dead TU</span>' : isTeamBonusAnswer(a) ? '<span class="warning">' + answerActorLabel(a) + '</span>' : answerActorLabel(a)}</strong> &mdash; ${a.pointType==='Power'?'TU ⚡︎ Power':a.pointType} (${a.points>0?'+':''}${a.points} Pts) &mdash; ${a.category}</span>
<button class="button button-danger" onclick="deleteAnswer('${a.id}')" style="padding:4px 8px;font-size:.8em;">Delete</button>
</div>`).join('') :'<p class="text-2">No answers recorded yet.</p>';
el.onscroll=updateFadeMasks;
setTimeout(updateFadeMasks,20); }
function calculatePlayerStats(){
return Object.values(getCurrentSession()?.players || {}).map(p =>{
const a = toArray(p.answers).filter(isPlayerPerformanceAnswer);
const points = a.reduce((sum, answer) => sum + (answer.points || 0), 0);
return { name:p.name, points, totalAnswers:a.length, tossupsCorrect:a.filter(x => x.pointType === 'Toss-up').length, bonusPoints:0, negs:a.filter(x => x.pointType === 'Neg').length, misses:a.filter(x => x.pointType === 'Miss').length, powers:a.filter(x => x.pointType === 'Power').length };
}).sort((a,b) => b.points !== a.points ? b.points - a.points : b.powers !== a.powers ? b.powers - a.powers : a.negs - b.negs);
}
function calculateTeamStats(){
const s = getCurrentSession();
return (s?.teams || []).map(team =>{
let pts = 0, ans = 0;
(team.playerMembers || []).forEach(name =>{
const p = s.players?.[name];
if (!p) return;
const performanceAnswers = toArray(p.answers).filter(isPlayerPerformanceAnswer);
pts += performanceAnswers.reduce((sum, a) => sum + (a.points || 0), 0);
ans += performanceAnswers.length;
});
const bonusAnswers = toArray(s.answerLog).filter(a => isTeamBonusAnswer(a) && (!a.player || a.player === '— Team Bonus —' || typeof a.player === 'string' && a.player.includes(team.name + ' Bonus') || (team.playerMembers || []).includes(a.player)));
pts += bonusAnswers.reduce((sum, a) => sum + (a.points || 0), 0);
ans += bonusAnswers.length;
return { name:team.name, totalPoints:pts, totalAnswers:ans, members:team.playerMembers || [], averagePerMember:team.playerMembers?.length ? (pts / team.playerMembers.length).toFixed(2) : 0 };
}).sort((a,b) => b.totalPoints - a.totalPoints);
}
function buildRankingList(players){
let html='',rank=1;
players.forEach((s,i)=>{
const prev=players[i-1];
const tied=prev&&prev.points===s.points&&prev.powers===s.powers&&prev.negs===s.negs;
if(i>0&&!tied) rank=i+1;
const sfx=['st','nd','rd'][rank-1]||'th';
html+=`<li style="padding:6px 0;border-bottom:1.5px solid var(--border);display:flex;justify-content:space-between;align-items:center;"><span><strong style="color:var(--primary);min-width:42px;display:inline-block;">${rank}${sfx}</strong> ${s.name}</span><span style="color:var(--text2);font-size:.92em;">${s.points} Pts${s.powers?' &middot; '+s.powers+'⚡︎ Powered':''}${s.negs?' &middot; '+'-'+s.negs+' Neg':''}${s.misses?' &middot; '+s.misses+' Miss':''}</span></li>`;
});
return html; }
function renderStatistics(){
const el=$('statisticsContainer'); if(!el) return;
const open=new Set();
el.querySelectorAll('.stat-card:not(.collapsed),.team-stat-card:not(.collapsed)').forEach(c=>{const n=c.querySelector('.player-name,.team-name');if(n) open.add(n.textContent.trim());});
const ps=calculatePlayerStats(),ts=calculateTeamStats(),active=ps.filter(s=>s.totalAnswers>0);
let html='<div class="stats-grid">';
ts.forEach(t=>{html+=`<div class="team-stat-card collapsed"><h3 onclick="toggleStatCard(event)"><span class="team-name">${t.name}</span><span class="team-score">${t.totalPoints} Pts</span></h3><div class="stat-details"><div class="stat-row"><span class="stat-label">Total Points:</span><span class="stat-value">${t.totalPoints}</span></div><div class="stat-row"><span class="stat-label">Recorded Events:</span><span class="stat-value">${t.totalAnswers}</span></div><div class="stat-row"><span class="stat-label">Avg per Member:</span><span class="stat-value">${t.averagePerMember}</span></div><div class="stat-row"><span class="stat-label">Members:</span><span>${t.members.join(', ')||'None'}</span></div></div></div>`;});
if(active.length){
active.forEach(s=>{html+=`<div class="stat-card collapsed"><h3 onclick="toggleStatCard(event)"><span class="player-name">${s.name}</span><span class="player-score">${s.points} Pts</span></h3><div class="stat-details"><div class="stat-row"><span class="stat-label">Total Points:</span><span class="stat-value">${s.points}</span></div><div class="stat-row"><span class="stat-label">Answers:</span><span class="stat-value">${s.totalAnswers}</span></div><div class="stat-row"><span class="stat-label">Toss-ups:</span><span class="stat-value">${s.tossupsCorrect+s.powers}${s.powers?` (${s.powers}⚡︎)`:''}</span></div><div class="stat-row"><span class="stat-label">Negs:</span><span class="stat-value">${s.negs}</span></div><div class="stat-row"><span class="stat-label">Misses:</span><span class="stat-value">${s.misses}</span></div></div></div>`;});
html+=`<div class="overall-ranking"><h3 style="margin-top:0;">Player Rankings</h3><ol style="list-style:none;margin:12px 0 0;padding:0;">${buildRankingList(active)}</ol></div>`;
} else{html+='<p class="text-2">No statistics available yet.</p>';}
html+='</div>';
el.innerHTML=html;
if(open.size){el.querySelectorAll('.stat-card,.team-stat-card').forEach(c=>{const n=c.querySelector('.player-name,.team-name');if(n&&open.has(n.textContent.trim())) c.classList.remove('collapsed');});}
}
function toggleStatCard(e){e.currentTarget.closest('.stat-card,.team-stat-card')?.classList.toggle('collapsed');}
