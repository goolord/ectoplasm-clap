// The Play view's macro controls, and the arithmetic that lets it show what you'll hear.
//
//  * Color  — where along the resonant band: K from 0.047 (near the chaotic corner) to 0.061
//             (towards the saddle-node apex), with F a fixed small distance right of the Hopf
//             curve, where the focus rings cleanly. Sets Feed and Kill.
//  * Ring   — how long it rings: a decay time to −60 dB, or Sustains. The first 85 % of the
//             knob's travel is decay time, 30 ms to 8 s on a log scale, which Resonance
//             (anti-damping in the processor, normalised so 1 is the edge of self-oscillation)
//             is solved for, between 0 and 0.97; the last 15 % sustains, Resonance 1.05 up. The
//             sliver in between is skipped: that close to the edge, effects the arithmetic below
//             leaves out (the ring's spatial modes, the anti-damping's soft limit) decide whether
//             it fades or sustains.
//  * Pitch  — the focus's ringing frequency, which is set with Speed. It moves in equal-tempered
//             semitones (A4 = 440 Hz) unless you hold Shift.
//
// Pitch and Ring are targets the app holds (solve): moving Color re-solves Speed and Resonance
// so both stay put, moving Pitch keeps the ring time, and moving Ring keeps the note. Decay time
// goes roughly as 1 / Speed, so a target can be out of reach (a 4 s ring at 1 kHz needs more
// than Resonance 0.97 gives); then you hear the nearest you can get, and the target is kept, so
// moving back brings it back.
//
// Pitch and decay come from the processor's discrete-time dynamics, not just the continuous
// eigenvalue: explicit Euler multiplies a mode by z = 1 + λ·dt per sub-step, which grows by about
// ω²·dt/2 on its own (enough to cancel half the damping at the default focus). The sub-steps are
// the processor's (LevelModel.steps), which depend on Diffusion. Using z keeps the
// numbers on screen within a few percent of the offline renders (tools/test/presets.mjs).

module T = GrayScottTheory

let kLow = 0.0470
let kHigh = 0.0610
/// How far right of the Hopf curve Color keeps F: close enough to ring, with Resonance making up
/// the rest of the decay time, and far enough that the focus's basin is roomy.
let bandOffset = 0.004
let maxResonance = 1.3

let clamp01 = x => Math.min(1.0, Math.max(0.0, x))

let hopfF = k => T.hopfF(k)->Option.getOr(T.fMin)

/// F and K for a Color.
let toFK = color => {
  let k = kLow +. clamp01(color) *. (kHigh -. kLow)
  (Math.min(T.fMax, Math.max(T.fMin, hopfF(k) +. bandOffset)), k)
}

/// The Color for a K, and whether F is on the band (where Color would put it).
let colorOf = (~f, ~k) => {
  let onBand =
    k >= kLow -. 0.0001 && k <= kHigh +. 0.0001 && Math.abs(f -. (hopfF(k) +. bandOffset)) < 0.0006
  (clamp01((k -. kLow) /. (kHigh -. kLow)), onBand)
}

// ---------------------------------------------------------------------------
// The focus as the processor runs it

type focus = {
  hz: float,
  // seconds to fall by 60 dB, or None if it sustains itself
  ringSeconds: option<float>,
  // decay rate in nepers per second (≤ 0 when it sustains)
  decayPerSecond: float,
}

/// The focus at these settings (du is Diffusion, which sets how long a sub-step can be).
let focus = (~f, ~k, ~speed, ~resonance, ~du) =>
  T.homogeneousState(~f, ~k)->Option.flatMap(({v}) => {
    let (steps, dt) = LevelModel.steps(~latticeTime=speed, ~du)
    let v2 = v *. v
    let trace = k -. v2
    let det = (f +. k) *. (v2 -. f)
    let omegaSquared = det -. trace *. trace /. 4.0
    if omegaSquared <= 0.0 || omegaSquared *. dt *. dt >= 1.0 {
      None
    } else {
      // Resonance: anti-damping g, normalised to the discrete edge |1 + λ·dt| = 1 (with the
      // trace and determinant g shifts; see updateAntiDamping in the processor)
      let g = resonance *. LevelModel.edgeGain(~f, ~k, ~v, ~dt)
      let trace' = trace +. g
      let det' = det -. g *. (v2 +. f)
      let omega'Squared = det' -. trace' *. trace' /. 4.0
      if omega'Squared <= 0.0 {
        None
      } else {
        // one sub-step multiplies the mode by z = 1 + λ·dt
        let re = 1.0 +. trace' /. 2.0 *. dt
        let im = Math.sqrt(omega'Squared) *. dt
        let stepsF = Int.toFloat(steps)
        let lnMagnitudePerSample = 0.5 *. Math.log(re *. re +. im *. im) *. stepsF
        let anglePerSample = Math.atan2(~y=im, ~x=re) *. stepsF
        let decayPerSecond = -.lnMagnitudePerSample *. T.referenceRate
        Some({
          hz: anglePerSample *. T.referenceRate /. (2.0 *. Math.Constants.pi),
          decayPerSecond,
          ringSeconds: decayPerSecond > 0.0 ? Some(Math.log(1000.0) /. decayPerSecond) : None,
        })
      }
    }
  })

