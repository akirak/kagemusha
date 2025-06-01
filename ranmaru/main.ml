open Cmdliner

let to_unix path = `Unix path

let client_socket_path =
  let doc = "UNIX socket path to listen to" in
  Term.(
    const to_unix
    $ Arg.(required & pos 0 (some string) None & info [] ~docv:"CLIENT" ~doc) )

let server_socket_path =
  let doc = "UNIX socket path of the upstream server" in
  Term.(
    const to_unix
    $ Arg.(
        required
        & pos 1 (some non_dir_file) None
        & info [] ~docv:"SERVER" ~doc ) )

let () =
  Printexc.record_backtrace true ;
  let doc = "Maintain connections to a LSP socket" in
  let info = Cmd.info "ranmaru" ~doc in
  let f client_sockaddr server_sockaddr =
    Ranmaru.run_proxy ~client_sockaddr ~server_sockaddr
  in
  let cmd =
    Cmd.v info Term.(const f $ client_socket_path $ server_socket_path)
  in
  exit (Cmd.eval cmd)
