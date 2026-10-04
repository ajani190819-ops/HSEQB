#!/usr/bin/env node
/**
 * Rebuilds index.html byte-for-byte from src/.
 *
 * src/manifest.json lists the source file (the template with unique
 * @@MARKER@@ tokens) and, for each marker, the ordered list of src files
 * whose concatenation (no separator) replaces the token. Because every
 * module file holds an exact byte slice of the original, the rebuilt
 * index.html must be byte-identical to the committed one.
 *
 * Usage: node build.js   (or: npm run build)
 *
 * After editing anything under src/, run the build and commit BOTH the
 * src/ change and the regenerated index.html. CI-style check:
 *   node build.js && git diff --exit-code index.html
 */
'use strict';
const fs = require('fs');
const path = require('path');

const root = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'src/manifest.json'), 'utf8'));

let out = fs.readFileSync(path.join(root, manifest.template), 'utf8');

for (const [marker, files] of Object.entries(manifest.blocks)) {
  const parts = files.map((f) => {
    const p = path.join(root, f);
    if (!fs.existsSync(p)) throw new Error(`missing source file: ${f}`);
    return fs.readFileSync(p, 'utf8');
  });
  const joined = parts.join(manifest.joinSeparator ?? '');
  const count = out.split(marker).length - 1;
  if (count !== 1) throw new Error(`marker ${marker} appears ${count} times (expected 1)`);
  out = out.split(marker).join(joined);
}

const outPath = path.join(root, manifest.output);
fs.writeFileSync(outPath, out);
console.log(`Built ${manifest.output}: ${Buffer.byteLength(out)} bytes from ${Object.values(manifest.blocks).flat().length} source files.`);
