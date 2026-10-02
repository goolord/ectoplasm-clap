// Ectoplasm: near-black grounds with a faint green cast (no blue), a slime-green accent, and
// concentration rendered as a ramp from the dark up through moss to a pale green glow. Region
// colours stay in the warm-neutral to green range: amber, olive, moss, lime.
// Every colour the GUI uses lives here.

type rgb = (int, int, int)

let css = ((r, g, b): rgb, alpha) =>
  "rgba(" ++
  Int.toString(r) ++
  "," ++
  Int.toString(g) ++
  "," ++
  Int.toString(b) ++
  "," ++
  Float.toString(alpha) ++ ")"

let hex = ((r, g, b): rgb) => {
  let byte = c => (c < 16 ? "0" : "") ++ Int.toString(c, ~radix=16)
  "#" ++ byte(r) ++ byte(g) ++ byte(b)
}

// Grounds and text
let slideRgb: rgb = (15, 18, 15) // page ground
let glassRgb: rgb = (23, 28, 23) // panel ground
let wellRgb: rgb = (9, 12, 9) // kymograph and dish ground
let ruleRgb: rgb = (40, 49, 41) // hairlines, axes, slider tracks
let inkRgb: rgb = (226, 234, 222) // primary text
let inkMutedRgb: rgb = (140, 154, 140) // secondary text

// Accents
let accentRgb: rgb = (142, 230, 140) // ectoplasm green: brand mark, knobs, thumbs, V profile line
let activeRgb: rgb = (236, 246, 228) // the thing under your hand: puck, pickups, Hopf curve
let oscillationRgb: rgb = (200, 255, 150) // measured self-oscillation
let fillRgb: rgb = (46, 72, 50) // V profile fill
let warnRgb: rgb = (236, 150, 112) // a typed value that couldn't be read

let slide = hex(slideRgb)
let glass = hex(glassRgb)
let well = hex(wellRgb)
let rule = hex(ruleRgb)
let ink = hex(inkRgb)
let inkMuted = hex(inkMutedRgb)
let accent = hex(accentRgb)
let warn = hex(warnRgb)
let active = hex(activeRgb)
let oscillation = hex(oscillationRgb)

let regionColour = (r: GrayScottTheory.region): rgb =>
  switch r {
  | Chaos => (214, 168, 104) // amber
  | Drones => (142, 230, 140) // ectoplasm green
  | Stripes => (186, 216, 112) // chartreuse
  | Damped => (112, 128, 110) // grey-green
  | Spots => (208, 200, 132) // olive-cream
  | Solitons => (150, 190, 120) // moss
  | Silent => slideRgb
  }

/// Region colours lifted toward the ink colour so small labels stay legible.
let labelColour = (r: GrayScottTheory.region): rgb => {
  let (red, green, blue) = regionColour(r)
  let lift = c => Float.toInt(Int.toFloat(c) +. (238.0 -. Int.toFloat(c)) *. 0.35)
  (lift(red), lift(green), lift(blue))
}

// Value ramp for V concentration, 0 → 1.
let rampStops: array<(float, rgb)> = [
  (0.00, wellRgb),
  (0.30, (30, 44, 31)),
  (0.55, (56, 96, 60)),
  (0.78, (112, 194, 112)),
  (1.00, (222, 255, 206)),
]

let lerp = (a, b, t) => Float.toInt(Int.toFloat(a) +. (Int.toFloat(b) -. Int.toFloat(a)) *. t)

/// 256-entry lookup table, flattened RGB.
let rampLut: array<int> = {
  let lut = []
  for i in 0 to 255 {
    let x = Int.toFloat(i) /. 255.0
    let rec find = j =>
      if j >= Array.length(rampStops) - 2 {
        j
      } else {
        let (next, _) = rampStops->Array.getUnsafe(j + 1)
        x <= next ? j : find(j + 1)
      }
    let j = find(0)
    let (x0, (r0, g0, b0)) = rampStops->Array.getUnsafe(j)
    let (x1, (r1, g1, b1)) = rampStops->Array.getUnsafe(j + 1)
    let t = Math.min(1.0, Math.max(0.0, (x -. x0) /. (x1 -. x0)))
    lut->Array.push(lerp(r0, r1, t))
    lut->Array.push(lerp(g0, g1, t))
    lut->Array.push(lerp(b0, b1, t))
  }
  lut
}

/// Typical V range in active regimes; values above saturate the profile.
let vFullScale = 0.45

// The culture in the Play page's dish (TuringDish.res)
let cultureRgb: rgb = (74, 150, 82)
