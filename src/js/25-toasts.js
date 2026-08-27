function showRecordToast(msg, cls){
const t = $('recordToast');
if (!t) return;
t.textContent = msg;
t.className = 'show' + (cls ? ' '+cls :'');
clearTimeout(t._timer);
t._timer = setTimeout(() =>{ t.className = ''; }, 1700);
}
function recomputeAdmin(){
if (isIframe && _iframeDebugActive) return; // preserve temp admin grant in preview
const name = localStorage.getItem('qb_userName') || '';
if (adminList.includes(name)) _adminToken.grant(); else _adminToken.revoke();
applyAdminUI(); }
function applyAdminUI(){
const ccs = $('catColorSection');
if (ccs) ccs.style.display = isAdmin ? '' :'none';
const cfs = $('catFreqSection');
if (cfs) cfs.style.display = isAdmin ? '' :'none';
if (isAdmin){ renderCatColorPickers(); renderCatFreqPickers(); }
const dangerEl = $('sec-danger');
const adminEl  = $('sec-admin');
const dangerBtn = $('jumpBtn-sec-danger');
const adminBtn  = $('jumpBtn-sec-admin');
if (dangerEl)  dangerEl.style.display  = isAdmin ? '' :'none';
if (adminEl)   adminEl.style.display   = isAdmin ? '' :'none';
if (dangerBtn) dangerBtn.style.display  = isAdmin ? '' :'none';
if (adminBtn)  adminBtn.style.display   = isAdmin ? '' :'none';
applyDebugMenuVisibility();
document.querySelectorAll('.session-invalid-toggle').forEach(el =>{ el.style.display = isAdmin ? '' :'none'; });
document.querySelectorAll('.ld-admin-btn').forEach(el =>{ el.style.display = isAdmin ? '' :'none'; });
renderAdminPanel(); }
function showToast(msg, type, duration, undoCallback){
const t = $('appToast');
if (!t){ alert(msg); return; }
t.innerHTML = '';
const msgEl = document.createElement('span');
msgEl.textContent = msg;
t.appendChild(msgEl);
if(undoCallback){
const space = document.createElement('span');
space.textContent = ' ';
t.appendChild(space);
const undoBtn = document.createElement('button');
undoBtn.textContent = 'Undo';
undoBtn.style.cssText = 'background:rgba(255,255,255,.25);border:1px solid rgba(255,255,255,.4);color:#fff;padding:2px 8px;border-radius:4px;cursor:pointer;font-weight:700;font-family:inherit;font-size:.9em;margin-left:8px;';
undoBtn.onclick = () => {
undoCallback();
t.className = '';
showToast('Undone', 'info', 1500); };
t.appendChild(undoBtn); }
t.className   = 'show' + (type ? ' toast-' + type :'');
clearTimeout(t._timer);
t._timer = setTimeout(() =>{ t.className = ''; }, duration || 2800);
}
var _confirmResolve = null;
function showConfirm(msg, okLabel, warnStyle){
return new Promise(resolve =>{
_confirmResolve = resolve;
const el    = $('confirmToast');
const msgEl = $('confirmToastMsg');
const okEl  = $('confirmToastOk');
if (!el){ resolve(confirm(msg)); return; }
msgEl.textContent = msg;
okEl.textContent  = okLabel || 'Confirm';
okEl.className    = 'ct-ok' + (warnStyle === 'warn' ? ' warn-ok' :'');
el.classList.add('show'); });
}
function resolveConfirmToast(result){
const el = $('confirmToast');
if (el) el.classList.remove('show');
if (_confirmResolve){ _confirmResolve(result); _confirmResolve = null; }
}
