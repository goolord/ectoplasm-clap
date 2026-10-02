// A rotary knob for the Play view. The owner maps its 0..1 position to whatever it controls and
// tells the knob what to say about it (set), so a knob can show the result — "345 Hz", "120 ms" —
// rather than its own position.
//
// Drag up and down (Shift for fine steps), scroll, or use the arrow keys, Page Up/Down, Home
// and End; double-click goes back to the default. A knob can snap (Pitch snaps to semitones):
// then drags land on the nearest snapped position, and the wheel and keys move a snapped step at a
// time, unless Shift is held, which gives the same free, fine movement as on any other knob.
//
// A knob that can read typed values (parse) turns its value into a text field on a click, or on
// Enter while it has focus: Enter applies, Escape cancels, and so does leaving it unchanged. What
// it can't read shakes, and the value stays as it was.
//
// Every change is bracketed by onGestureStart and onGestureEnd, so hosts record a drag, or a typed
// value, as one automation move.

open Web

let size = 64.0
let radius = 24.0
let sweepDegrees = 270.0

@send external querySelector: (element, string) => element = "querySelector"

/// How a knob snaps, as positions.
type snap = {
  /// the snapped position nearest a position
  nearest: float => float,
  /// the position n snapped steps up from a position (down for n < 0)
  step: (float, int) => float,
  /// how many steps Page Up and Page Down take
  bigStep: int,
}

type t = {
  element: element,
  valueArc: element,
  pointer: element,
  valueText: element,
  detailText: element,
  input: element,
  mutable value: float,
  mutable text: string,
  mutable dragging: option<(float, float)>, // (start clientY, start value)
  // the text the editor opened with, while it's open
  mutable editing: option<string>,
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
  knob.text = text
  draw(knob)
  setTextContent(knob.valueText, text)
  setTextContent(knob.detailText, detail)
  knob.element->setAttribute("aria-valuetext", text ++ ", " ++ detail)
  knob.element->toggleClass("muted", muted)
}

// A short shake for a value that couldn't be read (restarted if it's already shaking).
let shake = el => {
  el->toggleClass("invalid", false)
  el->offsetWidth->ignore
  el->toggleClass("invalid", true)
  Web.setTimeout(() => el->toggleClass("invalid", false), 450)->ignore
}

let clamp01 = x => Math.min(1.0, Math.max(0.0, x))

/// A full turn is 200 px of travel, 1000 px with Shift.
let turnTravel = (~fine) => fine ? 1000.0 : 200.0

/// How far a wheel click turns a knob without a snap.
let wheelStep = (~fine) => fine ? 0.004 : 0.02

