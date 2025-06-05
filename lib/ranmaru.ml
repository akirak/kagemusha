open Import

let max_connections = 5

(* Shutdown/exit handling functions *)
let is_shutdown_request (req : Jsonrpc.Request.t) =
  match req.method_ with "shutdown" -> true | _ -> false

let is_exit_notification (notification : Jsonrpc.Notification.t) =
  match notification.method_ with "exit" -> true | _ -> false

let is_unredirected_batch_item = function
  | `Request req -> is_shutdown_request req
  | `Notification notification -> is_exit_notification notification

type channel_message =
  | Connect
  | Packet of (Jsonrpc.Packet.t * Client_registry.Id.t)

let handle_client_incoming_messages ~incoming_channel ~client_socket
    ~client_id =
  let open Eio in
  Stream.add incoming_channel Connect ;
  let packet_stream = Stream.create 2 in
  let rec loop () =
    ( Stream.take packet_stream
    |> fun packet -> Stream.add incoming_channel (Packet (packet, client_id))
    ) ;
    Eio.Fiber.yield () ; loop ()
  in
  Fiber.both loop (fun () ->
      Lsp_utils.Reader.to_stream packet_stream client_socket )

let handle_client_responses ~stream ~client_socket =
  let rec loop () =
    let packet =
      match Eio.Stream.take stream with
      | `Response response -> Jsonrpc.Packet.Response response
      | `Batch_response batch -> Jsonrpc.Packet.Batch_response batch
    in
    Lsp_utils.write_packet client_socket packet ;
    Eio.Fiber.yield () ;
    loop ()
  in
  loop ()

type result =
  | Immediate of Jsonrpc.Response.t
  | Wait of Jsonrpc.Id.t list
  | Done

let translate_request ~id_translator request =
  let open Jsonrpc.Request in
  let new_id = Id_translator.translate id_translator request.id in
  {request with id= new_id}

