{ pkgs, lib, ... }:
pkgs.rustPlatform.buildRustPackage rec {
  pname = "binary-wallpapers";
  version = "0.1";
  cargoLock.lockFile = ./Cargo.lock;
  src = pkgs.lib.cleanSource ./.;
}
