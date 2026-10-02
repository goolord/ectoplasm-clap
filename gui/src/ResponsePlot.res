// What the plugin does to a sound, drawn as a frequency response in decibels relative to the
// input: the ring's response from the processor's own level model (LevelModel), made up by the
// level match the processor puts on it, mixed with the dry signal, through the Output gain. The
// resonant focus is the peak at the pitch it rings at, as narrow as its ring is long; the rest of
// the curve is what the ring does to the frequencies it doesn't ring at (the pickups' distance and
// Diffusion shape it). Past the edge of oscillation it sustains itself, marked as a bright line.
//
// It's the linearised ring, so it's what quiet input hears. Loud input, and heavy Drive, push the
// ring out of its linear range: the peak comes down and widens, and the processor's learned trim
// (a few dB, not shown) makes up the level.
//
// The peak is a handle: drag it sideways for the pitch and up and down for the ring (up rings
// longer, so the peak gets narrower), or scroll over the plot for the ring. The plot only reports
// the pointer's movement (onDrag); the owner decides what it means, so the peak moves exactly as
// the Pitch and Ring knobs would. Under the Hz axis, the Cs mark the octaves.

open Web
module T = GrayScottTheory

let minHz = 20.0
let maxHz = 10000.0
let topDb = 24.0
let floorDb = -36.0

/// Everything the curve depends on.
type settings = {
  f: float,
  k: float,
  du: float,
  ratio: float,
  speed: float,
  resonance: float,
  tap: float,
  drive: float,
  mix: float,
  outputDb: float,
}

type t = {
  element: element,
  ctx: ctx2d,
  width: float,
  height: float,
  mutable settings: option<settings>,
  // where the peak is, if there's a focus to drag
  mutable peakHz: option<float>,
  // where the curve is at the peak, in design pixels (the handle sits there)
  mutable peakY: float,
  mutable hover: bool,
  // the pointer where a drag started, in design pixels
  mutable dragging: option<(float, float)>,
  mutable dirty: bool,
  mutable invalidate: unit => unit,
}

let set = (plot, settings: settings) =>
  if plot.settings != Some(settings) {
    plot.settings = Some(settings)
    let {f, k, speed, resonance, du} = settings
    plot.peakHz = Macro.pitch(~f, ~k, ~speed, ~resonance, ~du)
    plot.element->toggleClass("draggable", plot.peakHz->Option.isSome)
    plot.dirty = true
    plot.invalidate()
  }

// The Cs, C1 (32.7 Hz) to C9 (8.4 kHz), to read the frequency axis by.
let octaveCs = Array.fromInitializer(~length=9, i => (i + 1, Macro.hzOfMidi(Int.toFloat((i + 2) * 12))))

let hint = "Drag the peak: ← → pitch, ↑ ↓ ring"

let font = "10px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif"

