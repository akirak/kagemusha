open Cmdliner

let to_unix path = `Unix path

let client_socket_path =
  let doc = "UNIX socket path to listen to" in
  let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
  Term.(
    const to_unix
    $ Arg.(required & opt (some string) None & info ["client"] ~env ~docv:"CLIENT" ~doc) )

let server_socket_path =
  let doc = "UNIX socket path of the upstream server" in
  let env = Cmd.Env.info "RANMARU_MASTER_SOCKET" ~doc in
  Term.(
    const to_unix
    $ Arg.(
        required
        & opt (some non_dir_file) None
        & info ["master"] ~env ~docv:"SERVER" ~doc ) )

let () =
  Printexc.record_backtrace true ;
  let doc =
    "LSP proxy that handles shutdown/exit and manages multiple clients"
  in
  let info = Cmd.info "ranmaru" ~doc in
  let f client_sockaddr server_sockaddr =
    Ranmaru.run_proxy ~client_sockaddr ~server_sockaddr
  in
  let cmd =
    Cmd.v info Term.(const f $ client_socket_path $ server_socket_path)
  in
  exit (Cmd.eval cmd)
