function importFromJSON(event){
const file=event.target.files[0]; if(!file) return;
const statusEl=$('importStatus');
statusEl.style.display='block'; statusEl.style.color='var(--text2)'; statusEl.textContent='Reading file…';
const reader=new FileReader();
reader.onload=e=>{
try{
const data=JSON.parse(e.target.result);
if(!data.sessionName||(!data.players&&!data.answerLog)) throw new Error('Not a valid export.');
const existingId=Object.keys(state.sessions).find(id=>state.sessions[id].name===data.sessionName);
const doImport = () =>{
const sid=existingId||Date.now().toString();
const imported={id:sid,name:data.sessionName,created:data.created||new Date().toISOString(),lastUpdated:new Date().toISOString(),players:data.players||{},teams:data.teams||[],categories:data.categories||[],answers:data.answers||[],answerLog:data.answerLog||[]};
Object.keys(imported.players).forEach(name=>{imported.players[name].answers=imported.answerLog.filter(a=>a.player===name);imported.players[name].points=imported.players[name].answers.filter(isPlayerPerformanceAnswer).reduce((s,a)=>s+(a.points||0),0);});
state.sessions[sid]=imported; state.currentSessionId=sid;
loadSessionData(); saveAllData(); renderAll();
statusEl.style.color='var(--success)'; statusEl.textContent='Imported "'+imported.name+'" with '+imported.answerLog.length+' answers.';
};
if(existingId){
showConfirm('Session "'+data.sessionName+'" exists. Overwrite?','Overwrite','warn').then(ok=>{
if(!ok){statusEl.textContent='Cancelled.';event.target.value='';return;}
doImport(); });
} else{ doImport(); }
} catch(err){statusEl.style.color='var(--danger)';statusEl.textContent='Import failed:'+err.message;}
event.target.value=''; };
reader.onerror=()=>{statusEl.style.color='var(--danger)';statusEl.textContent='Failed to read file.';};
reader.readAsText(file); }
function exportToExcel(){
const s=getCurrentSession(); if(!s) return;
const ps=calculatePlayerStats(),ts=calculateTeamStats(),csv=[];
if($('exportPlayers').classList.contains('selected')){csv.push('Player Statistics','Player Name,Total Toss-up Points,Total Decisions,Correct TUs,Powered TUs,Negs,Misses');ps.forEach(p=>csv.push([p.name,p.points,p.totalAnswers,p.powers+p.tossupsCorrect,p.powers,p.negs,p.misses].join(',')));csv.push('');}
if($('exportTeamStats').classList.contains('selected')&&ts.length){csv.push('Team Statistics','Team Name,Total Points,Total Answers,Members');ts.forEach(t=>csv.push([t.name,t.totalPoints,t.totalAnswers,'"'+t.members.join(', ')+'"'].join(',')));csv.push('');}
if($('exportAnswerLog').classList.contains('selected')){csv.push('Answer Log','Player,Point Type,Category,Points,Timestamp');(s.answerLog||[]).forEach(a=>csv.push([a.player,a.pointType,a.category,a.points,new Date(a.timestamp).toLocaleString()].join(',')));}
downloadFile(csv.join('\n'),'quiz-bowl-'+s.name+'-'+new Date().toISOString().split('T')[0]+'.csv','text/csv');
}
function exportAllData(format){
const allSessions = Object.values(state.sessions||{});
if (!allSessions.length){ showToast('No data to export.', 'warn'); return; }
const date = new Date().toISOString().split('T')[0];
if (format === 'json'){
const payload = { exportedAt: new Date().toISOString(), sessions: allSessions };
downloadFile(JSON.stringify(payload, null, 2), 'hse-qb-all-sessions-'+date+'.json', 'application/json');
showToast('All sessions exported as JSON.', 'success');
} else if (format === 'xlsx'){
if (typeof XLSX === 'undefined'){ showToast('Excel library not loaded yet — try again.', 'warn'); return; }
const wb = XLSX.utils.book_new();
// Sheet 1: Answer Log (all sessions)
const logRows = [['Session','Player','Point Type','Category','Points','Timestamp']];
allSessions.forEach(s =>{
(s.answerLog||[]).forEach(a =>{
logRows.push([s.name||'', a.player||'', a.pointType||'', a.category||'', a.points, new Date(a.timestamp).toLocaleString()]);
});
});
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(logRows), 'Answer Log');
// Sheet 2: Player Stats (per session)
const playerRows = [['Session','Player','Toss-up Points','Total Decisions','Correct TUs','Powered TUs','Negs','Misses']];
allSessions.forEach(s =>{
Object.values(s.players||{}).forEach(p =>{
const ans = toArray(p.answers).filter(isPlayerPerformanceAnswer);
const tossupPoints = ans.reduce((sum,a) => sum + (a.points || 0), 0);
playerRows.push([
s.name||'', p.name||'', tossupPoints,
ans.length,
ans.filter(a=>a.pointType==='Toss-up'||a.pointType==='Power').length,
ans.filter(a=>a.pointType==='Power').length,
ans.filter(a=>a.pointType==='Neg').length,
ans.filter(a=>a.pointType==='Miss').length
]);
});
});
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(playerRows), 'Player Stats');
// Sheet 3: Session Summary
const summaryRows = [['Session','Created','Answer Count','Toss-Ups Heard']];
allSessions.forEach(s =>{
summaryRows.push([s.name||'', s.created ? new Date(s.created).toLocaleString() : '', (s.answerLog||[]).length, s.tHeard||0]);
});
XLSX.utils.book_append_sheet(wb, XLSX.utils.aoa_to_sheet(summaryRows), 'Session Summary');
XLSX.writeFile(wb, 'hse-qb-all-sessions-'+date+'.xlsx');
showToast('All sessions exported as Excel.', 'success');
} else {
const rows = ['Session,Player,Point Type,Category,Points,Timestamp'];
allSessions.forEach(s =>{
(s.answerLog||[]).forEach(a =>{
rows.push([
'"'+(s.name||'').replace(/"/g,'""')+'"',
'"'+(a.player||'').replace(/"/g,'""')+'"',
a.pointType, '"'+(a.category||'').replace(/"/g,'""')+'"',
a.points, new Date(a.timestamp).toLocaleString()
].join(','));
});
});
downloadFile(rows.join('\n'), 'hse-qb-all-sessions-'+date+'.csv', 'text/csv');
showToast('All sessions exported as CSV.', 'success');
}
}
function exportToJSON(){
const s=getCurrentSession(); if(!s) return;
downloadFile(JSON.stringify({sessionName:s.name,created:s.created,lastUpdated:s.lastUpdated,players:s.players,teams:s.teams,answerLog:s.answerLog,categories:state.categories},null,2),'quiz-bowl-'+s.name+'-'+new Date().toISOString().split('T')[0]+'.json','application/json');
}
function downloadFile(content,filename,mimeType){
const a=document.createElement('a');
a.href='data:'+mimeType+';charset=utf-8,'+encodeURIComponent(content);
a.download=filename; a.style.display='none';
document.body.appendChild(a); a.click(); document.body.removeChild(a); }
