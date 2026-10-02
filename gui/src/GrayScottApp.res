// Top-level view: two pages on one stage, wired to the patch through the typed Bridge.
//
//  * Play (the default): what you see is what you hear. The chemistry as a culture in a dish,
//    lit up along the resonator ring where your sound is ringing (TuringDish); a plain-language
//    readout of what you'll hear, and the resonance as a frequency response whose peak you can
//    drag; and six knobs, in two groups, that say what they do in the units you hear — Pitch as
//    a note (in tune unless you hold Shift), Ring as a decay time, Color as the regime (see
//    Macro.res for how the macros map onto the parameters). Click a knob's value to type one.
//  * Lab: the F×K phase plane and every parameter on a slider.
//
// Every parameter lives in one mirror (values). Whatever moves it — a knob, a slider, the phase
// plane, a preset, host automation — goes through applyValue, so every view agrees.
//
// The Play page also keeps two targets, the note and the ring you asked for (targetHz,
// targetRing). Pitch, Ring, Color and the response plot set them, and realise solves Speed and
// Resonance for them at the current F and K, so turning one keeps the others where you put them.
// A target out of reach stays a target: you hear the nearest the chemistry can do, and turning
// back brings it back. Anything else that moves F, K, Speed or Resonance (the Lab page, a preset,
// the host) resets the targets to what it put there; the host's echo of a value this view just
// sent doesn't.
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
//    parameter menu opens on a double right-click on a slider or knob (HostMenu).
//  - In the CLAP plugin the interface size and the page you were on are user settings
//    (Settings): the Size control asks the host to resize the window.
//  - Nothing repaints on a timer: a change (a lattice snapshot, a moved parameter) schedules one
//    animation frame, and only the page on show is drawn.

open Web
module Param = CmajorBindings.Param
module Bridge = CmajorBindings.Bridge
module T = GrayScottTheory

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
  --warn: ${Palette.warn};
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
  overflow: hidden;
  display: grid;
  grid-template-rows: auto 1fr;
  row-gap: 10px;
}
.gsr *, .gsr *::before, .gsr *::after { box-sizing: inherit; }

.gsr button {
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

/* header */
.gsr header { display: flex; align-items: center; gap: 12px; height: 30px; }
.gsr h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: 0.02em; color: var(--accent); }
.gsr .presets { position: relative; display: flex; align-items: center; gap: 2px; margin-left: 6px; }
.gsr .presets > button { padding: 2px 8px; }
.gsr .preset-name { min-width: 168px; text-align: left; display: flex; align-items: baseline; gap: 8px; }
.gsr .preset-name .edited { color: var(--ink-muted); font-size: 11px; }
.gsr .preset-menu {
  position: absolute; left: 0; top: calc(100% + 4px); z-index: 3; display: none; width: 360px;
  padding: 4px; background: var(--glass); border: 1px solid var(--rule); border-radius: 6px;
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.5);
}
.gsr .preset-menu.on { display: grid; gap: 1px; }
.gsr .preset-menu button {
  display: grid; gap: 1px; text-align: left; border-color: transparent; background: transparent; padding: 5px 8px;
}
.gsr .preset-menu button:hover, .gsr .preset-menu button.on { background: var(--slide); border-color: var(--rule); }
.gsr .preset-menu .name { font-weight: 600; }
.gsr .preset-menu button.on .name { color: var(--accent); }
.gsr .preset-menu .desc { color: var(--ink-muted); font-size: 11px; }
.gsr .spacer { flex: 1; }
.gsr .pages { display: flex; }
.gsr .pages button { padding: 2px 14px; border-radius: 0; }
.gsr .pages button:first-child { border-radius: 4px 0 0 4px; }
.gsr .pages button:last-child { border-radius: 0 4px 4px 0; border-left: none; }
.gsr .pages button.on { background: var(--accent); color: var(--slide); border-color: var(--accent); font-weight: 600; }
.gsr .meter { display: flex; align-items: center; gap: 6px; color: var(--ink-muted); }
.gsr .meter-track { width: 72px; height: 6px; background: var(--glass); border-radius: 3px; overflow: hidden; }
.gsr .meter-fill { height: 100%; width: 0%; background: linear-gradient(90deg, var(--fill), var(--accent)); }
.gsr .size { position: relative; }
.gsr .size > button { padding: 2px 10px; }
.gsr .size-menu {
  position: absolute; right: 0; top: calc(100% + 4px); z-index: 3; display: none;
  padding: 4px; background: var(--glass); border: 1px solid var(--rule); border-radius: 6px;
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.5);
}
.gsr .size-menu.on { display: grid; gap: 2px; }
.gsr .size-menu button { width: 72px; text-align: right; border-color: transparent; background: transparent; }
.gsr .size-menu button.on { color: var(--active); border-color: var(--rule); }

