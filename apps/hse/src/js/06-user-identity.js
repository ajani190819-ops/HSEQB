function loadUserId(){
  const stored = localStorage.getItem('qb_userName') || '';
  const display = $('userIdDisplayName');
  const sub = $('userIdSubtitle');
  const input = $('userDisplayNameInput');
  const cid = $('userClientIdDisplay');
  const avatar = $('userIdAvatar');
  const name = stored.trim();
  if (cid) cid.textContent = authUser?.uid || clientId || '—';
  if (display) display.textContent = name || 'Not set';
  if (input && document.activeElement !== input) input.value = name;
  if (avatar) avatar.textContent = name ? name.charAt(0).toUpperCase() : (authUser?.isAnonymous ? 'G' : '?');
  if (sub){
    sub.textContent = name
      ? 'Saved to your Firebase account'
      : (authUser ? (authUser.isAnonymous ? 'Guest account · add a display name' : 'Add a display name for your account') : 'Sign in to load your profile');
  }
  updateAuthUI(authUser);
}
function saveUserId(){
  const input = $('userDisplayNameInput');
  const legacyFirst = $('userIdFirstName')?.value || '';
  const legacyLast = $('userIdLastName')?.value || '';
  const name = (input?.value || (legacyFirst + ' ' + legacyLast)).trim().replace(/\s+/g,' ').slice(0,61);
  if (!name){ showToast('Please enter a display name.'); input?.focus(); return; }
  localStorage.setItem('qb_userName', name);
  if (authUser?.uid) localStorage.setItem('qb_profileOwnerUid', authUser.uid);
  recomputeAdmin();
  loadUserId();
  setUserIdLoadStatus('Saving display name…', 'var(--text2)');
  const writes=[];
  if (authUser && typeof authUser.updateProfile === 'function') writes.push(authUser.updateProfile({displayName:name}));
  if (!isIframe && userProfileRef){
    const customization=getUserCustomization();
    writes.push(userProfileRef.update({displayName:name, name, customization, settings:customization, email:authUser?.email || null, isAnonymous:!!authUser?.isAnonymous, lastSeen:new Date().toISOString()}));
  }
  if (!isIframe && userIdentitiesRef){
    const identity={name, lastSeen:new Date().toISOString(), email:authUser?.email || null, uid:authUser?.uid || clientId};
    writes.push(userIdentitiesRef.child(clientId).update(identity));
    userIdentitiesCache[clientId]=identity;
  }
  Promise.all(writes)
    .then(()=>{ loadUserId(); setUserIdLoadStatus('✓ Display name saved to Firebase.', 'var(--success)'); setTimeout(()=>loadUserId(), 2200); })
    .catch(err=>{ setUserIdLoadStatus('Display name could not be saved.', 'var(--danger)'); showFirebaseError('Display name save failed: ' + err.message); });
}
function clearUserId(){
  showConfirm('Clear your Firebase display name from this account?', 'Clear').then(ok=>{
    if (!ok) return;
    localStorage.removeItem('qb_userName');
    recomputeAdmin();
    const writes=[];
    if (authUser && typeof authUser.updateProfile === 'function') writes.push(authUser.updateProfile({displayName:null}));
    if (!isIframe && userProfileRef) writes.push(userProfileRef.update({displayName:null, name:null, lastSeen:new Date().toISOString()}));
    if (!isIframe && userIdentitiesRef) writes.push(userIdentitiesRef.child(clientId).update({name:null, lastSeen:new Date().toISOString()}));
    loadUserId();
    Promise.all(writes).then(()=>setUserIdLoadStatus('Display name cleared.', 'var(--success)'))
      .catch(err=>showFirebaseError('Display name clear failed: ' + err.message));
  });
}
/* Kept as a compatibility helper for older saved files; Firebase auth now handles account selection. */
function loadExistingAccount(){ showToast('Sign out and sign in with the Firebase account you want to use.', 'info'); }
function newAccount(){ showToast('Sign out, then choose Create account to make a new Firebase account.', 'info'); }
const WELCOME_LAST_SHOWN_KEY = 'qb_welcomeLastShown';
const WELCOME_RESHOW_MS = 60 * 24 * 60 * 60 * 1000; // 60 days
function maybeShowWelcomeToast(){
const last = parseInt(localStorage.getItem(WELCOME_LAST_SHOWN_KEY) || '0', 10);
const now  = Date.now();
const isNew = last === 0;
const isReturning = last > 0 && (now - last) > WELCOME_RESHOW_MS;
if (!isNew && !isReturning) return;
setTimeout(() =>{
const toast = $('welcomeToast');
if (!toast) return;
const title = document.querySelector('#welcomeToast .wt-title');
const sub   = document.querySelector('#welcomeToast .wt-sub');
if (isReturning && title && sub){
title.textContent = '▸ Welcome back!';
sub.textContent   = "It's been a while — want a refresher? The Help guide has everything you need.";
}
toast.classList.add('show');
}, 1200); }
function dismissWelcomeToast(openHelp){
const toast = $('welcomeToast');
if (toast) toast.classList.remove('show');
localStorage.setItem(WELCOME_LAST_SHOWN_KEY, Date.now().toString());
if (openHelp) openHelpModal(); }
