// Renders every factory preset (gui/src/Presets.res, compiled) through the real DSP and checks
// that what the Play view shows is what you hear: finite, audible while there's input, sustaining
// after the input stops exactly when the Ring knob says "Sustains", otherwise fading 60 dB in
// within a factor of three of the time it shows (the resolution of this measurement), and
// ringing within 10 % of
// the pitch the Pitch knob shows (a spectral peak while a moderate noise burst plays, or of the
// sustained tail). The pitch is the focus's, so it isn't checked where the Play view marks it as
// approximate: Dv/Du below 1 (Turing patterns) or heavy Drive (louder input brings out the
// ring's upper spatial modes).
//
//   node tools/test/presets.mjs        (or: just test)   — needs the GUI compiled (just ui)

import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";
import { patchSource, writeWav, readLeft } from "../patch-source.mjs";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const cmaj = process.env.CMAJ ?? "cmaj";
const work = path.join(root, "build", "test", "presets");
fs.rmSync(work, { recursive: true, force: true });
fs.mkdirSync(work, { recursive: true });

const compiled = (name) => pathToFileURL(path.join(root, "gui", "src", `${name}.res.mjs`)).href;
let Presets, Bindings, Macro;
try {
  Presets = await import(compiled("Presets"));
  Bindings = await import(compiled("CmajorBindings"));
  Macro = await import(compiled("Macro"));
} catch (e) {
  console.error(`FAIL presets: couldn't load the compiled GUI (run \`just ui\` first): ${e.message}`);
  process.exit(1);
}

const source = fs.readFileSync(path.join(root, "dsp", "GrayScottResonator.cmajor"), "utf8");
const rate = 48000;
// 1 s of silence (`cmaj render` drops ~0.4 s of its input), a 0.5 s noise burst, 3.5 s of silence
const input = path.join(work, "in.wav");
let seed = 7;
const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
writeWav(input, rate, rate * 5, (i) => (i >= rate && i < rate * 1.5 ? (rnd() * 2 - 1) * 0.2 : 0));

const rms = (x, from, to) => {
  let t = 0;
  for (let i = Math.floor(from * rate); i < Math.floor(to * rate); i++) t += x[i] * x[i];
  return Math.sqrt(t / Math.max(1, Math.floor(to * rate) - Math.floor(from * rate)));
};
const db = (a, b) => 20 * Math.log10(Math.max(a, 1e-12) / Math.max(b, 1e-12));
// the strongest frequency between 30 Hz and 3 kHz (Hann-windowed Goertzel scan, in 0.23 % steps: a
// long ring is a peak well under 1 % wide, which a coarser scan can step over)
const spectralPeak = (x, from, to) => {
  const a = Math.floor(from * rate), b = Math.floor(to * rate);
  let best = 0, bestHz = 0;
  for (let step = 0; step <= 2000; step++) {
    const hz = 30 * Math.pow(100, step / 2000), w = 2 * Math.PI * hz / rate, c = 2 * Math.cos(w);
    let s1 = 0, s2 = 0;
    for (let i = a; i < b; i++) {
      const s = x[i] * (0.5 - 0.5 * Math.cos(2 * Math.PI * (i - a) / (b - a))) + c * s1 - s2;
      s2 = s1; s1 = s;
    }
    const m = s1 * s1 + s2 * s2 - c * s1 * s2;
    if (m > best) { best = m; bestHz = hz; }
  }
  return bestHz;
};

