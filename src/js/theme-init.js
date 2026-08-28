/* Apply the cached choice before the sign-in form paints, including on a cold load. */
(function () {
  try {
    var saved = localStorage.getItem('themeMode');
    var legacyDark = localStorage.getItem('darkMode') === 'true';
    var mode = ['light', 'dark', 'device'].indexOf(saved) >= 0 ? saved : (legacyDark ? 'dark' : 'device');
    var dark = mode === 'dark' || (mode === 'device' && window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    var rawStyle = localStorage.getItem('accentStyle');
    var accentStyle = rawStyle === 'gradient' ? 'gradient' : 'stripes';
    var storedTheme = localStorage.getItem('colorTheme');
    var themes = {
      tricolor:{ primary:'#003da5', secondary:'#c8102e', tertiary:'#ffffff', accent:'#c8102e' },
      royal:{ primary:'#0b41a8', secondary:'#002b7f', tertiary:'#ffffff', accent:'#002b7f' },
      indigo:{ primary:'#667eea', secondary:'#764ba2' },
      teal:{ primary:'#11998e', secondary:'#38ef7d' },
      crimson:{ primary:'#dc3545', secondary:'#8e1b26' },
      purple:{ primary:'#764ba2', secondary:'#3f2a63' },
      sunset:{ primary:'#f39c12', secondary:'#e0533d' },
      slate:{ primary:'#4a5568', secondary:'#2d3748' },
      forest:{ primary:'#2f855a', secondary:'#1c4532' }
    };
    function isHex(v){ return /^#[0-9a-f]{6}$/i.test(v || ''); }
    function shadeHex(hex, amount){
      var n = parseInt(hex.slice(1), 16);
      var mix = function (c) { return Math.round(amount < 0 ? c * (1 + amount) : c + (255 - c) * amount); };
      var r = mix((n >> 16) & 255), g = mix((n >> 8) & 255), b = mix(n & 255);
      return '#' + ((1 << 24) + (r << 16) + (g << 8) + b).toString(16).slice(1);
    }
    function mixHex(a, b, t){
      var pa = parseInt(a.slice(1), 16), pb = parseInt(b.slice(1), 16);
      var ch = function (v, s) { return (v >> s) & 255; };
      var mix = function (s) { return Math.round(ch(pa, s) + (ch(pb, s) - ch(pa, s)) * t); };
      return '#' + ((1 << 24) + (mix(16) << 16) + (mix(8) << 8) + mix(0)).toString(16).slice(1);
    }
    var themeId = themes[storedTheme] ? storedTheme : 'tricolor';
    var palette = themes[themeId];
    if (storedTheme === 'custom'){
      var cp = localStorage.getItem('customPrimary');
      var cs = localStorage.getItem('customSecondary');
      var ca = localStorage.getItem('customAccent');
      if (isHex(cp)){
        themeId = 'custom';
        palette = {
          primary:cp.toLowerCase(),
          secondary:isHex(cs) ? cs.toLowerCase() : '#c8102e',
          tertiary:'#ffffff',
          accent:isHex(ca) ? ca.toLowerCase() : (isHex(cs) ? cs.toLowerCase() : '#c8102e')
        };
      }
    }
    var blue = palette.primary;
    var accent = palette.accent || palette.secondary || shadeHex(blue, -0.45);
    var white = dark ? '#f4f6fb' : (palette.tertiary || '#ffffff');
    var secondary = accentStyle === 'gradient'
      ? (palette.secondary || accent)
      : mixHex(blue, dark ? '#dfe6f5' : '#ffffff', dark ? 0.30 : 0.32);
    document.documentElement.classList.toggle('dark-mode', !!dark);
    document.documentElement.dataset.theme = mode;
    document.documentElement.dataset.accentStyle = accentStyle;
    document.documentElement.dataset.colorTheme = themeId;
    document.documentElement.style.colorScheme = dark ? 'dark' : 'light';
    document.documentElement.style.setProperty('--primary', blue);
    document.documentElement.style.setProperty('--primary-light', shadeHex(blue, dark ? 0.24 : 0.28));
    document.documentElement.style.setProperty('--primary-dark', shadeHex(blue, -0.28));
    document.documentElement.style.setProperty('--secondary', secondary);
    document.documentElement.style.setProperty('--accent-line', accent);
    document.documentElement.style.setProperty('--tertiary', white);
    document.documentElement.style.setProperty('--hse-blue', blue);
    document.documentElement.style.setProperty('--hse-red', accent);
    document.documentElement.style.setProperty('--hse-white', white);
    var themeMeta = document.querySelector('meta[name="theme-color"]');
    if (themeMeta) themeMeta.setAttribute('content', blue);
  } catch (e) { /* Storage can be unavailable in private browsing; tricolor pinstripe remains the fallback. */ }
}());