let pitch = (~f, ~k, ~speed, ~resonance, ~du) =>
  focus(~f, ~k, ~speed, ~resonance, ~du)->Option.map(x => x.hz)

let minSpeed = 0.05
let maxSpeed = 4.0

/// The Speed that puts the focus at a frequency (clamped to Speed's range). Pitch is nearly
/// proportional to Speed, so a few fixed-point steps settle it.
let speedFor = (~hz, ~f, ~k, ~resonance, ~du) => {
  let clampSpeed = s => Math.min(maxSpeed, Math.max(minSpeed, s))
  let rec refine = (speed, n) =>
    if n == 0 {
      speed
    } else {
      switch pitch(~f, ~k, ~speed, ~resonance, ~du) {
      | Some(now) if now > 0.0 => refine(clampSpeed(speed *. hz /. now), n - 1)
      | _ => speed
      }
    }
  refine(1.0, 4)
}

/// Where the focus's pitch is only a guide: with Dv/Du below 1 Turing patterns form and move the
/// sound off it, and with heavy Drive the ring's upper spatial modes come forward.
let pitchIsApproximate = (~ratio, ~drive) => ratio < 0.95 || drive > 9.0

// Knob position ↔ Hz, logarithmic.
let minHz = 20.0
let maxHz = 2000.0
let clampHz = hz => Math.min(maxHz, Math.max(minHz, hz))
let hzToNorm = hz => clamp01(Math.log(hz /. minHz) /. Math.log(maxHz /. minHz))
let normToHz = n => minHz *. Math.pow(maxHz /. minHz, ~exp=clamp01(n))

// ---------------------------------------------------------------------------
// Notes: equal temperament, A4 = 440 Hz, as MIDI note numbers (fractional between semitones)

let midiOf = hz => 69.0 +. 12.0 *. Math.log2(hz /. 440.0)
let hzOfMidi = m => 440.0 *. Math.pow(2.0, ~exp=(m -. 69.0) /. 12.0)

let nearestSemitone = hz => hzOfMidi(Math.round(midiOf(hz)))

/// n semitones up (or down, for n < 0) from hz. Big steps go from the nearest note; a single step
/// from a note that's out of tune first lands on the next note that way, so one press tunes it.
let semitoneStep = (hz, n) => {
  let m = midiOf(hz)
  let nearest = Math.round(m)
  let short = Math.abs(m -. nearest) > 0.01 && (nearest -. m) *. Int.toFloat(n) > 0.0
  hzOfMidi(nearest +. Int.toFloat(short && Math.Int.abs(n) == 1 ? 0 : n))
}

let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

let noteName = hz => {
  let index = Float.toInt(Math.round(midiOf(hz)))
  noteNames->Array.getUnsafe(mod(mod(index, 12) + 12, 12)) ++
  Int.toString(Float.toInt(Math.floor(Int.toFloat(index) /. 12.0)) - 1)
}

/// How far from the nearest note, in whole cents (−50..50).
let cents = hz => {
  let m = midiOf(hz)
  Float.toInt(Math.round((m -. Math.round(m)) *. 100.0))
}

/// The offset from the nearest note when it's more than a cent out: "−13 ¢".
let centsText = hz => {
  let c = cents(hz)
  Math.Int.abs(c) > 1 ? Some((c > 0 ? "+" : "−") ++ Int.toString(Math.Int.abs(c)) ++ " ¢") : None
}

