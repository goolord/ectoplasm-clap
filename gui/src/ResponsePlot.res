// What the lattice will do to a sound, drawn as a frequency response: the resonant focus as a
// peak at the pitch it rings at, as wide as its ring is short. Past the edge of oscillation it
// sustains itself, drawn as a single bright line. Where F and K have no focus there is no peak.
//
// It's the linearised focus as the processor integrates it (Macro.focus), which the offline
// renders match to within a few percent; at high Drive the lattice is nonlinear and the real
// response is wider.

open Web
module T = GrayScottTheory

let minHz = 20.0
let maxHz = 10000.0
let floorDb = -36.0

type t = {
  element: element,
  ctx: ctx2d,
  width: float,
  height: float,
  mutable f: float,
  mutable k: float,
  mutable speed: float,
  mutable resonance: float,
  mutable dirty: bool,
  mutable invalidate: unit => unit,
}

let set = (plot, ~f, ~k, ~speed, ~resonance) =>
  if f != plot.f || k != plot.k || speed != plot.speed || resonance != plot.resonance {
    plot.f = f
    plot.k = k
    plot.speed = speed
    plot.resonance = resonance
    plot.dirty = true
    plot.invalidate()
  }

let font = "10px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif"

let render = plot =>
  if plot.dirty {
    plot.dirty = false
    let ctx = plot.ctx
    let w = plot.width
    let h = plot.height
    let top = 14.0
    let bottom = h -. 16.0
    let xOf = hz => Math.log(hz /. minHz) /. Math.log(maxHz /. minHz) *. w
    let yOf = db => top +. Math.min(1.0, Math.max(0.0, db /. floorDb)) *. (bottom -. top)

    Ctx.fillStyle(ctx, Palette.glass)
    Ctx.fillRect(ctx, 0.0, 0.0, w, h)

    // frequency grid
    Ctx.font(ctx, font)
    Ctx.textBaseline(ctx, "top")
    Ctx.textAlign(ctx, "center")
    [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0]->Array.forEach(hz => {
      let x = Math.round(xOf(hz)) +. 0.5
      Ctx.fillStyle(ctx, Palette.rule)
      Ctx.fillRect(ctx, x, top, 1.0, bottom -. top)
      Ctx.fillStyle(ctx, Palette.inkMuted)
      Ctx.fillText(ctx, hz >= 1000.0 ? Float.toString(hz /. 1000.0) ++ "k" : Float.toString(hz), x, bottom +. 3.0)
    })
    Ctx.fillStyle(ctx, Palette.rule)
    Ctx.fillRect(ctx, 0.0, bottom, w, 1.0)

    let label = (text, x) => {
      Ctx.font(ctx, "600 12px Bahnschrift, 'DIN Alternate', 'Roboto Condensed', sans-serif")
      Ctx.textBaseline(ctx, "top")
      let anchorRight = x > w -. 140.0
      Ctx.textAlign(ctx, anchorRight ? "right" : "left")
      Ctx.fillStyle(ctx, Palette.accent)
      Ctx.fillText(ctx, text, anchorRight ? x -. 8.0 : x +. 8.0, 1.0)
    }

    switch Macro.focus(~f=plot.f, ~k=plot.k, ~speed=plot.speed, ~resonance=plot.resonance) {
    | Some({hz: hz0, decayPerSecond}) =>
      let x0 = xOf(hz0)
      let note = Macro.formatHz(hz0) ++ ", " ++ Macro.noteName(hz0)
      if decayPerSecond <= 0.0 {
        Ctx.fillStyle(ctx, Palette.css(Palette.accentRgb, 0.18))
        Ctx.fillRect(ctx, x0 -. 6.0, top, 12.0, bottom -. top)
        Ctx.fillStyle(ctx, Palette.accent)
        Ctx.fillRect(ctx, x0 -. 1.0, top, 2.0, bottom -. top)
        label("Sustains at " ++ note, x0)
      } else {
        // a two-pole resonator with poles at −α ± jω0 (per second)
        let alpha = decayPerSecond
        let omega0 = 2.0 *. Math.Constants.pi *. hz0
        let magnitude = omega => {
          let a = alpha *. alpha +. (omega -. omega0) *. (omega -. omega0)
          let b = alpha *. alpha +. (omega +. omega0) *. (omega +. omega0)
          1.0 /. Math.sqrt(a *. b)
        }
        let peak = magnitude(omega0)
        let steps = 240
        Ctx.beginPath(ctx)
        Ctx.moveTo(ctx, 0.0, bottom)
        for i in 0 to steps {
          let x = Int.toFloat(i) /. Int.toFloat(steps) *. w
          let hz = minHz *. Math.pow(maxHz /. minHz, ~exp=x /. w)
          let db = 20.0 *. Math.log10(magnitude(2.0 *. Math.Constants.pi *. hz) /. peak)
          Ctx.lineTo(ctx, x, yOf(db))
        }
        Ctx.lineTo(ctx, w, bottom)
        Ctx.closePath(ctx)
        Ctx.fillStyle(ctx, Palette.css(Palette.accentRgb, 0.16))
        Ctx.fill(ctx)
        Ctx.beginPath(ctx)
        for i in 0 to steps {
          let x = Int.toFloat(i) /. Int.toFloat(steps) *. w
          let hz = minHz *. Math.pow(maxHz /. minHz, ~exp=x /. w)
          let y = yOf(20.0 *. Math.log10(magnitude(2.0 *. Math.Constants.pi *. hz) /. peak))
          i == 0 ? Ctx.moveTo(ctx, x, y) : Ctx.lineTo(ctx, x, y)
        }
        Ctx.strokeStyle(ctx, Palette.accent)
        Ctx.lineWidth(ctx, 1.5)
        Ctx.stroke(ctx)
        label(note, x0)
      }
    | _ =>
      Ctx.font(ctx, font)
      Ctx.textAlign(ctx, "center")
      Ctx.textBaseline(ctx, "middle")
      Ctx.fillStyle(ctx, Palette.inkMuted)
      Ctx.fillText(
        ctx,
        "No resonant focus at these settings. Pick a preset, or turn Ring or Color to get back to one.",
        w /. 2.0,
        (top +. bottom) /. 2.0,
      )
    }
  }

let make = (~width: int, ~height: int) => {
  let (element, ctx) = makeCanvas(~width, ~height, ~className="response")
  element->setAttribute(
    "aria-label",
    "Frequency response of the lattice: where it rings, and how sharply",
  )
  {
    element,
    ctx,
    width: Int.toFloat(width),
    height: Int.toFloat(height),
    f: 0.0,
    k: 0.0,
    speed: 0.0,
    resonance: 0.0,
    dirty: true,
    invalidate: () => (),
  }
}
