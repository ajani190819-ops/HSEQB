function renderSubPanel(){
const s = getCurrentSession();
const el = $('subPanelContent');
if (!el || !s) return;
const activePlayers = [...new Set((s.teams||[]).flatMap(t=>t.playerMembers||[]))];
const poolPlayers   = Object.keys(s.players||{});
const bench         = poolPlayers.filter(p => !activePlayers.includes(p));
if (!activePlayers.length){
el.innerHTML = '<p style="color:var(--text2);font-size:.88em;">No active players yet. Add players to a team first.</p>';
return; }
if (_subOut && !activePlayers.includes(_subOut)) _subOut = null;
if (_subIn  && !bench.includes(_subIn))          _subIn  = null;
const chipStyle = (sel) =>
`display:inline-block;padding:5px 11px;border-radius:20px;cursor:pointer;font-size:.85em;font-weight:600;border:2px solid ${sel ? 'var(--primary)' :'var(--border)'};background:${sel ? 'var(--primary)' :'var(--sec-bg)'};color:${sel ? '#fff' :'var(--text1)'};transition:all .15s;user-select:none;`;
const outChips = activePlayers.map(p =>{
const sel = _subOut === p;
return `<span style="${chipStyle(sel)}" onclick="subPickOut('${p.replace(/'/g,"\\'")}');return false;">${getDisplayName(p, Object.keys(s.players||{}))}</span>`;
}).join('');
const inChips = bench.length
? bench.map(p =>{
const sel = _subIn === p;
return `<span style="${chipStyle(sel)}" onclick="subPickIn('${p.replace(/'/g,"\\'")}');return false;">${getDisplayName(p, Object.keys(s.players||{}))}</span>`;
}).join('') :'<span style="color:var(--text2);font-size:.82em;">No bench players available</span>';
const canSub = _subOut && _subIn;
const btnStyle = `width:100%;margin-top:4px;opacity:${canSub?1:.45};cursor:${canSub?'pointer':'not-allowed'};`;
el.innerHTML = `
<div style="display:flex;flex-direction:column;gap:8px;">
<div style="display:flex;align-items:baseline;gap:6px;margin-bottom:2px;">
<span style="font-size:.75em;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--text2);min-width:52px;">Sub Out</span>
<div class="flex-wrap-gap">${outChips}</div>
</div>
<div style="display:flex;align-items:baseline;gap:6px;">
<span style="font-size:.75em;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--text2);min-width:52px;">Sub In</span>
<div class="flex-wrap-gap">${inChips}</div>
</div>
<button onclick="executeSubFromPanel2();" class="button button-success" style="${btnStyle}" ${canSub?'':'disabled'}>
${_subOut && _subIn ? `⇄ ${getDisplayName(_subOut, Object.keys(s.players||{}))} → ${getDisplayName(_subIn, Object.keys(s.players||{}))}` :'⇄ Make Substitution'}
</button>
</div>
`;
}
function subPickOut(p){ _subOut = (_subOut === p) ? null :p; renderSubPanel(); }
function subPickIn(p) { _subIn  = (_subIn  === p) ? null :p; renderSubPanel(); }
function executeSubFromPanel(outPlayer){
const sel = $('subSelect_' + outPlayer);
if (!sel || !sel.value){ showToast('Select a bench player to swap in.', 'warn'); return; }
executeSubstitution(outPlayer, sel.value);
renderSubPanel(); }
function executeSubFromPanel2(){
if (!_subOut){ showToast('Please select the active player to substitute out.', 'warn'); return; }
if (!_subIn) { showToast('Please select the bench player to substitute in.', 'warn'); return; }
executeSubstitution(_subOut, _subIn);
_subOut = null; _subIn = null;
renderSubPanel(); }
