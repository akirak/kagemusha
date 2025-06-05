open Cmdliner

let test_cmdline_parsing () =
  (* Test that the command accepts --client and --master options *)
  let argv =
    [| "ranmaru"
     ; "--client"
     ; "/tmp/client.sock"
     ; "--master"
     ; "/tmp/master.sock" |]
  in
  (* Create a simple test command that extracts the arguments *)
  let test_client_path = ref None in
  let test_master_path = ref None in
  let client_socket_path =
    let doc = "UNIX socket path to listen to" in
    let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_client_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["client"] ~env ~docv:"CLIENT" ~doc ) )
  in
  let server_socket_path =
    let doc = "UNIX socket path of the upstream server" in
    let env = Cmd.Env.info "RANMARU_MASTER_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_master_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["master"] ~env ~docv:"SERVER" ~doc ) )
  in
  let test_term =
    Term.(const (fun _ _ -> `Ok ()) $ client_socket_path $ server_socket_path)
  in
  let info = Cmd.info "ranmaru" ~doc:"test" in
  let cmd = Cmd.v info test_term in
  (* Parse the command line *)
  match Cmd.eval_value ~argv cmd with
  | Ok (`Ok _) ->
      Alcotest.(check (option string))
        "client path" (Some "/tmp/client.sock") !test_client_path ;
      Alcotest.(check (option string))
        "master path" (Some "/tmp/master.sock") !test_master_path
  | _ -> Alcotest.fail "Command line parsing failed"

let test_env_vars () =
  (* Test that environment variables work *)
  Unix.putenv "RANMARU_CLIENT_SOCKET" "/env/client.sock" ;
  Unix.putenv "RANMARU_MASTER_SOCKET" "/env/master.sock" ;
  let argv = [|"ranmaru"|] in
  let test_client_path = ref None in
  let test_master_path = ref None in
  let client_socket_path =
    let doc = "UNIX socket path to listen to" in
    let env = Cmd.Env.info "RANMARU_CLIENT_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_client_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["client"] ~env ~docv:"CLIENT" ~doc ) )
  in
  let server_socket_path =
    let doc = "UNIX socket path of the upstream server" in
    let env = Cmd.Env.info "RANMARU_MASTER_SOCKET" ~doc in
    Term.(
      const (fun path ->
          test_master_path := Some path ;
          `Unix path )
      $ Arg.(
          required
          & opt (some string) None
          & info ["master"] ~env ~docv:"SERVER" ~doc ) )
  in
  let test_term =
    Term.(const (fun _ _ -> `Ok ()) $ client_socket_path $ server_socket_path)
  in
  let info = Cmd.info "ranmaru" ~doc:"test" in
  let cmd = Cmd.v info test_term in
  match Cmd.eval_value ~argv cmd with
  | Ok (`Ok _) ->
      Alcotest.(check (option string))
        "client env path" (Some "/env/client.sock") !test_client_path ;
      Alcotest.(check (option string))
        "master env path" (Some "/env/master.sock") !test_master_path
  | _ -> Alcotest.fail "Environment variable test failed"

let () =
  let open Alcotest in
  run "Ranmaru Command Line"
    [ ( "cmdline"
      , [ test_case "Command line parsing" `Quick test_cmdline_parsing
        ; test_case "Environment variables" `Quick test_env_vars ] ) ]
