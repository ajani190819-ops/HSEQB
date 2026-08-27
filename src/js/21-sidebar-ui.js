function setupSectionToggle(){
document.querySelectorAll('.qb-section h2').forEach(h2=>h2.addEventListener('click',function(){
this.querySelector('.toggle-icon')?.classList.toggle('collapsed');
this.nextElementSibling?.classList.toggle('collapsed');
})); }
const SECTION_LABELS={'sec-session':'Setup','sec-players':'Setup','sec-teams':'Setup','sec-categories':'Setup','sec-export':'Session & Data','sec-userid':'Settings','sec-visual':'Settings','sec-admin':'Admin Panel','sec-danger':'Session & Data','sec-debug':'Session & Data'};
function showSection(id){
document.querySelectorAll('.qb-sidebar .qb-section').forEach(s=>s.classList.remove('active-section'));
const el=$(id);
if(el){ el.classList.add('active-section'); el.querySelector('.collapsible-content')?.classList.remove('collapsed'); el.querySelector('.toggle-icon')?.classList.remove('collapsed'); }
localStorage.setItem('activeSidebarSection',id);
updateJumpDropdown(id);
$('sidebarJumpWrapper')?.classList.remove('open'); }
function updateJumpDropdown(activeId){
const labelEl=$('sidebarJumpLabel');
if(labelEl&&SECTION_LABELS[activeId]) labelEl.textContent=SECTION_LABELS[activeId];
document.querySelectorAll('.sidebar-jump-menu button').forEach(btn=>btn.classList.toggle('active-item',(btn.getAttribute('onclick')||'').includes(activeId)));
}
function toggleJumpDropdown(){ $('sidebarJumpWrapper')?.classList.toggle('open'); }
function toggleDangerZone(){
const body=$('dangerZoneBody'), arrow=$('dangerZoneArrow');
if(!body) return;
const open=body.style.display==='none';
body.style.display=open?'':'none';
if(arrow) arrow.style.transform=open?'':'rotate(-90deg)'; }
const isMobile = () => !isIframe && window.innerWidth <= 900;
if (isIframe){
const _memStore ={};
const _safeLS ={
getItem:   k => (_memStore[k] !== undefined ? _memStore[k] :null),
setItem:   (k, v) =>{ _memStore[k] = String(v); },
removeItem:k =>{ delete _memStore[k]; },
clear:     () =>{ Object.keys(_memStore).forEach(k => delete _memStore[k]); },
key:       i => Object.keys(_memStore)[i] || null,
get length(){ return Object.keys(_memStore).length; }
};
try{ Object.defineProperty(window, 'localStorage',{ get:() => _safeLS }); } catch(e){}
document.body.classList.add('dark-mode'); }
var _iframeDebugActive = false;
function toggleSidebar(){
const sidebar=$('mainSidebar');
const scroll=$('qbScroll');
const ascroll=$('analyticsScroll');
if(!sidebar) return;
if(isMobile()){
const opening=!sidebar.classList.contains('mobile-open');
sidebar.classList.toggle('mobile-open',opening);
scroll?.classList.toggle('menu-blurred',opening);
ascroll?.classList.toggle('menu-blurred',opening);
document.body.classList.toggle('menu-open',opening);
updateMobileBtn(opening);
} else{
const collapsed=sidebar.classList.toggle('collapsed');
if (!isIframe) localStorage.setItem('sidebarCollapsed',collapsed);
if (!isIframe) scheduleUserProfileSave();
updateDesktopBtn(collapsed); }
}
function updateDesktopBtn(collapsed){
const btn = $('sidebarOpenBtn'); if (!btn) return;
btn.style.display = (!isMobile() && !isIframe && !collapsed) ? 'none' :'inline-flex';
}
function updateMobileBtn(open){ const btn=$('sidebarOpenBtnMobile'); if(btn) btn.innerHTML=open?'&#9664; Hide':'&#9654; Menu'; }
function applySidebarState(){
const sidebar=$('mainSidebar');
const scroll=$('qbScroll');
const ascroll=$('analyticsScroll');
if(!sidebar) return;
sidebar.classList.remove('mobile-open');
scroll?.classList.remove('menu-blurred');
ascroll?.classList.remove('menu-blurred');
document.body.classList.remove('menu-open');
updateMobileBtn(false);
if(isMobile()){sidebar.classList.remove('collapsed');updateDesktopBtn(false);}
else{const c=isIframe?false:localStorage.getItem('sidebarCollapsed')==='true';sidebar.classList.toggle('collapsed',c);updateDesktopBtn(c);}
}
function toggleDarkMode(){
  setThemeMode(themeMode === 'dark' ? 'light' : 'dark', true);
}
function setAccentColor(color, persistLocal, syncRemote){
  if (!/^#[0-9a-f]{6}$/i.test(color || '')) return;
  document.documentElement.style.setProperty('--primary', color);
  if (persistLocal !== false) localStorage.setItem('accentColor', color);
  const select=$('accentColorSelect'); if(select) select.value=color;
  if (syncRemote !== false) scheduleUserProfileSave();
}
function changeSkillThreshold(delta){
const oldThreshold = skillThresholdPct;
skillThresholdPct = Math.max(0, Math.min(80, skillThresholdPct + delta));
saveGlobalSettings();
updateSkillThresholdUI();
if(analyticsOpen) renderAnalyticsPlayersUniversal();
showToast(`Skill threshold changed from ${oldThreshold}% to ${skillThresholdPct}%`, 'success', 3000, () =>{
skillThresholdPct = oldThreshold;
saveGlobalSettings();
updateSkillThresholdUI();
if(analyticsOpen) renderAnalyticsPlayersUniversal(); });
}
function updateSkillThresholdUI(){
const display = $('skillThresholdDisplay');
const bar = $('skillThresholdBar');
if(display) display.textContent = skillThresholdPct + '%';
if(bar) bar.style.width = skillThresholdPct + '%';
}
function initSkillThresholdUI(){
updateSkillThresholdUI(); }
function toggleScrollbars(){
const on=document.body.classList.toggle('hide-scrollbars');
localStorage.setItem('hideScrollbars',on);
const el=$('hideScrollbarsToggle'); if(el) el.checked=on;
scheduleUserProfileSave(); }
