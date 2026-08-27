const state={sessions:{},currentSessionId:null,selectedPlayer:null,selectedPointType:null,selectedCategory:null,categories:[]};
let firebaseUnsubscribe=null, playersUnsubscribe=null;
var analyticsOpen=false, currentAnalyticsTab='overview';
var userIdentitiesCache ={};
var playerSortKey = 'points';
var scoreBandRegistry = null; // Set by renderAnalyticsCharts; read by openScoreBand.
var lowDataPanelCollapsed = localStorage.getItem('lowDataPanelCollapsed') !== 'false';
var formulasPanelCollapsed  = localStorage.getItem('formulasPanelCollapsed')  !== 'false';
var skillThresholdPct = 40;
var catColors ={'Literature':'#3b82f6','Science':'#11998e','History':'#f97316','Social Studies':'#eab308','Pop Culture':'#a855f7','Fine Arts':'#06b6d4'};
var expandedPlayerCards = new Set();
var expandedTeamCards = new Set();
var manuallyIncluded = new Set();
var playerTHeardOverrides ={};
var sessionInvalidFlags ={};
