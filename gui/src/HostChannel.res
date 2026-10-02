// From nano-clap (ui/core/HostChannel.res). A request/reply channel to the CLAP plugin through
// the patch's stored state (see tools/clap-patch.mjs): a request asks for the stored-state value
// "bridge:<name>?<what>", and the plugin answers with a "bridge:<name>" value, an object. Nothing
// is stored: the plugin answers the request itself. Elsewhere (cmaj play, the GUI harness)
// nothing answers, so everything that uses a channel must work without a reply.

module Raw = CmajorBindings.Raw

type t = {
  connection: CmajorBindings.patchConnection,
  replyKey: string,
  mutable listener: option<CmajorBindings.storedStateChange => unit>,
}

let make = (connection, name) => {connection, replyKey: "bridge:" ++ name, listener: None}

let request = (t, what) => t.connection->Raw.requestStoredStateValue(t.replyKey ++ "?" ++ what)

// Calls onReply with every answer, until dispose.
let listen = (t, onReply: dict<JSON.t> => unit) => {
  let listener = ({key, value}: CmajorBindings.storedStateChange) =>
    switch value {
    | Object(reply) if key == t.replyKey => onReply(reply)
    | _ => ()
    }
  t.listener = Some(listener)
  t.connection->Raw.addStoredStateValueListener(listener)
}

let dispose = t =>
  t.listener->Option.forEach(listener => t.connection->Raw.removeStoredStateValueListener(listener))
