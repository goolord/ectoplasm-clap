// Minimal, dependency-free DOM + Canvas2D bindings — only what the GUI uses.

type element
type event
type ctx2d
type imageData
type bytes // Uint8ClampedArray
type rect = {left: float, top: float, width: float, height: float}

@val external document: 'a = "document"
@val external documentElement: element = "document.documentElement"
@val external devicePixelRatio: float = "window.devicePixelRatio"
@val external requestAnimationFrame: (float => unit) => int = "requestAnimationFrame"
@val external cancelAnimationFrame: int => unit = "cancelAnimationFrame"

@val @scope("document") external createElement: string => element = "createElement"

@send external appendChild: (element, element) => unit = "appendChild"
@send external remove: element => unit = "remove"
@send external replaceChildren: element => unit = "replaceChildren"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@set external setClassName: (element, string) => unit = "className"
let toggleClass: (element, string, bool) => unit = %raw(`(el, name, on) => { el.classList.toggle(name, on) }`)
@set external setTextContent: (element, string) => unit = "textContent"
@set external setInnerHTML: (element, string) => unit = "innerHTML"
@send external getBoundingClientRect: element => rect = "getBoundingClientRect"
@get external clientWidth: element => float = "clientWidth"
@get external clientHeight: element => float = "clientHeight"
@send external addEventListener: (element, string, event => unit) => unit = "addEventListener"
@send external setPointerCapture: (element, int) => unit = "setPointerCapture"
@send external releasePointerCapture: (element, int) => unit = "releasePointerCapture"
@send external focus: element => unit = "focus"
@send external selectText: element => unit = "select"
@get external offsetWidth: element => float = "offsetWidth"
@send external contains: (element, element) => bool = "contains"

/// The view's shadow root: created once, emptied when the view is mounted again.
let shadowRootOf: element => element = %raw(`
  (host) => {
    const root = host.shadowRoot ?? host.attachShadow({ mode: "open" });
    root.replaceChildren();
    return root;
  }
`)

@get external clientX: event => float = "clientX"
@get external clientY: event => float = "clientY"
@get external pointerId: event => int = "pointerId"
@get external deltaY: event => float = "deltaY"
@get external button: event => int = "button"
@get external key: event => string = "key"
@get external shiftKey: event => bool = "shiftKey"
@get external ctrlKey: event => bool = "ctrlKey"
@get external metaKey: event => bool = "metaKey"
@get external altKey: event => bool = "altKey"
@send external preventDefault: event => unit = "preventDefault"
@send external stopPropagation: event => unit = "stopPropagation"
@send external stopImmediatePropagation: event => unit = "stopImmediatePropagation"

let commandKey = ev => ctrlKey(ev) || metaKey(ev)

/// Where an event really started, inside the shadow root (the document only sees the host).
let originalTarget: event => element = %raw(`(ev) => (ev.composedPath && ev.composedPath()[0]) || ev.target`)
@get @return(nullable) external tagName: element => option<string> = "tagName"
@get @return(nullable) external inputType: element => option<string> = "type"

/// Listens on the document; returns the function that stops listening.
let listenDocument: (string, event => unit, ~capture: bool, ~passive: bool) => unit => unit = %raw(`
  (type, listener, capture, passive) => {
    const options = { capture, passive };
    document.addEventListener(type, listener, options);
    return () => document.removeEventListener(type, listener, options);
  }
`)

/// Listens on an element in the capture phase (before its own and its children's listeners).
let listenCapture: (element, string, event => unit) => unit = %raw(`
  (el, type, listener) => el.addEventListener(type, listener, true)
`)

@val external setTimeout: (unit => unit, int) => int = "setTimeout"
@val external clearTimeout: int => unit = "clearTimeout"

// Resizing
type resizeObserver
@new external makeResizeObserver: (unit => unit) => resizeObserver = "ResizeObserver"
@send external observe: (resizeObserver, element) => unit = "observe"
@send external disconnect: resizeObserver => unit = "disconnect"
@val @scope("CSS") external cssSupports: (string, string) => bool = "supports"

// <input type=range>
@get external inputValue: element => string = "value"
@set external setInputValue: (element, string) => unit = "value"

// Style
let setStyle: (element, string, string) => unit = %raw(`(el, k, v) => { el.style.setProperty(k, v) }`)

