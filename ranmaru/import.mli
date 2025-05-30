module Client_registry : sig
  module Id : sig
    type t
  end

  type t

  val make : unit -> t

  type response_packet =
    [ `Response of Jsonrpc.Response.t
    | `Batch_response of Jsonrpc.Response.t list ]

  val register : t -> Id.t * response_packet Eio.Stream.t

  val delete : t -> Id.t -> unit

  val send : t -> Id.t -> response_packet -> unit
end

module Id_translator : sig
  type t

  val make : unit -> t

  val translate : t -> Jsonrpc.Id.t -> Jsonrpc.Id.t

  val untranslate : t -> Jsonrpc.Id.t -> Jsonrpc.Id.t
end

module Client_map : sig
  type t

  val make : unit -> t

  val add : t -> Client_registry.Id.t -> Jsonrpc.Id.t -> unit

  val take : t -> Jsonrpc.Id.t -> Client_registry.Id.t

  val take_opt : t -> Jsonrpc.Id.t -> Client_registry.Id.t option
end

module Initializer : sig
  type t

  val make : unit -> t

  val await :
       server_socket:[> Eio.Flow.sink_ty] Eio.Resource.t
    -> id:Jsonrpc.Id.t
    -> params:Lsp.Types.InitializeParams.t
    -> t
    -> (Jsonrpc.Json.t, Jsonrpc.Response.Error.t) Result.t

  val set : t -> (Jsonrpc.Json.t, Jsonrpc.Response.Error.t) Result.t -> unit
end
