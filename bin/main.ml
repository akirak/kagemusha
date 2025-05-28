open Cmdliner

let lsp_message_split = Str.regexp "\r\n\r\n"

let extract_lsp_message_body message_string =
  let index = Str.search_forward lsp_message_split message_string 0 in
  Str.string_after message_string (index + 4)

let handle_packets ~input ~f =
  let rec loop () =
    let buffer = Cstruct.create 4096 in
    match Eio.Flow.single_read input buffer with
    | bytes_read when bytes_read > 0 ->
        let sub = Cstruct.sub buffer 0 bytes_read in
        let string = Cstruct.to_string sub in
        extract_lsp_message_body string
        |> Yojson.Safe.from_string |> Jsonrpc.Packet.t_of_yojson
        |> f ~buffer:sub ;
        Eio.Fiber.yield () ;
        loop ()
    | _ -> Eio.Fiber.yield () ; loop ()
  in
  try loop () with End_of_file -> ()

type message = Raw of Cstruct.t | Decoded of Jsonrpc.Packet.t

let is_shutdown_request (req : Jsonrpc.Request.t) =
  match req.method_ with "shutdown" -> true | _ -> false

let is_exit_notification (notification : Jsonrpc.Notification.t) =
  match notification.method_ with "exit" -> true | _ -> false

let is_unredirected_batch_item = function
  | `Request req -> is_shutdown_request req
  | `Notification notification -> is_exit_notification notification

let to_packet = function
  | `Request req -> Jsonrpc.Packet.Request req
  | `Notification notification -> Jsonrpc.Packet.Notification notification

let mangle_batch_call list =
  let redirected_batch, list1 =
    List.partition (fun x -> not (is_unredirected_batch_item x)) list
  in
  ( List.map to_packet redirected_batch |> List.to_seq
  , to_packet (List.hd list1) )

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

exception Lsp_exit

let run_proxy make_server_socket =
  let open Eio in
  Eio_main.run
  @@ fun env ->
  Switch.run (fun sw ->
      let response_stream = Stream.create 5 in
      let stdout = Stdenv.stdout env in
      let server_socket = make_server_socket ~sw ~env () in
      let handle_client_packets ~buffer packet =
        match packet with
        | Jsonrpc.Packet.Request req when is_shutdown_request req ->
            Jsonrpc.Response.ok req.id `Null
            |> (fun response -> Jsonrpc.Packet.Response response)
            |> fun packet -> Stream.add response_stream (Decoded packet)
        | Jsonrpc.Packet.Notification notification
          when is_exit_notification notification ->
            raise Lsp_exit
        | Jsonrpc.Packet.Batch_call calls ->
            let redirected, _ = mangle_batch_call calls in
            Seq.iter (write_packet server_socket) redirected
        | _ ->
            Flow.write server_socket [buffer]
      in
      let rec process_responses () =
        ( match Stream.take response_stream with
        | Raw buffer -> Eio.Flow.write stdout [buffer]
        | Decoded packet -> write_packet stdout packet ) ;
        Fiber.yield () ; process_responses ()
      in
      let rec redirect_server_responses () =
        let buffer = Cstruct.create 4096 in
        match Eio.Flow.single_read server_socket buffer with
        | bytes_read when bytes_read > 0 ->
            let sub = Cstruct.sub buffer 0 bytes_read in
            Stream.add response_stream (Raw sub) ;
            Fiber.yield () ;
            redirect_server_responses ()
        | _ ->
            Fiber.yield () ;
            redirect_server_responses ()
      in
      try
        Fiber.all
          [ (fun () ->
              handle_packets ~input:(Stdenv.stdin env)
                ~f:handle_client_packets )
          ; redirect_server_responses
          ; process_responses ]
      with Lsp_exit -> () )

let open_socket socket_path ~sw ~env () =
  let open Eio in
  let net = Stdenv.net env in
  Net.connect ~sw net (`Unix socket_path)

let socket_path =
  let doc = "UNIX socket path of the master language server" in
  let arg =
    Arg.(
      required & pos 0 (some non_dir_file) None & info [] ~docv:"FILE" ~doc )
  in
  Term.(const open_socket $ arg)

let cmd =
  let doc = "Connect to a UNIX socket" in
  let info = Cmd.info "kagemusha" ~doc in
  Cmd.v info Term.(const run_proxy $ socket_path)

let () =
  Printexc.record_backtrace true ;
  exit (Cmd.eval cmd)
