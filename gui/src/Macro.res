// The Play view's macro controls, and the arithmetic that lets it show what you'll hear.
//
//  * Color  — where along the resonant band: K from 0.047 (near the chaotic corner) to 0.061
//             (towards the saddle-node apex), with F a fixed small distance right of the Hopf
//             curve, where the focus rings cleanly. Sets Feed and Kill.
//  * Ring   — how long it rings: the Resonance parameter (anti-damping in the processor,
//             normalised so 1 is the edge of self-oscillation), shown as the decay time it
//             gives here. The first 85 % of the knob's travel takes Resonance from 0 to 0.97,
//             tapered towards the edge, where decay time goes as 1 / (1 − Resonance); the last
//             15 % sustains, from 1.05 up. The sliver in between is skipped: that close to the
//             edge, effects the arithmetic below leaves out (the ring's spatial modes, the
//             anti-damping's soft limit) decide whether it fades or sustains.
//  * Pitch  — the focus's ringing frequency, which is set with Speed. It's a target: moving
//             Color, Ring or Pitch re-solves Speed so the note stays where you put it.
//
// Pitch and decay come from the processor's discrete-time dynamics, not just the continuous
// eigenvalue: explicit Euler multiplies a mode by z = 1 + λ·dt per sub-step, which grows by about
// ω²·dt/2 on its own (enough to cancel half the damping at the default focus). Using z keeps the
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

let maxSubSteps = 8

type focus = {
  hz: float,
  // seconds to fall by 60 dB, or None if it sustains itself
  ringSeconds: option<float>,
  // decay rate in nepers per second (≤ 0 when it sustains)
  decayPerSecond: float,
}

let focus = (~f, ~k, ~speed, ~resonance) =>
  T.homogeneousState(~f, ~k)->Option.flatMap(({v}) => {
    let steps = Math.Int.max(1, Math.Int.min(maxSubSteps, Float.toInt(Math.ceil(speed))))
    let dt = Math.min(1.0, speed /. Int.toFloat(steps))
    let v2 = v *. v
    let trace = k -. v2
    let det = (f +. k) *. (v2 -. f)
    let omegaSquared = det -. trace *. trace /. 4.0
    if omegaSquared <= 0.0 || omegaSquared *. dt *. dt >= 1.0 {
      None
    } else {
      // Resonance: anti-damping g, normalised to the discrete edge |1 + λ·dt| = 1 (with the
      // trace and determinant g shifts; see updateAntiDamping in the processor)
      let edge = -.(trace +. det *. dt) /. (1.0 -. (v2 +. f) *. dt)
      let g = resonance *. Math.max(0.0, edge)
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

let pitch = (~f, ~k, ~speed, ~resonance) => focus(~f, ~k, ~speed, ~resonance)->Option.map(x => x.hz)

let minSpeed = 0.05
let maxSpeed = 4.0

/// The Speed that puts the focus at a frequency (clamped to Speed's range). Pitch is nearly
/// proportional to Speed, so a few fixed-point steps settle it.
let speedFor = (~hz, ~f, ~k, ~resonance) => {
  let clampSpeed = s => Math.min(maxSpeed, Math.max(minSpeed, s))
  let rec refine = (speed, n) =>
    if n == 0 {
      speed
    } else {
      switch pitch(~f, ~k, ~speed, ~resonance) {
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
let hzToNorm = hz => clamp01(Math.log(hz /. minHz) /. Math.log(maxHz /. minHz))
let normToHz = n => minHz *. Math.pow(maxHz /. minHz, ~exp=clamp01(n))

let noteNames = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

let noteName = hz => {
  let index = Float.toInt(Math.round(69.0 +. 12.0 *. Math.log2(hz /. 440.0)))
  noteNames->Array.getUnsafe(mod(mod(index, 12) + 12, 12)) ++ Int.toString(index / 12 - 1)
}

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
// Ring: knob ↔ Resonance

let ringSustainFrom = 0.85
let maxDecayResonance = 0.97
let minSustainResonance = 1.05

let ringToResonance = ring => {
  let n = clamp01(ring)
  n <= ringSustainFrom
    ? 1.0 -. Math.pow(1.0 -. maxDecayResonance, ~exp=n /. ringSustainFrom)
    : minSustainResonance +.
      (n -. ringSustainFrom) /. (1.0 -. ringSustainFrom) *. (maxResonance -. minSustainResonance)
}

let resonanceToRing = resonance =>
  if resonance <= maxDecayResonance {
    clamp01(
      ringSustainFrom *.
      Math.log(1.0 -. Math.max(0.0, resonance)) /.
      Math.log(1.0 -. maxDecayResonance),
    )
  } else if resonance < minSustainResonance {
    ringSustainFrom
  } else {
    ringSustainFrom +.
    (1.0 -. ringSustainFrom) *.
    clamp01((resonance -. minSustainResonance) /. (maxResonance -. minSustainResonance))
  }
