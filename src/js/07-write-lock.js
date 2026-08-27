let clientId = (() =>{
try{
const k='qb_clientId', e=localStorage.getItem(k); if (e) return e;
const f=crypto?.randomUUID?.()??Date.now().toString(36)+Math.random().toString(36).slice(2);
localStorage.setItem(k,f); return f;
} catch{ return Date.now().toString(36)+Math.random().toString(36).slice(2); }
})();
const writeInFlight = new Set();
function withWriteLock(id, fn){
writeInFlight.add(id);
try{ return fn(); } finally{ setTimeout(()=>writeInFlight.delete(id), 300); }
}
function updateSessionAtomic(id, mutator){
if (isIframe) return Promise.resolve(); // blocked in preview
writeInFlight.add(id);
notifySaveStart();
return sessionsRef.child(id).transaction(
cur =>{
if (!cur) return cur;
const n = normalizeSession(cur);
mutator(n);
n.lastUpdated = new Date().toISOString();
n.updatedBy = clientId;
return n; },
err =>{
setTimeout(() => writeInFlight.delete(id), 300);
notifySaveComplete(); // decrement counter; error already shown by caller
if (err) showFirebaseError('Save failed:' + err.message); },
false
).then(() =>{
setTimeout(() => writeInFlight.delete(id), 300);
notifySaveComplete(); });
}
function setSessionNonAtomic(id, value){
if (isIframe) return Promise.resolve();
writeInFlight.add(id); notifySaveStart();
return sessionsRef.child(id).set(value)
.then(()=>notifySaveComplete())
.catch(e=>{notifySaveComplete();throw e;})
.finally(()=>setTimeout(()=>writeInFlight.delete(id),300)); }
