function toArray(val){
if (!val) return [];
if (Array.isArray(val)) return val;
return Object.keys(val).sort((a,b)=>+a-+b).map(k=>val[k]); }
function normalizeSession(s){
if (!s) return s;
s.teams=toArray(s.teams); s.answerLog=toArray(s.answerLog);
s.answers=toArray(s.answers); s.categories=toArray(s.categories);
if (s.players) Object.values(s.players).forEach(p=>{p.answers=toArray(p.answers);});
s.teams.forEach(t=>{t.playerMembers=toArray(t.playerMembers);});
if (typeof s.tHeard!=='number') s.tHeard=0;
return s; }
const CURRENT_SESSION_KEY='currentSession';
const CATEGORY_TREE ={
'Literature':    ['Poetry','Theater','Fiction','Nonfiction'],
'Science':       ['Biology','Chemistry','Physics','Math','Astronomy','Computer Science','Earth Science'],
'History':       ['Ancient History','American History','European History','World History'],
'Social Studies':['Philosophy','Geography','Religion','Mythology','Social Sciences'],
'Fine Arts':     ['Visual Arts','Music','Musicals','Opera'],
'Pop Culture':   ['Popular Media','Sports','Current Events'],
};
const DEFAULT_CATEGORIES = Object.values(CATEGORY_TREE).flat();
const CAT_PARENT ={};
Object.entries(CATEGORY_TREE).forEach(([parent, subs]) => subs.forEach(s => CAT_PARENT[s] = parent));
function getParentCat(cat){
if (CAT_PARENT[cat]) return CAT_PARENT[cat];  // subcategory → its parent
if (CATEGORY_TREE[cat]) return cat;            // already a parent (general)
return cat;                                    // unknown
}
function catLabel(cat){
const p = CAT_PARENT[cat];
if (p) return `${p} › ${cat}`;          // subcategory:"Science › Biology"
if (CATEGORY_TREE[cat]) return cat;      // parent used as general:just "Science"
return cat;                              // unknown / legacy
}
// Official scoring model: bonuses belong to the team, not to an individual player.
// Keep all Bonus events in the log, but never include them in player skill metrics.
const PLAYER_PERFORMANCE_TYPES = new Set(['Power', 'Toss-up', 'Neg', 'Miss']);
function isPlayerPerformanceAnswer(answer){
return !!answer && PLAYER_PERFORMANCE_TYPES.has(answer.pointType);
}
function isTeamBonusAnswer(answer){
return !!answer && answer.pointType === 'Bonus';
}
function answerActorLabel(answer){
if (isTeamBonusAnswer(answer)) return answer.player && /^— .* Bonus —$/.test(answer.player) ? answer.player.replace(/^— | —$/g, '') : 'Team Bonus';
if (answer.pointType === 'Dead') return 'Dead TU';
return answer.player || '—';
}
