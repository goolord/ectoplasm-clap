// Top-level view: the stage the phase plane, lattice view and sliders live on, wired to the
// patch through the typed Bridge.
//
// What the plugin's web view needs smoothing over comes from nano-clap's Shell.res:
//
//  - The view has a shadow root, so its styles stay its own. Cmajor sets the manifest's size on
//    the view as an inline style; :host overrides it so the stage can scale with the window, and
//    the page behind gets the panel ground (it shows while a host resizes the window).
//  - The stage keeps the design size (880×560), scaled to fit the window and centred. CSS zoom
//    lays the page out again at the scale, so text and lines land on whole device pixels at any
//    size; a transform only where zoom isn't supported.
//  - The browser's context menu, shortcuts and page zoom are off (BrowserChrome), and the host's
//    parameter menu opens on a double right-click on a slider (HostMenu).
//  - In the CLAP plugin the interface size is a user setting (Settings): the Size control asks
//    the host to resize the window and opens new windows at that size.
//  - Nothing repaints on a timer: a change (a lattice snapshot, a moved parameter) schedules one
//    animation frame.

open Web
module Param = CmajorBindings.Param
module Bridge = CmajorBindings.Bridge

let designWidth = 880.
let designHeight = 560.

let stylesheet = `
:host {
  display: block;
  position: relative;
  /* important, because Cmajor sets the manifest's size on the view as an inline style, which
     would pin it at the design size and stop the stage scaling with the window */
  width: 100% !important;
  height: 100% !important;
  overflow: hidden;
  background: ${Palette.slide};
  user-select: none;
  -webkit-user-select: none;
  cursor: default;
}
.gsr {
  --slide: ${Palette.slide};
  --glass: ${Palette.glass};
  --rule: ${Palette.rule};
  --ink: ${Palette.ink};
  --ink-muted: ${Palette.inkMuted};
  --accent: ${Palette.accent};
  --active: ${Palette.active};
  --fill: ${Palette.hex(Palette.fillRgb)};
  box-sizing: border-box;
  position: absolute;
  left: 0;
  top: 0;
  width: ${Float.toString(designWidth)}px;
  height: ${Float.toString(designHeight)}px;
  transform-origin: 0 0;
  padding: 14px 16px 12px;
  background: var(--slide);
  color: var(--ink);
  font-family: Bahnschrift, "DIN Alternate", "DIN 2014", "Roboto Condensed", "Arial Narrow", sans-serif;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  user-select: none;
  overflow: hidden;
  display: grid;
  grid-template-rows: auto 1fr auto;
  row-gap: 10px;
}
.gsr *, .gsr *::before, .gsr *::after { box-sizing: inherit; }

.gsr header { display: flex; align-items: baseline; gap: 14px; }
.gsr h1 {
  margin: 0;
  font-size: 22px;
  font-weight: 300;
  font-stretch: condensed;
  letter-spacing: 0.01em;
}
.gsr h1 b { font-weight: 700; color: var(--accent); }
.gsr .subtitle { color: var(--ink-muted); font-size: 12px; }
.gsr .meter { margin-left: auto; display: flex; align-items: center; gap: 8px; color: var(--ink-muted); }
.gsr .size { position: relative; align-self: center; }
.gsr .size > button { margin: 0; padding: 2px 10px; }
.gsr .size-menu {
  position: absolute; right: 0; top: calc(100% + 4px); z-index: 2; display: none;
  padding: 4px; background: var(--glass); border: 1px solid var(--rule); border-radius: 6px;
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.45);
}
.gsr .size-menu.on { display: grid; gap: 2px; }
.gsr .size-menu button { margin: 0; width: 72px; text-align: right; border-color: transparent; background: transparent; }
.gsr .size-menu button.on { color: var(--active); border-color: var(--rule); }
.gsr .meter-track { width: 120px; height: 6px; background: var(--glass); border-radius: 3px; overflow: hidden; }
.gsr .meter-fill { height: 100%; width: 0%; background: linear-gradient(90deg, var(--fill), var(--active)); }

.gsr main { display: grid; grid-template-columns: 372px 1fr; column-gap: 16px; min-height: 0; }
.gsr .phase { display: flex; flex-direction: column; gap: 6px; }
.gsr .phase-canvas { display: block; border-radius: 6px; cursor: crosshair; touch-action: none; }
.gsr .phase-readout { padding: 0 2px; display: grid; gap: 2px; }
.gsr .phase-region-line { display: flex; align-items: baseline; gap: 10px; }
.gsr .phase-region { font-size: 16px; font-weight: 700; }
.gsr .phase-values { color: var(--ink-muted); white-space: pre; }
.gsr .phase-hint { color: var(--ink); }
.gsr .phase-resonance { color: var(--active); }

.gsr .lattice { display: flex; flex-direction: column; gap: 6px; }
.gsr .kymograph-wrap { position: relative; }
.gsr .kymograph { display: block; border-radius: 6px 6px 2px 2px; }
.gsr .profile { display: block; border-radius: 2px 2px 6px 6px; touch-action: none; cursor: ew-resize; }
.gsr .empty-note {
  position: absolute; inset: 0; display: grid; place-items: center;
  color: var(--ink-muted); font-size: 13px;
}
.gsr .time-label { position: absolute; right: 6px; font-size: 10px; color: var(--ink-muted); opacity: 0.8; }
.gsr .time-now { top: 4px; }
.gsr .time-ago { bottom: 4px; }

.gsr .controls { display: grid; grid-template-columns: repeat(3, 1fr); column-gap: 16px; }
.gsr .control-group { display: grid; gap: 4px; align-content: start; }
.gsr h2 {
  margin: 0 0 2px;
  font-size: 13px;
  font-weight: 600;
  color: var(--ink-muted);
  border-bottom: 1px solid var(--rule);
  padding-bottom: 3px;
}
.gsr .slider { display: grid; grid-template-columns: 96px 1fr 58px; align-items: center; column-gap: 8px; height: 22px; }
.gsr .slider-label { color: var(--ink); }
.gsr .slider-value { text-align: right; color: var(--ink-muted); }

.gsr input[type=range] { -webkit-appearance: none; appearance: none; width: 100%; height: 18px; background: transparent; margin: 0; }
.gsr input[type=range]::-webkit-slider-runnable-track { height: 4px; border-radius: 2px; background: var(--rule); }
.gsr input[type=range]::-webkit-slider-thumb {
  -webkit-appearance: none; width: 12px; height: 12px; margin-top: -4px; border-radius: 50%;
  background: var(--slide); border: 2px solid var(--accent);
}
.gsr input[type=range]::-moz-range-track { height: 4px; border-radius: 2px; background: var(--rule); }
.gsr input[type=range]::-moz-range-thumb { width: 10px; height: 10px; border-radius: 50%; background: var(--slide); border: 2px solid var(--accent); }
.gsr input[type=range]:hover::-webkit-slider-thumb { border-color: var(--active); }

.gsr button {
  justify-self: start;
  margin-top: 4px;
  font: inherit;
  color: var(--ink);
  background: var(--glass);
  border: 1px solid var(--rule);
  border-radius: 4px;
  padding: 3px 12px;
  cursor: pointer;
}
.gsr button:hover { border-color: var(--accent); }
.gsr :focus-visible { outline: 2px solid var(--active); outline-offset: 2px; }
`

