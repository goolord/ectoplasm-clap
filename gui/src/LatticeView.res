// Real-time view of chemical V on the 128-node ring.
//
// Top: a kymograph — the ring unrolled left→right, newest snapshot at the
// top, history scrolling down (~7 s at 30 snapshots/s). Its colour range
// adapts to the recent min/max of V so that ripples on a near-uniform field
// stay visible; the profile underneath shows absolute concentration.
// Bottom: the current V profile with the two injectors and the two pickups.
// Pickups can be dragged to set Pickup distance.

open Web
module Bindings = CmajorBindings

let numNodes = 128
let maxPickupDistance = 12.0 // nodes — matches the processor constant

let width = 468
let kymoHeight = 222
let profileHeight = 92
let historyRows = kymoHeight

type t = {
  element: element,
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

let nodeToX = (node: float) => node /. Int.toFloat(numNodes) *. Int.toFloat(width)
let xToNode = (x: float) => x /. Int.toFloat(width) *. Int.toFloat(numNodes)

// Smallest colour span, so dither-level noise on a flat field isn't blown up.
let minimumSpan = 0.03

let adaptRange = (view, frame: Bindings.latticeFrame) => {
  let lo = frame.v->Array.reduce(Float.Constants.positiveInfinity, Math.min)
  let hi = frame.v->Array.reduce(Float.Constants.negativeInfinity, Math.max)
  // Expand instantly, contract over ~1 s.
  view.rangeLow = lo < view.rangeLow ? lo : view.rangeLow +. (lo -. view.rangeLow) *. 0.02
  view.rangeHigh = hi > view.rangeHigh ? hi : view.rangeHigh +. (hi -. view.rangeHigh) *. 0.02
}

let pushFrame = (view, frame: Bindings.latticeFrame) => {
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

let drawMarkerLine = (ctx, x, colour, dashed) => {
  Ctx.save(ctx)
  Ctx.strokeStyle(ctx, colour)
  Ctx.lineWidth(ctx, 1.0)
  if dashed {
    Ctx.setLineDash(ctx, [3.0, 4.0])
  }
  Ctx.beginPath(ctx)
  Ctx.moveTo(ctx, x, 0.0)
  Ctx.lineTo(ctx, x, Int.toFloat(kymoHeight))
  Ctx.stroke(ctx)
  Ctx.restore(ctx)
}

let renderKymograph = view => {
  let ctx = view.kymoCtx
  let w = Int.toFloat(width)
  let h = Int.toFloat(kymoHeight)
  Ctx.fillStyle(ctx, Palette.well)
  Ctx.fillRect(ctx, 0.0, 0.0, w, h)

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

  switch view.latest {
  | Some(frame) =>
    drawMarkerLine(ctx, nodeToX(frame.injectL), Palette.css(Palette.inkRgb, 0.4), true)
    drawMarkerLine(ctx, nodeToX(frame.injectR), Palette.css(Palette.inkRgb, 0.4), true)
    drawMarkerLine(ctx, nodeToX(frame.tapL), Palette.css(Palette.activeRgb, 0.75), false)
    drawMarkerLine(ctx, nodeToX(frame.tapR), Palette.css(Palette.activeRgb, 0.75), false)
  | None => ()
  }
}

let renderProfile = view => {
  let ctx = view.profileCtx
  let w = Int.toFloat(width)
  let h = Int.toFloat(profileHeight)
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
      let x = nodeToX(node)
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
      let x = nodeToX(node)
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
  setTextContent(timeAgo, "7 s ago")
  kymoWrap->appendChild(timeNow)
  kymoWrap->appendChild(timeAgo)

  element->appendChild(kymoWrap)
  element->appendChild(profileCanvas)

  let view = {
    element,
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
      let node = xToNode(x)
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
      let dl = Math.abs(x -. nodeToX(frame.tapL))
      let dr = Math.abs(x -. nodeToX(frame.tapR))
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
