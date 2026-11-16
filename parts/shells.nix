{ inputs
, lib
, self
, ...
}:
with lib;
{
  perSystem = { pkgs, system, ... }: {
    devShells.default = pkgs.mkShell {
      packages = with pkgs; [
        inputs.agenix-rekey.packages.${system}.default
        #inputs.deploy-rs.packages.${system}.default
        git
        rage
        python3 # pkgs/privacy-check
      ];
      # the pre-commit privacy check (git-hooks/pre-commit)
      shellHook = ''
        if git rev-parse --show-toplevel > /dev/null 2>&1; then
          git config core.hooksPath git-hooks
        fi
      '';
    };
  };
}
