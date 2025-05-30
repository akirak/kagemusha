let lsp_message_split = Str.regexp "\r\n\r\n"

let extract_lsp_message_body message_string =
  let index = Str.search_forward lsp_message_split message_string 0 in
  Str.string_after message_string (index + 4)

type message = Raw of Cstruct.t | Decoded of Jsonrpc.Packet.t

let to_packet = function
  | `Request req -> Jsonrpc.Packet.Request req
  | `Notification notification -> Jsonrpc.Packet.Notification notification

let write_packet flow packet =
  let json = Jsonrpc.Packet.yojson_of_t packet in
  let json_str = Yojson.Safe.to_string json in
  let content_length = String.length json_str in
  (* This function is only used for building the response to a shutdown
     request. With a CRLF appended to the entire message, Emacs lsp/eglot
     booster will fail, so we don't append it. *)
  let lsp_message =
    Printf.sprintf "Content-Length: %d\r\n\r\n%s" content_length json_str
  in
  Eio.Flow.copy_string lsp_message flow

let read_lsp_message flow =
  let buffer = Cstruct.create 4096 in
  match Eio.Flow.single_read flow buffer with
  | bytes_read when bytes_read > 0 ->
      Cstruct.sub buffer 0 bytes_read
      |> Cstruct.to_string |> extract_lsp_message_body
      |> Yojson.Safe.from_string |> Jsonrpc.Packet.t_of_yojson |> Option.some
  | _ -> Option.none
