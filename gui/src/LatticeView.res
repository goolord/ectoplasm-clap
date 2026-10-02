// Real-time view of chemical V on the 128-node ring.
//
// Top: a kymograph — the ring unrolled left→right, newest snapshot at the
// top, history scrolling down (~7 s at 30 snapshots/s). Its colour range
// adapts to the recent min/max of V so that ripples on a near-uniform field
// stay visible; the profile underneath shows absolute concentration.
// Bottom: the current V profile with the two injectors and the two pickups.
// Pickups can be dragged to set Pickup distance.
//
// Given a CellAutomaton, the history is drawn as its cells instead: square blocks, newest
// generation at the top, born cells glowing and dying ones fading (the Play page).

open Web
module Bindings = CmajorBindings

let numNodes = 128
let maxPickupDistance = 12.0 // nodes — matches the processor constant

// ~7 s of history at 30 snapshots/s, whatever size the view is drawn at
let historyRows = 210

// The cell style: a pixel map into the automaton's history, and a 1× image to paint it into.
type cells = {
  ca: CellAutomaton.t,
  map: CellAutomaton.ints32,
  scratch: element,
  image: imageData,
}

type t = {
  element: element,
  cells: option<cells>,
  width: int,
  kymoHeight: int,
  profileHeight: int,
  kymoCtx: ctx2d,
  profileCanvas: element,
  profileCtx: ctx2d,
  history: element, // numNodes × historyRows backing canvas
  historyCtx: ctx2d,
  rowImage: imageData,
  emptyNote: element,
  mutable head: int, // row holding the newest snapshot
  mutable rangeLow: float,
  mutable rangeHigh: float,
  mutable filledRows: int,
  mutable latest: option<Bindings.latticeFrame>,
  mutable dirty: bool,
  mutable dragging: option<[#left | #right]>,
  // asks the app for a repaint (it renders on demand, not every frame)
  mutable invalidate: unit => unit,
}

let markDirty = view => {
  view.dirty = true
  view.invalidate()
}

let nodeToX = (view, node: float) => node /. Int.toFloat(numNodes) *. Int.toFloat(view.width)
let xToNode = (view, x: float) => x /. Int.toFloat(view.width) *. Int.toFloat(numNodes)

// Smallest colour span, so dither-level noise on a flat field isn't blown up.
let minimumSpan = 0.03

let adaptRange = (view, frame: Bindings.latticeFrame) => {
  let lo = frame.v->Array.reduce(Float.Constants.positiveInfinity, Math.min)
  let hi = frame.v->Array.reduce(Float.Constants.negativeInfinity, Math.max)
  // Expand instantly, contract over ~1 s.
  view.rangeLow = lo < view.rangeLow ? lo : view.rangeLow +. (lo -. view.rangeLow) *. 0.02
  view.rangeHigh = hi > view.rangeHigh ? hi : view.rangeHigh +. (hi -. view.rangeHigh) *. 0.02
}

/// Pixel → (generation, cell) for the history area: square cells across the width, the newest
/// generation in the top row, a pixel of gap where cells are big enough to show one.
let buildCellMap = (~width, ~height) => {
  let map = CellAutomaton.makeInts(width * height)
  let cellWidth = Int.toFloat(width) /. Int.toFloat(CellAutomaton.numCells)
  let showGaps = cellWidth >= 3.0
  for y in 0 to height - 1 {
    let rowF = (Int.toFloat(y) +. 0.5) /. cellWidth
    let age = Float.toInt(rowF)
    for x in 0 to width - 1 {
      let colF = (Int.toFloat(x) +. 0.5) /. cellWidth
      let cell = Math.Int.min(CellAutomaton.numCells - 1, Float.toInt(colF))
      let entry = if age >= CellAutomaton.generations {
        CellAutomaton.outside
      } else if showGaps && (colF -. Math.floor(colF) < 1.0 /. cellWidth || rowF -. Math.floor(rowF) < 1.0 /. cellWidth) {
        CellAutomaton.gap
      } else {
        CellAutomaton.index(~age, ~cell)
      }
      CellAutomaton.setInt(map, y * width + x, entry)
    }
  }
  map
}

let rec pushFrame = (view, frame: Bindings.latticeFrame) =>
  switch view.cells {
  | Some(_) =>
    // the automaton is pushed by its owner; this view only needs the latest frame
    if view.latest->Option.isNone {
      setStyle(view.emptyNote, "display", "none")
    }
    view.latest = Some(frame)
    markDirty(view)
  | None => pushSmooth(view, frame)
  }

and pushSmooth = (view, frame: Bindings.latticeFrame) => {
  adaptRange(view, frame)
  let span = Math.max(minimumSpan, view.rangeHigh -. view.rangeLow)
  let centre = (view.rangeHigh +. view.rangeLow) /. 2.0
  let low = centre -. span /. 2.0
  let bytes = imageBytes(view.rowImage)
  let lut = Palette.rampLut
  for i in 0 to numNodes - 1 {
    let v = frame.v->Array.get(i)->Option.getOr(0.0)
    let n = Math.min(1.0, Math.max(0.0, (v -. low) /. span))
    let idx = Float.toInt(n *. 255.0) * 3
    setByte(bytes, i * 4, lut->Array.getUnsafe(idx))
    setByte(bytes, i * 4 + 1, lut->Array.getUnsafe(idx + 1))
    setByte(bytes, i * 4 + 2, lut->Array.getUnsafe(idx + 2))
    setByte(bytes, i * 4 + 3, 255)
  }
  view.head = mod(view.head - 1 + historyRows, historyRows)
  Ctx.putImageData(view.historyCtx, view.rowImage, 0, view.head)
  view.filledRows = Math.Int.min(historyRows, view.filledRows + 1)
  if view.latest->Option.isNone {
    setStyle(view.emptyNote, "display", "none")
  }
  view.latest = Some(frame)
  markDirty(view)
}

let drawMarkerLine = (ctx, x, height, colour, dashed) => {
  Ctx.save(ctx)
  Ctx.strokeStyle(ctx, colour)
  Ctx.lineWidth(ctx, 1.0)
  if dashed {
    Ctx.setLineDash(ctx, [3.0, 4.0])
  }
  Ctx.beginPath(ctx)
  Ctx.moveTo(ctx, x, 0.0)
  Ctx.lineTo(ctx, x, height)
  Ctx.stroke(ctx)
  Ctx.restore(ctx)
}

let renderKymograph = view => {
  let ctx = view.kymoCtx
  let w = Int.toFloat(view.width)
  let h = Int.toFloat(view.kymoHeight)
  Ctx.fillStyle(ctx, Palette.well)
  Ctx.fillRect(ctx, 0.0, 0.0, w, h)

  switch view.cells {
  | Some({ca, map, scratch, image}) =>
    CellAutomaton.paint(ca, image, map, ~pixels=view.width * view.kymoHeight, ~background=Palette.wellRgb)
    Ctx.putImageData(getContext2d(scratch), image, 0, 0)
    Ctx.imageSmoothingEnabled(ctx, false)
    Ctx.drawImage(ctx, scratch, 0.0, 0.0, w, h)
  | None =>

  // Rows [head, historyRows) are newest→older, then wrap to [0, head).
  let rowScale = h /. Int.toFloat(historyRows)
  let firstSpan = historyRows - view.head
  Ctx.imageSmoothingEnabled(ctx, true)
  Ctx.drawImageRegion(
    ctx,
    view.history,
    0.0,
    Int.toFloat(view.head),
    Int.toFloat(numNodes),
    Int.toFloat(firstSpan),
    0.0,
    0.0,
    w,
    Int.toFloat(firstSpan) *. rowScale,
  )
  if view.head > 0 {
    Ctx.drawImageRegion(
      ctx,
      view.history,
      0.0,
      0.0,
      Int.toFloat(numNodes),
      Int.toFloat(view.head),
      0.0,
      Int.toFloat(firstSpan) *. rowScale,
      w,
      Int.toFloat(view.head) *. rowScale,
    )
  }
  }

  switch view.latest {
  | Some(frame) =>
    drawMarkerLine(ctx, nodeToX(view, frame.injectL), h, Palette.css(Palette.inkRgb, 0.4), true)
    drawMarkerLine(ctx, nodeToX(view, frame.injectR), h, Palette.css(Palette.inkRgb, 0.4), true)
    drawMarkerLine(ctx, nodeToX(view, frame.tapL), h, Palette.css(Palette.activeRgb, 0.75), false)
    drawMarkerLine(ctx, nodeToX(view, frame.tapR), h, Palette.css(Palette.activeRgb, 0.75), false)
  | None => ()
  }
}

let renderProfile = view => {
  let ctx = view.profileCtx
  let w = Int.toFloat(view.width)
  let h = Int.toFloat(view.profileHeight)
  let top = 20.0
  let bottom = h -. 6.0
  Ctx.fillStyle(ctx, Palette.glass)
  Ctx.fillRect(ctx, 0.0, 0.0, w, h)
  Ctx.fillStyle(ctx, Palette.rule)
  Ctx.fillRect(ctx, 0.0, bottom, w, 1.0)

  switch view.latest {
  | None => ()
  | Some(frame) =>
    let yOf = v => bottom -. Math.min(1.0, v /. Palette.vFullScale) *. (bottom -. top)
    let xOfNode = i => (Int.toFloat(i) +. 0.5) /. Int.toFloat(numNodes) *. w

    // Filled concentration profile
    Ctx.beginPath(ctx)
    Ctx.moveTo(ctx, 0.0, bottom)
    for i in 0 to numNodes - 1 {
      Ctx.lineTo(ctx, xOfNode(i), yOf(frame.v->Array.get(i)->Option.getOr(0.0)))
    }
    Ctx.lineTo(ctx, w, bottom)
    Ctx.closePath(ctx)
    Ctx.fillStyle(ctx, Palette.css(Palette.fillRgb, 0.55))
    Ctx.fill(ctx)

    Ctx.beginPath(ctx)
    for i in 0 to numNodes - 1 {
      let x = xOfNode(i)
      let y = yOf(frame.v->Array.get(i)->Option.getOr(0.0))
      i == 0 ? Ctx.moveTo(ctx, x, y) : Ctx.lineTo(ctx, x, y)
    }
    Ctx.strokeStyle(ctx, Palette.accent)
    Ctx.lineWidth(ctx, 1.5)
    Ctx.stroke(ctx)

    Ctx.font(ctx, "10px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
    Ctx.textAlign(ctx, "center")
    Ctx.textBaseline(ctx, "top")

    // Injectors: small downward wedges on the top edge
    // Labels sit on the side away from each injector's pickup.
    [(frame.injectL, "In L", -16.0), (frame.injectR, "In R", 16.0)]->Array.forEach(((
      node,
      label,
      offset,
    )) => {
      let x = nodeToX(view, node)
      Ctx.beginPath(ctx)
      Ctx.moveTo(ctx, x -. 4.0, 2.0)
      Ctx.lineTo(ctx, x +. 4.0, 2.0)
      Ctx.lineTo(ctx, x, 8.0)
      Ctx.closePath(ctx)
      Ctx.fillStyle(ctx, Palette.inkMuted)
      Ctx.fill(ctx)
      Ctx.fillText(ctx, label, x +. offset, 1.0)
    })

    // Pickups: draggable rings riding on the profile
    let sample = node => {
      let i = Float.toInt(Math.floor(node))
      let t = node -. Math.floor(node)
      let a = frame.v->Array.get(mod(i + numNodes, numNodes))->Option.getOr(0.0)
      let b = frame.v->Array.get(mod(i + 1, numNodes))->Option.getOr(0.0)
      a +. (b -. a) *. t
    }
    [(frame.tapL, "Out L", #left), (frame.tapR, "Out R", #right)]->Array.forEach(((
      node,
      label,
      side,
    )) => {
      let x = nodeToX(view, node)
      let y = yOf(sample(node))
      let active = view.dragging == Some(side)
      Ctx.beginPath(ctx)
      Ctx.arc(ctx, x, y, active ? 6.5 : 5.0, 0.0, 2.0 *. Math.Constants.pi)
      Ctx.fillStyle(ctx, Palette.glass)
      Ctx.fill(ctx)
      Ctx.strokeStyle(ctx, Palette.active)
      Ctx.lineWidth(ctx, 2.0)
      Ctx.stroke(ctx)
      Ctx.fillStyle(ctx, Palette.active)
      Ctx.fillText(ctx, label, x +. (side == #left ? 18.0 : -18.0), 1.0)
    })
  }
}

let render = view =>
  if view.dirty {
    view.dirty = false
    renderKymograph(view)
    renderProfile(view)
  }

let make = (
  ~width: int,
  ~kymoHeight: int,
  ~profileHeight: int,
  ~cells: option<CellAutomaton.t>=?,
  ~onPickupDistance: float => unit,
  ~onGestureStart: unit => unit,
  ~onGestureEnd: unit => unit,
) => {
  let element = div(~className="lattice")
  let (kymo, kymoCtx) = makeCanvas(~width, ~height=kymoHeight, ~className="kymograph")
  let (profileCanvas, profileCtx) = makeCanvas(
    ~width,
    ~height=profileHeight,
    ~className="profile",
  )
  setAttribute(kymo, "aria-label", "Chemical V on the ring over the last seven seconds")
  setAttribute(
    profileCanvas,
    "aria-label",
    "Current V profile. Drag an output marker to change pickup distance.",
  )

  let history = createElement("canvas")
  setCanvasWidth(history, numNodes)
  setCanvasHeight(history, historyRows)
  let historyCtx = getContext2d(history)
  Ctx.fillStyle(historyCtx, Palette.well)
  Ctx.fillRect(historyCtx, 0.0, 0.0, Int.toFloat(numNodes), Int.toFloat(historyRows))

  let kymoWrap = div(~className="kymograph-wrap")
  let emptyNote = div(~className="empty-note")
  setTextContent(emptyNote, "Start audio to watch the lattice react.")
  kymoWrap->appendChild(kymo)
  kymoWrap->appendChild(emptyNote)
  let timeNow = div(~className="time-label time-now")
  setTextContent(timeNow, "now")
  let timeAgo = div(~className="time-label time-ago")
  let shownSeconds = switch cells {
  | Some(_) =>
    // square cells: as many generations as fit, at 30 a second
    Int.toFloat(kymoHeight) /. (Int.toFloat(width) /. Int.toFloat(CellAutomaton.numCells)) /. 30.0
  | None => Int.toFloat(historyRows) /. 30.0
  }
  setTextContent(timeAgo, Float.toFixed(shownSeconds, ~digits=shownSeconds < 2.0 ? 1 : 0) ++ " s ago")
  kymoWrap->appendChild(timeNow)
  kymoWrap->appendChild(timeAgo)

  element->appendChild(kymoWrap)
  element->appendChild(profileCanvas)

  let view = {
    element,
    cells: cells->Option.map(ca => {
      let (scratch, _, image) = CellAutomaton.scratch(~width, ~height=kymoHeight)
      {ca, map: buildCellMap(~width, ~height=kymoHeight), scratch, image}
    }),
    width,
    kymoHeight,
    profileHeight,
    kymoCtx,
    profileCanvas,
    profileCtx,
    history,
    historyCtx,
    rowImage: Ctx.createImageData(historyCtx, numNodes, 1),
    emptyNote,
    head: 0,
    rangeLow: 0.0,
    rangeHigh: Palette.vFullScale,
    filledRows: 0,
    latest: None,
    dirty: true,
    dragging: None,
    invalidate: () => (),
  }

  let distanceFor = (side, x) =>
    switch view.latest {
    | None => None
    | Some(frame) =>
      let node = xToNode(view, x)
      let nodes = switch side {
      | #left => node -. frame.injectL
      | #right => frame.injectR -. node
      }
      Some(Math.min(1.0, Math.max(0.0, nodes /. maxPickupDistance)))
    }

  profileCanvas->addEventListener("pointerdown", ev =>
    switch view.latest {
    | None => ()
    | Some(frame) =>
      let (x, _) = localPoint(profileCanvas, ev, ~width=Int.toFloat(width), ~height=Int.toFloat(profileHeight))
      let dl = Math.abs(x -. nodeToX(view, frame.tapL))
      let dr = Math.abs(x -. nodeToX(view, frame.tapR))
      let side = dl <= dr ? #left : #right
      if Math.min(dl, dr) < 24.0 {
        preventDefault(ev)
        setPointerCapture(profileCanvas, pointerId(ev))
        view.dragging = Some(side)
        markDirty(view)
        onGestureStart()
        distanceFor(side, x)->Option.forEach(onPickupDistance)
      }
    }
  )
  profileCanvas->addEventListener("pointermove", ev =>
    switch view.dragging {
    | Some(side) =>
      let (x, _) = localPoint(profileCanvas, ev, ~width=Int.toFloat(width), ~height=Int.toFloat(profileHeight))
      distanceFor(side, x)->Option.forEach(onPickupDistance)
    | None => ()
    }
  )
  let finish = ev =>
    if view.dragging->Option.isSome {
      view.dragging = None
      markDirty(view)
      releasePointerCapture(profileCanvas, pointerId(ev))
      onGestureEnd()
    }
  profileCanvas->addEventListener("pointerup", finish)
  profileCanvas->addEventListener("pointercancel", finish)

  view
}
