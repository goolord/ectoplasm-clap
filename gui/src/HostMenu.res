// Adapted from nano-clap (ui/core/HostMenu.res). The host's menu for a parameter, which a double
// right-click on a control opens. In FL Studio it has Create automation clip, Link to
// controller, Edit events and so on.
//
// The CLAP plugin answers stored-state requests whose key starts with "bridge:host?" (see
// tools/clap-patch.mjs): ?get with a "bridge:host" value {menu}, whether the host can show its
// menu (CLAP's context-menu extension); ?menu=<json> {id, x, y, scale} shows it for the parameter
// with that endpoint ID, at a point in the view (CSS pixels, and the device pixel ratio);
// ?dismiss closes it. Elsewhere nothing answers, and a double right-click does nothing.
//
// On Windows the host's menu never hears a click or a key in the view, whose window belongs to
// the web view's own process, so it would stay open until a click somewhere else in the host.
// The next press or Escape in the view after the menu opens asks the plugin to close it.

open Web

type t = {
  channel: HostChannel.t,
  // whether the host can show its menu
  mutable available: bool,
  // stops listening for the press or key that closes the menu, while it may be open
  mutable stopDismiss: option<unit => unit>,
}

// Windows' default double-click time
let doubleClickMs = 500.

let make = connection => {
  let t = {channel: HostChannel.make(connection, "host"), available: false, stopDismiss: None}
  t.channel->HostChannel.listen(reply =>
    t.available = switch reply->Dict.get("menu") {
    | Some(Boolean(menu)) => menu
    | _ => false
    }
  )
  t.channel->HostChannel.request("get")
  t
}

let stopDismissing = t => {
  t.stopDismiss->Option.forEach(stop => stop())
  t.stopDismiss = None
}

let dispose = t => {
  t->stopDismissing
  t.channel->HostChannel.dispose
}

// Closes the menu on the next press or Escape in the view. The menu may have closed already (an
// item was picked), so the press still does what it does.
let dismissOnNextInput = t => {
  t->stopDismissing
  let dismiss = () => {
    t->stopDismissing
    t.channel->HostChannel.request("dismiss")
  }
  let stopPress = listenDocument("pointerdown", _ => dismiss(), ~capture=true, ~passive=true)
  let stopKey = listenDocument(
    "keydown",
    ev =>
      if ev->key == "Escape" {
        dismiss()
      },
    ~capture=false,
    ~passive=true,
  )
  t.stopDismiss = Some(
    () => {
      stopPress()
      stopKey()
    },
  )
}

// Shows the menu for the parameter id where ev happened.
let show = (t, id, ev) => {
  t->dismissOnNextInput
  t.channel->HostChannel.request(
    "menu=" ++
    JSON.stringify(
      Object(
        Dict.fromArray([
          ("id", JSON.String(id)),
          ("x", Number(ev->clientX)),
          ("y", Number(ev->clientY)),
          ("scale", Number(devicePixelRatio)),
        ]),
      ),
    ),
  )
}

// Opens the menu on a double right-click on e, a control for the parameter id. The menu opens
// with the context-menu event, which comes with the release on Windows, as menus do there.
let attach = (t, e, id) => {
  // the time of the last right press
  let last = ref(None)
  let armed = ref(false)
  e->listenCapture("pointerdown", ev => {
    armed := false
    if ev->button == 2 && t.available {
      let now = Date.now()
      switch last.contents {
      | Some(at) if now -. at <= doubleClickMs =>
        last := None
        armed := true
        ev->preventDefault
        ev->stopImmediatePropagation
      | _ => last := Some(now)
      }
    } else {
      last := None
    }
  })
  e->addEventListener("contextmenu", ev => {
    ev->preventDefault
    if armed.contents {
      armed := false
      show(t, id, ev)
    }
  })
}
