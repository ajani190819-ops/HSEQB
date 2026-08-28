var _chartInstances ={};
var _lastChartFingerprint = null;
function destroyChart(id){ if (_chartInstances[id]){ _chartInstances[id].destroy(); delete _chartInstances[id]; } }
Chart.register({
id:'doughnutGaps',
afterDatasetsDraw(chart){
if (chart.config.type !== 'doughnut') return;
const meta0 = chart.getDatasetMeta(0);
if (!meta0?.data?.length) return;
const{ ctx } = chart;
const _isDarkNow = document.body.classList.contains('dark-mode');
const gapCol     = _isDarkNow ? '#1c2128' :'#ffffff';
const outlineCol = _isDarkNow ? 'rgba(255,255,255,0.55)' :'rgba(0,0,0,0.38)';
const gapW    = 3;   // gap line width
const borderW = 2;   // outline width
meta0.data.forEach(arc =>{
if (!arc || arc.hidden) return;
const cx = arc.x, cy = arc.y;
const inner = arc.innerRadius, outer = arc.outerRadius;
const start = arc.startAngle, end = arc.endAngle;
const angularInset = (gapW / 2 + borderW) / outer;
const arcStart = start + angularInset;
const arcEnd   = end   - angularInset;
ctx.save();
ctx.strokeStyle = gapCol;
ctx.lineWidth = gapW;
[start, end].forEach(angle =>{
ctx.beginPath();
ctx.moveTo(cx + inner * Math.cos(angle), cy + inner * Math.sin(angle));
ctx.lineTo(cx + outer * Math.cos(angle), cy + outer * Math.sin(angle));
ctx.stroke(); });
ctx.restore();
if (arcEnd > arcStart){
const innerInset = inner > 4 ? inner + borderW / 2 :0;
const outerInset = outer - borderW / 2;
ctx.save();
ctx.beginPath();
ctx.arc(cx, cy, outerInset, arcStart, arcEnd);
if (innerInset > 0){
ctx.lineTo(cx + innerInset * Math.cos(arcEnd), cy + innerInset * Math.sin(arcEnd));
ctx.arc(cx, cy, innerInset, arcEnd, arcStart, true);
ctx.closePath(); }
ctx.strokeStyle = outlineCol;
ctx.lineWidth = borderW;
ctx.stroke();
ctx.restore(); }
}); }
});
function makeChart(id, config){
destroyChart(id);
const canvas = $(id);
if (canvas) _chartInstances[id] = new Chart(canvas.getContext('2d'), config); }
function buildChartFingerprint(log, ps){
const totalPts = ps.reduce((s, p) => s + p.points, 0);
const players  = ps.filter(p => p.totalAnswers > 0).map(p => p.name).sort().join('|');
const cats     = [...new Set(log.map(a => a.category).filter(Boolean))].sort().join('|');
return log.length + '|' + totalPts + '|' + players + '|' + cats; }
function renderAnalyticsCharts(allAnswers, ps, globalTHeard){
const el = $('an-charts'); if (!el) return;
Object.keys(_chartInstances).forEach(id => destroyChart(id));
if (!allAnswers.length){
el.innerHTML = '<p style="color:var(--text2);padding:20px;">No data recorded yet.</p>';
return; }
const cnt=t=>allAnswers.filter(a=>a.pointType===t).length;
const powers=cnt('Power'),tossups=cnt('Toss-up'),bonuses=cnt('Bonus'),negs=cnt('Neg'),misses=cnt('Miss'),deads=cnt('Dead');
const catAnswers ={}, catByType ={};
allAnswers.forEach(a=>{ if(!a.category||a.category==='—') return; const cat=getParentCat(a.category); catAnswers[cat]=(catAnswers[cat]||0)+1; if(!catByType[cat])catByType[cat]={Power:0,'Toss-up':0,Bonus:0,Neg:0,Miss:0,Dead:0}; if(catByType[cat][a.pointType]!==undefined)catByType[cat][a.pointType]++; });
const allCatsByVol = Object.keys(catAnswers).sort((a,b)=>catAnswers[b]-catAnswers[a]);
const activePlayers=ps.filter(p=>p.totalAnswers>0);
const playerCatPts ={};
const allCatsSet = new Set();
allAnswers.forEach(a=>{ if(!a.category||a.category==='—'||!isPlayerPerformanceAnswer(a)) return; const cat=getParentCat(a.category); allCatsSet.add(cat); if(!playerCatPts[a.player])playerCatPts[a.player]={}; playerCatPts[a.player][cat]=(playerCatPts[a.player][cat]||0)+(a.points||0); });
const sumCat=c=>activePlayers.reduce((s,pl)=>s+(playerCatPts[pl.name]?.[c]||0),0);
const allCatsList=[...allCatsSet].sort((a,b)=>sumCat(b)-sumCat(a));
const PALETTE=['#667eea','#764ba2','#11998e','#f39c12','#e74c5c','#3498db','#2ecc71','#e67e22','#9b59b6','#1abc9c','#e91e63','#00bcd4','#ff5722','#8bc34a','#ffc107','#607d8b','#795548','#ff9800','#4caf50','#2196f3'];
const _CC={'Literature':'#3b82f6','Science':'#11998e','History':'#f97316','Social Studies':'#eab308','Pop Culture':'#a855f7','Fine Arts':'#06b6d4'};
function catColor(p){return catColors[p]||_CC[p]||PALETTE[Object.keys(CATEGORY_TREE).indexOf(p)%PALETTE.length];}
function mixColor(hex,bg,r){const[R,G,B]=[1,3,5].map(i=>parseInt(hex.slice(i,i+2),16));return`rgb(${Math.round(R*r+bg[0]*(1-r))},${Math.round(G*r+bg[1]*(1-r))},${Math.round(B*r+bg[2]*(1-r))})`;}
// Canvas fills can't read CSS custom properties, so pull the painted accent
// (the HSE blue by default) and derive translucent chart colors from it.
function accentRgba(alpha, fb){
const v = (getComputedStyle(document.documentElement).getPropertyValue('--primary') || '').trim();
const hex = /^#[0-9a-f]{6}$/i.test(v) ? v : fb;
const [R,G,B] = [1,3,5].map(i => parseInt(hex.slice(i, i + 2), 16));
return `rgba(${R},${G},${B},${alpha})`;
}
const isDark=document.body.classList.contains('dark-mode');
const gridColor=isDark?'rgba(255,255,255,.10)':'rgba(0,0,0,.08)', labelColor=isDark?'#b8c0d8':'#3f475f';
const tooltipBg=isDark?'#1c2128':'#fff', tooltipTxt=isDark?'#e6eaf4':'#1a1a2e';
const baseFont={family:"-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif",size:12};
const dm=()=>document.body.classList.contains('dark-mode');
const pluginDefaults ={
legend:{ labels:{ color:labelColor, font:baseFont, boxWidth:14, padding:12 } },
tooltip:{
backgroundColor:()=>dm()?'#1c2128':'#fff', titleColor:()=>dm()?'#eef1f8':'#121a33',
bodyColor:()=>dm()?'#b8c0d8':'#3f475f', borderColor:()=>dm()?'#2d3340':'#dde1ea',
borderWidth:1, padding:10, cornerRadius:8, position:'nearest', caretSize:6
}
};
const pieOpts ={ responsive:true, maintainAspectRatio:false, plugins:{ ...pluginDefaults, legend:{ ...pluginDefaults.legend, position:allCatsByVol.length > 8 ? 'bottom' :'right' } } };
const barScales ={
x:{ticks:{color:labelColor,font:{...baseFont,size:11},maxRotation:40},grid:{color:gridColor}},
y:{ticks:{color:labelColor,font:baseFont},grid:{color:gridColor},beginAtZero:true}
};
const barOpts ={ responsive:true, maintainAspectRatio:false, plugins:pluginDefaults, scales:barScales };
const catBarH    = Math.max(260, allCatsByVol.length * 24 + 60);
const PIE_H = 300;
const catBarH_actual = catBarH;
const CAT_COUNT   = allCatsByVol.length;
const PLR_COUNT   = activePlayers.length;
function barMinW(count){
if (count <= 5)  return '280px';
if (count <= 10) return '420px';
return '100%'; }
const playerPtsH_raw      = Math.max(520, activePlayers.length * 56 + 180);
const playerBreakdownH_raw = Math.max(520, activePlayers.length * 56 + 180);
const playerCatH_raw      = Math.max(520, activePlayers.length * 56 + 180);
const playerSharedRow = barMinW(PLR_COUNT) !== '100%';
const playerUnifiedH  = Math.max(playerPtsH_raw, playerBreakdownH_raw, playerCatH_raw);
const playerPtsH      = playerSharedRow ? playerUnifiedH :playerPtsH_raw;
const playerBreakdownH = playerSharedRow ? playerUnifiedH :playerBreakdownH_raw;
const playerCatH      = playerSharedRow ? playerUnifiedH :playerCatH_raw;
function chartCard(id, title, height, minWidth){
const mw = minWidth || '280px';
return `<div class="ch-card" style="min-width:${mw};">
<div class="ch-title">${title}</div>
<div style="overflow-x:auto;overflow-y:hidden;border-radius:4px;">
<div style="position:relative;height:${height}px;min-width:${mw};"><canvas id="${id}"></canvas></div>
</div>
</div>`;
}
let html = `<style>
.ch-grid{ display:flex; flex-wrap:wrap; gap:var(--sp); align-items:flex-start; width:100%; box-sizing:border-box; }
.ch-player-row{ display:flex; flex-wrap:wrap; gap:var(--sp); width:100%; align-items:stretch; }
.ch-player-row .ch-card{ display:flex; flex-direction:column; }
.ch-player-row .ch-card > div:last-child{ flex:1; }
.ch-card{
background:var(--card);
border:2px solid var(--panel-border);
border-radius:10px;
padding:18px;
box-shadow:var(--shadow-sm);
flex:1 1 280px;
box-sizing:border-box;
overflow:hidden; }
.ch-title{ font-size:.95em; font-weight:700; color:var(--primary); margin-bottom:14px; }
.ch-section{
width:100%;
font-size:.75em;
font-weight:700;
letter-spacing:.08em;
text-transform:uppercase;
color:var(--text3);
padding:4px 0 2px;
border-bottom:1.5px solid var(--border);
margin-bottom:2px; }
/* Subcat doughnuts:JS sets grid-template-columns inline; cards fill columns evenly */
.ch-subcat-row{ width:100%; box-sizing:border-box; display:grid; gap:var(--sp); align-items:start; }
.ch-subcat-row .ch-card{ flex:none; width:100%; min-width:0; box-sizing:border-box; }
/* On small screens override the inline repeat(N,1fr) to wrap into 2 cols then 1 col */
@media (max-width:900px){
.ch-subcat-row{ grid-template-columns:repeat(2, 1fr) !important; }
}
@media (max-width:540px){
.ch-subcat-row{ grid-template-columns:1fr !important; }
}
</style>`;
html += `<div class="ch-grid">`;
html += `<div class="ch-section">Answer Breakdown</div>`;
html += chartCard('chart-type-pie', 'Answer Type Breakdown', PIE_H, '260px');
if (allCatsByVol.length) html += chartCard('chart-cat-vol', 'Category Volume', PIE_H, '260px');
if (allCatsByVol.length){
html += `<div class="ch-section">Categories</div>`;
html += chartCard('chart-cat-breakdown', 'Category Answer Breakdown by Type', catBarH_actual, barMinW(CAT_COUNT));
}
const parentsWithSubData = Object.entries(CATEGORY_TREE).filter(([parent, subs]) =>{
return subs.some(sub => allAnswers.some(a => a.category === sub)); });
if (parentsWithSubData.length){
html += `<div class="ch-section">Subcategory Breakdown</div>`;
const subcatCount = parentsWithSubData.length;
const subcatCols = subcatCount; // always one row — all charts same size
const maxSubcatH = parentsWithSubData.reduce((max, [parent, subs]) =>{
const sliceCount = subs.filter(s => allAnswers.some(a => a.category === s)).length
+ (allAnswers.some(a => a.category === parent) ? 1 :0);
return Math.max(max, Math.min(360, Math.max(220, 220 + (sliceCount - 3) * 22)));
}, 220);
html += `<div class="ch-subcat-row" style="grid-template-columns:repeat(${subcatCols},1fr);">`;
parentsWithSubData.forEach(([parent, subs]) =>{
const id = 'chart-subcat-' + parent.replace(/\s+/g,'_');
const activeSubs = subs.filter(s => allAnswers.some(a => a.category === s));
const totalVol = allAnswers.length || 1;
const pColor = catColor(parent);
const infoRows = activeSubs.map((sub, i) =>{
const expected   = catFreqs[sub] ?? null;
const actualCount = allAnswers.filter(a => a.category === sub).length;
const actualPct  = (actualCount / totalVol) * 100;
const expStr     = expected != null ? expected.toFixed(1) + '%' :'—';
const actStr     = actualPct.toFixed(1) + '%';
const gap        = expected != null ? expected - actualPct :null;
const gapColor   = gap == null ? 'var(--text3)'
:gap > 3  ? 'var(--danger)'
:gap > 1  ? '#f39c12'
:gap < -1 ? 'var(--success)' :'var(--text3)';
const bgBase = isDark ? [28,33,40] :[255,255,255];
const ratio  = activeSubs.length === 1 ? 0.65 :0.30 + 0.55 * (i / (activeSubs.length - 1));
const swatchCol = mixColor(pColor, bgBase, ratio);
return `<div style="display:grid;grid-template-columns:10px 1fr auto auto auto;align-items:center;gap:5px;padding:3px 0;border-bottom:1px solid var(--border);">
<span style="width:10px;height:10px;border-radius:2px;background:${swatchCol};flex-shrink:0;display:inline-block;"></span>
<span style="font-size:.78em;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${sub}</span>
<span style="font-size:.76em;color:var(--text2);font-variant-numeric:tabular-nums;text-align:right;">${actStr}</span>
<span style="font-size:.76em;color:var(--text3);padding:0 2px;">/</span>
<span style="font-size:.76em;color:${gapColor};font-variant-numeric:tabular-nums;text-align:right;">${expStr}</span>
</div>`;
}).join('');
html += `<div class="ch-card ch-subcat-card" style="display:flex;flex-direction:column;padding:0;overflow:hidden;">
<!-- Chart panel -->
<div style="padding:14px 14px 10px;">
<div class="ch-title" class="mb-10">${parent}</div>
<div style="position:relative;height:${maxSubcatH}px;width:100%;"><canvas id="${id}"></canvas></div>
</div>
<!-- Info panel -->
<div style="padding:10px 14px 12px;border-top:2px solid var(--border);background:var(--sec-bg);">
<div style="display:grid;grid-template-columns:10px 1fr auto auto auto;gap:5px;font-size:.68em;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:var(--text3);padding-bottom:4px;margin-bottom:2px;border-bottom:1.5px solid var(--border);">
<span></span><span>Subcategory</span><span class="text-right">Actual</span><span></span><span class="text-right">Exp.</span>
</div>
${infoRows}
</div>
</div>`;
});
html += `</div>`;
}
const distModel = buildPerformanceModel(activePlayers);
const rankedPlayers = activePlayers.filter(p => distModel.byName[p.name]?.ranked);
if (activePlayers.length >= 1){
html += `<div class="ch-section">Players</div>`;
html += `<div class="ch-player-row">`;
if (activePlayers.length > 1)
html += chartCard('chart-player-pts', 'Total Points by Player', playerPtsH, barMinW(PLR_COUNT));
if (activePlayers.length > 1)
html += chartCard('chart-player-breakdown', 'Player Answer Breakdown by Type', playerBreakdownH, barMinW(PLR_COUNT));
if (allCatsList.length)
html += chartCard('chart-player-cat', 'Player Points by Category', playerCatH, barMinW(PLR_COUNT));
html += `</div>`;
// Overall performance distribution: a histogram of ranked players' Leaderboard Scores.
if (rankedPlayers.length > 1){
html += `<div class="ch-section">Overall Performance</div><div class="ch-player-row">${chartCard('chart-player-distribution', 'Score Distribution — click a bar to view its players', 340, rankedPlayers.length > 4 ? '520px' : '300px')}</div>`;
html += `<div style="font-size:.74em;color:var(--text3);line-height:1.45;margin:6px 2px 0;">Bars group ranked players into Leaderboard Score bands; bar height is the share of ranked players in that band. The solid line traces the current distribution and the dashed curve shows the ideal bell shape. The gold line marks the team average. Click a bar to see its players in order. Players with fewer than ${RANKED_MIN_TU} TU heard are provisional and not plotted${distModel.provisionalCount ? ` (${distModel.provisionalCount} excluded)` : ''}.</div>`;
}
html += `</div>`;
}
el.innerHTML = html;
if (powers + tossups + bonuses + negs + misses + deads > 0){
const typeLabels = [], typeData = [], typeColors = [];
// Remapped palette: toss-ups green, bonus blue, neg red, miss grey, dead dark grey
function ptColor(name){
  const s = getComputedStyle(document.documentElement);
  const v = (n, fb) => (s.getPropertyValue(n).trim() || fb);
  const map = {
    Power: v('--pt-power', '#15803d'),
    'Toss-up': v('--pt-tossup', '#16a34a'),
    Bonus: v('--pt-bonus', '#2563eb'),
    Neg: v('--pt-neg', '#dc2626'),
    Miss: v('--pt-miss', '#6b7280'),
    Dead: v('--pt-dead', '#1f2937')
  };
  return map[name] || '#888';
}
if (powers) { typeLabels.push('TU ⚡︎ Power'); typeData.push(powers);  typeColors.push(ptColor('Power')); }
if (tossups){ typeLabels.push('Toss-up');     typeData.push(tossups); typeColors.push(ptColor('Toss-up')); }
if (bonuses){ typeLabels.push('Bonus');   typeData.push(bonuses); typeColors.push(ptColor('Bonus')); }
if (negs)   { typeLabels.push('Neg');     typeData.push(negs);    typeColors.push(ptColor('Neg')); }
if (misses) { typeLabels.push('Miss');    typeData.push(misses);  typeColors.push(ptColor('Miss')); }
if (deads)  { typeLabels.push('Dead');    typeData.push(deads);   typeColors.push(ptColor('Dead')); }
makeChart('chart-type-pie',{ type:'doughnut',
data:{ labels:typeLabels, datasets:[{ data:typeData, backgroundColor:typeColors, borderColor:'transparent', borderWidth:0 }] },
options:{ ...pieOpts, plugins:{ ...pieOpts.plugins, legend:{ ...pieOpts.plugins.legend, position:'right' } } }
}); }
if (allCatsByVol.length){
makeChart('chart-cat-vol',{type:'doughnut',
data:{labels:allCatsByVol,datasets:[{data:allCatsByVol.map(c=>catAnswers[c]),backgroundColor:allCatsByVol.map(c=>catColor(getParentCat(c))+'cc'),borderColor:'transparent',borderWidth:0}]},
options:pieOpts}); }
if (allCatsByVol.length){
makeChart('chart-cat-breakdown',{ type:'bar',
data:{labels:allCatsByVol,datasets:[
{label:'Powered TUs', data:allCatsByVol.map(c=>catByType[c]?.Power||0), backgroundColor:ptColor('Power')+'cc',borderColor:ptColor('Power'),borderWidth:3,borderRadius:3},
{label:'Toss-ups', data:allCatsByVol.map(c=>catByType[c]?.['Toss-up']||0), backgroundColor:ptColor('Toss-up')+'cc',borderColor:ptColor('Toss-up'),borderWidth:3,borderRadius:3},
{label:'Bonuses',  data:allCatsByVol.map(c=>catByType[c]?.Bonus||0),       backgroundColor:ptColor('Bonus')+'cc',borderColor:ptColor('Bonus'),borderWidth:3,borderRadius:3},
{label:'Negs',     data:allCatsByVol.map(c=>catByType[c]?.Neg||0),         backgroundColor:ptColor('Neg')+'cc',borderColor:ptColor('Neg'),borderWidth:3,borderRadius:3},
{label:'Misses',   data:allCatsByVol.map(c=>catByType[c]?.Miss||0),        backgroundColor:ptColor('Miss')+'cc',borderColor:ptColor('Miss'),borderWidth:3,borderRadius:3},
{label:'Dead',     data:allCatsByVol.map(c=>catByType[c]?.Dead||0),        backgroundColor:ptColor('Dead')+'cc',borderColor:ptColor('Dead'),borderWidth:3,borderRadius:3},
]},
options:{ ...barOpts, scales:{ ...barScales, x:{ ...barScales.x, stacked:true }, y:{ ...barScales.y, stacked:true } } }
}); }
if (activePlayers.length > 0 && allCatsList.length){
const pNames = activePlayers.map(p => p.name.split(' ')[0]);
const playerParentPts ={};
const playerSubPts ={};
allAnswers.forEach(a =>{
if (!a.category || a.category === '—' || !isPlayerPerformanceAnswer(a)) return;
const parent = getParentCat(a.category);
const sub    = a.category;
if (!playerParentPts[a.player]) playerParentPts[a.player] ={};
playerParentPts[a.player][parent] = (playerParentPts[a.player][parent] || 0) + (a.points || 0);
if (!playerSubPts[a.player]) playerSubPts[a.player] ={};
if (!playerSubPts[a.player][parent]) playerSubPts[a.player][parent] ={};
playerSubPts[a.player][parent][sub] = (playerSubPts[a.player][parent][sub] || 0) + (a.points || 0);
});
const parentSet = new Set();
allAnswers.forEach(a =>{ if (a.category && a.category !== '—') parentSet.add(getParentCat(a.category)); });
const parentList = [...parentSet].sort((a, b) =>{
const aT = activePlayers.reduce((s, p) => s + (playerParentPts[p.name]?.[a] || 0), 0);
const bT = activePlayers.reduce((s, p) => s + (playerParentPts[p.name]?.[b] || 0), 0);
return bT - aT; });
function makeHatch(hexColor, tintColor, spacing, angle){
const size = spacing || 8;
const c = document.createElement('canvas');
c.width = size; c.heightize;
const ctx = c.getContext('2d');
ctx.fillStyle = tintColor;
ctx.fillRect(0, 0, size, size);
ctx.strokeStyle = hexColor;
ctx.lineWidth = 1.5;
ctx.beginPath();
if (angle === 'back'){
ctx.moveTo(size, 0);     ctx.lineTo(0, size);
ctx.moveTo(size*2, 0);   ctx.lineTo(0, size*2);
ctx.moveTo(size, -size); ctx.lineTo(-size, size);
} else{
ctx.moveTo(0, 0);     ctx.lineTo(size, size);
ctx.moveTo(-size, 0); ctx.lineTo(size, size*2);
ctx.moveTo(0, -size); ctx.lineTo(size*2, size); }
ctx.stroke();
const chartCanvas = $('chart-player-cat');
const ref = (chartCanvas && chartCanvas.getContext) ? chartCanvas :c;
return ref.getContext('2d').createPattern(c, 'repeat'); }
function buildPlayerCatDatasets(expandedParents){
const bgBase = isDark ? [28, 33, 40] :[255, 255, 255];
const datasets = [];
parentList.forEach(parent =>{
const pColor = catColor(parent);
if (expandedParents.has(parent)){
const allSubs = CATEGORY_TREE[parent] || [];
const hasGeneral = activePlayers.some(p => playerSubPts[p.name]?.[parent]?.[parent]);
const subPool = [];
if (hasGeneral) subPool.push(parent);
allSubs.forEach(s =>{ if (activePlayers.some(p => (playerSubPts[p.name]?.[parent]?.[s] || 0) > 0)) subPool.push(s); });
const totalSubs = subPool.length;
subPool.forEach((sub, si) =>{
const minMix = 0.25, maxMix = 0.75;
const mixRatio = totalSubs === 1 ? 0.55 :minMix + (maxMix - minMix) * (si / (totalSubs - 1));
const tintColor = mixColor(pColor, bgBase, mixRatio); // Hatch lines on every subcategory bar; alternate direction per sub
const hatchAngle = si % 2 === 0 ? 'fwd' :'back';
const bgFill = makeHatch(pColor, tintColor, 7, hatchAngle);
datasets.push({
label:sub === parent ? `${parent} (General)` :sub,
data:activePlayers.map(p => playerSubPts[p.name]?.[parent]?.[sub] || 0),
backgroundColor:bgFill,
borderColor:pColor,
borderWidth:3, borderRadius:2, _parent:parent, _expanded:true,
}); });
} else{
datasets.push({
label:parent,
data:activePlayers.map(p => playerParentPts[p.name]?.[parent] || 0),
backgroundColor:pColor + 'cc',
borderColor:pColor,
borderWidth:3, borderRadius:3, _parent:parent, _expanded:false,
}); }
});
return datasets; }
const expandedParents = new Set();
function redrawPlayerCat(){
const datasets = buildPlayerCatDatasets(expandedParents);
const chart = _chartInstances['chart-player-cat'];
if (!chart) return;
chart.data.datasets = datasets;
chart.update('none');
const titleEl = chart.canvas.closest('.ch-card')?.querySelector('.ch-title');
if (titleEl){
titleEl.textContent = expandedParents.size
? `Player Points by Category — click expanded segment to collapse`
:`Player Points by Category — click a segment to expand`;
}
}
makeChart('chart-player-cat',{
type:'bar',
data:{ labels:pNames, datasets:buildPlayerCatDatasets(expandedParents) },
options:{
...barOpts,
scales:{ ...barScales, x:{ ...barScales.x, stacked:true }, y:{ ...barScales.y, stacked:true } },
plugins:{
...pluginDefaults,
tooltip:{ ...pluginDefaults.tooltip, mode:'index', intersect:false, itemSort:(a, b) => b.datasetIndex - a.datasetIndex, filter:item => item.raw > 0 },
legend:{ ...pluginDefaults.legend, position:'bottom', labels:{ ...pluginDefaults.legend.labels, padding:10, boxWidth:12 } }
},
onClick(evt, elements){
if (!elements.length) return;
const ds = this.data.datasets[elements[0].datasetIndex];
const parent = ds._parent;
if (!parent) return;
if (expandedParents.has(parent)) expandedParents.delete(parent);
else expandedParents.add(parent);
redrawPlayerCat(); },
onHover(evt, elements){
evt.native.target.style.cursor = elements.length ? 'pointer' :'default'; }
}
});
const titleEl = document.querySelector('#chart-player-cat')?.closest('.ch-card')?.querySelector('.ch-title');
if (titleEl) titleEl.textContent = 'Player Points by Category — click a segment to expand';
}
if (activePlayers.length > 1){
const pNames = activePlayers.map(p => p.name.split(' ')[0]);
makeChart('chart-player-breakdown',{ type:'bar',
data:{
labels:pNames,
datasets:[
{ label:'Powered TUs', data:activePlayers.map(p => p.powers), backgroundColor:ptColor('Power')+'cc', borderColor:ptColor('Power'), borderWidth:3, borderRadius:3 },
{ label:'Regular TUs', data:activePlayers.map(p => p.tossupsCorrect), backgroundColor:ptColor('Toss-up')+'cc', borderColor:ptColor('Toss-up'), borderWidth:3, borderRadius:3 },
{ label:'Negs', data:activePlayers.map(p => p.negs), backgroundColor:ptColor('Neg')+'cc', borderColor:ptColor('Neg'), borderWidth:3, borderRadius:3 },
{ label:'Misses', data:activePlayers.map(p => p.misses || 0), backgroundColor:ptColor('Miss')+'cc', borderColor:ptColor('Miss'), borderWidth:3, borderRadius:3 },
{ label:'Dead', data:activePlayers.map(p => p.deads || 0), backgroundColor:ptColor('Dead')+'cc', borderColor:ptColor('Dead'), borderWidth:3, borderRadius:3 },
]
},
options:{ ...barOpts, scales:{ ...barScales, x:{ ...barScales.x, stacked:true }, y:{ ...barScales.y, stacked:true } } }
}); }
if (activePlayers.length > 1){
const pNames = activePlayers.map(p => p.name.split(' ')[0]);
makeChart('chart-player-pts',{ type:'bar',
data:{ labels:pNames, datasets:[{ label:'Points', data:activePlayers.map(p => p.points), backgroundColor:activePlayers.map((_, i) => PALETTE[i % PALETTE.length] + 'cc'), borderColor:activePlayers.map((_, i) => PALETTE[i % PALETTE.length]), borderWidth:3, borderRadius:4 }] },
options:{ ...barOpts, plugins:{ ...barOpts.plugins, legend:{ display:false } } }
}); }
// ── Score distribution histogram ────────────────────────────────────────────
// Ranked players are bucketed into Leaderboard Score bands. Bars show the
// current distribution, the solid line traces those bars, and the dashed
// curve is the ideal bell for the ranked team. Clicking a bar lists the
// players in that band, in order (see openScoreBand).
scoreBandRegistry = null;
if (rankedPlayers.length > 1){
const distribution = distModel;
const scores = rankedPlayers.map(p => distribution.byName[p.name].adjustedImpact).sort((a,b) => a - b);
const distMin = scores[0], distMax = scores[scores.length - 1];
// Pick a round band width that yields a readable number of bands.
const binW = [5,10,15,20,25,30,40,50].find(s => (distMax - distMin) / s <= 9) || 50;
const firstBand = Math.floor(distMin / binW) * binW;
const lastBand = Math.floor(distMax / binW) * binW;
let bands = [];
for (let b = firstBand; b <= lastBand; b += binW){
bands.push({ lo:b, hi:b + binW, count:scores.filter(s => s >= b && s < b + binW).length });
}
// Trim empty bands at the edges so the bars span the actual data.
while (bands.length > 1 && bands[0].count === 0) bands = bands.slice(1);
while (bands.length > 1 && bands[bands.length - 1].count === 0) bands = bands.slice(0, -1);
const axisMin = bands[0].lo - binW * 0.45;
const axisMax = bands[bands.length - 1].hi + binW * 0.45;
const pct = c => scores.length ? (100 * c) / scores.length : 0;
const bandData = bands.map(b => ({ x:(b.lo + b.hi) / 2, y:pct(b.count) }));
// Ridge line traces the bars but skips empty bands so it does not zigzag to zero.
const ridgeData = bands.filter(b => b.count > 0).map(b => ({ x:(b.lo + b.hi) / 2, y:pct(b.count) }));
// Ideal bell: a normal reference shape fitted to the plotted (adjusted) scores'
// own center and spread, so its shape is always visible on the data's axis and
// deviations — skew, lumps, gaps — stand out against it.
const idealMean = scores.reduce((s,v) => s + v, 0) / scores.length;
const idealVar = scores.reduce((s,v) => s + Math.pow(v - idealMean, 2), 0) / scores.length;
const idealSd = idealVar > 0 ? Math.sqrt(idealVar) : binW;
const ideal = [];
for (let i = 0; i <= 72; i++){
const x = axisMin + ((axisMax - axisMin) * i / 72);
const pdf = Math.exp(-0.5 * Math.pow((x - idealMean) / idealSd, 2)) / (idealSd * Math.sqrt(2 * Math.PI));
ideal.push({ x, y:pdf * binW * 100 });
}
const isDarkDist = document.body.classList.contains('dark-mode');
const barFill = isDarkDist ? accentRgba(.5, '#527cc2') : accentRgba(.45, '#2257b1');
const scoreBandTooltip = { ...pluginDefaults.tooltip, callbacks:{
title:items =>{
const it = items && items[0];
if (!it) return '';
if (it.datasetIndex === 0){ const b = bands[it.dataIndex]; return b ? `Band ${b.lo}–${b.hi}` : ''; }
return it.dataset.label;
},
label:ctx =>{
if (ctx.datasetIndex === 0){
const b = bands[ctx.dataIndex];
return `${b.count} ranked player${b.count !== 1 ? 's' : ''} (${pct(b.count).toFixed(0)}%) — click to view`;
}
return ctx.dataset.label;
}
} };
const averageLinePlugin = {
id:'performanceAverageLine',
afterDraw(chart){
const xScale = chart.scales.x, yScale = chart.scales.y;
if (!xScale || !yScale) return;
const x = xScale.getPixelForValue(distribution.average);
const ctx = chart.ctx;
ctx.save();
ctx.strokeStyle = isDarkDist ? 'rgba(255,212,59,.9)' : 'rgba(196,132,0,.9)';
ctx.lineWidth = 2;
ctx.setLineDash([6,4]);
ctx.beginPath(); ctx.moveTo(x, yScale.top); ctx.lineTo(x, yScale.bottom); ctx.stroke();
ctx.setLineDash([]);
ctx.fillStyle = isDarkDist ? '#ffd43b' : '#9a6700';
ctx.font = '700 11px -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif';
ctx.textAlign = 'center';
ctx.fillText('Team average', x, yScale.top + 14);
ctx.restore();
}
};
// Bars must span their exact score band. Scale pixel geometry only exists after
// Chart.js fits the layout (async via ResizeObserver), so size the bars in
// afterLayout — it runs on first render and on every resize before the bar
// elements are rebuilt, so bars stay glued to their bands at any chart size.
const bandSizingPlugin = {
id:'scoreBandSizing',
afterLayout(chart){
const ds = chart.data.datasets && chart.data.datasets[0];
if (!ds || ds.type !== 'bar') return;
const xs = chart.scales.x;
if (!xs || !Number.isFinite(xs.getPixelForValue(0))) return;
const span = Math.abs(xs.getPixelForValue(binW) - xs.getPixelForValue(0));
if (span > 0) ds.barThickness = Math.max(4, span * 0.86);
}
};
scoreBandRegistry = { bands, binW, average:distribution.average, entries:rankedPlayers.map(p =>({ name:p.name, score:distribution.byName[p.name].adjustedImpact, raw:distribution.byName[p.name].rawImpact || 0, tHeard:p.tHeard || 0 })) };
makeChart('chart-player-distribution',{ type:'scatter',
data:{ datasets:[
{ type:'bar', label:'Ranked players', data:bandData, parsing:false, backgroundColor:barFill, borderColor:'#667eea', borderWidth:1.5, borderRadius:3, barThickness:24 },
{ type:'line', label:'Current distribution', data:ridgeData, parsing:false, showLine:true, borderColor:'#3d4ca8', backgroundColor:'rgba(61,76,168,.08)', borderWidth:2, pointRadius:0, tension:.35, fill:true },
{ type:'line', label:'Ideal bell curve', data:ideal, parsing:false, showLine:true, borderColor:'#764ba2', borderWidth:2.5, borderDash:[7,5], pointRadius:0, tension:.3, fill:false }
] },
options:{ ...barOpts,
onClick:(evt, els) =>{ const bar = els.find(e => e.datasetIndex === 0); if (bar) openScoreBand(bar.index); },
onHover:(evt, els, chart) =>{ if (chart.canvas) chart.canvas.style.cursor = els.some(e => e.datasetIndex === 0) ? 'pointer' : 'default'; },
scales:{
x:{ type:'linear', min:axisMin, max:axisMax, ticks:{ color:labelColor, font:{...baseFont,size:11}, maxTicksLimit:9 }, grid:{ color:gridColor }, title:{ display:true, text:'Leaderboard Score (higher is better →)', color:labelColor, font:{...baseFont,size:11} } },
y:{ min:0, suggestedMax:Math.max(12, Math.max(...ideal.map(p => p.y), ...bandData.map(p => p.y)) * 1.15), ticks:{ color:labelColor, font:{...baseFont,size:11}, callback:v => v + '%' }, grid:{ color:gridColor }, title:{ display:true, text:'Share of ranked players', color:labelColor, font:{...baseFont,size:11} } }
},
plugins:{ ...pluginDefaults, legend:{ ...pluginDefaults.legend, position:'bottom' }, tooltip:scoreBandTooltip }
},
plugins:[averageLinePlugin, bandSizingPlugin]
});
}
Object.entries(CATEGORY_TREE).forEach(([parent, subs]) =>{
const subCounts ={};
let hasData = false;
subs.forEach(sub =>{
const cnt = allAnswers.filter(a => a.category === sub).length;
if (cnt > 0){ subCounts[sub] = cnt; hasData = true; }
});
const generalCnt = allAnswers.filter(a => a.category === parent).length;
if (generalCnt > 0){ subCounts['General'] = generalCnt; hasData = true; }
if (!hasData) return;
const labels = Object.keys(subCounts);
const data   = Object.values(subCounts);
const pColor = catColor(parent);
const bgBase = isDark ? [28, 33, 40] :[255, 255, 255];
const colors = labels.map((_, i) =>{
const ratio = labels.length === 1 ? 0.65 :0.30 + 0.55 * (i / (labels.length - 1));
return mixColor(pColor, bgBase, ratio); });
makeChart('chart-subcat-' + parent.replace(/\s+/g,'_'),{
type:'doughnut',
data:{ labels, datasets:[{ data, backgroundColor:colors, borderColor:'transparent', borderWidth:0 }] },
options:{ ...pieOpts, maintainAspectRatio:false, plugins:{ ...pieOpts.plugins,
legend:{ display:false }
} }
}); });
}
