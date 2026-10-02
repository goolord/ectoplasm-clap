// Cold steel with an ectoplasm glow: near-neutral gunmetal grounds with a faint blue cast, a
// green accent, and concentration rendered as a value ramp from blackened steel up to a pale
// green glow.
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
let slideRgb: rgb = (17, 20, 24) // page ground
let glassRgb: rgb = (25, 30, 36) // panel ground
let wellRgb: rgb = (11, 13, 16) // kymograph ground
let ruleRgb: rgb = (43, 51, 60) // hairlines, axes, slider tracks
let inkRgb: rgb = (221, 228, 234) // primary text
let inkMutedRgb: rgb = (138, 150, 163) // secondary text

// Accents
let accentRgb: rgb = (137, 222, 152) // ectoplasm green: brand mark, knobs, thumbs, V profile line
let activeRgb: rgb = (230, 238, 244) // the thing under your hand: puck, pickups, Hopf curve
let oscillationRgb: rgb = (164, 240, 170) // measured self-oscillation
let fillRgb: rgb = (74, 90, 108) // V profile fill

let slide = hex(slideRgb)
let glass = hex(glassRgb)
let well = hex(wellRgb)
let rule = hex(ruleRgb)
let ink = hex(inkRgb)
let inkMuted = hex(inkMutedRgb)
let accent = hex(accentRgb)
let active = hex(activeRgb)
let oscillation = hex(oscillationRgb)

let regionColour = (r: GrayScottTheory.region): rgb =>
  switch r {
  | Chaos => (196, 182, 166) // pewter
  | Drones => (226, 234, 240) // polished steel
  | Stripes => (127, 186, 180) // blued-teal
  | Damped => (98, 114, 132) // slate
  | Spots => (160, 160, 196) // cold lavender-grey
  | Solitons => (120, 164, 200) // steel blue
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
  (0.30, (38, 47, 58)),
  (0.55, (76, 95, 115)),
  (0.78, (128, 170, 158)),
  (1.00, (214, 246, 222)),
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
