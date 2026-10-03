function calcTeamEfficiency(team, sessionTHeard){
const{ tossups, bonuses, powers, negs } = team;
const eBonus = (tossups + powers) > 0 ? (100 * (10 * bonuses)) / (30 * (tossups + powers)) :null;
const tHeard = sessionTHeard > 0 ? sessionTHeard :Math.max(20, tossups + negs);
const numerator = 15 * powers + 10 * tossups + 10 * bonuses - 5 * negs;
const eTotal = tHeard > 0 ? (100 * numerator) / (45 * tHeard) :null;
return{ eBonus, eTotal, tHeard, tHeardIsReal:sessionTHeard > 0 };
}
function effBar(value, color, label, tooltip){
if (value === null) return '';
const pct = Math.min(Math.max(value, 0), 100);
const barColor = pct >= 66 ? 'var(--success)' :pct >= 33 ? '#f39c12' :'var(--danger)';
return `<div class="mb-10" title="${tooltip}">
<div style="display:flex;justify-content:space-between;align-items:baseline;margin-bottom:4px;">
<span style="font-size:.78em;font-weight:700;color:var(--text2);">${label}</span>
<span style="font-size:.9em;font-weight:700;color:${barColor};">${value.toFixed(1)}%</span>
</div>
<div style="height:8px;background:var(--border);border-radius:8px;overflow:hidden;">
<div style="height:100%;width:${pct}%;background:${barColor};border-radius:8px;transition:width .4s ease;"></div>
</div></div>`;
}
function renderAnalyticsTeamCompositions(){
const el = $('an-teams'); if (!el) return;
const sessions = validSessions();
const teamMap = {};
const allTeamCards = [];
sessions.forEach(session =>{
const dateStr = new Date(session.created).toLocaleDateString([],{ month:'short', day:'numeric', year:'numeric' });
const teams = toArray(session.teams).filter(t => toArray(t.playerMembers).length > 0);
teams.forEach(team =>{
const members = toArray(team.playerMembers).slice().sort();
const key = members.join('|');
const data = {
teamName:team.name,
members,
dateStr,
sessionDate:session.created,
sessionId:session.id,
isCurrent:session.id === state.currentSessionId
};
let pts = 0, answers = 0, decisions = 0, powers = 0, negs = 0, misses = 0, tossups = 0, bonuses = 0;
members.forEach(name =>{
const p = (session.players ||{})[name];
if (!p) return;
const a = toArray(p.answers).filter(isPlayerPerformanceAnswer);
pts += a.reduce((sum, answer) => sum + (answer.points || 0), 0);
answers += a.length;
decisions += a.length;
powers += a.filter(x => x.pointType === 'Power').length;
negs += a.filter(x => x.pointType === 'Neg').length;
misses += a.filter(x => x.pointType === 'Miss').length;
tossups += a.filter(x => x.pointType === 'Toss-up').length;
});
const teamBonusAnswers = toArray(session.answerLog).filter(a => isTeamBonusAnswer(a) && (a.player === `— ${team.name} Bonus —` || (teams.length === 1 && a.player === '— Team Bonus —') || members.includes(a.player)));
bonuses = teamBonusAnswers.length;
pts += teamBonusAnswers.reduce((sum, answer) => sum + (answer.points || 0), 0);
answers += bonuses;
const eff = calcTeamEfficiency({ tossups, bonuses, powers, negs, answers:decisions }, session.tHeard || 0);
Object.assign(data, { pts, answers, decisions, powers, negs, misses, tossups, bonuses, ...eff });
if(!teamMap[key]){ teamMap[key] = { ...data, appearances: 1 }; }
else{
teamMap[key].appearances++;
teamMap[key].pts += pts;
teamMap[key].answers += answers;
teamMap[key].decisions += decisions;
teamMap[key].powers += powers;
teamMap[key].negs += negs;
teamMap[key].misses += misses;
teamMap[key].tossups += tossups;
teamMap[key].bonuses += bonuses;
teamMap[key].teamName = data.teamName;
teamMap[key].dateStr = data.dateStr;
if(new Date(data.sessionDate) > new Date(teamMap[key].sessionDate)) teamMap[key].sessionDate = data.sessionDate;
}
}); });
Object.values(teamMap).forEach(team => allTeamCards.push(team));
allTeamCards.sort((a, b) => new Date(b.sessionDate) - new Date(a.sessionDate));
if (!allTeamCards.length){
el.innerHTML = '<p class="text-2">No team compositions found. Create teams and assign players to sessions to see them here.</p>';
return; }
const sessionCount = validSessions().length;
const playerCounts = [...new Set(allTeamCards.map(t => t.members.length))].sort((a,b) => a-b);
let html = `
<div style="margin-bottom:12px;">
<div style="margin-bottom:10px;position:relative;">
<input
id="teamCompSearch"
type="text"
placeholder="Search by team name, player, or date…"
oninput="filterTeamCards(this.value)"
style="width:100%;padding:10px 36px 10px 13px;border:2px solid var(--input-border);border-radius:var(--radius-sm);font-size:.92em;font-family:inherit;background:var(--input-bg);color:var(--input-text);transition:border-color .2s;"
onfocus="this.style.borderColor='var(--primary)'" onblur="this.style.borderColor='var(--input-border)'"
/>
<span style="position:absolute;right:11px;top:50%;transform:translateY(-50%);font-size:1em;color:var(--text3);pointer-events:none;">🔍</span>
</div>
<div style="display:flex;flex-wrap:wrap;gap:6px;">
<button class="button" onclick="filterTeamsByPlayerCount(0)" id="tcfilter-all" style="font-size:.8em;padding:4px 10px;background:var(--primary);color:#fff;">Show All (${allTeamCards.length})</button>`;
playerCounts.forEach(count => {
const cnt = allTeamCards.filter(t => t.members.length === count).length;
html += `<button class="button" onclick="filterTeamsByPlayerCount(${count})" id="tcfilter-${count}" style="font-size:.8em;padding:4px 10px;">${count} Player${count !== 1 ? 's' :''} (${cnt})</button>`;
});
html += `  </div>
</div>
<div id="teamCompSummary" style="background:color-mix(in srgb,var(--accent-line) 9%,transparent);border:1px solid var(--panel-border);border-radius:8px;padding:10px 14px;margin-bottom:var(--sp);font-size:.85em;color:var(--primary);font-weight:600;">
${allTeamCards.length} unique team composition${allTeamCards.length !== 1 ? 's' :''} across <strong>${sessionCount} session${sessionCount !== 1 ? 's' :''}</strong>
</div>
<div id="teamCompList">`;
const accentColors = ['var(--primary)', 'var(--secondary)', 'var(--success)', '#e67e22', '#e74c3c'];
allTeamCards.forEach((team, ti) =>{
const color = accentColors[ti % accentColors.length];
const cardId = 'tcomp_' + team.members.join('_').replace(/\W/g, '_');
const acc = team.decisions ? Math.round(((team.decisions - team.negs - (team.misses || 0)) / team.decisions) * 100) : 0;
const memberTitle = team.members.join(' / ');
const eBonusTooltip = `Capitalization = 100 × (10 × bonuses) / (30 × (toss-ups + powers)). How well the team capitalized on the bonuses available after winning toss-ups.`;
const eTotalTooltip = `Point Control = 100 × (15P + 10T + 10B − 5N) / (45 × questions heard).`;
const statChips = [
['Points',   team.pts,      color],
['Toss-ups', team.tossups,  'var(--success)'],
['Bonuses',  team.bonuses,  'var(--primary)'],
['Powers',   team.powers,   'var(--pt-power)'],
['Negs',     team.negs,     'var(--danger)'],
['Misses',   team.misses,   'var(--warning)'],
['Accuracy', acc + '%',     'var(--text2)'],
].filter(([, v]) => v !== 0 && v !== '0%').map(([label, val, c]) =>
`<div style="text-align:center;background:var(--sec-bg);border:1.5px solid var(--border);border-radius:8px;padding:8px 12px;flex:1;min-width:64px;">
<div style="font-size:.72em;color:var(--text2);font-weight:600;margin-bottom:3px;">${label}</div>
<div style="font-size:.95em;font-weight:700;color:${c};">${val}</div>
</div>`
).join('');
html += `
<div class="team-comp-card" data-player-count="${team.members.length}" data-search="${[team.teamName, ...team.members, team.dateStr].join(' ').toLowerCase()}" style="background:var(--card);border:2px solid var(--border);border-left:4px solid ${color};border-radius:10px;margin-bottom:10px;overflow:hidden;box-shadow:var(--shadow-sm);">
<div onclick="toggleTeamCard('${cardId}')" style="display:flex;align-items:center;gap:12px;padding:13px 16px;cursor:pointer;user-select:none;">
<div class="flex-1-min0">
<div style="font-weight:700;font-size:1em;color:${color};display:flex;align-items:center;gap:8px;flex-wrap:wrap;">
${team.teamName}
${team.appearances > 1 ? `<span style="font-size:.7em;background:var(--success);color:#fff;padding:2px 8px;border-radius:8px;font-weight:700;">${team.appearances} Appearances</span>` :''}
</div>
<div style="font-size:.82em;color:var(--text);font-weight:600;margin-top:2px;">${memberTitle}</div>
<div style="font-size:.75em;color:var(--text2);margin-top:1px;">${team.dateStr} &bull; ${team.answers} Recorded Events</div>
</div>
<div style="display:flex;gap:8px;align-items:center;flex-shrink:0;">
<span style="font-size:1.05em;font-weight:700;color:var(--primary);">${team.pts} Pts</span>
<span id="${cardId}_arrow" style="font-size:.8em;color:var(--text2);transition:transform .2s;">&#9660;</span>
</div>
</div>
<div id="${cardId}" style="display:none;border-top:1.5px solid var(--border);">
<div style="padding:14px 16px;">
<div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:14px;">
${statChips}
</div>
<div style="border-top:1.5px solid var(--border);padding-top:12px;">
${effBar(team.eBonus, color, 'Capitalization', eBonusTooltip)}
${effBar(team.eTotal, color, 'Point Control', eTotalTooltip)}
${(team.eBonus === null && team.eTotal === null) ? '<div style="font-size:.8em;color:var(--text2);font-style:italic;">No Toss-Up Answers Recorded Yet.</div>' :''}
</div>
</div>
</div>
</div>`;
});
html += '</div>';
el.innerHTML = html;
const searchEl = $('teamCompSearch');
if (searchEl) searchEl.value = _teamCompSearchQuery || '';
expandedTeamCards.forEach(id =>{
const panel = $(id);
const arrow = $(id + '_arrow');
if (panel) panel.style.display = 'block';
if (arrow) arrow.style.transform = 'rotate(180deg)'; });
// Re-apply any active player-count filter / search query so the user's
// selection survives the periodic renderAll() triggered by autosave.
if (_currentTeamFilterCount > 0 || (_teamCompSearchQuery || '').trim()){
document.querySelectorAll('[id^="tcfilter-"]').forEach(btn => btn.classList.remove('active'));
const btn = $('tcfilter-' + (_currentTeamFilterCount === 0 ? 'all' : _currentTeamFilterCount));
if (btn) btn.classList.add('active');
filterTeamCards(_teamCompSearchQuery || '');
}
}
function toggleTeamCard(id){
const panel = $(id);
const arrow = $(id + '_arrow');
if (!panel) return;
const open = panel.style.display === 'none';
panel.style.display = open ? 'block' :'none';
if (arrow) arrow.style.transform = open ? 'rotate(180deg)' :'';
if (open) expandedTeamCards.add(id); else expandedTeamCards.delete(id); }
var _teamCompSearchQuery = '';
function filterTeamCards(query){
_teamCompSearchQuery = query || '';
const q = query.trim().toLowerCase();
const cards = document.querySelectorAll('.team-comp-card');
let visible = 0;
cards.forEach(card =>{
const playerCountMatch = _currentTeamFilterCount === 0 || parseInt(card.dataset.playerCount) === _currentTeamFilterCount;
const queryMatch = !q || card.dataset.search.includes(q);
const match = playerCountMatch && queryMatch;
card.style.display = match ? '' :'none';
if (match) visible++; });
const summary = $('teamCompSummary');
if (summary){
if (q || _currentTeamFilterCount > 0){
const filters = [];
if(_currentTeamFilterCount > 0) filters.push(`${_currentTeamFilterCount} player${_currentTeamFilterCount !== 1 ? 's' :''}`);
if(q) filters.push(`"${query}"`);
summary.textContent = visible === 0
? `No results for ${filters.join(' + ')}`
:`${visible} result${visible !== 1 ? 's' :''} for ${filters.join(' + ')}`;
} else{
const total = cards.length;
summary.innerHTML = `${total} unique team composition${total !== 1 ? 's' :''} across all sessions`;
}
}
}
var _currentTeamFilterCount = 0;
function filterTeamsByPlayerCount(count){
_currentTeamFilterCount = count;
document.querySelectorAll('[id^="tcfilter-"]').forEach(btn => btn.classList.remove('active'));
const btn = $('tcfilter-' + (count === 0 ? 'all' : count));
if(btn) btn.classList.add('active');
const query = $('teamCompSearch')?.value || '';
filterTeamCards(query); }
