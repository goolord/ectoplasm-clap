// The ring as a culture in a petri dish. The 128 nodes go round the dish (node 0 at twelve
// o'clock, clockwise), and each generation of the cellular automaton (CellAutomaton.res) is a
// ring of cells: the newest at the rim, older ones growing inward, like rings in a culture.
// Injectors are marked outside the rim, pickups on it, and the hole in the middle says what
// the ring is tuned to.

open Web
module CA = CellAutomaton

let rings = 34 // generations shown, a little over a second
let hole = 30.0 // radius of the middle, design px
let margin = 11.0 // room outside the rim for the markers

type t = {
  element: element,
  ctx: ctx2d,
  size: int,
  scratch: element,
  image: imageData,
  map: CA.ints32,
  ca: CA.t,
  mutable latest: option<CmajorBindings.latticeFrame>,
  mutable caption: string,
  mutable dirty: bool,
  mutable invalidate: unit => unit,
}

let rim = size => Int.toFloat(size) /. 2.0 -. margin

/// Pixel → (generation, cell) for a dish `size` px across, at 1×.
let buildMap = size => {
  let map = CA.makeInts(size * size)
  let centre = Int.toFloat(size) /. 2.0
  let outer = rim(size)
  let ringWidth = (outer -. hole) /. Int.toFloat(rings)
  for py in 0 to size - 1 {
    for px in 0 to size - 1 {
      let dx = Int.toFloat(px) +. 0.5 -. centre
      let dy = Int.toFloat(py) +. 0.5 -. centre
      let r = Math.sqrt(dx *. dx +. dy *. dy)
      let entry = if r > outer || r < hole {
        CA.outside
      } else {
        let depth = (outer -. r) /. ringWidth
        let age = Math.Int.min(rings - 1, Float.toInt(depth))
        // clockwise from twelve o'clock, in cells
        let turn = Math.atan2(~y=dx, ~x=-.dy) /. (2.0 *. Math.Constants.pi)
        let along = (turn < 0.0 ? turn +. 1.0 : turn) *. Int.toFloat(CA.numCells)
        let cell = Math.Int.min(CA.numCells - 1, Float.toInt(along))
        // about half a pixel of gap between cells, both ways
        let arc = 2.0 *. Math.Constants.pi *. r /. Int.toFloat(CA.numCells)
        let radialGap = depth -. Math.floor(depth) < 0.5 /. ringWidth
        let angularGap = along -. Math.floor(along) < 0.5 /. arc
        radialGap || angularGap ? CA.gap : CA.index(~age, ~cell)
      }
      CA.setInt(map, py * size + px, entry)
    }
  }
  map
}

let setFrame = (dish, frame) => {
  dish.latest = Some(frame)
  dish.dirty = true
  dish.invalidate()
}

let setCaption = (dish, caption) =>
  if caption != dish.caption {
    dish.caption = caption
    dish.dirty = true
    dish.invalidate()
  }

let render = dish =>
  if dish.dirty {
    dish.dirty = false
    let ctx = dish.ctx
    let size = Int.toFloat(dish.size)
    let centre = size /. 2.0
    let outer = rim(dish.size)

    let scratchCtx = getContext2d(dish.scratch)
    CA.paint(dish.ca, dish.image, dish.map, ~pixels=dish.size * dish.size, ~background=Palette.glassRgb)
    Ctx.putImageData(scratchCtx, dish.image, 0, 0)
    Ctx.imageSmoothingEnabled(ctx, false)
    Ctx.drawImage(ctx, dish.scratch, 0.0, 0.0, size, size)

    // the dish's glass rim
    Ctx.beginPath(ctx)
    Ctx.arc(ctx, centre, centre, outer +. 1.5, 0.0, 2.0 *. Math.Constants.pi)
    Ctx.strokeStyle(ctx, Palette.css(Palette.accentRgb, 0.35))
    Ctx.lineWidth(ctx, 1.0)
    Ctx.stroke(ctx)
    Ctx.beginPath(ctx)
    Ctx.arc(ctx, centre, centre, hole -. 1.5, 0.0, 2.0 *. Math.Constants.pi)
    Ctx.strokeStyle(ctx, Palette.rule)
    Ctx.stroke(ctx)

    let at = (node, radius) => {
      let a = node /. Int.toFloat(CA.numCells) *. 2.0 *. Math.Constants.pi -. Math.Constants.pi /. 2.0
      (centre +. radius *. Math.cos(a), centre +. radius *. Math.sin(a))
    }
    switch dish.latest {
    | Some(frame) =>
      // injectors: wedges pointing in from outside the rim
      [frame.injectL, frame.injectR]->Array.forEach(node => {
        let (x0, y0) = at(node, outer +. 3.0)
        let (x1, y1) = at(node -. 1.6, outer +. 10.0)
        let (x2, y2) = at(node +. 1.6, outer +. 10.0)
        Ctx.beginPath(ctx)
        Ctx.moveTo(ctx, x0, y0)
        Ctx.lineTo(ctx, x1, y1)
        Ctx.lineTo(ctx, x2, y2)
        Ctx.closePath(ctx)
        Ctx.fillStyle(ctx, Palette.inkMuted)
        Ctx.fill(ctx)
      })
      // pickups: rings on the rim
      [frame.tapL, frame.tapR]->Array.forEach(node => {
        let (x, y) = at(node, outer +. 1.5)
        Ctx.beginPath(ctx)
        Ctx.arc(ctx, x, y, 3.5, 0.0, 2.0 *. Math.Constants.pi)
        Ctx.fillStyle(ctx, Palette.glass)
        Ctx.fill(ctx)
        Ctx.strokeStyle(ctx, Palette.active)
        Ctx.lineWidth(ctx, 1.5)
        Ctx.stroke(ctx)
      })
    | None => ()
    }

    Ctx.font(ctx, "600 11px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
    Ctx.textAlign(ctx, "center")
    Ctx.textBaseline(ctx, "middle")
    Ctx.fillStyle(ctx, Palette.accent)
    Ctx.fillText(ctx, dish.caption, centre, centre)
  }

let make = (~size: int, ~ca: CA.t) => {
  let (element, ctx) = makeCanvas(~width=size, ~height=size, ~className="dish")
  element->setAttribute(
    "aria-label",
    "The ring as a cellular automaton: the newest generation at the rim, older ones inward",
  )
  let (scratch, _, image) = CA.scratch(~width=size, ~height=size)
  {
    element,
    ctx,
    size,
    scratch,
    image,
    map: buildMap(size),
    ca,
    latest: None,
    caption: "",
    dirty: true,
    invalidate: () => (),
  }
}
