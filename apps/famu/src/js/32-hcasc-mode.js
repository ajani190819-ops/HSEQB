/*
 * HCASC match mode
 *
 * The original tracker was designed around generic quiz-bowl scoring.  HCASC
 * has a deliberately different shape: three four-minute Face-Off rounds,
 * team bonuses, and a two-team, 60-second Ultimate Challenge.  This module
 * keeps the existing player analytics and exports intact while adding an
 * official-format scoreboard and richer event metadata to every new entry.
 */
const HCASC_FORMAT = 'HCASC';
const HCASC_ROUNDS = Object.freeze({
  1: { label:'Face-Off 1', short:'FO 1', seconds:240 },
  2: { label:'Face-Off 2', short:'FO 2', seconds:240 },
  3: { label:'Face-Off 3', short:'FO 3', seconds:240 },
  4: { label:'Ultimate Challenge', short:'Ultimate', seconds:60 }
});
const HCASC_POINTS = Object.freeze({ faceOff:10, bonus:20, ultimate:25, tiebreaker:10, incorrect:0 });
const HCASC_DEFAULT_BOARD = ['History & Culture', 'Science & Technology', 'Arts & Humanities', 'Society & Popular Culture'];

function hcascEscape(value){
  return String(value == null ? '' : value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
}
function hcascRoundNumber(value){
  const n = Number(value);
  return HCASC_ROUNDS[n] ? n : 1;
}
function hcascRoundDefaults(){
  return {
    1:{ categories:[...HCASC_DEFAULT_BOARD], questions:0, faceOffPoints:0, bonusPoints:0 },
    2:{ categories:[...HCASC_DEFAULT_BOARD], questions:0, faceOffPoints:0, bonusPoints:0 },
    3:{ categories:[...HCASC_DEFAULT_BOARD], questions:0, faceOffPoints:0, bonusPoints:0 },
    4:{ categories:[...HCASC_DEFAULT_BOARD], questions:0, faceOffPoints:0, bonusPoints:0 }
  };
}
function hcascEnsureSession(session){
  if (!session) return session;
  // Sessions created before HCASC mode used power/neg quiz-bowl scoring. Do a
  // one-time, explicit migration so opening an existing FAMU session cannot
  // quietly display a non-HCASC score on the official scoreboard.
  if (!session.format){
    session.answerLog = toArray(session.answerLog).map(answer =>{
      const migrated = {...answer};
      migrated.legacyPointType = answer.pointType || null;
      if (answer.pointType === 'Power' || answer.pointType === 'Toss-up'){
        migrated.pointType = 'Toss-up';
        migrated.points = HCASC_POINTS.faceOff;
        migrated.phase = 'Face-Off';
      } else if (answer.pointType === 'Bonus'){
        migrated.points = HCASC_POINTS.bonus;
        migrated.phase = 'Bonus';
      } else if (answer.pointType === 'Neg' || answer.pointType === 'Miss' || answer.pointType === 'Dead'){
        migrated.points = HCASC_POINTS.incorrect;
        migrated.phase = 'Face-Off';
      }
      migrated.format = HCASC_FORMAT;
      migrated.round = Number(answer.round) || 1;
      return migrated;
    });
    Object.values(session.players || {}).forEach(player =>{
      player.answers = session.answerLog.filter(answer => answer.player === player.name && isPlayerPerformanceAnswer(answer));
      player.points = player.answers.reduce((sum, answer) => sum + (Number(answer.points) || 0), 0);
    });
    session.format = HCASC_FORMAT;
    session.scoreModel = 'HCASC-2026';
  }
  session.format = session.format || HCASC_FORMAT;
  session.currentRound = hcascRoundNumber(session.currentRound);
  session.currentPhase = session.currentPhase || (session.currentRound === 4 ? 'Ultimate' : 'Face-Off');
  session.rounds = session.rounds && typeof session.rounds === 'object' ? session.rounds : hcascRoundDefaults();
  const defaults = hcascRoundDefaults();
  Object.keys(defaults).forEach(key =>{
    const round = session.rounds[key] = session.rounds[key] || {};
    round.categories = Array.isArray(round.categories) && round.categories.length
      ? round.categories.slice(0, 4) : [...defaults[key].categories];
    while (round.categories.length < 4) round.categories.push(defaults[key].categories[round.categories.length]);
    if (typeof round.questions !== 'number') round.questions = 0;
    if (typeof round.faceOffPoints !== 'number') round.faceOffPoints = 0;
    if (typeof round.bonusPoints !== 'number') round.bonusPoints = 0;
  });
  if (typeof session.questionNumber !== 'number') session.questionNumber = 0;
  if (typeof session.clockRemainingSeconds !== 'number') session.clockRemainingSeconds = HCASC_ROUNDS[session.currentRound].seconds;
  if (typeof session.clockRunning !== 'boolean') session.clockRunning = false;
  if (typeof session.clockStartedAt !== 'number') session.clockStartedAt = 0;
  session.activeCategory = session.activeCategory || session.rounds[session.currentRound].categories[0];
  session.activeQuestionId = session.activeQuestionId || null;
  session.activeTeamId = session.activeTeamId || null;
  session.activePlayer = session.activePlayer || null;
  session.roundPlayers = session.roundPlayers && typeof session.roundPlayers === 'object' ? session.roundPlayers : {};
  session.ultimateCounts = session.ultimateCounts && typeof session.ultimateCounts === 'object' ? session.ultimateCounts : {};
  session.ultimateClocks = session.ultimateClocks && typeof session.ultimateClocks === 'object' ? session.ultimateClocks : {};
  session.ultimateCategoriesUsed = session.ultimateCategoriesUsed && typeof session.ultimateCategoriesUsed === 'object' ? session.ultimateCategoriesUsed : {};
  session.ultimateTeamId = session.ultimateTeamId || null;
  return session;
}

// Normalize both Firebase/local records and imported records before they reach
// the board.  The base normalizer still owns the legacy map/array migrations.
const _hcascBaseNormalizeSession = normalizeSession;
normalizeSession = function(session){
  return hcascEnsureSession(_hcascBaseNormalizeSession(session));
};

function hcascTeamForPlayer(session, player){
  if (!session || !player) return null;
  return (session.teams || []).find(team => (team.playerMembers || []).includes(player)) || null;
}
function hcascTeamIdForAnswer(session, answer){
  if (answer && answer.teamId) return String(answer.teamId);
  if (!answer) return null;
  if (isTeamBonusAnswer(answer)){
    const match = String(answer.player || '').match(/^—\s*(.*?)\s+Bonus\s*—$/);
    if (match){
      const team = (session.teams || []).find(t => t.name === match[1]);
      if (team) return team.id;
    }
  }
  return hcascTeamForPlayer(session, answer.player)?.id || null;
}
function hcascTeamScore(session, teamId){
  if (!session || !teamId) return 0;
  return toArray(session.answerLog).reduce((total, answer) =>{
    return hcascTeamIdForAnswer(session, answer) === String(teamId) ? total + (Number(answer.points) || 0) : total;
  }, 0);
}
function hcascTeamAnswers(session, teamId){
  return toArray(session?.answerLog).filter(answer => hcascTeamIdForAnswer(session, answer) === String(teamId));
}
function hcascTeamLabel(session, teamId){
  return (session?.teams || []).find(team => String(team.id) === String(teamId))?.name || 'Team';
}
function hcascTeamOptions(session){
  return (session?.teams || []).filter(team => (team.playerMembers || []).length).map(team =>
    `<option value="${hcascEscape(team.id)}">${hcascEscape(team.name)}</option>`).join('');
}
function hcascPlayerOptions(session, teamId){
  const team = (session?.teams || []).find(item => String(item.id) === String(teamId));
  return (team?.playerMembers || []).map(player =>
    `<option value="${hcascEscape(player)}">${hcascEscape(getDisplayName(player, Object.keys(session.players || {})))}</option>`).join('');
}
function hcascSelectionChanged(kind, value){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  if (kind === 'team'){
    session.activeTeamId = value || null;
    const team = (session.teams || []).find(item => String(item.id) === String(value));
    session.activePlayer = team?.playerMembers?.[0] || null;
  } else if (kind === 'player') session.activePlayer = value || null;
  saveAllData();
  hcascRenderBoard();
}
function hcascSetRound(round){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  const next = hcascRoundNumber(round);
  session.currentRound = next;
  session.currentPhase = next === 4 ? 'Ultimate' : 'Face-Off';
  session.clockRunning = false;
  session.clockStartedAt = 0;
  session.clockRemainingSeconds = HCASC_ROUNDS[next].seconds;
  session.activeQuestionId = null;
  session.activeCategory = session.rounds[next].categories[0];
  if (next === 4){
    if (!session.ultimateTeamId){
      const teams = (session.teams || []).filter(t => (t.playerMembers || []).length);
      session.ultimateTeamId = teams[0]?.id || null;
    }
    const chosen = Object.entries(session.ultimateCategoriesUsed).find(([, owner]) => String(owner) === String(session.ultimateTeamId));
    session.activeCategory = chosen?.[0] || session.rounds[4].categories.find(category => !session.ultimateCategoriesUsed[category]) || session.rounds[4].categories[0];
  }
  saveAllData();
  hcascRenderBoard();
}
function hcascSelectCategory(category){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  if (session.currentRound === 4){
    const usedBy = session.ultimateCategoriesUsed[category];
    if (usedBy && String(usedBy) !== String(session.ultimateTeamId)){
      showToast('That Ultimate Challenge category has already been used.', 'warn');
      return;
    }
    if (session.ultimateTeamId) session.ultimateCategoriesUsed[category] = session.ultimateTeamId;
  }
  session.activeCategory = category;
  saveAllData();
  hcascRenderBoard();
}
function hcascRenameCategory(index){
  const session = getCurrentSession();
  if (!session) return;
  const round = hcascRoundNumber(session.currentRound);
  const old = session.rounds[round].categories[index] || 'Category';
  const next = window.prompt('Category name for this round:', old);
  if (next == null || !next.trim()) return;
  session.rounds[round].categories[index] = next.trim().slice(0, 80);
  if (session.activeCategory === old) session.activeCategory = session.rounds[round].categories[index];
  saveAllData();
  hcascRenderBoard();
}
function hcascClockSeconds(){
  const session = getCurrentSession();
  if (!session) return 0;
  hcascEnsureSession(session);
  if (!session.clockRunning || !session.clockStartedAt) return Math.max(0, session.clockRemainingSeconds);
  const elapsed = Math.floor((Date.now() - session.clockStartedAt) / 1000);
  return Math.max(0, session.clockRemainingSeconds - elapsed);
}
function hcascFormatClock(seconds){
  const safe = Math.max(0, Number(seconds) || 0);
  return String(Math.floor(safe / 60)).padStart(2, '0') + ':' + String(safe % 60).padStart(2, '0');
}
function hcascPersistClock(){
  const session = getCurrentSession();
  if (!session) return;
  if (session.clockRunning){
    const current = hcascClockSeconds();
    session.clockRemainingSeconds = current;
    session.clockStartedAt = Date.now();
    if (current <= 0) session.clockRunning = false;
  }
  saveAllData();
}
function hcascToggleClock(){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  if (session.clockRunning){
    session.clockRemainingSeconds = hcascClockSeconds();
    session.clockRunning = false;
    session.clockStartedAt = 0;
  } else {
    if (hcascClockSeconds() <= 0) session.clockRemainingSeconds = HCASC_ROUNDS[session.currentRound].seconds;
    session.clockStartedAt = Date.now();
    session.clockRunning = true;
  }
  saveAllData();
  hcascRenderBoard();
}
function hcascResetClock(){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  session.clockRunning = false;
  session.clockStartedAt = 0;
  session.clockRemainingSeconds = HCASC_ROUNDS[session.currentRound].seconds;
  saveAllData();
  hcascRenderBoard();
}
function hcascNextQuestion(){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  session.questionNumber += 1;
  session.activeQuestionId = 'hcasc-q-' + Date.now() + '-' + session.questionNumber;
  if (session.currentRound < 4) session.rounds[session.currentRound].questions += 1;
  saveAllData();
  hcascRenderBoard();
}
function hcascSetUltimateTeam(teamId){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  const previousTeamId = session.ultimateTeamId;
  if (previousTeamId && String(previousTeamId) !== String(teamId)){
    session.ultimateClocks[previousTeamId] = { remaining:hcascClockSeconds(), running:false };
  }
  session.ultimateTeamId = teamId || null;
  session.activeTeamId = teamId || null;
  const savedClock = session.ultimateClocks[teamId];
  session.clockRunning = false;
  session.clockStartedAt = 0;
  session.clockRemainingSeconds = savedClock ? Math.max(0, Number(savedClock.remaining) || 0) : ((session.ultimateCounts[teamId] || 0) >= 10 ? 0 : 60);
  const team = (session.teams || []).find(item => String(item.id) === String(teamId));
  session.activePlayer = team?.playerMembers?.[0] || null;
  if (session.currentRound === 4){
    const chosen = Object.entries(session.ultimateCategoriesUsed).find(([, owner]) => String(owner) === String(teamId));
    if (chosen) session.activeCategory = chosen[0];
    else session.activeCategory = session.rounds[4].categories.find(category => !session.ultimateCategoriesUsed[category]) || session.rounds[4].categories[0];
  }
  saveAllData();
  hcascRenderBoard();
}
function hcascEventMetadata(session, player, pointType){
  hcascEnsureSession(session);
  const team = hcascTeamForPlayer(session, player);
  return {
    format: HCASC_FORMAT,
    round: session.currentRound,
    phase: session.currentRound === 4 ? 'Ultimate' : (pointType === 'Bonus' ? 'Bonus' : 'Face-Off'),
    teamId: team?.id || null,
    questionId: session.activeQuestionId || null,
    questionNumber: session.questionNumber || 0,
    hcascCategory: session.activeCategory || '—'
  };
}
// Used by the legacy Record Answer surface so entries from either surface have
// the same audit fields.  It intentionally does not change the selected event.
function hcascGetEventMeta(player, pointType){
  const session = getCurrentSession();
  return session ? hcascEventMetadata(session, player, pointType) : {};
}

function hcascAppendAnswer(session, answer){
  hcascEnsureSession(session);
  session.answerLog = toArray(session.answerLog);
  session.answerLog.push(answer);
  if (!session.players) session.players = {};
  if (answer.player && !String(answer.player).startsWith('— ') && isPlayerPerformanceAnswer(answer)){
    const player = session.players[answer.player] || (session.players[answer.player] = {name:answer.player, points:0, answers:[]});
    player.answers = toArray(player.answers);
    player.answers.push(answer);
    player.points = player.answers.filter(isPlayerPerformanceAnswer).reduce((sum, item) => sum + (Number(item.points) || 0), 0);
  }
  if (answer.pointType === 'Bonus') session.teamBonusPoints = (session.teamBonusPoints || 0) + (Number(answer.points) || 0);
  if (answer.round && session.rounds[answer.round]){
    const round = session.rounds[answer.round];
    if (answer.pointType === 'Bonus') round.bonusPoints += Number(answer.points) || 0;
    if (answer.phase === 'Face-Off' && answer.points > 0) round.faceOffPoints += Number(answer.points) || 0;
  }
}
function hcascRecordEvent(kind){
  const session = getCurrentSession();
  if (!session) return;
  hcascEnsureSession(session);
  const teams = (session.teams || []).filter(item => (item.playerMembers || []).length);
  const teamId = session.currentRound === 4 ? (session.ultimateTeamId || teams[0]?.id) : (session.activeTeamId || teams[0]?.id);
  const team = teams.find(item => String(item.id) === String(teamId));
  if (!team){ showToast('Set up two teams before recording HCASC scoring.', 'warn'); return; }
  const player = session.activePlayer || team.playerMembers?.[0] || null;
  const isUltimate = session.currentRound === 4;
  const event = {
    faceOffCorrect:{ pointType:'Toss-up', label:'Face-Off', points:HCASC_POINTS.faceOff, phase:'Face-Off' },
    faceOffIncorrect:{ pointType:'Neg', label:'Face-Off incorrect', points:HCASC_POINTS.incorrect, phase:'Face-Off' },
    turnoverCorrect:{ pointType:'Toss-up', label:'Turnover Face-Off', points:HCASC_POINTS.faceOff, phase:'Face-Off', turnover:true },
    bonus:{ pointType:'Bonus', label:'Bonus', points:HCASC_POINTS.bonus, phase:'Bonus' },
    ultimateCorrect:{ pointType:'Ultimate', label:'Ultimate correct', points:HCASC_POINTS.ultimate, phase:'Ultimate' },
    ultimateMiss:{ pointType:'Miss', label:'Ultimate pass/miss', points:HCASC_POINTS.incorrect, phase:'Ultimate' }
  }[kind];
  if (!event) return;
  if (isUltimate && event.phase !== 'Ultimate') { showToast('Face-Off scoring is not available during the Ultimate Challenge.', 'warn'); return; }
  if (!isUltimate && event.phase === 'Ultimate') { showToast('Switch to the Ultimate round before logging Ultimate answers.', 'warn'); return; }
  if (event.phase === 'Bonus' && !session.activeQuestionId){ showToast('Start a Face-Off question before recording its Bonus.', 'warn'); return; }
  if (!session.activeQuestionId){
    session.questionNumber += 1;
    session.activeQuestionId = 'hcasc-q-' + Date.now() + '-' + session.questionNumber;
    if (!isUltimate) session.rounds[session.currentRound].questions += 1;
  }
  if (event.phase === 'Bonus'){
    const questionAnswers = toArray(session.answerLog).filter(answer => answer.questionId === session.activeQuestionId);
    const earnedBonus = questionAnswers.some(answer => answer.teamId === team.id && answer.phase === 'Face-Off' && Number(answer.points) === HCASC_POINTS.faceOff);
    const alreadyLogged = questionAnswers.some(answer => answer.teamId === team.id && answer.pointType === 'Bonus');
    if (!earnedBonus || alreadyLogged){ showToast('A Bonus is available only after that team answers its Face-Off correctly.', 'warn'); return; }
  }
  if (isUltimate && (session.ultimateCounts[team.id] || 0) >= 10){
    showToast(`${team.name} has used all 10 Ultimate Challenge questions.`, 'warn');
    return;
  }
  if (!isUltimate && event.phase === 'Face-Off'){
    const assigned = session.roundPlayers?.[session.currentRound]?.[team.id];
    if (assigned && assigned !== player){
      showToast(`${team.name} is represented by ${assigned} for this Face-Off round. Players may change between rounds, not during a game.`, 'warn');
      return;
    }
  }
  const now = new Date().toISOString();
  const answer = {
    id:'hcasc-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7),
    player:event.phase === 'Bonus' ? `— ${team.name} Bonus —` : (player || `— ${team.name} —`),
    pointType:event.pointType,
    category:session.activeCategory || '—',
    points:event.points,
    timestamp:now,
    format:HCASC_FORMAT,
    round:session.currentRound,
    phase:event.phase,
    teamId:team.id,
    questionId:session.activeQuestionId || null,
    questionNumber:session.questionNumber || 0,
    turnover:!!event.turnover,
    ultimateTeamId:isUltimate ? team.id : null
  };
  const apply = current =>{
    hcascEnsureSession(current);
    current.currentRound = session.currentRound;
    current.currentPhase = session.currentPhase;
    current.activeQuestionId = answer.questionId;
    current.questionNumber = answer.questionNumber;
    current.activeCategory = answer.category;
    current.activeTeamId = session.activeTeamId || team.id;
    if (isUltimate) current.ultimateTeamId = team.id;
    if (!isUltimate && event.phase === 'Face-Off'){
      current.roundPlayers[answer.round] = current.roundPlayers[answer.round] || {};
      current.roundPlayers[answer.round][team.id] = player;
    }
    if (isUltimate) current.ultimateCounts[team.id] = (current.ultimateCounts[team.id] || 0) + 1;
    hcascAppendAnswer(current, answer);
  };
  updateSessionAtomic(session.id, apply);
  withWriteLock(session.id, () => { const current = getCurrentSession(); if (current) apply(current); });
  showRecordToast(`${team.name} — ${event.label} (${event.points > 0 ? '+' : ''}${event.points} pts)`, event.points > 0 ? 'pts' : 'miss');
  renderAll();
}
function hcascScoreSummary(session){
  const teams = (session?.teams || []).filter(team => (team.playerMembers || []).length);
  return teams.map(team =>{
    const answers = hcascTeamAnswers(session, team.id);
    return {
      id:team.id, name:team.name, score:answers.reduce((sum, answer) => sum + (Number(answer.points) || 0), 0),
      faceOff:answers.filter(answer => answer.phase === 'Face-Off' && answer.points > 0).reduce((sum, answer) => sum + answer.points, 0),
      bonuses:answers.filter(answer => answer.pointType === 'Bonus').reduce((sum, answer) => sum + (Number(answer.points) || 0), 0),
      ultimate:answers.filter(answer => answer.phase === 'Ultimate').reduce((sum, answer) => sum + (Number(answer.points) || 0), 0),
      members:team.playerMembers || []
    };
  });
}
function hcascRenderBoard(){
  const board = $('hcascBoard');
  const session = getCurrentSession();
  if (!board || !session) return;
  hcascEnsureSession(session);
  const round = session.currentRound;
  const roundInfo = HCASC_ROUNDS[round];
  const teams = (session.teams || []).filter(team => (team.playerMembers || []).length);
  const summaries = hcascScoreSummary(session);
  const selectedTeam = session.activeTeamId || session.ultimateTeamId || teams[0]?.id || '';
  const selectedTeamObj = teams.find(team => String(team.id) === String(selectedTeam)) || teams[0];
  const assignedPlayer = round !== 4 ? session.roundPlayers?.[round]?.[selectedTeamObj?.id] : null;
  const selectedPlayer = assignedPlayer || session.activePlayer || selectedTeamObj?.playerMembers?.[0] || '';
  const categories = session.rounds[round].categories;
  const seconds = hcascClockSeconds();
  const clockClass = seconds <= 10 ? ' is-critical' : seconds <= 30 ? ' is-warning' : '';
  const scoreCards = summaries.length ? summaries.map((item, index) => `
    <article class="hcasc-score-card ${index === 0 ? 'hcasc-score-card-a' : 'hcasc-score-card-b'}">
      <div class="hcasc-team-mark">${index === 0 ? 'A' : 'B'}</div>
      <div class="hcasc-team-copy"><span>${hcascEscape(item.name)}</span><small>${item.faceOff} Face-Off · ${item.bonuses} Bonus · ${item.ultimate} Ultimate</small></div>
      <strong>${item.score}</strong>
    </article>`).join('') : `<div class="hcasc-empty-state">Add two teams with players in Setup to start an official HCASC match.</div>`;
  const teamOptions = hcascTeamOptions(session);
  const playerOptions = selectedTeamObj ? hcascPlayerOptions(session, selectedTeamObj.id) : '';
  const teamSelect = round === 4 ? `
    <label class="hcasc-field"><span>Ultimate team</span><select onchange="hcascSetUltimateTeam(this.value)">${teamOptions || '<option>No teams yet</option>'}</select></label>` : `
    <label class="hcasc-field"><span>Scoring team</span><select onchange="hcascSelectionChanged('team', this.value)">${teamOptions || '<option>No teams yet</option>'}</select></label>`;
  board.innerHTML = `
    <div class="hcasc-board-topline"><div><span class="hcasc-eyebrow">FAMU HCASC · OFFICIAL FORMAT</span><h2>Match scoreboard</h2><p>Three Face-Off rounds, team Bonuses, then the 60-second Ultimate Challenge.</p></div><div class="hcasc-rule-chip">No neg penalties · FO 10 · Bonus 20 · Ultimate 25</div></div>
    ${teams.length !== 2 ? `<div class="hcasc-format-warning">Official HCASC matches use two teams of three active players. This practice session currently has ${teams.length} configured team${teams.length === 1 ? '' : 's'}.</div>` : teams.some(team => (team.playerMembers || []).length !== 3) ? '<div class="hcasc-format-warning">Official matches use three players per team; use the fourth roster player as a between-game substitute.</div>' : ''}
    <div class="hcasc-score-grid">${scoreCards}</div>
    <div class="hcasc-round-strip"><div class="hcasc-round-tabs">${Object.entries(HCASC_ROUNDS).map(([key, info]) => `<button class="hcasc-round-tab ${Number(key) === round ? 'active' : ''}" onclick="hcascSetRound(${key})"><b>${info.short}</b><span>${info.label.replace('Face-Off ', '')}</span></button>`).join('')}</div><div class="hcasc-clock${clockClass}"><span class="hcasc-clock-label">${round === 4 ? 'TEAM CLOCK' : 'ROUND CLOCK'}</span><strong id="hcascClock">${hcascFormatClock(seconds)}</strong><button onclick="hcascToggleClock()">${session.clockRunning ? 'Pause' : 'Start'}</button><button class="hcasc-clock-reset" onclick="hcascResetClock()" title="Reset clock">↺</button></div></div>
    <div class="hcasc-round-note"><span><b>${roundInfo.label}</b> · ${round === 4 ? '60 seconds / team · ' + (session.ultimateCounts[selectedTeamObj?.id] || 0) + '/10 questions · 25 points each' : '4 minutes · three Face-Off / Bonus pairs per category'}</span><span>Question ${session.questionNumber || 0}${session.activeCategory ? ' · ' + hcascEscape(session.activeCategory) : ''}</span></div>
    <div class="hcasc-category-row"><span class="hcasc-category-label">${round === 4 ? 'Choose one category' : 'Category board'}</span>${categories.map((category, index) => { const usedBy = session.ultimateCategoriesUsed[category]; const locked = round === 4 && usedBy && String(usedBy) !== String(session.ultimateTeamId); return `<button class="hcasc-category ${session.activeCategory === category ? 'active' : ''}${locked ? ' locked' : ''}" ${locked ? 'disabled' : ''} onclick="hcascSelectCategory(decodeURIComponent('${encodeURIComponent(category)}'))" ondblclick="hcascRenameCategory(${index})"><span>${hcascEscape(category)}</span><small>${locked ? 'Already used' : 'Double-click to edit'}</small></button>`; }).join('')}</div>
    <div class="hcasc-log-panel"><div class="hcasc-log-heading"><div><span class="hcasc-eyebrow">LIVE SCORING</span><h3>Log the next ruling</h3></div><button class="hcasc-next-question" onclick="hcascNextQuestion()">${round === 4 ? '+ Next Ultimate question' : '+ New Face-Off question'}</button></div><div class="hcasc-controls">${teamSelect}<label class="hcasc-field"><span>${assignedPlayer ? 'Face-Off player (locked)' : 'Player / responder'}</span><select ${assignedPlayer ? 'disabled' : ''} onchange="hcascSelectionChanged('player', this.value)">${playerOptions || '<option>No players yet</option>'}</select></label></div><div class="hcasc-action-grid">${round === 4 ? `<button class="hcasc-action hcasc-action-primary" onclick="hcascRecordEvent('ultimateCorrect')"><b>+25</b><span>Ultimate correct</span></button><button class="hcasc-action hcasc-action-neutral" onclick="hcascRecordEvent('ultimateMiss')"><b>0</b><span>Pass / incorrect</span></button>` : `<button class="hcasc-action hcasc-action-primary" onclick="hcascRecordEvent('faceOffCorrect')"><b>+10</b><span>Face-Off correct</span></button><button class="hcasc-action hcasc-action-bonus" onclick="hcascRecordEvent('bonus')"><b>+20</b><span>Team Bonus</span></button><button class="hcasc-action hcasc-action-neutral" onclick="hcascRecordEvent('faceOffIncorrect')"><b>0</b><span>Face-Off incorrect</span></button><button class="hcasc-action hcasc-action-turnover" onclick="hcascRecordEvent('turnoverCorrect')"><b>+10</b><span>Turnover correct</span></button>`}</div><p class="hcasc-audit-note">Every ruling stores its round, category, team, responder, question number, and timestamp in the answer log.</p></div>`;
  const teamSelectEl = board.querySelector('select');
  if (teamSelectEl) teamSelectEl.value = selectedTeam;
  const selects = board.querySelectorAll('select');
  if (selects[1]) selects[1].value = selectedPlayer;
}
function hcascTick(){
  const session = getCurrentSession();
  const clock = $('hcascClock');
  if (!session || !clock) return;
  const seconds = hcascClockSeconds();
  clock.textContent = hcascFormatClock(seconds);
  clock.closest('.hcasc-clock')?.classList.toggle('is-critical', seconds <= 10);
  clock.closest('.hcasc-clock')?.classList.toggle('is-warning', seconds > 10 && seconds <= 30);
  if (session.clockRunning && seconds <= 0){
    session.clockRunning = false;
    session.clockStartedAt = 0;
    session.clockRemainingSeconds = 0;
    saveAllData();
    hcascRenderBoard();
    showToast('Time!', 'warn');
  }
}

// Add the board after the existing source-defined tracker has rendered, so
// existing sessions and all existing analytics continue to work unchanged.
const _hcascBaseRenderAll = renderAll;
renderAll = function(){
  _hcascBaseRenderAll();
  const session = getCurrentSession();
  if (session) hcascEnsureSession(session);
  hcascRenderBoard();
};

if (typeof window !== 'undefined'){
  window.setInterval(hcascTick, 500);
  window.addEventListener('beforeunload', hcascPersistClock);
}
