
/* Apply the cached choice before the sign-in form paints, including on a cold load. */
(function () {
  try {
    var saved = localStorage.getItem('themeMode');
    var legacyDark = localStorage.getItem('darkMode') === 'true';
    var mode = ['light', 'dark', 'device'].indexOf(saved) >= 0 ? saved : (legacyDark ? 'dark' : 'device');
    var dark = mode === 'dark' || (mode === 'device' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.classList.toggle('dark-mode', !!dark);
    document.documentElement.dataset.theme = mode;
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
  } catch (e) { /* Storage can be unavailable in private browsing; light remains the fallback. */ }
}());
