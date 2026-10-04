let _flashTimer  = null;
let _connected   = false;
const SAVE_INDICATOR_IDS = ['autosaveStatus', 'autosaveStatusMobile'];
const ALL_INDICATOR_STATES  = ['state-connecting', 'state-idle', 'state-flash', 'state-error'];
function _setIndicatorState(stateName, labelText, title){
SAVE_INDICATOR_IDS.forEach(id =>{
const el = $(id);
if (!el) return;
el.classList.remove(...ALL_INDICATOR_STATES);
el.classList.add('state-' + stateName);
const label = el.querySelector('.save-label');
if (label) label.textContent = labelText;
if (title) el.title = title; else el.removeAttribute('title'); });
}
function applyDebugMenuVisibility(){
const show = !_connected;
const debugEl  = $('sec-debug');
const debugBtn = $('jumpBtn-sec-debug');
if (debugEl)  debugEl.style.display  = show ? '' :'none';
if (debugBtn) debugBtn.style.display = show ? '' :'none'; }
const setLoadingState = () =>{
_connected = false;
_setIndicatorState('connecting', 'Connecting…');
applyDebugMenuVisibility(); };
const updateAutoSave = () =>{
_connected = true;
if (!_flashTimer) _setIndicatorState('idle', 'Synced');
applyDebugMenuVisibility(); };
const showFirebaseError = msg =>{
_connected = false;
clearTimeout(_flashTimer);
_flashTimer = null;
_setIndicatorState('error', 'Offline', msg || 'Connection issue — changes may not be saved');
applyDebugMenuVisibility(); };
function notifySaveStart(){
if (!_connected) return;
clearTimeout(_flashTimer);
_setIndicatorState('flash', 'Syncing…'); }
function notifySaveComplete(){
if (!_connected) return;
clearTimeout(_flashTimer);
_setIndicatorState('flash', 'Synced');
_flashTimer = setTimeout(() =>{ _flashTimer = null; _setIndicatorState('idle', 'Synced'); }, 2000);
}
function notifySaveError(msg){ clearTimeout(_flashTimer); _flashTimer = null; showFirebaseError(msg); }
// ── GitHub Deploy Status ──────────────────────────────────────────────────
