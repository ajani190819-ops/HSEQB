function authMessage(msg){ const e=$('authError'); if(e)e.textContent=msg||''; }
function authEmail(){ return ($('authEmail')?.value||'').trim().toLowerCase(); }
function submitAuth(e){
  e.preventDefault();
  authMessage('Signing in…');
  firebase.auth().signInWithEmailAndPassword(authEmail(), $('authPassword').value)
    .catch(err => authMessage(err.message));
  return false;
}
function continueAsGuest(){
  authMessage('Starting guest session…');
  firebase.auth().signInAnonymously().catch(err => authMessage(err.message));
}
function createAuthAccount(){
  const email=authEmail(), pw=$('authPassword')?.value||'';
  if(!email || pw.length < 6){ authMessage('Enter an email and a password of at least 6 characters.'); return; }
  authMessage('Creating account…');
  firebase.auth().createUserWithEmailAndPassword(email,pw).catch(err=>authMessage(err.message));
}
function upgradeGuestAccount(){
  if(!authUser || !authUser.isAnonymous){ showToast('You are already using a permanent account.'); return; }
  const email=prompt('Enter an email address for this guest account:'); if(!email) return;
  const pw=prompt('Create a password (at least 6 characters):');
  if(!pw || pw.length < 6){ showToast('Password must be at least 6 characters.'); return; }
  const credential=firebase.auth.EmailAuthProvider.credential(email.trim().toLowerCase(),pw);
  authUser.linkWithCredential(credential)
    .then(()=>showToast('Guest account upgraded. Your data is now protected by your email and password.'))
    .catch(err=>showToast(err.code==='auth/email-already-in-use'?'That email already has an account. Sign out and use that account instead.':err.message,'warn'));
}
function resetAuthPassword(){
  const email=authEmail();
  if(!email){ authMessage('Enter your email first.'); return; }
  firebase.auth().sendPasswordResetEmail(email)
    .then(()=>authMessage('Password reset email sent.'))
    .catch(err=>authMessage(err.message));
}
function getUserCustomization(){
  const inlineAccent = document.documentElement.style.getPropertyValue('--primary').trim();
  const customization = {
    themeMode: normalizeThemeMode(themeMode),
    accentStyle: normalizeAccentStyle(accentStyle),
    accentColor: inlineAccent || localStorage.getItem('accentColor') || DEFAULT_ACCENT,
    colorTheme: colorTheme || DEFAULT_COLOR_THEME,
    customPrimary: customThemeColors.primary,
    customSecondary: customThemeColors.secondary,
    customAccent: customThemeColors.accent || customThemeColors.secondary,
    hideScrollbars: !!document.body?.classList.contains('hide-scrollbars'),
    sidebarCollapsed: !!$('mainSidebar')?.classList.contains('collapsed')
  };
  if (_isHex(advancedThemeColors.bannerStripe)) customization.customBannerStripe = advancedThemeColors.bannerStripe;
  if (_isHex(advancedThemeColors.bannerOutline)) customization.customBannerOutline = advancedThemeColors.bannerOutline;
  return customization;
}
function setProfileSyncStatus(message, color){
  ['profileSyncStatus','visualSettingsSyncStatus'].forEach(id =>{
    const el=$(id);
    if (el){ el.textContent=message||''; if(color) el.style.color=color; }
  });
}
function setUserIdLoadStatus(message, color){
  const el=$('userIdLoadStatus');
  if (el){ el.textContent=message||''; if(color) el.style.color=color; }
}
function scheduleUserProfileSave(){
  if (isIframe || !userProfileRef || !authUser) return;
  clearTimeout(_profileSaveTimer);
  setProfileSyncStatus('Saving account preferences…', 'var(--text2)');
  _profileSaveTimer = setTimeout(() => saveUserCustomization(), 350);
}
function saveUserCustomization(){
  if (isIframe || !userProfileRef || !authUser) return Promise.resolve();
  clearTimeout(_profileSaveTimer);
  const customization = getUserCustomization();
  localStorage.setItem('qb_customizationOwnerUid', authUser.uid);
  return userProfileRef.update({ customization, settings:customization, lastSeen:new Date().toISOString() })
    .then(() => setProfileSyncStatus('✓ Account preferences saved.', 'var(--success)'))
    .catch(err =>{
      setProfileSyncStatus('Preferences could not be saved.', 'var(--danger)');
      showFirebaseError('Preferences save failed: ' + err.message);
    });
}
function getStoredLocalNameForUser(uid){
  const owner = localStorage.getItem('qb_profileOwnerUid');
  if (owner && owner !== uid) return '';
  return localStorage.getItem('qb_userName') || '';
}
function resetLocalCustomizationForAccountSwitch(){
  localStorage.removeItem('themeMode');
  localStorage.removeItem('darkMode');
  localStorage.removeItem('accentColor');
  localStorage.removeItem('colorTheme');
  localStorage.removeItem('accentStyle');
  localStorage.removeItem('customPrimary');
  localStorage.removeItem('customSecondary');
  localStorage.removeItem('customAccent');
  localStorage.removeItem('customBannerStripe');
  localStorage.removeItem('customBannerOutline');
  localStorage.removeItem('hideScrollbars');
  localStorage.removeItem('sidebarCollapsed');
  applyTheme('device', true, false);
  ['--primary','--primary-light','--primary-dark','--secondary','--accent-line','--tertiary','--hse-blue','--hse-red','--hse-white','--banner-stripe','--banner-stripe-soft','--banner-outline'].forEach(v => document.documentElement.style.removeProperty(v));
  document.body.classList.remove('hide-scrollbars');
  const hideToggle=$('hideScrollbarsToggle'); if(hideToggle) hideToggle.checked=false;
  const base=getColorTheme(DEFAULT_COLOR_THEME);
  customThemeColors={ primary:base.primary, secondary:base.secondary, tertiary:base.tertiary || '#ffffff', accent:base.accent || base.secondary };
  advancedThemeColors={ bannerStripe:'', bannerOutline:'' };
  applyColorTheme(DEFAULT_COLOR_THEME, true, false);
  applyAccentStyle(DEFAULT_ACCENT_STYLE, true, false);
}
function extractProfileCustomization(profile){
  const source = { ...(profile || {}), ...(profile?.settings || {}), ...(profile?.customization || {}) };
  const result = {};
  const mode = source.themeMode || source.theme;
  if (THEME_MODES.includes(String(mode || '').toLowerCase())) result.themeMode = normalizeThemeMode(mode);
  if (typeof source.accentColor === 'string' && /^#[0-9a-f]{6}$/i.test(source.accentColor)) result.accentColor = source.accentColor;
  if (source.colorTheme === 'custom' || getColorTheme(source.colorTheme)) result.colorTheme = source.colorTheme;
  if (ACCENT_STYLES.includes(String(source.accentStyle || '').toLowerCase())) result.accentStyle = String(source.accentStyle).toLowerCase();
  if (typeof source.customPrimary === 'string' && /^#[0-9a-f]{6}$/i.test(source.customPrimary)) result.customPrimary = source.customPrimary;
  if (typeof source.customSecondary === 'string' && /^#[0-9a-f]{6}$/i.test(source.customSecondary)) result.customSecondary = source.customSecondary;
  if (typeof source.customAccent === 'string' && /^#[0-9a-f]{6}$/i.test(source.customAccent)) result.customAccent = source.customAccent;
  if (typeof source.customBannerStripe === 'string' && /^#[0-9a-f]{6}$/i.test(source.customBannerStripe)) result.customBannerStripe = source.customBannerStripe;
  if (typeof source.customBannerOutline === 'string' && /^#[0-9a-f]{6}$/i.test(source.customBannerOutline)) result.customBannerOutline = source.customBannerOutline;
  if (typeof source.hideScrollbars === 'boolean') result.hideScrollbars = source.hideScrollbars;
  if (typeof source.sidebarCollapsed === 'boolean') result.sidebarCollapsed = source.sidebarCollapsed;
  return result;
}
function loadAuthenticatedUserProfile(user){
  if (!userProfileRef) return Promise.resolve({});
  const identityPromise = userIdentitiesRef
    ? userIdentitiesRef.child(user.uid).once('value').catch(() => ({ val:() => null }))
    : Promise.resolve({ val:() => null });
  return Promise.all([userProfileRef.once('value'), identityPromise]).then(([profileSnap, identitySnap]) =>{
    const profile = profileSnap.val() || {};
    const identity = identitySnap.val() || {};
    const localName = getStoredLocalNameForUser(user.uid);
    const displayName = String(profile.displayName || profile.name || user.displayName || identity.name || localName || '').trim().slice(0,61);
    if (localStorage.getItem('qb_profileOwnerUid') && localStorage.getItem('qb_profileOwnerUid') !== user.uid){
      localStorage.removeItem('qb_userName');
    }
    localStorage.setItem('qb_profileOwnerUid', user.uid);
    if (displayName) localStorage.setItem('qb_userName', displayName);
    else localStorage.removeItem('qb_userName');
    const customization = extractProfileCustomization(profile);
    return { ...profile, displayName, customization, hasSavedCustomization:Object.keys(customization).length > 0 };
  });
}
function applyAuthenticatedUserProfile(profile, user){
  localStorage.setItem('qb_customizationOwnerUid', user.uid);
  const name = String(profile?.displayName || user?.displayName || '').trim();
  if (name) localStorage.setItem('qb_userName', name);
  const customization = profile?.customization || extractProfileCustomization(profile);
  if (customization.themeMode) applyTheme(customization.themeMode, true, false);
  else applyTheme(themeMode || 'device', true, false);
  if (customization.customPrimary)   customThemeColors.primary   = customization.customPrimary.toLowerCase();
  if (customization.customSecondary) customThemeColors.secondary = customization.customSecondary.toLowerCase();
  if (customization.customAccent) customThemeColors.accent = customization.customAccent.toLowerCase();
  else if (customization.customSecondary) customThemeColors.accent = customization.customSecondary.toLowerCase();
  advancedThemeColors = {
    bannerStripe:(typeof customization.customBannerStripe === 'string' && /^#[0-9a-f]{6}$/i.test(customization.customBannerStripe)) ? customization.customBannerStripe.toLowerCase() : '',
    bannerOutline:(typeof customization.customBannerOutline === 'string' && /^#[0-9a-f]{6}$/i.test(customization.customBannerOutline)) ? customization.customBannerOutline.toLowerCase() : ''
  };
  if (customization.colorTheme) applyColorTheme(customization.colorTheme, true, false);
  else if (customization.accentColor) setAccentColor(customization.accentColor, true, false);
  applyAccentStyle(customization.accentStyle || accentStyle, true, false);
  applyAdvancedThemeOverrides(advancedThemeColors, true, false);
  if (typeof customization.hideScrollbars === 'boolean'){
    document.body.classList.toggle('hide-scrollbars', customization.hideScrollbars);
    const toggle=$('hideScrollbarsToggle'); if(toggle) toggle.checked=customization.hideScrollbars;
    localStorage.setItem('hideScrollbars', customization.hideScrollbars ? 'true' : 'false');
  }
  if (typeof customization.sidebarCollapsed === 'boolean'){
    localStorage.setItem('sidebarCollapsed', customization.sidebarCollapsed ? 'true' : 'false');
  }
  syncThemeControls();
  loadUserId();
}
function updateAuthUI(user){
  const email=$('userAuthEmail'), type=$('userAuthType'), uid=$('userClientIdDisplay'), upgrade=$('upgradeGuestBtn');
  if (uid) uid.textContent = user?.uid || '—';
  if (email) email.textContent = user ? (user.email || 'Guest account') : 'Not signed in';
  if (type) type.textContent = user ? (user.isAnonymous ? 'Guest' : 'Firebase account') : '—';
  if (upgrade) upgrade.style.display = user?.isAnonymous ? 'inline-flex' : 'none';
}
function signOutUser(){
  if (!firebase?.auth) return;
  authMessage('Signing out…');
  firebase.auth().signOut().catch(err => showToast('Sign out failed: ' + err.message, 'warn'));
}
function initAuth(){
  authStarted=true;
  setupDeviceThemeListener();
  restoreVisualSettings();
  syncThemeControls();
  const gate=$('authGate');
  if (gate && !firebase.auth().currentUser) gate.style.display='flex';
  firebase.auth().onAuthStateChanged(user =>{
    authUser=user;
    const sequence=++_profileLoadSequence;
    if (!user){
      userProfileRef=null;
      updateAuthUI(null);
      if (gate) gate.style.display='flex';
      authMessage('');
      return;
    }
    clientId=user.uid;
    localStorage.setItem('qb_clientId',user.uid);
    userProfileRef=userProfilesRef ? userProfilesRef.child(user.uid) : null;
    const previousCustomizationOwner=localStorage.getItem('qb_customizationOwnerUid');
    if (previousCustomizationOwner && previousCustomizationOwner !== user.uid) resetLocalCustomizationForAccountSwitch();
    if (gate) gate.style.display='flex';
    authMessage('Loading your saved profile…');
    loadAuthenticatedUserProfile(user)
      .catch(err =>{
        console.warn('[HSE QB] Profile load failed:', err);
        return { profileLoadFailed:true };
      })
      .then(profile =>{
        if (sequence !== _profileLoadSequence || authUser?.uid !== user.uid) return;
        applyAuthenticatedUserProfile(profile || {}, user);
        updateAuthUI(user);
        authMessage('');
        if (gate) gate.style.display='none';
        if (!appStarted){ appStarted=true; startApp(); }
        else { loadUserId(); applyAdminUI(); applySidebarState(); }
        // Migrate a device-only preference into the account the first time it signs in.
        if (!profile?.profileLoadFailed && !profile?.hasSavedCustomization) saveUserCustomization();
      });
  });
}
