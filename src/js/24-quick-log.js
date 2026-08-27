let _subOut = null, _subIn = null;
let _qlPending = null; //{ player, type, cat } waiting for optional category
function renderQuickLog(){
const el = $('quickLogContainer');
const s = getCurrentSession();
if (!el || !s) return;
const players = [...new Set((s.teams || []).flatMap(t => t.playerMembers || []))];
const teams = (s.teams || []).filter(t => (t.playerMembers || []).length > 0);
if (!players.length){ el.innerHTML = '<p style="color:var(--text2);font-size:.85em;margin-bottom:10px;">Add players to a team to use quick-log.</p>'; return; }
const allPlayers = Object.keys(s.players || {});
const cats = s.categories || [];
const hasCats = cats.length > 0;
const teamBonusButtons = teams.map(team => `<button class="ql-team-bonus" onclick="recordTeamBonus('${team.id}')" title="Record a team bonus for ${team.name}">★ ${team.name} Bonus +10</button>`).join('');
const playerRows = players.map(player =>{
const disp = getDisplayName(player, allPlayers);
const safe = player.replace(/'/g,"\\'");
const pid = 'ql_' + player.replace(/[^a-zA-Z0-9]/g,'_');
const pending = _qlPending && _qlPending.player === player;
const catRowOpen = pending && hasCats ? 'open' : '';
const catChips = hasCats ? cats.slice(0,16).map(c =>{
const cSafe = c.replace(/'/g,"\\'");
const selected = pending && _qlPending.cat === c ? 'selected' : '';
return `<span class="ql-cat-chip ${selected}" onclick="qlSelectCat('${safe}','${cSafe}')">${c}</span>`;
}).join('') + `<button class="ql-confirm-btn" onclick="qlConfirm('${safe}')">✔ Log</button><button class="ql-cancel-btn" onclick="qlCancel()">✕</button>` : '';
const pendingTag = pending ? `<span style="font-size:.68em;font-weight:700;color:var(--primary);margin-left:3px;white-space:nowrap;">${_qlPending.type}</span>` : '';
return `<div class="ql-row" id="${pid}_row"><div class="ql-name" title="${player}">${disp}${pendingTag}</div><div class="ql-btns"><button class="ql-btn ql-power" onclick="qlTap('${safe}','Power')" title="Toss-up ⚡︎ Power (+15)">⚡︎<br>+15</button><button class="ql-btn ql-tu" onclick="qlTap('${safe}','Toss-up')" title="Toss-up (+10)">✔<br>+10</button><button class="ql-btn ql-miss" onclick="qlTap('${safe}','Miss')" title="Miss (0)">○<br>0</button><button class="ql-btn ql-neg" onclick="qlTap('${safe}','Neg')" title="Neg (−5)">✗<br>−5</button></div></div><div class="ql-cat-row ${catRowOpen}" id="${pid}_cats">${catChips}</div>`;
}).join('');
el.innerHTML = `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:10px;">${teamBonusButtons}</div>${playerRows}`;
}
function qlTap(player, type){
const s = getCurrentSession();
const hasCats = s && (s.categories||[]).length > 0;
if (hasCats){
_qlPending ={ player, type, cat:null };
renderQuickLog();
} else{
qlQuickRecord(player, type, null); }
}
function qlSelectCat(player,cat){ if(_qlPending&&_qlPending.player===player){_qlPending.cat=_qlPending.cat===cat?null:cat;renderQuickLog();} }
function qlConfirm(player){
if (!_qlPending || _qlPending.player !== player) return;
qlQuickRecord(_qlPending.player, _qlPending.type, _qlPending.cat); }
function qlCancel(){ _qlPending = null; renderQuickLog(); }
function qlQuickRecord(player, type, cat){
_qlPending = null;
const id = state.currentSessionId; if (!id) return;
const pointMap ={'Toss-up':10,'Bonus':10,'Neg':-5,'Power':15,'Miss':0,'Dead':0};
const points   = pointMap[type];
const isBuzzIn = ['Toss-up','Power','Neg','Miss','Dead'].includes(type);
const recordedPlayer = type === 'Bonus' ? '— Team Bonus —' : player;
const effectiveCategory = cat || '—';
const answer ={id:Date.now().toString(),player:recordedPlayer,pointType:type,category:effectiveCategory,points,timestamp:new Date().toISOString()};
const applyAnswer = s =>{
s.answerLog = toArray(s.answerLog);
if (isBuzzIn){
const prev = s.answerLog.length > 0 ? s.answerLog[s.answerLog.length-1] :null;
const prevWasWrong = prev && (prev.pointType === 'Neg' || prev.pointType === 'Miss');
const thisIsFollowup = prevWasWrong && (type === 'Toss-up' || type === 'Power');
if (!thisIsFollowup) s.tHeard = (s.tHeard||0) + 1; }
s.answerLog.push(answer);
if (!s.players) s.players ={};
if (isPlayerPerformanceAnswer(answer) && player){
const pl = s.players[player] || (s.players[player] = {name:player,points:0,answers:[]});
pl.answers = toArray(pl.answers); pl.answers.push(answer); pl.points = pl.answers.filter(isPlayerPerformanceAnswer).reduce((sum, x) => sum + (x.points || 0), 0);
}
if (isTeamBonusAnswer(answer)) s.teamBonusPoints = (s.teamBonusPoints || 0) + points; };
updateSessionAtomic(id, applyAnswer);
withWriteLock(id, ()=>{ const s=getCurrentSession(); if(s) applyAnswer(s); });
const s2 = getCurrentSession();
const allP = s2 ? Object.keys(s2.players||{}) :[];
const dispName = player ? getDisplayName(player, allP) :'Team';
const ptSign   = points > 0 ? '+'+points :(points < 0 ? ''+points :'0');
const toastCls = type === 'Neg' ? 'neg' :(type === 'Miss' || type === 'Dead' ? 'miss' :(points >= 15 ? 'pts' :''));
showRecordToast(dispName + ' — ' + type + ' (' + ptSign + ' pts)', toastCls);
renderAll(); }