type t = {
  root: element,
  bridge: Bridge.t,
  phase: PhasePlot.t,
  lattice: LatticeView.t,
  sliders: array<Controls.slider>,
  meterFill: element,
  mutable level: float,
  mutable shownLevel: float,
  mutable frameHandle: option<int>,
  mutable cleanups: array<unit => unit>,
}

// One animation frame per change, never a free-running loop.
let render = app => {
  app.frameHandle = None
  PhasePlot.render(app.phase)
  LatticeView.render(app.lattice)
  // the meter moves in 1 % steps, so a steady level writes no styles
  let level = Math.round(Math.min(1.0, app.level *. 2.0) *. 100.0)
  if level != app.shownLevel {
    app.shownLevel = level
    setStyle(app.meterFill, "width", Float.toString(level) ++ "%")
  }
}

let invalidate = app =>
  if app.frameHandle->Option.isNone {
    app.frameHandle = Some(requestAnimationFrame(_ => render(app)))
  }

// The interface size control: only shown where the plugin keeps the setting and sizes the
// window (the CLAP plugin), as nano-clap's settings dialog does.
let makeSizeControl = (settings: Settings.t) => {
  let box = div(~className="size")
  let toggle = createElement("button")
  setAttribute(toggle, "type", "button")
  setAttribute(toggle, "title", "Size of the interface")
  let menu = div(~className="size-menu")
  let percent = zoom => Float.toString(Math.round(zoom *. 100.)) ++ "%"
  let steps = Settings.zoomSteps->Array.map(zoom => {
    let b = createElement("button")
    setAttribute(b, "type", "button")
    setTextContent(b, percent(zoom))
    b->addEventListener("click", _ => {
      settings->Settings.setZoom(zoom)
      menu->toggleClass("on", false)
    })
    menu->appendChild(b)
    (zoom, b)
  })
  toggle->addEventListener("click", _ => menu->toggleClass("on", true))
  box->appendChild(toggle)
  box->appendChild(menu)

  let update = () => {
    setStyle(box, "display", settings->Settings.available ? "block" : "none")
    setTextContent(toggle, "Size " ++ percent(settings.zoom))
    steps->Array.forEach(((zoom, b)) => b->toggleClass("on", Math.abs(zoom -. settings.zoom) < 0.005))
  }
  update()
  let stopListening = settings->Settings.listen(update)
  // a press anywhere else closes the menu
  let stopOutside = listenDocument(
    "pointerdown",
    ev =>
      if !(box->contains(ev->originalTarget)) {
        menu->toggleClass("on", false)
      },
    ~capture=true,
    ~passive=true,
  )
  (
    box,
    () => {
      stopListening()
      stopOutside()
    },
  )
}

