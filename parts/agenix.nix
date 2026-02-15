{ inputs, lib, self, ... }: with lib; with builtins;
{
  perSystem = { pkgs, system, self', ... }: {
    packages.agenix-rekey = inputs.agenix-rekey.packages."${system}".default;
    packages.agenix-rekey-sub = pkgs.writeShellApplication {
      name = "agenix-rekey-sub";
      text = ''
        exec ${getExe self'.packages.agenix-rekey} --extra-flake-params "?submodules=1" "$@"
      '';
    };
  };
}