// Canvas element
@set external setCanvasWidth: (element, int) => unit = "width"
@set external setCanvasHeight: (element, int) => unit = "height"
@send external getContext2d: (element, @as("2d") _) => ctx2d = "getContext"

module Ctx = {
  @set external fillStyle: (ctx2d, string) => unit = "fillStyle"
  @set external strokeStyle: (ctx2d, string) => unit = "strokeStyle"
  @set external lineWidth: (ctx2d, float) => unit = "lineWidth"
  @set external font: (ctx2d, string) => unit = "font"
  @set external textAlign: (ctx2d, string) => unit = "textAlign"
  @set external textBaseline: (ctx2d, string) => unit = "textBaseline"
  @set external globalAlpha: (ctx2d, float) => unit = "globalAlpha"
  @set external imageSmoothingEnabled: (ctx2d, bool) => unit = "imageSmoothingEnabled"
  @send external setLineDash: (ctx2d, array<float>) => unit = "setLineDash"
  @send external setTransform: (ctx2d, float, float, float, float, float, float) => unit =
    "setTransform"
  @send external fillRect: (ctx2d, float, float, float, float) => unit = "fillRect"
  @send external clearRect: (ctx2d, float, float, float, float) => unit = "clearRect"
  @send external beginPath: ctx2d => unit = "beginPath"
  @send external closePath: ctx2d => unit = "closePath"
  @send external moveTo: (ctx2d, float, float) => unit = "moveTo"
  @send external lineTo: (ctx2d, float, float) => unit = "lineTo"
  @send external arc: (ctx2d, float, float, float, float, float) => unit = "arc"
  @send external stroke: ctx2d => unit = "stroke"
  @send external fill: ctx2d => unit = "fill"
  @send external fillText: (ctx2d, string, float, float) => unit = "fillText"
  @send external strokeText: (ctx2d, string, float, float) => unit = "strokeText"
  @set external lineJoin: (ctx2d, string) => unit = "lineJoin"
  @send external translate: (ctx2d, float, float) => unit = "translate"
  @send external rotate: (ctx2d, float) => unit = "rotate"
  @send external save: ctx2d => unit = "save"
  @send external restore: ctx2d => unit = "restore"
  @send external createImageData: (ctx2d, int, int) => imageData = "createImageData"
  @send external putImageData: (ctx2d, imageData, int, int) => unit = "putImageData"
  @send external drawImage: (ctx2d, element, float, float, float, float) => unit = "drawImage"
  @send
  external drawImageRegion: (
    ctx2d,
    element,
    float,
    float,
    float,
    float,
    float,
    float,
    float,
    float,
  ) => unit = "drawImage"
}

@get external imageBytes: imageData => bytes = "data"
@set_index external setByte: (bytes, int, int) => unit = ""

/// Canvases keep a backing store at twice their design size, whatever the screen's pixel ratio
/// or the window's zoom (as nano-clap does): sharp at 100–200 % without resizing the store.
let backingScale = 2.0

/// Creates a canvas and a context scaled so drawing uses design pixels.
let makeCanvas = (~width: int, ~height: int, ~className: string) => {
  let canvas = createElement("canvas")
  setCanvasWidth(canvas, Float.toInt(Int.toFloat(width) *. backingScale))
  setCanvasHeight(canvas, Float.toInt(Int.toFloat(height) *. backingScale))
  setStyle(canvas, "width", Int.toString(width) ++ "px")
  setStyle(canvas, "height", Int.toString(height) ++ "px")
  setClassName(canvas, className)
  let ctx = getContext2d(canvas)
  Ctx.setTransform(ctx, backingScale, 0.0, 0.0, backingScale, 0.0, 0.0)
  (canvas, ctx)
}

let div = (~className: string) => {
  let el = createElement("div")
  setClassName(el, className)
  el
}

/// Pointer position on an element in its design pixels (width × height), whatever zoom or
/// transform the stage is shown at.
let localPoint = (el: element, ev: event, ~width: float, ~height: float) => {
  let r = getBoundingClientRect(el)
  let sx = r.width > 0.0 ? width /. r.width : 1.0
  let sy = r.height > 0.0 ? height /. r.height : 1.0
  ((clientX(ev) -. r.left) *. sx, (clientY(ev) -. r.top) *. sy)
}