let make = (connection: CmajorBindings.patchConnection, host: element) => {
  let bridge = Bridge.make(connection)
  let restoreBrowserChrome = BrowserChrome.install()
  let settings = Settings.make(connection)
  let hostMenu = HostMenu.make(connection)

  // the page around the view shows while a host resizes the window
  setStyle(documentElement, "background", Palette.slide)

  let shadow = shadowRootOf(host)
  let style = createElement("style")
  setTextContent(style, stylesheet)
  shadow->appendChild(style)
  let root = div(~className="gsr")
  shadow->appendChild(root)

  // Header
  let header = createElement("header")
  let title = createElement("h1")
  setInnerHTML(title, "Gray-Scott <b>Resonator</b>")
  let subtitle = createElement("span")
  setClassName(subtitle, "subtitle")
  setTextContent(subtitle, "Reaction-diffusion on a 128-node ring")
  let meter = div(~className="meter")
  let meterLabel = createElement("span")
  setTextContent(meterLabel, "Lattice level")
  let meterTrack = div(~className="meter-track")
  let meterFill = div(~className="meter-fill")
  meterTrack->appendChild(meterFill)
  meter->appendChild(meterLabel)
  meter->appendChild(meterTrack)
  let (sizeControl, stopSizeControl) = makeSizeControl(settings)
  header->appendChild(title)
  header->appendChild(subtitle)
  header->appendChild(meter)
  header->appendChild(sizeControl)

  // Phase plane (F, K move together under one gesture)
  let phase = PhasePlot.make(
    ~onChange=(~f, ~k) => {
      Bridge.set(bridge, Feed, f)
      Bridge.set(bridge, Kill, k)
    },
    ~onGestureStart=() => {
      Bridge.beginGesture(bridge, Feed)
      Bridge.beginGesture(bridge, Kill)
    },
    ~onGestureEnd=() => {
      Bridge.endGesture(bridge, Feed)
      Bridge.endGesture(bridge, Kill)
    },
  )

  // Controls (built before the lattice view so pickup drags can update the slider)
  let reseed = createElement("button")
  setAttribute(reseed, "type", "button")
  setTextContent(reseed, "Reseed lattice")
  reseed->addEventListener("click", _ => Bridge.reseed(bridge))

  let (controls, sliders) = Controls.make(
    bridge,
    ~hostMenu,
    ~onLocalChange=(param, value) =>
      switch param {
      | Speed => PhasePlot.setSpeed(phase, value)
      | _ => ()
      },
    ~extra=reseed,
  )
  let sliderFor = param => sliders->Array.find(s => s.param == param)

  let lattice = LatticeView.make(
    ~onPickupDistance=d => {
      Bridge.set(bridge, TapDistance, d)
      sliderFor(TapDistance)->Option.forEach(s => Controls.show(s, d))
    },
    ~onGestureStart=() => Bridge.beginGesture(bridge, TapDistance),
    ~onGestureEnd=() => Bridge.endGesture(bridge, TapDistance),
  )

  let main = createElement("main")
  main->appendChild(phase.element)
  main->appendChild(lattice.element)

  root->appendChild(header)
  root->appendChild(main)
  root->appendChild(controls)

  let app = {
    root,
    bridge,
    phase,
    lattice,
    sliders,
    meterFill,
    level: 0.0,
    shownLevel: -1.0,
    frameHandle: None,
    cleanups: [],
  }
  phase.invalidate = () => invalidate(app)
  lattice.invalidate = () => invalidate(app)

  // Scaling: the stage keeps the design size, scaled to fit the window and centred in it.
  let supportsZoom = cssSupports("zoom", "2")
  let layout = () => {
    let orDesign = (x, design) => x == 0. ? design : x
    let w = host->clientWidth->orDesign(designWidth)
    let h = host->clientHeight->orDesign(designHeight)
    let scale = Math.min(w /. designWidth, h /. designHeight)
    let ox = Math.max(0., (w -. designWidth *. scale) /. 2.)
    let oy = Math.max(0., (h -. designHeight *. scale) /. 2.)
    let px = v => Float.toString(v) ++ "px"
    if supportsZoom {
      // (a zoomed element's own left and top are zoomed too)
      setStyle(root, "zoom", Float.toString(scale))
      setStyle(root, "left", px(ox /. scale))
      setStyle(root, "top", px(oy /. scale))
    } else {
      setStyle(
        root,
        "transform",
        "translate(" ++ px(ox) ++ ", " ++ px(oy) ++ ") scale(" ++ Float.toString(scale) ++ ")",
      )
    }
  }
  let resizeObserver = makeResizeObserver(layout)
  resizeObserver->observe(host)
  layout()

  // Host → GUI
  Bridge.onParameterChange(bridge, (param, value) =>
    switch param {
    | Feed => PhasePlot.setFK(phase, ~f=value, ~k=phase.k)
    | Kill => PhasePlot.setFK(phase, ~f=phase.f, ~k=value)
    | other =>
      sliderFor(other)->Option.forEach(s => Controls.show(s, value))
      if other == Speed {
        PhasePlot.setSpeed(phase, value)
      }
    }
  )
  Bridge.onLatticeFrame(bridge, frame => {
    LatticeView.pushFrame(lattice, frame)
    app.level = frame.level
  })

  app.cleanups = [
    () => resizeObserver->disconnect,
    restoreBrowserChrome,
    stopSizeControl,
    () => settings->Settings.dispose,
    () => hostMenu->HostMenu.dispose,
  ]
  invalidate(app)
  app
}

let stop = app => {
  switch app.frameHandle {
  | Some(handle) => cancelAnimationFrame(handle)
  | None => ()
  }
  app.frameHandle = None
  Bridge.dispose(app.bridge)
  app.cleanups->Array.forEach(cleanup => cleanup())
  app.cleanups = []
}
