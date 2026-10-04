#!/usr/bin/env node
/**
 * Automatic version bump for the HSEQB single-file app.
 *
 * The authoritative version is the `VERSION` constant in
 * src/js/01-constants.js; package.json and the rebuilt index.html mirror it.
 * All three must always agree — this script updates (or verifies) them as a
 * unit so they can never drift.
 *
 * Modes:
 *   node bump.js [patch|minor|major]
 *       Increment the semver (default: patch), rewrite the VERSION constant
 *       and package.json, then rebuild index.html via build.js so the
 *       committed deployable artifact carries the new version.
 *
 *   node bump.js --check
 *       Gate used by `npm run check` (run before pushing/merging a release):
 *         1. package.json version === VERSION constant in 01-constants.js
 *         2. index.html is a byte-exact rebuild of src/ (rebuilds in place
 *            and compares — fails when the committed index.html is stale)
 *         3. the rebuilt index.html embeds the same VERSION
 *       Exits non-zero with an ✖ message on any drift.
 *
 * Shipping a release: run `npm run bump` (patch/minor/major), then `npm run
 * check`, then commit/push. Versioning is manual-via-command here — there is
 * no CI bot that bumps automatically.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = __dirname;
const CONSTANTS = path.join(root, 'src', 'js', '01-constants.js');
const PACKAGE = path.join(root, 'package.json');
const BUILD = path.join(root, 'build.js');
const INDEX = path.join(root, 'index.html');
const SEMVER = /^(\d+)\.(\d+)\.(\d+)$/;

function read(p) { return fs.readFileSync(p, 'utf8'); }
function fail(msg) { console.error(`\u2716 ${msg}`); process.exit(1); }

// --- VERSION constant in src/js/01-constants.js (the source of truth) -----

function readConstantVersion() {
  const src = read(CONSTANTS);
  const occurrences = src.match(/^const VERSION = '\d+\.\d+\.\d+';/gm) || [];
  if (occurrences.length !== 1) {
    fail(`expected exactly one \`const VERSION = 'x.y.z';\` in ${path.relative(root, CONSTANTS)}, found ${occurrences.length}`);
  }
  const version = occurrences[0].match(/\d+\.\d+\.\d+/)[0];
  return { file: src, version };
}

// Rewrite the whole VERSION line (comment included) so the "auto-managed by
// bump.js" marker is preserved; only the numeric version changes.
function writeConstantVersion(newVersion) {
  const src = read(CONSTANTS);
  let count = 0;
  const out = src.replace(/^const VERSION = '\d+\.\d+\.\d+';.*$/m, () => {
    count++;
    return `const VERSION = '${newVersion}'; // auto-managed by bump.js`;
  });
  if (count !== 1) fail(`VERSION constant not found in ${path.relative(root, CONSTANTS)}`);
  fs.writeFileSync(CONSTANTS, out);
}

// --- package.json mirror ---------------------------------------------------

function readPackageVersion() {
  let pkg;
  try { pkg = JSON.parse(read(PACKAGE)); }
  catch (e) { fail(`package.json is not valid JSON: ${e.message}`); }
  if (!pkg.version || !SEMVER.test(pkg.version)) {
    fail(`package.json version "${pkg.version}" is not x.y.z semver`);
  }
  return pkg.version;
}

function writePackageVersion(newVersion) {
  const pkg = JSON.parse(read(PACKAGE));
  pkg.version = newVersion;
  fs.writeFileSync(PACKAGE, JSON.stringify(pkg, null, 2) + '\n');
}

// --- semver + rebuild ------------------------------------------------------

function bumpVersion(version, type) {
  const m = version.match(SEMVER);
  if (!m) fail(`current version "${version}" is not x.y.z semver`);
  let major = Number(m[1]);
  let minor = Number(m[2]);
  let patch = Number(m[3]);
  if (type === 'major') { major++; minor = 0; patch = 0; }
  else if (type === 'minor') { minor++; patch = 0; }
  else { patch++; }
  return `${major}.${minor}.${patch}`;
}

function rebuildIndex() {
  execFileSync(process.execPath, [BUILD], { cwd: root, stdio: 'inherit' });
}

// --- modes -----------------------------------------------------------------

function check() {
  const constVer = readConstantVersion();
  const pkgVer = readPackageVersion();
  if (pkgVer !== constVer.version) {
    fail(`version drift: package.json is ${pkgVer} but src/js/01-constants.js VERSION is ${constVer.version}`);
  }

  // index.html must be the exact current build of src/. Snapshot it, rebuild
  // (build.js writes byte-for-byte), and require an identical result.
  const before = fs.existsSync(INDEX) ? read(INDEX) : null;
  rebuildIndex();
  const after = read(INDEX);
  if (before !== after) {
    fail('index.html is stale — run `npm run build` (or `npm run bump`) and commit the rebuilt index.html');
  }

  const inHtml = after.match(/^const VERSION = '(\d+\.\d+\.\d+)';/m);
  if (!inHtml || inHtml[1] !== constVer.version) {
    fail(`rebuilt index.html does not embed VERSION = '${constVer.version}'`);
  }

  console.log(`\u2714 version check passed: package.json, src/js/01-constants.js, and index.html all at v${constVer.version}; index.html is a clean rebuild`);
}

function bump(type) {
  const oldVersion = readConstantVersion().version;
  const next = bumpVersion(oldVersion, type);
  writeConstantVersion(next);
  writePackageVersion(next);
  rebuildIndex();
  console.log(`\u2714 bumped v${oldVersion} \u2192 v${next} (${type})`);
  console.log('  updated: src/js/01-constants.js, package.json, index.html');
}

const arg = process.argv[2];
if (arg === '--check' || arg === 'check') {
  check();
} else {
  const type = arg || 'patch';
  if (!['patch', 'minor', 'major'].includes(type)) {
    fail(`unknown bump type "${type}" — use patch, minor, or major`);
  }
  bump(type);
}
