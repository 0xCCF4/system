{ inputs
, self
, lib
, ...
}:
with lib;
{
  # Network diagram of the fleet, the hosts describe themselves in nixos/topology.nix
  # Build with: nix build '.?submodules=1#topology' (SVG and PNG)
  imports = [ inputs.nix-topology.flakeModule ];

  perSystem = { system, pkgs, ... }: {
    packages.topology = pkgs.runCommand "topology"
      {
        nativeBuildInputs = [ pkgs.librsvg ];
      } ''
      mkdir -p $out
      cp ${self.topology.${system}.config.output}/*.svg $out/
      for svg in $out/*.svg; do
        rsvg-convert --output "''${svg%.svg}.png" "$svg"
      done
    '';

    topology.modules = [
      ({ config, ... }:
        let
          inherit (config.lib.topology) mkInternet mkConnection;
        in
        {
          # the renderers put the addresses on one line, separate them
          options.nodes = mkOption {
            type = types.attrsOf (types.submodule {
              options.interfaces = mkOption {
                type = types.attrsOf (types.submodule {
                  config.addressFormatter = mkDefault (concatStringsSep " ");
                });
              };
            });
          };

          config.nodes.internet = mkInternet {
            connections = [ (mkConnection "lux" "wan") ];
          };
        })
    ];
  };
}
