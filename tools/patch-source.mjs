// Helpers for the offline-render tools: set parameter values in a copy of the DSP source, and
// read and write 32-bit float WAV files.
//
// A parameter is set in two places: its `init:` annotation (the renderer sends that at start-up)
// and the processor's internal target and smoothed values, so there's no glide at the start.

import fs from "node:fs";

const internals = {
  feed: ["feedT", "feedS"], kill: ["killT", "killS"], diffusionU: ["duT", "duS"],
  diffusionRatio: ["ratioT", "ratioS"], speed: ["speedT", "speedS"], tapDistance: ["distT", "distS"],
  feedback: ["fbT", "fbS"], mix: ["mixT", "mixS"], drive: ["driveT", "driveS"], outputGain: ["gainT", "gainS"],
};
const decibels = new Set(["drive", "outputGain"]);

export function patchSource(source, params) {
  let s = source;
  for (const [name, value] of Object.entries(params)) {
    const annotation = new RegExp(String.raw`(float ${name}\s+\[\[[^\]]*init: )[-0-9.]+`);
    if (!annotation.test(s)) throw new Error(`no parameter ${name}`);
    s = s.replace(annotation, `$1${Number(value).toFixed(6)}`);
    const internal = decibels.has(name) ? Math.pow(10, value / 20) : value;
    for (const v of internals[name] ?? [])
      s = s.replace(new RegExp(String.raw`\b${v} = [-0-9.]+f`), `${v} = ${Number(internal).toFixed(6)}f`);
  }
  return s;
}

/// Writes a stereo 32-bit float WAV; gen(i) gives frame i (both channels).
export function writeWav(file, rate, frames, gen) {
  const samples = new Float32Array(frames * 2);
  for (let i = 0; i < frames; i++) samples[2 * i] = samples[2 * i + 1] = gen(i);
  const header = Buffer.alloc(44);
  header.write("RIFF", 0); header.writeUInt32LE(36 + samples.byteLength, 4); header.write("WAVEfmt ", 8);
  header.writeUInt32LE(16, 16); header.writeUInt16LE(3, 20); header.writeUInt16LE(2, 22);
  header.writeUInt32LE(rate, 24); header.writeUInt32LE(rate * 8, 28); header.writeUInt16LE(8, 32);
  header.writeUInt16LE(32, 34); header.write("data", 36); header.writeUInt32LE(samples.byteLength, 40);
  fs.writeFileSync(file, Buffer.concat([header, Buffer.from(samples.buffer)]));
}

/// The left channel of a 32-bit float WAV (WAVE_FORMAT_EXTENSIBLE or not).
export function readLeft(file) {
  const b = fs.readFileSync(file);
  let pos = 12, fmt, data;
  while (pos + 8 <= b.length) {
    const id = b.toString("ascii", pos, pos + 4), size = b.readUInt32LE(pos + 4);
    if (id === "fmt ") {
      const tag = b.readUInt16LE(pos + 8);
      fmt = { format: tag === 0xfffe ? b.readUInt16LE(pos + 32) : tag, channels: b.readUInt16LE(pos + 10), bits: b.readUInt16LE(pos + 22) };
    }
    if (id === "data") data = b.subarray(pos + 8, pos + 8 + size);
    pos += 8 + size + (size & 1);
  }
  if (fmt.format !== 3 || fmt.bits !== 32) throw new Error(`${file}: expected 32-bit float`);
  const n = data.length / (4 * fmt.channels), left = new Float32Array(n);
  for (let i = 0; i < n; i++) left[i] = data.readFloatLE(i * 4 * fmt.channels);
  return left;
}
