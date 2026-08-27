function saveGlobalSettings(){
if (isIframe || !globalSettingsRef) return;
globalSettingsRef.set({ skillThresholdPct, manuallyIncluded:[...manuallyIncluded], playerTHeardOverrides, sessionInvalidFlags, catColors, catFreqs }).catch(e => showFirebaseError('Settings save failed:' + e.message));
}
function saveManualInclusions(){
if (isIframe || !globalSettingsRef) return;
globalSettingsRef.child('manuallyIncluded').set([...manuallyIncluded]).catch(e => showFirebaseError('Inclusion save failed:' + e.message));
}
function adjustPlayerTHeard(playerName, delta){
playerTHeardOverrides[playerName] = (playerTHeardOverrides[playerName] || 0) + delta;
if (playerTHeardOverrides[playerName] === 0) delete playerTHeardOverrides[playerName];
if (globalSettingsRef) globalSettingsRef.child('playerTHeardOverrides').set(playerTHeardOverrides).catch(e => showFirebaseError('TH save failed:' + e.message));
renderAnalyticsPlayersUniversal(); }
function saveVersion(){ publishRelease(); } // legacy alias
function checkReleasePrompt(remoteBuild){
if (!isAdmin) return;
const prompt   = $('releasePrompt');
const upToDate = $('releaseUpToDate');
if (!prompt || !upToDate) return;
const isUnpublished = !remoteBuild || remoteBuild !== FILE_BUILD_ID;
if (isUnpublished){ prompt.classList.remove('hidden'); upToDate.classList.add('hidden'); }
else { prompt.classList.add('hidden'); upToDate.classList.remove('hidden'); }
}
function setReleaseUploadStatus(msg, kind){
const el = $('releaseUploadStatus');
if (!el) return;
el.textContent = msg || '';
el.style.color = kind === 'ok' ? 'var(--success)' : kind === 'err' ? 'var(--danger)' : 'var(--text2)';
}
function clearStaleReleaseHtmlPayload(){
if (releaseHtmlRef && releaseHtmlRef.set) releaseHtmlRef.set(null).catch(() =>{});
}
function publishHtmlToFirebase(html, setStatus, finish){
const kb = Math.max(1, Math.round(html.length / 1024));
if (html.length > 900 * 1024) setStatus('Warning: payload is ' + kb + ' KB — Firebase may reject values this large.', 'err');
else setStatus('Uploading ' + kb + ' KB to Firebase…');
releaseHtmlRef.set(html)
.then(() =>{ setStatus('HTML uploaded to Firebase (' + kb + ' KB).', 'ok'); finish(true, 'HTML uploaded to Firebase (' + kb + ' KB). Published.'); })
.catch(e =>{
showFirebaseError('HTML upload failed: ' + e.message);
clearStaleReleaseHtmlPayload();
finish(false, 'Metadata published — the HTML payload failed to upload (' + e.message + '), so users will fall back to the GitHub download URL.');
});
}
function publishRelease(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
if (!db || !releaseHtmlRef || !releaseHtmlRef.set){ showToast('Firebase is not connected — cannot publish.', 'warn'); return; }
const notes    = ($('releaseNotesInput')?.value || '').trim();
const comments = ($('adminCommentsInput')?.value || '').trim();
const payload  = { label:FILE_VERSION, buildId:FILE_BUILD_ID, downloadUrl:DOWNLOAD_URL, releaseNotes:notes, adminComments:comments, hasFirebasePayload:false, lastUpdated:new Date().toISOString() };
const fileInput = $('releaseFileInput');
const file = fileInput && fileInput.files && fileInput.files[0];
const setStatus = (msg, kind) => setReleaseUploadStatus(msg, kind);
setStatus('Preparing release…');
const finish = (hasPayload, statusMsg) =>{
payload.hasFirebasePayload = !!hasPayload;
versionRef.set(payload)
.then(() =>{
showToast('Published v'+FILE_VERSION, 'success');
hideUpdateBanner();
checkReleasePrompt(FILE_BUILD_ID);
if (statusMsg) setStatus(statusMsg, 'ok');
else if (!$('releaseUploadStatus')?.textContent?.trim()) setStatus('Published.', 'ok');
if (fileInput) fileInput.value = '';
})
.catch(e =>{ showFirebaseError(e.message); setStatus('Metadata publish failed: ' + e.message, 'err'); });
};
// Publishing metadata without a fresh HTML payload must not leave a stale releaseHtml behind,
// otherwise users would download an outdated file. Clear it so downloadUpdate falls back to GitHub.
if (file){
setStatus('Reading ' + file.name + '…');
file.text()
.then(html => publishHtmlToFirebase(html, setStatus, finish))
.catch(err =>{ setStatus('Could not read file: ' + err.message, 'err'); clearStaleReleaseHtmlPayload(); showFirebaseError('Release file read failed: ' + err.message); });
return;
}
// No file attached — when served over http(s) (GitHub Pages / local server), read the exact current source
if (window.location.protocol === 'http:' || window.location.protocol === 'https:'){
setStatus('No file attached — reading current page source…');
fetch(window.location.href, { cache:'no-store' })
.then(r =>{ if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
.then(html => publishHtmlToFirebase(html, setStatus, finish))
.catch(() =>{
setStatus('No file attached — could not read the current page source. Select the new index.html file to publish via Firebase.', 'err');
showToast('Attach the new index.html file to publish the download payload via Firebase.', 'warn');
clearStaleReleaseHtmlPayload();
finish(false, 'Metadata published — attach the index.html file so users can download it via Firebase instead of GitHub.');
});
return;
}
// Local file (file://) — the exact source cannot be read from disk, so require the attached file
setStatus('No file attached — please select the new index.html file to publish.', 'err');
showToast('Attach the new index.html file so users can download it via Firebase.', 'warn');
clearStaleReleaseHtmlPayload();
finish(false, 'Metadata published — attach the index.html file so users can download it via Firebase instead of GitHub.');
}
function showUpdateBanner(newLabel, downloadUrl, notes, hasFirebasePayload){
const banner = $('updateBanner');
if (!banner) return;
const hasUrl = downloadUrl && downloadUrl.startsWith('http');
const viaFb  = !!hasFirebasePayload;
banner.innerHTML =
`<span class="ub-icon">▲</span>` +
`<span class="ub-msg">This file is <strong>outdated / unpublished</strong> — published version is <strong>${newLabel}</strong> (you have ${FILE_VERSION})${notes ? ` — ${notes}` :''}.</span>` +
(hasUrl ? `<button class="ub-btn ub-download" onclick="downloadUpdate('${downloadUrl}')">↓ Download Update${viaFb ? ' (Firebase)' : ''}</button>` :'') +
`<button class="ub-btn ub-dismiss" onclick="hideUpdateBanner()" title="Dismiss">✕</button>`;
banner.classList.add('show'); }
function hideUpdateBanner(){
const banner = $('updateBanner');
if (banner) banner.classList.remove('show'); }
function showDevBanner(){
const banner = $('updateBanner');
if (!banner) return;
banner.style.background = 'linear-gradient(135deg, #5568d3 0%, #764ba2 100%)';
banner.innerHTML =
`<span class="ub-icon">🛠</span>` +
`<span class="ub-msg"><strong>Dev / Unpublished — v${FILE_VERSION}</strong> &nbsp;This build hasn't been published to Firebase yet.</span>` +
`<button class="ub-btn ub-dismiss" onclick="hideUpdateBanner()" title="Dismiss">✕</button>`;
banner.classList.add('show'); }
function triggerHtmlDownload(source){
const blob = typeof source === 'string' ? new Blob([source], { type:'text/html' }) : source;
const a = document.createElement('a');
a.href = URL.createObjectURL(blob);
a.download = 'hse-quiz-bowl-tracker.html';
document.body.appendChild(a);
a.click();
document.body.removeChild(a);
setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}
function downloadUpdate(url){
if (!url){ showToast('No download URL configured for this release.', 'warn'); return Promise.resolve(); }
showToast('Fetching update…');
const checkFirebasePayload = () => new Promise(resolve =>{
if (!db || !releaseHtmlRef || !releaseHtmlRef.once){ resolve(null); return; }
// Only trust the releaseHtml payload when the published metadata marks it as current
// (hasFirebasePayload === true) — otherwise a stale/leftover payload could be served.
Promise.all([
(versionRef && versionRef.once) ? versionRef.once('value') : Promise.resolve(null),
releaseHtmlRef.once('value')
])
.then(([metaSnap, htmlSnap]) =>{
const meta = metaSnap && metaSnap.val ? metaSnap.val() : null;
const html = htmlSnap && htmlSnap.val ? htmlSnap.val() : null;
const metaOk = meta && typeof meta === 'object' && meta.hasFirebasePayload === true;
resolve((metaOk && typeof html === 'string' && html) ? html : null);
})
.catch(() => resolve(null));
});
return checkFirebasePayload().then(htmlString =>{
// Prefer the HTML payload hosted in Firebase — no GitHub request needed, works on school networks
if (htmlString){
triggerHtmlDownload(htmlString);
showToast('Downloaded from Firebase! Replace your existing file with the new one.', 'success');
return true;
}
// Fallback: fetch from the GitHub raw URL so older releases without a Firebase payload still work
return fetch(url)
.then(r =>{
if (!r.ok) throw new Error('HTTP ' + r.status);
return r.blob(); })
.then(blob =>{
triggerHtmlDownload(blob);
showToast('Downloaded! Replace your existing file with the new one.', 'success'); })
.catch(err =>{
showToast('Download failed:' + err.message, 'warn');
return false; });
})
.catch(err =>{
showToast('Download failed:' + err.message, 'warn');
return false; });
}
