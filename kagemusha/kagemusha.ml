let is_shutdown_request (req : Jsonrpc.Request.t) =
  match req.method_ with "shutdown" -> true | _ -> false

let is_exit_notification (notification : Jsonrpc.Notification.t) =
  match notification.method_ with "exit" -> true | _ -> false

let is_unredirected_batch_item = function
  | `Request req -> is_shutdown_request req
  | `Notification notification -> is_exit_notification notification

let mangle_batch_call list =
  let open Kagemusha_lsp in
  let redirected_batch, list1 =
    List.partition (fun x -> not (is_unredirected_batch_item x)) list
  in
  ( List.map to_packet redirected_batch |> List.to_seq
  , to_packet (List.hd list1) )

exception Lsp_exit

let run_proxy server_sockaddr =
  let open Eio in
  Eio_main.run
  @@ fun env ->
  Switch.run (fun sw ->
      let open Kagemusha_lsp in
      let response_stream = Stream.create 5 in
      let stdout = Stdenv.stdout env in
      let net = Stdenv.net env in
      let server_socket = Net.connect ~sw net server_sockaddr in
      let handle_client_packets packet =
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
        | _ -> write_packet server_socket packet
      in
      let client_packet_stream = Eio.Stream.create 2 in
      let rec process_client_packets () =
        Stream.take client_packet_stream |> handle_client_packets ;
        Fiber.yield () ;
        process_client_packets ()
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
              Kagemusha_lsp.Reader.to_stream client_packet_stream (Stdenv.stdin env) )
          ; process_client_packets
          ; redirect_server_responses
          ; process_responses ]
      with Lsp_exit -> () )