/* pages */
.gsr .page { display: none; min-height: 0; }
.gsr .page.on { display: grid; }
.gsr .play { grid-template-rows: auto auto 1fr; row-gap: 10px; }
.gsr .play-top { display: grid; grid-template-columns: 304px 1fr; column-gap: 14px; }
.gsr .dish-box { display: grid; gap: 4px; }
.gsr .dish { display: block; border-radius: 8px; background: var(--glass); }
.gsr .caption { color: var(--ink-muted); font-size: 11px; line-height: 1.35; }
.gsr .hear { display: grid; align-content: start; gap: 8px; }
.gsr .hear-note { display: flex; align-items: baseline; gap: 10px; }
.gsr .hear-note b { font-size: 40px; line-height: 1; font-weight: 700; color: var(--accent); }
.gsr .hear-note span { font-size: 16px; color: var(--ink); }
.gsr .hear-note .cents { color: var(--ink-muted); }
.gsr .hear-ring { font-size: 15px; color: var(--ink); }
.gsr .hear-regime { font-size: 12px; color: var(--ink-muted); }
.gsr .hear-regime b { color: var(--ink); font-weight: 600; }
.gsr .hear-label { margin-top: 6px; font-size: 11px; color: var(--ink-muted); }
.gsr .lab { grid-template-rows: 1fr auto; row-gap: 10px; }

/* the lattice view (both pages) */
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

/* play page */
.gsr .response { display: block; border-radius: 6px; touch-action: none; }
.gsr .response.draggable { cursor: grab; }
.gsr .response.dragging { cursor: grabbing; }
.gsr .knob-groups { display: grid; grid-template-columns: 1fr 1fr; column-gap: 14px; }
.gsr .knob-group h2 { margin-bottom: 4px; }
.gsr .knobs { display: grid; grid-template-columns: repeat(3, 1fr); align-items: start; }
.gsr .knob { display: grid; justify-items: center; gap: 2px; padding: 4px 0; border-radius: 8px; outline-offset: -2px; }
.gsr .knob svg { display: block; cursor: ns-resize; touch-action: none; }
.gsr .knob-label { font-size: 13px; font-weight: 600; color: var(--ink); }
.gsr .knob-text { font-size: 14px; color: var(--accent); min-height: 17px; padding: 0 4px; border-radius: 3px; }
.gsr .knob-text.editable { cursor: text; }
.gsr .knob-text.editable:hover { background: var(--glass); }
.gsr .knob-input {
  display: none; width: 104px; height: 19px; margin: -1px 0; padding: 0 4px;
  font: inherit; font-size: 14px; text-align: center; color: var(--accent);
  background: var(--glass); border: 1px solid var(--accent); border-radius: 3px;
  user-select: text; -webkit-user-select: text;
}
.gsr .knob-input:focus-visible { outline: none; }
.gsr .knob.editing .knob-text { display: none; }
.gsr .knob.editing .knob-input { display: block; }
.gsr .invalid { animation: shake 0.4s ease-out; }
@keyframes shake {
  0%, 60% { color: var(--warn); border-color: var(--warn); }
  0%, 100% { transform: translateX(0); }
  20%, 60% { transform: translateX(-4px); }
  40%, 80% { transform: translateX(4px); }
}
.gsr .knob-detail { font-size: 11px; color: var(--ink-muted); min-height: 14px; }
.gsr .knob-track { fill: none; stroke: var(--rule); stroke-width: 5; stroke-linecap: round; }
.gsr .knob-value { fill: none; stroke: var(--accent); stroke-width: 5; stroke-linecap: round; }
.gsr .knob-cap { fill: var(--glass); stroke: var(--rule); stroke-width: 1; }
.gsr .knob-pointer { stroke: var(--active); stroke-width: 2.5; stroke-linecap: round; }
.gsr .knob:hover .knob-cap, .gsr .knob.active .knob-cap { stroke: var(--accent); }
.gsr .knob.muted .knob-value { stroke: var(--ink-muted); }
.gsr .knob.muted .knob-text { color: var(--ink-muted); }

/* lab page */
.gsr main { display: grid; grid-template-columns: 372px 1fr; column-gap: 16px; min-height: 0; }
.gsr .phase { display: flex; flex-direction: column; gap: 6px; }
.gsr .phase-canvas { display: block; border-radius: 6px; cursor: crosshair; touch-action: none; }
.gsr .phase-readout { padding: 0 2px; display: grid; gap: 2px; }
.gsr .phase-region-line { display: flex; align-items: baseline; gap: 10px; }
.gsr .phase-region { font-size: 16px; font-weight: 700; }
.gsr .phase-values { color: var(--ink-muted); white-space: pre; }
.gsr .phase-hint { color: var(--ink); }
.gsr .phase-resonance { color: var(--active); }

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
.gsr .control-group > button { justify-self: start; margin-top: 4px; }

