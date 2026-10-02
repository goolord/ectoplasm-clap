// Stress-renders the lattice at the edges of its parameter space and checks every sample is
// finite and bounded (see STABILITY.md). Each case patches a temporary copy of the DSP: the
// parameter's `init:` annotation (which the renderer sends at start-up) and the processor's
// internal target/smoothed defaults. Cases render in parallel at 44.1, 48 and 96 kHz.
//
//   node tools/test/stability.mjs [name filter]      (or: just test [filter])

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const cmaj = process.env.CMAJ ?? "cmaj";
const filter = process.argv[2] ?? "";
const source = fs.readFileSync(path.join(root, "dsp", "GrayScottResonator.cmajor"), "utf8");
const work = path.join(root, "build", "test", "stability");
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });

// --- cases ---------------------------------------------------------------------------
const extreme = { feedback: 1.5, drive: 24, diffusionU: 0.5, diffusionRatio: 0.1, tapDistance: 0, mix: 1 };
const corners = [
  ["low-F low-K", 0.010, 0.045],
  ["low-F high-K", 0.010, 0.070],
  ["high-F low-K", 0.090, 0.045],
  ["high-F high-K", 0.090, 0.070],
  ["chaos", 0.022, 0.050],
];
const cases = [];
for (const rate of [44100, 48000, 96000]) {
  for (const [name, feed, kill] of corners)
    for (const speed of [0.05, 4])
      cases.push({ name: `${name} speed ${speed} @${rate}`, rate, params: { ...extreme, feed, kill, speed } });
  cases.push({ name: `defaults @${rate}`, rate, params: {}, mustSound: true });
}
const selected = cases.filter((c) => c.name.includes(filter));

// --- source patching -----------------------------------------------------------------
const internals = { feed: ["feedT", "feedS"], kill: ["killT", "killS"], diffusionU: ["duT", "duS"],
  diffusionRatio: ["ratioT", "ratioS"], speed: ["speedT", "speedS"], tapDistance: ["distT", "distS"],
  feedback: ["fbT", "fbS"], mix: ["mixT", "mixS"], drive: ["driveT", "driveS"] };

function patchSource(params) {
  let s = source;
  for (const [name, value] of Object.entries(params)) {
    const annotation = new RegExp(String.raw`(float ${name}\s+\[\[[^\]]*init: )[-0-9.]+`);
    if (!annotation.test(s)) throw new Error(`no parameter ${name}`);
    s = s.replace(annotation, `$1${Number(value).toFixed(6)}`);
    const internal = name === "drive" ? Math.pow(10, value / 20) : value;
    for (const v of internals[name] ?? [])
      s = s.replace(new RegExp(String.raw`\b${v} = [-0-9.]+f`), `${v} = ${Number(internal).toFixed(6)}f`);
  }
  return s;
}

// --- signals -------------------------------------------------------------------------
// 4 s: 1 s of silence (`cmaj render` drops roughly the first 0.4 s of its input), a 0.5 s
// full-scale noise burst, then silence so self-oscillation shows in the tail.
function writeInput(file, rate) {
  const n = rate * 4, samples = new Float32Array(n * 2);
  let seed = 1;
  const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = rate; i < rate * 1.5; i++) samples[2 * i] = samples[2 * i + 1] = rnd() * 2 - 1;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + samples.byteLength, 4); header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(3, 20); header.writeUInt16LE(2, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 8, 28); header.writeUInt16LE(8, 32);
  header.writeUInt16LE(32, 34); header.write("data", 36); header.writeUInt32LE(samples.byteLength, 40);
  fs.writeFileSync(file, Buffer.concat([header, Buffer.from(samples.buffer)]));
}

function readSamples(file) {
  const b = fs.readFileSync(file);
  let pos = 12, fmt, data;
  while (pos + 8 <= b.length) {
    const id = b.toString("ascii", pos, pos + 4), size = b.readUInt32LE(pos + 4);
    if (id === "fmt ") {
      const tag = b.readUInt16LE(pos + 8);
      fmt = { format: tag === 0xfffe ? b.readUInt16LE(pos + 32) : tag, bits: b.readUInt16LE(pos + 22) };
    }
    if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size & 1);
  }
  if (fmt.format !== 3 || fmt.bits !== 32) throw new Error(`${file}: expected 32-bit float output`);
  return new Float32Array(data.buffer.slice(data.byteOffset, data.byteOffset + data.length));
}

const inputs = {};
for (const rate of new Set(selected.map((c) => c.rate))) {
  inputs[rate] = path.join(work, `in-${rate}.wav`);
  writeInput(inputs[rate], rate);
}

// --- run -----------------------------------------------------------------------------
async function run(c, index) {
  const dir = path.join(work, `case${index}`);
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, "t.cmajor"), patchSource(c.params));
  fs.writeFileSync(path.join(dir, "t.cmajorpatch"),
    JSON.stringify({ CmajorVersion: 1, ID: `dev.gsr.stability${index}`, version: "1", name: "stability", source: "t.cmajor" }));
  const out = path.join(dir, "out.wav");
  const error = await new Promise((resolve) => execFile(cmaj,
    ["render", `--input=${inputs[c.rate]}`, `--output=${out}`, path.join(dir, "t.cmajorpatch")],
    (err, stdout, stderr) => resolve(err || /error/i.test(stdout + stderr) ? (stdout + stderr).trim() || String(err) : null)));
  if (error || !fs.existsSync(out)) return { ...c, problems: [`didn't render: ${error}`] };

  const x = readSamples(out);
  let bad = 0, peak = 0, sum = 0;
  for (const v of x) {
    if (!Number.isFinite(v)) { bad++; continue; }
    peak = Math.max(peak, Math.abs(v));
    sum += v * v;
  }
  const rms = Math.sqrt(sum / x.length);
  // The wet path ends in tanh and the output gain defaults to −6 dB, so 0.5 is the ceiling
  // with Mix at 100%; the defaults case mixes in 20% of a full-scale burst.
  const problems = [
    bad > 0 && `${bad} non-finite samples`,
    peak > 0.75 && `peak ${peak.toFixed(3)}`,
    c.mustSound && rms < 1e-3 && `nearly silent (rms ${rms.toExponential(2)})`,
  ].filter(Boolean);
  return { ...c, problems, peak, rms };
}

const queue = selected.map((c, i) => [c, i]);
const results = [];
await Promise.all(Array.from({ length: Math.max(2, os.cpus().length - 2) }, async () => {
  while (queue.length) {
    const [c, i] = queue.shift();
    results[i] = await run(c, i);
  }
}));

let failures = 0;
for (const r of results) {
  if (r.problems.length) failures++;
  console.log(r.problems.length
    ? `FAIL ${r.name}: ${r.problems.join(", ")}`
    : `ok   ${r.name}: peak ${r.peak.toFixed(3)}, rms ${r.rms.toFixed(4)}`);
}
console.log(`${results.length - failures}/${results.length} stability cases passed`);
process.exit(failures ? 1 : 0);
