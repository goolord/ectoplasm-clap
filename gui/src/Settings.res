// Adapted from nano-clap (ui/core/Settings.res): the size of the interface, a user setting
// rather than part of a preset.
//
// The CLAP plugin keeps it in a settings file every instance shares, and answers stored-state
// requests whose key starts with "bridge:settings?" with a "bridge:settings" value
// {settings, zoom}, zoom being this window's size relative to the design size (see
// tools/clap-patch.mjs). Elsewhere (cmaj play, the GUI harness) nothing answers: the host owns
// the window size there, and the size control stays hidden.

type t = {
  channel: HostChannel.t,
  // the saved settings, once the plugin has answered
  mutable saved: option<dict<JSON.t>>,
  mutable zoom: float,
  mutable listeners: array<unit => unit>,
}

let zoomSteps = [0.75, 1., 1.25, 1.5, 1.75, 2.]

let request = (t, what) => t.channel->HostChannel.request(what)

let onReply = (t, reply: dict<JSON.t>) => {
  t.saved = switch reply->Dict.get("settings") {
  | Some(Object(saved)) => Some(saved)
  | _ => Some(Dict.make())
  }
  switch reply->Dict.get("zoom") {
  | Some(Number(zoom)) if Float.isFinite(zoom) => t.zoom = zoom
  | _ => ()
  }
  t.listeners->Array.forEach(fn => fn())
}

let make = connection => {
  let t = {channel: HostChannel.make(connection, "settings"), saved: None, zoom: 1., listeners: []}
  t.channel->HostChannel.listen(reply => onReply(t, reply))
  request(t, "get")
  t
}

let dispose = t => t.channel->HostChannel.dispose

// whether the plugin keeps the settings and sizes the window
let available = t => t.saved != None

// Calls fn whenever the plugin answers; returns a function that stops it.
let listen = (t, fn) => {
  let wrapped = () => fn()
  t.listeners->Array.push(wrapped)
  () => t.listeners = t.listeners->Array.filter(f => f !== wrapped)
}

let save = (t, key, value) => {
  let saved = t.saved->Option.mapOr(Dict.make(), Dict.copy)
  saved->Dict.set(key, value)
  t.saved = Some(saved)
  request(t, "save=" ++ JSON.stringify(Object(saved)))
}

// Asks the host to resize this window, and opens new windows at that size too.
let setZoom = (t, zoom) => {
  request(t, "zoom=" ++ Float.toString(zoom))
  save(t, "zoom", Number(zoom))
}
