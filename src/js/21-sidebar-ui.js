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
function _hexLum(hex){
  const n = parseInt(hex.slice(1), 16);
  return (0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)) / 255;
}
function _mixHex(a, b, t){
  const pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
  const ch = (v, s) => (v >> s) & 255;
  const mix = s => Math.round(ch(pa, s) + (ch(pb, s) - ch(pa, s)) * t);
  return '#' + ((1 << 24) + (mix(16) << 16) + (mix(8) << 8) + mix(0)).toString(16).slice(1);
}
function _clamp01(v){ return Math.max(0, Math.min(1, v)); }
function _hexToRgb(hex){
  const n = parseInt(hex.slice(1), 16);
  return { r:(n >> 16) & 255, g:(n >> 8) & 255, b:n & 255 };
}
function _hexToHsl(hex){
  const { r, g, b } = _hexToRgb(hex);
  const rr = r / 255, gg = g / 255, bb = b / 255;
  const max = Math.max(rr, gg, bb), min = Math.min(rr, gg, bb);
  const l = (max + min) / 2;
  if (max === min) return { h:0, s:0, l };
  const d = max - min;
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  const h = (max === rr
    ? ((gg - bb) / d) + (gg < bb ? 6 : 0)
    : max === gg
      ? ((bb - rr) / d) + 2
      : ((rr - gg) / d) + 4) * 60;
  return { h, s, l };
}
function _hslToHex(h, s, l){
  const hue = ((h % 360) + 360) % 360;
  const sat = _clamp01(s), light = _clamp01(l);
  const c = (1 - Math.abs(2 * light - 1)) * sat;
  const hp = hue / 60;
  const x = c * (1 - Math.abs(hp % 2 - 1));
  let rgb = [0, 0, 0];
  if (hp < 1) rgb = [c, x, 0];
  else if (hp < 2) rgb = [x, c, 0];
  else if (hp < 3) rgb = [0, c, x];
  else if (hp < 4) rgb = [0, x, c];
  else if (hp < 5) rgb = [x, 0, c];
  else rgb = [c, 0, x];
  const m = light - c / 2;
  return '#' + rgb.map(v => Math.round((v + m) * 255).toString(16).padStart(2, '0')).join('');
}
function _boostHexForDarkSurface(hex){
  if (!_isHex(hex)) return hex;
  const { h, s, l } = _hexToHsl(hex);
  const lum = _hexLum(hex);
  const sat = _clamp01(s < 0.75 ? s + 0.06 : s * 1.01);
  const lift = 0.05 + Math.max(0, 0.30 - lum) * 0.16;
  const floor = 0.39 + Math.max(0, 0.22 - lum) * 0.14;
  return _hslToHex(h, sat, Math.min(0.58, Math.max(l + lift, floor)));
}
// Paint the accent properties from the palette's base colors. Light mode keeps
// the calmer, slightly lifted treatment for white surfaces; dark mode now lifts
// colors with a small saturation boost too, so outlines and gradients stay
// vivid instead of drifting toward gray.
function _paintColors(primary, secondary, tertiary, accent){
  const root = document.documentElement.style;
  const dark = themeIsDark(themeMode);
  const adapt = (hex) => {
    if (!_isHex(hex)) return hex;
    if (dark) return _boostHexForDarkSurface(hex);
    const lum = _hexLum(hex);
    return lum < 0.34 ? _shadeHex(hex, (0.34 - lum) * 1.1) : hex;
  };
  const blue = adapt(primary);
  const gradientEnd = adapt(secondary || accent || _shadeHex(primary, -0.45));
  const accentTone = adapt(accent || secondary || _shadeHex(primary, -0.45));
  const white = dark ? '#f4f6fb' : (tertiary || '#ffffff');
  // Pinstripe style: gradients stay in the primary family while the accent
  // color moves into thin diagonal lines, tinted panels, and outline accents.
  const stripes = (typeof accentStyle === 'undefined') || accentStyle !== 'gradient';
  const gradEnd = stripes ? _mixHex(blue, dark ? '#dfe6f5' : '#ffffff', dark ? 0.30 : 0.32) : gradientEnd;
  root.setProperty('--primary', blue);
  root.setProperty('--primary-light', _shadeHex(blue, dark ? 0.24 : 0.28));
  root.setProperty('--primary-dark',  _shadeHex(blue, -0.28));
  root.setProperty('--secondary', gradEnd);
  root.setProperty('--accent-line', accentTone);
  root.setProperty('--tertiary', white);
  root.setProperty('--hse-blue', blue);
  root.setProperty('--hse-red', accentTone);
  root.setProperty('--hse-white', white);
}
function applyColorTheme(id, persistLocal, syncRemote){
  const custom = id === 'custom';
  const theme = custom ? null : getColorTheme(id);
  if (!custom && !theme) return applyColorTheme(DEFAULT_COLOR_THEME, persistLocal, syncRemote);
  colorTheme = custom ? 'custom' : theme.id;
  const primary   = custom ? customThemeColors.primary   : theme.primary;
  const secondary = custom ? customThemeColors.secondary : theme.secondary;
  const tertiary  = custom ? customThemeColors.tertiary : theme.tertiary;
  const accent    = custom ? (customThemeColors.accent || customThemeColors.secondary) : (theme.accent || theme.secondary);
  _paintColors(primary, secondary, tertiary, accent);
  if (persistLocal !== false){
    localStorage.setItem('colorTheme', colorTheme);
    localStorage.setItem('accentColor', primary); // legacy key stays in sync
    if (custom){
      localStorage.setItem('customPrimary', primary);
      localStorage.setItem('customSecondary', secondary);
      localStorage.setItem('customAccent', accent);
    }
  }
  syncColorThemeControls();
  if (typeof _chartInstances !== 'undefined' && _chartInstances){
    Object.values(_chartInstances).forEach(chart =>{ try{ chart.update(); }catch(e){} });
  }
  if (syncRemote !== false) scheduleUserProfileSave();
}
function setColorTheme(id){ applyColorTheme(id, true, true); }
// Accent style: 'stripes' (pinstripe texture + tinted outlines) or 'gradient'
// (classic two-color blends). Stored per account like the color theme.
function normalizeAccentStyle(v){
  const value = String(v || '').toLowerCase();
  return ACCENT_STYLES.includes(value) ? value : DEFAULT_ACCENT_STYLE;
}
function applyAccentStyle(style, persistLocal, syncRemote){
  accentStyle = normalizeAccentStyle(style);
  document.documentElement.dataset.accentStyle = accentStyle;
  // Repaint so gradients and accents both follow the selected style.
  const palette = colorTheme === 'custom' ? customThemeColors : getColorTheme(colorTheme);
  if (palette) _paintColors(palette.primary, palette.secondary, palette.tertiary, palette.accent);
  if (persistLocal !== false) localStorage.setItem('accentStyle', accentStyle);
  syncAccentStyleControls();
  if (typeof _chartInstances !== 'undefined' && _chartInstances){
    Object.values(_chartInstances).forEach(chart =>{ try{ chart.update(); }catch(e){} });
  }
  if (syncRemote !== false) scheduleUserProfileSave();
}
function setAccentStyle(style){ applyAccentStyle(style, true, true); }
function syncAccentStyleControls(){
  document.querySelectorAll('.vs-style-btn').forEach(b =>{
    b.classList.toggle('active', b.dataset.style === accentStyle);
    b.setAttribute('aria-pressed', b.dataset.style === accentStyle ? 'true' : 'false');
  });
  const hint = $('accentStyleHint');
  if (hint){
    hint.textContent = accentStyle === 'gradient'
      ? 'Classic look: the primary and gradient colors blend directly into each other. Panels still keep a light palette tint.'
      : 'Pinstripe look: softer primary-family gradients, evenly spaced diagonal texture, and a separate accent color for outlines and highlights.';
  }
}
function setCustomThemeColor(which, value){
  if (!_isHex(value)) return;
  const key = which === 'secondary' ? 'secondary' : which === 'accent' ? 'accent' : 'primary';
  customThemeColors[key] = value.toLowerCase();
  applyColorTheme('custom', true, true);
}
function resetCustomTheme(){
  const base = getColorTheme(DEFAULT_COLOR_THEME);
  customThemeColors = { primary:base.primary, secondary:base.secondary, tertiary:base.tertiary || '#ffffff', accent:base.accent || base.secondary };
  applyColorTheme('custom', true, true);
}
// Rebuild the swatch grid, mark the active card, and mirror the custom inputs.
function renderColorThemeGrid(){
  const grid = $('colorThemeGrid');
  if (!grid) return;
  grid.innerHTML = COLOR_THEMES.map(t => `
    <button type="button" class="theme-swatch${colorTheme === t.id ? ' active' : ''}" data-theme="${t.id}"
            onclick="setColorTheme('${t.id}')" aria-pressed="${colorTheme === t.id}" title="${t.name} — ${t.sub}">
      <span class="theme-swatch-chip" style="--swatch-left:${t.primary};--swatch-mid:${t.tertiary || t.secondary || '#fff'};--swatch-right:${t.accent || t.secondary};"></span>
      <span class="theme-swatch-name">${t.name}</span>
      <span class="theme-swatch-sub">${t.sub}</span>
    </button>`).join('') + `
    <button type="button" class="theme-swatch theme-swatch-custom${colorTheme === 'custom' ? ' active' : ''}" data-theme="custom"
            onclick="setColorTheme('custom')" aria-pressed="${colorTheme === 'custom'}" title="Custom — pick your own colors">
      <span class="theme-swatch-chip" style="--swatch-left:${customThemeColors.primary};--swatch-mid:${customThemeColors.secondary};--swatch-right:${customThemeColors.accent || customThemeColors.secondary};"></span>
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
  const a = $('customAccentInput');     if (a) a.value = customThemeColors.accent || customThemeColors.secondary;
  const ah = $('customAccentHex');      if (ah) ah.value = customThemeColors.accent || customThemeColors.secondary;
  const active = colorTheme === 'custom' ? { name:'Custom', sub:'Your colors' } : getColorTheme(colorTheme);
  const label = $('activeThemeLabel');
  if (label && active) label.textContent = active.name + ' — ' + active.sub;
}
// Back-compat: older profiles and LOCAL_SETTINGS store a bare accent hex.
function setAccentColor(color, persistLocal, syncRemote){
  if (!_isHex(color)) return;
  const match = COLOR_THEMES.find(t => t.primary.toLowerCase() === color.toLowerCase());
  if (match) return applyColorTheme(match.id, persistLocal, syncRemote);
  customThemeColors = { primary:color.toLowerCase(), secondary:_shadeHex(color, -0.45), tertiary:'#ffffff', accent:_shadeHex(color, -0.45) };
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
