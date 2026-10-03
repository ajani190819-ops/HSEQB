const $=id=>document.getElementById(id);
const isIframe = (() =>{
try{
if (window.self === window.top) return false; // not in an iframe at all
try{
const parentHref = window.parent.location.href; // throws on cross-origin
return parentHref.includes('claude.ai');
} catch(crossOriginErr){
const ref = document.referrer || '';
return ref.includes('claude.ai') || ref === ''; }
} catch(e){ return false; }
})();
// Global error resilience — catch JS errors and show a non-fatal warning
window.addEventListener('error', function(e){
const msg=(e&&e.message)?e.message:'Unknown error';
console.error('[HSE QB]', msg, e&&e.error);
if (!e.filename||e.filename===window.location.href||e.filename===''){
try{ showToast('&#9888; JS error: '+msg.slice(0,70),'warn',5000); }catch(_){}
}
});
window.addEventListener('unhandledrejection', function(e){
console.error('[HSE QB Promise]', e.reason);
try{ showToast('&#9888; Async error — check console','warn',4000); }catch(_){}
});
// _safe(fn, label): run fn(), catch+log errors, show toast. Returns null on error.
function _safe(fn,label){
try{ return fn(); }
catch(e){
console.error('[_safe:'+(label||'?')+']',e);
try{ showToast('&#9888; Error in '+(label||'component')+': '+e.message.slice(0,60),'warn',4000); }catch(_){}
return null;
}
}
