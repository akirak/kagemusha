(lang dune 3.18)

(generate_opam_files true)

(package
 (name ranmaru)
 (allow_empty)
 (depends
  (ocaml (>= 5.2))
  (dune (>= 3.16))
  eio
  eio_main
  jsonrpc
  lsp
  kcas
  kcas_data
  cmdliner
  yojson
  (alcotest :with-test)))
