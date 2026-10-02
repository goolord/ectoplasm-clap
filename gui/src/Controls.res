// Parameter sliders. Native <input type=range> underneath, so keyboard and
// screen-reader support come for free; double-click resets to the default, and a
// double right-click opens the host's menu for the parameter (in the CLAP plugin).

open Web
module Param = CmajorBindings.Param
module Bridge = CmajorBindings.Bridge

let resolution = 1000.0

type slider = {
  param: Param.t,
  row: element,
  input: element,
  readout: element,
  mutable value: float,
}

let show = (slider, value) => {
  slider.value = value
  setInputValue(
    slider.input,
    Float.toString(Math.round(Param.toNormalised(slider.param, value) *. resolution)),
  )
  setTextContent(slider.readout, Param.spec(slider.param).format(value))
}

let makeSlider = (
  bridge: Bridge.t,
  param: Param.t,
  ~hostMenu: HostMenu.t,
  ~onLocalChange: (Param.t, float) => unit,
) => {
  let spec = Param.spec(param)
  let row = div(~className="slider")
  let label = createElement("label")
  setClassName(label, "slider-label")
  setTextContent(label, spec.label)
  setAttribute(label, "for", "param-" ++ spec.id)

  let input = createElement("input")
  setAttribute(input, "type", "range")
  setAttribute(input, "id", "param-" ++ spec.id)
  setAttribute(input, "min", "0")
  setAttribute(input, "max", Float.toString(resolution))
  setAttribute(input, "step", "1")

  let readout = createElement("output")
  setClassName(readout, "slider-value")
  setAttribute(readout, "for", "param-" ++ spec.id)

  row->appendChild(label)
  row->appendChild(input)
  row->appendChild(readout)
  // a double right-click opens the host's menu for the parameter (automation, MIDI learn...)
  hostMenu->HostMenu.attach(row, spec.id)

  let slider = {param, row, input, readout, value: spec.init}
  show(slider, spec.init)

  let commit = value => {
    show(slider, value)
    Bridge.set(bridge, param, value)
    onLocalChange(param, value)
  }

  input->addEventListener("pointerdown", _ => Bridge.beginGesture(bridge, param))
  input->addEventListener("keydown", _ => Bridge.beginGesture(bridge, param))
  input->addEventListener("input", _ => {
    let n = Float.fromString(inputValue(input))->Option.getOr(0.0) /. resolution
    Bridge.beginGesture(bridge, param)
    commit(Param.fromNormalised(param, n))
  })
  input->addEventListener("change", _ => Bridge.endGesture(bridge, param))
  input->addEventListener("pointerup", _ => Bridge.endGesture(bridge, param))
  input->addEventListener("keyup", _ => Bridge.endGesture(bridge, param))
  input->addEventListener("dblclick", _ => {
    Bridge.beginGesture(bridge, param)
    commit(spec.init)
    Bridge.endGesture(bridge, param)
  })

  slider
}

type group = {title: string, params: array<Param.t>}

let groups = [
  {title: "Chemistry", params: [DiffusionU, DiffusionRatio, Speed]},
  {title: "Coupling", params: [Drive, TapDistance, Feedback]},
  {title: "Output", params: [Mix, OutputGain]},
]

/// Builds the control strip; returns it with every slider it created.
let make = (bridge, ~hostMenu, ~onLocalChange, ~extra: element) => {
  let strip = div(~className="controls")
  let sliders = []
  groups->Array.forEachWithIndex((group, index) => {
    let box = div(~className="control-group")
    let heading = createElement("h2")
    setTextContent(heading, group.title)
    box->appendChild(heading)
    group.params->Array.forEach(param => {
      let s = makeSlider(bridge, param, ~hostMenu, ~onLocalChange)
      sliders->Array.push(s)
      box->appendChild(s.row)
    })
    if index == Array.length(groups) - 1 {
      box->appendChild(extra)
    }
    strip->appendChild(box)
  })
  (strip, sliders)
}
