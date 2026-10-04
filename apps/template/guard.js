#!/usr/bin/env node
/**
 * Branding firewall for the QB Tracker template.
 *
 * This template exists so other schools and organizations can fork the quiz
 * bowl app WITHOUT any HSE affiliation and WITHOUT any possibility of
 * touching the HSE team's data. That guarantee is only as strong as the
 * build, so `npm run check` runs this guard on every push:
 *
 *   - the built index.html (and everything under src/, plus the PWA
 *     manifest and rules file) must contain NO HSE identifiers: app names,
 *     repo URLs, the HSE Firebase project / API key, export filenames, or
 *     the legacy admin reset password;
 *   - this repository's template must ship with `firebaseConfig = null`
 *     (offline mode). A fork that connects its OWN project appends the
 *     `// fork-configured` marker to that line, which opts out of the
 *     null-config check — the identifier scans above still run either way.
 *
 * If this guard fails, an HSE-specific value leaked into the template —
 * remove it before committing. Internal CSS paint-slot names that merely
 * contain "hse" (e.g. `--hse-blue`) are legacy identifiers shared with the
 * upstream app so features can be ported by copying modules; they are
 * invisible to users and are intentionally allowed.
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = __dirname;

// (pattern, why-it-must-never-appear)
const FORBIDDEN = [
  [/HSE Quiz Bowl/, 'HSE app name'],
  [/HSE QB/, 'HSE short name'],
  [/HSE Team/, 'HSE analytics heading'],
  [/hse-quiz-bowl/, 'HSE Firebase project / filenames'],
  [/hse-qb/, 'HSE export filenames'],
  [/ajani190819-ops/, 'HSE GitHub org/repo'],
  [/AIzaSyCRkK3IpRXeQC9JH73iC0tC-mjq5nulaAo/, 'HSE Firebase API key'],
  [/Neg 5/, 'legacy HSE admin reset password'],
];

// Files scanned relative to the app root (the built artifact is the most
// important — it is what actually ships).
const TARGETS = [
  'index.html',
  'manifest.webmanifest',
  'package.json',
  'firebase.database.rules.json',
  'src/index.template.html',
  'src/manifest.json',
  'src/css/core.css',
  'src/css/theme.css',
];
for (const f of fs.readdirSync(path.join(root, 'src', 'js'))) {
  TARGETS.push('src/js/' + f);
}

function fail(msg) { console.error(`\u2716 ${msg}`); process.exit(1); }

let violations = 0;
for (const rel of TARGETS) {
  const p = path.join(root, rel);
  if (!fs.existsSync(p)) fail(`expected file is missing: ${rel}`);
  const content = fs.readFileSync(p, 'utf8');
  for (const [pattern, why] of FORBIDDEN) {
    const m = content.match(pattern);
    if (m) {
      violations++;
      console.error(`\u2716 ${rel}: contains ${why} (match: ${JSON.stringify(m[0])})`);
    }
  }
}

// Offline-mode invariant for THIS repository's template: no Firebase
// project wired in. Forks mark their own config with `// fork-configured`.
const constants = fs.readFileSync(path.join(root, 'src', 'js', '01-constants.js'), 'utf8');
const cfgLine = constants.match(/^const firebaseConfig = .*$/m);
if (!cfgLine) fail('src/js/01-constants.js: `const firebaseConfig = …` line not found');
if (!/fork-configured/.test(cfgLine[0]) && !/\bnull\b/.test(cfgLine[0].split('//')[0])) {
  fail('template firebaseConfig must stay `null` — forks that connect their own project append `// fork-configured` to that line');
}

if (violations) fail(`${violations} HSE identifier(s) leaked into the template — remove them and rebuild`);
console.log('\u2714 branding guard passed: no HSE identifiers in the template build');