/// The note, and the offset when it's more than a cent out: "D4", "D4 −13 ¢".
let tuning = hz => noteName(hz) ++ centsText(hz)->Option.mapOr("", c => " " ++ c)

let formatHz = hz =>
  hz >= 1000.0
    ? Float.toFixed(hz /. 1000.0, ~digits=2) ++ " kHz"
    : Float.toFixed(hz, ~digits=0) ++ " Hz"

let formatSeconds = s =>
  s >= 10.0
    ? "10 s+"
    : s >= 1.0
    ? Float.toFixed(s, ~digits=1) ++ " s"
    : Float.toFixed(s *. 1000.0, ~digits=0) ++ " ms"

// ---------------------------------------------------------------------------
// Ring: a decay time, or Sustains, and the knob position for it

type ring =
  | /// seconds to fall by 60 dB
    Fades(float)
  | /// past the edge, at this Resonance
    Sustains(float)

let minRingSeconds = 0.03
let maxRingSeconds = 8.0
let ringSustainFrom = 0.85
let maxDecayResonance = 0.97
let minSustainResonance = 1.05

let ringToNorm = ring =>
  switch ring {
  // (kept just short of the sustain zone, so the longest fade reads back as a fade)
  | Fades(s) =>
    Math.min(
      ringSustainFrom -. 1e-6,
      ringSustainFrom *. clamp01(Math.log(s /. minRingSeconds) /. Math.log(maxRingSeconds /. minRingSeconds)),
    )
  | Sustains(resonance) =>
    ringSustainFrom +.
    (1.0 -. ringSustainFrom) *.
    clamp01((resonance -. minSustainResonance) /. (maxResonance -. minSustainResonance))
  }

let normToRing = n => {
  let n = clamp01(n)
  n < ringSustainFrom
    ? Fades(minRingSeconds *. Math.pow(maxRingSeconds /. minRingSeconds, ~exp=n /. ringSustainFrom))
    : Sustains(
        minSustainResonance +.
        (n -. ringSustainFrom) /. (1.0 -. ringSustainFrom) *. (maxResonance -. minSustainResonance),
      )
}

/// What a typed "sustain" sustains at: comfortably past the edge.
let typedSustainResonance = 1.1

/// The note and the ring a focus gives at this Resonance (what the app adopts as its targets
/// when something other than the macros moves the parameters).
let targetsOf = ({hz, ringSeconds}: focus, ~resonance) => (
  hz,
  switch ringSeconds {
  | Some(s) => Fades(s)
  | None => Sustains(resonance)
  },
)

/// The Resonance, between 0 and 0.97, whose decay time is closest to seconds. Decay time rises
/// monotonically with Resonance there, so bisection finds it; out of reach, it's the end nearest.
let resonanceFor = (~seconds, ~f, ~k, ~speed, ~du) => {
  // an overdamped (no focus) setting doesn't ring at all; a sustained one rings for ever
  let ringAt = resonance =>
    switch focus(~f, ~k, ~speed, ~resonance, ~du) {
    | Some({ringSeconds: Some(s)}) => s
    | Some({ringSeconds: None}) => Float.Constants.positiveInfinity
    | None => 0.0
    }
  if ringAt(maxDecayResonance) <= seconds {
    maxDecayResonance
  } else if ringAt(0.0) >= seconds {
    0.0
  } else {
    let rec bisect = (lo, hi, n) =>
      if n == 0 {
        (lo +. hi) /. 2.0
      } else {
        let mid = (lo +. hi) /. 2.0
        ringAt(mid) < seconds ? bisect(mid, hi, n - 1) : bisect(lo, mid, n - 1)
      }
    bisect(0.0, maxDecayResonance, 32)
  }
}

/// Speed and Resonance for a note and a ring at F and K. Speed depends a little on Resonance, and
/// decay time a lot on Speed, so the two solves alternate a few times (they settle in two or
/// three); Speed is solved last, so the note is exact.
let solve = (~f, ~k, ~hz, ~ring, ~resonance, ~du) =>
  switch ring {
  | Sustains(resonance) => (speedFor(~hz, ~f, ~k, ~resonance, ~du), resonance)
  | Fades(seconds) =>
    let rec go = (resonance, n) => {
      let speed = speedFor(~hz, ~f, ~k, ~resonance, ~du)
      let resonance = resonanceFor(~seconds, ~f, ~k, ~speed, ~du)
      n == 0 ? (speedFor(~hz, ~f, ~k, ~resonance, ~du), resonance) : go(resonance, n - 1)
    }
    go(Math.min(maxDecayResonance, Math.max(0.0, resonance)), 3)
  }

