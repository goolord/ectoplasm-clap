// The processor's level model (dsp/GrayScottResonator.cmajor, "The level model"), for the view:
// the ring linearised around its steady state, as the sum of second-order sections the
// processor uses to predict how loud the wet path is. The processor divides the wet signal by
// the model's gain for pink noise, so the view can draw what the plugin does to a sound in real
// decibels, relative to the input.
//
// Both sides have to agree: the step rule, the 33 even spatial modes (all a mono input
// excites), the pole clamp and the Resonance cap are the processor's.

module T = GrayScottTheory

let numNodes = 128
let referenceRate = T.referenceRate
let injectionGain = 0.003
let wetGain = 1.5
let maxPickupDistance = 12.0
let modelResonanceCap = 0.7
let minLevelMatch = 0.25
let maxLevelMatch = 316.0

// ---------------------------------------------------------------------------
// The integrator's step rule

let maxStep = 1.25
let maxSubSteps = 8

/// The longest Euler step diffusion allows (Du·dt ≤ ½), and no more than 1.25.
let longestStep = du => Math.min(maxStep, 0.5 /. du)

/// Sub-steps per sample, and their length, for a lattice time per sample (Speed at 48 kHz).
let steps = (~latticeTime, ~du) => {
  let n = Math.Int.max(
    1,
    Math.Int.min(maxSubSteps, Float.toInt(Math.ceil(latticeTime /. longestStep(du)))),
  )
  (n, Math.min(longestStep(du), latticeTime /. Int.toFloat(n)))
}

// ---------------------------------------------------------------------------
// The model

type section = {weight: float, p11: float, trace: float, det: float}

type t = {
  sections: array<section>,
  // input sample → wet path, before the match: injection, Drive and the fixed gain
  inputGain: float,
}

let bspline = t => {
  let t2 = t *. t
  let t3 = t2 *. t
  let it = 1.0 -. t
  [
    it *. it *. it /. 6.0,
    (3.0 *. t3 -. 6.0 *. t2 +. 4.0) /. 6.0,
    (-3.0 *. t3 +. 3.0 *. t2 +. 3.0 *. t +. 1.0) /. 6.0,
    t3 /. 6.0,
  ]
}

/// ~clampPoles takes a growing mode as just stable, as the processor does for its prediction;
/// without it, a mode past the edge is left as it is (and the response isn't meaningful).
let make = (~f, ~k, ~du, ~ratio, ~speed, ~resonance, ~tap, ~drive, ~clampPoles=true) => {
  let (n, dt) = steps(~latticeTime=speed, ~du)
  let (u, v, g) = switch T.homogeneousState(~f, ~k) {
  | Some({u, v}) =>
    let v2 = v *. v
    let trace = k -. v2
    let det = (f +. k) *. (v2 -. f)
    let edge = -.(trace +. det *. dt) /. (1.0 -. (v2 +. f) *. dt)
    (u, v, resonance *. Math.max(0.0, edge))
  | None => (1.0, 0.0, 0.0)
  }
  let tapAt = 32.0 +. tap *. maxPickupDistance
  let base = Math.floor(tapAt)
  let w = bspline(tapAt -. base)
  let injection = [1.0 /. 6.0, 4.0 /. 6.0, 1.0 /. 6.0, 0.0]
  let sections = Array.fromInitializer(~length=numNodes / 4 + 1, m => {
    let q = 2 * m
    let theta = 2.0 *. Math.Constants.pi *. Int.toFloat(q) /. Int.toFloat(numNodes)
    let lap = Math.cos(theta) -. 1.0
    let a00 = 1.0 +. dt *. (-.v *. v -. f +. du *. lap)
    let a01 = dt *. (-2.0 *. u *. v)
    let a10 = dt *. (v *. v)
    let a11 = 1.0 +. dt *. (2.0 *. u *. v -. (f +. k) +. g +. du *. ratio *. lap)
    let p = ref((a00, a01, a10, a11))
    for _ in 2 to n {
      let (p00, p01, p10, p11) = p.contents
      p :=
        (
          p00 *. a00 +. p01 *. a10,
          p00 *. a01 +. p01 *. a11,
          p10 *. a00 +. p11 *. a10,
          p10 *. a01 +. p11 *. a11,
        )
    }
    let (p00, p01, p10, p11) = p.contents
    let trace = p00 +. p11
    let det = p00 *. p11 -. p01 *. p10
    let (trace, det) = if !clampPoles {
      (trace, det)
    } else {
      let disc = trace *. trace *. 0.25 -. det
      if disc < 0.0 {
        det > 0.998 ? (trace *. Math.sqrt(0.998 /. det), 0.998) : (trace, det)
      } else {
        let clampRoot = r => Math.min(0.999, Math.max(-0.999, r))
        let r1 = clampRoot(trace *. 0.5 +. Math.sqrt(disc))
        let r2 = clampRoot(trace *. 0.5 -. Math.sqrt(disc))
        (r1 +. r2, r1 *. r2)
      }
    }
    // the injectors at nodes 32 and 96 put in the same; the left pickup reads at tapAt
    let tapRe = ref(0.0)
    let tapIm = ref(0.0)
    let injRe = ref(0.0)
    let injIm = ref(0.0)
    for j in 0 to 3 {
      let at = theta *. (base -. 1.0 +. Int.toFloat(j))
      let wj = w->Array.getUnsafe(j)
      tapRe := tapRe.contents +. wj *. Math.cos(at)
      tapIm := tapIm.contents +. wj *. Math.sin(at)
      let inj = 2.0 *. injection->Array.getUnsafe(j)
      let atInj = theta *. Int.toFloat(31 + j)
      injRe := injRe.contents +. inj *. Math.cos(atInj)
      injIm := injIm.contents -. inj *. Math.sin(atInj)
    }
    let pair = q == 0 || q == numNodes / 2 ? 1.0 : 2.0
    {
      weight: pair *.
      (tapRe.contents *. injRe.contents -. tapIm.contents *. injIm.contents) /.
      Int.toFloat(numNodes),
      p11,
      trace,
      det,
    }
  })
  {sections, inputGain: injectionGain *. Math.pow(10.0, ~exp=drive /. 20.0) *. wetGain}
}

