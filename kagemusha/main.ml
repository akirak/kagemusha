open Cmdliner

let to_unix path = `Unix path

let server_socket_path =
  let doc = "UNIX socket path of the upstream server" in
  Term.(
    const to_unix
    $ Arg.(required & pos 0 (some non_dir_file) None & info [] ~doc) )

let () =
  let doc = "Connect to a UNIX socket" in
  let info = Cmd.info "kagemusha" ~doc in
  let cmd =
    Cmd.v info Term.(const Kagemusha.run_proxy $ server_socket_path)
  in
  Printexc.record_backtrace true ;
  exit (Cmd.eval cmd)
