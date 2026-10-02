// Type-safe bindings to the Cmajor `PatchConnection` JS API, plus a typed
// parameter model and a glitch-free parameter bridge.

// ---------------------------------------------------------------------------
// Raw PatchConnection API

type patchConnection

type parameterChange = {endpointID: string, value: float}
type storedStateChange = {key: string, value: JSON.t}

// The parameters that differ from their defaults, and every stored-state value, in one reply.
type namedValue = {name: string, value: float}
type fullState = {parameters?: array<namedValue>, values?: dict<JSON.t>}

module Raw = {
  @send external sendEventOrValue: (patchConnection, string, float) => unit = "sendEventOrValue"
  @send
  external sendEventOrValueRamped: (patchConnection, string, float, int) => unit =
    "sendEventOrValue"
  // A void event endpoint takes no value.
  @send external sendVoidEvent: (patchConnection, string) => unit = "sendEventOrValue"
  @send
  external sendParameterGestureStart: (patchConnection, string) => unit =
    "sendParameterGestureStart"
  @send
  external sendParameterGestureEnd: (patchConnection, string) => unit = "sendParameterGestureEnd"
  @send external requestParameterValue: (patchConnection, string) => unit = "requestParameterValue"
  @send
  external addAllParameterListener: (patchConnection, parameterChange => unit) => unit =
    "addAllParameterListener"
  @send
  external removeAllParameterListener: (patchConnection, parameterChange => unit) => unit =
    "removeAllParameterListener"
  @send
  external addEndpointListener: (patchConnection, string, 'payload => unit) => unit =
    "addEndpointListener"
  @send
  external removeEndpointListener: (patchConnection, string, 'payload => unit) => unit =
    "removeEndpointListener"
  @send
  external addStoredStateValueListener: (patchConnection, storedStateChange => unit) => unit =
    "addStoredStateValueListener"
  @send
  external removeStoredStateValueListener: (patchConnection, storedStateChange => unit) => unit =
    "removeStoredStateValueListener"
  @send
  external requestStoredStateValue: (patchConnection, string) => unit = "requestStoredStateValue"
  @send
  external requestFullStoredState: (patchConnection, fullState => unit) => unit =
    "requestFullStoredState"
  let hasFullStoredState: patchConnection => bool = %raw(`
    (pc) => typeof pc.requestFullStoredState === "function"
  `)
}

// ---------------------------------------------------------------------------
// Parameters — mirrors the `input event` block in GrayScottResonator.cmajor.
// Every value that reaches the patch goes through `Param.clamp`, so the DSP
// never sees an out-of-range F or K even if a caller passes garbage.

module Param = {
  type t =
    | Feed
    | Kill
    | DiffusionU
    | DiffusionRatio
    | Speed
    | Drive
    | TapDistance
    | Feedback
    | Mix
    | OutputGain

  type spec = {
    id: string,
    label: string,
    min: float,
    max: float,
    init: float,
    format: float => string,
  }

  let fixed = (digits, suffix) => v => Float.toFixed(v, ~digits) ++ suffix
  let percent = v => Float.toFixed(v *. 100.0, ~digits=0) ++ "%"
  let decibels = v => (v > 0.0 ? "+" : "") ++ Float.toFixed(v, ~digits=1) ++ " dB"

  let spec = p =>
    switch p {
    | Feed => {id: "feed", label: "Feed F", min: 0.010, max: 0.090, init: 0.04462, format: fixed(4, "")}
    | Kill => {id: "kill", label: "Kill K", min: 0.045, max: 0.070, init: 0.0585, format: fixed(4, "")}
    | DiffusionU => {
        id: "diffusionU",
        label: "Diffusion",
        min: 0.05,
        max: 0.50,
        init: 0.40,
        format: fixed(2, ""),
      }
    | DiffusionRatio => {
        id: "diffusionRatio",
        label: "Dv / Du",
        min: 0.10,
        max: 1.00,
        init: 1.00,
        format: fixed(2, ""),
      }
    | Speed => {id: "speed", label: "Speed", min: 0.05, max: 4.0, init: 1.0, format: fixed(2, "×")}
    | Drive => {id: "drive", label: "Drive", min: 0.0, max: 24.0, init: 0.0, format: decibels}
    | TapDistance => {
        id: "tapDistance",
        label: "Pickup distance",
        min: 0.0,
        max: 1.0,
        init: 0.3,
        format: percent,
      }
    | Feedback => {
        id: "feedback",
        label: "Resonance",
        min: 0.0,
        max: 1.5,
        init: 0.93,
        format: fixed(2, ""),
      }
    | Mix => {id: "mix", label: "Mix", min: 0.0, max: 1.0, init: 1.0, format: percent}
    | OutputGain => {
        id: "outputGain",
        label: "Output",
        min: -36.0,
        max: 12.0,
        init: -6.0,
        format: decibels,
      }
    }

  let all = [Feed, Kill, DiffusionU, DiffusionRatio, Speed, Drive, TapDistance, Feedback, Mix, OutputGain]

  let id = p => spec(p).id
  let fromId = endpointId => all->Array.find(p => id(p) == endpointId)

  let clamp = (p, v) => {
    let s = spec(p)
    if Float.isNaN(v) {
      s.init
    } else {
      Math.min(s.max, Math.max(s.min, v))
    }
  }

  // Speed scales every frequency in the lattice, so it gets a log taper.
  let isLogarithmic = p => p == Speed

  let toNormalised = (p, v) => {
    let s = spec(p)
    let v = clamp(p, v)
    isLogarithmic(p)
      ? Math.log(v /. s.min) /. Math.log(s.max /. s.min)
      : (v -. s.min) /. (s.max -. s.min)
  }

  let fromNormalised = (p, n) => {
    let s = spec(p)
    let n = Math.min(1.0, Math.max(0.0, n))
    clamp(p, isLogarithmic(p) ? s.min *. Math.pow(s.max /. s.min, ~exp=n) : s.min +. n *. (s.max -. s.min))
  }
}

// ---------------------------------------------------------------------------
// Lattice snapshots — mirrors `struct LatticeFrame` in the processor.

type latticeFrame = {
  v: array<float>,
  injectL: float,
  injectR: float,
  tapL: float,
  tapR: float,
  level: float,
}

let latticeEndpoint = "lattice"
let reseedEndpoint = "reseed"

// ---------------------------------------------------------------------------
// Bridge
//
// Glitch-free parameter transport:
//  * Values are clamped to the declared range before they leave the GUI.
//  * Writes are coalesced to at most one message per endpoint per animation
//    frame, so dragging the F×K puck at 1 kHz pointer rates doesn't flood the
//    host's event FIFO. The processor then glides every value over ~25 ms.
//  * Drags are bracketed with gesture start/end so hosts record automation
//    as one undoable move.
//  * Echoes from the host for a parameter that's mid-gesture are ignored, so
//    the control under the user's pointer never jitters backwards.

module Bridge = {
  type t = {
    connection: patchConnection,
    pending: Map.t<string, float>,
    activeGestures: Set.t<string>,
    mutable scheduledFrame: option<int>,
    mutable paramListener: option<parameterChange => unit>,
    mutable latticeListener: option<latticeFrame => unit>,
  }

  let make = connection => {
    connection,
    pending: Map.make(),
    activeGestures: Set.make(),
    scheduledFrame: None,
    paramListener: None,
    latticeListener: None,
  }

  let flush = bridge => {
    bridge.scheduledFrame = None
    bridge.pending->Map.forEachWithKey((value, endpointId) =>
      Raw.sendEventOrValue(bridge.connection, endpointId, value)
    )
    bridge.pending->Map.clear
  }

  let set = (bridge, param, value) => {
    bridge.pending->Map.set(Param.id(param), Param.clamp(param, value))

    if bridge.scheduledFrame->Option.isNone {
      bridge.scheduledFrame = Some(Web.requestAnimationFrame(_ => flush(bridge)))
    }
  }

  let beginGesture = (bridge, param) => {
    let endpointId = Param.id(param)
    if !(bridge.activeGestures->Set.has(endpointId)) {
      bridge.activeGestures->Set.add(endpointId)
      Raw.sendParameterGestureStart(bridge.connection, endpointId)
    }
  }

  let endGesture = (bridge, param) => {
    let endpointId = Param.id(param)
    if bridge.activeGestures->Set.has(endpointId) {
      // Make sure the final value lands before the gesture closes.
      switch bridge.scheduledFrame {
      | Some(frame) => Web.cancelAnimationFrame(frame)
      | None => ()
      }
      flush(bridge)
      bridge.activeGestures->Set.delete(endpointId)->ignore
      Raw.sendParameterGestureEnd(bridge.connection, endpointId)
    }
  }

  let reseed = bridge => Raw.sendVoidEvent(bridge.connection, reseedEndpoint)

  /// Subscribes to host-side parameter changes (automation, presets, other
  /// views) and fetches the current value of every parameter. Where the host
  /// supports it (as nano-clap does) that's one requestFullStoredState round
  /// trip, which lists the parameters that differ from their defaults, instead
  /// of a request per parameter through the plugin's web view.
  let onParameterChange = (bridge, callback: (Param.t, float) => unit) => {
    let apply = (endpointId, value) =>
      switch Param.fromId(endpointId) {
      | Some(param) if !(bridge.activeGestures->Set.has(endpointId)) =>
        callback(param, Param.clamp(param, value))
      | _ => ()
      }
    let listener = (change: parameterChange) => apply(change.endpointID, change.value)

    bridge.paramListener = Some(listener)
    Raw.addAllParameterListener(bridge.connection, listener)

    if Raw.hasFullStoredState(bridge.connection) {
      Raw.requestFullStoredState(bridge.connection, state =>
        if bridge.paramListener->Option.isSome {
          state.parameters
          ->Option.getOr([])
          ->Array.forEach(({name, value}) => apply(name, value))
        }
      )
    } else {
      Param.all->Array.forEach(p => Raw.requestParameterValue(bridge.connection, Param.id(p)))
    }
  }

  let onLatticeFrame = (bridge, callback: latticeFrame => unit) => {
    bridge.latticeListener = Some(callback)
    Raw.addEndpointListener(bridge.connection, latticeEndpoint, callback)
  }

  let dispose = bridge => {
    switch bridge.scheduledFrame {
    | Some(frame) => Web.cancelAnimationFrame(frame)
    | None => ()
    }
    bridge.scheduledFrame = None
    bridge.activeGestures->Set.forEach(endpointId =>
      Raw.sendParameterGestureEnd(bridge.connection, endpointId)
    )
    bridge.activeGestures->Set.clear
    switch bridge.paramListener {
    | Some(listener) => Raw.removeAllParameterListener(bridge.connection, listener)
    | None => ()
    }
    switch bridge.latticeListener {
    | Some(listener) => Raw.removeEndpointListener(bridge.connection, latticeEndpoint, listener)
    | None => ()
    }
    bridge.paramListener = None
    bridge.latticeListener = None
  }
}