let render = plot =>
  if plot.dirty {
    plot.dirty = false
    let ctx = plot.ctx
    let w = plot.width
    let h = plot.height
    let top = 14.0
    // (two rows of axis labels: Hz, and the Cs under them)
    let bottom = h -. 28.0
    let xOf = hz => Math.log(hz /. minHz) /. Math.log(maxHz /. minHz) *. w
    let yOf = db =>
      top +. Math.min(1.0, Math.max(0.0, (topDb -. db) /. (topDb -. floorDb))) *. (bottom -. top)

    Ctx.fillStyle(ctx, Palette.glass)
    Ctx.fillRect(ctx, 0.0, 0.0, w, h)

    // the octaves, as a fainter grid of Cs, labelled under the Hz
    Ctx.font(ctx, font)
    Ctx.textBaseline(ctx, "top")
    Ctx.textAlign(ctx, "center")
    octaveCs->Array.forEach(((octave, hz)) => {
      let x = Math.round(xOf(hz)) +. 0.5
      Ctx.fillStyle(ctx, Palette.css(Palette.ruleRgb, 0.55))
      Ctx.fillRect(ctx, x, top, 1.0, bottom -. top)
      Ctx.fillStyle(ctx, Palette.css(Palette.inkMutedRgb, 0.7))
      Ctx.fillText(ctx, "C" ++ Int.toString(octave), Math.min(w -. 8.0, x), bottom +. 15.0)
    })

    // frequency grid
    [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]->Array.forEach(hz => {
      let x = Math.round(xOf(hz)) +. 0.5
      Ctx.fillStyle(ctx, Palette.rule)
      Ctx.fillRect(ctx, x, top, 1.0, bottom -. top)
      Ctx.fillStyle(ctx, Palette.inkMuted)
      Ctx.fillText(ctx, hz >= 1000.0 ? Float.toString(hz /. 1000.0) ++ "k" : Float.toString(hz), x, bottom +. 3.0)
    })
    Ctx.fillStyle(ctx, Palette.rule)
    Ctx.fillRect(ctx, 0.0, bottom, w, 1.0)

    // level grid, every 12 dB; 0 dB is as loud as what you put in
    Ctx.textAlign(ctx, "left")
    Ctx.textBaseline(ctx, "bottom")
    [12.0, 0.0, -12.0, -24.0]->Array.forEach(db => {
      let y = Math.round(yOf(db)) +. 0.5
      Ctx.fillStyle(
        ctx,
        db == 0.0 ? Palette.css(Palette.inkMutedRgb, 0.45) : Palette.css(Palette.ruleRgb, 0.55),
      )
      Ctx.fillRect(ctx, 0.0, y, w, 1.0)
      Ctx.fillStyle(ctx, Palette.css(Palette.inkMutedRgb, 0.8))
      let text = db == 0.0 ? "0 dB, your input" : (db > 0.0 ? "+" : "−") ++ Float.toString(Math.abs(db))
      Ctx.fillText(ctx, text, 4.0, y -. 1.0)
    })

    let label = (text, x) => {
      Ctx.font(ctx, "600 12px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
      Ctx.textBaseline(ctx, "top")
      let anchorRight = x > w -. 200.0
      Ctx.textAlign(ctx, anchorRight ? "right" : "left")
      Ctx.fillStyle(ctx, Palette.accent)
      Ctx.fillText(ctx, text, anchorRight ? x -. 8.0 : x +. 8.0, 1.0)
    }

    plot.settings->Option.forEach(({f, k, du, ratio, speed, resonance, tap, drive, mix, outputDb}) => {
      let model = LevelModel.make(~f, ~k, ~du, ~ratio, ~speed, ~resonance, ~tap, ~drive)
      let gain = LevelModel.predictedMatch(~f, ~k, ~du, ~ratio, ~speed, ~resonance, ~tap, ~drive)
      let output = Math.pow(10.0, ~exp=outputDb /. 20.0)
      // the wet path, made up, mixed with the dry signal (in phase with it), through Output
      let dbAt = hz => {
        let (re, im) = LevelModel.response(model, hz)
        let re = mix *. gain *. re +. (1.0 -. mix)
        let im = mix *. gain *. im
        20.0 *. Math.log10(Math.max(1.0e-9, Math.sqrt(re *. re +. im *. im) *. output))
      }
      let steps = 320
      let points = Array.fromInitializer(~length=steps + 1, i => {
        let x = Int.toFloat(i) /. Int.toFloat(steps) *. w
        (x, yOf(dbAt(minHz *. Math.pow(maxHz /. minHz, ~exp=x /. w))))
      })
      Ctx.beginPath(ctx)
      Ctx.moveTo(ctx, 0.0, bottom)
      points->Array.forEach(((x, y)) => Ctx.lineTo(ctx, x, y))
      Ctx.lineTo(ctx, w, bottom)
      Ctx.closePath(ctx)
      Ctx.fillStyle(ctx, Palette.css(Palette.accentRgb, 0.16))
      Ctx.fill(ctx)
      Ctx.beginPath(ctx)
      points->Array.forEachWithIndex(((x, y), i) => i == 0 ? Ctx.moveTo(ctx, x, y) : Ctx.lineTo(ctx, x, y))
      Ctx.strokeStyle(ctx, Palette.accent)
      Ctx.lineWidth(ctx, 1.5)
      Ctx.stroke(ctx)
      plot.peakHz->Option.forEach(hz => plot.peakY = yOf(dbAt(hz)))

      switch Macro.focus(~f, ~k, ~speed, ~resonance, ~du) {
      | Some({hz: hz0, decayPerSecond}) =>
        let x0 = xOf(hz0)
        let note = Macro.tuning(hz0) ++ ", " ++ Macro.formatHz(hz0)
        if decayPerSecond <= 0.0 {
          Ctx.fillStyle(ctx, Palette.css(Palette.accentRgb, 0.18))
          Ctx.fillRect(ctx, x0 -. 6.0, top, 12.0, bottom -. top)
          Ctx.fillStyle(ctx, Palette.accent)
          Ctx.fillRect(ctx, x0 -. 1.0, top, 2.0, bottom -. top)
          label("Sustains at " ++ note, x0)
        } else {
          label(note, x0)
        }
      | None =>
        Ctx.font(ctx, font)
        Ctx.textAlign(ctx, "center")
        Ctx.textBaseline(ctx, "top")
        Ctx.fillStyle(ctx, Palette.inkMuted)
        Ctx.fillText(
          ctx,
          "No resonant focus at these settings. Pick a preset, or turn Ring or Color to get back to one.",
          w /. 2.0,
          1.0,
        )
      }
    })

    // the peak's handle, and how to use it (out of the way of the peak, and gone while dragging)
    plot.peakHz->Option.forEach(hz => {
      let x = xOf(hz)
      let y = Math.max(top, plot.peakY)
      let active = plot.hover || plot.dragging->Option.isSome
      Ctx.beginPath(ctx)
      Ctx.arc(ctx, x, y, active ? 5.0 : 4.0, 0.0, 2.0 *. Math.Constants.pi)
      Ctx.fillStyle(ctx, active ? Palette.active : Palette.accent)
      Ctx.fill(ctx)
      Ctx.strokeStyle(ctx, Palette.glass)
      Ctx.lineWidth(ctx, 2.0)
      Ctx.stroke(ctx)
      if plot.dragging->Option.isNone {
        Ctx.font(ctx, font)
        Ctx.textBaseline(ctx, "bottom")
        let onLeft = x > w /. 2.0
        Ctx.textAlign(ctx, onLeft ? "left" : "right")
        Ctx.fillStyle(ctx, Palette.css(Palette.inkMutedRgb, plot.hover ? 1.0 : 0.75))
        Ctx.fillText(ctx, hint, onLeft ? 6.0 : w -. 6.0, bottom -. 4.0)
      }
    })
  }

/// onDrag gets how far the pointer has moved since the drag started: across, in octaves along
/// the frequency axis (so the peak can follow it), and up, in design pixels.
let make = (
  ~width: int,
  ~height: int,
  ~onDragStart: unit => unit,
  ~onDrag: (~octaves: float, ~rise: float, ~fine: bool) => unit,
  ~onDragEnd: unit => unit,
  ~onWheel: (~up: bool, ~fine: bool) => unit,
) => {
  let (element, ctx) = makeCanvas(~width, ~height, ~className="response")
  element->setAttribute(
    "aria-label",
    "Frequency response of the lattice: where it rings, and how sharply. Drag the peak sideways for the pitch, up and down for the ring.",
  )
  let plot = {
    element,
    ctx,
    width: Int.toFloat(width),
    height: Int.toFloat(height),
    settings: None,
    peakHz: None,
    peakY: 0.0,
    hover: false,
    dragging: None,
    dirty: true,
    invalidate: () => (),
  }
  let redraw = () => {
    plot.dirty = true
    plot.invalidate()
  }
  let point = ev => localPoint(element, ev, ~width=plot.width, ~height=plot.height)
  let octavesAcross = Math.log2(maxHz /. minHz)

  // The drag is relative, so it can start anywhere on the plot without the peak jumping.
  element->addEventListener("pointerdown", ev =>
    if ev->button == 0 && plot.peakHz->Option.isSome {
      preventDefault(ev)
      setPointerCapture(element, pointerId(ev))
      plot.dragging = Some(point(ev))
      element->toggleClass("dragging", true)
      onDragStart()
      redraw()
    }
  )
  element->addEventListener("pointermove", ev =>
    switch plot.dragging {
    | Some((x0, y0)) =>
      let (x, y) = point(ev)
      onDrag(~octaves=(x -. x0) /. plot.width *. octavesAcross, ~rise=y0 -. y, ~fine=shiftKey(ev))
    | None => ()
    }
  )
  let finish = ev =>
    if plot.dragging->Option.isSome {
      plot.dragging = None
      element->toggleClass("dragging", false)
      releasePointerCapture(element, pointerId(ev))
      onDragEnd()
      redraw()
    }
  element->addEventListener("pointerup", finish)
  element->addEventListener("pointercancel", finish)
  element->addEventListener("pointerenter", _ => {
    plot.hover = true
    redraw()
  })
  element->addEventListener("pointerleave", _ => {
    plot.hover = false
    redraw()
  })
  element->addEventListener("wheel", ev =>
    if !ctrlKey(ev) && plot.peakHz->Option.isSome {
      preventDefault(ev)
      onWheel(~up=deltaY(ev) < 0.0, ~fine=shiftKey(ev))
    }
  )
  plot
}