async function run(preset, index) {
  const params = Object.fromEntries(preset.values.map(([p, v]) => [Bindings.Param.id(p), v]));
  const dir = path.join(work, `p${index}`);
  fs.mkdirSync(dir);
  fs.writeFileSync(path.join(dir, "t.cmajor"), patchSource(source, params));
  fs.writeFileSync(path.join(dir, "t.cmajorpatch"),
    JSON.stringify({ CmajorVersion: 1, ID: `dev.ectoplasm.presettest${index}`, version: "1", name: "t", source: "t.cmajor" }));
  const out = path.join(dir, "out.wav");
  const failed = await new Promise((resolve) => execFile(cmaj,
    ["render", `--input=${input}`, `--output=${out}`, path.join(dir, "t.cmajorpatch")],
    (err, stdout, stderr) => resolve(err || /error/i.test(stdout + stderr) ? (stdout + stderr).trim() || String(err) : null)));
  if (failed) return { preset, problems: [`didn't render: ${failed}`] };

  const x = readLeft(out);
  const bad = x.reduce((n, v) => n + (Number.isFinite(v) ? 0 : 1), 0);
  const burst = rms(x, 1.1, 1.5);
  // the decay after the burst: the fall from 1.6–1.7 s to 2.6–2.7 s, as a T60
  const fallDb = db(rms(x, 1.6, 1.7), rms(x, 2.6, 2.7));
  // sustaining: still within 30 dB of the burst seconds later, and not falling (a ring that has
  // decayed can leave a steady residue ~80 dB down, which isn't sustaining)
  const sustains = fallDb < 3 && db(rms(x, 4.0, 5.0), burst) > -30;
  const heardT60 = sustains ? Infinity : 60 / fallDb;
  const f = params.feed, k = params.kill, speed = params.speed, resonance = params.feedback;
  const focus = Macro.focus(f, k, speed, resonance, params.diffusionU);
  const predictedHz = focus?.hz;
  const shouldSustain = focus !== undefined && focus.ringSeconds === undefined;
  const [, onBand] = Macro.colorOf(f, k);
  // what it rings at: filtered noise while the burst plays, or the tail if it sustains
  const heardHz = sustains ? spectralPeak(x, 4.0, 5.0) : spectralPeak(x, 1.1, 1.5);
  const pitchError = predictedHz ? Math.abs(Math.log(heardHz / predictedHz)) : 0;

  const problems = [
    bad > 0 && `${bad} non-finite samples`,
    burst < 1e-3 && `nearly silent while playing (rms ${burst.toExponential(2)})`,
    // on the band, the Play view's promises must hold
    onBand && shouldSustain !== sustains &&
      (shouldSustain ? "shows Sustains but dies away" : "shows a decay time but keeps sounding"),
    // (rings shorter than ~0.2 s are hidden by the DC blocker's own settling, and longer than
    // the measuring window only need to read as long)
    onBand && !shouldSustain && !sustains && focus.ringSeconds > 0.2 && focus.ringSeconds < 3 &&
      Math.abs(Math.log(heardT60 / focus.ringSeconds)) > Math.log(3) &&
      `shows a ${focus.ringSeconds.toFixed(2)} s ring but fades in ${heardT60.toFixed(2)} s`,
    onBand && !Macro.pitchIsApproximate(params.diffusionRatio, params.drive) && pitchError > Math.log(1.1) &&
      `shows ${predictedHz.toFixed(0)} Hz but rings at ${heardHz.toFixed(0)} Hz`,
  ].filter(Boolean);
  return { preset, problems, burst, sustains, predictedHz, heardHz, ring: focus?.ringSeconds, heardT60 };
}

const results = await Promise.all(Presets.all.map(run));
let failures = 0;
for (const r of results) {
  if (r.problems.length) failures++;
  const pitch = r.predictedHz === undefined ? "no focus" : `predicted ${r.predictedHz.toFixed(0)} Hz, heard ~${r.heardHz.toFixed(0)} Hz`;
  console.log(r.problems.length
    ? `FAIL ${r.preset.name}: ${r.problems.join(", ")}`
    : `ok   ${r.preset.name.padEnd(15)} ${r.sustains ? "sustains          " : `rings ${r.ring?.toFixed(2) ?? "-"} s (${r.heardT60.toFixed(2)})`.padEnd(18)}  ${pitch}`);
}
console.log(`${results.length - failures}/${results.length} presets passed`);
process.exit(failures ? 1 : 0);
