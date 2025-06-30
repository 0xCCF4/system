{ pkgs, ... }:
let
  agenix = pkgs.writeShellApplication {
    name = "agenix";
    text = ''
      exec ${pkgs.agenix-rekey}/bin/agenix --extra-flake-params "?submodules=1" "$@"
    '';
  };
in
pkgs.mkShell {
  packages = with pkgs; [ agenix rage deploy-rs ];
}
