function buildUniversalPlayerStats(){
const playerMap ={};
validSessions().forEach(session =>{
const sessionTHeard = session.tHeard || 0;
Object.values(session.players ||{}).forEach(p =>{
if (!p || !p.name || p.name === '— Team Bonus —') return;
const answers = toArray(p.answers).filter(isPlayerPerformanceAnswer);
if (!answers.length) return;
if (!playerMap[p.name]) playerMap[p.name] = { name:p.name, points:0, totalAnswers:0, tossupsCorrect:0, bonusPoints:0, negs:0, misses:0, powers:0, sessions:0, catMap:{}, tHeard:0, _tHeardBase:0 };
const u = playerMap[p.name];
u.points += answers.reduce((sum, a) => sum + (a.points || 0), 0);
u.totalAnswers += answers.length;
u.tossupsCorrect += answers.filter(a => a.pointType === 'Toss-up').length;
u.negs += answers.filter(a => a.pointType === 'Neg').length;
u.misses += answers.filter(a => a.pointType === 'Miss').length;
u.powers += answers.filter(a => a.pointType === 'Power').length;
u.tHeard += sessionTHeard;
u._tHeardBase += sessionTHeard;
u.sessions++;
answers.forEach(a =>{
if (a.category && a.category !== '—'){
const pc = getParentCat(a.category);
u.catMap[pc] = (u.catMap[pc] || 0) + 1;
}
});
});
});
return Object.values(playerMap).map(p =>{
const delta = playerTHeardOverrides[p.name] || 0;
p.tHeard = Math.max(0, p._tHeardBase + delta);
p.tHeardDelta = delta;
return p;
}).sort((a,b) => b.points !== a.points ? b.points - a.points : b.powers !== a.powers ? b.powers - a.powers : a.negs - b.negs);
}
const RANKED_MIN_TU = 20; // One full session of toss-ups heard before a player earns a Leaderboard Score.
function getPlayerPerformanceMetrics(p, averageImpact, regressionK){
const tHeard = p.tHeard || 0;
const attempts = (p.powers || 0) + (p.tossupsCorrect || 0) + (p.negs || 0) + (p.misses || 0);
const correct = (p.powers || 0) + (p.tossupsCorrect || 0);
const rawImpact = tHeard > 0 ? ((15 * (p.powers || 0) + 10 * (p.tossupsCorrect || 0) - 5 * (p.negs || 0)) / tHeard) * 20 : null;
const reliability = attempts > 0 ? (100 * correct) / attempts : null;
// Negs and misses are intentionally included: this is powers among all recorded decisions.
const powerRate = attempts > 0 ? (100 * (p.powers || 0)) / attempts : null;
const attempts20 = tHeard > 0 ? (attempts / tHeard) * 20 : null;
const conversion = tHeard > 0 ? (100 * correct) / tHeard : null;
const confidence = tHeard > 0 ? tHeard / (tHeard + regressionK) : 0;
// Players below one full session (RANKED_MIN_TU toss-ups heard) stay provisional:
// their raw rates still show as diagnostics, but they receive no Leaderboard Score
// and are excluded from the team average, spread, and automatic k.
const ranked = tHeard >= RANKED_MIN_TU;
const adjustedImpact = rawImpact === null || !ranked ? null : confidence * rawImpact + (1 - confidence) * averageImpact;
return { tHeard, attempts, correct, rawImpact, adjustedImpact, reliability, powerRate, attempts20, conversion, confidence, ranked };
}
function buildPerformanceModel(players){
const active = (players || []).filter(p => p.totalAnswers > 0);
// Only players with at least one full session (RANKED_MIN_TU toss-ups heard) count
// toward the model. Partial-session players used to drag the average and shrink k.
const ranked = active.filter(p => (Number(p.tHeard) || 0) >= RANKED_MIN_TU);
const usable = ranked.map(p => getPlayerPerformanceMetrics(p, 0, 1)).filter(m => m.rawImpact !== null);
const average = usable.length ? usable.reduce((sum, m) => sum + m.rawImpact, 0) / usable.length : 0;
// Determine the prior strength from the actual exposure in this comparison.
// The median TU heard is a robust, data-driven equivalent sample size: at the
// typical ranked player’s exposure, raw performance receives 50% weight. Unlike
// the old fixed setting, this automatically adapts as sessions and playing time
// accumulate, without being distorted by one unusually long or short sample.
const exposures = ranked.map(p => Number(p.tHeard) || 0).filter(h => h > 0).sort((a,b) => a - b);
const mid = Math.floor(exposures.length / 2);
const regressionK = exposures.length
  ? Math.max(1, exposures.length % 2 ? exposures[mid] : (exposures[mid - 1] + exposures[mid]) / 2)
  : 1;
const byName ={};
active.forEach(p =>{ byName[p.name] = getPlayerPerformanceMetrics(p, average, regressionK); });
const values = ranked.map(p => byName[p.name].rawImpact).filter(v => v !== null);
const variance = values.length > 1 ? values.reduce((sum, v) => sum + Math.pow(v - average, 2), 0) / values.length : 0;
return { active, ranked, average, sd:Math.sqrt(variance), regressionK, byName, rankedCount:ranked.length, provisionalCount:active.length - ranked.length };
}
function renderAnalyticsPlayersUniversal(){
const el = $('an-players');
if (!el) return;
const allPlayers = buildUniversalPlayerStats();
const active = allPlayers.filter(p => p.totalAnswers > 0);
if (!active.length){ el.innerHTML = '<p class="text-2">No player performance data yet.</p>'; return; }
const model = buildPerformanceModel(active);
const validSorts = new Set(['points','impact','reliability','powerRate','attempts','alpha']);
if (!validSorts.has(playerSortKey)) playerSortKey = 'points';
const sortOptions = [
{ key:'points', label:'Total Points' },
{ key:'impact', label:'Leaderboard Score' },
{ key:'reliability', label:'Reliability' },
{ key:'powerRate', label:'Power Rate' },
{ key:'attempts', label:'TU/20' },
{ key:'alpha', label:'A–Z' },
];
let html = `<div style="background:var(--sec-bg);border:1.5px solid var(--border);border-radius:10px;margin-bottom:var(--sp);padding:12px 14px;display:flex;align-items:center;justify-content:space-between;flex-wrap:wrap;gap:8px;"><div style="font-size:.78em;color:var(--text2);"><strong style="color:var(--text);">Overall performance:</strong> Leaderboard Score · ${model.rankedCount ? `team average ${model.average.toFixed(1)} · auto k = ${model.regressionK} TU heard · ${model.rankedCount} of ${model.active.length} player${model.active.length !== 1 ? 's' : ''} ranked${model.provisionalCount ? ` · ${model.provisionalCount} need${model.provisionalCount === 1 ? 's' : ''} ${RANKED_MIN_TU} TU to rank` : ''}` : `no ranked players yet — a score requires ${RANKED_MIN_TU} TU heard${model.active.length ? ` (${model.active.length} provisional)` : ''}`}</div><button onclick="showSection('sec-danger')" style="font-size:.75em;font-weight:700;padding:4px 10px;border-radius:6px;border:1.5px solid var(--border);background:var(--card);color:var(--text2);cursor:pointer;white-space:nowrap;">Configure ↗</button></div>`;
html += `<div style="display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-bottom:14px;padding-bottom:14px;border-bottom:1.5px solid var(--border);"><span style="font-size:.75em;font-weight:700;color:var(--text3);text-transform:uppercase;letter-spacing:.5px;flex-shrink:0;margin-right:2px;">Sort</span>${sortOptions.map(o => `<button class="sort-pill${playerSortKey === o.key ? ' active' : ''}" onclick="playerSortKey='${o.key}';renderAnalyticsPlayersUniversal();">${o.label}</button>`).join('')}</div>`;
const sorted = active.map(p => ({ ...p, _metrics:model.byName[p.name] })).sort((a,b) =>{
const av = a._metrics, bv = b._metrics;
switch (playerSortKey){
case 'impact': return ((bv.adjustedImpact ?? -Infinity) - (av.adjustedImpact ?? -Infinity)) || ((bv.tHeard || 0) - (av.tHeard || 0));
case 'reliability': return (bv.reliability ?? -Infinity) - (av.reliability ?? -Infinity);
case 'powerRate': return (bv.powerRate ?? -Infinity) - (av.powerRate ?? -Infinity);
case 'attempts': return (bv.attempts20 ?? -Infinity) - (av.attempts20 ?? -Infinity);
case 'alpha': return a.name.localeCompare(b.name);
default: return b.points !== a.points ? b.points - a.points : b.powers !== a.powers ? b.powers - a.powers : a.negs - b.negs;
}
});
let rank = 1;
html += sorted.map((p, i) =>{
if (i > 0){
const prev = sorted[i - 1];
const key = playerSortKey === 'impact' ? 'adjustedImpact' : playerSortKey === 'reliability' ? 'reliability' : playerSortKey === 'powerRate' ? 'powerRate' : playerSortKey === 'attempts' ? 'attempts20' : playerSortKey === 'points' ? 'points' : null;
if (key && prev._metrics[key] !== p._metrics[key] && !(key === 'points' && prev.points === p.points)) rank = i + 1;
else if (key === null || (key === 'points' && (prev.points !== p.points || prev.powers !== p.powers || prev.negs !== p.negs))) rank = i + 1;
}
const m = p._metrics;
const cardId = 'pcard_' + p.name.replace(/\W/g, '_');
const safeName = p.name.replace(/\\/g,'\\\\').replace(/'/g,"\\'");
const impact = m.adjustedImpact;
const impactColor = impact === null ? 'var(--text3)' : impact >= model.average ? 'var(--success)' : 'var(--danger)';
const rawText = m.rawImpact === null ? '—' : m.rawImpact.toFixed(1);
const lowSample = m.confidence < 0.6;
const unranked = !m.ranked;
const rankLabel = playerSortKey === 'alpha' ? '' : unranked && playerSortKey === 'impact' ? '—' : rank + (['st','nd','rd'][rank - 1] || 'th');
const fmt = (v, suffix='') => v === null || v === undefined || !Number.isFinite(v) ? '—' : v.toFixed(1) + suffix;
const topCats = Object.entries(p.catMap).sort((a,b) => b[1] - a[1]).slice(0,3);
return `<div class="player-card-wrap"><div class="player-card-header" onclick="togglePlayerCard('${cardId}')"><div class="player-card-rank">${rankLabel}</div><div class="flex-1-min0"><div style="font-weight:700;font-size:.95em;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${p.name}</div><div style="font-size:.75em;color:var(--text3);margin-top:1px;">${p.sessions} session${p.sessions !== 1 ? 's' : ''} · ${p.tossupsCorrect + p.powers} correct · ${p.tHeard || 0} TU heard${unranked ? ` · needs ${RANKED_MIN_TU} TU to rank` : ''}</div></div><div style="display:flex;gap:6px;align-items:center;flex-shrink:0;"><span style="display:flex;flex-direction:column;align-items:flex-end;min-width:78px;text-align:right;"><span style="font-size:1em;font-weight:800;color:${impactColor};">${impact === null ? '—' : impact.toFixed(1)}</span><small style="font-size:.58em;font-weight:600;color:var(--text3);">Leaderboard Score</small></span><span style="display:flex;flex-direction:column;align-items:flex-end;min-width:58px;text-align:right;"><span style="font-size:1em;font-weight:800;color:var(--text2);">${m.attempts20 === null ? '—' : m.attempts20.toFixed(1)}</span><small style="font-size:.58em;font-weight:600;color:var(--text3);">TU/20</small></span><span style="font-size:.75em;color:var(--text3);transition:transform .2s;margin-left:2px;" id="${cardId}_arrow">▼</span></div></div><div id="${cardId}" class="hidden"><div class="player-card-body"><div style="display:flex;justify-content:space-between;align-items:flex-start;gap:8px;margin-bottom:12px;flex-wrap:wrap;"><div class="flex-wrap-gap"><span style="background:rgba(17,153,142,.08);border:1px solid rgba(17,153,142,.3);color:var(--success);border-radius:6px;padding:3px 9px;font-size:.77em;font-weight:600;">${p.tossupsCorrect + p.powers} Correct</span><span style="background:color-mix(in srgb,var(--primary) 8%,transparent);border:1px solid color-mix(in srgb,var(--primary) 30%,transparent);color:var(--primary);border-radius:6px;padding:3px 9px;font-size:.77em;font-weight:600;">⚡︎ ${p.powers} Power${p.powers !== 1 ? 's' : ''}</span><span style="background:rgba(220,53,69,.08);border:1px solid rgba(220,53,69,.3);color:var(--danger);border-radius:6px;padding:3px 9px;font-size:.77em;font-weight:600;">${p.negs} Neg${p.negs !== 1 ? 's' : ''}</span><span style="background:rgba(243,156,18,.08);border:1px solid rgba(243,156,18,.35);color:var(--warning);border-radius:6px;padding:3px 9px;font-size:.77em;font-weight:600;">${p.misses} Miss${p.misses !== 1 ? 'es' : ''}</span></div><div style="display:flex;align-items:center;gap:5px;font-size:.75em;color:var(--text3);background:var(--sec-bg);border:1.5px solid var(--border);border-radius:8px;padding:4px 7px;" title="Adjust player exposure when substitutions change how many toss-ups they heard"><button onclick="event.stopPropagation();adjustPlayerTHeard('${safeName}',-1);" class="btn-icon-20">−</button><span>${p.tHeard || 0}${p.tHeardDelta ? ` (${p.tHeardDelta > 0 ? ' +' :''}${p.tHeardDelta})` : ''} TU heard</span><button onclick="event.stopPropagation();adjustPlayerTHeard('${safeName}',1);" class="btn-icon-20">+</button></div></div><div class="metric-grid"><div class="metric-tile"><div class="metric-lbl">Total Points</div><div class="metric-val" style="color:var(--primary);">${p.points}</div></div><div class="metric-tile"><div class="metric-lbl">Leaderboard Score</div><div class="metric-val" style="color:${impactColor};">${impact === null ? '—' : impact.toFixed(1)}</div><div style="font-size:.68em;color:var(--text3);margin-top:3px;">${unranked ? `Ranks after ${RANKED_MIN_TU} TU heard · Raw TU/20: ${rawText}` : `Raw TU/20: ${rawText} · Avg: ${model.average.toFixed(1)}`}</div></div><div class="metric-tile"><div class="metric-lbl">Reliability</div><div class="metric-val" style="color:var(--success);">${fmt(m.reliability, '%')}</div><div style="font-size:.68em;color:var(--text3);margin-top:3px;">correct / all decisions</div></div><div class="metric-tile"><div class="metric-lbl">Power Rate</div><div class="metric-val" style="color:var(--primary);">${fmt(m.powerRate, '%')}</div><div style="font-size:.68em;color:var(--text3);margin-top:3px;">powers / all decisions</div></div><div class="metric-tile"><div class="metric-lbl">TU/20</div><div class="metric-val" style="color:var(--text2);">${fmt(m.attempts20)}</div><div style="font-size:.68em;color:var(--text3);margin-top:3px;">participation pace</div></div><div class="metric-tile"><div class="metric-lbl">Confidence</div><div class="metric-val" style="color:${lowSample ? 'var(--warning)' : 'var(--success)'};">${Math.round(m.confidence * 100)}%</div><div style="font-size:.68em;color:var(--text3);margin-top:3px;">${lowSample ? 'small sample' : 'sample supported'}</div></div></div>${topCats.length ? `<div style="border-top:1.5px solid var(--border);padding-top:10px;margin-top:12px;"><div style="font-size:.7em;font-weight:700;color:var(--text3);text-transform:uppercase;letter-spacing:.4px;margin-bottom:6px;">Top Categories by Decisions</div>${topCats.map(([cat, count]) => `<div style="display:flex;justify-content:space-between;padding:4px 0;font-size:.82em;border-bottom:1.5px solid var(--border);"><span style="color:var(--text2);font-weight:500;">${catLabel(cat)}</span><span style="font-weight:700;color:var(--primary);">${count}</span></div>`).join('')}</div>` : ''}<div style="margin-top:12px;padding:9px 11px;border-radius:8px;background:var(--sec-bg);color:var(--text2);font-size:.74em;line-height:1.45;">Bonuses are team-scored and intentionally excluded from individual player metrics.</div></div></div></div>`;
}).join('');
html += `<div style="background:var(--card);border:1.5px solid var(--border);border-radius:10px;margin-top:var(--sp);overflow:hidden;box-shadow:var(--shadow-xs);"><div onclick="formulasPanelCollapsed=!formulasPanelCollapsed;localStorage.setItem('formulasPanelCollapsed',formulasPanelCollapsed);renderAnalyticsPlayersUniversal();" style="display:flex;align-items:center;justify-content:space-between;padding:12px 16px;cursor:pointer;user-select:none;" onmouseover="this.style.background='var(--hover)';" onmouseout="this.style.background='';"><span class="fs-85-fw7">📐 Player Metric Formulas &amp; Definitions</span><span style="font-size:.75em;color:var(--text3);transition:transform .25s;display:inline-block;transform:${formulasPanelCollapsed ? '' : 'rotate(180deg)'};">▼</span></div>${formulasPanelCollapsed ? '' : `<div style="border-top:1.5px solid var(--border);padding:16px;display:grid;gap:10px;">${[
['Toss-Ups Heard (H)', 'Session toss-ups heard used as the player opportunity count.', 'This is the denominator for the rate-based calculations and represents opportunity, not quality. It is taken from the session’s toss-up counter and accumulated across the sessions included in Analytics. Because substitutions can give players different amounts of playing time, adjust this value when the automatic session exposure does not match what a player actually heard.'],
['Raw TU/20', '(15×P + 10×T − 5×N) ÷ H × 20', 'This converts a player’s recorded toss-up results to a common 20-question pace, making players with different amounts of playing time easier to compare. Powers contribute 15 points, regular toss-up answers contribute 10, and negs subtract 5; misses contribute zero. Team bonuses are deliberately excluded because they are not attributable to one player.'],
['Leaderboard Score', 'Confidence×Raw TU/20 + (1−Confidence)×Team Average', `This is the score used to rank players. It combines the player’s Raw TU/20 with the average raw score of the ranked players, using Confidence to decide how much of each to use. A qualifying sample is pulled less; as Toss-Ups Heard increases, the player’s own results control more of the score. A player earns a Leaderboard Score (and a rank) only after hearing at least ${RANKED_MIN_TU} toss-ups — one full session — so partial-session players never skew the standings.`],
['Reliability', '(P + T) ÷ (P + T + N + M) × 100', 'This measures how often a player’s recorded decisions were correct. Powers and regular toss-up answers count as correct, while negs and misses count as unsuccessful decisions. It is a decision-quality diagnostic rather than the overall leaderboard score, and it does not use Toss-Ups Heard in its denominator.'],
['Power Rate', 'P ÷ (P + T + N + M) × 100', 'This is the share of all recorded player decisions that were powers. Counting negs and misses in the denominator prevents the rate from looking artificially high when a player has taken risky or unsuccessful attempts. It is useful for describing style, but it is not a measure of total scoring by itself.'],
['TU/20', '(P + T + N + M) ÷ H × 20', 'This estimates how many decisions a player makes during a typical 20 toss-ups. It includes powers, regular answers, negs, and misses, then scales that count by Toss-Ups Heard. It can exceed 20 because more than one player may record a decision on the same toss-up, for example when a neg is followed by another buzz.'],
['Confidence', 'H ÷ (H + k)', `This is the amount of trust assigned to the player’s own sample. H is the player’s Toss-Ups Heard, and k is automatically set to the median Toss-Ups Heard among ranked players — those with at least one full ${RANKED_MIN_TU}-toss-up session (${model.regressionK}) — so the typical ranked player is 50% trusted. Confidence is 50% at H=k, 75% at H=3k, and approaches 100% gradually rather than ever reaching it exactly.`],
['Bonus Points', 'Recorded once for the team; never assigned to an individual', 'A bonus is recorded for the team because its conversion is a group effort rather than an individual decision. Bonus points therefore remain in team totals and session scoring, but they are excluded from Raw TU/20, Leaderboard Score, and the individual player diagnostics.'],
].map(([name, formula, desc]) => `<div style="background:var(--sec-bg);border:1.5px solid var(--border);border-radius:8px;padding:10px 12px;"><div style="display:flex;align-items:baseline;justify-content:space-between;gap:8px;flex-wrap:wrap;margin-bottom:4px;"><span style="font-size:.82em;font-weight:800;color:var(--primary);">${name}</span><code style="font-size:.72em;color:var(--text2);background:var(--hover);border-radius:4px;padding:2px 6px;white-space:nowrap;">${formula}</code></div><div style="font-size:.76em;color:var(--text3);line-height:1.45;">${desc}</div></div>`).join('')}</div>`}</div>`;
el.innerHTML = html;
expandedPlayerCards.forEach(id =>{ const panel = $(id); const arrow = $(id + '_arrow'); if (panel) panel.style.display = 'block'; if (arrow) arrow.style.transform = 'rotate(180deg)'; });
}
function togglePlayerCard(id){
const panel = $(id);
const arrow = $(id + '_arrow');
if (!panel) return;
const open = panel.style.display === 'none';
panel.style.display = open ? 'block' :'none';
if (arrow) arrow.style.transform = open ? 'rotate(180deg)' :'';
if (open) expandedPlayerCards.add(id);
else expandedPlayerCards.delete(id); }
function toggleLowDataInclude(playerName){
if (manuallyIncluded.has(playerName)) manuallyIncluded.delete(playerName); else manuallyIncluded.add(playerName);
saveManualInclusions(); renderAnalyticsPlayersUniversal(); }
function _getLowDataThresh(){
const all = buildUniversalPlayerStats();
const counts = all.map(p => p.powers + p.tossupsCorrect + p.negs).sort((a,b)=>a-b);
const med = counts[Math.floor(counts.length/2)] || 0;
return Math.floor(med * (skillThresholdPct / 100)); }
function includeLowDataAll(){
const thresh = _getLowDataThresh();
buildUniversalPlayerStats().forEach(p =>{
const buzzes = p.powers + p.tossupsCorrect + p.negs;
if (buzzes < thresh || (p.tHeard || 0) === 0) manuallyIncluded.add(p.name); });
saveManualInclusions();
renderAnalyticsPlayersUniversal(); }
function excludeLowDataAll(){
const thresh = _getLowDataThresh();
buildUniversalPlayerStats().forEach(p =>{
const buzzes = p.powers + p.tossupsCorrect + p.negs;
if (buzzes < thresh || (p.tHeard || 0) === 0) manuallyIncluded.delete(p.name); });
saveManualInclusions();
renderAnalyticsPlayersUniversal(); }
