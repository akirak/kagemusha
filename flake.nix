{
  inputs = {
    nixpkgs.url = "github:nix-ocaml/nix-overlays";
  };

  outputs =
    {
      nixpkgs,
      self,
      ...
    }:
    let
      eachSystem =
        f:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system:
          f (
            nixpkgs.legacyPackages.${system}.extend (
              _self: super: {
                # You can set the OCaml version to a particular release. Also, you
                # may have to pin some packages to a particular revision if the
                # devshell fail to build. This should be resolved in the upstream.
                ocamlPackages = super.ocaml-ng.ocamlPackages_latest;
              }
            )
          )
        );
    in
    {
      packages = eachSystem (pkgs: {
        kagemusha = pkgs.ocamlPackages.buildDunePackage {
          pname = "kagemusha";
          version = "0";
          duneVersion = "3";
          src = ./.;
          buildInputs = [ pkgs.ocamlPackages.ocaml-syntax-shims ];
          propagatedBuildInputs = with pkgs.ocamlPackages; [
            eio
            eio_main
            jsonrpc
            cmdliner
            yojson
          ];
        };

        ranmaru = pkgs.ocamlPackages.buildDunePackage {
          pname = "ranmaru";
          version = "0";
          duneVersion = "3";
          src = ./.;
          buildInputs = [ pkgs.ocamlPackages.ocaml-syntax-shims ];
          propagatedBuildInputs = with pkgs.ocamlPackages; [
            eio
            eio_main
            jsonrpc
            lsp
            kcas
            kcas_data
            cmdliner
            yojson
          ];
        };
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          inputsFrom = with self.packages.${pkgs.system}; [
            kagemusha
            ranmaru
          ];
          packages = (
            with pkgs.ocamlPackages;
            [
              ocaml-lsp
              ocamlformat
              ocp-indent
              utop
            ]
          );
        };
      });

      checks = eachSystem (pkgs: {
        inherit (self.packages.${pkgs.system}) kagemusha ranmaru;
      });
    };
}
