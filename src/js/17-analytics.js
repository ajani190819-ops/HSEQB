function setToggleSwitchState(on){
const knob = $('viewToggleKnob');
const sw   = $('viewToggleSwitch');
const tl   = $('toggleLabelTracker');
const al   = $('toggleLabelAnalytics');
if (knob){ if(on){ knob.style.left='auto'; knob.style.right='2px'; } else { knob.style.left='2px'; knob.style.right='auto'; } }
if (sw){
  sw.style.background = on ? 'var(--header-control-bg-strong)' :'var(--header-control-bg)';
  sw.style.borderColor = 'var(--header-control-border)';
}
if (tl)   tl.style.color = on ? 'var(--header-control-text-muted)' :'var(--header-control-text)';
if (al)   al.style.color = on ? 'var(--header-control-text)' :'var(--header-control-text-muted)';
const mknob = $('viewToggleKnobMobile');
const mlbl  = $('toggleLabelMobile');
if (mknob) mknob.style.left = on ? '20px' :'2px';
if (mlbl)  mlbl.textContent = on ? 'Stats' :'Tracker'; }
function toggleAnalytics(){
analyticsOpen=!analyticsOpen;
localStorage.setItem('analyticsOpen', analyticsOpen);
const tv=$('trackerView');
const av=$('analyticsView');
if(analyticsOpen){
tv.style.display='none'; av.style.display='flex';
renderAnalytics();
} else{
tv.style.display='flex'; av.style.display='none'; }
setToggleSwitchState(analyticsOpen);
setTimeout(updateFadeMasks,50); }
function switchAnalyticsTab(tab, el){
currentAnalyticsTab=tab;
localStorage.setItem('analyticsTab', tab);
if (tab !== 'charts'){
Object.keys(_chartInstances).forEach(id => destroyChart(id));
_lastChartFingerprint = null; }
document.querySelectorAll('.analytics-tab').forEach(b=>b.classList.remove('active'));
el.classList.add('active');
document.querySelectorAll('.analytics-panel').forEach(p=>p.classList.remove('active'));
$('an-'+tab)?.classList.add('active');
renderAnalytics(tab === 'charts');
const scrollEl = $('analyticsScroll');
if (scrollEl){
const saved = parseInt(localStorage.getItem('analyticsScroll_'+tab)||'0', 10);
scrollEl.scrollTop = saved; }
}
function validSessions(){ return Object.values(state.sessions).filter(s => !sessionInvalidFlags[s.id]); }
function buildGlobalAnswerLog(){
const all = [];
validSessions().forEach(s => all.push(...toArray(s.answerLog)));
return all; }
function buildGlobalTHeard(){ return validSessions().reduce((sum, s) => sum + (s.tHeard || 0), 0); }
function renderAnalytics(forceCharts){
const s=getCurrentSession(); if(!s) return;
const tab=currentAnalyticsTab;
const globalPs = buildUniversalPlayerStats();
const globalLog = buildGlobalAnswerLog();
const globalTHeard = buildGlobalTHeard();
const sessionCount = validSessions().length;
if(tab==='overview') renderAnalyticsOverview(globalLog, globalPs, globalTHeard, sessionCount);
else if(tab==='players') renderAnalyticsPlayersUniversal();
else if(tab==='charts'){
const fp = buildChartFingerprint(globalLog, globalPs);
if (forceCharts || fp !== _lastChartFingerprint){
_lastChartFingerprint = fp;
renderAnalyticsCharts(globalLog, globalPs, globalTHeard); }
}
else if(tab==='teams') renderAnalyticsTeamCompositions(); }
function renderAnalyticsOverview(allAnswers, ps, globalTHeard, sessionCount){
const el=$('an-overview'); if(!el) return;
const playerPts = ps.reduce((sum,p) => sum + (p.points || 0), 0);
const teamBonusPoints = allAnswers.filter(isTeamBonusAnswer).reduce((sum,a) => sum + (a.points || 0), 0);
const totalPts = playerPts + teamBonusPoints;
const totalAns = allAnswers.length;
const totalNegs = allAnswers.filter(a => a.pointType === 'Neg').length;
const totalMisses = allAnswers.filter(a => a.pointType === 'Miss').length;
const totalDeads = allAnswers.filter(a => a.pointType === 'Dead').length;
const totalPowers = allAnswers.filter(a => a.pointType === 'Power').length;
const totalTossups = allAnswers.filter(a => a.pointType === 'Toss-up').length;
const totalBonuses = allAnswers.filter(isTeamBonusAnswer).length;
const decisionEvents = allAnswers.filter(isPlayerPerformanceAnswer);
const correctAns = decisionEvents.filter(a => a.pointType === 'Power' || a.pointType === 'Toss-up').length;
const activePlayers = ps.filter(p => p.totalAnswers > 0);
const catMap ={};
allAnswers.forEach(a =>{
const raw = a.category || '—'; if (raw === '—') return;
const cat = getParentCat(raw);
if (!catMap[cat]) catMap[cat] = { pts:0, count:0, negs:0, misses:0 };
catMap[cat].pts += (a.points || 0); catMap[cat].count++;
if (a.pointType === 'Neg') catMap[cat].negs++;
else if (a.pointType === 'Miss') catMap[cat].misses++;
});
const catArr = Object.keys(catMap).map(c => ({ name:c, pts:catMap[c].pts, count:catMap[c].count, negs:catMap[c].negs, misses:catMap[c].misses }));
catArr.sort((a,b) => b.pts - a.pts);
const strengths = catArr.slice(0,5);
let html = '';
const n = activePlayers.length || 1;
const teamActualPts20 = globalTHeard > 0 ? ((15 * totalPowers + 10 * totalTossups - 5 * totalNegs) / globalTHeard * 20).toFixed(1) : '—';
const totalBuzzes = totalPowers + totalTossups + totalNegs + totalMisses;
const teamReliability = totalBuzzes > 0 ? ((100 * correctAns) / totalBuzzes).toFixed(1) + '%' : '—';
const teamPowerRate = totalBuzzes > 0 ? ((100 * totalPowers) / totalBuzzes).toFixed(1) + '%' : '—';
function avg(total){ return (total / n).toFixed(1); }
function avgRate(fn, asPct){
const vals = activePlayers.map(p => fn(p)).filter(v => v !== null);
if (!vals.length) return '—';
const mean = vals.reduce((sum,v) => sum + v, 0) / vals.length;
return asPct ? (mean * 100).toFixed(1) + '%' : mean.toFixed(1);
}
const avgReliability = avgRate(p =>{
const attempts = (p.powers || 0) + (p.tossupsCorrect || 0) + (p.negs || 0) + (p.misses || 0);
const correct = (p.powers || 0) + (p.tossupsCorrect || 0);
return attempts > 0 ? correct / attempts : null;
}, true);
const avgPowerRate = avgRate(p =>{
const attempts = (p.powers || 0) + (p.tossupsCorrect || 0) + (p.negs || 0) + (p.misses || 0);
return attempts > 0 ? (p.powers || 0) / attempts : null;
}, true);
const avgAttempts20 = avgRate(p =>{
const attempts = (p.powers || 0) + (p.tossupsCorrect || 0) + (p.negs || 0) + (p.misses || 0);
const tH = p.tHeard || 0;
return tH > 0 ? (attempts / tH) * 20 : null;
}, false);
const avgActualPts20 = avgRate(p =>{
const tH = p.tHeard || 0;
return tH > 0 ? (p.points / tH) * 20 : null;
}, false);
const accColor = v => v === '—' ? 'var(--primary)' : parseFloat(v) >= 80 ? 'var(--success)' : parseFloat(v) >= 50 ? '#f39c12' : 'var(--danger)';
const _ovGroups = [
{
label:'Team Totals',
twoCol:false,
rows:[
{ label:'Active Players', val:activePlayers.length, color:'var(--primary)' },
{ label:'Toss-ups Heard', val:globalTHeard,         color:'var(--primary)' },
{ label:'Total Points',   val:totalPts,             color:'var(--primary)' },
{ label:'Recorded Events', val:totalAns,             color:'var(--text2)'   },
]
},
{
label:'Answer Breakdown',
twoCol:true,
colHeaders:['Total', 'Avg / Player'],
rows:[
{ label:'Toss-ups', total:totalPowers+totalTossups, avg:avg(totalPowers+totalTossups), totalColor:'var(--pt-tossup)', avgColor:'var(--pt-tossup)' },
{ label:'⚡︎ Powered', total:totalPowers, avg:avg(totalPowers), totalColor:'var(--pt-power)', avgColor:'var(--pt-power)' },
{ label:'Bonuses (team)', total:totalBonuses, avg:'—', totalColor:'var(--pt-bonus)', avgColor:'var(--text3)' },
{ label:'Points',   total:totalPts,     avg:avg(playerPts),     totalColor:'var(--primary)', avgColor:'var(--primary)' },
{ label:'Negs',     total:totalNegs,    avg:avg(totalNegs),    totalColor:'var(--pt-neg)',  avgColor:'var(--pt-neg)'  },
{ label:'Misses',   total:totalMisses,  avg:avg(totalMisses),  totalColor:'var(--pt-miss)', avgColor:'var(--pt-miss)' },
{ label:'Dead TUs (team)', total:totalDeads,   avg:'—',   totalColor:'var(--pt-dead)',   avgColor:'var(--pt-dead)'   },
]
},
{
label:'Performance Rates',
twoCol:true,
colHeaders:['Team', 'Avg / Player'],
rows:[
{ label:'Reliability',            total:teamReliability,    avg:avgReliability,    totalColor:accColor(teamReliability), avgColor:accColor(avgReliability) },
{ label:'Power Rate',              total:teamPowerRate,      avg:avgPowerRate,      totalColor:'var(--primary)', avgColor:'var(--primary)' },
{ label:'TU/20',     total:globalTHeard > 0 ? ((totalBuzzes / globalTHeard) * 20).toFixed(1) : '—', avg:avgAttempts20, totalColor:'var(--text2)', avgColor:'var(--text2)' },
{ label:'Points / 20',    total:teamActualPts20,   avg:avgActualPts20,   totalColor:'var(--primary)', avgColor:'var(--primary)' },
]
},
];
const _secHdr = `font-size:.65em;font-weight:800;letter-spacing:.09em;text-transform:uppercase;color:var(--text3);padding:8px 0 4px;margin-bottom:4px;border-bottom:1.5px solid var(--border);`;
const [_totalsGroup, _breakdownGroup, _ratesGroup] = _ovGroups;
html += `<div style="background:var(--card);border:2px solid var(--border);border-radius:10px;padding:16px 18px;margin-bottom:var(--sp);box-shadow:var(--shadow-sm);">
<h3 class="m12-fs11">HSE Team Overview</h3>`;
html += `<div style="${_secHdr}">${_totalsGroup.label}</div>`;
html += `<div style="display:flex;flex-wrap:wrap;gap:6px;margin-bottom:12px;">`;
_totalsGroup.rows.forEach(r =>{
html += `<div style="display:flex;align-items:center;gap:6px;background:var(--sec-bg);border:1.5px solid var(--border);border-radius:20px;padding:5px 12px;white-space:nowrap;">
<span style="font-size:.72em;font-weight:600;color:var(--text2);">${r.label}</span>
<span style="font-size:.92em;font-weight:800;color:${r.color};">${r.val}</span>
</div>`;
});
html += `</div>`;
html += `<div style="display:flex;gap:20px;align-items:flex-start;flex-wrap:wrap;">`;
[_breakdownGroup, _ratesGroup].forEach(({label, colHeaders, rows}) =>{
html += `<div style="flex:1;min-width:180px;">`;
html += `<div style="${_secHdr}">${label}</div>`;
html += `<div style="display:grid;grid-template-columns:1fr auto auto;gap:0;margin-bottom:3px;padding:0 2px;">
<div></div>
<div style="font-size:.58em;font-weight:700;color:var(--text3);width:56px;text-align:right;padding-right:10px;">${colHeaders[0]}</div>
<div style="font-size:.58em;font-weight:700;color:var(--text3);width:56px;text-align:right;">${colHeaders[1]}</div>
</div>`;
rows.forEach(r =>{
html += `<div style="display:grid;grid-template-columns:1fr auto auto;align-items:center;padding:4px 2px;border-bottom:1.5px solid var(--border);">
<span style="font-size:.82em;color:var(--text2);">${r.label}</span>
<span style="width:56px;text-align:right;padding-right:10px;font-weight:700;font-size:.88em;color:${r.totalColor};">${r.total}</span>
<span style="width:56px;text-align:right;font-weight:700;font-size:.88em;color:${r.avg !== null ? r.avgColor :'var(--text3)'};">${r.avg !== null ? r.avg :'—'}</span>
</div>`;
});
html += `</div>`;
});
html += `</div>`;
html += `</div>`; // end panel
if (strengths.length){
html += '<div style="background:var(--card);border:2px solid var(--border);border-radius:10px;padding:16px;margin-bottom:var(--sp);box-shadow:var(--shadow-sm);">';
html += '<h3 class="m12-fs95">&#9650; Category Strengths</h3>';
strengths.forEach(c =>{ html += '<div class="stat-row"><span class="stat-label">'+c.name+'</span><span class="stat-value" style="color:var(--success)">'+c.pts+' Pts</span></div>'; });
html += '</div>'; }
const subcatVolMap ={};
allAnswers.forEach(a =>{
const raw = a.category || ''; if (!raw) return;
subcatVolMap[raw] = (subcatVolMap[raw] || 0) + 1; });
const totalSubcatVol = Object.values(subcatVolMap).reduce((s, v) => s + v, 0);
const subcatGaps = [];
Object.entries(CATEGORY_TREE).forEach(([parent, subs]) =>{
subs.forEach(sub =>{
const expected = catFreqs[sub];
if (expected == null || expected <= 0) return;
const actual = totalSubcatVol > 0 ? (subcatVolMap[sub] || 0) / totalSubcatVol * 100 :0;
const gap = expected - actual; // positive = under-covered
subcatGaps.push({ sub, parent, expected, actual, gap });
}); });
const parentOrder = Object.keys(CATEGORY_TREE);
const needsWork = subcatGaps
.filter(x => x.gap > 0.5) // only show meaningful gaps
.sort((a, b) =>{
const pi = parentOrder.indexOf(a.parent) - parentOrder.indexOf(b.parent);
if (pi !== 0) return pi;
return b.gap - a.gap; // within parent:biggest gap first
});
if (needsWork.length){
html += '<div style="background:var(--card);border:2px solid var(--border);border-radius:10px;padding:16px;margin-bottom:var(--sp);box-shadow:var(--shadow-sm);">';
html += '<h3 class="m4-fs95-danger">&#9660; Categories to Work On</h3>';
html += '<p class="fs-76-text3">Subcategories where your heard volume is below the expected tournament frequency, grouped by category.</p>';
let lastParent = null;
needsWork.forEach(({ sub, parent, expected, actual, gap }) =>{
if (parent !== lastParent){
if (lastParent !== null) html += '<div style="height:6px;"></div>';
html += '<div style="font-size:.72em;font-weight:800;text-transform:uppercase;letter-spacing:.07em;color:var(--text3);padding:4px 0 2px;border-bottom:1.5px solid var(--border);margin-bottom:4px;">' + parent + '</div>';
lastParent = parent; }
const gapColor = gap > 3 ? 'var(--danger)' :gap > 1.5 ? '#f39c12' :'var(--text2)';
html += '<div class="stat-row">'
+ '<span class="stat-label">' + sub + '</span>'
+ '<span style="font-size:.8em;color:var(--text3);flex:1;padding:0 8px;">'
+ actual.toFixed(1) + '% heard vs ' + expected.toFixed(1) + '% expected'
+ '</span>' + '<span class="stat-value" style="color:' + gapColor + ';">&minus;' + gap.toFixed(1) + '%</span>' + '</div>';
});
html += '</div>'; }
if(!totalAns) html+='<p class="text-2">No answers recorded yet. Start tracking to see your team overview!</p>';
el.innerHTML=html; }
