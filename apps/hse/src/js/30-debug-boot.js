function injectDebugData(){
const s = getCurrentSession(); if (!s){ showToast('No active session.', 'warn'); return; }
const scenario = $('debugScenario')?.value || 'mid';
const statusEl = $('debugStatus');
const team1Players = ['Alex Carter', 'Jordan Lee', 'Sam Rivera', 'Morgan Chen'];
const team2Players = ['Taylor Brooks', 'Casey Kim', 'Riley Patel', 'Drew Nguyen'];
const allPlayers   = [...team1Players, ...team2Players];
const cats = DEFAULT_CATEGORIES;
const rng = (arr) => arr[Math.floor(Math.random() * arr.length)];
const profiles ={
'Alex Carter':{power:25,tossup:40,bonus:20,neg:8, miss:7},
'Jordan Lee':{power:10,tossup:35,bonus:25,neg:10,miss:20},
'Sam Rivera':{power:5, tossup:25,bonus:20,neg:5, miss:45},
'Morgan Chen':{power:15,tossup:35,bonus:20,neg:12,miss:18},
'Taylor Brooks':{power:20,tossup:38,bonus:20,neg:10,miss:12},
'Casey Kim':{power:8, tossup:30,bonus:22,neg:8, miss:32},
'Riley Patel':{power:6, tossup:28,bonus:18,neg:6, miss:42},
'Drew Nguyen':{power:12,tossup:32,bonus:20,neg:15,miss:21},
};
const pointMap ={ 'Power':15, 'Toss-up':10, 'Bonus':10, 'Neg':-5, 'Miss':0, 'Dead':0 };
const tuHeard = scenario === 'full' ? 30 :scenario === 'blowout' ? 30 :20;
function pickType(player){
const p = scenario === 'blowout' && team2Players.includes(player)
?{ power:3, tossup:15, bonus:10, neg:18, miss:54 }  // team 2 struggles in blowout
:(profiles[player] ||{ power:10, tossup:30, bonus:20, neg:10, miss:30 });
const pool = [];
for (let i=0; i<p.power;   i++) pool.push('Power');
for (let i=0; i<p.tossup;  i++) pool.push('Toss-up');
for (let i=0; i<p.neg;     i++) pool.push('Neg');
for (let i=0; i<p.miss;    i++) pool.push('Miss');
return rng(pool); }
const log = [];
let tHeardCount = 0;
const baseTime = new Date('2025-11-01T14:00:00Z').getTime();
let t = baseTime;
const playerAnswers ={}; //{ name:[answers] }
allPlayers.forEach(n =>{ playerAnswers[n] = []; });
for (let q = 0; q < tuHeard; q++){
t += 35000 + Math.floor(Math.random() * 40000); // 35–75s per question
const buzzPool = [...allPlayers, 'Alex Carter', 'Taylor Brooks', 'Morgan Chen'];
const buzzer = rng(buzzPool);
const type = pickType(buzzer);
const cat  = rng(cats);
const ts   = new Date(t).toISOString();
const buzzAnswer ={
id:(t).toString(),
player:buzzer,
pointType:type,
category:cat,
points:pointMap[type],
timestamp:ts,
};
log.push(buzzAnswer);
playerAnswers[buzzer].push(buzzAnswer);
const isBuzz = ['Toss-up','Power','Neg','Miss','Dead'].includes(type);
if (isBuzz){
const prev = log[log.length - 2] || null;
const prevWasWrong = prev && (prev.pointType === 'Neg' || prev.pointType === 'Miss');
const isFollowup = prevWasWrong && (type === 'Toss-up' || type === 'Power');
if (!isFollowup) tHeardCount++; }
if ((type === 'Power' || type === 'Toss-up') && Math.random() < 0.65){
t += 20000 + Math.floor(Math.random() * 15000);
const bonusCat = Math.random() < 0.7 ? cat :rng(cats); // usually same category
const bonusTs  = new Date(t).toISOString();
const bonusTeam = team1Players.includes(buzzer) ? 'Team Alpha' : 'Team Beta';
const bonusAnswer ={
id:(t + 1).toString(),
player:'— ' + bonusTeam + ' Bonus —',
pointType:'Bonus',
category:bonusCat,
points:10,
timestamp:bonusTs,
};
log.push(bonusAnswer); }
}
const players ={};
allPlayers.forEach(name =>{
const answers = playerAnswers[name];
const points  = answers.reduce((sum, a) => sum + a.points, 0);
players[name] ={ name, points, answers };
});
const teams = [
{ name:'Team Alpha', playerMembers:team1Players, id:'debug-team-1' },
{ name:'Team Beta',  playerMembers:team2Players, id:'debug-team-2' },
];
const id = state.currentSessionId; void id; // kept for reference only, never written to Firebase
const sess = getCurrentSession(); if (!sess){ showToast('No session.', 'warn'); return; }
sess.players    = players;
sess.teams      = teams;
sess.answerLog  = log;
sess.tHeard     = tHeardCount;
sess.categories = [...DEFAULT_CATEGORIES];
sess.lastUpdated = new Date().toISOString();
const totalAnswers = log.length;
const totalPts = allPlayers.reduce((s, n) => s + (players[n]?.points || 0), 0);
if (statusEl) statusEl.textContent = `✔ Injected ${totalAnswers} answers across ${tuHeard} questions. ${allPlayers.length} players, 2 teams, ${totalPts} total points.`;
showToast('Debug data injected.', 'success'); }
function clearDebugData(){
showConfirm('Clear all data in the current session?', 'Clear').then(ok =>{
if (!ok) return;
const s = getCurrentSession(); if (!s) return;
s.players   ={};
s.teams     = [];
s.answerLog = [];
s.tHeard    = 0;
loadSessionData(); renderAll();
const statusEl = $('debugStatus');
if (statusEl) statusEl.textContent = '✔ Session data cleared.';
showToast('Session cleared.'); });
}
function resetAllData(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
showConfirm('Enter the admin password to proceed:', 'Verify', 'warn').then(ok =>{
if (!ok) return;
const ct = $('confirmToast');
const msgEl = $('confirmToastMsg');
const okEl  = $('confirmToastOk');
if (!ct) return;
msgEl.innerHTML = 'Admin password:<input id="resetPwInput" type="password" placeholder="Password" style="margin-top:8px;display:block;width:100%;padding:7px 10px;border:1.5px solid var(--border);border-radius:6px;font-family:inherit;font-size:.95em;background:var(--card);color:var(--text);" />';
okEl.textContent = 'Submit';
okEl.className = 'ct-ok';
ct.classList.add('show');
setTimeout(() => $('resetPwInput')?.focus(), 80);
_confirmResolve = (confirmed) =>{
_confirmResolve = null;
ct.classList.remove('show');
if (!confirmed) return;
const pw = $('resetPwInput')?.value;
if (pw !== 'Neg 5'){ showToast('Incorrect password.'); return; }
showConfirm('Delete ALL sessions and data? This cannot be undone.', 'Delete Everything').then(final =>{
if (!final) return;
sessionsRef.remove().catch(e=>showFirebaseError(e.message));
globalPlayersRef.remove().catch(e=>showFirebaseError(e.message));
localStorage.setItem(CURRENT_SESSION_KEY,'');
state.sessions={}; state.currentSessionId=null;
createNewSession(); renderAll(); });
}; });
}
document.addEventListener('DOMContentLoaded', initFirebase);