// ---------------------------------------------------------------------------
// Typing values in. Each parser takes what someone might type and returns the value in the
// parameter's own units, or None if it can't read it.

let number = "([0-9]+(?:[.][0-9]*)?|[.][0-9]+)"

// a typed minus may be the typographic one; the patterns allow spaces between the parts
let tidy = text => text->String.trim->String.replaceAll("−", "-")->String.toLowerCase

let matchOf = (pattern, text) =>
  RegExp.fromString("^" ++ pattern ++ "$", ~flags="i")
  ->RegExp.exec(tidy(text))
  ->Option.map(RegExp.Result.matches)

let groupAt = (groups: array<option<string>>, i) => groups[i]->Option.flatMap(x => x)

let numberAt = (groups, i) => groupAt(groups, i)->Option.flatMap(Float.fromString)

let noteLetters = dict{"c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11}

/// A note ("A3", "a#3", "Bb2", "C♯4", "e♭-1"), optionally with cents as the knob shows them
/// ("D4 −13 ¢", "d4+20c"), or a frequency ("440", "440 Hz", "1.2k", "1.2 kHz"), as Hz.
let parsePitch = text =>
  switch matchOf(
    "([a-g]) *([#♯b♭]?) *(-?[0-9])(?: *([+-]) *" ++ number ++ " *(?:¢|c|cents?)?)?",
    text,
  ) {
  | Some(groups) =>
    switch (groupAt(groups, 0)->Option.flatMap(Dict.get(noteLetters, _)), numberAt(groups, 2)) {
    | (Some(letter), Some(octave)) =>
      let accidental = switch groupAt(groups, 1) {
      | Some("#") | Some("♯") => 1
      | Some("b") | Some("♭") => -1
      | _ => 0
      }
      let cents =
        numberAt(groups, 4)->Option.mapOr(0.0, c => groupAt(groups, 3) == Some("-") ? -.c : c)
      Some(
        hzOfMidi((octave +. 1.0) *. 12.0 +. Int.toFloat(letter + accidental) +. cents /. 100.0),
      )
    | _ => None
    }
  | None =>
    matchOf(number ++ " *(k)? *(hz)?", text)->Option.flatMap(groups =>
      numberAt(groups, 0)->Option.flatMap(x => {
        let hz = groupAt(groups, 1)->Option.isSome ? x *. 1000.0 : x
        hz > 0.0 ? Some(hz) : None
      })
    )
  }

/// A decay time ("1.2 s", "300 ms", "2 sec") or a sustain ("sustain", "inf", "∞", which sustains
/// at typedSustainResonance). A bare number is milliseconds above 20 and seconds up to it, which
/// reads "300" and "1.5" the way they're meant: no ring worth setting is under 20 ms or over 20 s.
let parseRing = text =>
  switch tidy(text) {
  | "sustain" | "sustains" | "sustained" | "inf" | "infinite" | "∞" | "forever" =>
    Some(Sustains(typedSustainResonance))
  | _ =>
    matchOf(number ++ " *(ms|msec|milliseconds?|s|sec|secs|seconds?)?", text)->Option.flatMap(groups =>
      numberAt(groups, 0)->Option.flatMap(x => {
        let seconds = switch groupAt(groups, 1) {
        | Some(unit) if String.startsWith(unit, "m") => x /. 1000.0
        | Some(_) => x
        | None => x > 20.0 ? x /. 1000.0 : x
        }
        seconds > 0.0 ? Some(Fades(seconds)) : None
      })
    )
  }

/// Decibels: "-6", "+3 dB", "−12db".
let parseDecibels = text =>
  matchOf("([+-]?) *" ++ number ++ " *(db)?", text)->Option.flatMap(groups =>
    numberAt(groups, 1)->Option.map(x => groupAt(groups, 0) == Some("-") ? -.x : x)
  )

/// A percentage, "50" or "50 %", as 0..1.
let parsePercent = text =>
  matchOf(number ++ " *%?", text)->Option.flatMap(groups =>
    numberAt(groups, 0)->Option.map(x => x /. 100.0)
  )