// ---------------------------------------------------------------------------
// Complex arithmetic, on (re, im)

let cmul = ((a, b), (c, d)) => (a *. c -. b *. d, a *. d +. b *. c)
let cdiv = ((a, b), (c, d)) => {
  let n = c *. c +. d *. d
  ((a *. c +. b *. d) /. n, (b *. c -. a *. d) /. n)
}
let cadd = ((a, b), (c, d)) => (a +. c, b +. d)
let cscale = ((a, b), s) => (a *. s, b *. s)
let abs2 = ((a, b)) => a *. a +. b *. b

// The processor's fixed output filters at the reference rate: an 8 Hz DC blocker and a 2-pole
// Butterworth low-pass at 16 kHz.
let dcCoeff = 1.0 -. 2.0 *. Math.Constants.pi *. 8.0 /. referenceRate
let lowPass = {
  let kk = Math.tan(Math.Constants.pi *. 16000.0 /. referenceRate)
  let q = Math.Constants.sqrt1_2
  let norm = 1.0 /. (1.0 +. kk /. q +. kk *. kk)
  let b0 = kk *. kk *. norm
  (b0, 2.0 *. b0, b0, 2.0 *. (kk *. kk -. 1.0) *. norm, (1.0 -. kk /. q +. kk *. kk) *. norm)
}

/// The wet path's complex gain at a frequency, from a mono input, before the level match.
let response = (model, hz) => {
  let w = 2.0 *. Math.Constants.pi *. hz /. referenceRate
  let zi = (Math.cos(w), -.Math.sin(w))
  let zi2 = cmul(zi, zi)
  let y = model.sections->Array.reduce((0.0, 0.0), (y, s) =>
    cadd(
      y,
      cscale(
        cdiv(
          cadd((s.p11, 0.0), cscale(zi, -.s.det)),
          cadd(cadd((1.0, 0.0), cscale(zi, -.s.trace)), cscale(zi2, s.det)),
        ),
        s.weight,
      ),
    )
  )
  let dc = cdiv(cadd((1.0, 0.0), cscale(zi, -1.0)), cadd((1.0, 0.0), cscale(zi, -.dcCoeff)))
  let (b0, b1, b2, a1, a2) = lowPass
  let lp = cdiv(
    cadd(cadd((b0, 0.0), cscale(zi, b1)), cscale(zi2, b2)),
    cadd(cadd((1.0, 0.0), cscale(zi, a1)), cscale(zi2, a2)),
  )
  cscale(cmul(cmul(y, dc), lp), model.inputGain)
}

let modelPoints = 96

/// RMS gain for pink noise, 20 Hz to 20 kHz.
let pinkGain = model => {
  let total = ref(0.0)
  for j in 0 to modelPoints - 1 {
    let hz = 20.0 *. Math.pow(1000.0, ~exp=(Int.toFloat(j) +. 0.5) /. Int.toFloat(modelPoints))
    total := total.contents +. abs2(response(model, hz))
  }
  Math.sqrt(total.contents /. Int.toFloat(modelPoints))
}

/// The gain the processor puts on the wet path for these settings, before its learned trim.
let predictedMatch = (~f, ~k, ~du, ~ratio, ~speed, ~resonance, ~tap, ~drive) => {
  let model = make(
    ~f,
    ~k,
    ~du,
    ~ratio,
    ~speed,
    ~resonance=Math.min(resonance, modelResonanceCap),
    ~tap,
    ~drive,
  )
  Math.min(1000.0, Math.max(minLevelMatch, 1.0 /. Math.max(pinkGain(model), 1.0e-9)))
  ->Math.min(maxLevelMatch)
}