.gsr input[type=range] { -webkit-appearance: none; appearance: none; width: 100%; height: 18px; background: transparent; margin: 0; }
.gsr input[type=range]::-webkit-slider-runnable-track { height: 4px; border-radius: 2px; background: var(--rule); }
.gsr input[type=range]::-webkit-slider-thumb {
  -webkit-appearance: none; width: 12px; height: 12px; margin-top: -4px; border-radius: 50%;
  background: var(--slide); border: 2px solid var(--accent);
}
.gsr input[type=range]::-moz-range-track { height: 4px; border-radius: 2px; background: var(--rule); }
.gsr input[type=range]::-moz-range-thumb { width: 10px; height: 10px; border-radius: 50%; background: var(--slide); border: 2px solid var(--accent); }
.gsr input[type=range]:hover::-webkit-slider-thumb { border-color: var(--active); }
`

type page = Play | Lab

// What each regime does, in the Play page's terms
let playHint = (region: GrayScottTheory.region) =>
  switch region {
  | Chaos => "Rough and restless: it never quite settles."
  | Drones => "A clean, tuned resonance. Turn up Ring to make it sing."
  | Stripes => "A resonance with patterns forming in the chemistry."
  | Damped => "Short, plucky rings."
  | Spots => "Input sparks short-lived spots; little ringing."
  | Solitons => "Loud input fires pulses around the ring."
  | Silent => "Nothing rings here."
  }

// A drag on the response plot's peak: where it started, and which ways it has moved so far (a
// sideways drag leaves the ring alone, and an up-and-down one the pitch, so an out-of-reach
// target on the other axis isn't lost to a pixel of wobble).
type peakDrag = {
  startHz: float,
  startRing: float, // Ring knob position
  mutable across: bool,
  mutable upDown: bool,
}

type knobs = {
  pitch: Knob.t,
  ring: Knob.t,
  color: Knob.t,
  drive: Knob.t,
  mix: Knob.t,
  output: Knob.t,
}

type t = {
  bridge: Bridge.t,
  dish: TuringDish.t,
  phase: PhasePlot.t,
  labLattice: LatticeView.t,
  response: ResponsePlot.t,
  meterFill: element,
  mutable page: page,
  mutable level: float,
  mutable shownLevel: float,
  mutable frameHandle: option<int>,
  mutable cleanups: array<unit => unit>,
}

// One animation frame per change, never a free-running loop; only the page on show is drawn.
let render = app => {
  app.frameHandle = None
  switch app.page {
  | Play =>
    TuringDish.render(app.dish)
    ResponsePlot.render(app.response)
  | Lab =>
    PhasePlot.render(app.phase)
    LatticeView.render(app.labLattice)
  }
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

// Closes a popup menu on a press anywhere outside its box. Returns the function that stops it.
let closeOnOutsidePress = (box, menu) =>
  listenDocument(
    "pointerdown",
    ev =>
      if !(box->contains(ev->originalTarget)) {
        menu->toggleClass("on", false)
      },
    ~capture=true,
    ~passive=true,
  )

let button = (~text, ~title=?) => {
  let b = createElement("button")
  setAttribute(b, "type", "button")
  setTextContent(b, text)
  title->Option.forEach(t => setAttribute(b, "title", t))
  b
}

// The interface size control: only shown where the plugin keeps the setting and sizes the
// window (the CLAP plugin), as nano-clap's settings dialog does.
let makeSizeControl = (settings: Settings.t) => {
  let box = div(~className="size")
  let toggle = button(~text="", ~title="Size of the interface")
  let menu = div(~className="size-menu")
  let percent = zoom => Float.toString(Math.round(zoom *. 100.)) ++ "%"
  let steps = Settings.zoomSteps->Array.map(zoom => {
    let b = button(~text=percent(zoom))
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
  let stopOutside = closeOnOutsidePress(box, menu)
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

  //==============================================================================
  // The parameter mirror, and the one place a value changes

  let values = Dict.make()
  Param.all->Array.forEach(p => values->Dict.set(Param.id(p), Param.spec(p).init))
  let valueOf = p => values->Dict.get(Param.id(p))->Option.getOr(Param.spec(p).init)
  let currentF = () => valueOf(Feed)
  let currentK = () => valueOf(Kill)
  let currentSpeed = () => valueOf(Speed)
  let currentResonance = () => valueOf(Feedback)
  let currentDu = () => valueOf(DiffusionU)

  // Views built below call back into send and refreshDerived, which need those views.
  let onPhaseMove: ref<(float, float) => unit> = ref((_, _) => ())
  let onPickupMove: ref<float => unit> = ref(_ => ())
  let onPeakDragStart = ref(() => ())
  let onPeakDrag: ref<(float, float, bool) => unit> = ref((_, _, _) => ())
  let onPeakDragEnd = ref(() => ())
  let onPlotWheel: ref<(bool, bool) => unit> = ref((_, _) => ())

  // The Play page's targets: the note and the ring you asked for (see the top of this file).
  let targetHz = ref(220.0)
  let targetRing = ref(Macro.Fades(0.5))
  // Something other than the Play page's macros has moved the parameters: what they give now is
  // the new target. (Where there's no focus there's nothing to read, so the old targets stay.)
  let currentFocus = () =>
    Macro.focus(
      ~f=currentF(),
      ~k=currentK(),
      ~speed=currentSpeed(),
      ~resonance=currentResonance(),
      ~du=currentDu(),
    )
  let adoptTargets = () =>
    currentFocus()->Option.forEach(focus => {
      let (hz, ring) = Macro.targetsOf(focus, ~resonance=currentResonance())
      targetHz := hz
      targetRing := ring
    })
  adoptTargets()
  let affectsTargets = (p: Param.t) =>
    switch p {
    | Feed | Kill | Speed | Feedback | DiffusionU => true
    | _ => false
    }

  //==============================================================================
  // Views

  let phase = PhasePlot.make(
    ~onChange=(~f, ~k) => onPhaseMove.contents(f, k),
    ~onGestureStart=() => {
      Bridge.beginGesture(bridge, Feed)
      Bridge.beginGesture(bridge, Kill)
    },
    ~onGestureEnd=() => {
      Bridge.endGesture(bridge, Feed)
      Bridge.endGesture(bridge, Kill)
    },
  )
  let dish = TuringDish.make(~size=304)
  let lattice = (~width, ~kymoHeight, ~profileHeight) =>
    LatticeView.make(
      ~width,
      ~kymoHeight,
      ~profileHeight,
      ~onPickupDistance=d => onPickupMove.contents(d),
      ~onGestureStart=() => Bridge.beginGesture(bridge, TapDistance),
      ~onGestureEnd=() => Bridge.endGesture(bridge, TapDistance),
    )
  let labLattice = lattice(~width=468, ~kymoHeight=222, ~profileHeight=92)
  let response = ResponsePlot.make(
    ~width=530,
    ~height=184,
    ~onDragStart=() => onPeakDragStart.contents(),
    ~onDrag=(~octaves, ~rise, ~fine) => onPeakDrag.contents(octaves, rise, fine),
    ~onDragEnd=() => onPeakDragEnd.contents(),
    ~onWheel=(~up, ~fine) => onPlotWheel.contents(up, fine),
  )

  // What you'll hear, in words
  let hearNote = div(~className="hear-note")
  let hearNoteName = createElement("b")
  let hearCents = createElement("span")
  setClassName(hearCents, "cents")
  let hearHz = createElement("span")
  hearNote->appendChild(hearNoteName)
  hearNote->appendChild(hearCents)
  hearNote->appendChild(hearHz)
  let hearRing = div(~className="hear-ring")
  let hearRegime = div(~className="hear-regime")

  //==============================================================================
  // Header

  let header = createElement("header")
  let title = createElement("h1")
  setTextContent(title, "Ectoplasm")
  setAttribute(title, "title", "A Gray-Scott reaction-diffusion resonator")

  let presetBox = div(~className="presets")
  let previous = button(~text="‹", ~title="Previous preset")
  let presetName = button(~text="")
  setClassName(presetName, "preset-name")
  let presetLabel = createElement("span")
  let editedLabel = createElement("span")
  setClassName(editedLabel, "edited")
  presetName->appendChild(presetLabel)
  presetName->appendChild(editedLabel)
  let next = button(~text="›", ~title="Next preset")
  let presetMenu = div(~className="preset-menu")
  presetBox->appendChild(previous)
  presetBox->appendChild(presetName)
  presetBox->appendChild(next)
  presetBox->appendChild(presetMenu)

  let pages = div(~className="pages")
  let playButton = button(~text="Play", ~title="Macro knobs and the sound you'll hear")
  let labButton = button(~text="Lab", ~title="The F×K phase plane and every parameter")
  pages->appendChild(playButton)
  pages->appendChild(labButton)

  let meter = div(~className="meter")
  let meterLabel = createElement("span")
  setTextContent(meterLabel, "Level")
  let meterTrack = div(~className="meter-track")
  let meterFill = div(~className="meter-fill")
  meterTrack->appendChild(meterFill)
  meter->appendChild(meterLabel)
  meter->appendChild(meterTrack)
  let (sizeControl, stopSizeControl) = makeSizeControl(settings)

  header->appendChild(title)
  header->appendChild(presetBox)
  header->appendChild(div(~className="spacer"))
  header->appendChild(pages)
  header->appendChild(meter)
  header->appendChild(sizeControl)

  let app = {
    bridge,
    dish,
    phase,
    labLattice,
    response,
    meterFill,
    page: Play,
    level: 0.0,
    shownLevel: -1.0,
    frameHandle: None,
    cleanups: [],
  }
  phase.invalidate = () => invalidate(app)
  dish.invalidate = () => invalidate(app)
  labLattice.invalidate = () => invalidate(app)
  response.invalidate = () => invalidate(app)

  let sliders: ref<array<Controls.slider>> = ref([])
  let knobsRef: ref<option<knobs>> = ref(None)
  let lastPreset: ref<option<Presets.preset>> = ref(None)

  let refreshPresetLabel = () => {
    let matching = Presets.all->Array.find(p => Presets.matches(p, valueOf))
    switch (matching, lastPreset.contents) {
    | (Some(p), _) =>
      setTextContent(presetLabel, p.name)
      setTextContent(editedLabel, "")
      presetName->setAttribute("title", p.description)
    | (None, Some(p)) =>
      setTextContent(presetLabel, p.name)
      setTextContent(editedLabel, "edited")
      presetName->setAttribute("title", p.description ++ " (edited)")
    | (None, None) =>
      setTextContent(presetLabel, "Custom")
      setTextContent(editedLabel, "")
      presetName->setAttribute("title", "Pick a preset")
    }
  }

  // What the knobs, the response plot and the preset name show follows from all the values.
  let refreshDerived = () => {
    let f = currentF()
    let k = currentK()
    let speed = currentSpeed()
    let resonance = currentResonance()
    let du = currentDu()
    ResponsePlot.set(
      response,
      {
        f,
        k,
        du,
        ratio: valueOf(DiffusionRatio),
        speed,
        resonance,
        tap: valueOf(TapDistance),
        drive: valueOf(Drive),
        mix: valueOf(Mix),
        outputDb: valueOf(OutputGain),
      },
    )
    PhasePlot.setResonance(phase, resonance)
    knobsRef.contents->Option.forEach(knobs => {
      let focus = Macro.focus(~f, ~k, ~speed, ~resonance, ~du)
      let approximate = Macro.pitchIsApproximate(~ratio=valueOf(DiffusionRatio), ~drive=valueOf(Drive))
      TuringDish.setChemistry(dish, ~f, ~k)
      let region = T.classify(~f, ~k)
      // where a target is out of reach, which way (what you hear is the nearest it can get)
      let pitchLimit = hz => {
        let short = Macro.midiOf(targetHz.contents) -. Macro.midiOf(hz)
        short > 0.05 ? Some("highest here") : short < -0.05 ? Some("lowest here") : None
      }
      let ringLimit = seconds =>
        switch targetRing.contents {
        | Fades(target) if seconds < target *. 0.995 => Some("longest here")
        | Fades(target) if seconds > target *. 1.005 => Some("shortest here")
        | _ => None
        }
      switch focus {
      | Some({hz, ringSeconds}) =>
        setTextContent(hearNoteName, (approximate ? "≈ " : "") ++ Macro.noteName(hz))
        setTextContent(hearCents, approximate ? "" : Macro.centsText(hz)->Option.getOr("in tune"))
        setTextContent(
          hearHz,
          Macro.formatHz(hz) ++ pitchLimit(hz)->Option.mapOr("", limit => " (the " ++ limit ++ ")"),
        )
        setTextContent(
          hearRing,
          switch ringSeconds {
          | Some(s) =>
            "Rings for " ++
            Macro.formatSeconds(s) ++
            " after each sound" ++
            ringLimit(s)->Option.mapOr("", limit => ", the " ++ limit)
          | None => "Sustains on its own once it's been played"
          },
        )
      | None =>
        setTextContent(hearNoteName, "No note")
        setTextContent(hearCents, "")
        setTextContent(hearHz, "")
        setTextContent(hearRing, "Nothing rings at this Color. Turn it, or pick a preset.")
      }
      setInnerHTML(hearRegime, "<b>" ++ T.regionName(region) ++ ".</b> " ++ playHint(region))
      switch focus {
      | Some({hz}) =>
        knobs.pitch->Knob.set(
          Macro.hzToNorm(hz),
          ~text=(approximate ? "≈ " : "") ++ Macro.tuning(hz),
          // (one of the two, to fit on a line: "≈" already says it's rough)
          ~detail=Macro.formatHz(hz) ++
          switch (pitchLimit(hz), approximate) {
          | (Some(limit), _) => ", " ++ limit
          | (None, true) => ", roughly"
          | (None, false) => ""
          },
        )
      | None =>
        knobs.pitch->Knob.set(
          Param.toNormalised(Speed, speed),
          ~text="Speed " ++ Float.toFixed(speed, ~digits=2) ++ "×",
          ~detail="no pitch here",
          ~muted=true,
        )
      }
      switch focus {
      | Some({ringSeconds: Some(seconds)}) =>
        knobs.ring->Knob.set(
          Macro.ringToNorm(Fades(seconds)),
          ~text=Macro.formatSeconds(seconds),
          ~detail=ringLimit(seconds)->Option.getOr("to fade 60 dB"),
        )
      | Some({ringSeconds: None}) =>
        knobs.ring->Knob.set(
          Macro.ringToNorm(Sustains(resonance)),
          ~text="Sustains",
          ~detail="self-oscillates",
        )
      | None =>
        knobs.ring->Knob.set(
          Macro.ringToNorm(targetRing.contents),
          ~text="No focus",
          ~detail="turn Color",
          ~muted=true,
        )
      }
      let (color, onBand) = Macro.colorOf(~f, ~k)
      let region = T.regionName(T.classify(~f, ~k))
      knobs.color->Knob.set(
        color,
        ~text=region,
        ~detail=onBand ? "K " ++ Float.toFixed(k, ~digits=4) : "Lab setting, turn to retune",
        ~muted=!onBand,
      )
      let show = (knob, p) =>
        knob->Knob.set(Param.toNormalised(p, valueOf(p)), ~text=Param.spec(p).format(valueOf(p)), ~detail="")
      show(knobs.drive, Drive)
      show(knobs.mix, Mix)
      show(knobs.output, OutputGain)
    })
    refreshPresetLabel()
  }

  // A value has changed, from anywhere: mirror it and show it in the views that show it directly.
  let applyValue = (param: Param.t, value) => {
    let value = Param.clamp(param, value)
    values->Dict.set(Param.id(param), value)
    switch param {
    | Feed | Kill => PhasePlot.setFK(phase, ~f=currentF(), ~k=currentK())
    | Speed => PhasePlot.setSpeed(phase, value)
    | DiffusionU => PhasePlot.setDiffusion(phase, value)
    | _ => ()
    }
    sliders.contents
    ->Array.find(s => s.param == param)
    ->Option.forEach(s =>
      if s.value != value {
        Controls.show(s, value)
      }
    )
  }

  // ...and when it came from this view, send it on.
  let send = (param, value) => {
    applyValue(param, value)
    Bridge.set(bridge, param, valueOf(param))
  }

  onPhaseMove :=
    (f, k) => {
      send(Feed, f)
      send(Kill, k)
      adoptTargets()
      refreshDerived()
    }
  onPickupMove :=
    d => {
      send(TapDistance, d)
      refreshDerived()
    }

  //==============================================================================
  // Presets

  let selectPreset = (preset: Presets.preset) => {
    lastPreset := Some(preset)
    preset.values->Array.forEach(((p, v)) => {
      Bridge.beginGesture(bridge, p)
      send(p, v)
      Bridge.endGesture(bridge, p)
    })
    // start the ring from rest on the new chemistry
    Bridge.reseed(bridge)
    adoptTargets()
    refreshDerived()
  }

  let step = delta => {
    let count = Array.length(Presets.all)
    let index = switch lastPreset.contents {
    | Some(p) => Presets.all->Array.findIndex(q => q.name == p.name)
    | None => -1
    }
    Presets.all[mod(index + delta + count, count)]->Option.forEach(selectPreset)
  }
  previous->addEventListener("click", _ => step(-1))
  next->addEventListener("click", _ => step(1))

  let menuButtons = Presets.all->Array.map(preset => {
    let b = button(~text="")
    let name = createElement("span")
    setClassName(name, "name")
    setTextContent(name, preset.name)
    let desc = createElement("span")
    setClassName(desc, "desc")
    setTextContent(desc, preset.description)
    b->appendChild(name)
    b->appendChild(desc)
    b->addEventListener("click", _ => {
      selectPreset(preset)
      presetMenu->toggleClass("on", false)
    })
    presetMenu->appendChild(b)
    (preset, b)
  })
  presetName->addEventListener("click", _ => {
    menuButtons->Array.forEach(((p, b)) => b->toggleClass("on", Presets.matches(p, valueOf)))
    presetMenu->toggleClass("on", true)
  })
  let stopPresetMenu = closeOnOutsidePress(presetBox, presetMenu)

  //==============================================================================
  // Play page

  // Puts Speed and Resonance where the targets say at the current F and K.
  let realise = () => {
    let (f, k) = (currentF(), currentK())
    let (speed, resonance) = Macro.solve(
      ~f,
      ~k,
      ~hz=targetHz.contents,
      ~ring=targetRing.contents,
      ~resonance=currentResonance(),
      ~du=currentDu(),
    )
    if Macro.focus(~f, ~k, ~speed, ~resonance, ~du=currentDu())->Option.isSome {
      send(Feedback, resonance)
      send(Speed, speed)
    } else {
      // No focus here to tune. A sustain is still a Resonance; a fade waits for Color to bring
      // the chemistry back to the band.
      switch targetRing.contents {
      | Sustains(resonance) => send(Feedback, resonance)
      | Fades(_) => ()
      }
    }
    refreshDerived()
  }
  let hasFocus = () => currentFocus()->Option.isSome
  let gestures = (params: array<Param.t>) => (
    () => params->Array.forEach(p => Bridge.beginGesture(bridge, p)),
    () => params->Array.forEach(p => Bridge.endGesture(bridge, p)),
  )
  let (colorStart, colorEnd) = gestures([Feed, Kill, Speed, Feedback])
  let (tuningStart, tuningEnd) = gestures([Speed, Feedback])

  let moveOnBand = color => {
    let (f, k) = Macro.toFK(color)
    send(Feed, f)
    send(Kill, k)
    realise()
  }
  let setPitch = hz => {
    targetHz := Macro.clampHz(hz)
    realise()
  }
  let setRing = n => {
    targetRing := Macro.normToRing(n)
    realise()
  }

  let paramKnob = (param: Param.t, ~label, ~title, ~parse, ~typeHint) =>
    Knob.make(
      ~label,
      ~title,
      ~defaultValue=Param.toNormalised(param, Param.spec(param).init),
      ~onChange=n => {
        send(param, Param.fromNormalised(param, n))
        refreshDerived()
      },
      ~onGestureStart=() => Bridge.beginGesture(bridge, param),
      ~onGestureEnd=() => Bridge.endGesture(bridge, param),
      ~parse=text => parse(text)->Option.map(v => Param.toNormalised(param, v)),
      ~typeHint,
    )
  let init = p => Param.spec(p).init
  let (initColor, _) = Macro.colorOf(~f=init(Feed), ~k=init(Kill))
  let (initHz, initRing) =
    Macro.focus(
      ~f=init(Feed),
      ~k=init(Kill),
      ~speed=init(Speed),
      ~resonance=init(Feedback),
      ~du=init(DiffusionU),
    )
    ->Option.map(Macro.targetsOf(_, ~resonance=init(Feedback)))
    ->Option.getOr((293.66, Macro.Fades(0.5)))
  // Pitch snaps to semitones, as knob positions
  let semitones: Knob.snap = {
    nearest: n => Macro.hzToNorm(Macro.nearestSemitone(Macro.normToHz(n))),
    step: (n, steps) => Macro.hzToNorm(Macro.semitoneStep(Macro.normToHz(n), steps)),
    bigStep: 12,
  }
  let knobs = {
    pitch: Knob.make(
      ~label="Pitch",
      ~title="The note the lattice rings at, in semitones (hold Shift for anything in between). Color and Ring keep it where you put it.",
      // (the note nearest the parameters' defaults, so a reset lands in tune)
      ~defaultValue=Macro.hzToNorm(Macro.nearestSemitone(initHz)),
      ~onChange=n =>
        if hasFocus() {
          setPitch(Macro.normToHz(n))
        } else {
          send(Speed, Param.fromNormalised(Speed, n))
          refreshDerived()
        },
      ~onGestureStart=tuningStart,
      ~onGestureEnd=tuningEnd,
      ~snap=semitones,
      ~parse=text => Macro.parsePitch(text)->Option.map(Macro.hzToNorm),
      ~typeHint="A3, 440 Hz",
    ),
    ring: Knob.make(
      ~label="Ring",
      ~title="How long it rings after each sound. Pitch and Color keep it where you put it. The last part of the turn sustains itself.",
      ~defaultValue=Macro.ringToNorm(initRing),
      ~onChange=setRing,
      ~onGestureStart=tuningStart,
      ~onGestureEnd=tuningEnd,
      ~parse=text =>
        Macro.parseRing(text)->Option.map(ring =>
          Macro.ringToNorm(
            // "sustain" while it's already sustaining keeps it as it is
            switch (ring, targetRing.contents) {
            | (Sustains(_), Sustains(current)) => Sustains(current)
            | _ => ring
            },
          )
        ),
      ~typeHint="1.2 s, 300 ms, sustain",
    ),
    color: Knob.make(
      ~label="Color",
      ~title="Where along the resonant band: towards the chaotic corner on the left, towards the saddle-node apex on the right. The pitch stays put.",
      ~defaultValue=initColor,
      ~onChange=moveOnBand,
      ~onGestureStart=colorStart,
      ~onGestureEnd=colorEnd,
    ),
    drive: paramKnob(
      Drive,
      ~label="Drive",
      ~title="How hard the input pushes the chemistry",
      ~parse=Macro.parseDecibels,
      ~typeHint="dB",
    ),
    mix: paramKnob(Mix, ~label="Mix", ~title="Dry and wet", ~parse=Macro.parsePercent, ~typeHint="%"),
    output: paramKnob(
      OutputGain,
      ~label="Output",
      ~title="Output level",
      ~parse=Macro.parseDecibels,
      ~typeHint="dB",
    ),
  }
  knobsRef := Some(knobs)

  // The response plot's peak moves the same targets as the Pitch and Ring knobs, the same way:
  // sideways in semitones (free with Shift), up and down a Ring knob's turn per 200 px.
  let peakDrag: ref<option<peakDrag>> = ref(None)
  onPeakDragStart :=
    () => {
      tuningStart()
      peakDrag :=
        Some({
          startHz: currentFocus()->Option.mapOr(targetHz.contents, x => x.hz),
          startRing: knobs.ring.value,
          across: false,
          upDown: false,
        })
    }
  onPeakDrag :=
    (octaves, rise, fine) =>
      peakDrag.contents->Option.forEach(drag => {
        drag.across = drag.across || Math.abs(octaves) > 0.05
        drag.upDown = drag.upDown || Math.abs(rise) > 3.0
        if drag.across {
          let hz = drag.startHz *. Math.pow(2.0, ~exp=octaves)
          targetHz := Macro.clampHz(fine ? hz : Macro.nearestSemitone(hz))
        }
        if drag.upDown {
          targetRing := Macro.normToRing(drag.startRing +. rise /. Knob.turnTravel(~fine))
        }
        if drag.across || drag.upDown {
          realise()
        }
      })
  onPeakDragEnd :=
    () => {
      peakDrag := None
      tuningEnd()
    }
  onPlotWheel :=
    (up, fine) => {
      let by = Knob.wheelStep(~fine)
      tuningStart()
      setRing(knobs.ring.value +. (up ? by : -.by))
      tuningEnd()
    }
  // a double right-click on a knob that is one parameter opens the host's menu for it
  hostMenu->HostMenu.attach(knobs.pitch.element, Param.id(Speed))
  hostMenu->HostMenu.attach(knobs.ring.element, Param.id(Feedback))
  hostMenu->HostMenu.attach(knobs.drive.element, Param.id(Drive))
  hostMenu->HostMenu.attach(knobs.mix.element, Param.id(Mix))
  hostMenu->HostMenu.attach(knobs.output.element, Param.id(OutputGain))

  let knobGroup = (title, members: array<Knob.t>) => {
    let group = div(~className="knob-group")
    let heading = createElement("h2")
    setTextContent(heading, title)
    group->appendChild(heading)
    let row = div(~className="knobs")
    members->Array.forEach(k => row->appendChild(k.element))
    group->appendChild(row)
    group
  }
  let knobRow = div(~className="knob-groups")
  knobRow->appendChild(knobGroup("The resonance", [knobs.pitch, knobs.ring, knobs.color]))
  knobRow->appendChild(knobGroup("In and out", [knobs.drive, knobs.mix, knobs.output]))

  let playPage = div(~className="page play")
  let playTop = div(~className="play-top")
  let dishBox = div(~className="dish-box")
  dishBox->appendChild(dish.element)
  let dishCaption = div(~className="caption")
  setTextContent(
    dishCaption,
    "The chemistry at this Color, grown in a dish. It lights up along the ring where your sound is ringing.",
  )
  dishBox->appendChild(dishCaption)
  let hear = div(~className="hear")
  hear->appendChild(hearNote)
  hear->appendChild(hearRing)
  hear->appendChild(hearRegime)
  let responseLabel = div(~className="hear-label")
  setTextContent(responseLabel, "What it does to your sound")
  hear->appendChild(responseLabel)
  hear->appendChild(response.element)
  playTop->appendChild(dishBox)
  playTop->appendChild(hear)
  playPage->appendChild(playTop)
  playPage->appendChild(knobRow)

  //==============================================================================
  // Lab page

  let reseed = button(
    ~text="Reseed lattice",
    ~title="Put the ring back at rest for the current chemistry",
  )
  reseed->addEventListener("click", _ => Bridge.reseed(bridge))
  let (controls, labSliders) = Controls.make(
    bridge,
    ~hostMenu,
    ~onLocalChange=(param, value) => {
      applyValue(param, value)
      if affectsTargets(param) {
        adoptTargets()
      }
      refreshDerived()
    },
    ~extra=reseed,
  )
  sliders := labSliders

  let main = createElement("main")
  main->appendChild(phase.element)
  main->appendChild(labLattice.element)
  let labPage = div(~className="page lab")
  labPage->appendChild(main)
  labPage->appendChild(controls)

  root->appendChild(header)
  root->appendChild(playPage)
  root->appendChild(labPage)

  //==============================================================================
  // Pages

  let showPage = (page, ~remember) => {
    app.page = page
    playPage->toggleClass("on", page == Play)
    labPage->toggleClass("on", page == Lab)
    playButton->toggleClass("on", page == Play)
    labButton->toggleClass("on", page == Lab)
    // what was hidden may be stale
    labLattice.dirty = true
    dish.pending = true
    response.dirty = true
    phase.dirty = true
    invalidate(app)
    if remember && settings->Settings.available {
      settings->Settings.save("page", String(page == Lab ? "lab" : "play"))
    }
  }
  playButton->addEventListener("click", _ => showPage(Play, ~remember=true))
  labButton->addEventListener("click", _ => showPage(Lab, ~remember=true))
  showPage(Play, ~remember=false)
  // the page you were last on, once the CLAP plugin has answered with the settings
  let restoredPage = ref(false)
  let stopPageSetting = settings->Settings.listen(() =>
    if !restoredPage.contents {
      restoredPage := true
      switch settings.saved->Option.flatMap(Dict.get(_, "page")) {
      | Some(String("lab")) => showPage(Lab, ~remember=false)
      | _ => ()
      }
    }
  )

  //==============================================================================
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

  //==============================================================================
  // Host → GUI

  Bridge.onParameterChange(bridge, (param, value) => {
    // (the host echoes what this view sends; only a change from elsewhere resets the targets)
    let s = Param.spec(param)
    let fresh = Math.abs(value -. valueOf(param)) > (s.max -. s.min) *. 1e-6
    applyValue(param, value)
    // (what this view sent, it has already shown)
    if fresh {
      if affectsTargets(param) {
        adoptTargets()
      }
      refreshDerived()
    }
  })
  Bridge.onLatticeFrame(bridge, frame => {
    TuringDish.setFrame(dish, frame)
    LatticeView.pushFrame(labLattice, frame)
    app.level = frame.level
  })

  refreshDerived()
  app.cleanups = [
    () => resizeObserver->disconnect,
    restoreBrowserChrome,
    stopSizeControl,
    stopPresetMenu,
    stopPageSetting,
    () => settings->Settings.dispose,
    () => hostMenu->HostMenu.dispose,
    () => TuringDish.stop(dish),
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
