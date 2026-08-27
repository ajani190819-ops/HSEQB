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
function publishRelease(){
if (!isAdmin){ showToast('Not authorised.', 'warn'); return; }
const notes    = ($('releaseNotesInput')?.value || '').trim();
const comments = ($('adminCommentsInput')?.value || '').trim();
const payload  = { label:FILE_VERSION, buildId:FILE_BUILD_ID, downloadUrl:DOWNLOAD_URL, releaseNotes:notes, adminComments:comments, lastUpdated:new Date().toISOString() };
versionRef.set(payload)
.then(() =>{
showToast('Published v'+FILE_VERSION, 'success');
hideUpdateBanner();
checkReleasePrompt(FILE_BUILD_ID); })
.catch(e => showFirebaseError(e.message)); }
function showUpdateBanner(newLabel, downloadUrl, notes){
const banner = $('updateBanner');
if (!banner) return;
const hasUrl = downloadUrl && downloadUrl.startsWith('http');
banner.innerHTML =
`<span class="ub-icon">▲</span>` +
`<span class="ub-msg">This file is <strong>outdated / unpublished</strong> — published version is <strong>${newLabel}</strong> (you have ${FILE_VERSION})${notes ? ` — ${notes}` :''}.</span>` +
(hasUrl ? `<button class="ub-btn ub-download" onclick="downloadUpdate('${downloadUrl}')">↓ Download Update</button>` :'') +
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
function downloadUpdate(url){
if (!url){ showToast('No download URL configured for this release.', 'warn'); return; }
showToast('Fetching update…');
fetch(url)
.then(r =>{
if (!r.ok) throw new Error('HTTP ' + r.status);
return r.blob(); })
.then(blob =>{
const a = document.createElement('a');
a.href = URL.createObjectURL(blob);
a.download = 'hse-quiz-bowl-tracker.html';
document.body.appendChild(a);
a.click();
document.body.removeChild(a);
setTimeout(() => URL.revokeObjectURL(a.href), 5000);
showToast('Downloaded! Replace your existing file with the new one.', 'success'); })
.catch(err =>{
showToast('Download failed:' + err.message, 'warn'); });
}
