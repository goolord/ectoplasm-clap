// Entry point loaded by the Cmajor host (see "view" in plugin.cmajorpatch).
//
// The host calls the module's default export with a PatchConnection and
// appends the returned element. The app lives in that custom element's shadow
// root; its listeners are torn down when the host removes the view, and it is
// rebuilt if the view is attached again.

// Called from the custom element's lifecycle callbacks with the host element.
type hooks = {
  mount: (CmajorBindings.patchConnection, Web.element) => unit,
  unmount: Web.element => unit,
}

let defineElement: (string, hooks) => unit = %raw(`
  (name, hooks) => {
    if (customElements.get(name)) return;
    customElements.define(name, class extends HTMLElement {
      constructor (connection) { super(); this.connection = connection; }
      connectedCallback() { hooks.mount(this.connection, this); }
      disconnectedCallback() { hooks.unmount(this); }
    });
  }
`)

let construct: (string, CmajorBindings.patchConnection) => Web.element = %raw(`
  (name, connection) => new (customElements.get(name))(connection)
`)

let elementName = "gray-scott-resonator-view"

// One app per host element.
let apps: Map.t<Web.element, GrayScottApp.t> = Map.make()

let mountInto = (connection, host) => {
  switch apps->Map.get(host) {
  | Some(old) => GrayScottApp.stop(old)
  | None => ()
  }
  apps->Map.set(host, GrayScottApp.make(connection, host))
}

let unmountFrom = host =>
  switch apps->Map.get(host) {
  | Some(app) =>
    GrayScottApp.stop(app)
    apps->Map.delete(host)->ignore
  | None => ()
  }

let createPatchView = (connection: CmajorBindings.patchConnection) => {
  defineElement(elementName, {mount: mountInto, unmount: unmountFrom})
  construct(elementName, connection)
}

let default = createPatchView