let handle_client_packet ~server_socket ~id_translator ~initialized ~init
    packet =
  let open Jsonrpc in
  match packet with
  | Packet.Request req -> (
    match req.method_ with
    | "initialize" ->
        let orig_id = req.id in
        let id = Id_translator.translate id_translator orig_id in
        let params =
          Option.get req.params |> Jsonrpc.Structured.yojson_of_t
          |> Lsp.Types.InitializeParams.t_of_yojson
        in
        let result = Initializer.await ~server_socket ~id ~params init in
        let response =
          match result with
          | Ok params -> Response.ok orig_id params
          | Error err -> Response.error orig_id err
        in
        Immediate response
    | "shutdown" ->
        (* Handle shutdown request locally - don't forward to master
           server *)
        let response = Response.ok req.id `Null in
        Immediate response
    | _ ->
        let new_request = translate_request ~id_translator req in
        Lsp_utils.write_packet server_socket (Packet.Request new_request) ;
        Wait [new_request.id] )
  | Packet.Notification notification -> (
    match notification.method_ with
    | "exit" ->
        (* Handle exit notification locally - don't forward to master server
           and don't kill ranmaru *)
        Done
    | "initialized" ->
        if Kcas.Loc.compare_and_set initialized false true then
          Lsp_utils.write_packet server_socket packet
        else () ;
        Done
    | _ ->
        Lsp_utils.write_packet server_socket packet ;
        Done )
  | Packet.Batch_call calls ->
      let redirected_batch, unredirected_items =
        List.partition (fun x -> not (is_unredirected_batch_item x)) calls
      in
      let new_calls, ids =
        List.map
          (function
            | `Request r ->
                let new_request = translate_request ~id_translator r in
                (`Request new_request, Some new_request.id)
            | `Notification n -> (`Notification n, None) )
          redirected_batch
        |> List.split
      in
      (* Only forward non-shutdown/exit items to the server *)
      if new_calls <> [] then
        Lsp_utils.write_packet server_socket (Packet.Batch_call new_calls) ;
      (* Handle shutdown requests in the unredirected items locally *)
      let shutdown_responses =
        List.filter_map
          (function
            | `Request req when is_shutdown_request req ->
                Some (Response.ok req.id `Null)
            | _ -> None )
          unredirected_items
      in
      if shutdown_responses <> [] then
        (* Return immediate responses for shutdown requests *)
        match shutdown_responses with
        | [response] -> Immediate response
        | responses ->
            (* Multiple shutdown requests in batch - this is unusual but
               handle it *)
            Immediate (List.hd responses)
      else Wait (List.filter_map Fun.id ids)
  | Packet.Response _ -> failwith "Unexpected Response from a client"
  | Packet.Batch_response _ ->
      failwith "Unexpected Batch_response from a client"

let run_gateway ~sw ~net ~server_sockaddr ~incoming_channel ~client_registry
    =
  let open Eio in
  let id_translator = Id_translator.make () in
  let message = Stream.take incoming_channel in
  let client_map = Client_map.make () in
  (* This [server_socket] must be only accessed from [send_to_server]. *)
  let server_socket = Net.connect ~sw net server_sockaddr in
  let init = Initializer.make () in
  let respond = Client_registry.send client_registry in
  let initialized = Kcas.Loc.make false in
  let handle_client_message = function
    | Connect -> ()
    | Packet (packet, client_id) -> (
      match
        handle_client_packet ~server_socket ~id_translator ~initialized ~init
          packet
      with
      | Immediate response -> respond client_id (`Response response)
      | Wait ids -> List.iter (Client_map.add client_map client_id) ids
      | Done -> () )
  in
  let rec client_incoming_loop () =
    Stream.take incoming_channel |> handle_client_message ;
    Fiber.yield () ;
    client_incoming_loop ()
  in
  let open Jsonrpc.Response in
  let handle_response_packet = function
    | Jsonrpc.Packet.Response response -> (
        let id = response.id in
        match Client_map.take_opt client_map id with
        | Some client_id ->
            let original_id = Id_translator.untranslate id_translator id in
            Client_registry.send client_registry client_id
              (`Response {response with id= original_id})
        | None ->
            (* The corresponding request should be an initialization
               request *)
            Initializer.set init response.result )
    | Jsonrpc.Packet.Batch_response batch ->
        let client_ids =
          List.map
            (fun response -> Client_map.take client_map response.id)
            batch
        in
        let untranslated_batch =
          List.map
            (fun response ->
              let original_id =
                Id_translator.untranslate id_translator response.id
              in
              {response with id= original_id} )
            batch
        in
        Client_registry.send client_registry (List.hd client_ids)
          (`Batch_response untranslated_batch)
    | _ -> failwith "Unexpected packet type in response"
  in
  let response_stream = Stream.create 2 in
  let rec server_response_loop () =
    Stream.take response_stream |> handle_response_packet ;
    Fiber.yield () ;
    server_response_loop ()
  in
  Fiber.all
    [ server_response_loop
    ; (fun () ->
        handle_client_message message ;
        client_incoming_loop () )
    ; (fun () -> Lsp_utils.Reader.to_stream response_stream server_socket) ]

let run_proxy ~client_sockaddr ~server_sockaddr =
  let open Eio in
  Eio_main.run
  @@ fun env ->
  Switch.run (fun sw ->
      let net = Stdenv.net env in
      let incoming_channel = Stream.create 2 in
      let handle_error _exn = () in
      let client_registry = Client_registry.make () in
      let client_handler client_socket _addr =
        let client_id, stream = Client_registry.register client_registry in
        Fiber.both
          (fun () ->
            handle_client_incoming_messages ~incoming_channel ~client_socket
              ~client_id )
          (fun () -> handle_client_responses ~stream ~client_socket)
      in
      Fiber.all
        [ (fun () ->
            run_gateway ~sw ~net ~server_sockaddr ~incoming_channel
              ~client_registry )
        ; (fun () ->
            let client_socket =
              Net.listen ~reuse_addr:true ~sw ~backlog:2 net client_sockaddr
            in
            Net.run_server ~max_connections ~on_error:handle_error
              client_socket client_handler ) ] )
