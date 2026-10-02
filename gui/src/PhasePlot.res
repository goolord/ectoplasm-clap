// Interactive F×K phase plane.
//
//  * Region tint: analytic classification (GrayScottTheory.classify).
//  * Dot field: measured response of the real processor (MeasuredMap); dot
//    size is how long it rings after the input stops, and a ring around a dot
//    means it kept oscillating on its own.
//  * Solid curve: saddle-node (above it the homogeneous state is gone).
//    Dashed curve: Hopf (left of it the homogeneous state oscillates).
//  * Drag the puck, or focus the plot and use the arrow keys
//    (Shift for fine steps).

open Web
module T = GrayScottTheory

let width = 372
let height = 316
let marginLeft = 44.0
let marginRight = 12.0
let marginTop = 12.0
let marginBottom = 34.0

let plotW = Int.toFloat(width) -. marginLeft -. marginRight
let plotH = Int.toFloat(height) -. marginTop -. marginBottom

let xOfF = f => marginLeft +. (f -. T.fMin) /. (T.fMax -. T.fMin) *. plotW
let yOfK = k => marginTop +. (1.0 -. (k -. T.kMin) /. (T.kMax -. T.kMin)) *. plotH
let fOfX = x => T.fMin +. (x -. marginLeft) /. plotW *. (T.fMax -. T.fMin)
let kOfY = y => T.kMin +. (1.0 -. (y -. marginTop) /. plotH) *. (T.kMax -. T.kMin)

let clampF = f => Math.min(T.fMax, Math.max(T.fMin, f))
let clampK = k => Math.min(T.kMax, Math.max(T.kMin, k))

type t = {
  element: element,
  canvas: element,
  ctx: ctx2d,
  background: element,
  regionLabel: element,
  regionHint: element,
  valueLabel: element,
  resonanceLabel: element,
  mutable f: float,
  mutable k: float,
  mutable speed: float,
  mutable dragging: bool,
  mutable dirty: bool,
  // asks the app for a repaint (it renders on demand, not every frame)
  mutable invalidate: unit => unit,
}

let markDirty = plot => {
  plot.dirty = true
  plot.invalidate()
}

// ---------------------------------------------------------------------------
// Static layer, rendered once into an offscreen canvas.

let paintRegions = (ctx: ctx2d) => {
  let w = Float.toInt(plotW)
  let h = Float.toInt(plotH)
  let image = Ctx.createImageData(ctx, w, h)
  let bytes = imageBytes(image)
  for py in 0 to h - 1 {
    let k = kOfY(marginTop +. Int.toFloat(py) +. 0.5)
    for px in 0 to w - 1 {
      let f = fOfX(marginLeft +. Int.toFloat(px) +. 0.5)
      let (r, g, b) = Palette.regionColour(T.classify(~f, ~k))
      let (r0, g0, b0) = Palette.glassRgb
      // Blend 13% of the region colour over the panel ground.
      let mix = (c, base) => Float.toInt(Int.toFloat(base) +. (Int.toFloat(c) -. Int.toFloat(base)) *. 0.13)
      let i = (py * w + px) * 4
      setByte(bytes, i, mix(r, r0))
      setByte(bytes, i + 1, mix(g, g0))
      setByte(bytes, i + 2, mix(b, b0))
      setByte(bytes, i + 3, 255)
    }
  }
  image
}

let paintMeasured = (ctx: ctx2d) => {
  let cols = MeasuredMap.columns
  let rows = MeasuredMap.rows
  for row in 0 to rows - 1 {
    for col in 0 to cols - 1 {
      let i = row * cols + col
      let level = MeasuredMap.level->Array.getUnsafe(i)
      let oscillating = MeasuredMap.selfOscillating->Array.getUnsafe(i)
      // Cells sit on a uniform grid spanning the full F and K ranges.
      let f = T.fMin +. Int.toFloat(col) /. Int.toFloat(cols - 1) *. (T.fMax -. T.fMin)
      let k = T.kMin +. Int.toFloat(row) /. Int.toFloat(rows - 1) *. (T.kMax -. T.kMin)
      let x = xOfF(f)
      let y = yOfK(k)
      // Quiet cells are left out so the field reads as "where it answers".
      let radius = 0.5 +. level *. level *. 2.6
      if level > 0.15 {
        Ctx.beginPath(ctx)
        Ctx.arc(ctx, x, y, radius, 0.0, 2.0 *. Math.Constants.pi)
        Ctx.fillStyle(ctx, Palette.css(Palette.inkRgb, 0.08 +. level *. 0.42))
        Ctx.fill(ctx)
      }
      if oscillating {
        Ctx.beginPath(ctx)
        Ctx.arc(ctx, x, y, radius +. 2.2, 0.0, 2.0 *. Math.Constants.pi)
        Ctx.strokeStyle(ctx, Palette.oscillation)
        Ctx.lineWidth(ctx, 1.0)
        Ctx.stroke(ctx)
      }
    }
  }
}

