// Factory presets. Each sets every parameter. Most are written in macro terms (Color, a ring time
// and a note), so they land on the resonant band at the note and ring time they name; the last
// two sit in the Lab view's territory, off the band. `just test` renders every one
// (tools/test/presets.mjs).

module Param = CmajorBindings.Param

type preset = {
  name: string,
  description: string,
  values: array<(Param.t, float)>,
}

let make = (
  name,
  description,
  ~f,
  ~k,
  ~speed,
  ~diffusion=0.40,
  ~ratio=1.0,
  ~drive=0.0,
  ~pickup=0.3,
  ~resonance=0.93,
  ~mix=1.0,
  ~output=-6.0,
) => {
  name,
  description,
  values: [
    (Param.Feed, f),
    (Kill, k),
    (DiffusionU, diffusion),
    (DiffusionRatio, ratio),
    (Speed, speed),
    (Drive, drive),
    (TapDistance, pickup),
    (Feedback, resonance),
    (Mix, mix),
    (OutputGain, output),
  ]->Array.map(((p, v)) => (p, Param.clamp(p, v))),
}

/// A preset on the resonant band: Color, Ring (a decay time in seconds, or Sustains at a
/// Resonance), and the note to ring at, solved the way the Play page's knobs are.
let tuned = (name, description, ~color, ~ring, ~hz, ~diffusion=?, ~ratio=?, ~drive=?, ~pickup=?) => {
  let (f, k) = Macro.toFK(color)
  let (speed, resonance) = Macro.solve(
    ~f,
    ~k,
    ~hz,
    ~ring,
    ~resonance=0.9,
    ~du=diffusion->Option.getOr(Param.spec(DiffusionU).init),
  )
  make(
    name,
    description,
    ~f,
    ~k,
    ~speed,
    ~resonance,
    ~diffusion?,
    ~ratio?,
    ~drive?,
    ~pickup?,
  )
}

let all = [
  make(
    "Init",
    "Every parameter at its default",
    ~f=Param.spec(Feed).init,
    ~k=Param.spec(Kill).init,
    ~speed=Param.spec(Speed).init,
  ),
  tuned(
    "Glass bell",
    "A clean, long ring on C5.",
    ~color=0.55,
    ~ring=Macro.Fades(0.27),
    ~hz=523.3,
    ~diffusion=0.30,
    ~pickup=0.15,
  ),
  tuned(
    "Ecto drone",
    "Past the edge: it keeps singing on A2 after the input stops.",
    ~color=0.35,
    ~ring=Macro.Sustains(1.13),
    ~hz=110.0,
  ),
  tuned(
    "Slime pluck",
    "Short and rubbery on G3, with Drive pushing the chemistry hard. Hit it with transients.",
    ~color=0.7,
    ~ring=Macro.Fades(0.14),
    ~hz=196.0,
    ~drive=12.0,
  ),
  tuned(
    "Turing hum",
    "Low Dv/Du lets stripes grow on the ring, so the tone shifts as the pattern settles.",
    ~color=0.9,
    ~ring=Macro.Fades(0.5),
    ~hz=146.8,
    ~diffusion=0.45,
    ~ratio=0.35,
    ~drive=12.0,
  ),
  tuned(
    "Membrane",
    "A deep, slow skin on C2, with the pickups far from the inputs.",
    ~color=0.2,
    ~ring=Macro.Fades(0.87),
    ~hz=65.4,
    ~diffusion=0.5,
    ~pickup=0.5,
  ),
  tuned(
    "Bright ghost",
    "A thin, whistling ring on C6, picked up right at the inputs.",
    ~color=0.45,
    ~ring=Macro.Fades(0.09),
    ~hz=1046.5,
    ~pickup=0.05,
  ),
  make(
    "Chaos bloom",
    "Left of the Hopf curve, with Turing patterns allowed and Drive high: rough and restless while you play.",
    ~f=0.0225,
    ~k=0.0525,
    ~speed=1.0,
    ~drive=18.0,
    ~ratio=0.6,
    ~resonance=0.0,
  ),
  make(
    "Soliton clicks",
    "Just above the saddle-node curve: loud input fires pulses that run around the ring.",
    ~f=0.070,
    ~k=0.0640,
    ~speed=2.0,
    ~drive=18.0,
    ~ratio=0.5,
    ~pickup=0.2,
    ~resonance=0.0,
  ),
]

/// Whether the current values are this preset's.
let matches = (preset, valueOf: Param.t => float) =>
  preset.values->Array.every(((p, v)) => {
    let s = Param.spec(p)
    Math.abs(valueOf(p) -. v) <= (s.max -. s.min) *. 0.002
  })
