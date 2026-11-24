{
  description = "roblox-lobby: a reusable lobby and teleport package for Roblox games";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        version = pkgs.lib.removeSuffix "\n" (builtins.readFile ./VERSION);
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./src
            ./scripts
            ./tests
            ./examples
            ./docs
            ./skills
            ./default.project.json
            ./selene.toml
            ./roblox-lobby.yml
            ./roblox.yml
            ./stylua.toml
            ./wally.toml
            ./VERSION
            ./LICENSE
            ./README.md
          ];
        };
        tools = [ pkgs.rojo pkgs.lune pkgs.selene pkgs.stylua ];
      in
      {
        # share/roblox-lobby: src/ (the package to vendor), RobloxLobby.rbxm, docs/, skills/, scripts/;
        # bin/roblox-lobby: `vendor` and `check` (see scripts/roblox-lobby).
        packages.default = pkgs.stdenvNoCC.mkDerivation {
          pname = "roblox-lobby";
          inherit version src;
          nativeBuildInputs = [ pkgs.rojo pkgs.makeWrapper ];
          buildPhase = ''
            rojo build default.project.json -o RobloxLobby.rbxm
          '';
          installPhase = ''
            share=$out/share/roblox-lobby
            mkdir -p $share $out/bin
            cp -r src scripts docs skills examples VERSION LICENSE README.md default.project.json wally.toml RobloxLobby.rbxm $share/
            makeWrapper $share/scripts/roblox-lobby $out/bin/roblox-lobby \
              --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.lune pkgs.coreutils pkgs.diffutils ]}
          '';
          meta.license = pkgs.lib.licenses.mit;
        };

        # nix flake check: unit tests, lint, format and the Rojo build test, all offline
        checks.default = pkgs.runCommand "roblox-lobby-checks" { nativeBuildInputs = tools; } ''
          cp -r ${src} work && chmod -R u+w work && cd work
          lune run tests
          stylua --check src tests scripts examples
          selene src
          lune run scripts/build-check
          touch $out
        '';

        devShells.default = pkgs.mkShell {
          buildInputs = tools ++ [ pkgs.wally ];
        };
      }
    );
}
