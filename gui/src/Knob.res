// A rotary knob for the Play view. The owner maps its 0..1 position to whatever it controls and
// tells the knob what to say about it (set), so a knob can show the result — "345 Hz", "120 ms" —
// rather than its own position.
//
// Drag up and down (Shift for fine steps), scroll, or use the arrow keys, Page Up/Down, Home
// and End; double-click goes back to the default. Every change is bracketed by onGestureStart
// and onGestureEnd, so hosts record a drag as one automation move.

open Web

let size = 64.0
let radius = 24.0
let sweepDegrees = 270.0

@send external querySelector: (element, string) => element = "querySelector"
@get external deltaY: event => float = "deltaY"

type t = {
  element: element,
  valueArc: element,
  pointer: element,
  valueText: element,
  detailText: element,
  mutable value: float,
  mutable dragging: option<(float, float)>, // (start clientY, start value)
}

let polar = (degrees, r) => {
  let a = (degrees -. 90.0) *. Math.Constants.pi /. 180.0
  (size /. 2.0 +. r *. Math.cos(a), size /. 2.0 +. r *. Math.sin(a))
}

let arcPath = (fromDegrees, toDegrees) => {
  let (x0, y0) = polar(fromDegrees, radius)
  let (x1, y1) = polar(toDegrees, radius)
  let large = toDegrees -. fromDegrees > 180.0 ? "1" : "0"
  let n = Float.toFixed(_, ~digits=2)
  `M ${n(x0)} ${n(y0)} A ${n(radius)} ${n(radius)} 0 ${large} 1 ${n(x1)} ${n(y1)}`
}

let startDegrees = -.sweepDegrees /. 2.0

let draw = knob => {
  let v = Math.min(1.0, Math.max(0.0, knob.value))
  let toDegrees = startDegrees +. v *. sweepDegrees
  knob.valueArc->setAttribute("d", v <= 0.001 ? "" : arcPath(startDegrees, toDegrees))
  let (x0, y0) = polar(toDegrees, radius -. 9.0)
  let (x1, y1) = polar(toDegrees, radius -. 2.0)
  knob.pointer->setAttribute("x1", Float.toString(x0))
  knob.pointer->setAttribute("y1", Float.toString(y0))
  knob.pointer->setAttribute("x2", Float.toString(x1))
  knob.pointer->setAttribute("y2", Float.toString(y1))
  knob.element->setAttribute("aria-valuenow", Float.toFixed(v *. 100.0, ~digits=0))
}

/// Shows a position and what it means. ~muted greys the knob out (e.g. when the Lab view has
/// put the parameters off the band this knob covers).
let set = (knob, value, ~text, ~detail, ~muted=false) => {
  knob.value = value
  draw(knob)
  setTextContent(knob.valueText, text)
  setTextContent(knob.detailText, detail)
  knob.element->setAttribute("aria-valuetext", text ++ ", " ++ detail)
  knob.element->toggleClass("muted", muted)
}

let make = (
  ~label: string,
  ~title: string,
  ~defaultValue: float,
  ~onChange: float => unit,
  ~onGestureStart: unit => unit,
  ~onGestureEnd: unit => unit,
) => {
  let element = div(~className="knob")
  element->setAttribute("tabindex", "0")
  element->setAttribute("role", "slider")
  element->setAttribute("aria-label", label)
  element->setAttribute("aria-valuemin", "0")
  element->setAttribute("aria-valuemax", "100")
  element->setAttribute("title", title)
  let s = Float.toString(size)
  setInnerHTML(
    element,
    `<div class="knob-label"></div>
     <svg width="${s}" height="${s}" viewBox="0 0 ${s} ${s}" aria-hidden="true">
       <path class="knob-track" d="${arcPath(startDegrees, -.startDegrees)}"/>
       <path class="knob-value" d=""/>
       <circle class="knob-cap" cx="${Float.toString(size /. 2.0)}" cy="${Float.toString(size /. 2.0)}" r="${Float.toString(radius -. 6.0)}"/>
       <line class="knob-pointer"/>
     </svg>
     <div class="knob-text"></div>
     <div class="knob-detail"></div>`,
  )
  setTextContent(element->querySelector(".knob-label"), label)

  let knob = {
    element,
    valueArc: element->querySelector(".knob-value"),
    pointer: element->querySelector(".knob-pointer"),
    valueText: element->querySelector(".knob-text"),
    detailText: element->querySelector(".knob-detail"),
    value: defaultValue,
    dragging: None,
  }
  draw(knob)

  // one gesture per discrete change (keys, wheel, double-click)
  let nudge = to => {
    onGestureStart()
    onChange(Math.min(1.0, Math.max(0.0, to)))
    onGestureEnd()
  }

  let dial = element->querySelector("svg")
  dial->addEventListener("pointerdown", ev =>
    if ev->button == 0 {
      preventDefault(ev)
      element->focus
      setPointerCapture(dial, pointerId(ev))
      knob.dragging = Some((clientY(ev), knob.value))
      element->toggleClass("active", true)
      onGestureStart()
    }
  )
  dial->addEventListener("pointermove", ev =>
    switch knob.dragging {
    | Some((startY, startValue)) =>
      // a full turn is 200 px of travel, 1000 px with Shift
      let range = shiftKey(ev) ? 1000.0 : 200.0
      onChange(Math.min(1.0, Math.max(0.0, startValue +. (startY -. clientY(ev)) /. range)))
    | None => ()
    }
  )
  let finish = ev =>
    if knob.dragging->Option.isSome {
      knob.dragging = None
      element->toggleClass("active", false)
      releasePointerCapture(dial, pointerId(ev))
      onGestureEnd()
    }
  dial->addEventListener("pointerup", finish)
  dial->addEventListener("pointercancel", finish)
  dial->addEventListener("dblclick", _ => nudge(defaultValue))
  dial->addEventListener("wheel", ev =>
    if !ctrlKey(ev) {
      preventDefault(ev)
      let step = shiftKey(ev) ? 0.004 : 0.02
      nudge(knob.value -. (deltaY(ev) > 0.0 ? step : -.step))
    }
  )
  element->addEventListener("keydown", ev => {
    let step = shiftKey(ev) ? 0.002 : 0.01
    let target = switch key(ev) {
    | "ArrowUp" | "ArrowRight" => Some(knob.value +. step)
    | "ArrowDown" | "ArrowLeft" => Some(knob.value -. step)
    | "PageUp" => Some(knob.value +. 0.1)
    | "PageDown" => Some(knob.value -. 0.1)
    | "Home" => Some(0.0)
    | "End" => Some(1.0)
    | _ => None
    }
    switch target {
    | Some(to) =>
      preventDefault(ev)
      nudge(to)
    | None => ()
    }
  })
  knob
}