let paintCurves = (ctx: ctx2d) => {
  Ctx.save(ctx)
  // Saddle-node: K = √F/2 − F
  Ctx.beginPath(ctx)
  let steps = 160
  for i in 0 to steps {
    let f = T.fMin +. Int.toFloat(i) /. Int.toFloat(steps) *. (T.fMax -. T.fMin)
    let k = clampK(T.saddleNodeK(f))
    i == 0 ? Ctx.moveTo(ctx, xOfF(f), yOfK(k)) : Ctx.lineTo(ctx, xOfF(f), yOfK(k))
  }
  Ctx.strokeStyle(ctx, Palette.css(Palette.inkRgb, 0.7))
  Ctx.lineWidth(ctx, 1.25)
  Ctx.stroke(ctx)

  // Hopf (lower branch), parameterised by K
  Ctx.beginPath(ctx)
  Ctx.setLineDash(ctx, [4.0, 3.0])
  let started = ref(false)
  for i in 0 to steps {
    let k = T.kMin +. Int.toFloat(i) /. Int.toFloat(steps) *. (0.0625 -. T.kMin)
    switch T.hopfF(k) {
    | Some(f) if f >= T.fMin && f <= T.fMax =>
      if started.contents {
        Ctx.lineTo(ctx, xOfF(f), yOfK(k))
      } else {
        Ctx.moveTo(ctx, xOfF(f), yOfK(k))
        started := true
      }
    | _ => ()
    }
  }
  Ctx.strokeStyle(ctx, Palette.css(Palette.activeRgb, 0.8))
  Ctx.stroke(ctx)
  Ctx.restore(ctx)
}

