function adminEscape(value){
const text = String(value == null ? '' : value);
return typeof updatesEscapeHtml === 'function' ? updatesEscapeHtml(text) : text.replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
}
function adminUidName(uid){
const identity = userIdentitiesCache && userIdentitiesCache[uid];
return String(identity?.name || (authUser?.uid === uid ? localStorage.getItem('qb_userName') : '') || '').trim();
}
function renderAdminPanel(){
const el = $('adminListDisplay');
if (!el) return;
if (!isAdmin){ el.innerHTML = ''; return; }
const uidEntries = Object.entries(adminUids || {}).filter(([, enabled]) => enabled === true);
const legacyEntries = uidEntries.length ? [] : (Array.isArray(adminList) ? adminList : []);
let html = '';
if (uidEntries.length){
  html = uidEntries.map(([uid]) =>{
    const name = adminUidName(uid);
    const label = name ? `${adminEscape(name)}<span class="admin-uid-sub">${adminEscape(uid)}</span>` : `<span>${adminEscape(uid)}</span>`;
    const current = authUser?.uid === uid ? '<span class="admin-current-pill">This account</span>' : '';
    const encodedUid = encodeURIComponent(uid);
    return `<div class="admin-uid-row"><div class="admin-uid-label">${label}</div><div class="admin-uid-actions">${current}<button onclick="removeAdmin(decodeURIComponent('${encodedUid}'))" class="admin-remove-btn">Remove</button></div></div>`;
  }).join('');
} else if (legacyEntries.length){
  html = legacyEntries.map(name =>{
    const encodedName = encodeURIComponent(name);
    return `<div class="admin-uid-row"><div class="admin-uid-label"><span>${adminEscape(name)}</span><span class="admin-uid-sub">Legacy name entry — add Firebase UIDs before applying the secure rules</span></div><div class="admin-uid-actions"><span class="admin-legacy-pill">Legacy</span><button onclick="removeLegacyAdmin(decodeURIComponent('${encodedName}'))" class="admin-remove-btn">Remove</button></div></div>`;
  }).join('');
} else {
  html = '<div class="admin-empty">No UID-based admins are configured yet. Add your Firebase UID below.</div>';
}
el.innerHTML = html;
}
function addAdmin(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
const input = $('adminUidInput') || $('adminAddInput');
const uid = (input?.value || '').trim();
if (!uid){ showToast('Enter the Firebase UID for the account to add.'); return; }
if (uid.length > 128 || /[.#$\[\]/]/.test(uid)){ showToast('That does not look like a valid Firebase UID.', 'warn'); return; }
if (adminUids && adminUids[uid] === true){ showToast('That account is already an admin.', 'warn'); return; }
if (!adminUidsRef || !adminUidsRef.child){ showToast('Firebase is not connected.', 'warn'); return; }
adminUidsRef.child(uid).set(true)
.then(() =>{
  if (input) input.value = '';
  renderAdminPanel();
  showToast('Admin access granted.', 'success');
})
.catch(e => showFirebaseError('Could not add admin: ' + e.message));
}
function removeAdmin(uid){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
const name = adminUidName(uid);
const label = name ? name + ' (' + uid + ')' : uid;
showConfirm('Remove ' + label + ' from UID-based admins?', 'Remove').then(ok =>{
if (!ok) return;
adminUidsRef.child(uid).remove()
.then(() =>{
  renderAdminPanel();
  showToast('Admin access removed.', 'success');
})
.catch(e => showFirebaseError('Could not remove admin: ' + e.message));
});
}
function removeLegacyAdmin(name){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
showConfirm('Remove ' + name + ' from the legacy admin list?', 'Remove').then(ok =>{
if (!ok) return;
adminListRef.set((Array.isArray(adminList) ? adminList : []).filter(item => item !== name))
.then(() => renderAdminPanel())
.catch(e => showFirebaseError('Could not remove legacy admin: ' + e.message));
});
}
const CAT_COLOR_DEFAULTS ={'Literature':'#3b82f6','Science':'#11998e','History':'#f97316','Social Studies':'#eab308','Pop Culture':'#a855f7','Fine Arts':'#06b6d4'};
const CAT_ORDER = ['Literature', 'Science', 'History', 'Social Studies', 'Fine Arts', 'Pop Culture'];
const CAT_FREQ_DEFAULTS ={
'Poetry':3.1, 'Theater':1.8, 'Fiction':8.1, 'Nonfiction':2.2,
'Biology':3.7, 'Chemistry':2.6, 'Physics':4.5, 'Math':7.5,
'Astronomy':1.1, 'Computer Science':0.4, 'Earth Science':1.1,
'Ancient History':1.5, 'American History':7.8, 'European History':4.5, 'World History':3.4,
'Philosophy':1.5, 'Geography':8.6, 'Religion':6.7, 'Mythology':7.5, 'Social Sciences':2.6,
'Visual Arts':4.1, 'Music':2.2, 'Musicals':0.4, 'Opera':1.1,
'Popular Media':5.6, 'Sports':1.9, 'Current Events':4.5,
};
var catFreqs ={ ...CAT_FREQ_DEFAULTS };
function renderCatFreqPickers(){
const container=$('catFreqPickers'); if(!container) return;
let html = '';
Object.entries(CATEGORY_TREE).forEach(([parent, subs]) =>{
html += `<div style="font-size:.78em;font-weight:700;color:var(--text2);margin-top:8px;margin-bottom:2px;text-transform:uppercase;letter-spacing:.05em;">${parent}</div>`;
subs.forEach(sub =>{
const val = catFreqs[sub] ?? CAT_FREQ_DEFAULTS[sub] ?? 0;
html += `<div class="flex-center-8">
<label style="flex:1;font-size:.82em;color:var(--text);">${sub}</label>
<div style="display:flex;align-items:center;gap:4px;">
<input type="number" id="catfreq_${sub.replace(/\s+/g,'_')}" value="${val}" min="0" max="100" step="0.5"
style="width:64px;padding:4px 6px;border:1.5px solid var(--input-border);border-radius:var(--radius-sm);font-size:.85em;font-family:inherit;background:var(--input-bg);color:var(--input-text);text-align:right;" />
<span style="font-size:.8em;color:var(--text3);">%</span>
</div>
</div>`;
}); });
container.innerHTML = html; }
function saveCatFreqs(){
const statusEl = $('catFreqStatus');
Object.entries(CATEGORY_TREE).forEach(([, subs]) =>{
subs.forEach(sub =>{
const input = $('catfreq_' + sub.replace(/\s+/g,'_'));
if (input) catFreqs[sub] = parseFloat(input.value) || 0; });
});
if (!isIframe && globalSettingsRef){
globalSettingsRef.child('catFreqs').set(catFreqs)
.catch(e => showFirebaseError('Frequency save failed:' + e.message)); }
if (statusEl){ statusEl.textContent = '✔ Saved'; setTimeout(() =>{ statusEl.textContent = ''; }, 2000); }
if (analyticsOpen) renderAnalytics(); }
function resetCatFreqs(){ catFreqs={...CAT_FREQ_DEFAULTS}; renderCatFreqPickers(); saveCatFreqs(); }
function renderCatColorPickers(){
const el = $('catColorPickers');
if (!el) return;
el.innerHTML = CAT_ORDER.map(cat =>{
const color = catColors[cat] || CAT_COLOR_DEFAULTS[cat] || '#667eea';
return `<div style="display:flex;align-items:center;gap:10px;">
<input type="color" value="${color}" id="catColorInput_${cat.replace(/\s+/g,'_')}"
style="width:36px;height:28px;border:1.5px solid var(--border);border-radius:5px;padding:1px;cursor:pointer;background:none;">
<span style="font-size:.88em;font-weight:600;color:var(--text);flex:1;">${cat}</span>
<button onclick="resetOneCatColor('${cat}')" title="Reset to default"
style="font-size:.75em;background:none;border:1.5px solid var(--border);color:var(--text2);border-radius:5px;padding:2px 8px;cursor:pointer;">Reset</button>
</div>`;
}).join(''); }
function saveCatColors(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
CAT_ORDER.forEach(cat =>{
const input = $('catColorInput_' + cat.replace(/\s+/g,'_'));
if (input) catColors[cat] = input.value; });
const statusEl = $('catColorStatus');
if (!isIframe){
globalSettingsRef.child('catColors').set(catColors)
.then(() =>{ if (statusEl){ statusEl.textContent = '✔ Saved!'; setTimeout(() => statusEl.textContent = '', 2000); } })
.catch(e => showFirebaseError(e.message));
} else{
if (statusEl){ statusEl.textContent = '✔ Applied (preview only — not saved).'; setTimeout(() => statusEl.textContent = '', 2500); }
}
if (analyticsOpen) renderAnalytics(); }
function resetCatColors(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
catColors ={ ...CAT_COLOR_DEFAULTS };
renderCatColorPickers();
saveCatColors(); }
function resetOneCatColor(cat){
catColors[cat] = CAT_COLOR_DEFAULTS[cat];
const input = $('catColorInput_' + cat.replace(/\s+/g,'_'));
if (input) input.value = CAT_COLOR_DEFAULTS[cat]; }
