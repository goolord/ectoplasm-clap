// From nano-clap (ui/core/BrowserChrome.res). The view runs in a web view inside the plugin
// window, where the browser's own context menu (back, refresh, print...) and shortcuts (reload,
// print, find, page zoom...) only get in the way, so they are switched off for the whole view.
// Text fields keep their cut/copy/paste menu.

open Web

let inTextField = ev =>
  switch ev->originalTarget->tagName {
  | Some("TEXTAREA") => true
  | Some("INPUT") => ev->originalTarget->inputType != Some("range")
  | _ => false
  }

let isBrowserShortcut = ev =>
  switch ev->key->String.toLowerCase {
  | "f3" | "f5" | "f7" | "f12" => true
  | "browserback" | "browserforward" | "browserrefresh" | "browsersearch" | "browserhome" => true
  | "arrowleft" | "arrowright" | "home" if ev->altKey => true
  | "r" | "p" | "f" | "g" | "s" | "o" | "u" | "j" | "h" | "n" | "t" | "w" | "+" | "=" | "-" | "0"
    if ev->commandKey => true
  | _ => false
  }

// Returns a function that switches them back on.
let install = () => {
  let stopMenu = listenDocument(
    "contextmenu",
    ev =>
      if !inTextField(ev) {
        ev->preventDefault
      },
    ~capture=false,
    ~passive=false,
  )
  let stopKeys = listenDocument(
    "keydown",
    ev =>
      if isBrowserShortcut(ev) {
        ev->preventDefault
      },
    ~capture=false,
    ~passive=false,
  )
  // ctrl-wheel (and pinch) would zoom the page
  let stopWheel = listenDocument(
    "wheel",
    ev =>
      if ev->ctrlKey {
        ev->preventDefault
      },
    ~capture=false,
    ~passive=false,
  )
  () => {
    stopMenu()
    stopKeys()
    stopWheel()
  }
}
