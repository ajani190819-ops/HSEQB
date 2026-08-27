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
function _shadeHex(hex, amount){
  const n = parseInt(hex.slice(1), 16);
  const mix = c => Math.round(amount < 0 ? c * (1 + amount) : c + (255 - c) * amount);
  const r = mix((n >> 16) & 255), g = mix((n >> 8) & 255), b = mix(n & 255);
  return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
}
function _isHex(v){ return /^#[0-9a-f]{6}$/i.test(v || ''); }
// Paint the four accent custom properties. Everything else in the stylesheet
// derives from these, so light/dark mode stays completely independent.
function _paintColors(primary, secondary){
  const root = document.documentElement.style;
  root.setProperty('--primary', primary);
  root.setProperty('--primary-light', _shadeHex(primary, 0.28));
  root.setProperty('--primary-dark',  _shadeHex(primary, -0.28));
  root.setProperty('--secondary', secondary || _shadeHex(primary, -0.45));
}
function applyColorTheme(id, persistLocal, syncRemote){
  const custom = id === 'custom';
  const theme = custom ? null : getColorTheme(id);
  if (!custom && !theme) return applyColorTheme(DEFAULT_COLOR_THEME, persistLocal, syncRemote);
  colorTheme = custom ? 'custom' : theme.id;
  const primary   = custom ? customThemeColors.primary   : theme.primary;
  const secondary = custom ? customThemeColors.secondary : theme.secondary;
  _paintColors(primary, secondary);
  if (persistLocal !== false){
    localStorage.setItem('colorTheme', colorTheme);
    localStorage.setItem('accentColor', primary); // legacy key stays in sync
    if (custom){
      localStorage.setItem('customPrimary', primary);
      localStorage.setItem('customSecondary', secondary);
    }
  }
  syncColorThemeControls();
  if (typeof _chartInstances !== 'undefined' && _chartInstances){
    Object.values(_chartInstances).forEach(chart =>{ try{ chart.update(); }catch(e){} });
  }
  if (syncRemote !== false) scheduleUserProfileSave();
}
function setColorTheme(id){ applyColorTheme(id, true, true); }
function setCustomThemeColor(which, value){
  if (!_isHex(value)) return;
  customThemeColors[which === 'secondary' ? 'secondary' : 'primary'] = value.toLowerCase();
  applyColorTheme('custom', true, true);
}
function resetCustomTheme(){
  const base = getColorTheme(DEFAULT_COLOR_THEME);
  customThemeColors = { primary:base.primary, secondary:base.secondary };
  applyColorTheme('custom', true, true);
}
// Rebuild the swatch grid, mark the active card, and mirror the custom inputs.
function renderColorThemeGrid(){
  const grid = $('colorThemeGrid');
  if (!grid) return;
  grid.innerHTML = COLOR_THEMES.map(t => `
    <button type="button" class="theme-swatch${colorTheme === t.id ? ' active' : ''}" data-theme="${t.id}"
            onclick="setColorTheme('${t.id}')" aria-pressed="${colorTheme === t.id}" title="${t.name} — ${t.sub}">
      <span class="theme-swatch-chip" style="background:linear-gradient(135deg,${t.primary},${t.secondary});"></span>
      <span class="theme-swatch-name">${t.name}</span>
      <span class="theme-swatch-sub">${t.sub}</span>
    </button>`).join('') + `
    <button type="button" class="theme-swatch theme-swatch-custom${colorTheme === 'custom' ? ' active' : ''}" data-theme="custom"
            onclick="setColorTheme('custom')" aria-pressed="${colorTheme === 'custom'}" title="Custom — pick your own colors">
      <span class="theme-swatch-chip" style="background:linear-gradient(135deg,${customThemeColors.primary},${customThemeColors.secondary});"></span>
      <span class="theme-swatch-name">Custom</span>
      <span class="theme-swatch-sub">Your colors</span>
    </button>`;
}
function syncColorThemeControls(){
  renderColorThemeGrid();
  const panel = $('customThemePanel');
  if (panel) panel.style.display = colorTheme === 'custom' ? 'block' : 'none';
  const p = $('customPrimaryInput');    if (p) p.value = customThemeColors.primary;
  const s = $('customSecondaryInput');  if (s) s.value = customThemeColors.secondary;
  const ph = $('customPrimaryHex');     if (ph) ph.value = customThemeColors.primary;
  const sh = $('customSecondaryHex');   if (sh) sh.value = customThemeColors.secondary;
  const active = colorTheme === 'custom' ? { name:'Custom', sub:'Your colors' } : getColorTheme(colorTheme);
  const label = $('activeThemeLabel');
  if (label && active) label.textContent = active.name + ' — ' + active.sub;
}
// Back-compat: older profiles and LOCAL_SETTINGS store a bare accent hex.
function setAccentColor(color, persistLocal, syncRemote){
  if (!_isHex(color)) return;
  const match = COLOR_THEMES.find(t => t.primary.toLowerCase() === color.toLowerCase());
  if (match) return applyColorTheme(match.id, persistLocal, syncRemote);
  customThemeColors = { primary:color.toLowerCase(), secondary:_shadeHex(color, -0.45) };
  applyColorTheme('custom', persistLocal, syncRemote);
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
