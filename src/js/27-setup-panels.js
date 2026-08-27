function selectPlayer(p){state.selectedPlayer=state.selectedPlayer===p?null:p;renderPlayerButtons();}
function handlePlayerImport(event){
const file=event.target.files[0]; if(!file) return;
const reader=new FileReader();
reader.onload=e=>{
const players=e.target.result.replace(/\r\n?/g,'\n').split('\n').flatMap(l=>l.split(/[,;]+/)).map(p=>p.trim()).filter(Boolean);
const id=state.currentSessionId; if(!id) return;
updateSessionAtomic(id,s=>{if(!s.players) s.players={};players.forEach(p=>{if(!s.players[p]) s.players[p]={name:p,points:0,answers:[]};});}).then(()=>saveGlobalPlayers(players));
withWriteLock(id,()=>{const s=getCurrentSession();if(!s.players) s.players={};players.forEach(p=>{if(!s.players[p]) s.players[p]={name:p,points:0,answers:[]};});});
renderPlayerPool(); renderPlayerButtons(); renderSubPanel(); renderTeams(); };
reader.readAsText(file); event.target.value=''; }
function addTeam(){
const input=$('teamNameInput');
const name=input.value.trim(); if(!name){showToast('Please enter a team name.');return;}
const id=state.currentSessionId; if(!id) return;
const team={id:Date.now().toString(),name,playerMembers:[]};
updateSessionAtomic(id,s=>{s.teams=toArray(s.teams);s.teams.push(team);});
withWriteLock(id,()=>{const s=getCurrentSession();s.teams=toArray(s.teams);s.teams.push(team);});
input.value=''; renderTeams(); }
function removeTeam(teamId){
const id=state.currentSessionId; if(!id) return;
const filter=s=>{s.teams=toArray(s.teams).filter(t=>t.id!==teamId);};
updateSessionAtomic(id,filter);
withWriteLock(id,()=>{const s=getCurrentSession();if(s) filter(s);});
renderTeams(); renderPlayerButtons(); renderSubPanel(); }
function updateTeamName(teamId,newName){
const id=state.currentSessionId; if(!id) return;
const update=s=>{const t=toArray(s.teams).find(t=>t.id===teamId);if(t) t.name=newName;};
updateSessionAtomic(id,update);
withWriteLock(id,()=>{const s=getCurrentSession();if(s) update(s);});
}
function togglePlayerInTeam(teamId,player){
const id=state.currentSessionId; if(!id) return;
const toggle=s=>{const t=toArray(s.teams).find(t=>t.id===teamId);if(!t) return;t.playerMembers=toArray(t.playerMembers);const i=t.playerMembers.indexOf(player);if(i>-1) t.playerMembers.splice(i,1);else t.playerMembers.push(player);};
updateSessionAtomic(id,toggle);
withWriteLock(id,()=>{const s=getCurrentSession();if(s) toggle(s);});
renderTeams(); renderPlayerButtons(); renderSubPanel(); }
function renderTeams(){
const s=getCurrentSession(); const el=$('teamsContainer');
if(!el||!s) return;
const teams=s.teams||[];
if(!teams.length){el.innerHTML='<p class="text-2">No teams created yet.</p>';return;}
const players=Object.keys(s.players||{});
el.innerHTML=teams.map(team=>`
<div class="team-section">
<input type="text" value="${team.name}" onchange="updateTeamName('${team.id}',this.value)" />
<div style="margin-top:10px;display:flex;flex-wrap:wrap;gap:8px;">
${players.length?players.map(p=>`<button class="button-category ${team.playerMembers.includes(p)?'selected':''}" onclick="togglePlayerInTeam('${team.id}','${p}')">${p}</button>`).join(''):'<p class="text-2">No players available.</p>'}
</div>
<button class="button button-danger" onclick="removeTeam('${team.id}')" class="mt-10">Remove Team</button>
</div>`).join('');
}
function renderCategoryTreeDisplay(){
const el = $('categoryTreeDisplay'); if (!el) return;
el.innerHTML = Object.entries(CATEGORY_TREE).map(([parent, subs]) =>
`<div class="mb-8">
<div style="font-size:.78em;font-weight:700;text-transform:uppercase;letter-spacing:.05em;color:var(--text2);margin-bottom:4px;">${parent}</div>
<div style="display:flex;flex-wrap:wrap;gap:4px;">${subs.map(s=>`<span style="font-size:.8em;padding:2px 8px;border-radius:10px;background:var(--sec-bg);border:1.5px solid var(--border);color:var(--text1);">${s}</span>`).join('')}</div>
</div>`
).join(''); }
var _selectedParentCat = null;
function renderCategories(){
const el = $('categoryButtonsContainer');
const group = $('categoryInputGroup');
if (!el) return;
const noCategory = state.selectedPointType === 'Neg' || state.selectedPointType === 'Dead';
if (group) group.style.display = noCategory ? 'none' :'';
if (noCategory){ el.innerHTML = ''; return; }
let html = '';
Object.entries(CATEGORY_TREE).forEach(([parent, subs]) =>{
const parentSel = state.selectedCategory === parent;
html += `<div class="cat-group">`;
html += `<button class="cat-group-label${parentSel ? ' selected' :''}" onclick="selectCategory('${parent.replace(/'/g,"\\'")}');" title="General ${parent}">${parent}</button>`;
subs.forEach(sub =>{
const sel = state.selectedCategory === sub;
html += `<button class="cat-group-chip${sel ? ' selected' :''}" onclick="selectCategory('${sub.replace(/'/g,"\\'")}');">${sub}</button>`;
});
html += `</div>`;
});
el.innerHTML = html; }
function selectCategory(c){
state.selectedCategory = state.selectedCategory === c ? null :c;
_selectedParentCat = state.selectedCategory ? (CAT_PARENT[state.selectedCategory] || state.selectedCategory) :null;
renderCategories(); }
