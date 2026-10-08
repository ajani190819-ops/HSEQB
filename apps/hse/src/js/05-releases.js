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
if (isUnpublished){
  prompt.classList.remove('hidden');
  upToDate.classList.add('hidden');
  upToDate.style.display = 'none';
} else {
  prompt.classList.add('hidden');
  upToDate.classList.remove('hidden');
  upToDate.style.display = 'block';
}
}
function setReleaseUploadStatus(msg, kind){
const el = $('releaseUploadStatus');
if (!el) return;
el.textContent = msg || '';
el.style.color = kind === 'ok' ? 'var(--success)' : kind === 'err' ? 'var(--danger)' : 'var(--text2)';
}
function extractReleaseBuildId(html){
if (typeof html !== 'string') return '';
// Built HSE artifacts always carry VERSION in the inlined constants module.
// Validating it prevents publishing a new Firebase version label alongside an
// older page captured before GitHub Pages finished deploying.
const match = html.match(/(?:const|var)\s+VERSION\s*=\s*['"]([^'"]+)['"]/);
return match ? String(match[1]).trim() : '';
}
function isBuiltReleaseArtifact(html){
if (typeof html !== 'string') return false;
// VERSION alone is not enough: a source module can contain the same constant.
// Require the generated document shape and reject any build placeholders so an
// admin cannot accidentally publish src/ or the unbuilt template as the app.
return /^\s*<!doctype html>/i.test(html) &&
  /<title>HSE Quiz Bowl Tracker<\/title>/i.test(html) &&
  /id=["']authGate["']/.test(html) &&
  /id=["']qbHeader["']/.test(html) &&
  !/@@@(CSS|JS)_[A-Z_]+@@@/.test(html);
}
function publishHtmlToFirebase(html, setStatus, finish){
const embeddedBuild = extractReleaseBuildId(html);
if (!isBuiltReleaseArtifact(html) || !embeddedBuild || embeddedBuild !== FILE_BUILD_ID){
const detail = !isBuiltReleaseArtifact(html) ? 'the file is not the generated single-file index.html' : embeddedBuild ? 'the file contains v' + embeddedBuild : 'the file has no embedded VERSION';
setStatus('Refused to publish: ' + detail + ', but this app is v' + FILE_BUILD_ID + '. Open the matching build and try again.', 'err');
showToast('The downloadable file does not match the build being published. Nothing was published.', 'warn', 7000);
return;
}
const kb = Math.max(1, Math.round(html.length / 1024));
if (html.length > 900 * 1024) setStatus('Warning: payload is ' + kb + ' KB — Firebase may reject values this large.', 'err');
else setStatus('Uploading ' + kb + ' KB to Firebase…');
releaseHtmlRef.set(html)
.then(() =>{ setStatus('HTML uploaded to Firebase (' + kb + ' KB).', 'ok'); finish(true, 'HTML uploaded to Firebase (' + kb + ' KB). Published.', { buildId:embeddedBuild, bytes:html.length }); })
.catch(e =>{
showFirebaseError('HTML upload failed: ' + e.message);
setStatus('Release was not published because the Firebase HTML upload failed: ' + e.message, 'err');
showToast('Nothing was published. The previous release remains available; try again with the matching index.html.', 'warn', 8000);
});
}
function publishRelease(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
if (!db || !releaseHtmlRef || !releaseHtmlRef.set){ showToast('Firebase is not connected — cannot publish.', 'warn'); return; }
const title    = ($('releaseTitleInput')?.value || '').trim().slice(0, 120);
const notes    = ($('releaseNotesInput')?.value || '').trim().slice(0, 5000);
const comments = ($('adminCommentsInput')?.value || '').trim().slice(0, 2000);
if (!title){ showToast('Add a short title for this update.', 'warn'); $('releaseTitleInput')?.focus(); return; }
if (!notes){ showToast('Write the public changelog before publishing.', 'warn'); $('releaseNotesInput')?.focus(); return; }
const payload  = { label:FILE_VERSION, buildId:FILE_BUILD_ID, title, downloadUrl:DOWNLOAD_URL, releaseNotes:notes, adminComments:comments, hasFirebasePayload:false, payloadBuildId:'', payloadBytes:0, lastUpdated:new Date().toISOString() };
const fileInput = $('releaseFileInput');
const file = fileInput && fileInput.files && fileInput.files[0];
const setStatus = (msg, kind) => setReleaseUploadStatus(msg, kind);
setStatus('Preparing release…');
const finish = (hasPayload, statusMsg, artifact) =>{
payload.hasFirebasePayload = !!hasPayload;
payload.payloadBuildId = artifact?.buildId || '';
payload.payloadBytes = artifact?.bytes || 0;
versionRef.set(payload)
.then(() => recordPublishedRelease({ ...payload, publishedAt:new Date().toISOString() }))
.then(() =>{
showToast('Published v'+FILE_VERSION, 'success');
hideUpdateBanner();
checkReleasePrompt(FILE_BUILD_ID);
if (statusMsg) setStatus(statusMsg + ' Changelog saved.', 'ok');
else if (!$('releaseUploadStatus')?.textContent?.trim()) setStatus('Published and added to the changelog.', 'ok');
if (fileInput) fileInput.value = '';
})
.catch(e =>{
showFirebaseError(e.message);
setStatus('Release published, but the changelog could not be saved: ' + e.message, 'err');
});
};
// A release is not published until its verified single-file HTML payload is uploaded.
// This keeps appVersion and releaseHtml atomic from the user's perspective.
if (file){
setStatus('Reading ' + file.name + '…');
file.text()
.then(html => publishHtmlToFirebase(html, setStatus, finish))
.catch(err =>{ setStatus('Release was not published — could not read file: ' + err.message, 'err'); showFirebaseError('Release file read failed: ' + err.message); });
return;
}
// No file attached — when served over http(s) (GitHub Pages / local server), read the exact current source
if (window.location.protocol === 'http:' || window.location.protocol === 'https:'){
setStatus('No file attached — reading current page source…');
fetch(window.location.href, { cache:'no-store' })
.then(r =>{ if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
.then(html => publishHtmlToFirebase(html, setStatus, finish))
.catch(() =>{
setStatus('Release was not published — could not read the current page source. Select the new index.html file.', 'err');
showToast('Attach the new index.html file to publish the Firebase download package. Nothing was published.', 'warn', 7000);
});
return;
}
// Local file (file://) — the exact source cannot be read from disk, so require the attached file
setStatus('Release was not published — select the new index.html file first.', 'err');
showToast('Attach the new index.html file so school-device users can download it via Firebase. Nothing was published.', 'warn', 7000);
}
function showUpdateBanner(newLabel, newBuild, downloadUrl, notes, hasFirebasePayload){
const banner = $('updateBanner');
if (!banner) return;
const hasUrl = !!(downloadUrl && downloadUrl.startsWith('http'));
const viaFb  = !!hasFirebasePayload;
const canOfferDownload = viaFb || hasUrl;
const encodedDownloadUrl = hasUrl ? encodeURIComponent(downloadUrl) : '';
const safeLabel = typeof updatesEscapeHtml === 'function' ? updatesEscapeHtml(newLabel) : String(newLabel || '');
const safeNotes = typeof updatesEscapeHtml === 'function' ? updatesEscapeHtml(notes) : String(notes || '');
const alreadyDownloaded = typeof updatesDownloadedBuild === 'function' && updatesDownloadedBuild() === String(newBuild || '');
const downloadArg = hasUrl ? `decodeURIComponent('${encodedDownloadUrl}')` : "''";
banner.innerHTML =
`<span class="ub-icon">▲</span>` +
`<span class="ub-msg">This file is <strong>outdated / unpublished</strong> — published version is <strong>${safeLabel}</strong> (you have ${FILE_VERSION})${notes ? ` — ${safeNotes}` :''}. ${viaFb ? 'The school-device download is served from Firebase; GitHub is only a fallback.' : ''}</span>` +
`<button class="ub-btn ub-history" onclick="openUpdatesModal()">View updates</button>` +
(canOfferDownload ? `<button class="ub-btn ub-download" onclick="downloadUpdate(${downloadArg})">${alreadyDownloaded ? '↓ Download again' : (viaFb ? '↓ Download for school device' : '↓ Download update')}</button>` :'') +
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
function triggerHtmlDownload(source, buildId){
const blob = typeof source === 'string' ? new Blob([source], { type:'text/html' }) : source;
const a = document.createElement('a');
a.href = URL.createObjectURL(blob);
const safeBuild = String(buildId || '').replace(/[^a-zA-Z0-9._-]/g, '-');
a.download = safeBuild ? 'hse-quiz-bowl-tracker-v' + safeBuild + '.html' : 'hse-quiz-bowl-tracker.html';
document.body.appendChild(a);
a.click();
document.body.removeChild(a);
setTimeout(() => URL.revokeObjectURL(a.href), 5000);
}
function downloadUpdate(url){
showToast('Preparing school-device download…');
const readFirebasePayload = () => new Promise(resolve =>{
if (!db || !versionRef || !releaseHtmlRef || !versionRef.once || !releaseHtmlRef.once){ resolve({ status:'unavailable' }); return; }
Promise.all([versionRef.once('value'), releaseHtmlRef.once('value')])
.then(([metaSnap, htmlSnap]) =>{
const meta = metaSnap && metaSnap.val ? metaSnap.val() : null;
const raw = htmlSnap && htmlSnap.val ? htmlSnap.val() : null;
const html = typeof raw === 'string' ? raw : raw && typeof raw.html === 'string' ? raw.html : '';
const expected = meta && typeof meta === 'object' ? String(meta.buildId || '') : String(meta || '');
const declared = meta && typeof meta === 'object' ? String(meta.payloadBuildId || '') : '';
const metaClaimsPayload = !!(meta && typeof meta === 'object' && meta.hasFirebasePayload === true);
const embedded = extractReleaseBuildId(html);
if (html && isBuiltReleaseArtifact(html) && expected && embedded === expected && (!declared || declared === embedded)){
resolve({ status:'valid', html, buildId:expected });
} else if (html || metaClaimsPayload){
resolve({ status:'invalid', expected, declared, embedded });
} else {
resolve({ status:'unavailable' });
}
})
.catch(() => resolve({ status:'unavailable' }));
});
return readFirebasePayload().then(result =>{
// Firebase is the primary path. It works from a downloaded local HTML file and
// does not send school-device users through GitHub at all.
if (result.status === 'valid'){
triggerHtmlDownload(result.html, result.buildId);
if (typeof updatesMarkDownloaded === 'function') updatesMarkDownloaded(result.buildId);
showToast('Downloaded v' + result.buildId + ' from Firebase. Open that versioned file from your Downloads folder.', 'success', 6000);
return true;
}
if (result.status === 'invalid'){
// Do not fall through to GitHub with a known-bad package: that is how users
// repeatedly receive the same old HTML file while the database says a newer
// version exists.
showToast('The Firebase download package does not match its published version. Ask an admin to republish the matching index.html; no GitHub download was attempted.', 'warn', 8000);
return false;
}
const firebaseClaimsPayload = !!(typeof latestReleaseMeta === 'object' && latestReleaseMeta && latestReleaseMeta.hasFirebasePayload === true);
if (!url || firebaseClaimsPayload){
showToast(firebaseClaimsPayload
  ? 'Could not read the verified Firebase package. Check your sign-in or ask an admin to republish the matching index.html; no GitHub download was attempted.'
  : 'No verified school-device package is available for this release. Ask an admin to publish the matching index.html.', 'warn', 8000);
return false;
}
// Legacy fallback: older releases may have no Firebase payload. Validate the
// fallback too, so a delayed GitHub Pages deploy cannot create a repeat-download loop.
return fetch(url, { cache:'no-store' })
.then(r =>{ if (!r.ok) throw new Error('HTTP ' + r.status); return r.text(); })
.then(html =>{
const expected = updatesCurrentBuild() || '';
const embedded = extractReleaseBuildId(html);
if (!isBuiltReleaseArtifact(html)) throw new Error('downloaded file is not the generated single-file index.html');
if (expected && embedded !== expected) throw new Error('downloaded file is v' + (embedded || 'unknown') + ', expected v' + expected);
triggerHtmlDownload(html, expected);
if (typeof updatesMarkDownloaded === 'function') updatesMarkDownloaded(expected);
showToast('Downloaded v' + (expected || FILE_VERSION) + '. Open the versioned file from your Downloads folder.', 'success', 6000);
return true;
})
.catch(err =>{
showToast('Download failed: ' + err.message, 'warn', 7000);
return false;
});
}).catch(err =>{
showToast('Download failed: ' + err.message, 'warn', 7000);
return false;
});
}
