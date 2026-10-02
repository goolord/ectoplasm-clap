// Measures the processor's behaviour across the F×K plane with offline
// `cmaj render` runs and writes tools/measured-map.json, which
// tools/gen-measured-map.mjs turns into gui/src/MeasuredMap.res.
//
//   node tools/measure-map.mjs            # 33×21 grid, ~1 min on 16 cores
//   node tools/gen-measured-map.mjs
//
// Each cell renders 5 s: 1 s silence, a 0.5 s noise burst, then silence.
// (The leading second matters: `cmaj render` drops roughly the first 0.4 s
// of an input file.) Parameters are patched into a temporary copy of the
// source — both the `init:` annotation (the renderer sends it at start-up)
// and the processor's internal target/smoothed defaults.

import fs from 'fs';
import os from 'os';
import path from 'path';
import { execFile } from 'child_process';

const here = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
const root = path.resolve(here, '..');
const work = fs.mkdtempSync(path.join(os.tmpdir(), 'gsr-measure-'));
const source = fs.readFileSync(path.join(root, 'dsp', 'GrayScottResonator.cmajor'), 'utf8');
const rate = 48000;

const base = { mix: 1, feedback: 0 };
const fValues = [], kValues = [];
for (let i = 0; i <= 32; i++) fValues.push(+(0.010 + i * 0.0025).toFixed(4));
for (let j = 0; j <= 20; j++) kValues.push(+(0.045 + j * 0.00125).toFixed(5));

// --- test signal ---------------------------------------------------------------
function writeInput(file) {
  const n = rate * 5, ch = 2, buf = Buffer.alloc(44 + n * ch * 4);
  buf.write('RIFF', 0); buf.writeUInt32LE(36 + n * ch * 4, 4); buf.write('WAVE', 8); buf.write('fmt ', 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(3, 20); buf.writeUInt16LE(ch, 22); buf.writeUInt32LE(rate, 24);
  buf.writeUInt32LE(rate * ch * 4, 28); buf.writeUInt16LE(ch * 4, 32); buf.writeUInt16LE(32, 34);
  buf.write('data', 36); buf.writeUInt32LE(n * ch * 4, 40);
  let seed = 1; const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = 0; i < n; i++) for (let c = 0; c < ch; c++)
    buf.writeFloatLE(i >= rate && i < rate * 1.5 ? (rnd() * 2 - 1) * 0.5 : 0, 44 + (i * ch + c) * 4);
  fs.writeFileSync(file, buf);
}

// --- source patching -------------------------------------------------------------
const internals = { feed: ['feedT', 'feedS'], kill: ['killT', 'killS'], diffusionU: ['duT', 'duS'],
  diffusionRatio: ['ratioT', 'ratioS'], speed: ['speedT', 'speedS'], tapDistance: ['distT', 'distS'],
  feedback: ['fbT', 'fbS'], mix: ['mixT', 'mixS'], drive: ['driveT', 'driveS'] };

function patchSource(params) {
  let s = source;
  for (const [name, value] of Object.entries(params)) {
    const annotation = new RegExp(String.raw`(float ${name}\s+\[\[[^\]]*init: )[-0-9.]+`);
    if (!annotation.test(s)) throw new Error(`no parameter ${name}`);
    s = s.replace(annotation, `$1${Number(value).toFixed(6)}`);
    const internal = name === 'drive' ? Math.pow(10, value / 20) : value;
    for (const v of internals[name] ?? [])
      s = s.replace(new RegExp(String.raw`\b${v} = [-0-9.]+f`), `${v} = ${Number(internal).toFixed(6)}f`);
  }
  return s;
}

// --- analysis --------------------------------------------------------------------
function readFloatWav(file) {
  const b = fs.readFileSync(file);
  let off = 12, data;
  while (off < b.length) {
    const id = b.toString('ascii', off, off + 4), size = b.readUInt32LE(off + 4);
    if (id === 'data') data = { offset: off + 8, size };
    off += 8 + size + (size & 1);
  }
  const n = data.size / 8, L = new Float32Array(n), R = new Float32Array(n);
  for (let i = 0; i < n; i++) { L[i] = b.readFloatLE(data.offset + i * 8); R[i] = b.readFloatLE(data.offset + i * 8 + 4); }
  return [L, R];
}
const at = t => Math.floor(t * rate);
const rms = (a, s, e) => { let t = 0; for (let i = s; i < e; i++) t += a[i] * a[i]; return Math.sqrt(t / (e - s)); };

// --- run -------------------------------------------------------------------------
const input = path.join(work, 'in.wav');
writeInput(input);

const cells = [];
for (const K of kValues) for (const F of fValues) cells.push({ F, K });

let next = 0, done = 0;
const results = [];
async function worker(id) {
  const dir = path.join(work, `w${id}`);
  fs.mkdirSync(dir);
  while (next < cells.length) {
    const cell = cells[next++];
    fs.writeFileSync(path.join(dir, 't.cmajor'), patchSource({ ...base, feed: cell.F, kill: cell.K }));
    fs.writeFileSync(path.join(dir, 't.cmajorpatch'),
      JSON.stringify({ CmajorVersion: 1, ID: `dev.gsr.measure${id}`, version: '1', name: 'measure', source: 't.cmajor' }));
    await new Promise((resolve, reject) => execFile('cmaj',
      ['render', `--input=${input}`, `--output=${path.join(dir, 'out.wav')}`, path.join(dir, 't.cmajorpatch')],
      err => err ? reject(err) : resolve()));
    const [L] = readFloatWav(path.join(dir, 'out.wav'));
    let nan = 0; for (const x of L) if (!Number.isFinite(x)) nan++;
    results.push({ ...cell, nan, burst: rms(L, at(1.1), at(1.5)), ring: rms(L, at(1.55), at(1.8)), tail: rms(L, at(4), L.length) });
    if (++done % 50 === 0) console.log(`${done}/${cells.length}`);
  }
}
await Promise.all(Array.from({ length: Math.max(2, os.cpus().length - 2) }, (_, i) => worker(i)));
fs.rmSync(work, { recursive: true, force: true });

results.sort((a, b) => a.K - b.K || a.F - b.F);
fs.writeFileSync(path.join(here, 'measured-map.json'), JSON.stringify(results));
const nans = results.reduce((a, r) => a + r.nan, 0);
console.log(`wrote tools/measured-map.json (${results.length} cells, ${nans} non-finite samples)`);
if (nans > 0) process.exitCode = 1;
