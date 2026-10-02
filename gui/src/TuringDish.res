// The Play page's dish: a 2D Gray-Scott culture (turing-gl.js, on the GPU) grown from the
// plugin's own F and K, with the 128-node resonator ring drawn through it. Where the ring is
// ringing, the culture's blobs along it light up, and the ring's activity is fed into the
// culture there, so playing reshapes the pattern along the ring.
//
// The culture uses a pattern-forming diffusion ratio (Dv/Du = 0.2) whatever the plugin's is: it
// shows the chemistry the Color knob picks — labyrinths, worms, spots, or nothing at all — in
// the form reaction-diffusion takes in two dimensions. The sound itself comes from the ring.

open Web

type floats
@new external makeFloats: int => floats = "Float32Array"
@set_index external setFloat: (floats, int, float) => unit = ""
@get_index external getFloat: (floats, int) => float = ""

type colours = {
  ground: array<int>,
  panel: array<int>,
  rim: array<int>,
  culture: array<int>,
  glowColour: array<int>,
}

type culture
@module("./turing-gl.js") external createCulture: (element, colours) => culture = "createCulture"
@send external setActivity: (culture, floats) => unit = "setActivity"
@send external sprinkle: (culture, int) => unit = "sprinkle"
@send external step: (culture, int, float, float, float) => unit = "step"
@send external renderCulture: (culture, float) => unit = "render"
@send external dispose: culture => unit = "dispose"
@get @return(nullable) external replacementCanvas: culture => option<element> = "canvas"

let numCells = 128
let stepsPerFrame = 20 // ~600 culture steps a second at 30 snapshots a second
let injectStrength = 0.03
let framesBetweenSprinkles = 90

type t = {
  element: element,
  culture: culture,
  activity: floats,
  mutable feed: float,
  mutable kill: float,
  mutable level: float,
  mutable span: float,
  mutable frames: int,
  mutable pending: bool, // a snapshot arrived since the last render
  mutable invalidate: unit => unit,
}

let rgb = ((r, g, b): Palette.rgb) => [r, g, b]

let make = (~size: int) => {
  let canvas = createElement("canvas")
  // the GPU draws at twice the design size, for crisp edges at any zoom
  setCanvasWidth(canvas, size * 2)
  setCanvasHeight(canvas, size * 2)
  setStyle(canvas, "width", Int.toString(size) ++ "px")
  setStyle(canvas, "height", Int.toString(size) ++ "px")
  setClassName(canvas, "dish")
  canvas->setAttribute(
    "aria-label",
    "The chemistry as a culture in a dish, lit up along the ring where the sound is ringing",
  )
  let culture = createCulture(
    canvas,
    {
      ground: rgb(Palette.wellRgb),
      panel: rgb(Palette.glassRgb),
      rim: rgb(Palette.accentRgb),
      culture: rgb(Palette.cultureRgb),
      glowColour: rgb(Palette.oscillationRgb),
    },
  )
  {
    element: culture->replacementCanvas->Option.getOr(canvas),
    culture,
    activity: makeFloats(numCells),
    feed: CmajorBindings.Param.spec(Feed).init,
    kill: CmajorBindings.Param.spec(Kill).init,
    level: 0.0,
    span: 0.004,
    frames: 0,
    pending: true,
    invalidate: () => (),
  }
}

let setChemistry = (dish, ~f, ~k) => {
  dish.feed = f
  dish.kill = k
}

/// A lattice snapshot: how strongly each node of the ring is ringing. A node's deviation from
/// the ring's median shows local activity; the output level adds the ring's uniform swing,
/// which is most of what you hear. Fast attack, a gentle fade.
let setFrame = (dish, frame: CmajorBindings.latticeFrame) => {
  let v = frame.v
  let sorted = v->Array.copy
  sorted->Array.sort((a, b) => a -. b)
  let median = sorted->Array.getUnsafe(numCells / 2)
  let largest = v->Array.reduce(0.0, (m, x) => Math.max(m, Math.abs(x -. median)))
  // the range adapts slowly, so a fading disturbance fades on screen too
  dish.span = Math.max(0.004, largest > dish.span ? largest : dish.span +. (largest -. dish.span) *. 0.01)
  let uniform = Math.min(1.0, frame.level *. 2.5)
  for i in 0 to numCells - 1 {
    let local = Math.abs(v->Array.getUnsafe(i) -. median) /. dish.span
    let target = Math.min(1.0, 0.6 *. local +. 0.7 *. uniform)
    let previous = getFloat(dish.activity, i)
    setFloat(dish.activity, i, target > previous ? target : previous *. 0.9)
  }
  dish.level = frame.level
  dish.pending = true
  dish.invalidate()
}

/// Grows the culture by the snapshots that arrived and draws it. Called only while the Play
/// page is on show, so a hidden dish costs nothing.
let render = dish =>
  if dish.pending {
    dish.pending = false
    dish.frames = dish.frames + 1
    if mod(dish.frames, framesBetweenSprinkles) == 0 {
      dish.culture->sprinkle(3)
    }
    dish.culture->setActivity(dish.activity)
    dish.culture->step(stepsPerFrame, dish.feed, dish.kill, injectStrength)
    dish.culture->renderCulture(Math.min(1.0, dish.level *. 2.0))
  }

let stop = dish => dish.culture->dispose
