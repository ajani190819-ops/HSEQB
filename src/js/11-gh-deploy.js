const GH_API = 'https://api.github.com/repos/ajani190819-ops/HSEQB/actions/runs?per_page=1';
let GH_TOKEN = null; // fetched from Firebase at runtime
const GH_POLL_INTERVAL = 10000; // 10s
let _ghPollTimer = null;
function _setGhState(state, title){
const el = $('versionBadge');
if(!el) return;
el.className = el.className.replace(/\bgh-state-\S+/g,'').trim() + ' gh-state-' + state;
el.title = title;
}
async function checkGhDeploy(){
try {
if(!GH_TOKEN){
const snap = await db.ref('config/githubToken').get();
GH_TOKEN = snap.exists() ? snap.val() : null;
}
if(!GH_TOKEN){ _setGhState('unknown','GitHub token not configured'); return; }
const res = await fetch(GH_API, { headers:{ Accept:'application/vnd.github+json', Authorization:'Bearer '+GH_TOKEN } });
if(!res.ok){ _setGhState('unknown', 'GitHub status unavailable'); return; }
const data = await res.json();
const run = data.workflow_runs?.[0];
if(!run){ _setGhState('unknown', 'No deploy runs found'); return; }
const { status, conclusion, display_title, created_at } = run;
const ago = Math.round((Date.now() - new Date(created_at).getTime()) / 60000);
const agoStr = ago < 60 ? ago+'m ago' : Math.round(ago/60)+'h ago';
if(status === 'in_progress' || status === 'queued' || status === 'waiting'){
_setGhState('pending', `Deploying… — "${display_title}" (${agoStr})`);
} else if(status === 'completed' && conclusion === 'success'){
_setGhState('success', `Deploy succeeded — "${display_title}" (${agoStr})`);
} else if(status === 'completed' && (conclusion === 'failure' || conclusion === 'cancelled')){
_setGhState('failure', `Deploy ${conclusion} — "${display_title}" (${agoStr})`);
} else {
_setGhState('unknown', `Status: ${status}/${conclusion||'—'} — "${display_title}"`);
}
} catch(e){
_setGhState('unknown', 'GitHub status unavailable');
}
}
function startGhPolling(){
checkGhDeploy();
_ghPollTimer = setInterval(checkGhDeploy, GH_POLL_INTERVAL);
}
