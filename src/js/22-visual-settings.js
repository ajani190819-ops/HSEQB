function restoreVisualSettings(){
  const ls=window.LOCAL_SETTINGS||{};
  const get=(k,fb)=>ls[k]!==undefined?ls[k]:(localStorage.getItem(k)??fb);
  const storedMode=get('themeMode',null);
  const legacyDark=get('darkMode',false);
  const mode=storedMode && THEME_MODES.includes(String(storedMode).toLowerCase())
    ? normalizeThemeMode(storedMode)
    : (legacyDark === 'true' || legacyDark === true ? 'dark' : 'device');
  applyTheme(mode,true,false);
  const hide=get('hideScrollbars','false') === 'true' || get('hideScrollbars',false) === true;
  document.body.classList.toggle('hide-scrollbars',hide);
  const hideEl=$('hideScrollbarsToggle'); if(hideEl) hideEl.checked=hide;
  localStorage.setItem('hideScrollbars',hide ? 'true' : 'false');
  const cp=get('customPrimary',null), cs=get('customSecondary',null), ca=get('customAccent',null);
  if(/^#[0-9a-f]{6}$/i.test(cp||'')) customThemeColors.primary=String(cp).toLowerCase();
  if(/^#[0-9a-f]{6}$/i.test(cs||'')) customThemeColors.secondary=String(cs).toLowerCase();
  if(/^#[0-9a-f]{6}$/i.test(ca||'')) customThemeColors.accent=String(ca).toLowerCase();
  else customThemeColors.accent=customThemeColors.secondary;
  advancedThemeColors = ADVANCED_THEME_KEYS.reduce((acc, key) => {
    const raw = get(ADVANCED_THEME_STORAGE_KEYS[key], null);
    acc[key] = /^#[0-9a-f]{6}$/i.test(raw||'') ? String(raw).toLowerCase() : '';
    return acc;
  }, {});
  const ct=get('colorTheme',null);
  const ac=get('accentColor',null);
  if(ct==='custom' || getColorTheme(ct)) applyColorTheme(ct,true,false);
  else if(/^#[0-9a-f]{6}$/i.test(ac||'')) setAccentColor(ac,true,false);   // pre-theme files
  else applyColorTheme(DEFAULT_COLOR_THEME,true,false);
  applyVisualStyle(get('visualStyle',null) || DEFAULT_VISUAL_STYLE,true,false);
  applyAccentStyle(get('accentStyle',null) || DEFAULT_ACCENT_STYLE,true,false);
  applyAdvancedThemeOverrides(advancedThemeColors, true, false);
  syncThemeControls();
}
function renderAll(){
renderSessionInfo(); renderPlayerPool(); renderPlayerMgmt(); renderPlayerButtons(); renderSubPanel();
renderPointTypeButtons(); renderTeams(); renderCategories(); renderAnswerLog(); renderStatistics(); renderTHeard();
if(analyticsOpen) renderAnalytics();
if($('sessionsModal')?.classList.contains('open')) renderSessionsList();
setTimeout(updateFadeMasks,50); }
function renderSessionInfo(){
const s = getCurrentSession();
if (!s) return;
const set=(id,val)=>{const el=$(id);if(el)el.textContent=val;};
set('sessionName',s.name);
set('headerSessionName',  s.name);
set('headerSessionNameMobile', s.name);
set('sessionCreated',     new Date(s.created).toLocaleString());
set('sessionLastUpdated', new Date(s.lastUpdated).toLocaleString());
set('sessionAnswerCount', (s.answerLog || []).length); }
