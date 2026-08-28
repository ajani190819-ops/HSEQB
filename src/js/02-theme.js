function normalizeThemeMode(mode){
  const value = String(mode || '').toLowerCase();
  return THEME_MODES.includes(value) ? value : 'device';
}
function devicePrefersDark(){
  return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
}
function themeIsDark(mode){
  return normalizeThemeMode(mode) === 'dark' || (normalizeThemeMode(mode) === 'device' && devicePrefersDark());
}
function syncThemeControls(){
  const mode = normalizeThemeMode(themeMode);
  ['themeModeSelect'].forEach(id =>{
    const el = $(id);
    if (el) el.value = mode;
  });
  const hint = $('themeModeHint');
  if (hint){
    hint.textContent = mode === 'device'
      ? 'Following your device preference: ' + (devicePrefersDark() ? 'Dark' : 'Light') + '.'
      : 'Using ' + (mode === 'dark' ? 'Dark' : 'Light') + ' mode.';
  }
  document.querySelectorAll('.vs-mode-btn').forEach(b =>{
    b.classList.toggle('active', b.dataset.mode === mode);
    b.setAttribute('aria-pressed', b.dataset.mode === mode ? 'true' : 'false');
  });
  document.querySelectorAll('.auth-theme-btn').forEach(b =>{
    b.classList.toggle('active', b.dataset.theme === mode);
    b.setAttribute('aria-pressed', b.dataset.theme === mode ? 'true' : 'false');
  });
}
function applyTheme(mode, persistLocal, syncRemote){
  themeMode = normalizeThemeMode(mode);
  const dark = themeIsDark(themeMode);
  document.documentElement.classList.toggle('dark-mode', dark);
  if (document.body) document.body.classList.toggle('dark-mode', dark);
  document.documentElement.dataset.theme = themeMode;
  document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
  // Repaint the selected palette when appearance changes; this is what makes
  // blue/red accents calmer on white surfaces and brighter on dark surfaces.
  if (typeof _paintColors === 'function' && typeof colorTheme !== 'undefined') {
    const palette = colorTheme === 'custom' ? customThemeColors : getColorTheme(colorTheme);
    if (palette) _paintColors(palette.primary, palette.secondary, palette.tertiary, palette.accent);
  }
  if (persistLocal !== false){
    localStorage.setItem('themeMode', themeMode);
    // Keep the old key in sync for files/settings created before theme selection existed.
    localStorage.setItem('darkMode', dark ? 'true' : 'false');
  }
  syncThemeControls();
  if (typeof syncAdvancedThemeControls === 'function') syncAdvancedThemeControls();
  if (typeof _chartInstances !== 'undefined' && _chartInstances){
    Object.values(_chartInstances).forEach(chart =>{ try{ chart.update(); }catch(e){} });
  }
  if (syncRemote) scheduleUserProfileSave();
}
function setThemeMode(mode, persistLocal){
  applyTheme(mode, persistLocal !== false, true);
}
function setupDeviceThemeListener(){
  if (!window.matchMedia || _deviceThemeQuery) return;
  _deviceThemeQuery = window.matchMedia('(prefers-color-scheme: dark)');
  const onChange = () =>{
    if (themeMode === 'device') applyTheme('device', false, false);
  };
  if (_deviceThemeQuery.addEventListener) _deviceThemeQuery.addEventListener('change', onChange);
  else if (_deviceThemeQuery.addListener) _deviceThemeQuery.addListener(onChange);
}
