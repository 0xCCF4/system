{ inputs, lib, self, ... }: with lib; with builtins;
{
  perSystem = { pkgs, system, self', ... }: {
    packages.binary-wallpapers = pkgs.rustPlatform.buildRustPackage rec {
      pname = "binary-wallpapers";
      version = "0.1";
      cargoLock.lockFile = ./Cargo.lock;
      src = pkgs.lib.cleanSource ./.;

      meta.mainProgram = "binary-wallpapers";
    };
  };
}
