// Analytic structure of the Gray-Scott reaction in the F×K plane, used to
// draw the phase plane and to label regions. Mirrors `homogeneousState` in
// GrayScottResonator.cmajor.
//
// Homogeneous steady states satisfy  U V = F + K  and  U V² = F (1 − U), i.e.
//     (F+K) V² − F V + F (F+K) = 0
// Real roots exist only below the saddle-node curve   K = √F / 2 − F.
// The Jacobian at the upper-V root has
//     trace = K − V²        det = (F+K)(V² − F)
// so it loses stability (Hopf) where V² = K, which gives the Hopf curve
//     F + K = √F · K^¼.

let fMin = 0.010
let fMax = 0.090
let kMin = 0.045
let kMax = 0.070

/// K on the saddle-node curve for a given F.
let saddleNodeK = f => Math.sqrt(f) /. 2.0 -. f

/// F on the (lower) Hopf branch for a given K, if K ≤ 1/16.
let hopfF = k => {
  let q = Math.pow(k, ~exp=0.25)
  let disc = Math.sqrt(k) -. 4.0 *. k
  if disc < 0.0 {
    None
  } else {
    let s = (q -. Math.sqrt(disc)) /. 2.0
    Some(s *. s)
  }
}

type homogeneous = {u: float, v: float}

let homogeneousState = (~f, ~k) => {
  let fk = f +. k
  let disc = f *. f -. 4.0 *. f *. fk *. fk
  if disc <= 0.0 {
    None
  } else {
    let v = (f +. Math.sqrt(disc)) /. (2.0 *. fk)
    Some({u: fk /. v, v})
  }
}

type resonance = {
  hertzPerUnitSpeed: float, // ringing frequency at Speed = 1
  q: float, // ω / (2·damping); infinite at the Hopf curve
  selfOscillating: bool,
}

/// The processor runs its lattice on a fixed 48 kHz time base (one Euler step
/// per 1/48000 s at Speed 1) whatever the host sample rate.
let referenceRate = 48000.0

/// Linear resonance of the homogeneous focus, if there is one, at Speed = 1;
/// multiply the frequency by Speed.
let resonance = (~f, ~k) =>
  homogeneousState(~f, ~k)->Option.flatMap(({v}) => {
    let trace = k -. v *. v
    let det = (f +. k) *. (v *. v -. f)
    let omegaSquared = det -. trace *. trace /. 4.0
    if det <= 0.0 || omegaSquared <= 0.0 {
      None
    } else {
      let omega = Math.sqrt(omegaSquared)
      let damping = -.trace /. 2.0
      Some({
        hertzPerUnitSpeed: omega /. (2.0 *. Math.Constants.pi) *. referenceRate,
        q: damping > 0.0 ? omega /. (2.0 *. damping) : Float.Constants.positiveInfinity,
        selfOscillating: damping <= 0.0,
      })
    }
  })

// ---------------------------------------------------------------------------
// Behaviour regions. Boundaries follow the analytic curves; the names follow
// Pearson's (1993) taxonomy as it shows up in this 1D ring, cross-checked
// against offline renders of the processor (see MeasuredMap.res).

type region =
  | Chaos // left of Hopf: homogeneous state unstable, spatiotemporal chaos
  | Drones // just right of Hopf: high-Q focus, sings with a little Resonance
  | Stripes // below the saddle-node curve, Turing-unstable when Dv/Du < 1
  | Damped // deep inside the stable region: low-Q, heavily damped
  | Spots // just above the saddle-node: localised, self-replicating spots
  | Solitons // above the saddle-node at high F: isolated travelling pulses
  | Silent // everything decays to U=1, V=0

let droneBand = 0.010
let stripeBand = 0.0055

let classify = (~f, ~k) => {
  let kSN = saddleNodeK(f)
  if k > kSN {
    let above = k -. kSN
    if above > 0.0045 {
      Silent
    } else if f < 0.05 {
      Spots
    } else {
      Solitons
    }
  } else {
    switch hopfF(k) {
    | Some(fH) if f < fH => Chaos
    | Some(fH) if f < fH +. droneBand => Drones
    | _ => kSN -. k < stripeBand ? Stripes : Damped
    }
  }
}

let regionName = r =>
  switch r {
  | Chaos => "Chaos"
  | Drones => "Drones"
  | Stripes => "Stripes"
  | Damped => "Damped"
  | Spots => "Spots"
  | Solitons => "Solitons"
  | Silent => "Silent"
  }

let regionHint = r =>
  switch r {
  | Chaos => "The ring never settles. Self-oscillates without input."
  | Drones => "A tuned focus. Raise Resonance to make it sing."
  | Stripes => "Labyrinth patterns form when Dv / Du is below 1."
  | Damped => "Stable and well damped. Short, plucky rings."
  | Spots => "Input triggers spots that split and drift."
  | Solitons => "Isolated pulses that travel and collide."
  | Silent => "Every disturbance dies away."
  }

// Label anchor points (F, K) for the phase plane.
let regionLabels = [
  (Chaos, 0.0150, 0.0470),
  (Drones, 0.0330, 0.0535),
  (Stripes, 0.0600, 0.0590),
  (Damped, 0.0700, 0.0490),
  (Spots, 0.0300, 0.0610),
  (Solitons, 0.0740, 0.0640),
  (Silent, 0.0300, 0.0680),
]
