// The ring read as a one-dimensional cellular automaton: each of the 128 nodes is a cell, and each
// lattice snapshot (30 a second) is a generation. A cell is alive while its V stands above the
// rest of its generation: its deviation from the ring's median, against the recent range of
// those deviations (with a little hysteresis, so a ring at rest doesn't flicker). Measuring
// against the median keeps the ring's uniform swing — the resonance you hear — from flooding
// whole generations, and unlike the mean it isn't dragged around by one strong local
// excursion (which would light up all the rest of the ring at once)
// — what's left is what happens across the ring: pulses spreading from the
// injectors, patterns forming and colliding. Each generation also remembers how it got there,
// which is what makes it read like a CA:
// each generation also remembers how it got there, which is what makes it read like a CA:
//
//   0 empty   1 fading (alive the generation before)   2 alive   3 born this generation
//
// Views (PetriDish, and LatticeView's cell style) lay the history out as cells on screen. They
// build a map from each pixel of a 1× image to a (generation, cell) index once, then each
// generation is one pass over that map and a colour lookup — a few hundred thousand array reads,
// no canvas calls per cell.

open Web

let numCells = 128
let generations = 64

// typed arrays, unboxed
type bytes8
type ints32
@new external makeBytes: int => bytes8 = "Uint8Array"
@get_index external getByte: (bytes8, int) => int = ""
@set_index external setByte8: (bytes8, int, int) => unit = ""
@new external makeInts: int => ints32 = "Int32Array"
@get_index external getInt: (ints32, int) => int = ""
@set_index external setInt: (ints32, int, int) => unit = ""

let empty = 0
let fading = 1
let alive = 2
let born = 3

/// In a pixel map: a gap between cells, and outside the view's shape.
let gap = -1
let outside = -2

type t = {
  states: bytes8, // generations × numCells, a ring buffer of rows
  mutable head: int, // row of the newest generation
  mutable rangeLow: float,
  mutable rangeHigh: float,
  mutable started: bool,
}

let make = () => {
  states: makeBytes(generations * numCells),
  head: 0,
  rangeLow: 0.0,
  rangeHigh: 0.0,
  started: false,
}

// Smallest range of deviations the threshold works over, so a ring at rest (or a tiny residue)
// isn't amplified into a field of flickering cells.
let minimumSpan = 0.012

/// Adds a generation from a lattice snapshot.
let push = (ca, v: array<float>) => {
  let sorted = v->Array.copy
  sorted->Array.sort((a, b) => a -. b)
  let median = sorted->Array.getUnsafe(numCells / 2)
  let deviation = v->Array.map(x => x -. median)
  let lo = deviation->Array.reduce(Float.Constants.positiveInfinity, Math.min)
  let hi = deviation->Array.reduce(Float.Constants.negativeInfinity, Math.max)
  if !ca.started {
    ca.rangeLow = lo
    ca.rangeHigh = hi
    ca.started = true
  }
  // Expand at once, contract slowly (~8 s): as a disturbance dies away its colonies die with it,
  // rather than the threshold zooming in on what's left and keeping half the ring alive.
  ca.rangeLow = lo < ca.rangeLow ? lo : ca.rangeLow +. (lo -. ca.rangeLow) *. 0.004
  ca.rangeHigh = hi > ca.rangeHigh ? hi : ca.rangeHigh +. (hi -. ca.rangeHigh) *. 0.004
  let span = Math.max(minimumSpan, ca.rangeHigh -. ca.rangeLow)
  let low = (ca.rangeHigh +. ca.rangeLow) /. 2.0 -. span /. 2.0

  let previous = ca.head
  ca.head = mod(ca.head - 1 + generations, generations)
  let row = ca.head * numCells
  let previousRow = previous * numCells
  for i in 0 to numCells - 1 {
    let n = (deviation->Array.getUnsafe(i) -. low) /. span
    let wasAlive = getByte(ca.states, previousRow + i) >= alive
    // hysteresis: born above 0.62, stays alive above 0.5
    let isAlive = n > (wasAlive ? 0.5 : 0.62)
    setByte8(
      ca.states,
      row + i,
      isAlive ? (wasAlive ? alive : born) : (wasAlive ? fading : empty),
    )
  }
}

/// State of a cell, `age` generations ago (0 is the newest).
let stateAt = (ca, ~age, ~cell) => getByte(ca.states, mod(ca.head + age, generations) * numCells + cell)

/// Index for a pixel map entry.
let index = (~age, ~cell) => age * numCells + cell

// colours as packed bytes for the fill loop
let colourBytes = {
  let bytes = []
  Palette.cellColours->Array.forEach(((r, g, b)) => {
    bytes->Array.push(r)
    bytes->Array.push(g)
    bytes->Array.push(b)
  })
  bytes
}

/// Paints the history into image (width × height at 1×) through a pixel map built by the view.
/// `background` is the colour outside the view's shape.
let paint = (ca, image: imageData, map: ints32, ~pixels: int, ~background: Palette.rgb) => {
  let out = imageBytes(image)
  let (gr, gg, gb) = Palette.cellGapRgb
  let (br, bg, bb) = background
  for p in 0 to pixels - 1 {
    let entry = getInt(map, p)
    let o = p * 4
    if entry >= 0 {
      let age = entry / numCells
      let cell = entry - age * numCells
      let c = stateAt(ca, ~age, ~cell) * 3
      setByte(out, o, colourBytes->Array.getUnsafe(c))
      setByte(out, o + 1, colourBytes->Array.getUnsafe(c + 1))
      setByte(out, o + 2, colourBytes->Array.getUnsafe(c + 2))
    } else if entry == gap {
      setByte(out, o, gr)
      setByte(out, o + 1, gg)
      setByte(out, o + 2, gb)
    } else {
      setByte(out, o, br)
      setByte(out, o + 1, bg)
      setByte(out, o + 2, bb)
    }
    setByte(out, o + 3, 255)
  }
}

/// A 1× scratch canvas and image the views paint into before scaling up to their own canvas
/// (nearest-neighbour, so cells stay crisp blocks).
let scratch = (~width, ~height) => {
  let canvas = createElement("canvas")
  setCanvasWidth(canvas, width)
  setCanvasHeight(canvas, height)
  let ctx = getContext2d(canvas)
  (canvas, ctx, Ctx.createImageData(ctx, width, height))
}
