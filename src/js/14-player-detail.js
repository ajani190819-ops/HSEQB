function openPlayerDetailModal(playerName){
const players = buildUniversalPlayerStats();
const player = players.find(p => p.name === playerName);
if (!player){ showToast('No toss-up data found for ' + playerName, 'warn'); return; }
const model = buildPerformanceModel(players);
const metrics = model.byName[playerName];
const answers = [];
validSessions().forEach(session =>{
const p = (session.players ||{})[playerName];
if (p) answers.push(...toArray(p.answers).filter(isPlayerPerformanceAnswer));
});
const catMap ={};
answers.forEach(a =>{
const cat = a.category || '—';
if (!catMap[cat]) catMap[cat] = { total:0, correct:0, powers:0, negs:0, misses:0 };
const d = catMap[cat];
d.total++;
if (a.pointType === 'Power'){ d.correct++; d.powers++; }
else if (a.pointType === 'Toss-up') d.correct++;
else if (a.pointType === 'Neg') d.negs++;
else if (a.pointType === 'Miss') d.misses++;
});
const categories = Object.entries(catMap).sort((a,b) => b[1].correct - a[1].correct || b[1].total - a[1].total);
const fmt = (value, digits=1) => value === null || value === undefined || !Number.isFinite(value) ? '—' : Number(value).toFixed(digits);
const safeName = playerName.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const impact = metrics?.adjustedImpact;
const rawImpact = metrics?.rawImpact;
const pdUnranked = metrics ? !metrics.ranked : true;
const impactColor = impact === null ? 'var(--text3)' : impact >= model.average ? 'var(--success)' : 'var(--danger)';
const confidencePct = metrics ? Math.round(metrics.confidence * 100) : 0;
const sampleNote = metrics && metrics.confidence < 0.6 ? 'Small sample — interpret with care' : 'Sufficient sample for comparison';
const metricLine = (label, value, note='') => `<div style="display:flex;justify-content:space-between;align-items:baseline;gap:10px;padding:8px 0;border-bottom:1.5px solid var(--border);"><span class="fs-82-fw6-text2">${label}</span><span style="text-align:right;font-size:.92em;font-weight:700;color:var(--text);">${value}${note ? `<small style="display:block;font-size:.72em;font-weight:400;color:var(--text3);">${note}</small>` : ''}</span></div>`;
let categoryRows = '';
if (!categories.length){
categoryRows = '<tr><td colspan="6" style="color:var(--text2);font-style:italic;padding:12px 10px;">No category data yet.</td></tr>';
} else{
categoryRows = categories.map(([name, d], i) => `<tr><td style="padding:7px 10px;color:var(--text3);">${i+1}</td><td style="font-weight:600;padding:7px 10px;">${name}</td><td class="right" style="padding:7px 10px;">${d.total}</td><td class="right" style="padding:7px 10px;color:var(--success);">${d.correct || '—'}</td><td class="right" style="padding:7px 10px;color:var(--primary);">${d.powers || '—'}</td><td class="right" style="padding:7px 10px;color:var(--danger);">${d.negs || '—'}</td></tr>`).join('');
}
$('pdModalTitle').textContent = playerName;
$('pdModalBody').innerHTML = `<div class="pd-hero">
<div style="display:flex;align-items:center;gap:14px;min-width:0;">
<div class="avatar-lg">${playerName.charAt(0).toUpperCase()}</div>
<div style="min-width:0;"><div class="pd-hero-name">${playerName}</div><div class="pd-hero-sub">${player.sessions} session${player.sessions !== 1 ? 's' : ''} · ${player.tossupsCorrect + player.powers} correct toss-up${player.tossupsCorrect + player.powers !== 1 ? 's' : ''} · ${player.totalAnswers} decisions</div><div style="display:flex;align-items:center;gap:6px;margin-top:8px;"><input id="renamePlayerInput" type="text" placeholder="Rename player…" value="${playerName}" maxlength="40" onkeydown="if(event.key==='Enter') renamePlayer('${safeName}');" style="padding:5px 9px;border:1.5px solid var(--border);border-radius:6px;font-family:inherit;font-size:.82em;background:var(--card);color:var(--text);width:160px;" /><button onclick="renamePlayer('${safeName}');" style="padding:5px 12px;border:1.5px solid var(--primary);border-radius:6px;font-size:.8em;font-weight:700;color:var(--primary);background:color-mix(in srgb,var(--primary) 7%,transparent);cursor:pointer;font-family:inherit;">Rename</button></div></div></div>
<div style="display:flex;flex-direction:column;align-items:flex-end;gap:4px;flex-shrink:0;"><div class="pd-hero-pts">${player.points} Pts</div><div style="font-size:.75em;font-weight:700;color:var(--text3);text-transform:uppercase;letter-spacing:.05em;">Leaderboard Score</div><div style="font-size:1.1em;font-weight:800;color:${impactColor};">${fmt(impact)}</div><div style="font-size:.75em;color:var(--text3);">Team avg: ${fmt(model.average)}</div></div>
</div>
<div class="pd-section-title">Official Player Summary</div>
<div class="pd-stat-chips"><span class="pd-chip tossup">${player.tossupsCorrect + player.powers} Correct</span><span class="pd-chip power">⚡︎ ${player.powers} Power${player.powers !== 1 ? 's' : ''}</span><span class="pd-chip neg">− ${player.negs} Neg${player.negs !== 1 ? 's' : ''}</span><span class="pd-chip" style="background:rgba(243,156,18,.1);color:var(--warning);border:1px solid rgba(243,156,18,.35);">${player.misses} Miss${player.misses !== 1 ? 'es' : ''}</span><span class="pd-chip" style="background:color-mix(in srgb,var(--primary) 10%,transparent);color:var(--primary);">${player.tHeard || 0} TU Heard</span></div>
<div class="pd-section-title">Performance Metrics</div>
<div style="background:var(--sec-bg);border:1.5px solid var(--border);border-radius:10px;padding:6px 16px;margin-bottom:var(--sp);">
${metricLine('Leaderboard Score', fmt(impact), pdUnranked ? `Raw TU/20: ${fmt(rawImpact)} · needs ${RANKED_MIN_TU} TU heard to rank` : `Raw: ${fmt(rawImpact)} · Team average: ${fmt(model.average)}`)}
${metricLine('Reliability', metrics && metrics.reliability !== null ? fmt(metrics.reliability) + '%' : '—', 'Correct decisions ÷ all recorded decisions')}
${metricLine('Power Rate', metrics && metrics.powerRate !== null ? fmt(metrics.powerRate) + '%' : '—', 'Powers ÷ all recorded decisions; negs and misses count against it')}
${metricLine('TU/20', metrics && metrics.attempts20 !== null ? fmt(metrics.attempts20) : '—', 'All player decisions per 20 toss-ups heard')}
${metricLine('Confidence', confidencePct + '%', sampleNote)}
</div>
${pdUnranked ? `<div style="margin:-6px 0 var(--sp);padding:9px 12px;border-radius:8px;background:rgba(243,156,18,.08);border:1px solid rgba(243,156,18,.35);color:var(--warning);font-size:.78em;font-weight:600;">⏳ Provisional: ${player.tHeard || 0}/${RANKED_MIN_TU} TU heard — a Leaderboard Score and rank are assigned after one full session (${RANKED_MIN_TU} toss-ups).</div>` : ''}
<div class="pd-section-title">Category Decision Breakdown</div>
<div style="overflow-x:auto;border-radius:8px;border:1.5px solid var(--border);"><table class="pd-cat-table"><thead><tr><th>#</th><th>Category</th><th class="right">Decisions</th><th class="right">Correct</th><th class="right">Powers</th><th class="right">Negs</th></tr></thead><tbody>${categoryRows}</tbody></table></div>
<div style="margin-top:12px;padding:10px 12px;border-radius:8px;background:var(--sec-bg);color:var(--text2);font-size:.76em;line-height:1.5;"><strong>Bonus scoring:</strong> bonus points are recorded for the team because bonus conversion is a group effort. They are not included in this individual player score.</div>`;
$('playerDetailModal').classList.add('open');
}
function closePlayerDetailModal(){ $('playerDetailModal').classList.remove('open'); }
function pctOrdinal(n){
const v = n % 100;
if (v >= 11 && v <= 13) return 'th';
switch (n % 10){ case 1: return 'st'; case 2: return 'nd'; case 3: return 'rd'; default: return 'th'; }
}
function openScoreBand(index){
if (!scoreBandRegistry || !scoreBandRegistry.bands || !scoreBandRegistry.bands[index]) return;
const band = scoreBandRegistry.bands[index];
const total = scoreBandRegistry.entries.length;
const inBand = scoreBandRegistry.entries
.filter(e => e.score >= band.lo && e.score < band.hi)
.sort((a,b) => b.score - a.score);
$('bandModalTitle').textContent = `Score Band ${band.lo}\u2013${band.hi}`;
const rows = inBand.map((e,i) =>{
const safe = e.name.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const percentile = Math.round(100 * scoreBandRegistry.entries.filter(x => x.score <= e.score).length / total);
const color = e.score >= scoreBandRegistry.average ? 'var(--success)' : 'var(--danger)';
return `<div onclick="openPlayerDetailModal('${safe}')" onmouseover="this.style.background='var(--hover)'" onmouseout="this.style.background='var(--sec-bg)'" style="display:flex;align-items:center;gap:10px;padding:9px 12px;border:1.5px solid var(--border);border-radius:8px;margin-bottom:6px;cursor:pointer;background:var(--sec-bg);"><span style="font-weight:800;color:var(--text3);min-width:22px;">${i+1}</span><span style="flex:1;min-width:0;font-weight:700;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${e.name}</span><span style="text-align:right;min-width:92px;flex-shrink:0;"><span style="font-weight:800;color:${color};">${e.score.toFixed(1)}</span><small style="display:block;font-size:.68em;color:var(--text3);">${percentile}${pctOrdinal(percentile)} percentile</small></span></div>`;
}).join('');
$('bandModalBody').innerHTML = inBand.length
? `<div style="font-size:.78em;color:var(--text2);margin-bottom:10px;">${inBand.length} ranked player${inBand.length !== 1 ? 's' : ''} with a Leaderboard Score between ${band.lo} and ${band.hi}, highest first. Click a player for details.</div>${rows}`
: '<p class="text-2" style="padding:8px 2px;">No ranked players fall in this band.</p>';
$('bandModal').classList.add('open');
}
function closeBandModal(){ $('bandModal').classList.remove('open'); }