let make = (
  ~label: string,
  ~title: string,
  ~defaultValue: float,
  ~onChange: float => unit,
  ~onGestureStart: unit => unit,
  ~onGestureEnd: unit => unit,
  ~snap: option<snap>=?,
  ~parse: option<string => option<float>>=?,
  ~typeHint: string="",
) => {
  let element = div(~className="knob")
  element->setAttribute("tabindex", "0")
  element->setAttribute("role", "slider")
  element->setAttribute("aria-label", label)
  element->setAttribute("aria-valuemin", "0")
  element->setAttribute("aria-valuemax", "100")
  element->setAttribute(
    "title",
    parse->Option.isSome ? title ++ " Click the value, or press Enter, to type one." : title,
  )
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
     <input class="knob-input" type="text" spellcheck="false" autocomplete="off">
     <div class="knob-detail"></div>`,
  )
  setTextContent(element->querySelector(".knob-label"), label)

  let knob = {
    element,
    valueArc: element->querySelector(".knob-value"),
    pointer: element->querySelector(".knob-pointer"),
    valueText: element->querySelector(".knob-text"),
    detailText: element->querySelector(".knob-detail"),
    input: element->querySelector(".knob-input"),
    value: defaultValue,
    text: "",
    dragging: None,
    editing: None,
  }
  draw(knob)

  // one gesture per discrete change (keys, wheel, double-click, a typed value)
  let nudge = to => {
    onGestureStart()
    onChange(clamp01(to))
    onGestureEnd()
  }
  // where a free movement lands, snapped unless it's fine
  let snapped = (to, ~fine) =>
    switch snap {
    | Some({nearest}) if !fine => nearest(clamp01(to))
    | _ => clamp01(to)
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
      let fine = shiftKey(ev)
      onChange(snapped(startValue +. (startY -. clientY(ev)) /. turnTravel(~fine), ~fine))
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
      let up = deltaY(ev) < 0.0
      switch snap {
      | Some({step}) if !shiftKey(ev) => nudge(step(knob.value, up ? 1 : -1))
      | _ =>
        let by = wheelStep(~fine=shiftKey(ev))
        nudge(knob.value +. (up ? by : -.by))
      }
    }
  )

  //----------------------------------------------------------------------------
  // Typing a value

  let startEditing = () =>
    if parse->Option.isSome && knob.editing->Option.isNone {
      // (what it says, without the "roughly" mark)
      let text = knob.text->String.replace("≈ ", "")
      knob.editing = Some(text)
      setInputValue(knob.input, text)
      element->toggleClass("editing", true)
      knob.input->focus
      knob.input->selectText
    }
  // Closes the editor, applying what was typed if asked to and it changed. Returns false, leaving
  // the editor open, if Enter was pressed on something it can't read.
  let stopEditing = (~apply, ~keepOpenIfInvalid) =>
    switch (knob.editing, parse) {
    | (Some(original), Some(parse)) =>
      let typed = inputValue(knob.input)
      let changed = apply && String.trim(typed) != String.trim(original)
      switch changed ? Some(parse(typed)) : None {
      | Some(None) if keepOpenIfInvalid =>
        shake(knob.input)
        knob.input->selectText
        false
      | result =>
        knob.editing = None
        element->toggleClass("editing", false)
        switch result {
        | Some(Some(position)) => nudge(position)
        | Some(None) => shake(knob.valueText)
        | None => ()
        }
        true
      }
    | _ => true
    }
  knob.valueText->addEventListener("click", _ => startEditing())
  knob.input->addEventListener("keydown", ev => {
    // the knob's own keys (arrows, Home, End) belong to the text while it's being edited
    stopPropagation(ev)
    switch key(ev) {
    | "Enter" =>
      preventDefault(ev)
      if stopEditing(~apply=true, ~keepOpenIfInvalid=true) {
        element->focus
      }
    | "Escape" =>
      preventDefault(ev)
      stopEditing(~apply=false, ~keepOpenIfInvalid=false)->ignore
      element->focus
    | _ => ()
    }
  })
  knob.input->addEventListener("blur", _ =>
    stopEditing(~apply=true, ~keepOpenIfInvalid=false)->ignore
  )
  if parse->Option.isSome {
    knob.valueText->toggleClass("editable", true)
    knob.input->setAttribute("aria-label", label ++ ": type a value")
    knob.input->setAttribute("placeholder", typeHint)
    element->setAttribute("aria-keyshortcuts", "Enter")
  }

  element->addEventListener("keydown", ev => {
    let fine = shiftKey(ev)
    let target = switch (key(ev), snap) {
    | ("Enter", _) =>
      startEditing()
      None
    | ("ArrowUp" | "ArrowRight", Some({step})) if !fine => Some(step(knob.value, 1))
    | ("ArrowDown" | "ArrowLeft", Some({step})) if !fine => Some(step(knob.value, -1))
    | ("PageUp", Some({step, bigStep})) => Some(step(knob.value, bigStep))
    | ("PageDown", Some({step, bigStep})) => Some(step(knob.value, -bigStep))
    | ("Home", Some({nearest})) => Some(nearest(0.0))
    | ("End", Some({nearest})) => Some(nearest(1.0))
    | ("ArrowUp" | "ArrowRight", _) => Some(knob.value +. (fine ? 0.002 : 0.01))
    | ("ArrowDown" | "ArrowLeft", _) => Some(knob.value -. (fine ? 0.002 : 0.01))
    | ("PageUp", _) => Some(knob.value +. 0.1)
    | ("PageDown", _) => Some(knob.value -. 0.1)
    | ("Home", _) => Some(0.0)
    | ("End", _) => Some(1.0)
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
