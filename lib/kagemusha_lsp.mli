val extract_lsp_message_body : string -> string

type message = Raw of Cstruct.t | Decoded of Jsonrpc.Packet.t

val to_packet :
     [`Notification of Jsonrpc.Notification.t | `Request of Jsonrpc.Request.t]
  -> Jsonrpc.Packet.t

val write_packet :
  [> Eio.Flow.sink_ty] Eio.Resource.t -> Jsonrpc.Packet.t -> unit

module Reader : sig
  val to_stream :
       Jsonrpc.Packet.t Eio.Stream.t
    -> [> Eio.Flow.source_ty] Eio.Resource.t
    -> unit
end