let paintAxes = (ctx: ctx2d) => {
  Ctx.strokeStyle(ctx, Palette.rule)
  Ctx.lineWidth(ctx, 1.0)
  Ctx.beginPath(ctx)
  Ctx.moveTo(ctx, marginLeft -. 0.5, marginTop)
  Ctx.lineTo(ctx, marginLeft -. 0.5, marginTop +. plotH +. 0.5)
  Ctx.lineTo(ctx, marginLeft +. plotW, marginTop +. plotH +. 0.5)
  Ctx.stroke(ctx)

  Ctx.fillStyle(ctx, Palette.inkMuted)
  Ctx.font(ctx, "10px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
  Ctx.textAlign(ctx, "center")
  Ctx.textBaseline(ctx, "top")
  [0.01, 0.03, 0.05, 0.07, 0.09]->Array.forEach(f => {
    let x = xOfF(f)
    Ctx.fillRect(ctx, x -. 0.5, marginTop +. plotH, 1.0, 4.0)
    Ctx.fillText(ctx, Float.toFixed(f, ~digits=2), x, marginTop +. plotH +. 6.0)
  })
  Ctx.fillText(ctx, "Feed F", marginLeft +. plotW /. 2.0, marginTop +. plotH +. 20.0)

  Ctx.save(ctx)
  Ctx.translate(ctx, 9.0, marginTop +. plotH /. 2.0)
  Ctx.rotate(ctx, -.Math.Constants.pi /. 2.0)
  Ctx.textAlign(ctx, "center")
  Ctx.textBaseline(ctx, "middle")
  Ctx.fillText(ctx, "Kill K", 0.0, 0.0)
  Ctx.restore(ctx)

  Ctx.textAlign(ctx, "right")
  Ctx.textBaseline(ctx, "middle")
  [0.045, 0.050, 0.055, 0.060, 0.065, 0.070]->Array.forEach(k => {
    let y = yOfK(k)
    Ctx.fillRect(ctx, marginLeft -. 4.0, y -. 0.5, 4.0, 1.0)
    Ctx.fillText(ctx, Float.toFixed(k, ~digits=3), marginLeft -. 7.0, y)
  })
}

let paintLabels = (ctx: ctx2d) => {
  Ctx.font(ctx, "600 11px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
  Ctx.textAlign(ctx, "center")
  Ctx.textBaseline(ctx, "middle")
  Ctx.lineJoin(ctx, "round")
  T.regionLabels->Array.forEach(((region, f, k)) => {
    let colour = switch region {
    | Silent => Palette.inkMutedRgb
    | other => Palette.labelColour(other)
    }
    let x = xOfF(f)
    let y = yOfK(k)
    // Halo in the panel colour keeps labels legible over the dot field.
    Ctx.strokeStyle(ctx, Palette.css(Palette.glassRgb, 0.9))
    Ctx.lineWidth(ctx, 4.0)
    Ctx.strokeText(ctx, T.regionName(region), x, y)
    Ctx.fillStyle(ctx, Palette.css(colour, 1.0))
    Ctx.fillText(ctx, T.regionName(region), x, y)
  })
}

let makeBackground = () => {
  let (canvas, ctx) = makeCanvas(~width, ~height, ~className="")
  Ctx.fillStyle(ctx, Palette.glass)
  Ctx.fillRect(ctx, 0.0, 0.0, Int.toFloat(width), Int.toFloat(height))

  // Region tint is drawn at 1:1 into a scratch canvas, then scaled in.
  let (scratch, scratchCtx) = {
    let c = createElement("canvas")
    setCanvasWidth(c, Float.toInt(plotW))
    setCanvasHeight(c, Float.toInt(plotH))
    (c, getContext2d(c))
  }
  Ctx.putImageData(scratchCtx, paintRegions(scratchCtx), 0, 0)
  Ctx.drawImage(ctx, scratch, marginLeft, marginTop, plotW, plotH)

  paintMeasured(ctx)
  paintCurves(ctx)
  paintAxes(ctx)
  paintLabels(ctx)
  canvas
}

// ---------------------------------------------------------------------------
// Dynamic layer

let updateReadout = plot => {
  let region = T.classify(~f=plot.f, ~k=plot.k)
  setTextContent(plot.regionLabel, T.regionName(region))
  setTextContent(plot.regionHint, T.regionHint(region))
  setStyle(
    plot.regionLabel,
    "color",
    switch region {
    | Silent => Palette.inkMuted
    | other => Palette.css(Palette.regionColour(other), 1.0)
    },
  )
  setTextContent(
    plot.valueLabel,
    "F " ++ Float.toFixed(plot.f, ~digits=4) ++ "   K " ++ Float.toFixed(plot.k, ~digits=4),
  )
  setTextContent(
    plot.resonanceLabel,
    switch T.resonance(~f=plot.f, ~k=plot.k) {
    | Some({selfOscillating: true, hertzPerUnitSpeed}) =>
      "Oscillates near " ++ Float.toFixed(hertzPerUnitSpeed *. plot.speed, ~digits=0) ++ " Hz"
    | Some({hertzPerUnitSpeed, q}) =>
      "Rings at " ++
      Float.toFixed(hertzPerUnitSpeed *. plot.speed, ~digits=0) ++
      " Hz, " ++ (
        q > 100.0 ? "right on the edge of oscillation" : "Q " ++ Float.toFixed(q, ~digits=q < 10.0 ? 1 : 0)
      )
    | None => "No resonant focus here"
    },
  )
}

let render = plot =>
  if plot.dirty {
    plot.dirty = false
    let ctx = plot.ctx
    Ctx.drawImage(ctx, plot.background, 0.0, 0.0, Int.toFloat(width), Int.toFloat(height))

    let x = xOfF(plot.f)
    let y = yOfK(plot.k)

    // Crosshair
    Ctx.strokeStyle(ctx, Palette.css(Palette.activeRgb, 0.3))
    Ctx.lineWidth(ctx, 1.0)
    Ctx.beginPath(ctx)
    Ctx.moveTo(ctx, x, marginTop)
    Ctx.lineTo(ctx, x, marginTop +. plotH)
    Ctx.moveTo(ctx, marginLeft, y)
    Ctx.lineTo(ctx, marginLeft +. plotW, y)
    Ctx.stroke(ctx)

    // Puck
    Ctx.beginPath(ctx)
    Ctx.arc(ctx, x, y, plot.dragging ? 9.0 : 7.0, 0.0, 2.0 *. Math.Constants.pi)
    Ctx.fillStyle(ctx, Palette.css(Palette.activeRgb, 0.18))
    Ctx.fill(ctx)
    Ctx.strokeStyle(ctx, Palette.active)
    Ctx.lineWidth(ctx, 2.0)
    Ctx.stroke(ctx)
    Ctx.beginPath(ctx)
    Ctx.arc(ctx, x, y, 2.0, 0.0, 2.0 *. Math.Constants.pi)
    Ctx.fillStyle(ctx, Palette.active)
    Ctx.fill(ctx)
  }

let setFK = (plot, ~f, ~k) => {
  plot.f = clampF(f)
  plot.k = clampK(k)
  markDirty(plot)
  updateReadout(plot)
}

let setSpeed = (plot, speed) => {
  plot.speed = speed
  updateReadout(plot)
}

let make = (
  ~onChange: (~f: float, ~k: float) => unit,
  ~onGestureStart: unit => unit,
  ~onGestureEnd: unit => unit,
) => {
  let element = div(~className="phase")
  let (canvas, ctx) = makeCanvas(~width, ~height, ~className="phase-canvas")
  setAttribute(canvas, "tabindex", "0")
  setAttribute(canvas, "role", "slider")
  setAttribute(
    canvas,
    "aria-label",
    "Feed and kill rate. Arrow keys move the point; hold Shift for fine steps.",
  )

  let readout = div(~className="phase-readout")
  let regionLine = div(~className="phase-region-line")
  let regionLabel = createElement("span")
  setClassName(regionLabel, "phase-region")
  let valueLabel = createElement("span")
  setClassName(valueLabel, "phase-values")
  regionLine->appendChild(regionLabel)
  regionLine->appendChild(valueLabel)
  let regionHint = div(~className="phase-hint")
  let resonanceLabel = div(~className="phase-resonance")
  readout->appendChild(regionLine)
  readout->appendChild(regionHint)
  readout->appendChild(resonanceLabel)

  element->appendChild(canvas)
  element->appendChild(readout)

  let plot = {
    element,
    canvas,
    ctx,
    background: makeBackground(),
    regionLabel,
    regionHint,
    valueLabel,
    resonanceLabel,
    f: CmajorBindings.Param.spec(Feed).init,
    k: CmajorBindings.Param.spec(Kill).init,
    speed: 1.0,
    dragging: false,
    dirty: true,
    invalidate: () => (),
  }
  updateReadout(plot)

  let moveTo = (x, y) => {
    let f = clampF(fOfX(x))
    let k = clampK(kOfY(y))
    setFK(plot, ~f, ~k)
    onChange(~f, ~k)
  }

  canvas->addEventListener("pointerdown", ev => {
    preventDefault(ev)
    setPointerCapture(canvas, pointerId(ev))
    plot.dragging = true
    onGestureStart()
    let (x, y) = localPoint(canvas, ev, ~width=Int.toFloat(width), ~height=Int.toFloat(height))
    moveTo(x, y)
  })
  canvas->addEventListener("pointermove", ev =>
    if plot.dragging {
      let (x, y) = localPoint(canvas, ev, ~width=Int.toFloat(width), ~height=Int.toFloat(height))
      moveTo(x, y)
    }
  )
  let finish = ev =>
    if plot.dragging {
      plot.dragging = false
      markDirty(plot)
      releasePointerCapture(canvas, pointerId(ev))
      onGestureEnd()
    }
  canvas->addEventListener("pointerup", finish)
  canvas->addEventListener("pointercancel", finish)

  canvas->addEventListener("keydown", ev => {
    let fine = shiftKey(ev)
    let df = fine ? 0.0001 : 0.001
    let dk = fine ? 0.00005 : 0.0005
    let nudge = switch key(ev) {
    | "ArrowLeft" => Some((-.df, 0.0))
    | "ArrowRight" => Some((df, 0.0))
    | "ArrowUp" => Some((0.0, dk))
    | "ArrowDown" => Some((0.0, -.dk))
    | _ => None
    }
    switch nudge {
    | Some((ddf, ddk)) =>
      preventDefault(ev)
      let f = clampF(plot.f +. ddf)
      let k = clampK(plot.k +. ddk)
      setFK(plot, ~f, ~k)
      onGestureStart()
      onChange(~f, ~k)
      onGestureEnd()
    | None => ()
    }
  })

  plot
}
