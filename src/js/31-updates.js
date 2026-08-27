/*
 * Public release history and Updates center.
 *
 * appVersion remains the single source of truth for the currently downloadable
 * build. releaseHistory keeps the human-readable changelog that users can see.
 * Keeping those concerns separate means publishing a new log never overwrites
 * the history that came before it.
 */
var releaseHistoryCache = {};
var latestReleaseMeta = null;
var updatesModalOpen = false;

function updatesEscapeHtml(value){
  return String(value == null ? '' : value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
function updatesFormatText(value){
  return updatesEscapeHtml(value).replace(/\r?\n/g, '<br>');
}
function updatesParseVersion(value){
  return String(value || '').split('.').map(n => parseInt(n, 10) || 0);
}
function updatesCompareVersions(a, b){
  const av = updatesParseVersion(a), bv = updatesParseVersion(b);
  for (let i = 0; i < Math.max(av.length, bv.length); i++){
    if ((av[i] || 0) !== (bv[i] || 0)) return (av[i] || 0) > (bv[i] || 0) ? 1 : -1;
  }
  return 0;
}
function updatesFormatDate(value){
  if (!value) return 'Date not recorded';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return 'Date not recorded';
  return date.toLocaleDateString(undefined, { year:'numeric', month:'short', day:'numeric' });
}
function updatesCurrentBuild(){
  return latestReleaseMeta && typeof latestReleaseMeta === 'object'
    ? (latestReleaseMeta.buildId || '') : '';
}
function updatesCurrentLabel(){
  return latestReleaseMeta && typeof latestReleaseMeta === 'object'
    ? (latestReleaseMeta.label || '') : '';
}
function setLatestReleaseMeta(data){
  if (!data){ latestReleaseMeta = null; }
  else if (typeof data === 'object'){
    latestReleaseMeta = { ...data };
  } else {
    // Older appVersion records were just strings. Keep them readable in the center.
    latestReleaseMeta = { label:String(data), buildId:String(data), releaseNotes:'' };
  }
  updateUpdatesBadge();
  const version = $('updatesPublishVersion');
  if (version) version.textContent = FILE_VERSION;
  if (updatesModalOpen) renderUpdatesCenter();
}
function updateUpdatesBadge(){
  const badge = $('updatesUnreadBadge');
  if (!badge) return;
  const remoteBuild = updatesCurrentBuild();
  const isNew = !!remoteBuild && updatesCompareVersions(remoteBuild, FILE_BUILD_ID) > 0;
  badge.textContent = isNew ? 'New' : '';
  badge.classList.toggle('show', isNew);
  badge.setAttribute('aria-label', isNew ? 'New updates available' : 'No new updates');
}
function getReleaseHistoryEntries(){
  let entries = Object.entries(releaseHistoryCache || {}).map(([id, release]) => ({
    id, ...(release && typeof release === 'object' ? release : {})
  }));
  entries = entries.filter(item => item.buildId || item.label || item.releaseNotes || item.title);
  entries.sort((a, b) =>{
    const ad = new Date(a.publishedAt || a.lastUpdated || 0).getTime();
    const bd = new Date(b.publishedAt || b.lastUpdated || 0).getTime();
    return bd - ad;
  });

  // A current appVersion written by an older build may not have a history row yet.
  // Show it in the center instead of making the public page look empty.
  const current = latestReleaseMeta && typeof latestReleaseMeta === 'object'
    ? latestReleaseMeta : null;
  if (current && (current.buildId || current.label) && !entries.some(item =>
    item.buildId && current.buildId && item.buildId === current.buildId)){
    entries.unshift({
      id:'current-release',
      label:current.label || current.buildId,
      buildId:current.buildId || current.label,
      title:current.title || '',
      releaseNotes:current.releaseNotes || '',
      downloadUrl:current.downloadUrl || '',
      hasFirebasePayload:!!current.hasFirebasePayload,
      publishedAt:current.lastUpdated || current.publishedAt || ''
    });
  }

  // Preview mode has no Firebase data. A small local example keeps the feature
  // discoverable in the built-in preview without ever writing fake data remotely.
  if (!entries.length && isIframe){
    entries.push({
      id:'preview-release', label:FILE_VERSION, buildId:FILE_BUILD_ID,
      title:'A clearer home for updates',
      releaseNotes:'The Updates center now keeps a shared release history. Admins can publish a build, write public release notes, and attach the downloadable file here.',
      publishedAt:new Date().toISOString(), preview:true
    });
  }
  return entries;
}
function renderUpdatesSummary(entries){
  const el = $('updatesCurrentSummary');
  if (!el) return;
  const currentBuild = updatesCurrentBuild() || FILE_BUILD_ID;
  const currentLabel = updatesCurrentLabel() || FILE_VERSION;
  const currentEntry = entries.find(item => item.buildId === currentBuild) || entries[0];
  const isAhead = updatesCompareVersions(currentBuild, FILE_BUILD_ID) > 0;
  const status = isAhead ? 'Update available' : 'You are on the latest local build';
  const notes = currentEntry?.releaseNotes ? updatesFormatText(currentEntry.releaseNotes) : 'No release notes have been added yet.';
  el.innerHTML = `<div class="updates-current-kicker">CURRENT RELEASE</div>` +
    `<div class="updates-current-main"><div><div class="updates-current-title">${updatesEscapeHtml(currentEntry?.title || 'HSE Quiz Bowl Tracker')}</div>` +
    `<div class="updates-current-notes">${notes}</div></div>` +
    `<div class="updates-version-stack"><strong>v${updatesEscapeHtml(currentLabel)}</strong><span class="updates-status ${isAhead ? 'updates-status-new' : ''}">${status}</span></div></div>`;
}
function renderReleaseCard(item, currentBuild){
  const version = item.label || item.buildId || 'Unversioned';
  const title = item.title || ('HSE Quiz Bowl Tracker ' + (version ? 'v' + version : 'update'));
  const notes = item.releaseNotes || 'No public release notes were added for this update.';
  const isCurrent = !!currentBuild && item.buildId === currentBuild;
  const by = item.publishedBy ? ` · ${updatesEscapeHtml(item.publishedBy)}` : '';
  const currentPill = isCurrent ? '<span class="updates-current-pill">Current</span>' : '';
  const previewPill = item.preview ? '<span class="updates-preview-pill">Preview</span>' : '';
  const canDownload = !!item.downloadUrl && /^https?:/i.test(item.downloadUrl) && isCurrent;
  const encodedDownloadUrl = canDownload ? encodeURIComponent(item.downloadUrl) : '';
  const download = canDownload
    ? `<button class="button updates-card-download" onclick="downloadUpdate(decodeURIComponent('${encodedDownloadUrl}'))">↓ Download build</button>` : '';
  return `<article class="updates-release-card${isCurrent ? ' is-current' : ''}">` +
    `<div class="updates-release-rail"><span class="updates-release-dot"></span></div>` +
    `<div class="updates-release-content"><div class="updates-release-meta"><strong>v${updatesEscapeHtml(version)}</strong><span>${updatesFormatDate(item.publishedAt || item.lastUpdated)}${by}</span>${currentPill}${previewPill}</div>` +
    `<h4>${updatesEscapeHtml(title)}</h4><div class="updates-release-notes">${updatesFormatText(notes)}</div>${download ? `<div class="updates-release-actions">${download}</div>` : ''}</div></article>`;
}
function renderUpdatesCenter(){
  const list = $('updatesList');
  if (!list) return;
  const entries = getReleaseHistoryEntries();
  const currentBuild = updatesCurrentBuild() || (entries[0] && entries[0].buildId) || FILE_BUILD_ID;
  renderUpdatesSummary(entries);
  const count = $('updatesHistoryCount');
  if (count) count.textContent = entries.length ? `${entries.length} ${entries.length === 1 ? 'release' : 'releases'}` : '';
  if (!entries.length){
    list.innerHTML = '<div class="updates-empty"><div class="updates-empty-icon">↻</div><strong>No updates have been published yet.</strong><span>When an admin publishes a release, its notes will appear here for everyone.</span></div>';
  } else {
    list.innerHTML = entries.map(item => renderReleaseCard(item, currentBuild)).join('');
  }
  const status = $('updatesLoadStatus');
  if (status){
    if (isIframe) status.textContent = 'Preview data · Firebase history is disabled';
    else status.textContent = entries.length ? 'Synced release history' : 'No release history yet';
  }
}
function renderUpdatesAdminUI(){
  const panel = $('updatesAdminPanel');
  if (panel) panel.style.display = isAdmin ? '' : 'none';
  const version = $('updatesPublishVersion');
  if (version) version.textContent = FILE_VERSION;
  updateUpdatesBadge();
  if (typeof checkReleasePrompt === 'function') checkReleasePrompt(updatesCurrentBuild());
}
function openUpdatesModal(){
  const modal = $('updatesModal');
  if (!modal) return;
  updatesModalOpen = true;
  modal.classList.add('open');
  renderUpdatesAdminUI();
  renderUpdatesCenter();
  if (!isIframe && releaseHistoryRef && releaseHistoryRef.once){
    const status = $('updatesLoadStatus');
    if (status) status.textContent = 'Refreshing release history…';
    releaseHistoryRef.once('value').then(snap =>{
      releaseHistoryCache = snap.val() || {};
      renderUpdatesCenter();
    }).catch(() =>{
      if (status) status.textContent = 'Could not refresh release history';
    });
  }
}
function closeUpdatesModal(){
  const modal = $('updatesModal');
  if (modal) modal.classList.remove('open');
  updatesModalOpen = false;
}
function refreshUpdates(){
  if (!releaseHistoryRef || !releaseHistoryRef.once || isIframe){
    renderUpdatesCenter();
    return;
  }
  const status = $('updatesLoadStatus');
  if (status) status.textContent = 'Refreshing release history…';
  releaseHistoryRef.once('value').then(snap =>{
    releaseHistoryCache = snap.val() || {};
    renderUpdatesCenter();
    showToast('Release history refreshed.', 'success', 1800);
  }).catch(e =>{
    if (status) status.textContent = 'Could not refresh release history';
    showToast('Could not refresh release history: ' + e.message, 'warn');
  });
}
function recordPublishedRelease(payload){
  if (isIframe || !releaseHistoryRef || !releaseHistoryRef.push) return Promise.resolve();
  const entry = {
    label:payload.label || FILE_VERSION,
    buildId:payload.buildId || FILE_BUILD_ID,
    title:String(payload.title || '').trim().slice(0, 120),
    releaseNotes:String(payload.releaseNotes || '').trim().slice(0, 5000),
    adminComments:String(payload.adminComments || '').trim().slice(0, 2000),
    downloadUrl:payload.downloadUrl || DOWNLOAD_URL,
    hasFirebasePayload:!!payload.hasFirebasePayload,
    publishedAt:payload.publishedAt || new Date().toISOString(),
    publishedBy:localStorage.getItem('qb_userName') || authUser?.email || 'Admin',
    publishedByUid:authUser?.uid || clientId || ''
  };
  const existing = Object.values(releaseHistoryCache || {});
  const duplicate = existing.some(item => item && item.buildId === entry.buildId &&
    item.title === entry.title && item.releaseNotes === entry.releaseNotes);
  if (duplicate) return Promise.resolve();
  const releaseRef = releaseHistoryRef.push();
  return releaseRef.set(entry).then(() =>{
    // The live listener normally updates this immediately; updating the cache here
    // also makes the center feel instant when a listener is slow to fire.
    if (releaseRef.key) releaseHistoryCache[releaseRef.key] = entry;
    if (updatesModalOpen) renderUpdatesCenter();
  });
}

// Keep the publishing form available in the new public center while admin access
// continues to be controlled by the existing account/admin-list flow.
if (typeof document !== 'undefined'){
  document.addEventListener('keydown', event =>{
    if (event.key === 'Escape' && $('updatesModal')?.classList.contains('open')) closeUpdatesModal();
  });
}
